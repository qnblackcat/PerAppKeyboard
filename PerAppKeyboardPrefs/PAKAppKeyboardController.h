#import <Preferences/PSListController.h>

// One app's page: "System default" plus every iOS keyboard the user has enabled, with a
// checkmark on the one the app starts on. Opened from the app list (AltList sets the
// specifier's `applicationIdentifier`).
@interface PAKAppKeyboardController : PSListController
@end
