#import "Core/Runtime/DYPlusRuntime.h"
#import "Settings/DYPlusSettingViewControllerActions.h"
#import "Settings/DYPlusBranding.h"
#import "Settings/DYPlusSettingsPreferences.h"
#import "Settings/DYPlusSettingViewControllerPrivate.h"
#import "Settings/DYPlusSettingItem.h"
#import "Settings/DYPlusSettingUIComponents.h"
#import "Services/Media/DYPlusManager.h"
#import "UI/Components/DYPlusBottomAlertView.h"
#import "Core/Utilities/DYPlusUtils.h"
#import "Integration/Playback/DYPlusFloatSpeedButton.h"
#import "Services/Preferences/DYPlusSwitchManager.h"
#import "Integration/System/DYPlusABTestHook.h"
#import "Diagnostics/DYPlusSelfTest.h"
#import "Core/Storage/DYPlusPaths.h"
#import "UI/Components/DYPlusFilterSettingsView.h"
#import <Photos/Photos.h>
#import <objc/runtime.h>
#import <math.h>

@interface DYPlusImagePickerDelegate : NSObject <UIImagePickerControllerDelegate, UINavigationControllerDelegate>
@property (nonatomic, copy) void (^completionBlock)(NSDictionary *info);
@end

@interface DYPlusSettingViewController ()
- (void)handleCleanCache;
- (void)backupSettings;
- (void)restoreSettings;
- (void)showColorPicker;
- (void)showImagePickerForCustomAlbum;
- (NSArray<NSIndexPath *> *)rowsForSection:(NSInteger)section;
@end

@implementation DYPlusSettingViewController (Actions)

- (void)iconButtonTapped:(UIButton *)sender {
    NSInteger tag = sender.tag;
    NSInteger section = tag / 1000;
    NSInteger row = tag % 1000;
    
    NSArray<DYPlusSettingItem *> *visibleItems = [self visibleItemsForSection:section];
    if (row >= visibleItems.count) {
        return;
    }
    
    DYPlusSettingItem *item = visibleItems[row];
    
    NSString *saveFilename = nil;
    if ([item.key isEqualToString:@"DYYYIconLikeBefore"]) {
        saveFilename = @"like_before.png";
    } else if ([item.key isEqualToString:@"DYYYIconLikeAfter"]) {
        saveFilename = @"like_after.png";
    } else if ([item.key isEqualToString:@"DYYYIconComment"]) {
        saveFilename = @"comment.png";
    } else if ([item.key isEqualToString:@"DYYYIconUnfavorite"]) {
        saveFilename = @"unfavorite.png";
    } else if ([item.key isEqualToString:@"DYYYIconFavorite"]) {
        saveFilename = @"favorite.png";
    } else if ([item.key isEqualToString:@"DYYYIconShare"]) {
        saveFilename = @"share.png";
    }
    
    if (saveFilename) {
        NSString *dyplusFolderPath = [DYPlusPaths iconsDir];
        NSString *imagePath = [dyplusFolderPath stringByAppendingPathComponent:saveFilename];
        
        BOOL fileExists = [[NSFileManager defaultManager] fileExistsAtPath:imagePath];
        UIImage *previewImage = fileExists ? [UIImage imageWithContentsOfFile:imagePath] : nil;
        
        // 显示图标选择弹窗
        [self showIconOptionsDialogWithTitle:item.title previewImage:previewImage saveFilename:saveFilename];
    }
}

// 添加热更新功能实现方法

- (void)animatedSwitchToggled:(UISwitch *)sender { [self switchToggled:sender]; }

- (void)tableView:(UITableView *)tableView willDisplayCell:(UITableViewCell *)cell forRowAtIndexPath:(NSIndexPath *)indexPath { cell.layer.mask = nil; }

#pragma mark - UITableViewDelegate

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    if (!self.isCategoryPage && !self.isSearching) {
        [tableView deselectRowAtIndexPath:indexPath animated:YES];
        if (indexPath.section == 0) [self openCategoryAtIndex:indexPath.row];
        else [self showAboutPage];
        return;
    }
    if (self.isCategoryPage && !self.isGroupPage && !self.isSearching) {
        [tableView deselectRowAtIndexPath:indexPath animated:YES];
        [self openGroupAtIndex:indexPath.row];
        return;
    }
    NSArray<DYPlusSettingItem *> *visibleItems = [self visibleItemsForSection:indexPath.section];
    if (indexPath.row >= visibleItems.count) {
        [tableView deselectRowAtIndexPath:indexPath animated:YES];
        return;
    }
    
    DYPlusSettingItem *item = visibleItems[indexPath.row];
    
    // 子分组标题行：点击展开/折叠其条目
    if (item.type == DYPlusSettingItemTypeGroupHeader) {
        [self toggleGroupHeaderAtIndexPath:indexPath];
        [tableView deselectRowAtIndexPath:indexPath animated:YES];
        return;
    }
    
    // 添加清理缓存功能处理
    if ([item.key isEqualToString:@"DYYYCleanCache"]) {
        [self handleCleanCache];
        [tableView deselectRowAtIndexPath:indexPath animated:YES];
        return;
    }
    
    // 一键自检功能处理
    if ([item.key isEqualToString:@"DYYYSelfTest"]) {
        [DYPlusSelfTest presentFromViewController:self];
        [tableView deselectRowAtIndexPath:indexPath animated:YES];
        return;
    }
    
    // 添加清除设置功能
    if ([item.key isEqualToString:@"DYYYCleanSettings"]) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:[NSString stringWithFormat:@"重置 %@ 偏好", DYPlusProductName]
            message:@"只清除本插件的设置。建议先备份；抖音账号与其他应用设置会保留。"
            preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
        [alert addAction:[UIAlertAction actionWithTitle:@"重置" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
            NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
            for (NSString *key in defaults.dictionaryRepresentation) {
                if ([key hasPrefix:@"DYYY"]) [defaults removeObjectForKey:key];
            }
            DYPlusConfigCacheInvalidate();
            [self ensureCustomAlbumSizeDefault];
            [DYPlusSettingsPreferences setChoiceValue:0 forKey:@"DYYYDefaultQuality"];
            [self.tableView reloadData];
            [[NSNotificationCenter defaultCenter] postNotificationName:@"DYYYSettingChanged" object:nil userInfo:@{@"key":@"DYYYResetAll"}];
            [DYPlusManager showToast:@"插件偏好已重置，部分功能重启抖音后生效"];
        }]];
        [self presentViewController:alert animated:YES completion:nil];
        [tableView deselectRowAtIndexPath:indexPath animated:YES];
        return;
    }

    // 添加备份设置功能处理
    if ([item.key isEqualToString:@"DYYYBackupSettings"]) {
        [self backupSettings];
        [tableView deselectRowAtIndexPath:indexPath animated:YES];
        return;
    }
    
    // 添加恢复设置功能处理
    if ([item.key isEqualToString:@"DYYYRestoreSettings"]) {
        [self restoreSettings];
        [tableView deselectRowAtIndexPath:indexPath animated:YES];
        return;
    }
    
    // 处理图标自定义项
    if ([item.key hasPrefix:@"DYYYIcon"]) {
        [self handleIconSelection:item];
        [tableView deselectRowAtIndexPath:indexPath animated:YES];
        return;
    }
    
    // 热更新功能处理
    if ([item.key isEqualToString:@"SaveCurrentABTestData"]) {
        [self saveCurrentABTestData];
        [tableView deselectRowAtIndexPath:indexPath animated:YES];
        return;
    } else if ([item.key isEqualToString:@"LoadABTestConfigFile"]) {
        [self loadABTestConfigFile];
        [tableView deselectRowAtIndexPath:indexPath animated:YES];
        return;
    } else if ([item.key isEqualToString:@"DeleteABTestConfigFile"]) {
        [self deleteABTestConfigFile];
        [tableView deselectRowAtIndexPath:indexPath animated:YES];
        return;
    }
    
    if (item.type == DYPlusSettingItemTypeChoice) {
        [self showChoiceForItem:item fromIndexPath:indexPath];
        [tableView deselectRowAtIndexPath:indexPath animated:YES];
        return;
    }

    if (item.type == DYPlusSettingItemTypeSlider) {
        [self showSliderForItem:item fromIndexPath:indexPath];
        [tableView deselectRowAtIndexPath:indexPath animated:YES];
        return;
    }

    if (item.type == DYPlusSettingItemTypeCustomPicker && [item.key isEqualToString:@"DYYYScheduleStyle"]) {
        if (!DYPlusCachedBool(@"DYYYisShowScheduleDisplay")) {
            [DYPlusManager showToast:@"请先开启\"显示进度时长\"选项"];
            return;
        }
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"选择进度条样式"
                                                                       message:nil
                                                                preferredStyle:UIAlertControllerStyleActionSheet];
        NSArray *styles = @[
            @{@"title": @"进度条右侧剩余", @"value": @"进度条右侧剩余"},
            @{@"title": @"进度条右侧完整", @"value": @"进度条右侧完整"},
            @{@"title": @"进度条左侧剩余", @"value": @"进度条左侧剩余"},
            @{@"title": @"进度条左侧完整", @"value": @"进度条左侧完整"},
            @{@"title": @"进度条两侧左右", @"value": @"进度条两侧左右"}
        ];
        for (NSDictionary *style in styles) {
            UIAlertAction *action = [UIAlertAction actionWithTitle:style[@"title"]
                                                             style:UIAlertActionStyleDefault
                                                           handler:^(UIAlertAction * _Nonnull action) {
                [[NSUserDefaults standardUserDefaults] setObject:style[@"value"] forKey:@"DYYYScheduleStyle"];
                DYPlusConfigCacheInvalidate();
                [self.tableView reloadData];
            }];
            [alert addAction:action];
        }
        UIAlertAction *cancelAction = [UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil];
        [alert addAction:cancelAction];
        if (UIDevice.currentDevice.userInterfaceIdiom == UIUserInterfaceIdiomPad) {
            UITableViewCell *selectedCell = [self.tableView cellForRowAtIndexPath:indexPath];
            alert.popoverPresentationController.sourceView = selectedCell;
            alert.popoverPresentationController.sourceRect = selectedCell.bounds;
        }
        [self presentViewController:alert animated:YES completion:nil];
        [tableView deselectRowAtIndexPath:indexPath animated:YES];
        return;
    }
    
    if (item.type == DYPlusSettingItemTypeTextField
        && ![item.key isEqualToString:@"DYYYCustomAlbumImage"]
        && ![item.key isEqualToString:@"DYYYfilterKeywords"]) {
        UIAlertController *editor = [UIAlertController alertControllerWithTitle:item.title
            message:item.placeholder preferredStyle:UIAlertControllerStyleAlert];
        [editor addTextFieldWithConfigurationHandler:^(UITextField *field) {
            id value = [NSUserDefaults.standardUserDefaults objectForKey:item.key];
            field.text = value ? [value description] : @"";
            field.placeholder = item.placeholder;
            field.clearButtonMode = UITextFieldViewModeWhileEditing;
        }];
        [editor addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
        [editor addAction:[UIAlertAction actionWithTitle:@"保存" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
            UITextField *field = editor.textFields.firstObject;
            field.tag = indexPath.section * 1000 + indexPath.row;
            [self textFieldDidChange:field];
            [self.tableView reloadData];
        }]];
        [self presentViewController:editor animated:YES completion:nil];
        [tableView deselectRowAtIndexPath:indexPath animated:YES];
        return;
    }
    if ([item.key isEqualToString:@"DYYYCustomAlbumImage"]) {
        [self showImagePickerForCustomAlbum];
        return;
    }

    if (item.type == DYPlusSettingItemTypeSpeedPicker) {
        [self showSpeedPickerForItem:item fromIndexPath:indexPath];
    } else if (item.type == DYPlusSettingItemTypeColorPicker) {
        [self showColorPicker];
    } else if ([item.key isEqualToString:@"DYYYfilterKeywords"]) {
        // 获取当前已保存的关键词
        NSString *currentKeywords = DYPlusPreferenceString(@"DYYYfilterKeywords");
        
        // 创建并显示过滤设置视图
        DYPlusFilterSettingsView *filterView = [[DYPlusFilterSettingsView alloc] initWithTitle:@"设置过滤关键词" text:currentKeywords];
        [filterView showWithConfirmBlock:^(NSString *selectedText) {
            [[NSUserDefaults standardUserDefaults] setObject:selectedText forKey:@"DYYYfilterKeywords"];
            [[NSUserDefaults standardUserDefaults] synchronize];
            [self.tableView reloadData];
        } cancelBlock:nil];
    }
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
}

- (void)handleIconSelection:(DYPlusSettingItem *)item {
    NSString *saveFilename = nil;
    
    // 映射图标类型到文件名
    if ([item.key isEqualToString:@"DYYYIconLikeBefore"]) {
        saveFilename = @"like_before.png";
    } else if ([item.key isEqualToString:@"DYYYIconLikeAfter"]) {
        saveFilename = @"like_after.png";
    } else if ([item.key isEqualToString:@"DYYYIconComment"]) {
        saveFilename = @"comment.png";
    } else if ([item.key isEqualToString:@"DYYYIconUnfavorite"]) {
        saveFilename = @"unfavorite.png";
    } else if ([item.key isEqualToString:@"DYYYIconFavorite"]) {
        saveFilename = @"favorite.png";
    } else if ([item.key isEqualToString:@"DYYYIconShare"]) {
        saveFilename = @"share.png";
    }
    
    if (saveFilename) {
        // 获取图标路径
        NSString *dyplusFolderPath = [DYPlusPaths iconsDir];
        NSString *imagePath = [dyplusFolderPath stringByAppendingPathComponent:saveFilename];
        
        // 检查是否已有自定义图标
        BOOL fileExists = [[NSFileManager defaultManager] fileExistsAtPath:imagePath];
        UIImage *previewImage = fileExists ? [UIImage imageWithContentsOfFile:imagePath] : nil;
        
        // 显示图标选项对话框
        [self showIconOptionsDialogWithTitle:item.title previewImage:previewImage saveFilename:saveFilename];
    }
}

// 添加这个辅助方法
- (void)showIconOptionsDialogWithTitle:(NSString *)title previewImage:(UIImage *)previewImage saveFilename:(NSString *)saveFilename {
    DYPlusIconOptionsDialogView *optionsDialog = [[DYPlusIconOptionsDialogView alloc] initWithTitle:title previewImage:previewImage];
    
    // 确保DYYY文件夹存在
    NSString *dyplusFolderPath = [DYPlusPaths iconsDir];
    NSString *imagePath = [dyplusFolderPath stringByAppendingPathComponent:saveFilename];
    
    if (![[NSFileManager defaultManager] fileExistsAtPath:dyplusFolderPath]) {
        [[NSFileManager defaultManager] createDirectoryAtPath:dyplusFolderPath withIntermediateDirectories:YES attributes:nil error:nil];
    }
    
    __weak typeof(self) weakSelf = self;
    
    // 设置清除按钮回调
    optionsDialog.onClear = ^{
        if ([[NSFileManager defaultManager] fileExistsAtPath:imagePath]) {
            NSError *error = nil;
            [[NSFileManager defaultManager] removeItemAtPath:imagePath error:&error];
            if (!error) {
                [DYPlusManager showToast:@"已恢复默认图标"];
                [weakSelf.tableView reloadData];
            }
        }
    };
    
    // 设置选择按钮回调
    optionsDialog.onSelect = ^{
        UIImagePickerController *picker = [[UIImagePickerController alloc] init];
        picker.sourceType = UIImagePickerControllerSourceTypePhotoLibrary;
        picker.allowsEditing = NO;
        picker.mediaTypes = @[@"public.image"];
        DYPlusImagePickerDelegate *pickerDelegate = [[DYPlusImagePickerDelegate alloc] init];
        pickerDelegate.completionBlock = ^(NSDictionary *info) {
            NSURL *imageURL = info[UIImagePickerControllerImageURL];
            if (!imageURL) {
                imageURL = info[UIImagePickerControllerReferenceURL];
            }
            
            if (imageURL) {
                NSData *imageData = [NSData dataWithContentsOfURL:imageURL];
                if (imageData) {
                    // 检测是否为GIF
                    const char *bytes = (const char *)imageData.bytes;
                    BOOL isGIF = (imageData.length >= 6 && (memcmp(bytes, "GIF87a", 6) == 0 || memcmp(bytes, "GIF89a", 6) == 0));
                    
                    if (isGIF) {
                        [imageData writeToFile:imagePath atomically:YES];
                    } else {
                        UIImage *selectedImage = [UIImage imageWithData:imageData];
                        NSData *pngData = UIImagePNGRepresentation(selectedImage);
                        [pngData writeToFile:imagePath atomically:YES];
                    }
                    
                    [DYPlusManager showToast:@"图标已设置，重启应用生效"];
                    [weakSelf.tableView reloadData];
                }
            }
        };
        
        static char kDYPlusPickerDelegateKey;
        picker.delegate = pickerDelegate;
        objc_setAssociatedObject(picker, &kDYPlusPickerDelegateKey, pickerDelegate, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [weakSelf presentViewController:picker animated:YES completion:nil];
    };
    
    [optionsDialog show];
}

- (void)showChoiceForItem:(DYPlusSettingItem *)item fromIndexPath:(NSIndexPath *)indexPath {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:item.title
                                                                   message:nil
                                                            preferredStyle:UIAlertControllerStyleActionSheet];
    [item.options enumerateObjectsUsingBlock:^(NSString *option, NSUInteger index, BOOL *stop) {
        [alert addAction:[UIAlertAction actionWithTitle:option
                                                  style:UIAlertActionStyleDefault
                                                handler:^(UIAlertAction *action) {
            [DYPlusSettingsPreferences setChoiceValue:(NSInteger)index forKey:item.key];
            [[NSUserDefaults standardUserDefaults] synchronize];
            [self.tableView reloadData];
        }]];
    }];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    if (UIDevice.currentDevice.userInterfaceIdiom == UIUserInterfaceIdiomPad) {
        UITableViewCell *selectedCell = [self.tableView cellForRowAtIndexPath:indexPath];
        alert.popoverPresentationController.sourceView = selectedCell;
        alert.popoverPresentationController.sourceRect = selectedCell.bounds;
    }
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)showSliderForItem:(DYPlusSettingItem *)item fromIndexPath:(NSIndexPath *)indexPath {
    NSNumber *stored = [[NSUserDefaults standardUserDefaults] objectForKey:item.key];
    NSInteger value = stored ? stored.integerValue : item.defaultInteger;
    if (value < 0) value = 0;
    if (value > 100) value = 100;

    DYPlusSliderViewController *sliderController =
        [[DYPlusSliderViewController alloc] initWithTitle:item.title
                                                  value:value
                                             completion:^(NSInteger percent) {
        if (percent < 0) percent = 0;
        if (percent > 100) percent = 100;
        [[NSUserDefaults standardUserDefaults] setInteger:percent forKey:item.key];
        [[NSUserDefaults standardUserDefaults] synchronize];
        [[NSNotificationCenter defaultCenter] postNotificationName:@"DYYYSettingChanged"
                                                            object:nil
                                                          userInfo:@{@"key": item.key, @"value": @(percent)}];
        [self.tableView reloadRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationFade];
                                             }];
    [self presentViewController:sliderController animated:YES completion:nil];
}

- (void)showSpeedPickerForItem:(DYPlusSettingItem *)item fromIndexPath:(NSIndexPath *)indexPath {
    if (item.key.length == 0) return;
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"选择倍速"
                                                                   message:nil
                                                            preferredStyle:UIAlertControllerStyleActionSheet];
    
    NSArray *speeds = @[@0.75, @1.0, @1.25, @1.5, @2.0, @2.5, @3.0];
    for (NSNumber *speed in speeds) {
        UIAlertAction *action = [UIAlertAction actionWithTitle:[NSString stringWithFormat:@"%.2f", speed.floatValue]
                                                         style:UIAlertActionStyleDefault
                                                       handler:^(UIAlertAction * _Nonnull action) {
            [[NSUserDefaults standardUserDefaults] setFloat:speed.floatValue forKey:item.key];
            [[NSUserDefaults standardUserDefaults] synchronize];
            NSIndexPath *visiblePath = [self visibleIndexPathForSettingKey:item.key] ?: indexPath;
            if (visiblePath && visiblePath.section < [self.tableView numberOfSections] &&
                visiblePath.row < [self.tableView numberOfRowsInSection:visiblePath.section]) {
                [self.tableView reloadRowsAtIndexPaths:@[visiblePath]
                                      withRowAnimation:UITableViewRowAnimationFade];
            }
        }];
        [alert addAction:action];
    }
    
    UIAlertAction *cancelAction = [UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil];
    [alert addAction:cancelAction];
    
    if (UIDevice.currentDevice.userInterfaceIdiom == UIUserInterfaceIdiomPad) {
        UITableViewCell *selectedCell = [self.tableView cellForRowAtIndexPath:[self.tableView indexPathForSelectedRow]];
        alert.popoverPresentationController.sourceView = selectedCell;
        alert.popoverPresentationController.sourceRect = selectedCell.bounds;
    }
    
    [self presentViewController:alert animated:YES completion:nil];
}

#pragma mark - Actions

- (void)switchToggled:(UISwitch *)sender {
    // 添加防崩溃检查
    if (!sender) {
        return;
    }
    
    NSInteger section = sender.tag / 1000;
    NSInteger row = sender.tag % 1000;

    NSArray<DYPlusSettingItem *> *visibleItems = [self visibleItemsForSection:section];
    if (row < 0 || row >= visibleItems.count) {
        return;
    }

    DYPlusSettingItem *item = visibleItems[row];
    if (!item) {
        return;
    }

    // 使用开关管理器处理切换逻辑
    [[DYPlusSwitchManager sharedManager] handleSwitchToggled:sender 
                                                  withItem:item 
                                                   section:section 
                                                       row:row
                                                 tableView:self.tableView
                                          settingSections:self.settingSections];

    // 触觉反馈
    [self.tableView reloadData];
    [self.feedbackGenerator impactOccurred];

    // 进度时长依赖处理
    if ([item.key isEqualToString:@"DYYYisShowScheduleDisplay"]) {
        // 关闭时，清空样式设置
        if (!sender.isOn) {
            [[NSUserDefaults standardUserDefaults] removeObjectForKey:@"DYYYScheduleStyle"];
        }
        // 刷新相关cell
        NSIndexPath *stylePath = [self visibleIndexPathForSettingKey:@"DYYYScheduleStyle"];
        if (stylePath) {
            [self.tableView reloadRowsAtIndexPaths:@[stylePath]
                                  withRowAnimation:UITableViewRowAnimationAutomatic];
        }
    }

    // 安全地同步设置
    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSUserDefaults standardUserDefaults] synchronize];
    });
}

- (void)updateClearButtonSubSwitchesUI:(NSInteger)section enabled:(BOOL)enabled {
    NSArray<NSString *> *subKeys = @[
        @"DYYYHideDanmaku",
        @"DYYYEnabshijianjindu", 
        @"DYYYHideTimeProgress",
        @"DYYYHideSlider",
        @"DYYYHideTabBar",
        @"DYYYHideSpeed"
    ];
    
    // 使用 DYYYSwitchManager 的方法
    [[DYPlusSwitchManager sharedManager] updateSubSwitchesInSection:section 
                                                         withKeys:subKeys 
                                                          enabled:enabled 
                                                        tableView:self.tableView 
                                                 settingSections:self.settingSections];
}

- (void)updateLongPressSubSwitchesUI:(NSInteger)section enabled:(BOOL)enabled {
    NSArray<NSString *> *subKeys = @[
        @"DYYYLongPressSaveVideo",
        @"DYYYLongPressSaveAudio",
        @"DYYYEnableFLEX",
        @"DYYYLongPressSaveCurrentImage",
        @"DYYYLongPressSaveAllImages",
        @"DYYYLongPressCopyLink",
        @"DYYYLongPressApiDownload",
        @"DYYYLongPressFilterUser",
        @"DYYYLongPressFilterTitle",
        @"DYYYLongPressTimerClose",
        @"DYYYLongPressCreateVideo"
    ];
    
    // 使用 DYYYSwitchManager 的方法
    [[DYPlusSwitchManager sharedManager] updateSubSwitchesInSection:section 
                                                         withKeys:subKeys 
                                                          enabled:enabled 
                                                        tableView:self.tableView 
                                                 settingSections:self.settingSections];
}

- (void)textFieldDidChange:(UITextField *)textField {
    NSIndexPath *indexPath = [NSIndexPath indexPathForRow:textField.tag % 1000 inSection:textField.tag / 1000];
    NSArray<DYPlusSettingItem *> *visibleItems = [self visibleItemsForSection:indexPath.section];
    if (indexPath.row >= visibleItems.count) {
        return;
    }
    
    DYPlusSettingItem *item = visibleItems[indexPath.row];
    
    // 添加对链接解析接口的特殊处理
    if ([item.key isEqualToString:@"DYYYInterfaceDownload"]) {
        NSString *text = [textField.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        if (text.length == 0) {
            textField.text = @"https://api.qsy.ink/api/douyin?key=DYYY&url=";
            [[NSUserDefaults standardUserDefaults] setObject:@"https://api.qsy.ink/api/douyin?key=DYYY&url=" forKey:item.key];
        } else {
            [[NSUserDefaults standardUserDefaults] setObject:textField.text forKey:item.key];
        }
    } 
    // 倍速数值设置的特殊处理
    else if ([item.key isEqualToString:@"DYYYSpeedSettings"]) {
        NSString *speedConfig = textField.text;
        if (speedConfig.length == 0) {
            speedConfig = @"1.0,1.25,1.5,2.0";
            textField.text = speedConfig;
        }
        [[NSUserDefaults standardUserDefaults] setObject:speedConfig forKey:item.key];
        [DYPlusManager showToast:@"倍速选项已更新"];
    }
    // 倍速按钮大小的特殊处理
    else if ([item.key isEqualToString:@"DYYYSpeedButtonSize"]) {
        NSString *sizeStr = textField.text;
        if (sizeStr.length == 0 || [sizeStr floatValue] <= 0) {
            sizeStr = @"40";
            textField.text = sizeStr;
        }
        [[NSUserDefaults standardUserDefaults] setObject:sizeStr forKey:item.key];
        [DYPlusManager showToast:@"倍速按钮大小已更新"];
    } 
    else {
        [[NSUserDefaults standardUserDefaults] setObject:textField.text forKey:item.key];
    }
    
    [[NSUserDefaults standardUserDefaults] synchronize];
    
    // 在设置值保存后添加：
    [[NSNotificationCenter defaultCenter] postNotificationName:@"DYYYSettingChanged" object:nil userInfo:@{
        @"key": item.key,
        @"value": textField.text ?: [NSNull null]
    }];
    
    // 处理特殊键
    if ([item.key isEqualToString:@"DYYYCustomAlbumImage"]) {
        [self showImagePickerForCustomAlbum];
    }
}

- (void)avatarTextFieldDidChange:(UITextField *)textField {
    self.avatarTapLabel.text = textField.text.length > 0 ? textField.text : DYPlusAuthorName;
}

- (void)headerTapped:(UIButton *)sender {
    // 触发触觉反馈
    [self.feedbackGenerator impactOccurred];
    [self.feedbackGenerator prepare];
    
    NSInteger section = sender.tag;
    if (self.isSearching) {
        return; // 搜索模式下分区行恒显示，不参与折叠切换，避免污染普通模式状态
    }
    NSArray<NSArray<DYPlusSettingItem *> *> *sections = self.isSearching ? self.filteredSections : self.settingSections;
    if (section >= sections.count) {
        return;
    }
    
    BOOL isCurrentExpanded = [self.expandedSections containsObject:@(section)];
    
    // 获取所有需要更新的行信息 - 在修改expandedSections之前
    NSMutableArray<NSIndexPath *> *allRowsToUpdate = [NSMutableArray array];
    NSMutableArray<NSNumber *> *sectionsToUpdate = [NSMutableArray array];
    
    // 收集当前要点击的section的所有行
    NSArray<NSIndexPath *> *currentSectionRows = [self rowsForSection:section];
    [allRowsToUpdate addObjectsFromArray:currentSectionRows];
    [sectionsToUpdate addObject:@(section)];
    
    // 如果当前section不是展开的，需要收集其他已展开section的所有行
    if (!isCurrentExpanded) {
        for (NSNumber *expandedSection in [self.expandedSections copy]) {
            if (![expandedSection isEqualToNumber:@(section)]) {
                NSArray<NSIndexPath *> *expandedSectionRows = [self rowsForSection:[expandedSection integerValue]];
                [allRowsToUpdate addObjectsFromArray:expandedSectionRows];
                [sectionsToUpdate addObject:expandedSection];
            }
        }
        
        // 清空已展开sections，只保留当前section
        [self.expandedSections removeAllObjects];
        [self.expandedSections addObject:@(section)];
    } else {
        // 当前section已展开，需要将其关闭
        [self.expandedSections removeObject:@(section)];
    }
    
    // 更新所有涉及的section头部箭头
    for (NSNumber *sectionNumber in sectionsToUpdate) {
        NSInteger sectionIndex = [sectionNumber integerValue];
        UIView *headerView = [self.tableView headerViewForSection:sectionIndex];
        UIButton *headerButton = [headerView viewWithTag:sectionIndex];
        UIImageView *arrow = [headerButton viewWithTag:100];
        
        BOOL shouldBeExpanded = [self.expandedSections containsObject:sectionNumber];
        
        if (@available(iOS 13.0, *)) {
            UIImageSymbolConfiguration *config = [UIImageSymbolConfiguration configurationWithPointSize:17 weight:UIImageSymbolWeightSemibold];
            arrow.image = [[UIImage systemImageNamed:shouldBeExpanded ? @"chevron.down" : @"chevron.right"] imageWithConfiguration:config];
        } else {
            arrow.image = [UIImage systemImageNamed:shouldBeExpanded ? @"chevron.down" : @"chevron.right"];
        }
        
        // 动画过渡效果
        [UIView animateWithDuration:0.3 animations:^{
            arrow.transform = shouldBeExpanded ? CGAffineTransformMakeRotation(M_PI/2) : CGAffineTransformIdentity;
        }];
    }
    
    // 简单方式：直接刷新表格而不是试图追踪单独的行操作
    [self.tableView reloadData];
    
    // 如果展开了某个section，让表格视图滚动到该section的位置
    if (!isCurrentExpanded) {
        NSIndexPath *firstRowPath = [NSIndexPath indexPathForRow:0 inSection:section];
        if ([self.tableView numberOfRowsInSection:section] > 0) {
            [self.tableView scrollToRowAtIndexPath:firstRowPath 
                                  atScrollPosition:UITableViewScrollPositionTop 
                                          animated:YES];
        }
    }
}

// 添加主标题文字间距调整

@end
