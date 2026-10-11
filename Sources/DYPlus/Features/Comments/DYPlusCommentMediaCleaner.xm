//
//  DYPlusCommentMediaCleaner.xm
//  功能：清理评论图片大图页底栏、返回键与渐变，并让图片在完整窗口内按原比例居中显示。
//

#import "Integration/Headers/DYPlusAwemeHeaders.h"
#import "Core/Utilities/DYPlusUtils.h"
#import "Core/Utilities/DYPlusUtils.h"
#import "Core/Utilities/DYPlusUtils.h"
#import <math.h>
#import <objc/runtime.h>

static NSString *const kDYPlusMediaInputClass =
    @"AWECommentInputViewSwiftImpl.CommentInputContainerView";
static NSString *const kDYPlusMediaCommonControllerClass =
    @"AWECommentMediaFeedSwfitImpl.CommentMediaFeedCommonImageCellViewController";
static NSString *const kDYPlusMediaInteractionControllerClass =
    @"AWECommentMediaFeedSwfitImpl.CommentMediaFeedPlayInteractionViewController";
static NSString *const kDYPlusMediaInteractionViewClass =
    @"AWECommentMediaFeedSwfitImpl.CommentMediaFeedPlayInteractionView";
static NSString *const kDYPlusMediaUserNameViewClass =
    @"AWECommentMediaFeedSwfitImpl.CommentMediaFeedUserNameContainerView";
static NSString *const kDYPlusMediaInteractionTagClass =
    @"AWECommentMediaFeedSwfitImpl.CommentMediaFeedPlayInteractionTag";
static NSString *const kDYPlusMediaPreviewClass =
    @"AWECommentMediaFeedSwfitImpl.CommentMediaFeedImagePreviewView";
static NSString *const kDYPlusMediaBackButtonIdentifier = @"CommentMediaFeedBackButton";

static char kDYPlusMediaVisibilityManagedKey;
static char kDYPlusMediaOriginalAlphaKey;
static char kDYPlusMediaOriginalHiddenKey;
static char kDYPlusMediaOriginalInteractionKey;
static char kDYPlusMediaOriginalAccessibilityKey;
static char kDYPlusMediaOriginalContentModeKey;
static char kDYPlusMediaCollectionExpandedKey;
static char kDYPlusMediaCollectionSizeKey;
static char kDYPlusMediaNativeReanchorKey;

static NSHashTable<UIView *> *gDYPlusMediaManagedViews;
static NSHashTable<AWECommentMediaFeedViewController *> *gDYPlusMediaControllers;

static BOOL DYPlusCommentMediaCleanerEnabled(void) {
    return DYPlusPrefBool(DYPlusKeyCommentMediaCleanBottomBar);
}

#pragma mark - 可逆视图状态

static void DYPlusMediaRememberVisibility(UIView *view) {
    if (!view || [objc_getAssociatedObject(view, &kDYPlusMediaVisibilityManagedKey) boolValue]) return;

    objc_setAssociatedObject(view, &kDYPlusMediaOriginalAlphaKey,
                             @(view.alpha), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(view, &kDYPlusMediaOriginalHiddenKey,
                             @(view.hidden), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(view, &kDYPlusMediaOriginalInteractionKey,
                             @(view.userInteractionEnabled), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(view, &kDYPlusMediaOriginalAccessibilityKey,
                             @(view.accessibilityElementsHidden), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(view, &kDYPlusMediaVisibilityManagedKey,
                             @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [gDYPlusMediaManagedViews addObject:view];
}

static void DYPlusMediaSuppressView(UIView *view) {
    if (!view) return;
    DYPlusMediaRememberVisibility(view);

    if (view.alpha != 0.0) view.alpha = 0.0;
    if (!view.hidden) view.hidden = YES;
    if (view.userInteractionEnabled) view.userInteractionEnabled = NO;
    if (!view.accessibilityElementsHidden) view.accessibilityElementsHidden = YES;
}

static void DYPlusMediaApplyAspectFit(UIView *view) {
    if (!view) return;
    if (!objc_getAssociatedObject(view, &kDYPlusMediaOriginalContentModeKey)) {
        objc_setAssociatedObject(view, &kDYPlusMediaOriginalContentModeKey,
                                 @(view.contentMode), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [gDYPlusMediaManagedViews addObject:view];
    }
    if (view.contentMode != UIViewContentModeScaleAspectFit) {
        view.contentMode = UIViewContentModeScaleAspectFit;
    }
}

static void DYPlusMediaRestoreView(UIView *view) {
    if (!view) return;

    if ([objc_getAssociatedObject(view, &kDYPlusMediaVisibilityManagedKey) boolValue]) {
        NSNumber *alpha = objc_getAssociatedObject(view, &kDYPlusMediaOriginalAlphaKey);
        NSNumber *hidden = objc_getAssociatedObject(view, &kDYPlusMediaOriginalHiddenKey);
        NSNumber *interaction = objc_getAssociatedObject(view, &kDYPlusMediaOriginalInteractionKey);
        NSNumber *accessibility = objc_getAssociatedObject(view, &kDYPlusMediaOriginalAccessibilityKey);
        if (alpha) view.alpha = alpha.doubleValue;
        if (hidden) view.hidden = hidden.boolValue;
        if (interaction) view.userInteractionEnabled = interaction.boolValue;
        if (accessibility) view.accessibilityElementsHidden = accessibility.boolValue;

        objc_setAssociatedObject(view, &kDYPlusMediaVisibilityManagedKey,
                                 nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(view, &kDYPlusMediaOriginalAlphaKey,
                                 nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(view, &kDYPlusMediaOriginalHiddenKey,
                                 nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(view, &kDYPlusMediaOriginalInteractionKey,
                                 nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(view, &kDYPlusMediaOriginalAccessibilityKey,
                                 nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }

    NSNumber *contentMode = objc_getAssociatedObject(view, &kDYPlusMediaOriginalContentModeKey);
    if (contentMode) {
        view.contentMode = (UIViewContentMode)contentMode.integerValue;
        objc_setAssociatedObject(view, &kDYPlusMediaOriginalContentModeKey,
                                 nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }

    [gDYPlusMediaManagedViews removeObject:view];
}

static void DYPlusMediaRestoreViewsUnderRoot(UIView *root) {
    if (!root) return;
    for (UIView *view in gDYPlusMediaManagedViews.allObjects) {
        if (view == root || [view isDescendantOfView:root]) DYPlusMediaRestoreView(view);
    }
}

#pragma mark - 结构匹配

static Class DYPlusMediaInputClass(void) {
    static Class cls;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ cls = NSClassFromString(kDYPlusMediaInputClass); });
    return cls;
}

static BOOL DYPlusMediaViewContainsClass(UIView *view, NSString *className, NSUInteger depth) {
    if (!view || depth > 12) return NO;
    if ([NSStringFromClass(view.class) isEqualToString:className]) return YES;
    for (UIView *subview in view.subviews) {
        if (DYPlusMediaViewContainsClass(subview, className, depth + 1)) return YES;
    }
    return NO;
}

static UIView *DYPlusMediaDescendantNamed(UIView *view, NSString *className, NSUInteger depth) {
    if (!view || depth > 12) return nil;
    if ([NSStringFromClass(view.class) isEqualToString:className]) return view;
    for (UIView *subview in view.subviews) {
        UIView *match = DYPlusMediaDescendantNamed(subview, className, depth + 1);
        if (match) return match;
    }
    return nil;
}

static void DYPlusMediaCollectControllersNamed(UIViewController *controller,
                                           NSString *className,
                                           NSMutableArray<UIViewController *> *output,
                                           NSUInteger depth) {
    if (!controller || depth > 12) return;
    for (UIViewController *child in controller.childViewControllers) {
        if ([NSStringFromClass(child.class) isEqualToString:className]) [output addObject:child];
        DYPlusMediaCollectControllersNamed(child, className, output, depth + 1);
    }
}

static NSArray<UIViewController *> *DYPlusMediaControllersNamed(UIViewController *controller,
                                                             NSString *className) {
    NSMutableArray<UIViewController *> *result = [NSMutableArray array];
    DYPlusMediaCollectControllersNamed(controller, className, result, 0);
    return result;
}

static UICollectionView *DYPlusMediaPageCollection(AWECommentMediaFeedViewController *controller) {
    if (!controller.isViewLoaded) return nil;
    UICollectionView *fallback = nil;
    for (UIView *subview in controller.view.subviews) {
        if (![subview isKindOfClass:UICollectionView.class]) continue;
        UICollectionView *collection = (UICollectionView *)subview;
        if (!fallback) fallback = collection;
        if (collection.delegate == (id<UICollectionViewDelegate>)controller
            || collection.dataSource == (id<UICollectionViewDataSource>)controller) {
            return collection;
        }
    }
    return fallback;
}

static UIView *DYPlusMediaInputView(AWECommentMediaFeedViewController *controller) {
    Class inputClass = DYPlusMediaInputClass();
    if (!inputClass || !controller.isViewLoaded) return nil;
    for (UIView *subview in controller.view.subviews) {
        if ([subview isKindOfClass:inputClass]) return subview;
    }
    return nil;
}

static BOOL DYPlusMediaButtonHasAction(UIButton *button, SEL action) {
    if (!button || !action) return NO;
    for (id target in button.allTargets) {
        NSArray<NSString *> *actions =
            [button actionsForTarget:target forControlEvent:UIControlEventTouchUpInside];
        if ([actions containsObject:NSStringFromSelector(action)]) return YES;
    }
    return NO;
}

// 返回键是根视图直属 UIButton。优先取控制器的 backButton，其次认
// CommentMediaFeedBackButton，再认 previewDismissByClickBackBtn。不碰删除键。
static UIView *DYPlusMediaBackButton(AWECommentMediaFeedViewController *controller) {
    if (!controller.isViewLoaded) return nil;

    if ([controller respondsToSelector:@selector(backButton)]) {
        UIView *button = controller.backButton;
        if (button) return button;
    }

    SEL action = @selector(previewDismissByClickBackBtn);
    for (UIView *subview in controller.view.subviews) {
        if (![subview isKindOfClass:UIButton.class]) continue;
        UIButton *button = (UIButton *)subview;
        if ([button.accessibilityIdentifier isEqualToString:kDYPlusMediaBackButtonIdentifier]
            || DYPlusMediaButtonHasAction(button, action)) {
            return button;
        }
    }
    return nil;
}

#pragma mark - 页面控件

static void DYPlusMediaApplyInteractionControls(AWECommentMediaFeedViewController *controller) {
    for (UIViewController *interaction in
         DYPlusMediaControllersNamed(controller, kDYPlusMediaInteractionControllerClass)) {
        UIView *root = interaction.viewIfLoaded;
        for (UIView *container in root.subviews) {
            BOOL containsLike =
                DYPlusMediaViewContainsClass(container, kDYPlusMediaInteractionViewClass, 0);
            BOOL containsInfo =
                DYPlusMediaViewContainsClass(container, kDYPlusMediaUserNameViewClass, 0)
                || DYPlusMediaViewContainsClass(container, kDYPlusMediaInteractionTagClass, 0);
            if (containsLike || containsInfo) {
                DYPlusMediaSuppressView(container);
            } else {
                DYPlusMediaRestoreView(container);
            }
        }
    }
}

static BOOL DYPlusMediaGradientMatchesEdge(UIView *view, BOOL top) {
    if (![NSStringFromClass(view.class) isEqualToString:@"AWEGradientView"]) return NO;
    UIView *parent = view.superview;
    if (!parent) return NO;

    CGRect frame = [view convertRect:view.bounds toView:parent];
    CGRect bounds = parent.bounds;
    CGFloat tolerance = MAX(1.0 / UIScreen.mainScreen.scale, 0.5);
    BOOL fullWidth = fabs(CGRectGetMinX(frame) - CGRectGetMinX(bounds)) <= tolerance
        && fabs(CGRectGetWidth(frame) - CGRectGetWidth(bounds)) <= tolerance;
    if (!fullWidth) return NO;

    if (top) {
        return fabs(CGRectGetMinY(frame) - CGRectGetMinY(bounds)) <= tolerance
            && CGRectGetMaxY(frame) < CGRectGetMaxY(bounds) - tolerance;
    }
    return fabs(CGRectGetMaxY(frame) - CGRectGetMaxY(bounds)) <= tolerance
        && CGRectGetMinY(frame) > CGRectGetMinY(bounds) + tolerance;
}

static void DYPlusMediaApplyChromeGradients(UIView *view) {
    if (!view) return;
    for (UIView *subview in view.subviews) {
        if ([NSStringFromClass(subview.class) isEqualToString:@"AWEGradientView"]) {
            if (DYPlusMediaGradientMatchesEdge(subview, YES) || DYPlusMediaGradientMatchesEdge(subview, NO)) {
                DYPlusMediaSuppressView(subview);
            } else {
                DYPlusMediaRestoreView(subview);
            }
            continue;
        }
        DYPlusMediaApplyChromeGradients(subview);
    }
}

static void DYPlusMediaApplyCommonCellChrome(AWECommentMediaFeedViewController *controller) {
    for (UIViewController *common in
         DYPlusMediaControllersNamed(controller, kDYPlusMediaCommonControllerClass)) {
        DYPlusMediaApplyChromeGradients(common.viewIfLoaded);
    }
}

// 输入栏上沿的分割线是根视图的直属子层，不是 CommentInputContainerView 的后代。
// 判据：普通 UIView、无子视图、全宽、高度不超过 1pt。不写死 y 或底栏高度。
static BOOL DYPlusMediaIsHairlineSeparator(UIView *view, UIView *root) {
    if (!view || !root || view.class != UIView.class || view.subviews.count > 0) return NO;

    CGFloat height = CGRectGetHeight(view.frame);
    if (height <= 0.0 || height > 1.0) return NO;

    CGFloat tolerance = MAX(1.0 / UIScreen.mainScreen.scale, 0.5);
    return fabs(CGRectGetMinX(view.frame) - CGRectGetMinX(root.bounds)) <= tolerance
        && fabs(CGRectGetWidth(view.frame) - CGRectGetWidth(root.bounds)) <= tolerance;
}

static void DYPlusMediaApplyHairlineSeparators(AWECommentMediaFeedViewController *controller) {
    UIView *root = controller.viewIfLoaded;
    if (!root) return;
    for (UIView *subview in root.subviews) {
        if (DYPlusMediaIsHairlineSeparator(subview, root)) DYPlusMediaSuppressView(subview);
    }
}

#pragma mark - 全窗口分页几何

static BOOL DYPlusMediaSizesClose(CGSize lhs, CGSize rhs) {
    return fabs(lhs.width - rhs.width) <= 0.5 && fabs(lhs.height - rhs.height) <= 0.5;
}

static BOOL DYPlusMediaRectsClose(CGRect lhs, CGRect rhs) {
    return fabs(CGRectGetMinX(lhs) - CGRectGetMinX(rhs)) <= 0.5
        && fabs(CGRectGetMinY(lhs) - CGRectGetMinY(rhs)) <= 0.5
        && DYPlusMediaSizesClose(lhs.size, rhs.size);
}

static void DYPlusMediaReanchorCurrentItem(AWECommentMediaFeedViewController *controller,
                                       UICollectionView *collection) {
    NSInteger index = (NSInteger)controller.currentIndex;
    if (index < 0 || collection.numberOfSections == 0
        || index >= [collection numberOfItemsInSection:0]) {
        return;
    }

    NSIndexPath *path = [NSIndexPath indexPathForItem:index inSection:0];
    [collection scrollToItemAtIndexPath:path
                       atScrollPosition:UICollectionViewScrollPositionCenteredVertically
                               animated:NO];
}

static void DYPlusMediaResetCollectionState(AWECommentMediaFeedViewController *controller) {
    UICollectionView *collection = DYPlusMediaPageCollection(controller);
    if (!collection || ![objc_getAssociatedObject(collection, &kDYPlusMediaCollectionExpandedKey) boolValue]) {
        return;
    }

    objc_setAssociatedObject(collection, &kDYPlusMediaCollectionExpandedKey,
                             nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(collection, &kDYPlusMediaCollectionSizeKey,
                             nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(controller, &kDYPlusMediaNativeReanchorKey,
                             @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [collection.collectionViewLayout invalidateLayout];
    [controller.view setNeedsLayout];
}

static void DYPlusMediaApplyCollectionState(AWECommentMediaFeedViewController *controller, BOOL enabled) {
    UICollectionView *collection = DYPlusMediaPageCollection(controller);
    if (!collection) return;

    if (!enabled) {
        DYPlusMediaResetCollectionState(controller);
        if ([objc_getAssociatedObject(controller, &kDYPlusMediaNativeReanchorKey) boolValue]) {
            [UIView performWithoutAnimation:^{
                [collection.collectionViewLayout invalidateLayout];
                [collection layoutIfNeeded];
                DYPlusMediaReanchorCurrentItem(controller, collection);
            }];
            objc_setAssociatedObject(controller, &kDYPlusMediaNativeReanchorKey,
                                     nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        return;
    }

    CGFloat width = CGRectGetWidth(controller.view.bounds);
    CGFloat height = CGRectGetHeight(controller.view.bounds);
    if (width <= 0.0 || height <= 0.0) return;

    CGSize targetSize = CGSizeMake(width, height);
    CGRect targetFrame = CGRectMake(0.0, 0.0, width, height);
    BOOL wasExpanded =
        [objc_getAssociatedObject(collection, &kDYPlusMediaCollectionExpandedKey) boolValue];
    NSValue *lastSizeValue = objc_getAssociatedObject(collection, &kDYPlusMediaCollectionSizeKey);
    BOOL sizeChanged = !wasExpanded || !lastSizeValue
        || !DYPlusMediaSizesClose(lastSizeValue.CGSizeValue, targetSize);

    objc_setAssociatedObject(collection, &kDYPlusMediaCollectionExpandedKey,
                             @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(collection, &kDYPlusMediaCollectionSizeKey,
                             [NSValue valueWithCGSize:targetSize], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(controller, &kDYPlusMediaNativeReanchorKey,
                             nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    [UIView performWithoutAnimation:^{
        if (!DYPlusMediaRectsClose(collection.frame, targetFrame)) collection.frame = targetFrame;
        if (sizeChanged) {
            [collection.collectionViewLayout invalidateLayout];
            [collection layoutIfNeeded];
            DYPlusMediaReanchorCurrentItem(controller, collection);
        }
    }];
}

static void DYPlusMediaApplyControllerState(AWECommentMediaFeedViewController *controller) {
    if (!controller || !controller.isViewLoaded) return;
    BOOL enabled = DYPlusCommentMediaCleanerEnabled();

    if (!enabled) {
        DYPlusMediaRestoreViewsUnderRoot(controller.view);
        DYPlusMediaApplyCollectionState(controller, NO);
        return;
    }

    DYPlusMediaApplyCollectionState(controller, YES);
    DYPlusMediaSuppressView(DYPlusMediaInputView(controller));
    DYPlusMediaSuppressView(DYPlusMediaBackButton(controller));
    DYPlusMediaApplyHairlineSeparators(controller);
    DYPlusMediaApplyInteractionControls(controller);
    DYPlusMediaApplyCommonCellChrome(controller);
}

#pragma mark - 图片显示模式

static BOOL DYPlusMediaIsPreviewCarrier(UIView *view) {
    if ([view isKindOfClass:UIImageView.class]) return YES;
    return [NSStringFromClass(view.class) isEqualToString:@"PHLivePhotoView"];
}

static void DYPlusMediaApplyImageCellState(AWECommentMediaFeedImageCell *cell) {
    UIView *mediaRoot = nil;
    if ([cell respondsToSelector:@selector(mediaContainerView)]) mediaRoot = [cell mediaContainerView];
    UIView *preview = DYPlusMediaDescendantNamed(mediaRoot ?: cell, kDYPlusMediaPreviewClass, 0);
    if (!preview && mediaRoot != cell) {
        preview = DYPlusMediaDescendantNamed(cell, kDYPlusMediaPreviewClass, 0);
    }
    if (!preview) return;

    BOOL enabled = DYPlusCommentMediaCleanerEnabled() && cell.window;
    for (UIView *carrier in preview.subviews) {
        if (!DYPlusMediaIsPreviewCarrier(carrier)) continue;
        if (enabled) {
            DYPlusMediaApplyAspectFit(carrier);
        } else {
            DYPlusMediaRestoreView(carrier);
        }
    }
}

#pragma mark - 钩子

%hook AWECommentMediaFeedViewController

- (CGSize)collectionView:(UICollectionView *)collectionView
                  layout:(UICollectionViewLayout *)collectionViewLayout
  sizeForItemAtIndexPath:(NSIndexPath *)indexPath {
    CGSize size = %orig;
    if (!DYPlusCommentMediaCleanerEnabled() || collectionView != DYPlusMediaPageCollection(self)) return size;

    CGSize target = self.view.bounds.size;
    return target.width > 0.0 && target.height > 0.0 ? target : size;
}

- (void)viewWillAppear:(BOOL)animated {
    %orig;
    [gDYPlusMediaControllers addObject:self];
    [self.view setNeedsLayout];
}

- (void)viewDidLayoutSubviews {
    %orig;
    [gDYPlusMediaControllers addObject:self];
    DYPlusMediaApplyControllerState(self);
}

- (void)viewDidDisappear:(BOOL)animated {
    %orig;
    if (self.viewIfLoaded.window) return;
    DYPlusMediaRestoreViewsUnderRoot(self.viewIfLoaded);
    DYPlusMediaResetCollectionState(self);
    [gDYPlusMediaControllers removeObject:self];
}

%end

%hook AWECommentMediaFeedImageCell

- (void)layoutSubviews {
    %orig;
    DYPlusMediaApplyImageCellState(self);
}

- (void)didMoveToWindow {
    %orig;
    DYPlusMediaApplyImageCellState(self);
}

%end

#pragma mark - 设置

%ctor {
    gDYPlusMediaManagedViews = [NSHashTable weakObjectsHashTable];
    gDYPlusMediaControllers = [NSHashTable weakObjectsHashTable];
}
