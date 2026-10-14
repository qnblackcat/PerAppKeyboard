// PerAppKeyboard
//
// Each app the user set up in Settings starts on its own keyboard every time its keyboard is
// brought up. The user can still switch with the globe key while typing; what happens to that
// pick (reset, or kept) when the keyboard is hidden or the app is left is up to the settings.
//
// Everything runs in the app process (UIKitCore): UIKeyboardImpl picks the input mode when a
// text input becomes first responder, and iOS resets it at several other moments (field
// changes, resuming the app), so we put it back right after each of those.

#import <UIKit/UIKit.h>
#import <notify.h>
#import "PAKPrefs.h"
#import "PAKKeyboards.h"

#pragma mark - Debug logging

// 1 = log the lifecycle events, every keyboard switch and why the app went inactive:
//   log stream --predicate 'eventMessage CONTAINS "PerAppKeyboard"' --level debug
// Everything under PAK_DEBUG is compiled out of release builds.
#define PAK_DEBUG 0

#if PAK_DEBUG
#import <os/log.h>

static unsigned long gLogSeq;   // numbered, so lines Console drops show up as gaps
#define PAKLog(fmt, ...) os_log(OS_LOG_DEFAULT, "[PerAppKeyboard #%lu] %{public}@", ++gLogSeq, [NSString stringWithFormat:(fmt), ##__VA_ARGS__])

static NSString *PAKModeIdentifiers(NSArray *raw) {
	NSMutableArray *ids = [NSMutableArray array];
	for (id item in raw ?: @[]) {
		if ([item isKindOfClass:NSString.class]) [ids addObject:item];
		else if ([item respondsToSelector:@selector(identifier)]) [ids addObject:[item identifier] ?: @"?"];
		else [ids addObject:NSStringFromClass([item class])];
	}
	return ids.count ? [ids componentsJoinedByString:@", "] : @"(none)";
}
#else
#define PAKLog(...) do {} while (0)
#endif

#pragma mark - Private UIKitCore interfaces (iOS 17.1 headers; input modes are in PAKKeyboards.h)

@interface UIKeyboardImpl : UIView
+ (instancetype)activeInstance;
@property (nonatomic, readonly) id textInputTraits;
- (BOOL)hardwareKeyboardAttached;
- (void)setKeyboardInputMode:(UIKeyboardInputMode *)mode userInitiated:(BOOL)userInitiated;
@end

#pragma mark - State

static NSString *gBundleID;
static BOOL gApplying;             // re-entrancy guard
static BOOL gTimerDisabled;        // see PAKDisableLastUsedTimer
// YES from the moment the keyboard is (re)presented until the user picks a keyboard themselves.
// While YES, every time iOS (re)sets the input mode we put it back on the app's keyboard.
// Set on launch, keyboard hide, background and foreground; cleared by a user-initiated switch.
// No timers: iOS resets the mode at unpredictable moments around show/resume.
static BOOL gPendingReset = YES;
// What the user picked with the globe key since the last reset (an input mode identifier). While
// no reset is pending it is put back whenever iOS resets the mode (iOS falls back to its own
// default every time a keyboard is presented, since we stopped it remembering the last one).
static NSString *gUserMode;
// The app left the screen in a way the user wants to reset the keyboard for (Home / another
// app, power button lock, per the settings) and hasn't come back yet. Going inactive in any
// other way (Control Center, lock screen pull-down, app switcher and back...) never resets:
// those look alike to the app (deactivationReasons is systemAnimation for both of the last two).
static BOOL gLeftApp;
// The device was locked with the power button since the app was last active. `lockstate` is only
// a snapshot, read when the app reaches the background, and that can be too early (it hasn't
// flipped yet) or never happen (the app may not reach the background while locking). So the lock
// is also noticed on the way there (WillResignActive, ProtectedDataWillBecomeUnavailable) and
// acted on at the latest when the app becomes active again.
static BOOL gLockSeen;
// iOS 15 / 16 only: the departure (lock or not) hasn't been decided yet, see PAKDecideDeparture.
static BOOL gDeparturePending;
static UIBackgroundTaskIdentifier gDecideTask;   // UIBackgroundTaskInvalid when none (set in the %ctor)

#pragma mark - Settings

static BOOL PAKPrefBool(NSString *key, BOOL fallback) {
	id value = PAKPrefsLoad()[key];
	return value ? [value boolValue] : fallback;
}

// "Last used in this app" lives in the app's own defaults: we can't write our jbroot plist from
// inside a sandboxed app, but an app can always write its own.
static NSString *const kPAKLastKeyboardKey = @"com.qn.perappkeyboard.lastKeyboard";

static BOOL PAKAppUsesLastKeyboard(void) {
	return [PAKPrefsKeyboardForBundle(gBundleID) isEqualToString:PAK_KEYBOARD_LAST];
}

// Back to the app's starting keyboard: its fixed one, or for "last used" apps the pick the user
// made last time (nothing to restore until they've made one).
static void PAKRequestReset(void) {
	if (PAKAppUsesLastKeyboard()) {
		gPendingReset = NO;
		gUserMode = [NSUserDefaults.standardUserDefaults stringForKey:kPAKLastKeyboardKey];
		return;
	}
	gPendingReset = YES;
	gUserMode = nil;
}

#pragma mark - Switching

// Don't force a keyboard onto fields where it makes no sense (passwords, numbers, URLs...).
static BOOL PAKTraitsAllowSwitch(UIKeyboardImpl *impl) {
	id<UITextInputTraits> traits = (id<UITextInputTraits>)impl.textInputTraits;
	if (!traits) return YES;
	if ([traits respondsToSelector:@selector(isSecureTextEntry)] && traits.isSecureTextEntry) return NO;
	if ([traits respondsToSelector:@selector(keyboardType)]) {
		// Deny-list instead of allow-list: apps use private types for plain text (Messages'
		// compose field reports 126), so only skip the types that are clearly not free text.
		switch (traits.keyboardType) {
			case UIKeyboardTypeNumbersAndPunctuation:
			case UIKeyboardTypeURL:
			case UIKeyboardTypeNumberPad:
			case UIKeyboardTypePhonePad:
			case UIKeyboardTypeNamePhonePad:
			case UIKeyboardTypeEmailAddress:
			case UIKeyboardTypeDecimalPad:
			case UIKeyboardTypeASCIICapableNumberPad:
				return NO;
			default:
				break;
		}
	}
	return YES;
}

// While we manage an app, what the user picks there must not become the system-wide "last used"
// keyboard, otherwise other apps would start on it. The master switch off gives it back.
static void PAKDisableLastUsedTimer(UIKeyboardInputModeController *controller, BOOL disable) {
	if (gTimerDisabled == disable) return;
	if ([controller respondsToSelector:@selector(setDisablesUpdateLastUsedInputModeTimer:)]) {
		[controller setDisablesUpdateLastUsedInputModeTimer:disable];
	}
	gTimerDisabled = disable;
}

static void PAKApply(UIKeyboardImpl *impl, NSString *source) {
	// Re-read every time: removing the app, or choosing another keyboard for it, applies at once.
	// (Adding an app applies the next time it launches, see the %ctor.)
	NSString *keyboard = PAKPrefsKeyboardForBundle(gBundleID);
	if (!keyboard) return;
	// "Last used" has no default to reset to; the settings may also have just been switched to it.
	if ([keyboard isEqualToString:PAK_KEYBOARD_LAST] && gPendingReset) PAKRequestReset();

	if (!PAKPrefBool(PAK_ENABLED, YES)) {
		// Master switch off: behave like stock iOS.
		if (gTimerDisabled) PAKDisableLastUsedTimer([UIKeyboardInputModeController sharedInputModeController], NO);
		return;
	}
	if (gApplying) return;

	impl = impl ?: [UIKeyboardImpl activeInstance];
	if (!impl || [impl hardwareKeyboardAttached] || !PAKTraitsAllowSwitch(impl)) return;

	UIKeyboardInputModeController *controller = [UIKeyboardInputModeController sharedInputModeController];
	if (!controller) return;
	PAKDisableLastUsedTimer(controller, YES);

	// Reset pending: the app's keyboard. Otherwise whatever the user picked, if anything.
	NSString *wanted = gPendingReset ? keyboard : gUserMode;
	if (!wanted) return;
	UIKeyboardInputMode *target = PAKResolveMode(controller, wanted);
	UIKeyboardInputMode *current = controller.currentInputMode;
	if (!target) {
		PAKLog(@"[%@] no keyboard matching '%@' (active: [%@], enabled: [%@])", source, wanted,
			   PAKModeIdentifiers(controller.activeInputModes), PAKModeIdentifiers(controller.enabledInputModes));
		return;
	}
	if ([current.identifier isEqualToString:target.identifier]) return;

	gApplying = YES;
	if ([impl respondsToSelector:@selector(setKeyboardInputMode:userInitiated:)]) {
		[impl setKeyboardInputMode:target userInitiated:NO];
	} else {
		[controller setCurrentInputMode:target];
	}
	gApplying = NO;
	PAKLog(@"[%@] %@ -> %@ (now: %@)", source, current.identifier, target.identifier, controller.currentInputMode.identifier);
}

static void PAKResetAndApply(NSString *source) {
	PAKRequestReset();
	PAKApply(nil, source);
}

#pragma mark - Is the device locked?

static BOOL PAKDeviceLocked(void) {
	static int token = NOTIFY_TOKEN_INVALID;
	if (token == NOTIFY_TOKEN_INVALID && notify_register_check("com.apple.springboard.lockstate", &token) != NOTIFY_STATUS_OK) return NO;
	uint64_t state = 0;
	notify_get_state(token, &state);
	return state != 0;
}

// iOS 17 has `lockstate` set by the time the app reaches the background. On iOS 15 / 16 it flips
// (and ProtectedDataWillBecomeUnavailable arrives) up to half a second later, so a lock would be
// taken for "Home". There the decision waits for it.
static BOOL PAKLockSignalLags(void) {
	return ![NSProcessInfo.processInfo isOperatingSystemAtLeastVersion:(NSOperatingSystemVersion){17, 0, 0}];
}

// What kind of departure was it? Lock (power button) or leaving the app (Home / another app); the
// matching setting says whether the keyboard goes back to the app's. Runs once per departure.
static void PAKDecideDeparture(NSString *source) {
	if (!gDeparturePending) return;
	gDeparturePending = NO;
	if (gDecideTask != UIBackgroundTaskInvalid) {
		[UIApplication.sharedApplication endBackgroundTask:gDecideTask];
		gDecideTask = UIBackgroundTaskInvalid;
	}
	BOOL locked = gLockSeen || PAKDeviceLocked();
	gLeftApp = locked ? PAKPrefBool(PAK_RESET_ON_LOCK, NO) : PAKPrefBool(PAK_RESET_ON_LEAVE_APP, YES);
	PAKLog(@"departure decided (%@): locked=%d -> %@", source, locked, gLeftApp ? @"reset" : @"keep keyboard");
	if (gLeftApp) PAKResetAndApply(@"background");
}

#if PAK_DEBUG
// The scene settings carry the reason the app lost focus: "systemAnimation" (app switcher,
// going Home, lock screen pull-down), "controlCenter", "notificationCenter". There is no public
// notification for it, so read it from the FBSScene. Empty if unavailable.
static NSString *PAKDeactivationReasons(void) {
	static NSRegularExpression *regex;
	static dispatch_once_t once;
	dispatch_once(&once, ^{ regex = [NSRegularExpression regularExpressionWithPattern:@"deactivationReasons = ([^;\\n]*);" options:0 error:nil]; });
	for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
		@try {
			NSString *desc = [[[scene valueForKey:@"_FBSScene"] valueForKey:@"settings"] description];
			NSTextCheckingResult *m = desc.length ? [regex firstMatchInString:desc options:0 range:NSMakeRange(0, desc.length)] : nil;
			if (m) return [desc substringWithRange:[m rangeAtIndex:1]];
		} @catch (NSException *e) {}
	}
	return @"";
}
#endif

#pragma mark - Hooks

%hook UIKeyboardImpl

// Where UIKeyboardImpl restores the remembered keyboard when a text input is attached.
- (void)setInputModeFromPreferences {
	%orig;
	PAKApply(self, @"setInputModeFromPreferences");
}

// Fallback in case the system picks the mode after the call above.
- (void)didSetDelegate {
	%orig;
	__weak UIKeyboardImpl *weakSelf = self;
	dispatch_async(dispatch_get_main_queue(), ^{ PAKApply(weakSelf, @"didSetDelegate"); });
}

// Every input mode change funnels through here; a user-initiated one (globe key / long press
// menu) means "stop overriding until the next reset".
- (void)_setKeyboardInputMode:(id)mode userInitiated:(BOOL)userInitiated updateIndicator:(BOOL)updateIndicator force:(BOOL)force executionContext:(id)context {
	if (userInitiated && !gApplying && [mode respondsToSelector:@selector(identifier)]) {
		gPendingReset = NO;
		gUserMode = [[(UIKeyboardInputMode *)mode identifier] copy];
		if (PAKAppUsesLastKeyboard()) [NSUserDefaults.standardUserDefaults setObject:gUserMode forKey:kPAKLastKeyboardKey];
		PAKLog(@"user switched keyboard to %@ -> keep it until the next reset", gUserMode);
	}
	%orig;
}

%end

%ctor {
	@autoreleasepool {
		// Loaded into every UIKit process (see the .plist filter); do nothing unless the user
		// set this app up in Settings.
		gBundleID = NSBundle.mainBundle.bundleIdentifier;
		gDecideTask = UIBackgroundTaskInvalid;
		if (!PAKPrefsKeyboardForBundle(gBundleID)) return;
		if (PAKAppUsesLastKeyboard()) PAKRequestReset();   // start on the last pick right away
		PAKLog(@"loaded in %@, keyboard '%@', settings %@ (%@): enabled=%d hide=%d leaveApp=%d lock=%d",
			   gBundleID, PAKPrefsKeyboardForBundle(gBundleID), PAKPrefsPath(), PAKPrefsLoad().count ? @"found" : @"missing, using defaults",
			   PAKPrefBool(PAK_ENABLED, YES), PAKPrefBool(PAK_RESET_ON_KEYBOARD_HIDE, YES),
			   PAKPrefBool(PAK_RESET_ON_LEAVE_APP, YES), PAKPrefBool(PAK_RESET_ON_LOCK, NO));

		NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
		NSOperationQueue *main = NSOperationQueue.mainQueue;
		[center addObserverForName:UIKeyboardDidHideNotification object:nil queue:main usingBlock:^(NSNotification *n) {
			// With "Hiding the keyboard" off, what the user picked survives hide / show.
			BOOL reset = PAKPrefBool(PAK_RESET_ON_KEYBOARD_HIDE, YES);
			if (reset) PAKRequestReset();
			PAKLog(@"UIKeyboardDidHide -> %@", reset ? @"will reset on next show" : @"keep the user's keyboard");
		}];
		[center addObserverForName:UIApplicationWillResignActiveNotification object:nil queue:main usingBlock:^(NSNotification *n) {
			if (PAKDeviceLocked()) gLockSeen = YES;
#if PAK_DEBUG
			PAKLog(@"will resign active, reasons=[%@] locked=%d", PAKDeactivationReasons(), PAKDeviceLocked());
#endif
		}];
		[center addObserverForName:UIApplicationProtectedDataWillBecomeUnavailable object:nil queue:main usingBlock:^(NSNotification *n) {
			gLockSeen = YES;   // posted when the device locks (needs a passcode)
			PAKLog(@"protected data will become unavailable");
		}];
		// Leaving the app counts as dismissing the keyboard even though iOS doesn't post DidHide
		// and brings the same keyboard back on return. Reset when it goes to the background (so
		// nothing flashes on return) and again on the way back in, for the departures the user
		// enabled.
		[center addObserverForName:UIApplicationDidEnterBackgroundNotification object:nil queue:main usingBlock:^(NSNotification *n) {
			gDeparturePending = YES;
			PAKLog(@"entered background, locked=%d lockSeen=%d lags=%d", PAKDeviceLocked(), gLockSeen, PAKLockSignalLags());
			if (!PAKLockSignalLags() || gLockSeen || PAKDeviceLocked()) {
				PAKDecideDeparture(@"background");
				return;
			}
			// Give the lock signals a moment: stay alive for it (a short background task) unless the
			// user is back sooner, in which case WillEnterForeground / DidBecomeActive decide.
			gDecideTask = [UIApplication.sharedApplication beginBackgroundTaskWithName:@"PerAppKeyboard" expirationHandler:^{
				PAKDecideDeparture(@"task expired");
			}];
			dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
				PAKDecideDeparture(@"delay");
			});
		}];
		[center addObserverForName:UIApplicationWillEnterForegroundNotification object:nil queue:main usingBlock:^(NSNotification *n) {
			PAKDecideDeparture(@"foreground");
			PAKLog(@"will enter foreground, reset=%d", gLeftApp);
			if (gLeftApp) PAKResetAndApply(@"foreground");
		}];
		[center addObserverForName:UIApplicationDidBecomeActiveNotification object:nil queue:main usingBlock:^(NSNotification *n) {
			PAKDecideDeparture(@"active");
			PAKLog(@"did become active, reset=%d lockSeen=%d", gLeftApp, gLockSeen);
			// The lock was only noticed after the departure was decided (or the app never reached
			// the background): the lock setting has the last word.
			if (gLockSeen) gLeftApp = PAKPrefBool(PAK_RESET_ON_LOCK, NO);
			gLockSeen = NO;
			if (!gLeftApp) return;
			gLeftApp = NO;
			PAKResetAndApply(@"becomeActive");
			// iOS may reset the mode once more while it restores the keyboard.
			dispatch_async(dispatch_get_main_queue(), ^{ PAKApply(nil, @"becomeActive+1"); });
		}];

		%init;
	}
}
