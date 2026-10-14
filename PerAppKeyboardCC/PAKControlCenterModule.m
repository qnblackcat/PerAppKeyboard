#import <UIKit/UIKit.h>
#import <ControlCenterUIKit/CCUIToggleModule.h>
#import <dlfcn.h>
#import <notify.h>
#import "../PAKPrefs.h"

// Control Center toggle for the tweak's master switch ("Enabled" in Settings). Loaded into
// SpringBoard by CCSupport, which can write the jbroot plist the tweak reads; the tweak re-reads
// it on every event, so the change applies at once.

__attribute__((constructor))
static void PAKControlCenterInit(void) {
	// the superclass has to be there before the module class is used
	dlopen("/System/Library/PrivateFrameworks/ControlCenterUIKit.framework/ControlCenterUIKit", RTLD_NOW);
	dlopen("/System/Library/PrivateFrameworks/ControlCenterUI.framework/ControlCenterUI", RTLD_NOW);
}

// Keeps the tile in step when the switch is flipped in Settings (PAKPrefsSet posts this).
static void PAKReloadCallback(CFNotificationCenterRef center, void *observer, CFNotificationName name, const void *object, CFDictionaryRef userInfo) {
	id module = (__bridge id)observer;
	dispatch_async(dispatch_get_main_queue(), ^{ [module refreshState]; });
}

@interface PAKControlCenterModule : CCUIToggleModule
@end

@implementation PAKControlCenterModule

- (instancetype)init {
	self = [super init];
	if (self) {
		CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), (__bridge const void *)self, PAKReloadCallback,
										CFSTR("com.qn.perappkeyboard/ReloadPrefs"), NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
	}
	return self;
}

- (void)dealloc {
	CFNotificationCenterRemoveEveryObserver(CFNotificationCenterGetDarwinNotifyCenter(), (__bridge const void *)self);
}

// Control Center tints the glyph itself, so it has to be a single colour image: glyph.png /
// @2x / @3x in the bundle (the four language tiles with the codes knocked out).
- (UIImage *)iconGlyph {
	UIImage *glyph = [UIImage imageNamed:@"glyph" inBundle:[NSBundle bundleForClass:self.class] compatibleWithTraitCollection:nil];
	if (glyph) return [glyph imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];

	UIImageSymbolConfiguration *configuration = [UIImageSymbolConfiguration configurationWithPointSize:24.0 weight:UIImageSymbolWeightMedium];
	return [UIImage systemImageNamed:@"keyboard" withConfiguration:configuration];
}

- (UIImage *)selectedIconGlyph {
	return [self iconGlyph];
}

- (UIColor *)selectedColor {
	return [UIColor colorWithRed:0.20 green:0.60 blue:1.0 alpha:1.0];
}

- (BOOL)isSelected {
	id enabled = PAKPrefsLoad()[PAK_ENABLED];
	return enabled ? [enabled boolValue] : YES;   // on unless switched off, like the tweak
}

- (void)setSelected:(BOOL)selected {
	PAKPrefsSet(@(selected), PAK_ENABLED);
	[super refreshState];
}

@end
