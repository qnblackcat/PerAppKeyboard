#import "PAKLog.h"
#import <os/log.h>
#include <fcntl.h>
#include <sys/stat.h>
#include <unistd.h>

static NSString *const PAKRecordSeparator = @"\x1e";

BOOL PAKDebugEnabled(void) {
	return [PAKPrefsLoad()[PAK_DEBUG_LOG] boolValue];
}

// The first directory the process may really write to wins; the reader looks in all of them.
static NSArray<NSString *> *PAKLogDirectories(void) {
	return @[
		jbroot(@"/var/mobile/Library/Caches/PerAppKeyboard"),
		jbroot(@"/var/tmp/PerAppKeyboard"),
		@"/var/mobile/tmp/PerAppKeyboard",
	];
}

static NSString *PAKWritableDirectory(void) {
	static NSString *directory;
	static BOOL failed;
	if (directory || failed) return directory;
	for (NSString *candidate in PAKLogDirectories()) {
		if (![[NSFileManager defaultManager] createDirectoryAtPath:candidate withIntermediateDirectories:YES attributes:nil error:NULL]) continue;
		// access() can say yes where the sandbox still refuses open(): try a real file
		NSString *probe = [candidate stringByAppendingPathComponent:@".probe"];
		int fd = open(probe.fileSystemRepresentation, O_WRONLY | O_CREAT, 0644);
		if (fd < 0) continue;
		close(fd);
		unlink(probe.fileSystemRepresentation);
		directory = candidate;
		return directory;
	}
	failed = YES;
	os_log(OS_LOG_DEFAULT, "[PerAppKeyboard] no writable log directory in this process, debug log file disabled");
	return nil;
}

static void PAKLogFileAppend(NSString *text) {
	static dispatch_queue_t queue;
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		queue = dispatch_queue_create("com.qn.perappkeyboard.log", DISPATCH_QUEUE_SERIAL);
	});
	long long millis = (long long)([[NSDate date] timeIntervalSince1970] * 1000);
	NSString *process = [[NSProcessInfo processInfo] processName];
	NSString *record = [NSString stringWithFormat:@"%@%lld %@ %@\n", PAKRecordSeparator, millis, process, text];
	dispatch_async(queue, ^{
		NSString *directory = PAKWritableDirectory();
		if (!directory) return;
		NSString *path = [directory stringByAppendingPathComponent:[process stringByAppendingString:@".log"]];
		struct stat st;
		if (stat(path.fileSystemRepresentation, &st) == 0 && st.st_size >= PAKLogFileMaxBytes) {
			rename(path.fileSystemRepresentation, [path stringByAppendingString:@".1"].fileSystemRepresentation);
		}
		int fd = open(path.fileSystemRepresentation, O_WRONLY | O_APPEND | O_CREAT, 0644);
		if (fd < 0) return;
		NSData *data = [record dataUsingEncoding:NSUTF8StringEncoding];
		write(fd, data.bytes, data.length);
		close(fd);
	});
}

void PAKLogWrite(NSString *format, ...) {
	va_list args;
	va_start(args, format);
	NSString *text = [[NSString alloc] initWithFormat:format arguments:args];
	va_end(args);
	os_log(OS_LOG_DEFAULT, "[PerAppKeyboard] %{public}@", text);
	PAKLogFileAppend(text);
}

static NSArray<NSString *> *PAKLogPaths(void) {
	NSMutableArray *paths = [NSMutableArray array];
	for (NSString *directory in PAKLogDirectories()) {
		for (NSString *name in [[NSFileManager defaultManager] contentsOfDirectoryAtPath:directory error:NULL]) {
			if ([name hasSuffix:@".log"] || [name hasSuffix:@".log.1"]) [paths addObject:[directory stringByAppendingPathComponent:name]];
		}
	}
	return paths;
}

NSString *PAKLogFileRead(NSUInteger maxBytes) {
	NSMutableArray<NSArray *> *records = [NSMutableArray array];   // [millis, "process text"]
	for (NSString *path in PAKLogPaths()) {
		NSString *content = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:NULL];
		for (NSString *record in [content componentsSeparatedByString:PAKRecordSeparator]) {
			NSRange space = [record rangeOfString:@" "];
			if (space.location == NSNotFound) continue;
			long long millis = [[record substringToIndex:space.location] longLongValue];
			if (millis <= 0) continue;
			[records addObject:@[@(millis), [record substringFromIndex:NSMaxRange(space)]]];
		}
	}
	[records sortUsingComparator:^NSComparisonResult(NSArray *a, NSArray *b) {
		return [a[0] compare:b[0]];
	}];
	NSDateFormatter *formatter = [NSDateFormatter new];
	formatter.dateFormat = @"MM-dd HH:mm:ss.SSS";
	NSMutableArray<NSString *> *lines = [NSMutableArray array];
	NSUInteger total = 0;
	// newest first, so the cut at maxBytes drops the oldest records
	for (NSArray *record in [records reverseObjectEnumerator]) {
		NSString *time = [formatter stringFromDate:[NSDate dateWithTimeIntervalSince1970:[record[0] longLongValue] / 1000.0]];
		NSString *line = [NSString stringWithFormat:@"%@ %@", time, record[1]];
		if (total + line.length > maxBytes && lines.count) break;
		total += line.length;
		[lines addObject:line];
	}
	return [[[lines reverseObjectEnumerator] allObjects] componentsJoinedByString:@""];
}

void PAKLogFileClear(void) {
	for (NSString *path in PAKLogPaths()) [[NSFileManager defaultManager] removeItemAtPath:path error:NULL];
}
