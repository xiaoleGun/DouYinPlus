//
//  DYPlusCommentGlass.xm
//  用 iOS 26 系统液态玻璃替换评论面板与输入框的不透明底色。
//  默认使用自适应的 Regular，用户可切换为 Clear；两种材质都不接管文字渲染。
//
//  实现约束：
//
//  · 槽位判据是「子树里唯一不透明的背景色」——面板在 CommentContainerInnerViewController.view，
//    输入栏与输入框各一处。不写死 frame / 层级；其他形态找不到槽位时自动不生效。
//
//  · Regular 不叠加任何 tint，通过玻璃视图的 overrideUserInterfaceStyle 跟随真实场景外观。
//    Clear 浅色不染色，深色沿用 DYYYGlassTintForStyle 的黑色 30% 染色。
//
//  · 玻璃自身必须有有效圆角，宿主 masksToBounds 只是硬裁、不会给玻璃折射与高光。
//    顶部半径取槽位实时 layer.cornerRadius 作为同心圆角下限；输入框跟随槽位实时半径。
//
//  · 新建时 effect=nil 挂载，再在转场协调器或短动画中写入 effect，走系统 materialize；
//    禁止用 alpha 淡入（UIVisualEffectView 文档：alpha < 1 会失真甚至不显示）。
//
//  · 回复态输入区底色槽承载独立平角玻璃，主面板仅在确认它完整覆盖底部时让位。
//    输入框另有独立玻璃，半径跟随宿主；不使用 UIGlassContainerEffect（嵌套会合并形状）。
//
//  · 深浅色从 UIWindowScene 的 trait 取：抖音把 window override 钉死为浅色。
//  · interactive 恒为 YES；玻璃不参与 hit-test，触摸源重定向到对应槽位及其子树。
//  · 主面板若已有其他插件的 effect view，整项让行，只移除自身创建的视图。
//

#import "Integration/Headers/DYPlusAwemeHeaders.h"
#import "Features/Glass/DYPlusCommentGlass.h"
#import "Core/UI/DYPlusGlass.h"
#import "Core/Utilities/DYPlusUtils.h"
#import "Core/Utilities/DYPlusUtils.h"
#import "Core/Utilities/DYPlusUtils.h"
#import "Core/Utilities/DYPlusUtils.h"
#import "Core/Utilities/DYPlusUtils.h"

#import <QuartzCore/QuartzCore.h>
#import <math.h>
#import <objc/runtime.h>

// 依赖的抖音类名集中在此，抖音改名时只改这里。
static NSString *const kDYPlusInnerControllerClass =
    @"AWECommentPanelContainerSwiftImpl.CommentContainerInnerViewController";
static NSString *const kDYPlusInputContainerClass =
    @"AWECommentInputViewSwiftImpl.CommentInputContainerView";

// 输入栏底色槽的尺寸比对容差。
static const CGFloat kDYPlusSlotSizeTolerance = 0.5;
// 槽位尚未写入圆角时的顶部半径下限，保证玻璃有效半径 > 0。
static const CGFloat kDYPlusTopRadiusFloor = 8.0;
// 没有可复用的页面转场时，材质更换使用这个短动画。
#pragma mark - 状态（全部挂在被改动的视图上，多个评论面板并存也互不干扰）

static char kSlotOriginalColorKey;     // 槽位：抖音写的底色
static char kSlotGlassKey;             // 槽位：我们插的玻璃层
static char kCoverOriginalColorKey;    // 满幅遮盖层：抖音写的底色
static char kGlassMaterializingKey;     // 玻璃：已排入 materialize，防止重复排队

// 本次会话是否接管过槽位。开关一直关着的用户不必为每帧的查找与还原付出代价。
static BOOL gEverAttached = NO;
// 所有在场的玻璃层，供深浅色切换时统一更新。
static NSHashTable *gGlassCarriers = nil;
// 已清过底色的满幅遮盖层，关开关时还原。
static NSHashTable *gClearedCovers = nil;
// 已挂上深浅色监听的场景，避免重复注册。
static __weak UIWindowScene *gObservedScene = nil;
// 最近接管的面板槽位与输入框槽位，只给调试探针读。
static __weak UIView *gLastPanelSlot = nil;
static __weak UIView *gLastFieldSlot = nil;
static __weak UIView *gLastInputBackdrop = nil;
static __weak UIViewController *gLastController = nil;
static __weak UIView *gEmoticonPanel = nil;
static NSUInteger gRenderOptimizeBlocks = 0;

static void DYPlusSyncPanelGlassHeight(void);

UIView *DYPlusCommentGlassCurrentSlot(void) {
    return gLastPanelSlot;
}

UIView *DYPlusCommentGlassCurrentField(void) {
    return gLastFieldSlot;
}

#pragma mark - 小工具

static BOOL DYPlusColorIsOpaque(UIColor *color) {
    return color && CGColorGetAlpha(color.CGColor) >= 0.99;
}

static BOOL DYPlusViewIsVisible(UIView *view) {
    return view && !view.hidden && view.alpha >= 0.01;
}

#pragma mark - 材质与外观

// 抖音的 window override 恒为浅色，真实系统外观从 UIWindowScene 取。
static UIUserInterfaceStyle gGlassStyle = UIUserInterfaceStyleUnspecified;

static BOOL DYPlusCommentGlassEnabled(void) {
    return DYPlusGlassOSAvailable() && DYPlusPrefBool(DYPlusKeyCommentGlass);
}

BOOL DYPlusCommentGlassOn(void) {
    return DYPlusCommentGlassEnabled();
}

static BOOL DYPlusCommentGlassUsesClearMaterial(void) {
    return DYPlusGlassOSAvailable() && DYPlusPrefBool(DYPlusKeyCommentGlassClear);
}

// 外观、Regular/Clear 档位或 tint 不变时不重建 effect，避免布局回调打断动画。
static void DYPlusApplyGlassStyle(UIUserInterfaceStyle style, BOOL animated) API_AVAILABLE(ios(26.0)) {
    if (style == UIUserInterfaceStyleUnspecified) return;
    gGlassStyle = style;

    BOOL clear = DYPlusCommentGlassUsesClearMaterial();
    NSArray<UIVisualEffectView *> *carriers = gGlassCarriers.allObjects;
    BOOL needsUpdate = NO;
    for (UIVisualEffectView *glass in carriers) {
        if (DYPlusGlassNeedsUpdate(glass, clear, style)) {
            needsUpdate = YES;
            break;
        }
    }
    if (!needsUpdate) return;

    DYPlusGlassRunAnimation(nil, animated, ^{
        for (UIVisualEffectView *glass in carriers) {
            glass.overrideUserInterfaceStyle = DYPlusGlassOverrideStyle(clear, style);
            if (!glass.effect || !DYPlusGlassNeedsUpdate(glass, clear, style)) continue;
            DYPlusGlassInstallEffect(glass, DYPlusGlassMakeEffect(clear, style, YES), clear, style);
        }
    });
}

// 挂在场景上监听，系统一切深浅色即刻改；否则只能等抖音下次布局。
static void DYPlusObserveGlassStyle(UIView *host) API_AVAILABLE(ios(26.0)) {
    UIWindowScene *scene = host.window.windowScene;
    if (!scene || scene == gObservedScene) return;
    gObservedScene = scene;
    [scene registerForTraitChanges:@[ UITraitUserInterfaceStyle.class ]
                       withHandler:^(UIWindowScene *changed, __unused UITraitCollection *previous) {
        DYPlusApplyGlassStyle(changed.traitCollection.userInterfaceStyle, YES);
    }];
}

#pragma mark - 槽位

// 槽位候选：当前带不透明底色，或底色已被我们清掉但记忆还在。
static BOOL DYPlusIsSlotCandidate(UIView *view) {
    return objc_getAssociatedObject(view, &kSlotOriginalColorKey) != nil
        || DYPlusColorIsOpaque(view.backgroundColor);
}

static void DYPlusCollectSlotCandidates(UIView *view, NSUInteger depth, NSMutableArray<UIView *> *candidates) {
    if (depth > 4) return;
    for (UIView *subview in view.subviews) {
        if ([subview isKindOfClass:UIVisualEffectView.class]) continue;
        if (DYPlusIsSlotCandidate(subview)) [candidates addObject:subview];
        DYPlusCollectSlotCandidates(subview, depth + 1, candidates);
    }
}

// 半屏与全屏复用同一个评论控制器；槽位按结构解析，认不出时不接管。
static UIView *DYPlusPanelSlot(UIViewController *controller) {
    UIViewController *inner = DYPlusChildControllerNamed(controller, kDYPlusInnerControllerClass);
    return inner.isViewLoaded ? inner.view : nil;
}

static UIView *DYPlusInputContainer(UIViewController *controller) {
    Class containerClass = NSClassFromString(kDYPlusInputContainerClass);
    if (!containerClass || !controller.isViewLoaded) return nil;
    for (UIView *subview in controller.view.subviews) {
        if ([subview isKindOfClass:containerClass]) return subview;
    }
    return nil;
}

// 输入栏有两个槽位：铺满容器的底色槽，以及输入框那枚圆角胶囊。
static void DYPlusResolveInputSlots(UIView *container, UIView **backdrop, UIView **field) {
    *backdrop = nil;
    *field = nil;
    if (!container) return;

    NSMutableArray<UIView *> *candidates = [NSMutableArray array];
    DYPlusCollectSlotCandidates(container, 0, candidates);

    CGSize size = container.bounds.size;
    for (UIView *candidate in candidates) {
        CGSize candidateSize = candidate.bounds.size;
        BOOL fillsContainer = fabs(candidateSize.width - size.width) <= kDYPlusSlotSizeTolerance
            && fabs(candidateSize.height - size.height) <= kDYPlusSlotSizeTolerance;
        if (!*backdrop && fillsContainer) {
            *backdrop = candidate;
        } else if (!*field && candidate.layer.cornerRadius > 0.0) {
            *field = candidate;
        }
    }
}

#pragma mark - 玻璃层

typedef NS_ENUM(NSUInteger, DYPlusGlassShape) {
    // 上圆下方：面板与输入栏底色槽；顶部半径跟槽位实时 cornerRadius。
    DYPlusGlassShapeTopRounded = 0,
    // 输入框跟随槽位半径，多行或附图时保持圆角矩形。
    DYPlusGlassShapeField,
    // 平角：输入栏底色槽与主面板玻璃上下拼接，避免回复态露出评论行。
    DYPlusGlassShapeFlat,
};

@interface DYPlusCommentBarGlassView : DYPlusGlassFlexView
@end

@implementation DYPlusCommentBarGlassView

- (void)layoutSubviews {
    [super layoutSubviews];
    DYPlusSyncPanelGlassHeight();
}

@end

// 顶部：同心圆角 + 槽位实时半径作下限，保证折射与高光所需的有效圆角。
// 胶囊：系统 capsuleConfiguration，正方形/扁矩形上都保证有效圆角 > 0。
static void DYPlusApplyGlassShape(UIVisualEffectView *glass, UIView *slot, DYPlusGlassShape shape)
    API_AVAILABLE(ios(26.0)) {
    if (shape == DYPlusGlassShapeFlat) return;
    if (shape == DYPlusGlassShapeField) {
        CGFloat radius = slot.layer.cornerRadius;
        glass.cornerConfiguration = radius > 0.0
            ? [UICornerConfiguration configurationWithUniformRadius:[UICornerRadius fixedRadius:radius]]
            : [UICornerConfiguration capsuleConfiguration];
        return;
    }

    CGFloat floor = slot.layer.cornerRadius;
    if (floor <= 0.0) floor = kDYPlusTopRadiusFloor;
    UICornerRadius *top = [UICornerRadius containerConcentricRadiusWithMinimum:floor];
    glass.cornerConfiguration =
        [UICornerConfiguration configurationWithUniformTopRadius:top
                                                bottomLeftRadius:nil
                                               bottomRightRadius:nil];
}

// 仅在 effect 仍为 nil 时写入，让系统 materialize 动画跑一次。
static void DYPlusMaterializeGlass(UIVisualEffectView *glass, UIViewController *controller)
    API_AVAILABLE(ios(26.0)) {
    if (!glass || glass.effect || [objc_getAssociatedObject(glass, &kGlassMaterializingKey) boolValue]) return;
    objc_setAssociatedObject(glass, &kGlassMaterializingKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    DYPlusGlassRunAnimation(controller, YES, ^{
        if (!glass.superview || !DYPlusCommentGlassEnabled()) {
            objc_setAssociatedObject(glass, &kGlassMaterializingKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            return;
        }

        UIUserInterfaceStyle style = gGlassStyle;
        if (style == UIUserInterfaceStyleUnspecified) style = DYPlusGlassStyleForView(glass);
        BOOL clear = DYPlusCommentGlassUsesClearMaterial();
        glass.overrideUserInterfaceStyle = DYPlusGlassOverrideStyle(clear, style);
        DYPlusGlassInstallEffect(glass, DYPlusGlassMakeEffect(clear, style, YES), clear, style);
        objc_setAssociatedObject(glass, &kGlassMaterializingKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        DYPlusSyncPanelGlassHeight();
    });
}

// 记下并清掉槽位的不透明底色。返回 NO 表示这个槽位不该接管——它本来就没有底色。
// 输入栏底色槽只做到这一步：它落在主面板槽位的矩形之内，清成透明后主面板玻璃直接透上来，
// 不必也不该再给它单独一块玻璃。
static BOOL DYPlusClearSlotColor(UIView *slot) {
    if (objc_getAssociatedObject(slot, &kSlotOriginalColorKey)) {
        if (DYPlusColorIsOpaque(slot.backgroundColor)) slot.backgroundColor = UIColor.clearColor;
        return YES;
    }
    UIColor *current = slot.backgroundColor;
    if (!DYPlusColorIsOpaque(current)) return NO;
    objc_setAssociatedObject(slot, &kSlotOriginalColorKey, current, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    slot.backgroundColor = UIColor.clearColor;
    gEverAttached = YES;
    return YES;
}

// 主面板列表若被涂成不透明色，会盖住垫在最底层的玻璃。只动满幅容器，不动文字/按钮/图片。
static const NSUInteger kDYPlusCoverWalkDepth = 14;
static const CGFloat kDYPlusCoverMinHeight = 8.0;

static BOOL DYPlusIsCoverCandidate(UIView *view, UIView *slot) {
    if (!view || view == slot) return NO;
    if (view.hidden || view.alpha < 0.01) return NO;
    if ([view isKindOfClass:UILabel.class]
        || [view isKindOfClass:UIControl.class]
        || [view isKindOfClass:UIImageView.class]
        || [view isKindOfClass:UIVisualEffectView.class]) {
        return NO;
    }
    if (!DYPlusColorIsOpaque(view.backgroundColor)) return NO;
    if (fabs(CGRectGetWidth(view.bounds) - CGRectGetWidth(slot.bounds)) > 1.0) return NO;
    if (CGRectGetHeight(view.bounds) < kDYPlusCoverMinHeight) return NO;
    return YES;
}

static void DYPlusClearCoverColor(UIView *view) {
    if (objc_getAssociatedObject(view, &kCoverOriginalColorKey)) {
        if (DYPlusColorIsOpaque(view.backgroundColor)) view.backgroundColor = UIColor.clearColor;
        return;
    }
    if (!DYPlusColorIsOpaque(view.backgroundColor)) return;
    objc_setAssociatedObject(view, &kCoverOriginalColorKey,
                             view.backgroundColor, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [gClearedCovers addObject:view];
    view.backgroundColor = UIColor.clearColor;
}

static void DYPlusWalkClearCovers(UIView *view, UIView *slot, NSUInteger depth) {
    if (depth > kDYPlusCoverWalkDepth) return;
    for (UIView *sub in view.subviews) {
        if ([sub isKindOfClass:UIVisualEffectView.class]) continue;
        if (DYPlusIsCoverCandidate(sub, slot)) DYPlusClearCoverColor(sub);
        if ([sub isKindOfClass:UILabel.class] || [sub isKindOfClass:UIImageView.class]) continue;
        DYPlusWalkClearCovers(sub, slot, depth + 1);
    }
}

static void DYPlusClearCoverLayers(UIView *slot) {
    if (!slot) return;
    DYPlusWalkClearCovers(slot, slot, 0);
}

static void DYPlusRestoreCoverColor(UIView *view) {
    UIColor *original = objc_getAssociatedObject(view, &kCoverOriginalColorKey);
    if (!original) return;
    objc_setAssociatedObject(view, &kCoverOriginalColorKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    view.backgroundColor = original;
}

static void DYPlusRestoreAllCovers(void) {
    NSArray<UIView *> *views = gClearedCovers.allObjects;
    [gClearedCovers removeAllObjects];
    for (UIView *view in views) DYPlusRestoreCoverColor(view);
}

// 接管一个槽位：清掉它的不透明底色，在最底层插一层玻璃壳。
// requireOpaque：输入框胶囊必须本来有底色；主面板槽位按类名认定，底色透明也要挂。
// 返回 nil 表示这个槽位不该接管——已被别的插件插了玻璃，或（输入框）没有底色。
static UIView *DYPlusAttachGlass(UIView *slot, DYPlusGlassShape shape, BOOL requireOpaque)
    API_AVAILABLE(ios(26.0)) {
    UIView *glass = objc_getAssociatedObject(slot, &kSlotGlassKey);
    // 退让只在尚未接管时判定；接管之后层级由 DYYYGlassEnsureBackmost 维持，不能再据此退出。
    if (!glass && [slot.subviews.firstObject isKindOfClass:UIVisualEffectView.class]) return nil;

    BOOL cleared = DYPlusClearSlotColor(slot);
    if (requireOpaque && !cleared) return nil;

    if (!glass) {
        glass = shape == DYPlusGlassShapeFlat
            ? [[DYPlusCommentBarGlassView alloc] initWithEffect:nil]
            : DYPlusGlassMakeShell();
        objc_setAssociatedObject(slot, &kSlotGlassKey, glass, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [gGlassCarriers addObject:glass];
        gEverAttached = YES;
    }

    // 槽位作为触摸源时包含它的整棵子树，面板列表与输入控件都不必单独枚举。
    ((DYPlusGlassFlexView *)glass).flexSourceView = slot;
    DYPlusApplyGlassShape((UIVisualEffectView *)glass, slot, shape);
    return glass;
}

static void DYPlusDetachGlass(UIView *slot) {
    UIView *glass = objc_getAssociatedObject(slot, &kSlotGlassKey);
    UIColor *original = objc_getAssociatedObject(slot, &kSlotOriginalColorKey);
    if (!glass && !original) return;

    [glass removeFromSuperview];
    if (original) slot.backgroundColor = original;

    objc_setAssociatedObject(slot, &kSlotOriginalColorKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(slot, &kSlotGlassKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

static BOOL DYPlusViewChainVisible(UIView *view) {
    for (UIView *node = view; node; node = node.superview) {
        if (!DYPlusViewIsVisible(node)) return NO;
    }
    return YES;
}

// 只在输入栏玻璃已实际渲染、同窗口且完整覆盖面板底部时，让主面板让位。
// 判据不成立时保留满幅主玻璃，宁可短暂重叠，也不留下原始视频的空洞。
static void DYPlusSyncPanelGlassHeight(void) {
    UIView *slot = gLastPanelSlot;
    UIVisualEffectView *panelGlass = objc_getAssociatedObject(slot, &kSlotGlassKey);
    UIVisualEffectView *inputGlass = objc_getAssociatedObject(gLastInputBackdrop, &kSlotGlassKey);
    if (!slot || !panelGlass || !DYPlusCommentGlassEnabled()) return;

    CGRect target = slot.bounds;
    if (inputGlass.effect && inputGlass.window && inputGlass.window == slot.window
        && DYPlusViewChainVisible(inputGlass)
        && gLastInputBackdrop.superview
        && [gLastInputBackdrop isDescendantOfView:slot.superview]) {
        CGRect cover = [inputGlass convertRect:inputGlass.bounds toView:slot];
        if (CGRectGetMinX(cover) <= 0.5
            && CGRectGetMaxX(cover) >= CGRectGetWidth(slot.bounds) - 0.5
            && CGRectGetMaxY(cover) >= CGRectGetHeight(slot.bounds) - 0.5
            && CGRectGetMinY(cover) > 0.0) {
            target.size.height = CGRectGetMinY(cover);
        }
    }
    if (!CGRectEqualToRect(panelGlass.frame, target)) panelGlass.frame = target;
}

// 小表情栏位于键盘的独立 window。只有能证明它完全落在输入栏玻璃之内时才清底色，
// 否则保留抖音原样，避免出现没有玻璃承接的透明横条。
static void DYPlusApplyEmoticonPanel(void) {
    UIView *panel = gEmoticonPanel;
    UIVisualEffectView *inputGlass = objc_getAssociatedObject(gLastInputBackdrop, &kSlotGlassKey);
    if (!panel || !inputGlass || !DYPlusCommentGlassEnabled() || !inputGlass.effect) return;
    CGRect panelRect = [panel convertRect:panel.bounds toView:nil];
    CGRect glassRect = [inputGlass convertRect:inputGlass.bounds toView:nil];
    if (CGRectContainsRect(CGRectInset(glassRect, -0.5, -0.5), panelRect)) {
        DYPlusClearCoverColor(panel);
    }
}

#pragma mark - 同步

// 输入栏在「移除评论区底栏」开启时被压成 alpha 0，此时整段不做；它的显隐 owner 是
// DYYYCommentBottomBar，这里只读不写。只挂壳与几何，effect 由调用方在 CATransaction 外 materialize。
//
// 回复态输入栏会移动到评论列表中段，因此底色槽本身也要承载一块平角玻璃；
// 主面板玻璃据此让位，避免玻璃重叠造成明显亮度台阶。
static void DYPlusSyncInputGlass(UIView *container) API_AVAILABLE(ios(26.0)) {
    if (!DYPlusViewIsVisible(container)) return;

    UIView *backdrop = nil;
    UIView *field = nil;
    DYPlusResolveInputSlots(container, &backdrop, &field);

    UIVisualEffectView *backdropGlass = backdrop
        ? (UIVisualEffectView *)DYPlusAttachGlass(backdrop, DYPlusGlassShapeFlat, YES) : nil;
    if (backdropGlass) {
        gLastInputBackdrop = backdrop;
        ((DYPlusGlassFlexView *)backdropGlass).flexSourceView = container;
        if (!CGRectEqualToRect(backdropGlass.frame, backdrop.bounds)) backdropGlass.frame = backdrop.bounds;
        DYPlusGlassEnsureBackmost(backdrop, backdropGlass);
    }
    if (!field) return;

    // 胶囊不用 UIGlassContainerEffect：嵌套会被合并成同一形状。
    UIVisualEffectView *glass = (UIVisualEffectView *)DYPlusAttachGlass(field, DYPlusGlassShapeField, YES);
    if (!glass) return;
    gLastFieldSlot = field;
    if (!CGRectEqualToRect(glass.frame, field.bounds)) glass.frame = field.bounds;
    DYPlusGlassEnsureBackmost(field, glass);
}

static void DYPlusMaterializeSlotGlass(UIView *slot, UIViewController *controller) API_AVAILABLE(ios(26.0)) {
    if (!slot) return;
    UIVisualEffectView *glass = objc_getAssociatedObject(slot, &kSlotGlassKey);
    if (glass) DYPlusMaterializeGlass(glass, controller);
}

static void DYPlusCommentGlassSync(UIViewController *controller) API_AVAILABLE(ios(26.0)) {
    BOOL enabled = DYPlusCommentGlassEnabled();
    if (!enabled && !gEverAttached) return;

    UIView *panel = DYPlusPanelSlot(controller);
    if (!panel) return;

    UIView *inputContainer = DYPlusInputContainer(controller);

    if (!enabled) {
        // 还原一次即收敛：槽位记忆清空后，后续布局只剩几次空查找。
        DYPlusDetachGlass(panel);
        UIView *backdrop = nil;
        UIView *field = nil;
        DYPlusResolveInputSlots(inputContainer, &backdrop, &field);
        DYPlusDetachGlass(backdrop);
        DYPlusDetachGlass(field);
        DYPlusRestoreAllCovers();
        return;
    }

    DYPlusObserveGlassStyle(panel);
    UIUserInterfaceStyle style = DYPlusGlassStyleForView(panel);

    // 本函数可能落在抖音的布局或键盘动画里，隐式动画会让玻璃几何拖在内容后面。
    // materialize 在几何就位后单独执行，不受这个 CATransaction 影响。
    UIVisualEffectView *panelGlass = nil;
    [CATransaction begin];
    [CATransaction setDisableActions:YES];

    panelGlass = (UIVisualEffectView *)DYPlusAttachGlass(panel, DYPlusGlassShapeTopRounded, NO);
    if (panelGlass) {
        gLastPanelSlot = panel;

        gLastController = controller;
        DYPlusGlassEnsureBackmost(panel, panelGlass);
        DYPlusClearCoverLayers(panel);

        DYPlusSyncInputGlass(inputContainer);
        DYPlusSyncPanelGlassHeight();
    }

    [CATransaction commit];

    // 几何就位后统一更新已存在的材质，再让新玻璃从 nil → effect materialize。
    if (panelGlass) {
        DYPlusApplyGlassStyle(style, YES);
        DYPlusMaterializeGlass(panelGlass, controller);
        if (DYPlusViewIsVisible(inputContainer)) {
            UIView *backdrop = nil;
            UIView *field = nil;
            DYPlusResolveInputSlots(inputContainer, &backdrop, &field);
            DYPlusMaterializeSlotGlass(backdrop, controller);
            DYPlusMaterializeSlotGlass(field, controller);
        }
        DYPlusApplyEmoticonPanel();
    }
}

#pragma mark - Hook

// DYYYCommentBottomBar.xm 也在这两个方法上挂了一层（底栏抑制），两处分属两个功能、各有各的开关，
// 本文件这一层还整体受 iOS 26 可用性约束。多层 %hook 会正常串联，两条同时生效。
%group DYPlusCommentGlassHooks

%hook AWECommentContainerViewController

- (void)viewWillAppear:(BOOL)animated {
    %orig;
    if (@available(iOS 26.0, *)) DYPlusCommentGlassSync(self);
}

- (void)viewDidLayoutSubviews {
    %orig;
    if (@available(iOS 26.0, *)) DYPlusCommentGlassSync(self);
}

%end

%hook UIView

- (void)setBackgroundColor:(UIColor *)color {
    if ((objc_getAssociatedObject(self, &kCoverOriginalColorKey)
         || objc_getAssociatedObject(self, &kSlotOriginalColorKey))
        && DYPlusColorIsOpaque(color)) {
        %orig(UIColor.clearColor);
        return;
    }
    %orig;
}

%end

%end

%group DYPlusCommentEmoticonHook

%hook AWECommentMiniEmoticonPanelView

- (void)layoutSubviews {
    %orig;
    gEmoticonPanel = self;
    if (@available(iOS 26.0, *)) {
        DYPlusApplyEmoticonPanel();
        if (gLastController && !objc_getAssociatedObject(gLastInputBackdrop, &kSlotGlassKey)) {
            DYPlusCommentGlassSync(gLastController);
        }
    }
}

%end

%end

// 热更新启用的不透明绘制优化会把评论列表和文字视图刷成实色，遮住液态玻璃。
// 仅在评论玻璃实际开启时关闭该 AB 网关；类或方法不存在时不会安装本 hook。
%group DYPlusCommentRenderOptimizeHook

%hook AWECommentABTestSettings

+ (BOOL)enableCommentRenderingOptimize:(id)context {
    if (DYPlusCommentGlassEnabled()) {
        gRenderOptimizeBlocks++;
        return NO;
    }
    return %orig;
}

%end

%end

#pragma mark - 设置项注册

%ctor {
    gGlassCarriers = [NSHashTable weakObjectsHashTable];
    gClearedCovers = [NSHashTable weakObjectsHashTable];

    if (DYPlusGlassOSAvailable()) {
        %init(DYPlusCommentGlassHooks);
        if (NSClassFromString(@"AWECommentMiniEmoticonPanelView")) {
            %init(DYPlusCommentEmoticonHook);
        }
        Class abTest = NSClassFromString(@"AWECommentABTestSettings");
        if ([abTest respondsToSelector:@selector(enableCommentRenderingOptimize:)]) {
            %init(DYPlusCommentRenderOptimizeHook);
        }
    }
}
