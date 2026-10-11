//
//  DYPlusSettingViewControllerBackup.m
//  DYYY
//
//  清理缓存、备份/恢复设置、ABTest 配置管理。
//

#import "Settings/DYPlusSettingViewController.h"
#import "Settings/DYPlusSettingsPreferences.h"
#import "Settings/DYPlusSettingViewControllerPrivate.h"
#import "Services/Media/DYPlusManager.h"
#import "UI/Components/DYPlusBottomAlertView.h"
#import "Core/Utilities/DYPlusUtils.h"
#import "Core/Storage/DYPlusPaths.h"
#import "Integration/System/DYPlusABTestHook.h"
#import "Core/Storage/DYPlusSettingsArchive.h"
#import "Core/Network/DYPlusRemoteConfiguration.h"

static dispatch_queue_t DYPlusSettingsIOQueue(void) {
    static dispatch_queue_t queue;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ queue = dispatch_queue_create("com.xiaolegun.dyplus.settings-io", DISPATCH_QUEUE_SERIAL); });
    return queue;
}

@class AWESettingItemModel;

// 添加备份选择器代理
@interface DYPlusBackupPickerDelegate : NSObject <UIDocumentPickerDelegate>
@property (nonatomic, copy) void (^completionBlock)(NSURL *url);
@end

// 实现备份选择器代理
@implementation DYPlusBackupPickerDelegate
- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    if (urls.count > 0) {
        if (self.completionBlock) {
            self.completionBlock(urls.firstObject);
        }
    }
}

@end

@implementation DYPlusSettingViewController (Backup)



- (void)handleCleanCache {
    [DYPlusBottomAlertView showAlertWithTitle:@"清理插件临时文件"
        message:@"只清理 DouYinPlus 的 Temp 目录，不清理抖音缓存、备份或图标。请等待下载和合成任务结束后操作。"
        cancelButtonText:@"取消" confirmButtonText:@"清理" cancelAction:nil confirmAction:^{
        if (![self beginSettingsIO]) return;
        dispatch_async(DYPlusSettingsIOQueue(), ^{
            NSUInteger size = [DYPlusUtils clearDirectoryContents:[DYPlusPaths tempDir]];
            dispatch_async(dispatch_get_main_queue(), ^{
                [self finishSettingsIO];
                [DYPlusManager showToast:[NSString stringWithFormat:@"已清理 %.2f MB 插件临时文件", size / 1048576.0]];
            });
        });
    }];
}

- (BOOL)beginSettingsIO {
    if (self.settingsIOBusy) { [DYPlusManager showToast:@"正在处理设置文件，请稍候"]; return NO; }
    self.settingsIOBusy = YES;
    self.tableView.userInteractionEnabled = NO;
    [DYPlusManager showToast:@"正在处理设置文件…"];
    return YES;
}

- (void)finishSettingsIO {
    self.settingsIOBusy = NO;
    self.tableView.userInteractionEnabled = YES;
}



- (void)backupSettings {
    if (![self beginSettingsIO]) return;
    dispatch_async(DYPlusSettingsIOQueue(), ^{
        @autoreleasepool {
            NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
            NSMutableDictionary *preferences = [NSMutableDictionary dictionary];
            for (NSString *key in defaults.dictionaryRepresentation) {
                if ([key hasPrefix:@"DYYY"] && ![key isEqualToString:@"DYYYIconsBase64"])
                    preferences[key] = [defaults objectForKey:key];
            }
            NSError *error = nil;
            NSMutableDictionary *icons = [NSMutableDictionary dictionary];
            for (NSString *name in DYPlusSettingsArchive.allowedIconNames) {
                NSString *path = [[DYPlusPaths iconsDir] stringByAppendingPathComponent:name];
                NSDictionary *attributes = [NSFileManager.defaultManager attributesOfItemAtPath:path error:nil];
                if (!attributes) continue;
                if (![attributes[NSFileType] isEqual:NSFileTypeRegular]) {
                    error = [NSError errorWithDomain:@"DYPlus.Backup" code:1 userInfo:@{NSLocalizedDescriptionKey:@"图标必须是普通文件"}];
                    break;
                }
                NSData *data = [DYPlusSettingsArchive readFileURL:[NSURL fileURLWithPath:path] error:&error];
                if (!data) break;
                icons[name] = data;
            }
            NSData *json = error ? nil : [DYPlusSettingsArchive encodePreferences:preferences icons:icons error:&error];
            NSString *directory = [DYPlusPaths backupDir];
            NSDateFormatter *formatter = [NSDateFormatter new];
            formatter.dateFormat = @"yyyyMMdd_HHmmss_SSS";
            NSString *name = [NSString stringWithFormat:@"DYPlus_Backup_%@.json", [formatter stringFromDate:NSDate.date]];
            BOOL success = json && [NSFileManager.defaultManager createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:&error]
                && [json writeToFile:[directory stringByAppendingPathComponent:name] options:NSDataWritingAtomic error:&error];
            dispatch_async(dispatch_get_main_queue(), ^{
                [self finishSettingsIO];
                [DYPlusManager showToast:success ? [NSString stringWithFormat:@"备份成功：%@", name]
                    : [NSString stringWithFormat:@"备份失败：%@", error.localizedDescription ?: @"无法写入文件"]];
            });
        }
    });
}

- (void)restoreSettings {
    if (self.settingsIOBusy) return;
    UIDocumentPickerViewController *picker = [[UIDocumentPickerViewController alloc] initWithDocumentTypes:@[@"public.json"] inMode:UIDocumentPickerModeImport];
    picker.allowsMultipleSelection = NO;
    picker.directoryURL = [NSURL fileURLWithPath:[DYPlusPaths backupDir] isDirectory:YES];
    self.restorePickerDelegate = [DYPlusBackupPickerDelegate new];
    __weak typeof(self) weakSelf = self;
    self.restorePickerDelegate.completionBlock = ^(NSURL *url) {
        __strong typeof(weakSelf) controller = weakSelf;
        if (!controller || ![controller beginSettingsIO]) return;
        dispatch_async(DYPlusSettingsIOQueue(), ^{
            NSError *error = nil;
            NSData *data = [DYPlusSettingsArchive readFileURL:url error:&error];
            DYPlusSettingsArchive *archive = data ? [DYPlusSettingsArchive decodeData:data error:&error] : nil;
            dispatch_async(dispatch_get_main_queue(), ^{
                [controller finishSettingsIO];
                if (!archive) {
                    [DYPlusManager showToast:[NSString stringWithFormat:@"恢复失败：%@", error.localizedDescription ?: @"文件格式无效"]];
                    return;
                }
                UIAlertController *confirm = [UIAlertController alertControllerWithTitle:@"恢复插件设置"
                    message:[NSString stringWithFormat:@"将覆盖备份中的 %lu 项设置和 %lu 个图标。仅从可信来源恢复；抖音自身设置不会被修改。", (unsigned long)archive.preferences.count, (unsigned long)archive.icons.count]
                    preferredStyle:UIAlertControllerStyleAlert];
                [confirm addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
                [confirm addAction:[UIAlertAction actionWithTitle:@"恢复" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
                    if (![controller beginSettingsIO]) return;
                    dispatch_async(DYPlusSettingsIOQueue(), ^{
                        NSError *applyError = nil;
                        BOOL success = [archive applyToDefaults:NSUserDefaults.standardUserDefaults iconsDirectory:DYPlusPaths.iconsDir error:&applyError];
                        if (success) {
                            [DYPlusSettingsPreferences migrateLegacyOptions];
                            DYPlusConfigCacheInvalidate();
                        }
                        dispatch_async(dispatch_get_main_queue(), ^{
                            [controller finishSettingsIO];
                            [controller.tableView reloadData];
                            [DYPlusManager showToast:success ? @"设置已恢复，请重启应用以应用所有更改"
                                : [NSString stringWithFormat:@"恢复失败：%@", applyError.localizedDescription ?: @"无法写入"]];
                        });
                    });
                }]];
                [controller presentViewController:confirm animated:YES completion:nil];
            });
        });
    };
    picker.delegate = self.restorePickerDelegate;
    [self presentViewController:picker animated:YES completion:nil];
}

#pragma mark - ABTest 配置

// 添加图标按钮点击处理方法
- (void)saveCurrentABTestData {
    NSDictionary *snapshot = [getCurrentABTestData() copy];
    if (![snapshot isKindOfClass:NSDictionary.class]) { [DYPlusManager showToast:@"无法获取 ABTest 配置"]; return; }
    if (![self beginSettingsIO]) return;
    dispatch_async(DYPlusSettingsIOQueue(), ^{
        NSError *error = nil;
        NSData *data = [NSJSONSerialization dataWithJSONObject:snapshot options:NSJSONWritingPrettyPrinted error:&error];
        NSString *directory = [DYPlusPaths abTestDir];
        BOOL success = data && DYPlusDecodeRemoteConfiguration(data, &error)
            && [NSFileManager.defaultManager createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:&error]
            && [data writeToFile:[directory stringByAppendingPathComponent:@"abtest_config.json"] options:NSDataWritingAtomic error:&error];
        dispatch_async(dispatch_get_main_queue(), ^{
            [self finishSettingsIO];
            [DYPlusManager showToast:success ? @"ABTest 配置已保存" : [NSString stringWithFormat:@"保存失败：%@", error.localizedDescription ?: @"无法写入"]];
        });
    });
}

- (void)loadABTestConfigFile {
    UIDocumentPickerViewController *picker = [[UIDocumentPickerViewController alloc] initWithDocumentTypes:@[@"public.json"] inMode:UIDocumentPickerModeImport];
    self.restorePickerDelegate = [DYPlusBackupPickerDelegate new];
    picker.delegate = self.restorePickerDelegate;
    picker.allowsMultipleSelection = NO;
    
    __weak typeof(self) weakSelf = self;
    self.restorePickerDelegate.completionBlock = ^(NSURL *url) {
        [weakSelf processABTestConfigFile:url];
    };
    
    [self presentViewController:picker animated:YES completion:nil];
}

- (void)processABTestConfigFile:(NSURL *)url {
    if (![self beginSettingsIO]) return;
    dispatch_async(DYPlusSettingsIOQueue(), ^{
        NSError *error = nil;
        NSData *data = [DYPlusSettingsArchive readFileURL:url error:&error];
        NSDictionary *configuration = data ? DYPlusDecodeRemoteConfiguration(data, &error) : nil;
        dispatch_async(dispatch_get_main_queue(), ^{
            [self finishSettingsIO];
            if (!configuration) { [DYPlusManager showToast:error.localizedDescription ?: @"配置无效"]; return; }
            UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"应用 ABTest 配置"
                message:@"仅应用可信来源的配置。该操作会改变抖音实验功能，插件无法保证每项实验兼容当前抖音版本。"
                preferredStyle:UIAlertControllerStyleAlert];
            [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
            [alert addAction:[UIAlertAction actionWithTitle:@"应用" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
                Class managerClass = NSClassFromString(@"AWEABTestManager");
                if (![managerClass respondsToSelector:@selector(sharedManager)]) { [DYPlusManager showToast:@"当前版本不支持 ABTest 管理器"]; return; }
                id manager = [managerClass performSelector:@selector(sharedManager)];
                if ([manager respondsToSelector:@selector(setAbTestData:)]) {
                    [manager performSelector:@selector(setAbTestData:) withObject:configuration];
                    [DYPlusManager showToast:@"已请求应用配置；最终结果取决于当前锁定模式与抖音版本"];
                } else [DYPlusManager showToast:@"当前版本不支持应用 ABTest 配置"];
            }]];
            [self presentViewController:alert animated:YES completion:nil];
        });
    });
}

- (void)deleteABTestConfigFile {
    NSString *dyplusFolderPath = [DYPlusPaths abTestDir];
    NSString *jsonFilePath = [dyplusFolderPath stringByAppendingPathComponent:@"abtest_data_fixed.json"];
    
    NSFileManager *fileManager = [NSFileManager defaultManager];
    if ([fileManager fileExistsAtPath:jsonFilePath]) {
        NSError *error = nil;
        [fileManager removeItemAtPath:jsonFilePath error:&error];
        
        if (!error) {
            DYPlusInvalidateABTestData();
            [DYPlusManager showToast:@"ABTest配置文件已删除"];
        } else {
            [DYPlusManager showToast:[NSString stringWithFormat:@"删除配置文件失败: %@", error.localizedDescription]];
        }
    } else {
        [DYPlusManager showToast:@"没有找到ABTest配置文件"];
    }
}

@end
