#import <Foundation/Foundation.h>

// Resets the keyboard around the moments the user leaves an app and comes back to it: hiding the
// keyboard, Home / another app, the power button. Call once, from the app process, after
// PAKSwitcherSetUp succeeded.
void PAKLifecycleStart(void);
