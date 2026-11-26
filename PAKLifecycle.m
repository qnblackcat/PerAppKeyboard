#import <UIKit/UIKit.h>
#import <notify.h>
#import "PAKLifecycle.h"
#import "PAKSwitcher.h"
#import "PAKPrefs.h"
#import "PAKLog.h"

#pragma mark - State

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
static UIBackgroundTaskIdentifier gDecideTask;   // UIBackgroundTaskInvalid when none (set in PAKLifecycleStart)
// Bumped each time a departure waits for the lock signals, so the delayed decision of an earlier
// one can't settle a later one.
static NSUInteger gDepartureGen;

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

#pragma mark - Observers

void PAKLifecycleStart(void) {
	gDecideTask = UIBackgroundTaskInvalid;
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
		PAKLog(@"will resign active, reasons=[%@] locked=%d", PAKDeactivationReasons(), PAKDeviceLocked());
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
		NSUInteger generation = ++gDepartureGen;
		dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
			if (generation == gDepartureGen) PAKDecideDeparture(@"delay");
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
}
