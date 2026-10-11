#import "Diagnostics/DYPlusCrashCatcher.h"
#import "Core/Storage/DYPlusPaths.h"
#import <UIKit/UIKit.h>
#import <signal.h>
#import <execinfo.h>
#import <unistd.h>
#import <fcntl.h>
#import <time.h>
#import <sys/stat.h>
#import <string.h>

#define DYPLUS_MAX_CRASH_LOGS 3

static BOOL DYPlusIsCrashLogName(NSString *name) {
    if (![name hasPrefix:@"Crash_"] || ![name hasSuffix:@".txt"] || name.length <= 10) return NO;
    NSString *timestamp = [name substringWithRange:NSMakeRange(6, name.length - 10)];
    return [timestamp rangeOfCharacterFromSet:NSCharacterSet.decimalDigitCharacterSet.invertedSet].location == NSNotFound;
}

static NSArray<NSString *> *DYPlusCrashLogNames(NSString *directory) {
    NSMutableArray *result = [NSMutableArray array];
    for (NSString *name in [NSFileManager.defaultManager contentsOfDirectoryAtPath:directory error:nil])
        if (DYPlusIsCrashLogName(name)) [result addObject:name];
    return result;
}

// 崩溃日志目录的 C 路径缓存（constructor 阶段准备，signal handler 内只做 C 级操作）
static char gDYPlusCrashDirPath[PATH_MAX] = {0};
// 防递归：崩溃处理中再次崩溃直接走默认流程
static volatile sig_atomic_t gDYPlusCrashHandling = 0;
// 链式保存的旧处理器，写完日志后交还抖音/其他 SDK 处理
static NSUncaughtExceptionHandler *gDYPlusPreviousExceptionHandler = NULL;
static void (*gDYPlusOldSignalHandlers[NSIG])(int);

static NSString *DYPlusCrashLogDirectory(void) {
    NSString *dir = [DYPlusPaths logsDir]; // 调试类统一平铺 Logs/
    [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
    return dir;
}

// 启动时清理旧日志，仅保留最近 DYYY_MAX_CRASH_LOGS 份
static void DYPlusCleanupOldCrashLogs(void) {
    NSString *dir = DYPlusCrashLogDirectory();
    // Logs 也存放数据库与音频报告，只清理本模块的 Crash_<数字>.txt。
    NSArray<NSString *> *files = DYPlusCrashLogNames(dir);
    if (files.count <= DYPLUS_MAX_CRASH_LOGS) return;

    NSArray<NSString *> *sorted = [files sortedArrayUsingComparator:^NSComparisonResult(NSString *a, NSString *b) {
        return [a compare:b];
    }];
    NSUInteger removeCount = sorted.count - DYPLUS_MAX_CRASH_LOGS;
    for (NSUInteger i = 0; i < removeCount; i++) {
        [[NSFileManager defaultManager] removeItemAtPath:[dir stringByAppendingPathComponent:sorted[i]] error:nil];
    }
}

static const char *DYPlusSignalName(int sig) {
    switch (sig) {
        case SIGABRT: return "SIGABRT";
        case SIGSEGV: return "SIGSEGV";
        case SIGBUS:  return "SIGBUS";
        case SIGILL:  return "SIGILL";
        case SIGFPE:  return "SIGFPE";
        case SIGTRAP: return "SIGTRAP";
        default:      return "UNKNOWN_SIGNAL";
    }
}

// 信号现场不格式化、不分配、不展开调用栈。完整栈由系统崩溃报告提供。
static void DYPlusSignalHandler(int sig) {
    if (gDYPlusCrashHandling) {
        signal(sig, SIG_DFL);
        raise(sig);
        return;
    }
    gDYPlusCrashHandling = 1;

    if (gDYPlusCrashDirPath[0] != 0) {
        // 纳秒时间戳防同秒两次崩溃互相覆盖；clock_gettime 是 async-signal-safe
        struct timespec ts = {0};
        clock_gettime(CLOCK_REALTIME, &ts);
        long long nanos = (long long)ts.tv_sec * 1000000000LL + ts.tv_nsec;
        char nameBuf[PATH_MAX];
        size_t offset = 0;
        while (gDYPlusCrashDirPath[offset] && offset < sizeof(nameBuf) - 40) {
            nameBuf[offset] = gDYPlusCrashDirPath[offset]; offset++;
        }
        const char prefix[] = "/Crash_";
        for (size_t i = 0; i < sizeof(prefix) - 1; i++) nameBuf[offset++] = prefix[i];
        char digits[32];
        size_t count = 0;
        unsigned long long timestamp = (unsigned long long)nanos;
        do { digits[count++] = (char)('0' + timestamp % 10); timestamp /= 10; } while (timestamp && count < sizeof(digits));
        while (count) nameBuf[offset++] = digits[--count];
        const char suffix[] = ".txt";
        for (size_t i = 0; i < sizeof(suffix); i++) nameBuf[offset++] = suffix[i];

        int fd = open(nameBuf, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0600);
        if (fd >= 0) {
            const char header[] = "DYPlus fatal signal: ";
            write(fd, header, sizeof(header) - 1);
            const char *signalName = DYPlusSignalName(sig);
            size_t length = 0;
            while (signalName[length]) length++;
            write(fd, signalName, length);
            const char footer[] = "\nSee the system crash report for the full stack.\n";
            write(fd, footer, sizeof(footer) - 1);
            close(fd);
        }
    }

    // 交还旧处理器或走默认崩溃流程
    void (*old)(int) = gDYPlusOldSignalHandlers[sig];
    if (old && old != SIG_DFL && old != DYPlusSignalHandler) {
        old(sig);
    }
    // 旧处理器如果返回，也不能吞掉致命信号。
    signal(sig, SIG_DFL);
    raise(sig);
}

// 未捕获 ObjC 异常处理器：ObjC 环境可用，写详细日志后链式调用旧处理器
static void DYPlusUncaughtExceptionHandler(NSException *exception) {
    if (gDYPlusCrashHandling) return;
    gDYPlusCrashHandling = 1;

    @try {
        NSString *dir = DYPlusCrashLogDirectory();
        long long ts = (long long)([[NSDate date] timeIntervalSince1970] * 1000000.0);
        NSString *path = [dir stringByAppendingPathComponent:[NSString stringWithFormat:@"Crash_%lld.txt", ts]];
        NSString *stack = [[exception callStackSymbols] componentsJoinedByString:@"\n"] ?: @"(无调用栈)";
        NSString *content = [NSString stringWithFormat:
            @"===== DYPlus 崩溃日志 =====\n时间: %@ (unix %lld)\n类型: 未捕获 ObjC 异常\n异常名: %@\n原因: %@\n\n调用栈:\n%@\n",
            [NSDate date], ts, exception.name ?: @"(未知)", exception.reason ?: @"(无原因)", stack];
        [content writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil];
    } @catch (NSException *e) {
        // 崩溃现场写日志失败则放弃，绝不二次崩溃
    }

    if (gDYPlusPreviousExceptionHandler) {
        gDYPlusPreviousExceptionHandler(exception);
    }
}

@implementation DYPlusCrashCatcher

+ (void)install {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        // 先迁移旧文件再清理，保证首启迁移来的日志也受 3 份上限约束
        [DYPlusPaths runLegacyMigrationIfNeeded];

        // 准备目录 + 缓存 C 路径 + 清理旧日志
        NSString *dir = DYPlusCrashLogDirectory();
        if (dir.fileSystemRepresentation) {
            strlcpy(gDYPlusCrashDirPath, dir.fileSystemRepresentation, sizeof(gDYPlusCrashDirPath));
        }
        DYPlusCleanupOldCrashLogs();

        // 链式保存旧异常处理器
        gDYPlusPreviousExceptionHandler = NSGetUncaughtExceptionHandler();
        NSSetUncaughtExceptionHandler(&DYPlusUncaughtExceptionHandler);

        // 安装信号处理器（保存旧处理器链）
        int signals[] = { SIGABRT, SIGSEGV, SIGBUS, SIGILL, SIGFPE, SIGTRAP };
        for (size_t i = 0; i < sizeof(signals) / sizeof(signals[0]); i++) {
            int sig = signals[i];
            void (*old)(int) = signal(sig, DYPlusSignalHandler);
            if (old != SIG_ERR && old != SIG_IGN) {
                gDYPlusOldSignalHandlers[sig] = old;
            }
        }

        NSLog(@"[DYYY] 崩溃日志抓取已安装, 目录: %@", dir);
    });
}

+ (NSArray<NSString *> *)savedLogFilePaths {
    NSString *dir = DYPlusCrashLogDirectory();
    NSArray<NSString *> *files = DYPlusCrashLogNames(dir);
    NSArray<NSString *> *sorted = [files sortedArrayUsingComparator:^NSComparisonResult(NSString *a, NSString *b) {
        return [a compare:b];
    }];
    NSMutableArray<NSString *> *paths = [NSMutableArray array];
    for (NSString *name in sorted) {
        [paths addObject:[dir stringByAppendingPathComponent:name]];
    }
    return paths;
}

@end

// 尽早安装（constructor 阶段，早于 Logos %ctor 的用户态初始化顺序不可保证，
// 但本安装与 DYYYFloatClearButton 的 SIGSEGV SIG_IGN 冲突已移除，故互不覆盖）
__attribute__((constructor)) static void DYPlusCrashCatcherAutoInstall(void) {
    @autoreleasepool {
        [DYPlusCrashCatcher install];
    }
}
