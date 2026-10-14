#import "PAKRootListController.h"
#import <Preferences/PSSpecifier.h>
#import "PAKAppListController.h"
#import "../PAKPrefs.h"

@implementation PAKRootListController

- (NSArray *)specifiers {
	if (!_specifiers) {
		// before loading: the plist's `detail` class names are resolved while loading
		BOOL haveAppPicker = PAKRegisterAppListController();

		NSMutableArray *specs = [[self loadSpecifiersFromPlistName:@"Root" target:self] mutableCopy];
		if (!haveAppPicker) {
			[specs filterUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(PSSpecifier *spec, NSDictionary *bindings) {
				return ![spec.properties[@"pak-app-picker"] boolValue];
			}]];
			for (PSSpecifier *spec in specs) {
				if ([spec.properties[@"label"] hasSuffix:@"Apps"]) {
					[spec setProperty:@"Choosing apps needs AltList (com.opa334.altlist). Install it, then reopen this page." forKey:@"footerText"];
				}
			}
		}
		PSSpecifier *sourceGroup = [PSSpecifier groupSpecifierWithName:@"\U0001F4BB Source Code"];
		[sourceGroup setProperty:@"\u00a9 2026 Qn (\u0110\u1ea1t Nguy\u1ec5n)" forKey:@"footerText"];
		[specs addObject:sourceGroup];
		PSSpecifier *source = [PSSpecifier preferenceSpecifierNamed:@"GitHub" target:self set:nil get:nil detail:nil cell:PSButtonCell edit:nil];
		source.buttonAction = @selector(openSourceCode:);
		[specs addObject:source];

		_specifiers = specs;
	}
	return _specifiers;
}

// Stores every specifier with defaults = com.qn.perappkeyboard in the jbroot plist rather than
// letting PSListController write it through cfprefsd, which sandboxed apps can't read.
static BOOL isOurs(PSSpecifier *specifier) {
	return [specifier.properties[@"defaults"] isEqualToString:@"com.qn.perappkeyboard"]
		&& specifier.properties[@"key"] != nil;
}

- (id)readPreferenceValue:(PSSpecifier *)specifier {
	if (!isOurs(specifier)) return [super readPreferenceValue:specifier];
	return PAKPrefsLoad()[specifier.properties[@"key"]] ?: specifier.properties[@"default"];
}

- (void)setPreferenceValue:(id)value specifier:(PSSpecifier *)specifier {
	if (!isOurs(specifier)) {
		[super setPreferenceValue:value specifier:specifier];
		return;
	}
	PAKPrefsSet(value, specifier.properties[@"key"]);
}

- (void)openSourceCode:(PSSpecifier *)specifier {
	[[UIApplication sharedApplication] openURL:[NSURL URLWithString:@"https://github.com/qnblackcat/PerAppKeyboard"] options:@{} completionHandler:nil];
}

@end
