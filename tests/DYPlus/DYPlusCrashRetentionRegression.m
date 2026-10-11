#import <Foundation/Foundation.h>
#import "Core/Storage/DYPlusPaths.h"
#import "Diagnostics/DYPlusCrashCatcher.h"

void DYPlusSeedCrashRetention(void) {
    NSString *directory = [DYPlusPaths logsDir];
    [NSFileManager.defaultManager createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:nil];
    for (NSString *name in @[@"regression.sqlite", @"AudioReport-regression.json", @"Crash_100000.txt", @"Crash_100001.txt", @"Crash_100002.txt", @"Crash_100003.txt"])
        [@"fixture" writeToFile:[directory stringByAppendingPathComponent:name] atomically:YES encoding:NSUTF8StringEncoding error:nil];
    printf("RETENTION SEEDED\n"); fflush(stdout);
}
void DYPlusVerifyCrashRetention(void) {
    NSString *directory = [DYPlusPaths logsDir];
    NSFileManager *files = NSFileManager.defaultManager;
    BOOL valid = [files fileExistsAtPath:[directory stringByAppendingPathComponent:@"regression.sqlite"]]
        && [files fileExistsAtPath:[directory stringByAppendingPathComponent:@"AudioReport-regression.json"]]
        && ![files fileExistsAtPath:[directory stringByAppendingPathComponent:@"Crash_100000.txt"]]
        && [DYPlusCrashCatcher savedLogFilePaths].count == 3;
    for (NSString *name in @[@"regression.sqlite", @"AudioReport-regression.json", @"Crash_100000.txt", @"Crash_100001.txt", @"Crash_100002.txt", @"Crash_100003.txt"])
        [files removeItemAtPath:[directory stringByAppendingPathComponent:name] error:nil];
    printf("CRASH RETENTION: %s\n", valid ? "PASS" : "FAIL"); fflush(stdout);
    if (!valid) exit(1);
}
