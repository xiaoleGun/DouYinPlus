//
//  DYPlusPlayInteractionDoubleTapHooks.xm
//  DYYY
//
//  双击、点赞、评论、分享等动作 hook（拆分自 AWEPlayInteractionViewController.xm）。
//

#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import "Integration/Headers/DYPlusAwemeHeaders.h"
#import "Services/Media/DYPlusManager.h"
#import "Integration/Headers/DYPlusFLEXHeaders.h"
#import <PhotosUI/PhotosUI.h>
#import "Core/Utilities/DYPlusUtils.h"
#import "Core/Runtime/DYPlusRuntime.h"
#import "UI/Components/DYPlusBottomAlertView.h"
#import "UI/Components/DYPlusToast.h"
#import "UI/Components/DYPlusConfirmCloseView.h"
#import "Services/Media/DYPlusScreenshot.h"
#import <CoreMotion/CoreMotion.h>
#import <QuartzCore/QuartzCore.h>
#import "Integration/Playback/DYPlusFloatSpeedButton.h"
#import "UI/PictureInPicture/DYPlusPipPlayer.h"
#import "UI/Components/DYPlusMenuComponents.h"
#import "Integration/Interaction/DYPlusPlayInteractionAdditions.h"

%hook AWEPlayInteractionViewController

- (void)onVideoPlayerViewDoubleClicked:(id)arg1 {
    BOOL isSwitchOn = [[NSUserDefaults standardUserDefaults] boolForKey:@"DYYYDouble"];
    if (!isSwitchOn) {
        %orig;
    }
}

- (void)onPlayer:(id)arg0 didDoubleClick:(id)arg1 {
    BOOL isPopupEnabled = [[NSUserDefaults standardUserDefaults] boolForKey:@"DYYYEnableDoubleOpenAlertController"];
    BOOL isDirectCommentEnabled = [[NSUserDefaults standardUserDefaults] boolForKey:@"DYYYEnableDoubleOpenComment"];

    if (isDirectCommentEnabled) {
        [self performCommentAction];
        return;
    }

    if (isPopupEnabled) {
        AWEAwemeModel *awemeModel = nil;

        if ([self respondsToSelector:@selector(awemeModel)]) {
            awemeModel = [self performSelector:@selector(awemeModel)];
        } else if ([self respondsToSelector:@selector(currentAwemeModel)]) {
            awemeModel = [self performSelector:@selector(currentAwemeModel)];
        } else if ([self respondsToSelector:@selector(getAwemeModel)]) {
            awemeModel = [self performSelector:@selector(getAwemeModel)];
        }

        if (!awemeModel) {
            UIViewController *baseVC = [self valueForKey:@"awemeBaseViewController"];
            if (baseVC && [baseVC respondsToSelector:@selector(model)]) {
                awemeModel = [baseVC performSelector:@selector(model)];
            } else if (baseVC && [baseVC respondsToSelector:@selector(awemeModel)]) {
                awemeModel = [baseVC performSelector:@selector(awemeModel)];
            }
        }

        if (!awemeModel) {
            %orig;
            return;
        }

        [self createFluentDesignDraggableMenuWithAwemeModel:awemeModel touchPoint:[arg1 locationInView:self.view]];
        return;
    }

    %orig;
}

%new
- (void)performScreenshotAction {
    // 直接调用DYYYScreenshot.h中声明的截图方法
    [self dyplus_startCustomScreenshotProcess];
}

%new
- (void)performCommentAction {
    // 查找评论按钮并触发点击
    UIViewController *topVC = [DYPlusManager getActiveTopController];
    UIView *commentButton = [self findCommentButtonInView:topVC.view];
    
    if (commentButton && [commentButton respondsToSelector:@selector(sendActionsForControlEvents:)]) {
        [(UIButton *)commentButton sendActionsForControlEvents:UIControlEventTouchUpInside];
    } else {
        // 尝试通过通知或其他方式触发评论
        [[NSNotificationCenter defaultCenter] postNotificationName:@"AWECommentPanelShow" object:nil];
    }
}

%new
- (void)performLikeAction {
    // 查找点赞按钮并触发点击
    UIViewController *topVC = [DYPlusManager getActiveTopController];
    UIView *likeButton = [self findLikeButtonInView:topVC.view];
    
    if (likeButton && [likeButton respondsToSelector:@selector(sendActionsForControlEvents:)]) {
        [(UIButton *)likeButton sendActionsForControlEvents:UIControlEventTouchUpInside];
        
        // 触感反馈
        if (@available(iOS 10.0, *)) {
            UIImpactFeedbackGenerator *generator = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium];
            [generator prepare];
            [generator impactOccurred];
        }
        
    } else {
        [DYPlusManager showToast:@"未找到点赞按钮"];
    }
}

%new
- (void)showSharePanel {
    // 查找分享按钮并触发点击
    UIViewController *topVC = [DYPlusManager getActiveTopController];
    UIView *shareButton = [self findShareButtonInView:topVC.view];
    
    if (shareButton && [shareButton respondsToSelector:@selector(sendActionsForControlEvents:)]) {
        [(UIButton *)shareButton sendActionsForControlEvents:UIControlEventTouchUpInside];
    } else {
        // 备用方案：获取分享链接
        AWEAwemeModel *awemeModel = [self getCurrentAwemeModel];
        if (awemeModel) {
            NSString *shareURL = [awemeModel valueForKey:@"shareURL"];
            if (shareURL) {
                [[UIPasteboard generalPasteboard] setString:shareURL];
            } else {
                [DYPlusManager showToast:@"无法获取分享链接"];
            }
        }
    }
}

%new
- (void)showDislikeOnVideo {
    // 查找更多选项按钮（三个点）并触发点击
    UIViewController *topVC = [DYPlusManager getActiveTopController];
    UIView *moreButton = [self findMoreButtonInView:topVC.view];
    
    if (moreButton && [moreButton respondsToSelector:@selector(sendActionsForControlEvents:)]) {
        [(UIButton *)moreButton sendActionsForControlEvents:UIControlEventTouchUpInside];
    } else {
        [DYPlusManager showToast:@"未找到操作面板按钮"];
    }
}

%new
- (void)showVideoDebugInfo:(AWEAwemeModel *)model {
    if (!model) return;
    
    NSMutableString *info = [NSMutableString string];
    
    // 使用 KVC 安全访问属性
    NSString *awemeId = [model valueForKey:@"awemeId"];
    NSString *authorName = @"未知";
    if (model.author && [model.author respondsToSelector:@selector(nickname)]) {
        authorName = model.author.nickname ?: @"未知";
    }
    
    [info appendFormat:@"视频ID: %@\n", awemeId ?: @"未知"];
    [info appendFormat:@"作者: %@\n", authorName];
    
    // 安全访问视频时长
    if (model.video) {
        NSNumber *duration = [model.video valueForKey:@"duration"];
        if (duration) {
            [info appendFormat:@"时长: %.1f秒\n", duration.floatValue];
        } else {
            [info appendFormat:@"时长: 未知\n"];
        }
    }
    
    // 安全访问统计数据
    if (model.statistics) {
        NSNumber *diggCount = [model.statistics valueForKey:@"diggCount"];
        NSNumber *commentCount = [model.statistics valueForKey:@"commentCount"];
        NSNumber *shareCount = [model.statistics valueForKey:@"shareCount"];
        
        [info appendFormat:@"点赞数: %ld\n", diggCount ? diggCount.longValue : 0];
        [info appendFormat:@"评论数: %ld\n", commentCount ? commentCount.longValue : 0];
        [info appendFormat:@"分享数: %ld\n", shareCount ? shareCount.longValue : 0];
    }
    
    [info appendFormat:@"类型: %@\n", model.awemeType == 68 ? @"图集" : @"视频"];
    
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"视频信息"
                                                                   message:info
                                                            preferredStyle:UIAlertControllerStyleAlert];
    
    UIAlertAction *copyAction = [UIAlertAction actionWithTitle:@"复制信息" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        [[UIPasteboard generalPasteboard] setString:info];
    }];
    
    UIAlertAction *cancelAction = [UIAlertAction actionWithTitle:@"关闭" style:UIAlertActionStyleCancel handler:nil];
    
    [alert addAction:copyAction];
    [alert addAction:cancelAction];
    
    [[DYPlusManager getActiveTopController] presentViewController:alert animated:YES completion:nil];
}

%new
- (UIView *)findCommentButtonInView:(UIView *)view {
    // 递归查找评论按钮
    for (UIView *subview in view.subviews) {
        if ([subview isKindOfClass:[UIButton class]]) {
            UIButton *button = (UIButton *)subview;
            NSString *imageName = button.currentImage.description.lowercaseString;
            NSString *className = NSStringFromClass([subview class]).lowercaseString;
            
            if ([imageName containsString:@"comment"] || 
                [className containsString:@"comment"] ||
                [imageName containsString:@"bubble"]) {
                return subview;
            }
        }
        
        UIView *found = [self findCommentButtonInView:subview];
        if (found) return found;
    }
    return nil;
}

%new
- (UIView *)findLikeButtonInView:(UIView *)view {
    // 递归查找点赞按钮
    for (UIView *subview in view.subviews) {
        if ([subview isKindOfClass:[UIButton class]]) {
            UIButton *button = (UIButton *)subview;
            NSString *imageName = button.currentImage.description.lowercaseString;
            NSString *className = NSStringFromClass([subview class]).lowercaseString;
            
            if ([imageName containsString:@"like"] || 
                [imageName containsString:@"heart"] ||
                [className containsString:@"like"] ||
                [className containsString:@"digg"]) {
                return subview;
            }
        }
        
        UIView *found = [self findLikeButtonInView:subview];
        if (found) return found;
    }
    return nil;
}

%new
- (UIView *)findShareButtonInView:(UIView *)view {
    // 递归查找分享按钮
    for (UIView *subview in view.subviews) {
        if ([subview isKindOfClass:[UIButton class]]) {
            UIButton *button = (UIButton *)subview;
            NSString *imageName = button.currentImage.description.lowercaseString;
            NSString *className = NSStringFromClass([subview class]).lowercaseString;
            
            if ([imageName containsString:@"share"] || 
                [className containsString:@"share"] ||
                [imageName containsString:@"arrow"]) {
                return subview;
            }
        }
        
        UIView *found = [self findShareButtonInView:subview];
        if (found) return found;
    }
    return nil;
}

%new
- (UIView *)findMoreButtonInView:(UIView *)view {
    // 递归查找更多选项按钮
    for (UIView *subview in view.subviews) {
        if ([subview isKindOfClass:[UIButton class]]) {
            UIButton *button = (UIButton *)subview;
            NSString *imageName = button.currentImage.description.lowercaseString;
            NSString *className = NSStringFromClass([subview class]).lowercaseString;
            
            if ([imageName containsString:@"more"] || 
                [imageName containsString:@"ellipsis"] ||
                [imageName containsString:@"dot"] ||
                [className containsString:@"more"]) {
                return subview;
            }
        }
        
        UIView *found = [self findMoreButtonInView:subview];
        if (found) return found;
    }
    return nil;
}

// 添加按钮事件处理方法

%new
- (AWEAwemeModel *)getCurrentAwemeModel {
    if ([self respondsToSelector:@selector(awemeModel)]) {
        return [self performSelector:@selector(awemeModel)];
    } else if ([self respondsToSelector:@selector(currentAwemeModel)]) {
        return [self performSelector:@selector(currentAwemeModel)];
    }
    return nil;
}

// 模块创建方法

%new
- (DYPlusMenuModule *)createDownloadModuleForAweme:(AWEAwemeModel *)awemeModel {
    BOOL isImageContent = (awemeModel.awemeType == 68);
    return [DYPlusMenuModule moduleWithTitle:isImageContent ? @"保存图片" : @"保存视频"
                                      icon:@"arrow.down.circle"
                                     color:@"#0078D7"
                                    action:^{
        [DYPlusManager showToast:@"下载功能已触发"];
    }];
}

%new
- (DYPlusMenuModule *)createScreenshotModule {
    return [DYPlusMenuModule moduleWithTitle:@"截图功能"
                                      icon:@"camera.viewfinder"
                                     color:@"#4CAF50"
                                    action:^{
        [self dyplus_startCustomScreenshotProcess];
    }];
}

%new
- (DYPlusMenuModule *)createAudioModuleForAweme:(AWEAwemeModel *)awemeModel {
    return [DYPlusMenuModule moduleWithTitle:@"保存音频"
                                      icon:@"music.note"
                                     color:@"#E3008C"
                                    action:^{
        [DYPlusManager showToast:@"音频下载已触发"];
    }];
}

%new
- (DYPlusMenuModule *)createVideoStatsModifyModule {
    return [DYPlusMenuModule moduleWithTitle:@"自定义视频数据"
                                      icon:@"number.circle.fill"
                                     color:@"#FF6B8B"
                                    action:^{
        AWEAwemeModel *awemeModel = [self getCurrentAwemeModel];
        if (awemeModel) {
            // 打开视频数据编辑界面
            UIViewController *viewController = [DYPlusManager getActiveTopController];
            if (viewController) {
                showVideoStatsEditAlert(viewController);
            }
        } else {
            [DYPlusManager showToast:@"无法获取当前视频"];
        }
    }];
}

%new
- (DYPlusMenuModule *)createCopyTextModuleForAweme:(AWEAwemeModel *)awemeModel {
    return [DYPlusMenuModule moduleWithTitle:@"复制文案"
                                      icon:@"doc.on.doc"
                                     color:@"#5C2D91"
                                    action:^{
        NSString *descText = [awemeModel valueForKey:@"descriptionString"];
        [[UIPasteboard generalPasteboard] setString:descText];
        [DYPlusManager showToast:@"文案已复制到剪贴板"];
    }];
}

%new
- (DYPlusMenuModule *)createCommentModule {
    return [DYPlusMenuModule moduleWithTitle:@"打开评论"
                                      icon:@"text.bubble"
                                     color:@"#107C10"
                                    action:^{
        [self performCommentAction];
    }];
}

%new
- (DYPlusMenuModule *)createLikeModule {
    return [DYPlusMenuModule moduleWithTitle:@"点赞视频"
                                      icon:@"heart"
                                     color:@"#D83B01"
                                    action:^{
        [self performLikeAction];
    }];
}

%new
- (DYPlusMenuModule *)createAdvancedModule {
    return [DYPlusMenuModule moduleWithTitle:@"其他功能"
                                      icon:@"gearshape.2.fill"
                                     color:@"#007AFF"
                                    action:^{
        [DYPlusManager showToast:@"高级功能面板"];
    }];
}

// 功能开关检查方法

%new
- (BOOL)shouldShowDownloadModule {
    return [[NSUserDefaults standardUserDefaults] boolForKey:@"DYYYDoubleTapDownload"] || 
           ![[NSUserDefaults standardUserDefaults] objectForKey:@"DYYYDoubleTapDownload"];
}

%new
- (BOOL)shouldShowScreenshotModule {
    return [[NSUserDefaults standardUserDefaults] boolForKey:@"DYYYEnableScreenshot"] || 
           ![[NSUserDefaults standardUserDefaults] objectForKey:@"DYYYEnableScreenshot"];
}

%new
- (BOOL)shouldShowAudioModule {
    return [[NSUserDefaults standardUserDefaults] boolForKey:@"DYYYDoubleTapDownloadAudio"] || 
           ![[NSUserDefaults standardUserDefaults] objectForKey:@"DYYYDoubleTapDownloadAudio"];
}

%new
- (BOOL)shouldShowCopyTextModule {
    return [[NSUserDefaults standardUserDefaults] boolForKey:@"DYYYDoubleTapCopyDesc"] || 
           ![[NSUserDefaults standardUserDefaults] objectForKey:@"DYYYDoubleTapCopyDesc"];
}

%new
- (BOOL)shouldShowCommentModule {
    return [[NSUserDefaults standardUserDefaults] boolForKey:@"DYYYDoubleTapComment"] || 
           ![[NSUserDefaults standardUserDefaults] objectForKey:@"DYYYDoubleTapComment"];
}

%new
- (BOOL)shouldShowLikeModule {
    return [[NSUserDefaults standardUserDefaults] boolForKey:@"DYYYDoubleTapLike"] || 
           ![[NSUserDefaults standardUserDefaults] objectForKey:@"DYYYDoubleTapLike"];
}

%new
- (BOOL)shouldShowAdvancedModule {
    return [[NSUserDefaults standardUserDefaults] boolForKey:@"DYYYEnableAdvancedSettings"] || 
           ![[NSUserDefaults standardUserDefaults] objectForKey:@"DYYYEnableAdvancedSettings"];
}

%new
- (DYPlusMenuModule *)createCommentModuleWithInstantClose {
    return [DYPlusMenuModule moduleWithTitle:@"打开评论"
                                      icon:@"text.bubble"
                                     color:@"#107C10"
                                    action:^{
        // 评论功能：立即关闭面板并执行操作
        [self dismissCurrentMenuPanel];
        dispatch_async(dispatch_get_main_queue(), ^{
            [self performCommentAction];
        });
    }];
}

%new
- (DYPlusMenuModule *)createLikeModuleWithInstantClose {
    return [DYPlusMenuModule moduleWithTitle:@"点赞视频"
                                      icon:@"heart"
                                     color:@"#D83B01"
                                    action:^{
        // 点赞功能：立即关闭面板并执行操作
        [self dismissCurrentMenuPanel];
        dispatch_async(dispatch_get_main_queue(), ^{
            [self performLikeAction];
        });
    }];
}

%new
- (DYPlusMenuModule *)createShareModuleWithInstantClose {
    return [DYPlusMenuModule moduleWithTitle:@"分享视频"
                                      icon:@"square.and.arrow.up"
                                     color:@"#FFB900"
                                    action:^{
        // 分享功能：立即关闭面板并执行操作
        [self dismissCurrentMenuPanel];
        dispatch_async(dispatch_get_main_queue(), ^{
            [self showSharePanel];
        });
    }];
}

%new
- (UIImage *)screenshotEntireScreen {
    @try {
        // 获取当前窗口
        UIWindow *keyWindow = DYPlus_findKeyWindow();
        if (!keyWindow) {
            return nil;
        }
        
        return [DYPlusScreenshot captureFullScreenshot:keyWindow];
    } @catch (NSException *exception) {
        NSLog(@"DYYY截图失败：%@", exception);
        return nil;
    }
}

%new
- (UIImage *)dyplus_cropImage:(UIImage *)image toRect:(CGRect)cropRect {
    return [DYPlusScreenshot cropImage:image toRect:cropRect];
}

%new
- (void)dyplus_presentShareSheetWithImage:(UIImage *)image fromView:(UIView *)sourceView {
    [DYPlusScreenshot presentShareSheetWithImage:image fromView:sourceView];
}

%new
- (void)dyplus_startCustomScreenshotProcess {
    NSLog(@"DYYY截图: AWEPlayInteractionViewController.dyyy_startCustomScreenshotProcess 被调用");
    
    // 确保在主线程执行UI操作
    dispatch_async(dispatch_get_main_queue(), ^{
        UIWindow *keyWindow = DYPlus_findKeyWindow();
        if (!keyWindow) {
            [DYPlusManager showToast:@"无法获取窗口进行截图"];
            return;
        }
        
        NSLog(@"DYYY截图: 开始抖音视频截图流程");
        
        // 获取当前播放的视频视图和播放状态
        id playerView = nil;
        @try {
            playerView = [self valueForKey:@"playerView"];
        } @catch (NSException *exception) {
            NSLog(@"DYYY截图: 无法获取playerView: %@", exception);
        }
        
        BOOL wasPlaying = NO;
        
        // 尝试暂停视频播放
        @try {
            BOOL paused = NO;
            if (DYPlusReadBooleanSelector(playerView, @selector(isPaused), &paused)) {
                wasPlaying = !paused;
                if (wasPlaying && [playerView respondsToSelector:@selector(pause)]) {
                    [playerView performSelector:@selector(pause)];
                    NSLog(@"DYYY截图: 暂停了视频播放");
                }
            }
        } @catch (NSException *exception) {
            NSLog(@"DYYY截图: 暂停视频失败: %@", exception);
        }
        
        // 等待一小段时间确保暂停生效
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            // 先截取全屏图像
            UIImage *initialScreenshot = [DYPlusScreenshot captureFullScreenshot:keyWindow];
            if (!initialScreenshot) {
                NSLog(@"DYYY截图: 获取全屏截图失败");
                [DYPlusManager showToast:@"无法获取屏幕截图"];
                // 恢复视频播放
                if (wasPlaying && playerView && [playerView respondsToSelector:@selector(play)]) {
                    [playerView performSelector:@selector(play)];
                }
                return;
            }
            
            NSLog(@"DYYY截图: 成功获取到屏幕截图，尺寸: %.0f x %.0f", initialScreenshot.size.width, initialScreenshot.size.height);
            
            // 显示选择区域视图
            DYPlusScreenshotSelectionView *selectionView = [[DYPlusScreenshotSelectionView alloc] initWithFrame:keyWindow.bounds completion:^(CGRect selectedRect, BOOL cancelled) {
                NSLog(@"DYYY截图回调: cancelled=%d, rect=%@", cancelled, NSStringFromCGRect(selectedRect));
                
                // 确保在主线程中恢复视频播放
                dispatch_async(dispatch_get_main_queue(), ^{
                    if (wasPlaying && playerView && [playerView respondsToSelector:@selector(play)]) {
                        [playerView performSelector:@selector(play)];
                        NSLog(@"DYYY截图: 恢复视频播放");
                    }
                });
                
                if (cancelled) {
                    [DYPlusManager showToast:@"已取消截图"];
                    return;
                }
                
                if (CGRectIsEmpty(selectedRect) || selectedRect.size.width < 10 || selectedRect.size.height < 10) {
                    [DYPlusManager showToast:@"截图区域太小"];
                    return;
                }
                
                // 使用已经捕获的高质量屏幕截图进行裁剪
                UIImage *croppedImage = [DYPlusScreenshot cropImage:initialScreenshot toRect:selectedRect];
                if (croppedImage) {
                    NSLog(@"DYYY截图: 成功裁剪图片，尺寸: %.0f x %.0f", croppedImage.size.width, croppedImage.size.height);
                    // 使用主线程显示分享sheet
                    dispatch_async(dispatch_get_main_queue(), ^{
                        [DYPlusScreenshot presentShareSheetWithImage:croppedImage fromView:keyWindow];
                    });
                } else {
                    NSLog(@"DYYY截图: 裁剪图片失败");
                    [DYPlusManager showToast:@"截图处理失败"];
                }
            }];
            
            if (selectionView) {
                // 确保视图被添加到窗口最上层
                NSLog(@"DYYY截图: 显示选择区域界面");
                [keyWindow addSubview:selectionView];
                [keyWindow bringSubviewToFront:selectionView];
            } else {
                NSLog(@"DYYY截图: 创建选择视图失败");
                [DYPlusManager showToast:@"创建截图界面失败"];
                // 恢复视频播放
                if (wasPlaying && playerView && [playerView respondsToSelector:@selector(play)]) {
                    [playerView performSelector:@selector(play)];
                }
            }
        });
        
        // 设置一个定时器确保即使回调失败也会恢复视频播放
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(15 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            if (wasPlaying && playerView && [playerView respondsToSelector:@selector(play)]) {
                [playerView performSelector:@selector(play)];
                NSLog(@"DYYY截图: 安全机制恢复视频播放");
            }
        });
    });
}

%end
