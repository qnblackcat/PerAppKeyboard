#import "PAKSwitcher.h"
#import "PAKPrefs.h"
#import "PAKLog.h"

static NSString *PAKModeIdentifiers(NSArray *raw) {
	NSMutableArray *ids = [NSMutableArray array];
	for (id item in raw ?: @[]) {
		if ([item isKindOfClass:NSString.class]) [ids addObject:item];
		else if ([item respondsToSelector:@selector(identifier)]) [ids addObject:[item identifier] ?: @"?"];
		else [ids addObject:NSStringFromClass([item class])];
	}
	return ids.count ? [ids componentsJoinedByString:@", "] : @"(none)";
}

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

#pragma mark - Settings

BOOL PAKPrefBool(NSString *key, BOOL fallback) {
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
void PAKRequestReset(void) {
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
static BOOL PAKTraitsAllowSwitch(id<PAKKeyboardHost> impl) {
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
	[controller setDisablesUpdateLastUsedInputModeTimer:disable];
	gTimerDisabled = disable;
}

void PAKApply(id<PAKKeyboardHost> impl, NSString *source) {
	// Looked up every time (PAKPrefsLoad only re-parses a changed file): removing the app, or
	// choosing another keyboard for it, applies at once.
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
	[impl setKeyboardInputMode:target userInitiated:NO];
	gApplying = NO;
	PAKLog(@"[%@] %@ -> %@ (now: %@)", source, current.identifier, target.identifier, controller.currentInputMode.identifier);
}

void PAKResetAndApply(NSString *source) {
	PAKRequestReset();
	PAKApply(nil, source);
}

BOOL PAKSwitcherSetUp(void) {
	gBundleID = NSBundle.mainBundle.bundleIdentifier;
	if (!PAKPrefsKeyboardForBundle(gBundleID)) return NO;
	if (PAKAppUsesLastKeyboard()) PAKRequestReset();   // start on the last pick right away
	return YES;
}

#pragma mark - Hook bodies

// Where the keyboard restores the remembered mode when a text input is attached.
void PAKHandleInputModeFromPreferences(id<PAKKeyboardHost> host) {
	PAKApply(host, @"setInputModeFromPreferences");
}

// Fallback in case the system picks the mode after the call above.
void PAKHandleDelegateSet(id<PAKKeyboardHost> host) {
	__weak id<PAKKeyboardHost> weakHost = host;
	dispatch_async(dispatch_get_main_queue(), ^{ PAKApply(weakHost, @"didSetDelegate"); });
}

// Every input mode change funnels through here; a user-initiated one (globe key / long press
// menu) means "stop overriding until the next reset".
void PAKHandleModeSet(id mode, BOOL userInitiated) {
	if (userInitiated && !gApplying && [mode respondsToSelector:@selector(identifier)]) {
		gPendingReset = NO;
		gUserMode = [[(UIKeyboardInputMode *)mode identifier] copy];
		if (PAKAppUsesLastKeyboard()) [NSUserDefaults.standardUserDefaults setObject:gUserMode forKey:kPAKLastKeyboardKey];
		PAKLog(@"user switched keyboard to %@ -> keep it until the next reset", gUserMode);
	}
}
