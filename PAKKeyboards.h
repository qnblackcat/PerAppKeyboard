#import <UIKit/UIKit.h>
#import "PAKPrefs.h"

// Private UIKitCore (iOS 17.1 headers) + lookups shared by the tweak and the Settings bundle.

@interface UIKeyboardInputMode : UITextInputMode
@property (nonatomic, readonly) NSString *identifier;
@property (nonatomic, readonly) NSString *displayName;
@property (nonatomic, readonly) NSString *extendedDisplayName;
@property (nonatomic, readonly) BOOL isEmojiInputMode;
@property (nonatomic, readonly) BOOL isExtensionInputMode;
@property (nonatomic, readonly) BOOL isHandwritingInputMode;
@end

@interface UIKeyboardInputModeController : NSObject
+ (instancetype)sharedInputModeController;
- (UIKeyboardInputMode *)currentInputMode;
- (void)setCurrentInputMode:(UIKeyboardInputMode *)mode;
- (NSArray *)activeInputModes;
- (NSArray *)enabledInputModes;   // NSString identifiers or modes, depending on the process
- (UIKeyboardInputMode *)inputModeWithIdentifier:(NSString *)identifier;
- (void)setDisablesUpdateLastUsedInputModeTimer:(BOOL)disabled;
@end

// "vi_VN-Telex@sw=QWERTY;hw=Automatic" / "en_US@sw=QWERTY" / "en-US" / "vi" -> "vi" / "en"
static inline NSString *PAKLanguageHead(NSString *value) {
	NSCharacterSet *separators = [NSCharacterSet characterSetWithCharactersInString:@"_-@;"];
	return [value componentsSeparatedByCharactersInSet:separators].firstObject ?: @"";
}

// The mode lists come back as UIKeyboardInputMode objects in some arrays/processes and as plain
// identifier strings in others (enabledInputModes in Settings): always hand out modes.
static inline NSArray<UIKeyboardInputMode *> *PAKModes(UIKeyboardInputModeController *controller, NSArray *raw) {
	NSMutableArray *result = [NSMutableArray array];
	for (id item in raw ?: @[]) {
		id mode = item;
		if ([item isKindOfClass:NSString.class]) {
			mode = [controller respondsToSelector:@selector(inputModeWithIdentifier:)] ? [controller inputModeWithIdentifier:item] : nil;
		}
		if ([mode respondsToSelector:@selector(isEmojiInputMode)]) [result addObject:mode];
	}
	return result;
}

// iOS keyboards only: no emoji, no third-party keyboard extensions.
static inline BOOL PAKModeIsSelectable(UIKeyboardInputMode *mode) {
	return mode && !mode.isEmojiInputMode && !mode.isExtensionInputMode;
}

static inline BOOL PAKModeIsLanguage(UIKeyboardInputMode *mode, NSString *lang) {
	if (!PAKModeIsSelectable(mode)) return NO;
	// isHandwritingInputMode doesn't exist before iOS 17: calling it unchecked crashes iOS 15 / 16.
	if ([mode respondsToSelector:@selector(isHandwritingInputMode)] && mode.isHandwritingInputMode) return NO;
	NSString *ident = mode.identifier ?: mode.primaryLanguage;
	return ident.length && [PAKLanguageHead(ident) caseInsensitiveCompare:lang] == NSOrderedSame;
}

// The keyboards the user has enabled, in their own order, that the tweak can switch to.
static inline NSArray<UIKeyboardInputMode *> *PAKSelectableModes(UIKeyboardInputModeController *controller) {
	NSMutableArray *result = [NSMutableArray array];
	for (UIKeyboardInputMode *mode in PAKModes(controller, controller.activeInputModes)) {
		if (PAKModeIsSelectable(mode)) [result addObject:mode];
	}
	return result;
}

// `wanted` is a stored keyboard: the exact input mode if the user still has it, otherwise the
// first keyboard of the same language, otherwise nil (leave the keyboard alone).
static inline UIKeyboardInputMode *PAKResolveMode(UIKeyboardInputModeController *controller, NSString *wanted) {
	if (!controller || !wanted.length || [wanted isEqualToString:PAK_KEYBOARD_LAST]) return nil;
	NSArray *lists = @[ PAKModes(controller, controller.activeInputModes), PAKModes(controller, controller.enabledInputModes) ];
	for (NSArray *modes in lists) {
		for (UIKeyboardInputMode *mode in modes) {
			if (PAKModeIsSelectable(mode) && [mode.identifier isEqualToString:wanted]) return mode;
		}
	}
	NSString *lang = PAKLanguageHead(wanted);
	for (NSArray *modes in lists) {
		for (UIKeyboardInputMode *mode in modes) {
			if (PAKModeIsLanguage(mode, lang)) return mode;
		}
	}
	return nil;
}

static inline NSString *PAKModeTitle(UIKeyboardInputMode *mode) {
	NSString *name = mode.extendedDisplayName.length ? mode.extendedDisplayName : mode.displayName;
	return name.length ? name : mode.identifier;
}

// Human readable name of a stored keyboard, also when the user no longer has it.
static inline NSString *PAKKeyboardTitle(NSString *wanted) {
	if ([wanted isEqualToString:PAK_KEYBOARD_LAST]) return @"Last used in this app";
	UIKeyboardInputMode *mode = PAKResolveMode([UIKeyboardInputModeController sharedInputModeController], wanted);
	if (mode) return PAKModeTitle(mode);
	NSString *language = [NSLocale.currentLocale localizedStringForLanguageCode:PAKLanguageHead(wanted)] ?: wanted;
	return [language stringByAppendingString:@" (not installed)"];
}
