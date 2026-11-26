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
#import "PAKSwitcher.h"
#import "PAKLifecycle.h"
#import "PAKLog.h"

// iOS 15 - 17
%group Legacy

%hook UIKeyboardImpl

- (void)setInputModeFromPreferences {
	%orig;
	PAKHandleInputModeFromPreferences(self);
}

- (void)didSetDelegate {
	%orig;
	PAKHandleDelegateSet(self);
}

- (void)_setKeyboardInputMode:(id)mode userInitiated:(BOOL)userInitiated updateIndicator:(BOOL)updateIndicator force:(BOOL)force executionContext:(id)context {
	PAKHandleModeSet(mode, userInitiated);
	%orig;
}

%end

%end

// iOS 18: UIKeyboardImpl only forwards to _UIKeyboardStateManager, so hook that one.
%group iOS18

%hook _UIKeyboardStateManager

- (void)setInputModeFromPreferences {
	%orig;
	PAKHandleInputModeFromPreferences(self);
}

- (void)didSetDelegate {
	%orig;
	PAKHandleDelegateSet(self);
}

- (void)_setKeyboardInputMode:(id)mode userInitiated:(BOOL)userInitiated updateIndicator:(BOOL)updateIndicator force:(BOOL)force executionContext:(id)context {
	PAKHandleModeSet(mode, userInitiated);
	%orig;
}

%end

%end

%ctor {
	@autoreleasepool {
		// Loaded into every UIKit process (see the .plist filter); do nothing unless the user
		// set this app up in Settings.
		if (!PAKSwitcherSetUp()) return;
		NSString *bundleID = NSBundle.mainBundle.bundleIdentifier;
		PAKLog(@"loaded in %@, keyboard '%@', settings %@ (%@): enabled=%d hide=%d leaveApp=%d lock=%d",
			   bundleID, PAKPrefsKeyboardForBundle(bundleID), PAKPrefsPath(), PAKPrefsLoad().count ? @"found" : @"missing, using defaults",
			   PAKPrefBool(PAK_ENABLED, YES), PAKPrefBool(PAK_RESET_ON_KEYBOARD_HIDE, YES),
			   PAKPrefBool(PAK_RESET_ON_LEAVE_APP, YES), PAKPrefBool(PAK_RESET_ON_LOCK, NO));
		PAKLifecycleStart();

		if (@available(iOS 18, *)) {
			%init(iOS18);
		} else {
			%init(Legacy);
		}
	}
}
