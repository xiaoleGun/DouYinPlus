//
//  DYYYMainSupport.m
//  DYYY
//
//  DYYY.xm 拆分后的共享支撑实现：倍速基础设施、tab 高度、评论可见状态与全屏布局判定。
//

#import "Integration/Common/DYPlusMainHooksShared.h"

CGFloat tabHeight = 0;
CGFloat originalTabHeight = 0;

CGFloat DYPlusVisibleTabBarHeightForView(UIView *view) {
    UIWindow *window = view.window;
    if (!window) return 0.0;

    UIViewController *owner = [DYPlusUtils findViewControllerFromView:view];
    UITabBarController *controller = owner.tabBarController;
    for (UIViewController *node = owner; node; node = node.parentViewController) {
        if (node.hidesBottomBarWhenPushed) return 0.0;
        UIViewController *top = node.navigationController.topViewController;
        if (top.hidesBottomBarWhenPushed) return 0.0;
        if ([node isKindOfClass:UITabBarController.class]) controller = (UITabBarController *)node;
    }
    if (!controller) return 0.0;
    UITabBar *bar = controller.tabBar;
    if (bar.window != window || CGRectIsEmpty(bar.bounds)) return 0.0;
    for (UIView *node = bar; node; node = node.superview) {
        if (node.hidden || node.alpha < 0.01 || node.layer.opacity < 0.01) return 0.0;
    }
    CGRect visible = CGRectIntersection([bar convertRect:bar.bounds toView:window], window.bounds);
    return CGRectIsNull(visible) || CGRectIsEmpty(visible) ? 0.0 : CGRectGetHeight(visible);
}

BOOL dyplusCommentViewVisible = NO;
BOOL dyplusCurrentLandscapeVideo = NO;
__weak AWEPlayInteractionViewController *dyplusCurrentFullScreenInteractionVC = nil;

static CGFloat getTabBarHeight(void) {
    static CGFloat cachedHeight = 0;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        UIWindow *keyWindow = nil;
        if (@available(iOS 13.0, *)) {
            NSSet *connectedScenes = [UIApplication sharedApplication].connectedScenes;
            for (UIScene *scene in connectedScenes) {
                if ([scene isKindOfClass:[UIWindowScene class]]) {
                    UIWindowScene *windowScene = (UIWindowScene *)scene;
                    for (UIWindow *window in windowScene.windows) {
                        if (window.isKeyWindow) {
                            keyWindow = window;
                            break;
                        }
                    }
                    if (keyWindow) break;
                }
            }
        } else {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
            keyWindow = [UIApplication sharedApplication].keyWindow;
#pragma clang diagnostic pop
        }
        
        if (@available(iOS 11.0, *)) {
            cachedHeight = keyWindow.safeAreaInsets.bottom;
        }
        if (cachedHeight == 0) {
            cachedHeight = 49.0; // 默认标签栏高度
        }
        
        tabHeight = cachedHeight;
    });
    return cachedHeight;
}

// 初始化函数
static void initializeTabHeight(void) __attribute__((constructor));
static void initializeTabHeight(void) {
    tabHeight = getTabBarHeight();
}

// 倍速管理基础设施（移植自 DYYY12345/DYYY.xm:211-620）
static __weak AWEPlayInteractionViewController *dyplusActiveSpeedInteractionController = nil;
__weak AWEAwemeModel *dyplusCurrentSpeedAweme = nil;
static NSString *dyplusLastAutoRestoredSpeedAwemeIdentifier = nil;
BOOL dyplusLongPressFastSpeedActive = NO;
BOOL dyplusLongPressLockedSpeedActive = NO;
static BOOL dyplusInteractionViewVisible = NO;

BOOL DYPlusShouldHandleSpeedFeatures(void) {
    if (DYPlusCachedBool(@"DYYYEnableFloatSpeedButton")) {
        return YES;
    }

    float defaultSpeed = DYPlusCachedFloat(@"DYYYDefaultSpeed");
    if (defaultSpeed <= 0.0f) {
        return NO;
    }

    return fabsf(defaultSpeed - 1.0f) > FLT_EPSILON;
}

void DYPlusClearLongPressSpeedState(void) {
    dyplusLongPressFastSpeedActive = NO;
    dyplusLongPressLockedSpeedActive = NO;
}
static CGFloat DYPlusViewControllerVisibilityScore(UIViewController *viewController) {
    if (!viewController || !viewController.isViewLoaded) {
        return -1.0;
    }

    UIView *view = viewController.view;
    UIWindow *window = view.window;
    if (!window || view.hidden || view.alpha <= 0.01 || CGRectIsEmpty(view.bounds)) {
        return -1.0;
    }

    CGRect frameInWindow = [view convertRect:view.bounds toView:window];
    CGRect visibleFrame = CGRectIntersection(frameInWindow, window.bounds);
    if (CGRectIsNull(visibleFrame) || CGRectIsEmpty(visibleFrame)) {
        return -1.0;
    }

    CGFloat visibleArea = CGRectGetWidth(visibleFrame) * CGRectGetHeight(visibleFrame);
    CGFloat totalArea = CGRectGetWidth(frameInWindow) * CGRectGetHeight(frameInWindow);
    CGFloat visibleRatio = totalArea > 0.0 ? visibleArea / totalArea : 0.0;
    CGPoint windowCenter = CGPointMake(CGRectGetMidX(window.bounds), CGRectGetMidY(window.bounds));
    CGFloat centerBonus = CGRectContainsPoint(visibleFrame, windowCenter) ? 1000000000.0 : 0.0;
    return centerBonus + visibleRatio * 1000000.0 + visibleArea;
}

static BOOL DYPlusAwemeModelsMatch(AWEAwemeModel *lhs, AWEAwemeModel *rhs) {
    if (!lhs || !rhs) {
        return NO;
    }
    if (lhs == rhs) {
        return YES;
    }

    NSString *lhsItemID = lhs.itemID;
    NSString *rhsItemID = rhs.itemID;
    return lhsItemID.length > 0 && rhsItemID.length > 0 && [lhsItemID isEqualToString:rhsItemID];
}

static NSString *DYPlusSpeedAwemeIdentifier(AWEAwemeModel *aweme) {
    if (!aweme) {
        return nil;
    }
    if (aweme.itemID.length > 0) {
        return aweme.itemID;
    }
    return [NSString stringWithFormat:@"%p", aweme];
}

static AWEAwemeModel *DYPlusSpeedAwemeFromObject(id object) {
    Class awemeClass = NSClassFromString(@"AWEAwemeModel");
    if (!object || !awemeClass) {
        return nil;
    }
    if ([object isKindOfClass:awemeClass]) {
        return (AWEAwemeModel *)object;
    }

    for (NSString *key in @[ @"model", @"awemeModel", @"currentAweme" ]) {
        @try {
            id value = [object valueForKey:key];
            if ([value isKindOfClass:awemeClass]) {
                return (AWEAwemeModel *)value;
            }
        } @catch (NSException *exception) {
        }
    }
    return nil;
}

static double DYPlusDefaultPlaybackSpeed(void) {
    double defaultSpeed = DYPlusCachedFloat(@"DYYYDefaultSpeed");
    if (isfinite(defaultSpeed) && defaultSpeed > 0.0) {
        return defaultSpeed;
    }
    return 1.0;
}

// 本地替代 setCurrentSpeedValue（当前项目 DYYYFloatSpeedButton.xm 未实现此函数）
static BOOL DYPlusSetCurrentSpeedValue(float speed) {
    if (!isfinite(speed) || speed <= 0.0f) {
        return NO;
    }

    NSArray *speeds = getSpeedOptions();
    for (NSInteger index = 0; index < speeds.count; index++) {
        if (fabs([speeds[index] floatValue] - speed) < 0.01f) {
            setCurrentSpeedIndex(index);
            return YES;
        }
    }
    return NO;
}

void DYPlusRestoreFloatSpeedButtonForAwemeIfNeeded(AWEAwemeModel *aweme) {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    BOOL shouldAutoRestore = [defaults boolForKey:@"DYYYEnableFloatSpeedButton"] && [defaults boolForKey:@"DYYYAutoRestoreSpeed"];
    if (!shouldAutoRestore) {
        dyplusLastAutoRestoredSpeedAwemeIdentifier = nil;
        return;
    }

    NSString *awemeIdentifier = DYPlusSpeedAwemeIdentifier(aweme);
    if (awemeIdentifier.length == 0 || [awemeIdentifier isEqualToString:dyplusLastAutoRestoredSpeedAwemeIdentifier]) {
        return;
    }

    dyplusLastAutoRestoredSpeedAwemeIdentifier = [awemeIdentifier copy];
    if (!DYPlusSetCurrentSpeedValue((float)DYPlusDefaultPlaybackSpeed())) {
        setCurrentSpeedIndex(0);
    }
    updateSpeedButtonUI();
}

static NSArray<AWEPlayInteractionViewController *> *DYPlusSpeedInteractionControllers(AWEPlayInteractionViewController *preferredController) {
    NSMutableArray<AWEPlayInteractionViewController *> *controllers = [NSMutableArray array];
    Class interactionControllerClass = NSClassFromString(@"AWEPlayInteractionViewController");
    UIWindow *window = [DYPlusManager getActiveWindow];
    UIViewController *rootViewController = window.rootViewController;
    while (rootViewController.presentedViewController) {
        rootViewController = rootViewController.presentedViewController;
    }

    for (UIViewController *viewController in rootViewController ? DYPlusAllViewControllersInHierarchy(rootViewController) : @[]) {
        if (interactionControllerClass && [viewController isKindOfClass:interactionControllerClass]) {
            [controllers addObject:(AWEPlayInteractionViewController *)viewController];
        }
    }

    if (preferredController && ![controllers containsObject:preferredController]) {
        [controllers addObject:preferredController];
    }
    return controllers;
}

static AWEPlayInteractionViewController *DYPlusResolveSpeedInteractionController(AWEPlayInteractionViewController *preferredController, AWEAwemeModel *targetAweme, BOOL allowVisibleFallback) {
    AWEPlayInteractionViewController *bestModelMatch = nil;
    AWEPlayInteractionViewController *bestVisibleController = nil;
    CGFloat bestModelMatchScore = -1.0;
    CGFloat bestVisibleScore = -1.0;

    for (AWEPlayInteractionViewController *controller in DYPlusSpeedInteractionControllers(preferredController)) {
        CGFloat visibilityScore = DYPlusViewControllerVisibilityScore(controller);
        if (visibilityScore < 0.0) {
            continue;
        }

        if (visibilityScore > bestVisibleScore) {
            bestVisibleScore = visibilityScore;
            bestVisibleController = controller;
        }
        if (targetAweme && DYPlusAwemeModelsMatch(controller.model, targetAweme) && visibilityScore > bestModelMatchScore) {
            bestModelMatchScore = visibilityScore;
            bestModelMatch = controller;
        }
    }

    return bestModelMatch ?: (allowVisibleFallback ? bestVisibleController : nil);
}

AWEPlayInteractionViewController *DYPlusResolveCurrentSpeedInteractionController(AWEPlayInteractionViewController *preferredController) {
    return DYPlusResolveSpeedInteractionController(preferredController, dyplusCurrentSpeedAweme, YES);
}

id DYPlusCurrentSpeedInteractionController(void) {
    return DYPlusResolveCurrentSpeedInteractionController(dyplusActiveSpeedInteractionController);
}

void DYPlusEnsureFloatSpeedButton(AWEPlayInteractionViewController *interactionController) {
    // [DYYYFloatingSpeedButton reloadConfiguration] — 当前项目无此方法，跳过

    AWEAwemeModel *targetAweme = dyplusCurrentSpeedAweme;
    BOOL allowVisibleFallback = !targetAweme || (interactionController && DYPlusAwemeModelsMatch(interactionController.model, targetAweme));
    AWEPlayInteractionViewController *currentController = DYPlusResolveSpeedInteractionController(interactionController, targetAweme, allowVisibleFallback);
    if (!currentController) {
        updateSpeedButtonVisibility();
        return;
    }

    if ((dyplusLongPressFastSpeedActive || dyplusLongPressLockedSpeedActive) &&
        currentController.model &&
        !DYPlusAwemeModelsMatch(dyplusCurrentSpeedAweme, currentController.model)) {
        DYPlusClearLongPressSpeedState();
    }

    dyplusActiveSpeedInteractionController = currentController;
    dyplusCurrentSpeedAweme = currentController.model;
    dyplusInteractionViewVisible = YES;

    if (!DYPlusGetBool(@"DYYYEnableFloatSpeedButton")) {
        updateSpeedButtonVisibility();
        return;
    }

    UIWindow *keyWindow = [DYPlusManager getActiveWindow];
    if (!keyWindow) {
        return;
    }

    DYPlusRestoreFloatSpeedButtonForAwemeIfNeeded(currentController.model);

    if (!speedButton) {
        CGFloat btnSize = DYPlusCachedFloat(@"DYYYSpeedButtonSize");
        if (btnSize <= 0) {
            btnSize = 32.0;
        }
        CGRect windowBounds = keyWindow.bounds;
        CGRect initialFrame = CGRectMake((windowBounds.size.width - btnSize) / 2.0, (windowBounds.size.height - btnSize) / 2.0, btnSize, btnSize);
        speedButton = [[DYPlusFloatingSpeedButton alloc] initWithFrame:initialFrame];
        speedButton.interactionController = currentController;
        updateSpeedButtonUI();
    } else if (speedButton.interactionController != currentController) {
        speedButton.interactionController = currentController;
        [speedButton resetButtonState];
    }

    if (![speedButton isDescendantOfView:keyWindow]) {
        [keyWindow addSubview:speedButton];
        [speedButton loadSavedPosition];
        // [speedButton resetFadeTimer] — 当前项目无此方法，跳过
    }

    [keyWindow bringSubviewToFront:speedButton];
    updateSpeedButtonVisibility();
}

// 提供给跨文件调用的刷新入口
void DYPlusRefreshFloatSpeedButton(void) {
    void (^applyBlock)(void) = ^{
        AWEPlayInteractionViewController *currentController = (AWEPlayInteractionViewController *)DYPlusCurrentSpeedInteractionController();
        DYPlusEnsureFloatSpeedButton(currentController);
    };
    if ([NSThread isMainThread]) {
        applyBlock();
    } else {
        dispatch_async(dispatch_get_main_queue(), applyBlock);
    }
}

static BOOL DYPlusSetPlaybackRateOnTarget(id target, double speed) {
    if (!target || ![target respondsToSelector:@selector(setVideoControllerPlaybackRate:)]) {
        return NO;
    }

    @try {
        [(AWEAwemePlayVideoViewController *)target setVideoControllerPlaybackRate:speed];
        return YES;
    } @catch (NSException *exception) {
        return NO;
    }
}

BOOL DYPlusApplyPlaybackSpeed(AWEPlayInteractionViewController *interactionController, double speed) {
    interactionController = DYPlusResolveCurrentSpeedInteractionController(interactionController);
    if (!interactionController) {
        return NO;
    }

    Protocol *speedControllerProtocol = NSProtocolFromString(@"AWEFastSpeedControllerProtocol");
    if (speedControllerProtocol && [interactionController respondsToSelector:@selector(controllerByProtocol:)]) {
        @try {
            id speedController = [interactionController controllerByProtocol:speedControllerProtocol];
            if ([speedController respondsToSelector:@selector(playVideoViewController)]) {
                id playVideoViewController = [(AWEPlayInteractionSpeedController *)speedController playVideoViewController];
                if (DYPlusSetPlaybackRateOnTarget(playVideoViewController, speed)) {
                    return YES;
                }
            }
        } @catch (NSException *exception) {
        }
    }

    if ([interactionController respondsToSelector:@selector(videoDelegate)] && DYPlusSetPlaybackRateOnTarget([interactionController videoDelegate], speed)) {
        return YES;
    }

    UIWindow *window = [DYPlusManager getActiveWindow];
    UIViewController *rootViewController = window.rootViewController;
    while (rootViewController.presentedViewController) {
        rootViewController = rootViewController.presentedViewController;
    }

    UIViewController *bestPlayerViewController = nil;
    CGFloat bestPlayerVisibilityScore = -1.0;
    for (UIViewController *viewController in rootViewController ? DYPlusAllViewControllersInHierarchy(rootViewController) : @[]) {
        if ([viewController isKindOfClass:NSClassFromString(@"AWEAwemePlayVideoViewController")] ||
            [viewController isKindOfClass:NSClassFromString(@"AWEDPlayerFeedPlayerViewController")] ||
            [viewController isKindOfClass:NSClassFromString(@"AWEDPlayerViewController_Merge")]) {
            CGFloat visibilityScore = DYPlusViewControllerVisibilityScore(viewController);
            if (visibilityScore > bestPlayerVisibilityScore) {
                bestPlayerVisibilityScore = visibilityScore;
                bestPlayerViewController = viewController;
            }
        }
    }

    return DYPlusSetPlaybackRateOnTarget(bestPlayerViewController, speed);
}

double DYPlusConfiguredPlaybackSpeed(void) {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    if ([defaults boolForKey:@"DYYYEnableFloatSpeedButton"]) {
        return getCurrentSpeed();
    }

    if ([defaults boolForKey:@"DYYYUserAgreementAccepted"]) {
        return DYPlusDefaultPlaybackSpeed();
    }
    return 1.0;
}

static BOOL DYPlusShouldPrepareDefaultPlaybackSpeedForPlayer(id playerViewController) {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    if (![defaults boolForKey:@"DYYYEnableFloatSpeedButton"] || ![defaults boolForKey:@"DYYYAutoRestoreSpeed"]) {
        return NO;
    }

    AWEAwemeModel *targetAweme = DYPlusSpeedAwemeFromObject(playerViewController) ?: dyplusCurrentSpeedAweme;
    NSString *awemeIdentifier = DYPlusSpeedAwemeIdentifier(targetAweme);
    return awemeIdentifier.length > 0 && ![awemeIdentifier isEqualToString:dyplusLastAutoRestoredSpeedAwemeIdentifier];
}

double DYPlusPreparedPlaybackSpeedForPlayer(id playerViewController) {
    if (DYPlusShouldPrepareDefaultPlaybackSpeedForPlayer(playerViewController)) {
        return DYPlusDefaultPlaybackSpeed();
    }
    return DYPlusConfiguredPlaybackSpeed();
}

void DYPlusApplyPreparedPlaybackSpeedToPlayer(id playerViewController) {
    if (!DYPlusShouldHandleSpeedFeatures() || !playerViewController || dyplusLongPressFastSpeedActive || dyplusLongPressLockedSpeedActive) {
        return;
    }

    double speed = DYPlusPreparedPlaybackSpeedForPlayer(playerViewController);
    void (^applyBlock)(void) = ^{
      DYPlusSetPlaybackRateOnTarget(playerViewController, speed);
    };
    if ([NSThread isMainThread]) {
        applyBlock();
    } else {
        dispatch_async(dispatch_get_main_queue(), applyBlock);
    }
}

static void DYPlusBindAndApplyCurrentPlaybackSpeed(void) {
    if (!DYPlusShouldHandleSpeedFeatures() || dyplusLongPressFastSpeedActive || dyplusLongPressLockedSpeedActive) {
        return;
    }

    AWEAwemeModel *targetAweme = dyplusCurrentSpeedAweme;
    AWEPlayInteractionViewController *currentController = DYPlusResolveSpeedInteractionController(nil, targetAweme, targetAweme == nil);
    if (!currentController) {
        return;
    }

    DYPlusEnsureFloatSpeedButton(currentController);
    DYPlusApplyPlaybackSpeed(currentController, DYPlusConfiguredPlaybackSpeed());
}

static void DYPlusScheduleConfiguredPlaybackSpeedRestoreAfterDelay(NSTimeInterval delay) {
    dispatch_block_t restoreBlock = ^{
      DYPlusBindAndApplyCurrentPlaybackSpeed();
    };
    if (delay <= 0.0) {
        dispatch_async(dispatch_get_main_queue(), restoreBlock);
    } else {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)), dispatch_get_main_queue(), restoreBlock);
    }
}

void DYPlusScheduleConfiguredPlaybackSpeedRestore(void) {
    DYPlusScheduleConfiguredPlaybackSpeedRestoreAfterDelay(0.0);
    DYPlusScheduleConfiguredPlaybackSpeedRestoreAfterDelay(0.2);
}

void DYPlusEndLockedLongPressSpeedAndRestoreIfNeeded(void) {
    if (!dyplusLongPressLockedSpeedActive) {
        return;
    }
    dyplusLongPressLockedSpeedActive = NO;
    DYPlusScheduleConfiguredPlaybackSpeedRestore();
}

static void DYPlusHandleCurrentSpeedAwemeChanged(id aweme) {
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{
          DYPlusHandleCurrentSpeedAwemeChanged(aweme);
        });
        return;
    }

    Class awemeClass = NSClassFromString(@"AWEAwemeModel");
    if (awemeClass && [aweme isKindOfClass:awemeClass]) {
        dyplusCurrentSpeedAweme = (AWEAwemeModel *)aweme;
    }
    if (!DYPlusShouldHandleSpeedFeatures()) {
        return;
    }

    DYPlusClearLongPressSpeedState();
    DYPlusRestoreFloatSpeedButtonForAwemeIfNeeded(dyplusCurrentSpeedAweme);

    DYPlusBindAndApplyCurrentPlaybackSpeed();
    DYPlusScheduleConfiguredPlaybackSpeedRestore();
}

// 评论打开且当前为 16:9 横屏时，放行抖音原生的视频上移布局。
BOOL DYPlusFullScreenCommentOriginalLayoutActive(void) {
    return DYPlusCachedBool(@"DYYYisEnableFullScreen")
        && dyplusCommentViewVisible
        && dyplusCurrentLandscapeVideo;
}

// DYYY 旧毛玻璃只在液态玻璃关闭时生效，避免同一面板叠加两套玻璃。
BOOL DYPlusLegacyCommentBlurActive(void) {
    return DYPlusCachedBool(@"DYYYisEnableCommentBlur")
        && !DYPlusCachedBool(@"DYYYCommentGlass");
}
