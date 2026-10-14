#import "PAKAppListController.h"
#import <objc/runtime.h>
#import <dlfcn.h>
#include <roothide.h>
#import "../PAKPrefs.h"
#import "../PAKKeyboards.h"

// The value shown on an app's row; nil (no value) for apps left on the system default.
static NSString *previewStringForApplicationWithIdentifier(id self, SEL _cmd, NSString *applicationID) {
	NSString *keyboard = PAKPrefsKeyboardForBundle(applicationID);
	return keyboard ? PAKKeyboardTitle(keyboard) : nil;
}

BOOL PAKRegisterAppListController(void) {
	static dispatch_once_t once;
	static BOOL available;
	dispatch_once(&once, ^{
		if (!NSClassFromString(@"ATLApplicationListSubcontrollerController")) {
			NSString *path = jbroot(@"/Library/Frameworks/AltList.framework/AltList");
			if (!dlopen(path.fileSystemRepresentation, RTLD_NOW))
				NSLog(@"[PerAppKeyboard] couldn't load AltList from %@: %s", path, dlerror());
		}
		Class base = NSClassFromString(@"ATLApplicationListSubcontrollerController");
		if (!base) return;

		Class cls = objc_allocateClassPair(base, "PAKAppListController", 0);
		if (!cls) { available = NSClassFromString(@"PAKAppListController") != nil; return; }
		class_addMethod(cls, @selector(previewStringForApplicationWithIdentifier:), (IMP)previewStringForApplicationWithIdentifier, "@@:@");
		objc_registerClassPair(cls);
		available = YES;
	});
	return available;
}
