//
//  DYPlusSharePanelGlass.xm
//  分享面板液态玻璃：卡片底色、关闭键、第三行圆钮，以及点头像后的输入覆盖层、
//  发送按钮和表情栏。分享评论面板（长按评论 → 分享）并入同一开关，复用同一套材质。
//  通讯录头像与输入文字本身不接管。
//

#import "Integration/Headers/DYPlusAwemeHeaders.h"
#import "Core/UI/DYPlusGlass.h"
#import "Core/Utilities/DYPlusUtils.h"

#import <QuartzCore/QuartzCore.h>
#import <math.h>
#import <objc/runtime.h>

static NSString *const kDYPlusShareEffectClass = @"DUXVisualEffectView";
static NSString *const kDYPlusShareOverlayClass = @"AWEIMShareImpl.ShareAdditionTextView";
static NSString *const kDYPlusShareCommentSheetClass =
    @"AWECommentLongPressPanelSwiftImpl.CommentLongPressPanelSheet";
static NSString *const kDYPlusShareCommentListClass =
    @"AWECommentLongPressPanelSwiftImpl.CommentLongPressPanelCollectionViewController";
static const CGFloat kDYPlusShareRadiusFloor = 20.0;
static const CGFloat kDYPlusShareSendRadiusFloor = 8.0;
// 分享评论面板每行胶囊的上下内缩：相邻两行各缩一次，空隙 = 2 倍。
static const CGFloat kDYPlusShareCardGapInset = 3.0;
static const float kDYPlusSharePlateLuma = 0.76f;
static const float kDYPlusSharePlateSat = 0.14f;

static char kSlotColorKey;
static char kSlotGlassKey;
static char kGlassClearKey;
static char kGlassStyleKey;
static char kGlassMaterializingKey;
static char kGlassFixedTintKey;
static char kCloseOriginalConfigKey;
static char kCloseOriginalImageKey;
static char kCloseModeKey;
static char kCloseGlassKey;
static char kCellOriginalImageKey;
static char kCellOriginalColorKey;
static char kCellGlassKey;
static char kDestainedCacheKey;
static char kDestainedFlagKey;
static char kOverlayColorKey;
static char kOverlayEffectKey;
static char kOverlayTakenKey;
static char kOverlayOpaqueKey;
static char kOverlayGlassKey;
static char kOverlayDividerKey;
static char kDividerHiddenKey;
static char kButtonColorKey;
static char kButtonOpaqueKey;
static char kButtonGlassKey;
static char kToolbarColorKey;
static char kToolbarOpaqueKey;
static char kToolbarGlassKey;
static char kPlateColorKey;
static char kPlateOpaqueKey;
static char kPlateGlassKey;
static char kCardLayerKey;
static char kCardFillKey;
static char kCardGlassKey;
static char kCardDividerKey;
static char kCardDividerHiddenKey;
static char kCommentSyncingKey;

static NSHashTable *gGlassCarriers;
static NSHashTable<AWESharePanelContainerViewController *> *gContainers;
static NSHashTable<AWESharePanelFunctionCell *> *gCells;
static NSHashTable<UIViewController *> *gCommentSheets;
static NSHashTable<UICollectionViewCell *> *gCardCells;
static BOOL gEverAttached = NO;
static __weak UIWindowScene *gObservedScene = nil;
static UIUserInterfaceStyle gGlassStyle = UIUserInterfaceStyleUnspecified;

typedef NS_ENUM(NSInteger, DYPlusShareCloseMode) {
    DYPlusShareCloseModeNone = 0,
    DYPlusShareCloseModeOfficial,
    DYPlusShareCloseModeOverlay,
};

#pragma mark - 开关与材质

static BOOL DYPlusShareEnabled(void) {
    return DYPlusGlassOSAvailable() && DYPlusPrefBool(DYPlusKeySharePanelGlass);
}

static BOOL DYPlusShareUsesClear(void) {
    return DYPlusGlassOSAvailable() && DYPlusPrefBool(DYPlusKeySharePanelGlassClear);
}

static BOOL DYPlusShareColorOpaque(UIColor *color) {
    return color && CGColorGetAlpha(color.CGColor) >= 0.99;
}

// 抖音铺的白 / 近白底板（#FFFFFF、#F3F3F4）：不透明 + 高明度 + 低饱和。
// 与去白底那套用同一对阈值；收 CGColor 是为了同时判 UIColor 与 CALayer 的填充。
static BOOL DYPlusShareCGColorIsPlate(CGColorRef color) {
    if (!color || CGColorGetAlpha(color) < 0.99) return NO;
    size_t count = CGColorGetNumberOfComponents(color);
    const CGFloat *components = CGColorGetComponents(color);
    if (!components) return NO;
    CGFloat red, green, blue;
    if (count >= 4) {
        red = components[0];
        green = components[1];
        blue = components[2];
    } else if (count >= 2) {
        red = green = blue = components[0];
    } else {
        return NO;
    }
    CGFloat maximum = MAX(red, MAX(green, blue));
    CGFloat minimum = MIN(red, MIN(green, blue));
    CGFloat saturation = maximum > 0.001 ? (maximum - minimum) / maximum : 0.0;
    return maximum >= kDYPlusSharePlateLuma && saturation <= kDYPlusSharePlateSat;
}



static UIColor *DYPlusShareTint(BOOL clear, UIUserInterfaceStyle style) {
    return clear ? DYPlusGlassTintForStyle(style) : nil;
}

static UIColor *DYPlusShareEffectTint(UIVisualEffectView *glass, BOOL clear, UIUserInterfaceStyle style)
    API_AVAILABLE(ios(26.0)) {
    UIColor *fixed = objc_getAssociatedObject(glass, &kGlassFixedTintKey);
    if (fixed) return fixed;
    return DYPlusShareTint(clear, style);
}

static UIGlassEffect *DYPlusShareMakeEffect(UIVisualEffectView *glass, BOOL clear,
                                        UIUserInterfaceStyle style)
    API_AVAILABLE(ios(26.0)) {
    UIGlassEffect *effect = [UIGlassEffect effectWithStyle:
        clear ? UIGlassEffectStyleClear : UIGlassEffectStyleRegular];
    effect.tintColor = DYPlusShareEffectTint(glass, clear, style);
    effect.interactive = YES;
    return effect;
}


static void DYPlusShareInstallEffect(UIVisualEffectView *glass, BOOL clear, UIUserInterfaceStyle style)
    API_AVAILABLE(ios(26.0)) {
    glass.effect = DYPlusShareMakeEffect(glass, clear, style);
    objc_setAssociatedObject(glass, &kGlassClearKey, @(clear), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(glass, &kGlassStyleKey, @(style), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

static BOOL DYPlusShareGlassNeedsUpdate(UIVisualEffectView *glass, BOOL clear, UIUserInterfaceStyle style)
    API_AVAILABLE(ios(26.0)) {
    if (glass.overrideUserInterfaceStyle != DYPlusGlassOverrideStyle(clear, style)) return YES;
    UIGlassEffect *current = [glass.effect isKindOfClass:UIGlassEffect.class]
        ? (UIGlassEffect *)glass.effect : nil;
    if (!current) return glass.effect != nil;
    NSNumber *installedClear = objc_getAssociatedObject(glass, &kGlassClearKey);
    NSNumber *installedStyle = objc_getAssociatedObject(glass, &kGlassStyleKey);
    if (!installedClear || installedClear.boolValue != clear) return YES;
    if (!installedStyle || installedStyle.integerValue != style) return YES;
    if (!current.interactive) return YES;
    UIColor *want = DYPlusShareEffectTint(glass, clear, style);
    return !((current.tintColor == want) || [current.tintColor isEqual:want]);
}

static void DYPlusShareApplyStyle(UIUserInterfaceStyle style, BOOL animated) API_AVAILABLE(ios(26.0)) {
    if (style == UIUserInterfaceStyleUnspecified) return;
    gGlassStyle = style;
    if (!DYPlusShareEnabled()) return;
    BOOL clear = DYPlusShareUsesClear();
    BOOL needs = NO;
    for (UIVisualEffectView *glass in gGlassCarriers.allObjects) {
        if (DYPlusShareGlassNeedsUpdate(glass, clear, style)) {
            needs = YES;
            break;
        }
    }
    if (!needs) return;

    DYPlusGlassRunAnimation(nil, animated, ^{
        for (UIVisualEffectView *glass in gGlassCarriers.allObjects) {
            glass.overrideUserInterfaceStyle = DYPlusGlassOverrideStyle(clear, style);
            if (!glass.effect || !DYPlusShareGlassNeedsUpdate(glass, clear, style)) continue;
            DYPlusShareInstallEffect(glass, clear, style);
        }
    });
}

static void DYPlusShareObserveStyle(UIView *host) API_AVAILABLE(ios(26.0)) {
    UIWindowScene *scene = host.window.windowScene;
    if (!scene || scene == gObservedScene) return;
    gObservedScene = scene;
    [scene registerForTraitChanges:@[ UITraitUserInterfaceStyle.class ]
                       withHandler:^(UIWindowScene *changed, __unused UITraitCollection *previous) {
        DYPlusShareApplyStyle(changed.traitCollection.userInterfaceStyle, YES);
    }];
}



static BOOL DYPlusShareRectUsable(CGRect rect) {
    return CGRectGetWidth(rect) >= 8.0 && CGRectGetHeight(rect) >= 8.0;
}

// 0 尺寸时写入 UIGlassEffect，系统不会建材质层；之后只改 frame 补不回来。
static void DYPlusSharePlaceGlass(UIVisualEffectView *glass, CGRect frame, UIView *host, UIView *below) {
    if (!glass || !host) return;
    BOOL wasEmpty = !DYPlusShareRectUsable(glass.bounds);
    if (!CGRectEqualToRect(glass.frame, frame)) glass.frame = frame;
    if (below.superview == host) {
        if (glass.superview != host) [host insertSubview:glass belowSubview:below];
    } else if (glass.superview != host) {
        [host insertSubview:glass atIndex:0];
    }
    if (wasEmpty && DYPlusShareRectUsable(glass.bounds) && glass.effect) {
        glass.effect = nil;
        objc_setAssociatedObject(glass, &kGlassMaterializingKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
}

static void DYPlusShareMaterialize(UIVisualEffectView *glass, UIViewController *controller)
    API_AVAILABLE(ios(26.0)) {
    if (!glass || !DYPlusShareRectUsable(glass.bounds) || glass.effect
        || [objc_getAssociatedObject(glass, &kGlassMaterializingKey) boolValue]) {
        return;
    }
    objc_setAssociatedObject(glass, &kGlassMaterializingKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    DYPlusGlassRunAnimation(controller, YES, ^{
        if (!glass.superview || !DYPlusShareEnabled()) {
            objc_setAssociatedObject(glass, &kGlassMaterializingKey,
                                     nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            return;
        }
        UIUserInterfaceStyle style = gGlassStyle;
        if (style == UIUserInterfaceStyleUnspecified) style = DYPlusGlassStyleForView(glass);
        BOOL clear = DYPlusShareUsesClear();
        glass.overrideUserInterfaceStyle = DYPlusGlassOverrideStyle(clear, style);
        DYPlusShareInstallEffect(glass, clear, style);
        objc_setAssociatedObject(glass, &kGlassMaterializingKey,
                                 nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    });
}

#pragma mark - 去白底

static UIImage *DYPlusShareDestainPlate(UIImage *image) {
    if (!image || [objc_getAssociatedObject(image, &kDestainedFlagKey) boolValue]) return image;
    UIImage *cached = objc_getAssociatedObject(image, &kDestainedCacheKey);
    if (cached) return cached;

    CGImageRef cgImage = image.CGImage;
    if (!cgImage) return image;
    size_t width = CGImageGetWidth(cgImage);
    size_t height = CGImageGetHeight(cgImage);
    if (width == 0 || height == 0) return image;

    size_t stride = width * 4;
    uint8_t *pixels = (uint8_t *)calloc(height * stride, 1);
    if (!pixels) return image;
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGContextRef context = CGBitmapContextCreate(
        pixels, width, height, 8, stride, space,
        kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
    CGColorSpaceRelease(space);
    if (!context) {
        free(pixels);
        return image;
    }
    CGContextDrawImage(context, CGRectMake(0.0, 0.0, width, height), cgImage);

    NSUInteger kept = 0;
    size_t count = width * height;
    for (size_t i = 0; i < count; i++) {
        uint8_t *pixel = pixels + i * 4;
        float red = pixel[0] / 255.0f;
        float green = pixel[1] / 255.0f;
        float blue = pixel[2] / 255.0f;
        float alpha = pixel[3] / 255.0f;
        if (alpha < 0.02f) continue;
        float maximum = fmaxf(red, fmaxf(green, blue));
        float minimum = fminf(red, fminf(green, blue));
        float saturation = maximum > 0.001f ? (maximum - minimum) / maximum : 0.0f;
        if (maximum >= kDYPlusSharePlateLuma && saturation <= kDYPlusSharePlateSat) {
            pixel[0] = pixel[1] = pixel[2] = pixel[3] = 0;
        } else {
            kept += 1;
        }
    }

    UIImage *result = image;
    if (kept > 0) {
        CGImageRef output = CGBitmapContextCreateImage(context);
        if (output) {
            result = [UIImage imageWithCGImage:output
                                         scale:image.scale
                                   orientation:image.imageOrientation];
            CGImageRelease(output);
            objc_setAssociatedObject(result, &kDestainedFlagKey, @YES,
                                     OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
    }
    CGContextRelease(context);
    free(pixels);
    objc_setAssociatedObject(image, &kDestainedCacheKey, result, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return result;
}

#pragma mark - 查找

// 分享面板容器与分享评论面板的外壳都是这个类，取到只为读它的圆角。
static UIView *DYPlusShareEffectView(UIViewController *controller) {
    Class cls = NSClassFromString(kDYPlusShareEffectClass);
    if (!cls || !controller.isViewLoaded) return nil;
    for (UIView *subview in controller.view.subviews) {
        if ([subview isKindOfClass:cls]) return subview;
    }
    return nil;
}

static AWESharePanelViewController *DYPlusShareContentController(UIViewController *controller) {
    if (!controller) return nil;
    if ([controller isKindOfClass:%c(AWESharePanelViewController)]) {
        return (AWESharePanelViewController *)controller;
    }
    if ([controller isKindOfClass:UINavigationController.class]) {
        return DYPlusShareContentController(((UINavigationController *)controller).topViewController);
    }
    for (UIViewController *child in controller.childViewControllers) {
        AWESharePanelViewController *found = DYPlusShareContentController(child);
        if (found) return found;
    }
    return nil;
}

static UIButton *DYPlusShareCloseButton(AWESharePanelViewController *controller) {
    if (!controller.isViewLoaded) return nil;
    NSMutableArray<UIView *> *stack = [NSMutableArray arrayWithObject:controller.view];
    while (stack.count > 0) {
        UIView *view = stack.lastObject;
        [stack removeLastObject];
        if ([view isKindOfClass:UIButton.class]
            && [((UIButton *)view).accessibilityLabel isEqualToString:@"关闭"]) {
            return (UIButton *)view;
        }
        for (UIView *subview in view.subviews) [stack addObject:subview];
    }
    return nil;
}

static UIViewController *DYPlusShareControllerForView(UIView *view) {
    for (UIResponder *responder = view.nextResponder; responder; responder = responder.nextResponder) {
        if ([responder isKindOfClass:UIViewController.class]) return (UIViewController *)responder;
    }
    return nil;
}

// 圆底板：约 56×56、圆角裁成圆。图标可能画在这张图里，也可能只在 smallImageView 上。
static BOOL DYPlusShareIsCirclePlate(UIImageView *imageView) {
    if (!imageView) return NO;
    CGFloat width = CGRectGetWidth(imageView.bounds);
    CGFloat height = CGRectGetHeight(imageView.bounds);
    if (width >= 40.0 && fabs(width - height) <= 1.0) return YES;
    return width < 1.0 && imageView.layer.cornerRadius >= 8.0;
}

static UIImageView *DYPlusShareFindCircleImage(UIView *view, NSUInteger depth) {
    if (!view || depth > 8) return nil;
    if ([view isKindOfClass:UIImageView.class]
        && DYPlusShareIsCirclePlate((UIImageView *)view)) {
        return (UIImageView *)view;
    }
    UIImageView *fallback = nil;
    for (UIView *subview in view.subviews) {
        UIImageView *found = DYPlusShareFindCircleImage(subview, depth + 1);
        if (!found) continue;
        if (CGRectGetWidth(found.bounds) >= 40.0) return found;
        if (!fallback) fallback = found;
    }
    return fallback;
}

static UIImageView *DYPlusShareCircleImageView(AWESharePanelFunctionCell *cell) {
    if ([cell respondsToSelector:@selector(imageView)] && cell.imageView
        && (DYPlusShareIsCirclePlate(cell.imageView)
            || cell.imageView.image
            || DYPlusShareColorOpaque(cell.imageView.backgroundColor))) {
        return cell.imageView;
    }
    return DYPlusShareFindCircleImage(cell, 0);
}

#pragma mark - 面板

static BOOL DYPlusShareClearSlot(UIView *slot) {
    UIColor *current = slot.backgroundColor;
    if (DYPlusShareColorOpaque(current)) {
        if (!objc_getAssociatedObject(slot, &kSlotColorKey)) {
            objc_setAssociatedObject(slot, &kSlotColorKey, current, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        slot.backgroundColor = UIColor.clearColor;
        gEverAttached = YES;
        return YES;
    }
    return objc_getAssociatedObject(slot, &kSlotColorKey) != nil;
}

static UIVisualEffectView *DYPlusShareAttachPanel(UIView *slot, UIView *shell)
    API_AVAILABLE(ios(26.0)) {
    if (!DYPlusShareClearSlot(slot)) return nil;
    UIVisualEffectView *glass = objc_getAssociatedObject(slot, &kSlotGlassKey);
    if (!glass) {
        if ([slot.subviews.firstObject isKindOfClass:UIVisualEffectView.class]) return nil;
        glass = DYPlusGlassMakeShell();
        CGFloat radius = shell.layer.cornerRadius;
        if (radius <= 0.0) radius = kDYPlusShareRadiusFloor;
        UICornerRadius *top = [UICornerRadius containerConcentricRadiusWithMinimum:radius];
        glass.cornerConfiguration =
            [UICornerConfiguration configurationWithUniformTopRadius:top
                                                    bottomLeftRadius:nil
                                                   bottomRightRadius:nil];
        ((DYPlusGlassFlexView *)glass).flexSourceView = slot;
        objc_setAssociatedObject(slot, &kSlotGlassKey, glass, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [gGlassCarriers addObject:glass];
        gEverAttached = YES;
    }
    if (!CGRectEqualToRect(glass.frame, slot.bounds)) glass.frame = slot.bounds;
    DYPlusGlassEnsureBackmost(slot, glass);
    return glass;
}

static void DYPlusShareDetachPanel(UIView *slot) {
    UIColor *original = objc_getAssociatedObject(slot, &kSlotColorKey);
    if (!original) return;
    [(UIView *)objc_getAssociatedObject(slot, &kSlotGlassKey) removeFromSuperview];
    slot.backgroundColor = original;
    objc_setAssociatedObject(slot, &kSlotColorKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(slot, &kSlotGlassKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

#pragma mark - 关闭键

static void DYPlusShareRememberClose(UIButton *button) {
    if (objc_getAssociatedObject(button, &kCloseOriginalImageKey)
        || objc_getAssociatedObject(button, &kCloseOriginalConfigKey)) {
        return;
    }
    if (button.configuration) {
        objc_setAssociatedObject(button, &kCloseOriginalConfigKey,
                                 button.configuration, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    UIImage *image = button.currentImage ?: button.imageView.image;
    if (image) {
        objc_setAssociatedObject(button, &kCloseOriginalImageKey,
                                 image, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
}

static void DYPlusShareRemoveCloseOverlay(UIButton *button) {
    UIView *glass = objc_getAssociatedObject(button, &kCloseGlassKey);
    [glass removeFromSuperview];
    [gGlassCarriers removeObject:glass];
    objc_setAssociatedObject(button, &kCloseGlassKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

static void DYPlusShareRestoreClose(UIButton *button) {
    if (!button) return;
    DYPlusShareRemoveCloseOverlay(button);
    UIButtonConfiguration *config = objc_getAssociatedObject(button, &kCloseOriginalConfigKey);
    UIImage *image = objc_getAssociatedObject(button, &kCloseOriginalImageKey);
    if (config) {
        button.configuration = config;
    } else if (objc_getAssociatedObject(button, &kCloseModeKey)) {
        button.configuration = nil;
        if (image) [button setImage:image forState:UIControlStateNormal];
    }
    objc_setAssociatedObject(button, &kCloseOriginalConfigKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(button, &kCloseOriginalImageKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(button, &kCloseModeKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

static void DYPlusShareApplyCloseOverlay(UIButton *button, UIViewController *controller)
    API_AVAILABLE(ios(26.0)) {
    UIImage *original = objc_getAssociatedObject(button, &kCloseOriginalImageKey);
    if (original) {
        UIImage *icon = DYPlusShareDestainPlate(original);
        if (button.configuration) button.configuration = nil;
        [button setImage:icon forState:UIControlStateNormal];
    }

    UIView *host = button.superview;
    if (!host) return;
    UIVisualEffectView *glass = objc_getAssociatedObject(button, &kCloseGlassKey);
    if (!glass) {
        glass = DYPlusGlassMakeShell();
        glass.cornerConfiguration = [UICornerConfiguration capsuleConfiguration];
        ((DYPlusGlassFlexView *)glass).flexSourceView = button;
        objc_setAssociatedObject(button, &kCloseGlassKey, glass, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [gGlassCarriers addObject:glass];
    }
    glass.autoresizingMask = UIViewAutoresizingNone;
    DYPlusSharePlaceGlass(glass, button.frame, host, button);
    objc_setAssociatedObject(button, &kCloseModeKey,
                             @(DYPlusShareCloseModeOverlay), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    DYPlusShareMaterialize(glass, controller);
}

static BOOL DYPlusShareApplyCloseOfficial(UIButton *button) API_AVAILABLE(ios(26.0)) {
    if (![UIButtonConfiguration respondsToSelector:@selector(glassButtonConfiguration)]) return NO;
    DYPlusShareRemoveCloseOverlay(button);

    UIImage *original = objc_getAssociatedObject(button, &kCloseOriginalImageKey);
    UIButtonConfiguration *config = [UIButtonConfiguration glassButtonConfiguration];
    config.cornerStyle = UIButtonConfigurationCornerStyleCapsule;
    config.contentInsets = NSDirectionalEdgeInsetsZero;
    if (original) config.image = DYPlusShareDestainPlate(original);
    button.configuration = config;
    objc_setAssociatedObject(button, &kCloseModeKey,
                             @(DYPlusShareCloseModeOfficial), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return YES;
}

static void DYPlusShareApplyClose(UIButton *button, UIViewController *controller)
    API_AVAILABLE(ios(26.0)) {
    if (!button) return;
    DYPlusShareRememberClose(button);
    if (DYPlusShareUsesClear()) {
        DYPlusShareApplyCloseOverlay(button, controller);
        return;
    }
    if (!DYPlusShareApplyCloseOfficial(button)) DYPlusShareApplyCloseOverlay(button, controller);
}

#pragma mark - 第三行圆钮

static void DYPlusShareRestoreCell(AWESharePanelFunctionCell *cell) {
    UIImageView *imageView = DYPlusShareCircleImageView(cell);
    UIImage *original = objc_getAssociatedObject(cell, &kCellOriginalImageKey);
    UIColor *color = objc_getAssociatedObject(cell, &kCellOriginalColorKey);
    if (imageView && original) imageView.image = original;
    if (imageView && color) imageView.backgroundColor = color;
    UIView *glass = objc_getAssociatedObject(cell, &kCellGlassKey);
    [glass removeFromSuperview];
    [gGlassCarriers removeObject:glass];
    objc_setAssociatedObject(cell, &kCellOriginalImageKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(cell, &kCellOriginalColorKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(cell, &kCellGlassKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [gCells removeObject:cell];
}

static void DYPlusShareApplyCell(AWESharePanelFunctionCell *cell, UIViewController *controller)
    API_AVAILABLE(ios(26.0)) {
    UIImageView *imageView = DYPlusShareCircleImageView(cell);
    if (!imageView) return;

    // 底板两种画法：56×56 合成图，或白底 + smallImageView 图标。后一种没有 image。
    if (DYPlusShareColorOpaque(imageView.backgroundColor)) {
        if (!objc_getAssociatedObject(cell, &kCellOriginalColorKey)) {
            objc_setAssociatedObject(cell, &kCellOriginalColorKey,
                                     imageView.backgroundColor, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        imageView.backgroundColor = UIColor.clearColor;
    }

    UIImage *current = imageView.image;
    if (current && ![objc_getAssociatedObject(current, &kDestainedFlagKey) boolValue]) {
        objc_setAssociatedObject(cell, &kCellOriginalImageKey,
                                 current, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        UIImage *icon = DYPlusShareDestainPlate(current);
        if (icon != current) imageView.image = icon;
    }

    UIView *host = imageView.superview;
    if (!host) return;
    UIVisualEffectView *glass = objc_getAssociatedObject(cell, &kCellGlassKey);
    if (!glass) {
        glass = DYPlusGlassMakeShell();
        glass.autoresizingMask = UIViewAutoresizingNone;
        glass.cornerConfiguration = [UICornerConfiguration capsuleConfiguration];
        ((DYPlusGlassFlexView *)glass).flexSourceView = cell;
        objc_setAssociatedObject(cell, &kCellGlassKey, glass, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [gGlassCarriers addObject:glass];
        [gCells addObject:cell];
        gEverAttached = YES;
    }
    DYPlusSharePlaceGlass(glass, imageView.frame, host, imageView);
    DYPlusShareMaterialize(glass, controller);
}

static void DYPlusShareCollectFunctionCells(UIView *view,
                                        NSMutableArray<AWESharePanelFunctionCell *> *output,
                                        NSUInteger depth) {
    if (!view || depth > 12) return;
    if ([view isKindOfClass:%c(AWESharePanelFunctionCell)]) {
        [output addObject:(AWESharePanelFunctionCell *)view];
        return;
    }
    for (UIView *subview in view.subviews) {
        DYPlusShareCollectFunctionCells(subview, output, depth + 1);
    }
}

static void DYPlusShareApplyVisibleCells(AWESharePanelViewController *controller)
    API_AVAILABLE(ios(26.0)) {
    if (!controller.isViewLoaded) return;
    NSMutableArray<AWESharePanelFunctionCell *> *cells = [NSMutableArray array];
    DYPlusShareCollectFunctionCells(controller.view, cells, 0);
    for (AWESharePanelFunctionCell *cell in cells) DYPlusShareApplyCell(cell, controller);
}

#pragma mark - 输入覆盖层 / 发送按钮 / 表情栏

static Class DYPlusShareOverlayClass(void) {
    static Class cls;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ cls = NSClassFromString(kDYPlusShareOverlayClass); });
    return cls;
}

static UIView *DYPlusShareOverlayHost(UIView *overlay) {
    return [overlay isKindOfClass:UIVisualEffectView.class]
        ? ((UIVisualEffectView *)overlay).contentView : overlay;
}

static UIVisualEffectView *DYPlusShareEnsureGlass(id owner, const void *key, UIView *flexSource)
    API_AVAILABLE(ios(26.0)) {
    UIVisualEffectView *glass = objc_getAssociatedObject(owner, key);
    if (glass) return glass;
    glass = DYPlusGlassMakeShell();
    ((DYPlusGlassFlexView *)glass).flexSourceView = flexSource;
    objc_setAssociatedObject(owner, key, glass, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [gGlassCarriers addObject:glass];
    gEverAttached = YES;
    return glass;
}

static void DYPlusShareDiscardGlass(id owner, const void *key) {
    UIView *glass = objc_getAssociatedObject(owner, key);
    [glass removeFromSuperview];
    [gGlassCarriers removeObject:glass];
    objc_setAssociatedObject(owner, key, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

static void DYPlusShareRememberColor(UIView *view, const void *colorKey, const void *opaqueKey) {
    id existing = objc_getAssociatedObject(view, colorKey);
    UIColor *color = view.backgroundColor;
    if (existing && existing != [NSNull null]) return;
    if (existing == [NSNull null] && (!color || CGColorGetAlpha(color.CGColor) <= 0.01)) return;
    objc_setAssociatedObject(view, colorKey,
                             color ?: (id)[NSNull null], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    if (!objc_getAssociatedObject(view, opaqueKey)) {
        objc_setAssociatedObject(view, opaqueKey, @(view.opaque), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
}

static void DYPlusShareRestoreColor(UIView *view, const void *colorKey, const void *opaqueKey) {
    id color = objc_getAssociatedObject(view, colorKey);
    if (!color) return;
    NSNumber *opaque = objc_getAssociatedObject(view, opaqueKey);
    objc_setAssociatedObject(view, colorKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(view, opaqueKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    view.backgroundColor = (color == [NSNull null]) ? nil : (UIColor *)color;
    if (opaque) view.opaque = opaque.boolValue;
}

static UIView *DYPlusShareFindDivider(UIView *host) {
    for (UIView *sub in host.subviews) {
        CGFloat height = CGRectGetHeight(sub.bounds);
        if (height > 0.1 && height < 1.5
            && CGRectGetWidth(sub.bounds) >= 200.0
            && CGRectGetMinY(sub.frame) < 16.0) {
            return sub;
        }
    }
    return nil;
}

static void DYPlusShareHideDivider(UIView *overlay) {
    UIView *divider = objc_getAssociatedObject(overlay, &kOverlayDividerKey);
    if (!divider) {
        divider = DYPlusShareFindDivider(DYPlusShareOverlayHost(overlay));
        if (!divider) return;
        objc_setAssociatedObject(overlay, &kOverlayDividerKey, divider, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(divider, &kDividerHiddenKey, @(divider.hidden),
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    divider.hidden = YES;
}

static void DYPlusShareRestoreDivider(UIView *overlay) {
    UIView *divider = objc_getAssociatedObject(overlay, &kOverlayDividerKey);
    NSNumber *hidden = objc_getAssociatedObject(divider, &kDividerHiddenKey);
    if (divider && hidden) divider.hidden = hidden.boolValue;
    objc_setAssociatedObject(overlay, &kOverlayDividerKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(divider, &kDividerHiddenKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

static void DYPlusShareRestoreOverlay(UIView *overlay) {
    if (!overlay) return;
    DYPlusShareRestoreDivider(overlay);
    DYPlusShareDiscardGlass(overlay, &kOverlayGlassKey);
    DYPlusShareRestoreColor(overlay, &kOverlayColorKey, &kOverlayOpaqueKey);
    objc_setAssociatedObject(overlay, &kOverlayTakenKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    UIVisualEffect *effect = objc_getAssociatedObject(overlay, &kOverlayEffectKey);
    objc_setAssociatedObject(overlay, &kOverlayEffectKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    if (effect && [overlay isKindOfClass:UIVisualEffectView.class]) {
        ((UIVisualEffectView *)overlay).effect = effect;
    }
}

// 清底色、摘原生 effect、藏顶部分割线。分享评论面板的覆盖层落在输入区白垫的玻璃上，
// 只做到这一步；分享面板还要接着自己挂一块玻璃。
static void DYPlusShareStripOverlay(UIView *overlay) {
    if (!overlay) return;
    DYPlusShareRememberColor(overlay, &kOverlayColorKey, &kOverlayOpaqueKey);
    if (DYPlusShareColorOpaque(overlay.backgroundColor)) overlay.backgroundColor = UIColor.clearColor;
    overlay.opaque = NO;

    if ([overlay isKindOfClass:UIVisualEffectView.class]) {
        UIVisualEffectView *effectView = (UIVisualEffectView *)overlay;
        if (effectView.effect && !objc_getAssociatedObject(overlay, &kOverlayEffectKey)) {
            objc_setAssociatedObject(overlay, &kOverlayEffectKey,
                                     effectView.effect, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        // 本函数会被覆盖层自己的布局回调反复调用，重复写 effect 会再挑一次布局。
        if (effectView.effect) effectView.effect = nil;
    }
    objc_setAssociatedObject(overlay, &kOverlayTakenKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    DYPlusShareHideDivider(overlay);
    DYPlusShareOverlayHost(overlay).opaque = NO;
}

// 覆盖层叠在第三行功能圆钮上，只能自己挂玻璃，不能只清底色。
static void DYPlusShareApplyOverlay(UIView *overlay, UIViewController *controller)
    API_AVAILABLE(ios(26.0)) {
    if (!overlay) return;
    DYPlusShareStripOverlay(overlay);

    UIView *host = DYPlusShareOverlayHost(overlay);
    if (!host) return;
    UIVisualEffectView *glass = DYPlusShareEnsureGlass(overlay, &kOverlayGlassKey, overlay);
    if (!CGRectEqualToRect(glass.frame, host.bounds)) glass.frame = host.bounds;
    DYPlusGlassEnsureBackmost(host, glass);
    DYPlusShareMaterialize(glass, controller);
}

static NSString *DYPlusShareButtonTitle(UIButton *button) {
    return button.currentTitle.length ? button.currentTitle
        : (button.accessibilityLabel ?: @"");
}

static BOOL DYPlusShareIsSendButton(UIView *view) {
    if (![view isKindOfClass:UIButton.class]) return NO;
    UIButton *button = (UIButton *)view;
    if (CGRectGetHeight(button.bounds) < 36.0) return NO;
    return [DYPlusShareButtonTitle(button) containsString:@"发送"];
}

static void DYPlusShareCollectSendButtons(UIView *view, NSMutableArray<UIButton *> *output,
                                      NSUInteger depth) {
    if (!view || depth > 8) return;
    if (DYPlusShareIsSendButton(view)) {
        [output addObject:(UIButton *)view];
        return;
    }
    for (UIView *subview in view.subviews) {
        DYPlusShareCollectSendButtons(subview, output, depth + 1);
    }
}

static void DYPlusShareRestoreSendButton(UIButton *button) {
    if (!button) return;
    DYPlusShareDiscardGlass(button, &kButtonGlassKey);
    DYPlusShareRestoreColor(button, &kButtonColorKey, &kButtonOpaqueKey);
}

static void DYPlusShareApplySendButton(UIButton *button, UIViewController *controller)
    API_AVAILABLE(ios(26.0)) {
    if (!button) return;
    DYPlusShareRememberColor(button, &kButtonColorKey, &kButtonOpaqueKey);
    UIColor *current = button.backgroundColor;
    if (current && CGColorGetAlpha(current.CGColor) > 0.01) {
        button.backgroundColor = UIColor.clearColor;
    }
    button.opaque = NO;

    // 玻璃挂在按钮内部：随按钮释放，并吃到原生 8pt 裁剪。
    UIVisualEffectView *glass = DYPlusShareEnsureGlass(button, &kButtonGlassKey, button);
    CGFloat radius = button.layer.cornerRadius;
    if (radius <= 0.0) radius = kDYPlusShareSendRadiusFloor;
    glass.cornerConfiguration =
        [UICornerConfiguration configurationWithUniformRadius:[UICornerRadius fixedRadius:radius]];

    id original = objc_getAssociatedObject(button, &kButtonColorKey);
    NSString *title = DYPlusShareButtonTitle(button);
    BOOL primary = ([original isKindOfClass:UIColor.class] && DYPlusShareColorOpaque((UIColor *)original))
        || ([title containsString:@"发送"] && ![title containsString:@"建群"]);
    if (primary) {
        UIColor *tint = ([original isKindOfClass:UIColor.class] && DYPlusShareColorOpaque((UIColor *)original))
            ? (UIColor *)original
            : [UIColor colorWithRed:0.9961 green:0.1725 blue:0.3333 alpha:1.0];
        objc_setAssociatedObject(glass, &kGlassFixedTintKey, tint, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }

    if (!CGRectEqualToRect(glass.frame, button.bounds)) glass.frame = button.bounds;
    DYPlusGlassEnsureBackmost(button, glass);
    DYPlusShareMaterialize(glass, controller);
}

static void DYPlusShareApplySendButtons(UIView *overlay, UIViewController *controller)
    API_AVAILABLE(ios(26.0)) {
    NSMutableArray<UIButton *> *buttons = [NSMutableArray array];
    DYPlusShareCollectSendButtons(overlay, buttons, 0);
    for (UIButton *button in buttons) DYPlusShareApplySendButton(button, controller);
}

static void DYPlusShareRestoreToolbarFill(UIView *view) {
    DYPlusShareRestoreColor(view, &kToolbarColorKey, &kToolbarOpaqueKey);
}

static void DYPlusShareClearToolbarFills(UIView *view, NSUInteger depth) {
    if (!view || depth > 4) return;
    if ([view isKindOfClass:UIControl.class]
        || [view isKindOfClass:UIImageView.class]
        || [view isKindOfClass:UILabel.class]
        || [view isKindOfClass:UIVisualEffectView.class]) {
        return;
    }
    if (DYPlusShareColorOpaque(view.backgroundColor)) {
        DYPlusShareRememberColor(view, &kToolbarColorKey, &kToolbarOpaqueKey);
        view.backgroundColor = UIColor.clearColor;
        view.opaque = NO;
    }
    for (UIView *subview in view.subviews) DYPlusShareClearToolbarFills(subview, depth + 1);
}

static void DYPlusShareRestoreToolbarFillsUnder(UIView *view, NSUInteger depth) {
    if (!view || depth > 4) return;
    if (objc_getAssociatedObject(view, &kToolbarColorKey)) DYPlusShareRestoreToolbarFill(view);
    for (UIView *subview in view.subviews) DYPlusShareRestoreToolbarFillsUnder(subview, depth + 1);
}

static void DYPlusShareRestoreToolbar(UIView *bar) {
    if (!bar) return;
    DYPlusShareDiscardGlass(bar, &kToolbarGlassKey);
    DYPlusShareRestoreToolbarFillsUnder(bar, 0);
}

static UIView *DYPlusShareToolbarSlot(UIView *bar) {
    if ([bar respondsToSelector:@selector(inputControlBar)]) {
        UIView *slot = ((AWEIMShareInputEmoticonToolBarView *)bar).inputControlBar;
        if (slot) return slot;
    }
    for (UIView *subview in bar.subviews) {
        CGFloat height = CGRectGetHeight(subview.bounds);
        if (height >= 32.0 && height <= 48.0
            && fabs(CGRectGetWidth(subview.bounds) - CGRectGetWidth(bar.bounds)) < 2.0) {
            return subview;
        }
    }
    return nil;
}

static void DYPlusShareApplyToolbar(UIView *bar, UIViewController *controller)
    API_AVAILABLE(ios(26.0)) {
    if (!bar) return;
    DYPlusShareClearToolbarFills(bar, 0);
    UIView *slot = DYPlusShareToolbarSlot(bar);
    if (!slot || !DYPlusShareRectUsable(slot.bounds)) return;
    slot.opaque = NO;
    UIVisualEffectView *glass = DYPlusShareEnsureGlass(bar, &kToolbarGlassKey, slot);
    if (!CGRectEqualToRect(glass.frame, slot.bounds)) glass.frame = slot.bounds;
    DYPlusGlassEnsureBackmost(slot, glass);
    DYPlusShareMaterialize(glass, controller);
}

static void DYPlusShareWalkContent(AWESharePanelViewController *content, UIView **overlay, UIView **toolbar) {
    if (overlay) *overlay = nil;
    if (toolbar) *toolbar = nil;
    if (!content.isViewLoaded) return;
    Class overlayClass = DYPlusShareOverlayClass();
    Class toolbarClass = %c(AWEIMShareInputEmoticonToolBarView);
    for (UIView *subview in content.view.subviews) {
        if (overlay && overlayClass && !*overlay && [subview isKindOfClass:overlayClass]) {
            *overlay = subview;
        }
        if (toolbar && toolbarClass && !*toolbar && [subview isKindOfClass:toolbarClass]) {
            *toolbar = subview;
        }
    }
}

static void DYPlusShareSyncInput(AWESharePanelViewController *content)
    API_AVAILABLE(ios(26.0)) {
    UIView *overlay = nil;
    UIView *toolbar = nil;
    DYPlusShareWalkContent(content, &overlay, &toolbar);
    if (overlay && !overlay.hidden) {
        DYPlusShareApplyOverlay(overlay, content);
        DYPlusShareApplySendButtons(overlay, content);
    }
    if (toolbar) DYPlusShareApplyToolbar(toolbar, content);
}

static void DYPlusShareRestoreInput(AWESharePanelViewController *content) {
    UIView *overlay = nil;
    UIView *toolbar = nil;
    DYPlusShareWalkContent(content, &overlay, &toolbar);
    if (overlay) {
        NSMutableArray<UIButton *> *buttons = [NSMutableArray array];
        DYPlusShareCollectSendButtons(overlay, buttons, 0);
        for (UIButton *button in buttons) DYPlusShareRestoreSendButton(button);
        DYPlusShareRestoreOverlay(overlay);
    }
    if (toolbar) DYPlusShareRestoreToolbar(toolbar);
}

#pragma mark - 分享评论面板

// 不透明浅色底板槽：记原色清透明，最底层挂一块玻璃。
// corners 为 nil 时圆角交给宿主的裁剪，只在新建玻璃时写一次。
static UIVisualEffectView *DYPlusShareApplyPlate(UIView *slot, UICornerConfiguration *corners,
                                             UIViewController *controller)
    API_AVAILABLE(ios(26.0)) {
    if (!slot) return nil;
    BOOL taken = objc_getAssociatedObject(slot, &kPlateColorKey) != nil;
    if (!taken && !DYPlusShareCGColorIsPlate(slot.backgroundColor.CGColor)) return nil;

    DYPlusShareRememberColor(slot, &kPlateColorKey, &kPlateOpaqueKey);
    if (DYPlusShareColorOpaque(slot.backgroundColor)) slot.backgroundColor = UIColor.clearColor;
    slot.opaque = NO;

    BOOL fresh = objc_getAssociatedObject(slot, &kPlateGlassKey) == nil;
    UIVisualEffectView *glass = DYPlusShareEnsureGlass(slot, &kPlateGlassKey, slot);
    if (fresh && corners) glass.cornerConfiguration = corners;
    if (!CGRectEqualToRect(glass.frame, slot.bounds)) glass.frame = slot.bounds;
    DYPlusGlassEnsureBackmost(slot, glass);
    DYPlusShareMaterialize(glass, controller);
    return glass;
}

static void DYPlusShareRestorePlate(UIView *slot) {
    if (!slot) return;
    DYPlusShareDiscardGlass(slot, &kPlateGlassKey);
    DYPlusShareRestoreColor(slot, &kPlateColorKey, &kPlateOpaqueKey);
}

// 白卡片底画在行内一层非视图 CALayer 上：CAShapeLayer 看 fillColor、普通层看 backgroundColor。
// 同一行还有一层行间分割线，靠「够不够一块卡片大」把它排除掉。
static CGRect DYPlusShareCardRect(CALayer *layer) {
    if ([layer isKindOfClass:CAShapeLayer.class]) {
        CGPathRef path = ((CAShapeLayer *)layer).path;
        if (path && !CGPathIsEmpty(path)) {
            CGRect box = CGPathGetBoundingBox(path);
            return CGRectOffset(box,
                                CGRectGetMinX(layer.frame) - CGRectGetMinX(layer.bounds),
                                CGRectGetMinY(layer.frame) - CGRectGetMinY(layer.bounds));
        }
    }
    return layer.frame;
}

static CALayer *DYPlusShareCardLayer(UIView *view, NSUInteger depth) {
    if (!view || depth > 3) return nil;
    for (CALayer *layer in view.layer.sublayers) {
        // 视图自带的层由视图那条路处理，只认抖音直接加上来的绘制层。
        if ([layer.delegate isKindOfClass:UIView.class]) continue;
        CGColorRef fill = [layer isKindOfClass:CAShapeLayer.class]
            ? ((CAShapeLayer *)layer).fillColor : layer.backgroundColor;
        if (!DYPlusShareCGColorIsPlate(fill)) continue;
        if (!DYPlusShareRectUsable(DYPlusShareCardRect(layer))) continue;
        return layer;
    }
    for (UIView *subview in view.subviews) {
        CALayer *found = DYPlusShareCardLayer(subview, depth + 1);
        if (found) return found;
    }
    return nil;
}

// 行间分割线与卡片底是同一层视图上的两个非视图 sublayer。每行成了独立胶囊之后那条线会浮在
// 两枚胶囊中间的空隙里，要藏起来。判据与 DYYYShareFindDivider 同款，只是那条找视图、这条找层：
// 卡片层本身按指针排除，剩下的按「细长」认——卡片有一整行那么高，分割线是亚像素。
// 只接管当前可见的那条：抖音自己就藏起来的（末行、或它另有判断）不必碰，
// 也就不会在还原时把一条本不该出现的线写回去。
// 高度不设下限——描边画的一条线，路径包围盒高度是 0。
static CALayer *DYPlusShareFindCardDivider(UIView *host, CALayer *card) {
    for (CALayer *layer in host.layer.sublayers) {
        if (layer == card || layer.hidden || [layer.delegate isKindOfClass:UIView.class]) continue;
        CGRect rect = DYPlusShareCardRect(layer);
        if (CGRectGetHeight(rect) < 1.5 && CGRectGetWidth(rect) >= 200.0) return layer;
    }
    return nil;
}

// 抖音复用行之后会把 hidden 写回来，每轮布局都重设一次。记着的层脱离层级就重新找。
static void DYPlusShareHideCardDivider(UICollectionViewCell *cell, UIView *host, CALayer *card) {
    CALayer *divider = objc_getAssociatedObject(cell, &kCardDividerKey);
    if (divider && !divider.superlayer) {
        objc_setAssociatedObject(cell, &kCardDividerKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(cell, &kCardDividerHiddenKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        divider = nil;
    }
    if (!divider) {
        divider = DYPlusShareFindCardDivider(host, card);
        if (!divider) return;
        // 判据已经排掉了藏着的层，记下的原状态恒为「可见」。
        objc_setAssociatedObject(cell, &kCardDividerKey, divider, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(cell, &kCardDividerHiddenKey, @NO, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    if (!divider.hidden) divider.hidden = YES;
}

static void DYPlusShareRestoreCardDivider(UICollectionViewCell *cell) {
    CALayer *divider = objc_getAssociatedObject(cell, &kCardDividerKey);
    NSNumber *hidden = objc_getAssociatedObject(cell, &kCardDividerHiddenKey);
    if (divider && hidden) divider.hidden = hidden.boolValue;
    objc_setAssociatedObject(cell, &kCardDividerKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(cell, &kCardDividerHiddenKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

static void DYPlusShareRestoreCardCell(UICollectionViewCell *cell) {
    CALayer *layer = objc_getAssociatedObject(cell, &kCardLayerKey);
    UIColor *fill = objc_getAssociatedObject(cell, &kCardFillKey);
    if (layer && fill) {
        if ([layer isKindOfClass:CAShapeLayer.class]) ((CAShapeLayer *)layer).fillColor = fill.CGColor;
        else layer.backgroundColor = fill.CGColor;
    }
    DYPlusShareRestoreCardDivider(cell);
    DYPlusShareDiscardGlass(cell, &kCardGlassKey);
    objc_setAssociatedObject(cell, &kCardLayerKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(cell, &kCardFillKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [gCardCells removeObject:cell];
}

// 每行一枚独立胶囊：矩形取抖音那块卡片底的实际几何，上下各内缩 kDYYYShareCardGapInset 让相邻两行
// 之间露出面板玻璃，圆角交给系统 capsuleConfiguration 按内缩后的高度算，行序与行数都不参与。
// covered：输入区白垫整段罩住了卡片。此时卡片玻璃要藏起来，否则它会从白垫玻璃底下透成
// 一块更亮的矩形（同一处三层玻璃）；填充与分割线仍保持清掉 / 隐藏，写回去会更显眼。
static void DYPlusShareApplyCardCell(UICollectionViewCell *cell, UIViewController *controller,
                                 BOOL covered)
    API_AVAILABLE(ios(26.0)) {
    CALayer *layer = objc_getAssociatedObject(cell, &kCardLayerKey);
    // 抖音换掉绘制层时旧层会脱离层级，记着的那个再清也没用，重新找一次。
    if (layer && !layer.superlayer) {
        objc_setAssociatedObject(cell, &kCardLayerKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(cell, &kCardFillKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        layer = nil;
    }
    BOOL taken = layer != nil;
    if (!layer) layer = DYPlusShareCardLayer(cell, 0);
    if (!layer) return;
    UIView *host = [layer.superlayer.delegate isKindOfClass:UIView.class]
        ? (UIView *)layer.superlayer.delegate : nil;
    if (!host) return;

    // 玻璃挂到行最底层，而不是塞进持有卡片底的那层视图：那层里还有别的裸 sublayer，
    // insertSubview:atIndex:0 只在视图之间排序，玻璃会排到裸层之后把它们盖掉。
    CGRect rect = CGRectInset([host convertRect:DYPlusShareCardRect(layer) toView:cell],
                              0.0, kDYPlusShareCardGapInset);
    if (!DYPlusShareRectUsable(rect)) return;

    BOOL shape = [layer isKindOfClass:CAShapeLayer.class];
    if (!taken) {
        CGColorRef fill = shape ? ((CAShapeLayer *)layer).fillColor : layer.backgroundColor;
        objc_setAssociatedObject(cell, &kCardLayerKey, layer, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(cell, &kCardFillKey, [UIColor colorWithCGColor:fill],
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [gCardCells addObject:cell];
    }
    // 复用后抖音会把填充写回来，每次布局都清一次；行间分割线同理。
    if (shape) ((CAShapeLayer *)layer).fillColor = NULL;
    else layer.backgroundColor = NULL;
    DYPlusShareHideCardDivider(cell, host, layer);

    BOOL fresh = objc_getAssociatedObject(cell, &kCardGlassKey) == nil;
    UIVisualEffectView *glass = DYPlusShareEnsureGlass(cell, &kCardGlassKey, cell);
    glass.autoresizingMask = UIViewAutoresizingNone;
    if (glass.hidden != covered) glass.hidden = covered;
    if (fresh) glass.cornerConfiguration = [UICornerConfiguration capsuleConfiguration];
    DYPlusSharePlaceGlass(glass, rect, cell, nil);
    DYPlusShareMaterialize(glass, controller);
}

static void DYPlusShareCollectCardCells(UIView *view, NSMutableArray<UICollectionViewCell *> *output,
                                    NSUInteger depth) {
    if (!view || depth > 8) return;
    if ([view isKindOfClass:%c(CommentLongPressPanelNormalBaseCell)]) {
        [output addObject:(UICollectionViewCell *)view];
        return;
    }
    for (UIView *subview in view.subviews) DYPlusShareCollectCardCells(subview, output, depth + 1);
}

static BOOL DYPlusShareIsCommentSheet(UIViewController *controller) {
    return [NSStringFromClass(controller.class) isEqualToString:kDYPlusShareCommentSheetClass];
}

// 底色槽只按「画底的普通视图」排除，不按类名精确匹配：
// KVO / 动画会给视图换 isa，object_getClass 拿到的是运行时子类，精确比类会漏判。
static BOOL DYPlusShareCanBePlate(UIView *view) {
    return ![view isKindOfClass:UIScrollView.class]
        && ![view isKindOfClass:UIVisualEffectView.class]
        && ![view isKindOfClass:UIControl.class]
        && ![view isKindOfClass:UIImageView.class]
        && ![view isKindOfClass:UILabel.class];
}

// 面板底色槽：外壳 contentView 里那张满幅不透明浅底。
static UIView *DYPlusShareCommentSlot(UIView *shell) {
    UIView *host = [shell isKindOfClass:UIVisualEffectView.class]
        ? ((UIVisualEffectView *)shell).contentView : shell;
    for (UIView *subview in host.subviews) {
        if (objc_getAssociatedObject(subview, &kPlateColorKey)) return subview;
        if (!DYPlusShareCanBePlate(subview)) continue;
        if (!DYPlusShareCGColorIsPlate(subview.backgroundColor.CGColor)) continue;
        if (fabs(CGRectGetWidth(subview.bounds) - CGRectGetWidth(host.bounds)) > 1.0) continue;
        if (fabs(CGRectGetHeight(subview.bounds) - CGRectGetHeight(host.bounds)) > 1.0) continue;
        return subview;
    }
    return nil;
}

// 输入区白垫盖住列表，且比覆盖层高（还罩着表情面板那一段），玻璃挂它、覆盖层只清底色。
static void DYPlusShareCommentWalk(UIViewController *list, UIView **overlay,
                               UIView **plate, UIView **toolbar) {
    if (overlay) *overlay = nil;
    if (plate) *plate = nil;
    if (toolbar) *toolbar = nil;
    if (!list.isViewLoaded) return;

    Class overlayClass = DYPlusShareOverlayClass();
    Class toolbarClass = %c(AWEIMShareInputEmoticonToolBarView);
    UIView *found = nil;
    for (UIView *subview in list.view.subviews) {
        if (overlayClass && !found && [subview isKindOfClass:overlayClass]) found = subview;
        if (toolbar && toolbarClass && !*toolbar && [subview isKindOfClass:toolbarClass]) {
            *toolbar = subview;
        }
    }
    if (overlay) *overlay = found;
    if (!plate) return;
    for (UIView *subview in list.view.subviews) {
        if (subview == found || (toolbar && subview == *toolbar)) continue;
        if (objc_getAssociatedObject(subview, &kPlateColorKey)) {
            *plate = subview;
            return;
        }
        if (!found || !DYPlusShareCanBePlate(subview)) continue;
        if (!DYPlusShareCGColorIsPlate(subview.backgroundColor.CGColor)) continue;
        // 1pt 余量：白垫和覆盖层顶边对齐，浮点噪声不该判成「没框住」。
        if (CGRectGetMinY(subview.frame) > CGRectGetMinY(found.frame) + 1.0) continue;
        if (CGRectGetMaxY(subview.frame) < CGRectGetMaxY(found.frame) - 1.0) continue;
        if (CGRectGetWidth(subview.frame) < CGRectGetWidth(found.frame) - 1.0) continue;
        *plate = subview;
        return;
    }
}

static UIViewController *DYPlusShareCommentList(UIViewController *sheet) {
    return DYPlusChildControllerNamed(sheet, kDYPlusShareCommentListClass);
}

static void DYPlusShareRestoreCommentSheet(UIViewController *sheet) {
    if (sheet.isViewLoaded) {
        DYPlusShareRestorePlate(DYPlusShareCommentSlot(DYPlusShareEffectView(sheet) ?: sheet.view));
    }
    UIViewController *list = DYPlusShareCommentList(sheet);
    UIView *overlay = nil;
    UIView *plate = nil;
    UIView *toolbar = nil;
    DYPlusShareCommentWalk(list, &overlay, &plate, &toolbar);
    if (overlay) {
        NSMutableArray<UIButton *> *buttons = [NSMutableArray array];
        DYPlusShareCollectSendButtons(overlay, buttons, 0);
        for (UIButton *button in buttons) DYPlusShareRestoreSendButton(button);
        DYPlusShareRestoreOverlay(overlay);
    }
    if (plate) DYPlusShareRestorePlate(plate);
    if (toolbar) DYPlusShareRestoreToolbar(toolbar);
    for (UICollectionViewCell *cell in gCardCells.allObjects) {
        if (!list.viewIfLoaded || [cell isDescendantOfView:list.view]) DYPlusShareRestoreCardCell(cell);
    }
    [gCommentSheets removeObject:sheet];
}

static void DYPlusShareCommentSyncContents(UIViewController *sheet) API_AVAILABLE(ios(26.0)) {
    if (!sheet.isViewLoaded) return;
    BOOL enabled = DYPlusShareEnabled();
    if (!enabled) {
        if (gEverAttached) DYPlusShareRestoreCommentSheet(sheet);
        return;
    }

    [gCommentSheets addObject:sheet];
    DYPlusShareObserveStyle(sheet.view);
    UIUserInterfaceStyle style = DYPlusGlassStyleForView(sheet.view);

    UIView *shell = DYPlusShareEffectView(sheet);
    UIView *slot = DYPlusShareCommentSlot(shell ?: sheet.view);
    UIViewController *list = DYPlusShareCommentList(sheet);
    UIViewController *controller = list ?: sheet;

    UIView *overlay = nil;
    UIView *plate = nil;
    UIView *toolbar = nil;
    DYPlusShareCommentWalk(list, &overlay, &plate, &toolbar);

    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    UIVisualEffectView *panel = nil;
    if (slot) {
        CGFloat radius = shell ? shell.layer.cornerRadius : 0.0;
        if (radius <= 0.0) radius = kDYPlusShareRadiusFloor;
        UICornerRadius *top = [UICornerRadius containerConcentricRadiusWithMinimum:radius];
        UICornerConfiguration *corners =
            [UICornerConfiguration configurationWithUniformTopRadius:top
                                                    bottomLeftRadius:nil
                                                   bottomRightRadius:nil];
        panel = DYPlusShareApplyPlate(slot, corners, controller);
    }
    BOOL inputUp = overlay && !overlay.hidden;
    if (inputUp) {
        DYPlusShareStripOverlay(overlay);
        DYPlusShareApplySendButtons(overlay, controller);
        if (!DYPlusShareApplyPlate(plate, nil, controller)) plate = nil;
    } else {
        if (overlay) DYPlusShareRestoreOverlay(overlay);
        if (plate) DYPlusShareRestorePlate(plate);
        plate = nil;
    }
    if (toolbar) DYPlusShareApplyToolbar(toolbar, controller);

    NSMutableArray<UICollectionViewCell *> *cells = [NSMutableArray array];
    DYPlusShareCollectCardCells(list.viewIfLoaded, cells, 0);
    BOOL covered = plate != nil && !plate.hidden;
    for (UICollectionViewCell *cell in cells) DYPlusShareApplyCardCell(cell, controller, covered);
    [CATransaction commit];

    if (panel) DYPlusShareApplyStyle(style, YES);
}

// 安装玻璃会触发 effect view 和操作行的布局，同一面板的一轮同步只执行一次。
static void DYPlusShareCommentSync(UIViewController *sheet) API_AVAILABLE(ios(26.0)) {
    if (!sheet || [objc_getAssociatedObject(sheet, &kCommentSyncingKey) boolValue]) return;
    objc_setAssociatedObject(sheet, &kCommentSyncingKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    @try {
        DYPlusShareCommentSyncContents(sheet);
    } @finally {
        objc_setAssociatedObject(sheet, &kCommentSyncingKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
}

// 面板外壳是 Swift 类、布局回调不保证经过被挂钩的基类，行自己也能把整面板的同步带起来。
static UIViewController *DYPlusShareCommentSheetForView(UIView *view) {
    for (UIResponder *responder = view.nextResponder; responder; responder = responder.nextResponder) {
        if ([responder isKindOfClass:UIViewController.class]
            && DYPlusShareIsCommentSheet((UIViewController *)responder)) {
            return (UIViewController *)responder;
        }
    }
    return nil;
}

#pragma mark - 同步

static void DYPlusShareRestoreController(AWESharePanelContainerViewController *container) {
    AWESharePanelViewController *content = DYPlusShareContentController(container);
    if (content.isViewLoaded) {
        DYPlusShareRestoreInput(content);
        DYPlusShareRestoreClose(DYPlusShareCloseButton(content));
        DYPlusShareDetachPanel(content.view);
    }
    for (AWESharePanelFunctionCell *cell in gCells.allObjects) {
        if (!content.view || [cell isDescendantOfView:content.view]) DYPlusShareRestoreCell(cell);
    }
    [gContainers removeObject:container];
}

static void DYPlusShareRestoreAll(void) {
    for (AWESharePanelFunctionCell *cell in gCells.allObjects) DYPlusShareRestoreCell(cell);
    for (AWESharePanelContainerViewController *container in gContainers.allObjects) {
        AWESharePanelViewController *content = DYPlusShareContentController(container);
        if (content.isViewLoaded) {
            DYPlusShareRestoreInput(content);
            DYPlusShareRestoreClose(DYPlusShareCloseButton(content));
            DYPlusShareDetachPanel(content.view);
        }
    }
    [gContainers removeAllObjects];
    for (UIViewController *sheet in gCommentSheets.allObjects) DYPlusShareRestoreCommentSheet(sheet);
    for (UICollectionViewCell *cell in gCardCells.allObjects) DYPlusShareRestoreCardCell(cell);
    [gCommentSheets removeAllObjects];
}

static void DYPlusShareSync(AWESharePanelContainerViewController *container) API_AVAILABLE(ios(26.0)) {
    if (!container.isViewLoaded) return;
    BOOL enabled = DYPlusShareEnabled();
    if (!enabled && !gEverAttached) return;

    AWESharePanelViewController *content = DYPlusShareContentController(container);
    if (!content.isViewLoaded) return;

    if (!enabled) {
        DYPlusShareRestoreController(container);
        return;
    }

    [gContainers addObject:container];
    DYPlusShareObserveStyle(content.view);
    UIUserInterfaceStyle style = DYPlusGlassStyleForView(content.view);
    UIView *shell = DYPlusShareEffectView(container);

    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    UIVisualEffectView *panel = DYPlusShareAttachPanel(content.view, shell ?: content.view);
    DYPlusShareApplyClose(DYPlusShareCloseButton(content), content);
    DYPlusShareApplyVisibleCells(content);
    DYPlusShareSyncInput(content);
    [CATransaction commit];

    if (panel) {
        DYPlusShareApplyStyle(style, YES);
        DYPlusShareMaterialize(panel, content);
    }
}

static void DYPlusShareRefreshVisible(void) {
    BOOL enabled = DYPlusShareEnabled();
    if (!enabled) DYPlusShareRestoreAll();
    for (AWESharePanelContainerViewController *container in gContainers.allObjects) {
        [container.viewIfLoaded setNeedsLayout];
    }
    for (UIViewController *sheet in gCommentSheets.allObjects) {
        if (@available(iOS 26.0, *)) DYPlusShareCommentSync(sheet);
    }
    for (AWESharePanelFunctionCell *cell in gCells.allObjects) {
        if (!enabled) continue;
        if (@available(iOS 26.0, *)) DYPlusShareApplyCell(cell, DYPlusShareControllerForView(cell));
    }
}

#pragma mark - Hook

%group DYPlusSharePanelGlassHooks

%hook AWESharePanelContainerViewController

- (void)viewWillAppear:(BOOL)animated {
    %orig;
    if (@available(iOS 26.0, *)) DYPlusShareSync(self);
}

- (void)viewDidLayoutSubviews {
    %orig;
    if (@available(iOS 26.0, *)) DYPlusShareSync(self);
}

- (void)viewDidDisappear:(BOOL)animated {
    %orig;
    if (self.viewIfLoaded.window) return;
    DYPlusShareRestoreController(self);
}

%end

%hook AWESharePanelViewController

- (void)viewDidLayoutSubviews {
    %orig;
    UIViewController *parent = self.parentViewController;
    while (parent && ![parent isKindOfClass:%c(AWESharePanelContainerViewController)]) {
        parent = parent.parentViewController;
    }
    if ([parent isKindOfClass:%c(AWESharePanelContainerViewController)]) {
        if (@available(iOS 26.0, *)) {
            DYPlusShareSync((AWESharePanelContainerViewController *)parent);
        }
    }
}

- (void)awe_themeReload {
    %orig;
    UIViewController *parent = self.parentViewController;
    while (parent && ![parent isKindOfClass:%c(AWESharePanelContainerViewController)]) {
        parent = parent.parentViewController;
    }
    if ([parent isKindOfClass:%c(AWESharePanelContainerViewController)]) {
        if (@available(iOS 26.0, *)) {
            DYPlusShareSync((AWESharePanelContainerViewController *)parent);
        }
    }
}

%end

%hook AWESharePanelFunctionCell

- (void)layoutSubviews {
    %orig;
    if (!DYPlusShareEnabled()) {
        if (objc_getAssociatedObject(self, &kCellGlassKey)) DYPlusShareRestoreCell(self);
        return;
    }
    if (@available(iOS 26.0, *)) DYPlusShareApplyCell(self, DYPlusShareControllerForView(self));
}

- (void)updateWithViewModel:(id)viewModel bigFontAdapter:(id)adapter {
    %orig;
    if (!DYPlusShareEnabled()) return;
    if (@available(iOS 26.0, *)) DYPlusShareApplyCell(self, DYPlusShareControllerForView(self));
}

- (void)updateImageViewWithViewModel:(id)viewModel {
    %orig;
    if (!DYPlusShareEnabled()) return;
    if (@available(iOS 26.0, *)) DYPlusShareApplyCell(self, nil);
}

- (void)prepareForReuse {
    %orig;
    if (!DYPlusShareEnabled()) DYPlusShareRestoreCell(self);
}

%end

%hook AWEIMShareInputEmoticonToolBarView

- (void)layoutSubviews {
    %orig;
    if (!DYPlusShareEnabled()) {
        if (objc_getAssociatedObject(self, &kToolbarGlassKey)) DYPlusShareRestoreToolbar(self);
        return;
    }
    if (@available(iOS 26.0, *)) {
        DYPlusShareApplyToolbar(self, DYPlusShareControllerForView(self));
    }
}

- (void)setTabBackgroundColor:(id)color {
    if (DYPlusShareEnabled() && DYPlusShareControllerForView(self)) {
        if ([color isKindOfClass:UIColor.class] && DYPlusShareColorOpaque(color)) {
            DYPlusShareRememberColor(self, &kToolbarColorKey, &kToolbarOpaqueKey);
            %orig(UIColor.clearColor);
            return;
        }
    }
    %orig;
}

%end

// 分享评论面板的外壳，按类名只认这一种 DUX 弹层；分享面板走它自己那条 hook。
%hook DUXContentSheet

- (void)viewWillAppear:(BOOL)animated {
    %orig;
    if (!DYPlusShareIsCommentSheet(self)) return;
    if (@available(iOS 26.0, *)) DYPlusShareCommentSync(self);
}

- (void)viewDidLayoutSubviews {
    %orig;
    if (!DYPlusShareIsCommentSheet(self)) return;
    if (@available(iOS 26.0, *)) DYPlusShareCommentSync(self);
}

- (void)viewDidDisappear:(BOOL)animated {
    %orig;
    if (!DYPlusShareIsCommentSheet(self) || self.viewIfLoaded.window) return;
    DYPlusShareRestoreCommentSheet(self);
}

%end

%hook CommentLongPressPanelNormalBaseCell

- (void)layoutSubviews {
    %orig;
    if (!DYPlusShareEnabled()) {
        if (objc_getAssociatedObject(self, &kCardGlassKey)) DYPlusShareRestoreCardCell(self);
        return;
    }
    // 面板外壳是 Swift 类、它的布局回调不保证经过被挂钩的基类，行这一路是同步的主驱动：
    // 白垫是选人之后才加进来的，只有每次列表布局都重扫一遍才接得住。
    if (@available(iOS 26.0, *)) {
        UIViewController *sheet = DYPlusShareCommentSheetForView(self);
        if (sheet) DYPlusShareCommentSync(sheet);
    }
}

- (void)prepareForReuse {
    %orig;
    if (!DYPlusShareEnabled()) DYPlusShareRestoreCardCell(self);
}

%end

%hook UIVisualEffectView

- (void)setEffect:(UIVisualEffect *)effect {
    if (DYPlusShareEnabled() && objc_getAssociatedObject(self, &kOverlayTakenKey) && effect) {
        %orig(nil);
        return;
    }
    %orig;
}

// 单选 ↔ 多选切换只换发送按钮、不改覆盖层高度，面板那层布局回调不一定跑，
// 由被接管的覆盖层自己补一次。判据先看关联对象，未接管的 effect view 直接返回。
// 分享评论面板还要顺带重扫一次白垫——它和覆盖层不是同时到位的。
- (void)layoutSubviews {
    %orig;
    if (!objc_getAssociatedObject(self, &kOverlayTakenKey) || !DYPlusShareEnabled()) return;
    if (@available(iOS 26.0, *)) {
        UIViewController *sheet = DYPlusShareCommentSheetForView(self);
        if (sheet) DYPlusShareCommentSync(sheet);
        else DYPlusShareApplySendButtons(self, DYPlusShareControllerForView(self));
    }
}

%end

%hook UIView

- (void)setBackgroundColor:(UIColor *)color {
    if (DYPlusShareEnabled() && DYPlusShareColorOpaque(color)
        && (objc_getAssociatedObject(self, &kOverlayColorKey)
            || objc_getAssociatedObject(self, &kButtonColorKey)
            || objc_getAssociatedObject(self, &kToolbarColorKey)
            || objc_getAssociatedObject(self, &kPlateColorKey))) {
        %orig(UIColor.clearColor);
        return;
    }
    %orig;
}

%end

%end

#pragma mark - 设置

%ctor {
    gGlassCarriers = [NSHashTable weakObjectsHashTable];
    gContainers = [NSHashTable weakObjectsHashTable];
    gCells = [NSHashTable weakObjectsHashTable];
    gCommentSheets = [NSHashTable weakObjectsHashTable];
    gCardCells = [NSHashTable weakObjectsHashTable];

    if (DYPlusGlassOSAvailable()) {
        %init(DYPlusSharePanelGlassHooks);
        [[NSNotificationCenter defaultCenter] addObserverForName:@"DYYYSettingChanged"
                                                          object:nil
                                                           queue:NSOperationQueue.mainQueue
                                                      usingBlock:^(NSNotification *note) {
            NSString *changedKey = note.userInfo[@"key"];
            if ([changedKey isEqualToString:DYPlusKeySharePanelGlass] ||
                [changedKey isEqualToString:DYPlusKeySharePanelGlassClear]) {
                DYPlusShareRefreshVisible();
            }
        }];
    }
}
