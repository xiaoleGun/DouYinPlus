//
//  DYPlusInnerNotificationGlass.xm
//  应用内通知横幅：白卡片换成系统液态玻璃，回复键走官方玻璃按钮，角标改成正圆玻璃。
//  只藏私信副标题里的「私信了你:」；其它文字不接管。
//

#import "Integration/Headers/DYPlusAwemeHeaders.h"
#import "Core/UI/DYPlusGlass.h"
#import "Core/Utilities/DYPlusUtils.h"

#import <objc/runtime.h>

static const CGFloat kDYPlusNotiNativeCorner = 12.0;
static const NSInteger kDYPlusNotiCornerDefault = 100;
static NSString *const kDYPlusNotiHintPrefix = @"私信了你";

static char kSlotColorKey;
static char kSlotGlassKey;
static char kSlotMarkedKey;
static char kGlassMaterializingKey;
static char kCornerRadiusKey;
static char kCornerConfigKey;
static char kActionConfigKey;
static char kActionColorKey;
static char kActionTitleKey;
static char kActionAttrTitleKey;
static char kActionForegroundKey;
static char kActionClearKey;
static char kBadgeColorKey;
static char kBadgeGlassKey;
static char kHintHiddenKey;
static char kInkOriginalKey;
static char kInkAppliedKey;

static NSHashTable *gGlassCarriers;
static NSHashTable<AWEInnerNotificationContainerView *> *gContainers;
static NSHashTable<AWEInnerPushCommonView *> *gCommonViews;
static BOOL gEverAttached = NO;
static BOOL gInkReapplying = NO;
static __weak UIWindowScene *gObservedScene = nil;
static UIUserInterfaceStyle gGlassStyle = UIUserInterfaceStyleUnspecified;

static UIView *DYPlusNotiSlot(AWEInnerNotificationContainerView *container);
static void DYPlusNotiApplyInkText(UIView *root, BOOL clear, UIUserInterfaceStyle style);
static void DYPlusNotiRestoreInkText(UIView *root);

#pragma mark - 开关与材质

static BOOL DYPlusNotiEnabled(void) {
    return DYPlusGlassOSAvailable() && DYPlusPrefBool(DYPlusKeyInnerNotiGlass);
}

static BOOL DYPlusNotiUsesClear(void) {
    return DYPlusGlassOSAvailable() && DYPlusPrefBool(DYPlusKeyInnerNotiGlassClear);
}

// 未写过键时保持胶囊（100），与 beta7 观感一致。
static CGFloat DYPlusNotiCornerProgress(void) {
    NSNumber *stored = [NSUserDefaults.standardUserDefaults objectForKey:DYPlusKeyInnerNotiCorner];
    NSInteger percent = stored ? stored.integerValue : kDYPlusNotiCornerDefault;
    if (percent < 0) percent = 0;
    if (percent > 100) percent = 100;
    return percent / 100.0;
}

static BOOL DYPlusNotiColorOpaque(UIColor *color) {
    return color && CGColorGetAlpha(color.CGColor) >= 0.99;
}

static void DYPlusNotiApplyStyle(UIUserInterfaceStyle style, BOOL animated) API_AVAILABLE(ios(26.0)) {
    if (style == UIUserInterfaceStyleUnspecified) return;
    gGlassStyle = style;
    if (!DYPlusNotiEnabled()) return;
    BOOL clear = DYPlusNotiUsesClear();
    for (AWEInnerPushCommonView *common in gCommonViews.allObjects) {
        DYPlusNotiApplyInkText(common, clear, style);
    }
    for (AWEInnerNotificationContainerView *container in gContainers.allObjects) {
        DYPlusNotiApplyInkText(DYPlusNotiSlot(container), clear, style);
    }
    BOOL needs = NO;
    for (UIVisualEffectView *glass in gGlassCarriers.allObjects) {
        if (DYPlusGlassNeedsUpdate(glass, clear, style)) {
            needs = YES;
            break;
        }
    }
    if (!needs) return;

    DYPlusGlassRunAnimation(nil, animated, ^{
        for (UIVisualEffectView *glass in gGlassCarriers.allObjects) {
            glass.overrideUserInterfaceStyle = DYPlusGlassOverrideStyle(clear, style);
            if (!glass.effect || !DYPlusGlassNeedsUpdate(glass, clear, style)) continue;
            DYPlusGlassInstallEffect(glass, DYPlusGlassMakeEffect(clear, style, YES), clear, style);
        }
    });
}

static void DYPlusNotiObserveStyle(UIView *host) API_AVAILABLE(ios(26.0)) {
    UIWindowScene *scene = host.window.windowScene;
    if (!scene || scene == gObservedScene) return;
    gObservedScene = scene;
    [scene registerForTraitChanges:@[ UITraitUserInterfaceStyle.class ]
                       withHandler:^(UIWindowScene *changed, __unused UITraitCollection *previous) {
        DYPlusNotiApplyStyle(changed.traitCollection.userInterfaceStyle, YES);
    }];
}

static BOOL DYPlusNotiRectUsable(CGRect rect) {
    return CGRectGetWidth(rect) >= 8.0 && CGRectGetHeight(rect) >= 8.0;
}

// 0 尺寸写入 UIGlassEffect 不会建材质层，之后只改 frame 补不回来。
static void DYPlusNotiPlaceGlass(UIVisualEffectView *glass, UIView *slot) {
    if (!glass || !slot) return;
    BOOL wasEmpty = !DYPlusNotiRectUsable(glass.bounds);
    if (!CGRectEqualToRect(glass.frame, slot.bounds)) glass.frame = slot.bounds;
    DYPlusGlassEnsureBackmost(slot, glass);
    if (wasEmpty && DYPlusNotiRectUsable(glass.bounds) && glass.effect) {
        glass.effect = nil;
        objc_setAssociatedObject(glass, &kGlassMaterializingKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
}

static void DYPlusNotiMaterialize(UIVisualEffectView *glass) API_AVAILABLE(ios(26.0)) {
    if (!glass || !DYPlusNotiRectUsable(glass.bounds) || glass.effect
        || [objc_getAssociatedObject(glass, &kGlassMaterializingKey) boolValue]) {
        return;
    }
    objc_setAssociatedObject(glass, &kGlassMaterializingKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    DYPlusGlassRunAnimation(nil, YES, ^{
        if (!glass.superview || !DYPlusNotiEnabled()) {
            objc_setAssociatedObject(glass, &kGlassMaterializingKey,
                                     nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            return;
        }
        UIUserInterfaceStyle style = gGlassStyle;
        if (style == UIUserInterfaceStyleUnspecified) style = DYPlusGlassStyleForView(glass);
        BOOL clear = DYPlusNotiUsesClear();
        glass.overrideUserInterfaceStyle = DYPlusGlassOverrideStyle(clear, style);
        DYPlusGlassInstallEffect(glass, DYPlusGlassMakeEffect(clear, style, YES), clear, style);
        objc_setAssociatedObject(glass, &kGlassMaterializingKey,
                                 nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    });
}

#pragma mark - 圆角

static void DYPlusNotiRememberCorners(UIView *view) {
    if (!view || objc_getAssociatedObject(view, &kCornerRadiusKey)) return;
    objc_setAssociatedObject(view, &kCornerRadiusKey,
                             @(view.layer.cornerRadius), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    if ([view respondsToSelector:@selector(cornerConfiguration)]) {
        objc_setAssociatedObject(view, &kCornerConfigKey,
                                 view.cornerConfiguration, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
}

static UICornerConfiguration *DYPlusNotiCardCornerConfig(UIView *view) API_AVAILABLE(ios(26.0)) {
    DYPlusNotiRememberCorners(view);
    CGFloat native = kDYPlusNotiNativeCorner;
    NSNumber *remembered = objc_getAssociatedObject(view, &kCornerRadiusKey);
    if (remembered && remembered.doubleValue > 0.0) native = remembered.doubleValue;
    CGFloat capsule = MIN(CGRectGetWidth(view.bounds), CGRectGetHeight(view.bounds)) * 0.5;
    if (capsule < native) capsule = native;
    CGFloat radius = native + (capsule - native) * DYPlusNotiCornerProgress();
    view.layer.cornerRadius = radius;
    return [UICornerConfiguration configurationWithUniformRadius:[UICornerRadius fixedRadius:radius]];
}

static void DYPlusNotiApplyCardShape(UIView *view, UIVisualEffectView *glass) API_AVAILABLE(ios(26.0)) {
    if (!view) return;
    UICornerConfiguration *config = DYPlusNotiCardCornerConfig(view);
    if ([view respondsToSelector:@selector(setCornerConfiguration:)]) {
        view.cornerConfiguration = config;
    }
    if (glass && [glass respondsToSelector:@selector(setCornerConfiguration:)]) {
        glass.cornerConfiguration = config;
    }
}

static void DYPlusNotiApplyCapsule(UIView *view) API_AVAILABLE(ios(26.0)) {
    if (!view) return;
    DYPlusNotiRememberCorners(view);
    if ([view respondsToSelector:@selector(setCornerConfiguration:)]) {
        view.cornerConfiguration = [UICornerConfiguration capsuleConfiguration];
    }
    CGFloat height = CGRectGetHeight(view.bounds);
    if (height >= 1.0) view.layer.cornerRadius = height * 0.5;
}

static void DYPlusNotiRestoreCorners(UIView *view) {
    NSNumber *radius = objc_getAssociatedObject(view, &kCornerRadiusKey);
    if (!view || !radius) return;
    if ([view respondsToSelector:@selector(setCornerConfiguration:)]) {
        view.cornerConfiguration = objc_getAssociatedObject(view, &kCornerConfigKey);
    }
    view.layer.cornerRadius = radius.doubleValue;
    objc_setAssociatedObject(view, &kCornerRadiusKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(view, &kCornerConfigKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

#pragma mark - 查找

static AWEInnerNotificationContainerView *DYPlusNotiContainerOf(UIView *view) {
    while (view) {
        if ([view isKindOfClass:%c(AWEInnerNotificationContainerView)]) {
            return (AWEInnerNotificationContainerView *)view;
        }
        view = view.superview;
    }
    return nil;
}

static UIView *DYPlusNotiSlot(AWEInnerNotificationContainerView *container) {
    UIView *marked = objc_getAssociatedObject(container, &kSlotMarkedKey);
    if (marked.superview == container) return marked;

    if ([container respondsToSelector:@selector(containerView)]) {
        UIView *candidate = container.containerView;
        if (candidate.superview == container
            && (DYPlusNotiColorOpaque(candidate.backgroundColor)
                || objc_getAssociatedObject(candidate, &kSlotColorKey))) {
            return candidate;
        }
    }
    for (UIView *child in container.subviews) {
        if (child.hidden) continue;
        if (DYPlusNotiColorOpaque(child.backgroundColor)
            || objc_getAssociatedObject(child, &kSlotColorKey)) {
            return child;
        }
    }
    return nil;
}

static AWEInnerPushCommonView *DYPlusNotiCommonIn(UIView *view, NSUInteger depth) {
    if (!view || depth > 6) return nil;
    if ([view isKindOfClass:%c(AWEInnerPushCommonView)]) return (AWEInnerPushCommonView *)view;
    for (UIView *child in view.subviews) {
        AWEInnerPushCommonView *found = DYPlusNotiCommonIn(child, depth + 1);
        if (found) return found;
    }
    return nil;
}

#pragma mark - 卡片

static BOOL DYPlusNotiClearSlot(UIView *slot) {
    UIColor *current = slot.backgroundColor;
    if (DYPlusNotiColorOpaque(current)) {
        if (!objc_getAssociatedObject(slot, &kSlotColorKey)) {
            objc_setAssociatedObject(slot, &kSlotColorKey, current, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        slot.backgroundColor = UIColor.clearColor;
        gEverAttached = YES;
        return YES;
    }
    return objc_getAssociatedObject(slot, &kSlotColorKey) != nil;
}

static UIVisualEffectView *DYPlusNotiAttachCard(AWEInnerNotificationContainerView *container,
                                            UIView *slot)
    API_AVAILABLE(ios(26.0)) {
    if (!DYPlusNotiClearSlot(slot)) return nil;

    UIVisualEffectView *glass = objc_getAssociatedObject(slot, &kSlotGlassKey);
    if (!glass) {
        UIView *first = slot.subviews.firstObject;
        if ([first isKindOfClass:UIVisualEffectView.class]
            && first != objc_getAssociatedObject(slot, &kSlotGlassKey)) {
            return nil;
        }
        glass = DYPlusGlassMakeShell();
        ((DYPlusGlassFlexView *)glass).flexSourceView = container;
        objc_setAssociatedObject(slot, &kSlotGlassKey, glass, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(container, &kSlotMarkedKey, slot, OBJC_ASSOCIATION_ASSIGN);
        [gGlassCarriers addObject:glass];
        gEverAttached = YES;
    }

    DYPlusNotiApplyCardShape(container, glass);
    DYPlusNotiApplyCardShape(slot, glass);
    DYPlusNotiPlaceGlass(glass, slot);
    return glass;
}

static void DYPlusNotiDetachCard(AWEInnerNotificationContainerView *container) {
    UIView *slot = DYPlusNotiSlot(container);
    if (!slot) return;
    UIView *glass = objc_getAssociatedObject(slot, &kSlotGlassKey);
    [gGlassCarriers removeObject:glass];
    [glass removeFromSuperview];
    UIColor *original = objc_getAssociatedObject(slot, &kSlotColorKey);
    if (original) slot.backgroundColor = original;
    DYPlusNotiRestoreCorners(slot);
    DYPlusNotiRestoreCorners(container);
    objc_setAssociatedObject(slot, &kSlotColorKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(slot, &kSlotGlassKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(container, &kSlotMarkedKey, nil, OBJC_ASSOCIATION_ASSIGN);
}

#pragma mark - 回复键

static BOOL DYPlusNotiActionHasGlass(UIButton *button) {
    return button.configuration && objc_getAssociatedObject(button, &kActionClearKey);
}

static void DYPlusNotiRememberAction(UIButton *button) {
    if (!button || DYPlusNotiActionHasGlass(button)) return;
    if (button.configuration && !objc_getAssociatedObject(button, &kActionConfigKey)) {
        objc_setAssociatedObject(button, &kActionConfigKey,
                                 button.configuration, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    if (button.backgroundColor) {
        objc_setAssociatedObject(button, &kActionColorKey,
                                 button.backgroundColor, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    NSAttributedString *attributed = button.currentAttributedTitle;
    if (attributed.length) {
        objc_setAssociatedObject(button, &kActionAttrTitleKey,
                                 attributed, OBJC_ASSOCIATION_COPY_NONATOMIC);
    }
    NSString *title = button.currentTitle.length ? button.currentTitle : attributed.string;
    if (title.length) {
        objc_setAssociatedObject(button, &kActionTitleKey,
                                 title, OBJC_ASSOCIATION_COPY_NONATOMIC);
    }
    UIColor *foreground = nil;
    if (attributed.length) {
        foreground = [attributed attribute:NSForegroundColorAttributeName
                                   atIndex:0
                            effectiveRange:NULL];
    }
    if (!foreground) foreground = [button titleColorForState:UIControlStateNormal];
    if (foreground) {
        objc_setAssociatedObject(button, &kActionForegroundKey,
                                 foreground, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
}

static UIButtonConfiguration *DYPlusNotiMakeActionConfig(BOOL clear) API_AVAILABLE(ios(26.0)) {
    UIButtonConfiguration *config = nil;
    if (clear && [UIButtonConfiguration respondsToSelector:@selector(clearGlassButtonConfiguration)]) {
        config = [UIButtonConfiguration clearGlassButtonConfiguration];
    } else if ([UIButtonConfiguration respondsToSelector:@selector(glassButtonConfiguration)]) {
        config = [UIButtonConfiguration glassButtonConfiguration];
    }
    if (!config) return nil;
    config.cornerStyle = UIButtonConfigurationCornerStyleCapsule;
    return config;
}

static void DYPlusNotiWriteActionTitle(UIButton *button, UIButtonConfiguration *config) {
    NSAttributedString *attributed = objc_getAssociatedObject(button, &kActionAttrTitleKey);
    NSString *title = objc_getAssociatedObject(button, &kActionTitleKey);
    UIColor *foreground = objc_getAssociatedObject(button, &kActionForegroundKey);
    if (attributed.length) {
        config.attributedTitle = attributed;
    } else if (title.length) {
        config.title = title;
    }
    if (foreground) config.baseForegroundColor = foreground;
}

static void DYPlusNotiRestoreAction(UIButton *button) {
    if (!button || !objc_getAssociatedObject(button, &kActionForegroundKey)) return;
    UIButtonConfiguration *original = objc_getAssociatedObject(button, &kActionConfigKey);
    button.configuration = original;
    UIColor *color = objc_getAssociatedObject(button, &kActionColorKey);
    if (color) button.backgroundColor = color;
    if (!original) {
        NSAttributedString *attributed = objc_getAssociatedObject(button, &kActionAttrTitleKey);
        NSString *title = objc_getAssociatedObject(button, &kActionTitleKey);
        UIColor *foreground = objc_getAssociatedObject(button, &kActionForegroundKey);
        if (attributed) {
            [button setAttributedTitle:attributed forState:UIControlStateNormal];
        } else if (title) {
            [button setTitle:title forState:UIControlStateNormal];
        }
        if (foreground) [button setTitleColor:foreground forState:UIControlStateNormal];
    }
    objc_setAssociatedObject(button, &kActionConfigKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(button, &kActionColorKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(button, &kActionTitleKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(button, &kActionAttrTitleKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(button, &kActionForegroundKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(button, &kActionClearKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

static void DYPlusNotiApplyAction(UIButton *button) API_AVAILABLE(ios(26.0)) {
    if (!button || button.hidden || button.alpha < 0.01) {
        if (button) DYPlusNotiRestoreAction(button);
        return;
    }

    DYPlusNotiRememberAction(button);
    if (objc_getAssociatedObject(button, &kActionColorKey)) {
        button.backgroundColor = UIColor.clearColor;
    }

    BOOL clear = DYPlusNotiUsesClear();
    NSNumber *installed = objc_getAssociatedObject(button, &kActionClearKey);
    if (DYPlusNotiActionHasGlass(button) && installed.boolValue == clear) return;

    UIButtonConfiguration *config = DYPlusNotiMakeActionConfig(clear);
    if (!config) return;
    DYPlusNotiWriteActionTitle(button, config);
    button.configuration = config;
    objc_setAssociatedObject(button, &kActionClearKey, @(clear), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    gEverAttached = YES;
}

#pragma mark - 角标

static void DYPlusNotiRestoreBadge(UIView *badge) {
    if (!badge) return;
    UIView *glass = objc_getAssociatedObject(badge, &kBadgeGlassKey);
    [gGlassCarriers removeObject:glass];
    [glass removeFromSuperview];
    UIColor *original = objc_getAssociatedObject(badge, &kBadgeColorKey);
    if (original) badge.backgroundColor = original;
    DYPlusNotiRestoreCorners(badge);
    objc_setAssociatedObject(badge, &kBadgeColorKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(badge, &kBadgeGlassKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

static void DYPlusNotiApplyBadge(UIView *badge) API_AVAILABLE(ios(26.0)) {
    if (!badge || badge.hidden || badge.alpha < 0.01) {
        if (badge) DYPlusNotiRestoreBadge(badge);
        return;
    }

    UIColor *current = badge.backgroundColor;
    if (DYPlusNotiColorOpaque(current)) {
        if (!objc_getAssociatedObject(badge, &kBadgeColorKey)) {
            objc_setAssociatedObject(badge, &kBadgeColorKey, current, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        badge.backgroundColor = UIColor.clearColor;
    } else if (!objc_getAssociatedObject(badge, &kBadgeColorKey)) {
        return;
    }

    UIVisualEffectView *glass = objc_getAssociatedObject(badge, &kBadgeGlassKey);
    if (!glass) {
        glass = DYPlusGlassMakeShell();
        glass.cornerConfiguration = [UICornerConfiguration capsuleConfiguration];
        ((DYPlusGlassFlexView *)glass).flexSourceView = badge;
        objc_setAssociatedObject(badge, &kBadgeGlassKey, glass, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [gGlassCarriers addObject:glass];
        gEverAttached = YES;
    }
    DYPlusNotiApplyCapsule(badge);
    DYPlusNotiPlaceGlass(glass, badge);
    DYPlusNotiMaterialize(glass);
}

#pragma mark - 「私信了你」

static BOOL DYPlusNotiIsHintText(NSString *text) {
    if (text.length < kDYPlusNotiHintPrefix.length) return NO;
    NSString *trimmed = [text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (![trimmed hasPrefix:kDYPlusNotiHintPrefix]) return NO;
    NSString *rest = [trimmed substringFromIndex:kDYPlusNotiHintPrefix.length];
    static NSCharacterSet *junk;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        junk = [NSCharacterSet characterSetWithCharactersInString:@":： "];
    });
    return [rest stringByTrimmingCharactersInSet:junk].length == 0;
}

static void DYPlusNotiWalkLabels(UIView *view, NSUInteger depth, void (^block)(UILabel *label)) {
    if (!view || depth > 8 || !block) return;
    if ([view isKindOfClass:UIControl.class]) return;
    if ([view isKindOfClass:UILabel.class]) block((UILabel *)view);
    for (UIView *child in view.subviews) DYPlusNotiWalkLabels(child, depth + 1, block);
}

static BOOL DYPlusNotiColorIsInk(UIColor *color, UIUserInterfaceStyle style) {
    if (!color) return NO;
    UIColor *resolved = [color resolvedColorWithTraitCollection:
                        [UITraitCollection traitCollectionWithUserInterfaceStyle:style]];
    CGFloat hue = 0.0, saturation = 0.0, brightness = 0.0, alpha = 0.0;
    if (![resolved getHue:&hue saturation:&saturation brightness:&brightness alpha:&alpha]) {
        CGFloat white = 0.0;
        if (![resolved getWhite:&white alpha:&alpha]) return NO;
        brightness = white;
    }
    return alpha >= 0.5 && brightness <= 0.35 && saturation <= 0.50;
}

static void DYPlusNotiApplyInkText(UIView *root, BOOL clear, UIUserInterfaceStyle style) {
    DYPlusNotiWalkLabels(root, 0, ^(UILabel *label) {
        UIColor *current = label.textColor;
        UIColor *original = objc_getAssociatedObject(label, &kInkOriginalKey);
        UIColor *applied = objc_getAssociatedObject(label, &kInkAppliedKey);
        if (!original || (![current isEqual:original] && ![current isEqual:applied])) {
            original = current;
            objc_setAssociatedObject(label, &kInkOriginalKey, original, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        UIColor *want = DYPlusNotiColorIsInk(original, style) && (clear || style == UIUserInterfaceStyleDark)
            ? [UIColor colorWithWhite:1.0 alpha:CGColorGetAlpha(original.CGColor)] : original;
        if (want && ![current isEqual:want]) label.textColor = want;
        objc_setAssociatedObject(label, &kInkAppliedKey, want, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    });
}

static void DYPlusNotiRestoreInkText(UIView *root) {
    DYPlusNotiWalkLabels(root, 0, ^(UILabel *label) {
        UIColor *original = objc_getAssociatedObject(label, &kInkOriginalKey);
        if (!original) return;
        label.textColor = original;
        objc_setAssociatedObject(label, &kInkOriginalKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(label, &kInkAppliedKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    });
}

static void DYPlusNotiRestoreHint(AWEInnerPushCommonView *common) {
    UIView *root = ([common respondsToSelector:@selector(middleContentTextStackView)]
                    && common.middleContentTextStackView)
        ? common.middleContentTextStackView : common;
    DYPlusNotiWalkLabels(root, 0, ^(UILabel *label) {
        NSNumber *hidden = objc_getAssociatedObject(label, &kHintHiddenKey);
        if (!hidden) return;
        label.hidden = hidden.boolValue;
        objc_setAssociatedObject(label, &kHintHiddenKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    });
}

static AWEInnerPushCommonView *DYPlusNotiCommonOf(UIView *view) {
    while (view) {
        if ([view isKindOfClass:%c(AWEInnerPushCommonView)]) return (AWEInnerPushCommonView *)view;
        view = view.superview;
    }
    return nil;
}

static void DYPlusNotiHideHintLabel(UILabel *label) {
    if (!label) return;
    if (!objc_getAssociatedObject(label, &kHintHiddenKey)) {
        objc_setAssociatedObject(label, &kHintHiddenKey,
                                 @(label.hidden), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    if (!label.hidden) label.hidden = YES;
    gEverAttached = YES;
}

static void DYPlusNotiApplyHint(AWEInnerPushCommonView *common) {
    UIView *root = ([common respondsToSelector:@selector(middleContentTextStackView)]
                    && common.middleContentTextStackView)
        ? common.middleContentTextStackView : common;
    DYPlusNotiWalkLabels(root, 0, ^(UILabel *label) {
        NSString *text = label.text.length ? label.text : label.attributedText.string;
        BOOL hint = DYPlusNotiIsHintText(text);
        NSNumber *marked = objc_getAssociatedObject(label, &kHintHiddenKey);
        if (hint) {
            DYPlusNotiHideHintLabel(label);
        } else if (marked) {
            label.hidden = marked.boolValue;
            objc_setAssociatedObject(label, &kHintHiddenKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
    });
}

#pragma mark - 同步

static void DYPlusNotiRestoreCommon(AWEInnerPushCommonView *common) {
    if ([common respondsToSelector:@selector(rightActionButton)]) {
        DYPlusNotiRestoreAction(common.rightActionButton);
    }
    if ([common respondsToSelector:@selector(leftExtraIconBackgroundView)]) {
        DYPlusNotiRestoreBadge(common.leftExtraIconBackgroundView);
    }
    DYPlusNotiRestoreHint(common);
    DYPlusNotiRestoreInkText(common);
    [gCommonViews removeObject:common];
}

static void DYPlusNotiRestoreContainer(AWEInnerNotificationContainerView *container) {
    AWEInnerPushCommonView *common = DYPlusNotiCommonIn(container, 0);
    if (common) DYPlusNotiRestoreCommon(common);
    DYPlusNotiRestoreInkText(DYPlusNotiSlot(container));
    DYPlusNotiDetachCard(container);
    [gContainers removeObject:container];
}

static void DYPlusNotiRestoreAll(void) {
    for (AWEInnerPushCommonView *common in gCommonViews.allObjects) {
        DYPlusNotiRestoreCommon(common);
    }
    for (AWEInnerNotificationContainerView *container in gContainers.allObjects) {
        DYPlusNotiDetachCard(container);
    }
    [gContainers removeAllObjects];
}

static void DYPlusNotiSyncCommon(AWEInnerPushCommonView *common) API_AVAILABLE(ios(26.0)) {
    if (!common) return;
    BOOL enabled = DYPlusNotiEnabled();
    if (!enabled && !gEverAttached) return;
    if (!enabled) {
        DYPlusNotiRestoreCommon(common);
        return;
    }

    [gCommonViews addObject:common];
    DYPlusNotiApplyHint(common);
    DYPlusNotiApplyInkText(common, DYPlusNotiUsesClear(), DYPlusGlassStyleForView(common));
    if ([common respondsToSelector:@selector(rightActionButton)]) {
        DYPlusNotiApplyAction(common.rightActionButton);
    }
    if ([common respondsToSelector:@selector(leftExtraIconBackgroundView)]) {
        DYPlusNotiApplyBadge(common.leftExtraIconBackgroundView);
    }
}

static void DYPlusNotiSyncContainer(AWEInnerNotificationContainerView *container)
    API_AVAILABLE(ios(26.0)) {
    if (!container) return;
    BOOL enabled = DYPlusNotiEnabled();
    if (!enabled && !gEverAttached) return;
    if (!enabled) {
        DYPlusNotiRestoreContainer(container);
        return;
    }

    UIView *slot = DYPlusNotiSlot(container);
    if (!slot) return;

    [gContainers addObject:container];
    DYPlusNotiObserveStyle(container);
    UIUserInterfaceStyle style = DYPlusGlassStyleForView(container);

    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    UIVisualEffectView *card = DYPlusNotiAttachCard(container, slot);
    DYPlusNotiSyncCommon(DYPlusNotiCommonIn(container, 0));
    DYPlusNotiApplyInkText(slot, DYPlusNotiUsesClear(), style);
    [CATransaction commit];

    if (card) {
        DYPlusNotiApplyStyle(style, YES);
        DYPlusNotiMaterialize(card);
    }
}

static void DYPlusNotiRefreshVisible(void) {
    BOOL enabled = DYPlusNotiEnabled();
    if (!enabled) {
        DYPlusNotiRestoreAll();
        return;
    }
    if (@available(iOS 26.0, *)) {
        for (AWEInnerNotificationContainerView *container in gContainers.allObjects) {
            DYPlusNotiSyncContainer(container);
        }
        for (AWEInnerPushCommonView *common in gCommonViews.allObjects) {
            DYPlusNotiSyncCommon(common);
        }
    }
}

// 文案会在横幅首次同步之后才落到 UILabel；在写入点立即重涂，避免首帧文字颜色滞后。
static void DYPlusNotiReapplyInk(UILabel *label) {
    if (gInkReapplying || !label || !DYPlusNotiEnabled()) return;
    if (!DYPlusNotiContainerOf(label)) return;
    gInkReapplying = YES;
    DYPlusNotiApplyInkText(label, DYPlusNotiUsesClear(), DYPlusGlassStyleForView(label));
    gInkReapplying = NO;
}

#pragma mark - Hook

%group DYPlusInnerNotificationGlassHooks

%hook AWEInnerNotificationContainerView

- (void)renderModel:(id)model context:(id)context {
    %orig;
    if (@available(iOS 26.0, *)) DYPlusNotiSyncContainer(self);
}

- (void)layoutSubviews {
    %orig;
    if (@available(iOS 26.0, *)) DYPlusNotiSyncContainer(self);
}

- (void)viewDidDisappear:(BOOL)animated reason:(long long)reason {
    %orig;
    if (self.window) return;
    DYPlusNotiRestoreContainer(self);
}

%end

%hook AWEInnerPushCommonView

- (void)updateViewWithRequest:(id)request notificationContent:(id)content viewModel:(id)viewModel {
    %orig;
    if (@available(iOS 26.0, *)) {
        DYPlusNotiSyncCommon(self);
        AWEInnerNotificationContainerView *container = DYPlusNotiContainerOf(self);
        if (container) DYPlusNotiSyncContainer(container);
    }
}

- (void)layoutSubviews {
    %orig;
    if (@available(iOS 26.0, *)) DYPlusNotiSyncCommon(self);
}

%end

// 文案在布局之后才写入；只靠 layoutSubviews 会首帧漏藏，拖一下才消失。
%hook UILabel

- (void)setText:(NSString *)text {
    %orig;
    if (DYPlusNotiEnabled() && DYPlusNotiIsHintText(text) && DYPlusNotiCommonOf(self)) {
        DYPlusNotiHideHintLabel(self);
    }
    DYPlusNotiReapplyInk(self);
}

- (void)setAttributedText:(NSAttributedString *)text {
    %orig;
    if (DYPlusNotiEnabled() && DYPlusNotiIsHintText(text.string) && DYPlusNotiCommonOf(self)) {
        DYPlusNotiHideHintLabel(self);
    }
    DYPlusNotiReapplyInk(self);
}

- (void)setTextColor:(UIColor *)color {
    %orig;
    DYPlusNotiReapplyInk(self);
}

- (void)setHidden:(BOOL)hidden {
    if (!hidden && DYPlusNotiEnabled() && objc_getAssociatedObject(self, &kHintHiddenKey)) {
        NSString *text = self.text.length ? self.text : self.attributedText.string;
        if (DYPlusNotiIsHintText(text)) {
            %orig(YES);
            return;
        }
    }
    %orig;
}

%end

%end

#pragma mark - 设置

%ctor {
    gGlassCarriers = [NSHashTable weakObjectsHashTable];
    gContainers = [NSHashTable weakObjectsHashTable];
    gCommonViews = [NSHashTable weakObjectsHashTable];

    if (DYPlusGlassOSAvailable()) {
        %init(DYPlusInnerNotificationGlassHooks);
        [[NSNotificationCenter defaultCenter] addObserverForName:@"DYYYSettingChanged"
                                                          object:nil
                                                           queue:NSOperationQueue.mainQueue
                                                      usingBlock:^(NSNotification *note) {
            NSString *changedKey = note.userInfo[@"key"];
            if ([changedKey isEqualToString:DYPlusKeyInnerNotiGlass] ||
                [changedKey isEqualToString:DYPlusKeyInnerNotiGlassClear] ||
                [changedKey isEqualToString:DYPlusKeyInnerNotiCorner]) {
                DYPlusNotiRefreshVisible();
            }
        }];
    }
}
