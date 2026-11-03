#import <Foundation/Foundation.h>
#include <notify.h>
#include <sys/stat.h>
#include <roothide.h>

// Settings live in one plist inside jbroot instead of going through cfprefsd. Sandboxed
// processes (Messages, every App Store app...) are denied our domain by cfprefsd, but they can
// read files inside jbroot, which is where the tweak itself gets loaded from.
// Shared by the tweak and the Settings bundle.

#define PAK_ENABLED                 @"Enabled"               // master switch
#define PAK_RESET_ON_KEYBOARD_HIDE  @"ResetOnKeyboardHide"   // dismissing and showing the keyboard
#define PAK_RESET_ON_LEAVE_APP      @"ResetOnLeaveApp"       // Home / another app
#define PAK_RESET_ON_LOCK           @"ResetOnLock"           // power button

// { bundle id : keyboard }, the keyboard each app starts on: an input mode identifier
// ("vi_VN-Telex@sw=QWERTY;hw=Automatic"), or PAK_KEYBOARD_LAST. Apps that aren't in the map are
// left alone, so nothing happens anywhere until the user sets an app up in Settings.
#define PAK_APP_KEYBOARDS           @"AppKeyboards"

// Instead of a fixed keyboard, an app can start on whatever keyboard the user last picked in it.
// The pick is remembered per app, in the app's own preferences (a sandboxed app can't write
// ours), so it also survives the app being relaunched.
#define PAK_KEYBOARD_LAST           @"PAKLastUsed"

static inline NSString *PAKPrefsPath(void) {
	return jbroot(@"/var/mobile/Library/Preferences/com.qn.perappkeyboard.plist");
}

// Parsed again only when the file changed (inode / mtime / size; the plist is written atomically,
// so a save always swaps the inode): the tweak asks for settings on every keyboard show.
static inline NSDictionary *PAKPrefsLoad(void) {
	static NSDictionary *cached;
	static struct stat cachedStat;
	NSString *path = PAKPrefsPath();
	struct stat st;
	if (stat(path.fileSystemRepresentation, &st) != 0) {
		cached = nil;
		return [NSDictionary dictionaryWithContentsOfFile:path] ?: @{};
	}
	if (!cached || st.st_ino != cachedStat.st_ino || st.st_size != cachedStat.st_size ||
		st.st_mtimespec.tv_sec != cachedStat.st_mtimespec.tv_sec || st.st_mtimespec.tv_nsec != cachedStat.st_mtimespec.tv_nsec) {
		cached = [NSDictionary dictionaryWithContentsOfFile:path] ?: @{};
		cachedStat = st;
	}
	return cached;
}

static inline void PAKPrefsSet(id value, NSString *key) {
	NSMutableDictionary *prefs = [PAKPrefsLoad() mutableCopy];
	prefs[key] = value;
	NSString *path = PAKPrefsPath();
	[[NSFileManager defaultManager] createDirectoryAtPath:[path stringByDeletingLastPathComponent]
							   withIntermediateDirectories:YES attributes:nil error:NULL];
	if (![prefs writeToFile:path atomically:YES]) NSLog(@"[PerAppKeyboard] couldn't write preferences to %@", path);
	notify_post("com.qn.perappkeyboard/ReloadPrefs");   // lets the Control Center tile follow the Settings switch
}

static inline NSDictionary<NSString *, NSString *> *PAKPrefsAppKeyboards(void) {
	id stored = PAKPrefsLoad()[PAK_APP_KEYBOARDS];
	return [stored isKindOfClass:NSDictionary.class] ? stored : @{};
}

static inline NSString *PAKPrefsKeyboardForBundle(NSString *bundleID) {
	return bundleID ? PAKPrefsAppKeyboards()[bundleID] : nil;
}

// keyboard == nil / empty: back to whatever iOS picks.
static inline void PAKPrefsSetAppKeyboard(NSString *bundleID, NSString *keyboard) {
	if (!bundleID) return;
	NSMutableDictionary *map = [PAKPrefsAppKeyboards() mutableCopy];
	if (keyboard.length) map[bundleID] = keyboard; else [map removeObjectForKey:bundleID];
	PAKPrefsSet(map, PAK_APP_KEYBOARDS);
}
