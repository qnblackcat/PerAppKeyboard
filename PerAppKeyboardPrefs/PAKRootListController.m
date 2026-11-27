#import "PAKRootListController.h"
#import <Preferences/PSSpecifier.h>
#import "PAKAppListController.h"
#import "../PAKPrefs.h"
#import "../PAKLog.h"
#include <sys/utsname.h>

#define PAKLogCopyMaxBytes (200 * 1024)

@implementation PAKRootListController {
	NSString *_logFooter;               // the troubleshooting note, shown only while Debug is on
	NSArray<PSSpecifier *> *_logRows;   // share/copy/clear buttons, shown only while Debug is on
}

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
		// the log buttons only make sense while Debug is on
		NSMutableArray *logRows = [NSMutableArray array];
		for (PSSpecifier *spec in specs) {
			if ([@[@"shareLog", @"copyLog", @"clearLog"] containsObject:spec.identifier]) [logRows addObject:spec];
		}
		_logRows = logRows;
		BOOL debugOn = [PAKPrefsLoad()[@"Debug"] boolValue];
		if (!debugOn) [specs removeObjectsInArray:_logRows];
		for (PSSpecifier *spec in specs) {
			if ([spec.identifier isEqualToString:@"troubleGroup"]) {
				_logFooter = [spec propertyForKey:@"footerText"];
				if (!debugOn) [spec setProperty:@"" forKey:@"footerText"];
			}
		}
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
	// show or hide the log buttons when the Debug switch is flipped
	if (![specifier.identifier isEqualToString:@"debugSwitch"] || !_logRows.count) return;
	PSSpecifier *debugRow = [self specifierForID:@"debugSwitch"];
	PSSpecifier *group = [self specifierForID:@"troubleGroup"];
	[group setProperty:([value boolValue] ? _logFooter : @"") forKey:@"footerText"];
	if ([value boolValue]) {
		if (![self specifierForID:@"shareLog"]) [self insertContiguousSpecifiers:_logRows afterSpecifier:debugRow animated:YES];
	} else {
		[self removeContiguousSpecifiers:_logRows animated:YES];
	}
	// the footer is only re-read when its section is reloaded
	NSInteger section = [self indexPathForSpecifier:group].section;
	if (section != NSNotFound) {
		[self.table reloadSections:[NSIndexSet indexSetWithIndex:section] withRowAnimation:UITableViewRowAnimationNone];
	}
}

#pragma mark - About

- (void)openURLString:(NSString *)string {
	[[UIApplication sharedApplication] openURL:[NSURL URLWithString:string] options:@{} completionHandler:nil];
}

- (void)openSourceCode {
	[self openURLString:@"https://github.com/qnblackcat/PerAppKeyboard"];
}

- (void)openTwitter {
	[self openURLString:@"https://x.com/t70438299"];
}

- (NSString *)tweakVersion:(PSSpecifier *)specifier {
	return @PAK_VERSION;
}

#pragma mark - Troubleshooting

- (void)showAlertWithTitle:(NSString *)title message:(NSString *)message {
	UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];
	[alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
	[self presentViewController:alert animated:YES completion:nil];
}

// The log with a header saying what it came from, or nil (after telling the user) if there is nothing to send
- (NSString *)debugLogForSending {
	NSString *log = PAKLogFileRead(PAKLogCopyMaxBytes);
	if (!log.length) {
		[self showAlertWithTitle:@"The log is empty" message:@"Turn on Debug, use an app you set up, then try again. Nothing is recorded for apps that aren't set up."];
		return nil;
	}
	struct utsname system;
	uname(&system);
	NSString *header = [NSString stringWithFormat:@"PerAppKeyboard %@ debug log, iOS %@, %s\n", @PAK_VERSION, [UIDevice currentDevice].systemVersion, system.machine];
	return [header stringByAppendingString:log];
}

- (void)copyDebugLog {
	NSString *log = [self debugLogForSending];
	if (!log) return;
	[UIPasteboard generalPasteboard].string = log;
	[self showAlertWithTitle:@"Copied" message:[NSString stringWithFormat:@"%lu KB of log copied to the clipboard.", (unsigned long)(log.length / 1024 + 1)]];
}

- (void)shareDebugLog {
	NSString *log = [self debugLogForSending];
	if (!log) return;
	NSURL *url = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:@"PerAppKeyboard-debug-log.txt"]];
	if (![log writeToURL:url atomically:YES encoding:NSUTF8StringEncoding error:NULL]) {
		[self showAlertWithTitle:@"Couldn't write the log file" message:nil];
		return;
	}
	UIActivityViewController *sheet = [[UIActivityViewController alloc] initWithActivityItems:@[url] applicationActivities:nil];
	sheet.popoverPresentationController.sourceView = self.view;
	[self presentViewController:sheet animated:YES completion:nil];
}

- (void)clearDebugLog {
	UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Delete the debug log?" message:nil preferredStyle:UIAlertControllerStyleAlert];
	[alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
	[alert addAction:[UIAlertAction actionWithTitle:@"Delete" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
		PAKLogFileClear();
	}]];
	[self presentViewController:alert animated:YES completion:nil];
}

@end
