#import <UIKit/UIKit.h>
#import "PAKKeyboards.h"

// What the hooked class answers to. iOS 15 - 17 do the work in UIKeyboardImpl; on iOS 18 it only
// forwards to _UIKeyboardStateManager, which keeps the same selectors.
@protocol PAKKeyboardHost
@property (nonatomic, readonly) id textInputTraits;
- (BOOL)hardwareKeyboardAttached;
- (void)setKeyboardInputMode:(UIKeyboardInputMode *)mode userInitiated:(BOOL)userInitiated;
@end

@interface UIKeyboardImpl : UIView <PAKKeyboardHost>
+ (instancetype)activeInstance;
@end

@interface _UIKeyboardStateManager : NSObject <PAKKeyboardHost>
@end

// The part of the tweak that decides which keyboard an app gets and puts it there: state, the
// per-app settings lookup and the switch itself. Everything runs in the app process.

// Looks the app up in the settings; NO (and nothing to do) if the user hasn't set it up.
BOOL PAKSwitcherSetUp(void);

BOOL PAKPrefBool(NSString *key, BOOL fallback);

// Back to the app's starting keyboard (applied by the next PAKApply).
void PAKRequestReset(void);
// Put the wanted keyboard on `host` (nil: the active keyboard). `source` is only for the log.
void PAKApply(id<PAKKeyboardHost> host, NSString *source);
void PAKResetAndApply(NSString *source);

// The hook bodies, shared by the iOS 15 - 17 and iOS 18 hook groups.
void PAKHandleInputModeFromPreferences(id<PAKKeyboardHost> host);
void PAKHandleDelegateSet(id<PAKKeyboardHost> host);
void PAKHandleModeSet(id mode, BOOL userInitiated);
