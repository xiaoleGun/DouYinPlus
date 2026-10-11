#import "Core/Storage/DYPlusPaths.h"
#import <sys/stat.h>

@implementation DYPlusPaths

+ (NSString *)documentsDir {
    return NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
}

+ (NSString *)dyplusRootDir {
    return [[self documentsDir] stringByAppendingPathComponent:@"DYYY"];
}

+ (NSString *)iconsDir {
    return [[self dyplusRootDir] stringByAppendingPathComponent:@"Icons"];
}

+ (NSString *)abTestDir {
    return [[self dyplusRootDir] stringByAppendingPathComponent:@"ABTest"];
}

+ (NSString *)backupDir {
    return [[self dyplusRootDir] stringByAppendingPathComponent:@"Backup"];
}

+ (NSString *)tempDir {
    return [[self dyplusRootDir] stringByAppendingPathComponent:@"Temp"];
}

+ (NSString *)logsDir {
    return [[self dyplusRootDir] stringByAppendingPathComponent:@"Logs"];
}

#pragma mark - 旧文件一次性迁移（幂等 move，失败留原地由读取侧回退）

static void DYPlusMigrateFile(NSString *oldPath, NSString *newPath) {
    NSFileManager *fm = [NSFileManager defaultManager];
    if ([fm fileExistsAtPath:oldPath] && ![fm fileExistsAtPath:newPath]) {
        [fm moveItemAtPath:oldPath toPath:newPath error:nil];
    }
}

// 目录内全部文件迁移（成功后删除空旧目录）
static void DYPlusMigrateDirectoryContents(NSString *oldDir, NSString *newDir) {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSArray<NSString *> *files = [fm contentsOfDirectoryAtPath:oldDir error:nil];
    for (NSString *name in files) {
        DYPlusMigrateFile([oldDir stringByAppendingPathComponent:name],
                        [newDir stringByAppendingPathComponent:name]);
    }
    // 空目录清理
    NSArray<NSString *> *remaining = [fm contentsOfDirectoryAtPath:oldDir error:nil];
    if (remaining.count == 0) {
        [fm removeItemAtPath:oldDir error:nil];
    }
}

static void DYPlusMigrateLegacyFiles(void) {
    NSFileManager *fm = [NSFileManager defaultManager];
    for (NSString *dir in @[[DYPlusPaths dyplusRootDir], [DYPlusPaths iconsDir], [DYPlusPaths abTestDir],
                            [DYPlusPaths backupDir], [DYPlusPaths tempDir], [DYPlusPaths logsDir]]) {
        [fm createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
    }

    NSString *doc = [DYPlusPaths documentsDir];
    NSString *root = [DYPlusPaths dyplusRootDir];
    NSString *logs = [DYPlusPaths logsDir];

    // 逆向助手数据库：Documents 根 → Logs/（平铺）
    DYPlusMigrateFile([doc stringByAppendingPathComponent:@"iosnixiangzhushoutest.sqlite"],
                    [logs stringByAppendingPathComponent:@"iosnixiangzhushoutest.sqlite"]);

    // 崩溃日志：旧 CrashLogs/ 目录 → Logs/（平铺）
    DYPlusMigrateDirectoryContents([root stringByAppendingPathComponent:@"CrashLogs"], logs);

    // 图标/头像：DYYY 根 → Icons/
    for (NSString *name in @[@"like_before.png", @"like_after.png", @"comment.png",
                             @"unfavorite.png", @"favorite.png", @"share.png",
                             @"qingping.png", @"custom_album_image.png"]) {
        DYPlusMigrateFile([root stringByAppendingPathComponent:name],
                        [[DYPlusPaths iconsDir] stringByAppendingPathComponent:name]);
    }

    // ABTest 配置：DYYY 根 → ABTest/
    for (NSString *name in @[@"abtest_data_fixed.json", @"abtest_config.json"]) {
        DYPlusMigrateFile([root stringByAppendingPathComponent:name],
                        [[DYPlusPaths abTestDir] stringByAppendingPathComponent:name]);
    }

    // 设置备份：DYYY 根 DYYY_Backup_*.json → Backup/
    NSArray<NSString *> *rootFiles = [fm contentsOfDirectoryAtPath:root error:nil];
    for (NSString *name in rootFiles) {
        if ([name hasPrefix:@"DYYY_Backup_"] && [name.pathExtension isEqualToString:@"json"]) {
            DYPlusMigrateFile([root stringByAppendingPathComponent:name],
                            [[DYPlusPaths backupDir] stringByAppendingPathComponent:name]);
        }
    }
}

__attribute__((constructor)) static void DYPlusPathsMigrateOnLaunch(void) {
    @autoreleasepool {
        [DYPlusPaths runLegacyMigrationIfNeeded];
    }
}

+ (void)runLegacyMigrationIfNeeded {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        DYPlusMigrateLegacyFiles();
    });
}

@end
