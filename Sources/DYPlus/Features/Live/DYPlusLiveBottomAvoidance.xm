// 直播预览控制层的底部避让；只移动文字/控制层及贴底水印，不移动直播视频。
#import "Integration/Headers/DYPlusAwemeHeaders.h"
#import "Features/Glass/DYPlusGlassTabBar.h"
#import "Features/Live/DYPlusLiveBottomAvoidance.h"
#import "Core/Utilities/DYPlusUtils.h"
#import <objc/runtime.h>

static char kOriginalTransformKey;
static char kAppliedTransformKey;
static NSHashTable<AWELivePreStream4LayerContainerView *> *gLiveContainers;
static BOOL gSyncing;
static const CGFloat kLiveBottomGap = 8.0;

static BOOL DYPlusLiveViewVisible(UIView *view) {
    if (!view.window) return NO;
    for (UIView *node = view; node; node = node.superview) {
        if (node.hidden || node.alpha < 0.01 || node.layer.opacity < 0.01) return NO;
    }
    return YES;
}

BOOL DYPlusLiveBottomAvoidanceHandlesView(UIView *view) {
    if (!DYPlusGlassTabBarCurrent() && !DYPlusCachedBool(@"DYYYisEnableFullScreen")) return NO;
    Class cls = NSClassFromString(@"AWELivePreStream4LayerContainerView");
    for (UIView *node = view; node; node = node.superview) {
        if (cls && [node isKindOfClass:cls]) return YES;
    }
    return NO;
}

static UIView *DYPlusLiveBottomBar(UIView *container) {
    UIView *bar = DYPlusGlassPlatterCurrent() ?: DYPlusGlassTabBarCurrent();
    if (!bar && DYPlusCachedBool(@"DYYYisEnableFullScreen")) {
        UIViewController *vc = [DYPlusUtils findViewControllerFromView:container];
        bar = vc.tabBarController.tabBar;
    }
    return bar.window == container.window && DYPlusLiveViewVisible(bar) ? bar : nil;
}

static void DYPlusLiveRestoreTarget(UIView *target) {
    NSValue *original = objc_getAssociatedObject(target, &kOriginalTransformKey);
    NSValue *applied = objc_getAssociatedObject(target, &kAppliedTransformKey);
    if (!original) return;
    objc_setAssociatedObject(target, &kOriginalTransformKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(target, &kAppliedTransformKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    // 宿主已改过 transform 时保留它的新值，不能用旧基线覆盖。
    if (applied && CGAffineTransformEqualToTransform(target.transform, applied.CGAffineTransformValue)) {
        target.transform = original.CGAffineTransformValue;
    }
}

static void DYPlusLiveAvoidBottom(UIView *target, UIView *bar, UIView *container, BOOL controlLayer) {
    if (!target || !target.superview || !bar || !DYPlusLiveViewVisible(target)) {
        DYPlusLiveRestoreTarget(target);
        return;
    }
    NSValue *original = objc_getAssociatedObject(target, &kOriginalTransformKey);
    NSValue *applied = objc_getAssociatedObject(target, &kAppliedTransformKey);
    CGAffineTransform baseline = original && applied
        && CGAffineTransformEqualToTransform(target.transform, applied.CGAffineTransformValue)
        ? original.CGAffineTransformValue : target.transform;
    // frame 含 transform 的平移：扣除上次自身位移，始终从原布局计算，避免逐帧累计上移。
    CGRect frame = CGRectOffset(target.frame, 0.0, baseline.ty - target.transform.ty);
    CGRect barRect = [bar convertRect:bar.bounds toView:target.superview];
    if (CGRectGetMaxX(frame) <= CGRectGetMinX(barRect)
        || CGRectGetMinX(frame) >= CGRectGetMaxX(barRect)) {
        DYPlusLiveRestoreTarget(target);
        return;
    }
    // 控制层的避让量从未被移动的直播容器计算。不能用控制层本身的 frame 反推位移：
    // IESLive 可能在保留 transform 的同时重写 frame，那会把上次位移叠进下一轮。
    CGRect containerRect = [container convertRect:container.bounds toView:target.superview];
    CGFloat lift = MAX(0.0, CGRectGetMaxY(containerRect) - CGRectGetMinY(barRect) + kLiveBottomGap);
    if (!controlLayer && !original && CGRectGetMaxY(frame) <= CGRectGetMinY(barRect) - kLiveBottomGap) {
        DYPlusLiveRestoreTarget(target);
        return;
    }
    if (lift < 0.5) {
        DYPlusLiveRestoreTarget(target);
        return;
    }
    CGAffineTransform wanted = baseline;
    wanted.ty -= lift;
    if (original && applied && CGAffineTransformEqualToTransform(target.transform, wanted)) return;
    objc_setAssociatedObject(target, &kOriginalTransformKey, [NSValue valueWithCGAffineTransform:baseline],
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(target, &kAppliedTransformKey, [NSValue valueWithCGAffineTransform:wanted],
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    if (!CGAffineTransformEqualToTransform(target.transform, wanted)) target.transform = wanted;
}

static void DYPlusLiveSyncBottom(AWELivePreStream4LayerContainerView *container) {
    if (gSyncing) return;
    gSyncing = YES;
    @try {
        UIView *bar = DYPlusLiveBottomBar(container);
        if ([container respondsToSelector:@selector(controlContainer)]) {
            DYPlusLiveAvoidBottom(container.controlContainer, bar, container, YES);
        }
        if ([container respondsToSelector:@selector(bottomDarkWatermark)]) {
            DYPlusLiveAvoidBottom(container.bottomDarkWatermark, bar, container, NO);
        }
    } @finally {
        gSyncing = NO;
    }
}

void DYPlusLiveRefreshBottomAvoidance(void) {
    for (AWELivePreStream4LayerContainerView *container in gLiveContainers.allObjects) {
        DYPlusLiveSyncBottom(container);
    }
}

%hook AWELivePreStream4LayerContainerView

- (void)layoutSubviews {
    %orig;
    [gLiveContainers addObject:self];
    DYPlusLiveSyncBottom(self);
}

- (void)didMoveToWindow {
    %orig;
    if (self.window) [gLiveContainers addObject:self];
    else [gLiveContainers removeObject:self];
    DYPlusLiveSyncBottom(self);
}

%end

%ctor {
    gLiveContainers = [NSHashTable weakObjectsHashTable];
    %init;
    [[NSNotificationCenter defaultCenter] addObserverForName:@"DYYYSettingChanged"
                                                      object:nil queue:NSOperationQueue.mainQueue
                                                 usingBlock:^(__unused NSNotification *note) {
        DYPlusLiveRefreshBottomAvoidance();
    }];
}
