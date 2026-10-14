#import "PAKAppKeyboardController.h"
#import <Preferences/PSSpecifier.h>
#import <Preferences/PSTableCell.h>
#import "../PAKPrefs.h"
#import "../PAKKeyboards.h"

// Property on each row: the input mode identifier it stands for, @"" for "Don’t change".
static NSString *const kRowKeyboard = @"pak-keyboard";

@implementation PAKAppKeyboardController

- (NSString *)applicationID {
	return [self.specifier propertyForKey:@"applicationIdentifier"];
}

- (void)setSpecifier:(PSSpecifier *)specifier {
	[super setSpecifier:specifier];
	self.title = specifier.name;
}

// The keyboard this page shows as chosen: the exact one if it's still installed.
- (NSString *)checkedKeyboard {
	NSString *stored = PAKPrefsKeyboardForBundle(self.applicationID);
	if (!stored) return @"";
	if ([stored isEqualToString:PAK_KEYBOARD_LAST]) return stored;
	UIKeyboardInputMode *mode = PAKResolveMode([UIKeyboardInputModeController sharedInputModeController], stored);
	return mode.identifier ?: stored;
}

// Rebuilt every time the page opens, so keyboards added in Settings show up.
- (NSArray *)specifiers {
	if (!_specifiers) {
		NSMutableArray *specs = [NSMutableArray array];

		PSSpecifier *group = [PSSpecifier groupSpecifierWithName:nil];
		[group setProperty:@"The keyboard this app starts on. Third-party keyboards aren\u2019t listed.\n\n\u2022 \u201cDon\u2019t change\u201d leaves it to iOS.\n\u2022 \u201cLast used\u201d remembers your last pick in this app." forKey:@"footerText"];
		[specs addObject:group];

		void (^addRow)(NSString *, NSString *) = ^(NSString *title, NSString *keyboard) {
			PSSpecifier *row = [PSSpecifier preferenceSpecifierNamed:title target:self set:NULL get:NULL detail:Nil cell:PSListItemCell edit:Nil];
			[row setProperty:keyboard forKey:kRowKeyboard];
			[specs addObject:row];
		};
		addRow(@"Don\u2019t change (iOS decides)", @"");
		addRow(@"Last used in this app", PAK_KEYBOARD_LAST);
		for (UIKeyboardInputMode *mode in PAKSelectableModes([UIKeyboardInputModeController sharedInputModeController])) {
			addRow(PAKModeTitle(mode), mode.identifier);
		}
		_specifiers = specs;
	}
	return _specifiers;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
	UITableViewCell *cell = [super tableView:tableView cellForRowAtIndexPath:indexPath];
	NSString *keyboard = [[self specifierAtIndexPath:indexPath] propertyForKey:kRowKeyboard];
	if (keyboard && [cell respondsToSelector:@selector(setChecked:)]) {
		[(PSTableCell *)cell setChecked:[keyboard isEqualToString:[self checkedKeyboard]]];
	}
	return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
	NSString *keyboard = [[self specifierAtIndexPath:indexPath] propertyForKey:kRowKeyboard];
	if (!keyboard) {
		[super tableView:tableView didSelectRowAtIndexPath:indexPath];
		return;
	}
	PAKPrefsSetAppKeyboard(self.applicationID, keyboard);
	[tableView deselectRowAtIndexPath:indexPath animated:YES];
	[tableView reloadData];
}

- (void)viewWillDisappear:(BOOL)animated {
	[super viewWillDisappear:animated];
	// show the new choice on the app's row in the previous page
	PSListController *previous = (PSListController *)self.navigationController.topViewController;
	if ([previous respondsToSelector:@selector(reloadSpecifier:)]) [previous reloadSpecifier:self.specifier];
}

@end
