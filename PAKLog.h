#import <Foundation/Foundation.h>
#import "PAKPrefs.h"

// PAKLog does nothing unless the Debug switch is on (Settings → PerAppKeyboard → Troubleshooting).
// A macro, so the arguments aren't evaluated while Debug is off. While on, each line goes to the
// unified log with the "[PerAppKeyboard]" prefix and is appended to a log file (capped at
// PAKLogFileMaxBytes per process, rotated to <name>.1).
//
// The tweak runs inside sandboxed apps, so the log file goes to the first directory the process
// can really write to (see PAKLogDirectories); the Settings bundle reads all of them.

#define PAKLogFileMaxBytes (128 * 1024)

#define PAKLog(fmt, ...) do { if (PAKDebugEnabled()) PAKLogWrite(@"" fmt, ##__VA_ARGS__); } while (0)

BOOL PAKDebugEnabled(void);
void PAKLogWrite(NSString *format, ...) NS_FORMAT_FUNCTION(1, 2);

// Used by the Settings bundle: the log of every process merged by time, newest last, limited to
// the last maxBytes characters.
NSString *PAKLogFileRead(NSUInteger maxBytes);
void PAKLogFileClear(void);
