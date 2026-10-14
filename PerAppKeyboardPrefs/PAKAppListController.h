#import <Foundation/Foundation.h>

// Creates the PAKAppListController class at runtime: a subclass of AltList's "one page per app"
// list (ATLApplicationListSubcontrollerController) that shows the keyboard chosen for each app
// as the row's value. Tapping an app opens PAKAppKeyboardController.
//
// AltList is loaded with dlopen(jbroot(...)) rather than linked, so the Settings pane still
// opens (without the app picker) when AltList is missing, and the same code works on rootless,
// roothide and rootful. Returns NO if AltList couldn't be loaded.
// Must run before the specifiers are loaded: their `detail` class is resolved by name.
BOOL PAKRegisterAppListController(void);
