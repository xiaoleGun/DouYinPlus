//
//  DYPlusUtils.m
//  DYYY
//
//  公共工具主文件：配置内存缓存、遍历基础 C 函数、杂项工具方法。
//  广告过滤见 DYYYUtilsAdFilter.m，动图/媒体见 DYYYUtilsMedia.m，
//  视图/控制器遍历与玻璃 flex 见 DYYYUtilsTraversal.m，
//  缓存失效/特性迁移/玻璃门控见 DYYYUtilsConfig.m。
//

#import "Core/Utilities/DYPlusUtils.h"
#import <UIKit/UIKit.h>
#import "Core/UI/DYPlusTheme.h"
#import "Core/Storage/DYPlusPaths.h"
#import "Core/UI/DYPlusUIContext.h"
#import <math.h>

#pragma mark - 遍历基础 C 函数

void DYPlusEnumerateSubviews(UIView *view, void (^block)(UIView *)) {
    if (!view || !block) return;
    NSMutableArray<UIView *> *views = [NSMutableArray arrayWithObject:view];
    NSUInteger index = 0;
    while (index < views.count) {
        @autoreleasepool {
            UIView *current = views[index++];
            block(current);
            [views addObjectsFromArray:current.subviews];
        }
    }
}

NSArray<UIViewController *> *DYPlusAllViewControllersInHierarchy(UIViewController *rootViewController) {
    if (!rootViewController) return @[];
    // 快照仅由调用方持有，不缓存/强持有已退出的控制器，导航变化即时可见。
    NSMutableArray *result = [NSMutableArray array];
    NSMutableArray *queue = [NSMutableArray arrayWithObject:rootViewController];
    NSHashTable *visited = [NSHashTable hashTableWithOptions:NSPointerFunctionsObjectPointerPersonality];
    for (NSUInteger index = 0; index < queue.count && result.count < 4096; index++) {
        UIViewController *controller = queue[index];
        if ([visited containsObject:controller]) continue;
        [visited addObject:controller];
        [result addObject:controller];
        [queue addObjectsFromArray:controller.childViewControllers];
        if (controller.presentedViewController) [queue addObject:controller.presentedViewController];
    }
    return result;
}

static UIViewController *DYPlusSearchChildController(UIViewController *controller, NSString *className, NSUInteger depth) {
    if (!controller || depth > 12) return nil;
    for (UIViewController *child in controller.childViewControllers) {
        if ([NSStringFromClass(child.class) isEqualToString:className]) return child;
        UIViewController *match = DYPlusSearchChildController(child, className, depth + 1);
        if (match) return match;
    }
    return nil;
}

UIViewController *DYPlusChildControllerNamed(UIViewController *controller, NSString *className) {
    return DYPlusSearchChildController(controller, className, 0);
}

BOOL DYPlusColorIsOpaqueBlack(UIColor *color) {
    if (!color) return NO;

    CGFloat red = 0.0;
    CGFloat green = 0.0;
    CGFloat blue = 0.0;
    CGFloat alpha = 0.0;
    if ([color getRed:&red green:&green blue:&blue alpha:&alpha]) {
        return red <= 0.02 && green <= 0.02 && blue <= 0.02 && alpha >= 0.98;
    }

    CGFloat white = 0.0;
    if ([color getWhite:&white alpha:&alpha]) {
        return white <= 0.02 && alpha >= 0.98;
    }
    return NO;
}

UIView *DYPlusCellContentView(UIView *view) {
    static Class contentCls;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ contentCls = NSClassFromString(@"UITableViewCellContentView"); });
    if (!contentCls) return nil;

    for (NSUInteger i = 0; view && i < 12; i++) {
        if ([view isKindOfClass:contentCls]) return view;
        view = view.superview;
    }
    return nil;
}

CGFloat DYPlusFullCellHeight(UIView *view) {
    UIView *contentView = DYPlusCellContentView(view.superview);
    return contentView ? CGRectGetHeight(contentView.bounds) : 0.0;
}

BOOL DYPlusViewControllerChainLooksLikeChat(UIViewController *vc) {
    static NSSet<NSString *> *markers;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        markers = [NSSet setWithObjects:@"Chat", @"Conversation", @"IMDetail", @"QuickReplay", nil];
    });
    for (int i = 0; vc && i < 12; i++) {
        NSString *name = NSStringFromClass(vc.class);
        for (NSString *marker in markers) {
            if ([name containsString:marker]) return YES;
        }
        vc = vc.parentViewController;
    }
    return NO;
}

@implementation DYPlusUtils

+ (void)showToast:(NSString *)message {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIViewController *topVC = [self topView];
        if (!topVC || !topVC.view) return;
        
        // 创建 Toast 标签
        UILabel *toastLabel = [[UILabel alloc] init];
        toastLabel.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.8];
        toastLabel.textColor = [UIColor whiteColor];
        toastLabel.textAlignment = NSTextAlignmentCenter;
        toastLabel.font = [UIFont systemFontOfSize:16];
        toastLabel.text = message;
        toastLabel.alpha = 0.0;
        toastLabel.layer.cornerRadius = 8;
        toastLabel.clipsToBounds = YES;
        
        // 计算大小和位置
        CGSize textSize = [message sizeWithAttributes:@{NSFontAttributeName: toastLabel.font}];
        CGFloat width = textSize.width + 32;
        CGFloat height = textSize.height + 16;
        CGFloat x = (topVC.view.bounds.size.width - width) / 2;
        CGFloat y = topVC.view.bounds.size.height - height - 100;
        
        toastLabel.frame = CGRectMake(x, y, width, height);
        [topVC.view addSubview:toastLabel];
        
        // 显示动画
        [UIView animateWithDuration:0.3 animations:^{
            toastLabel.alpha = 1.0;
        } completion:^(BOOL finished) {
            // 延迟隐藏
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                [UIView animateWithDuration:0.3 animations:^{
                    toastLabel.alpha = 0.0;
                } completion:^(BOOL finished) {
                    [toastLabel removeFromSuperview];
                }];
            });
        }];
    });
}

+ (UIViewController *)topView { return DYPlusVisibleViewController(DYPlusActiveWindow().rootViewController); }

+ (NSUInteger)clearDirectoryContents:(NSString *)directoryPath {
    // 该 API 只允许插件 Temp 根目录。拒绝符号链接，绝不递归进入宿主或外部目录。
    NSString *trusted = [DYPlusPaths tempDir].stringByStandardizingPath;
    NSString *requested = directoryPath.stringByStandardizingPath;
    NSFileManager *files = NSFileManager.defaultManager;
    if (![requested isEqualToString:trusted] ||
        ![[files attributesOfItemAtPath:[DYPlusPaths dyplusRootDir] error:nil][NSFileType] isEqual:NSFileTypeDirectory] ||
        ![[files attributesOfItemAtPath:requested error:nil][NSFileType] isEqual:NSFileTypeDirectory]) return 0;
    NSUInteger total = 0;
    for (NSString *name in [files contentsOfDirectoryAtPath:requested error:nil]) {
        if ([name hasPrefix:@"."]) continue;
        NSString *path = [requested stringByAppendingPathComponent:name];
        NSDictionary *attributes = [files attributesOfItemAtPath:path error:nil];
        NSUInteger size = [attributes fileSize];
        // 枚举器不跟随符号链接，removeItem 删除链接本身。
        if ([attributes[NSFileType] isEqual:NSFileTypeDirectory]) {
            NSDirectoryEnumerator *enumerator = [files enumeratorAtPath:path];
            for (NSString *child in enumerator) {
                NSDictionary *childAttributes = [files attributesOfItemAtPath:[path stringByAppendingPathComponent:child] error:nil];
                if ([childAttributes[NSFileType] isEqual:NSFileTypeRegular]) size += [childAttributes fileSize];
            }
        }
        if ([files removeItemAtPath:path error:nil]) total += size;
    }
    return total;
}

+ (void)applyBlurEffectToView:(UIView *)view transparency:(float)userTransparency blurViewTag:(NSInteger)tag {
    if (!view)
        return;

    view.backgroundColor = [UIColor clearColor];

    UIVisualEffectView *existingBlurView = nil;
    for (UIView *subview in view.subviews) {
        if ([subview isKindOfClass:[UIVisualEffectView class]] && subview.tag == tag) {
            existingBlurView = (UIVisualEffectView *)subview;
            break;
        }
    }

    BOOL isDarkMode = [DYPlusUtils isDarkMode];
    UIBlurEffectStyle blurStyle = isDarkMode ? UIBlurEffectStyleDark : UIBlurEffectStyleLight;

    UIView *overlayView = nil;

    if (!existingBlurView) {
        UIBlurEffect *blurEffect = [UIBlurEffect effectWithStyle:blurStyle];
        UIVisualEffectView *blurEffectView = [[UIVisualEffectView alloc] initWithEffect:blurEffect];
        blurEffectView.frame = view.bounds;
        blurEffectView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        blurEffectView.alpha = userTransparency;
        blurEffectView.tag = tag;

        overlayView = [[UIView alloc] initWithFrame:view.bounds];
        overlayView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        [blurEffectView.contentView addSubview:overlayView];

        [view insertSubview:blurEffectView atIndex:0];
    } else {
        UIBlurEffect *blurEffect = [UIBlurEffect effectWithStyle:blurStyle];
        [existingBlurView setEffect:blurEffect];
        existingBlurView.alpha = userTransparency;

        for (UIView *subview in existingBlurView.contentView.subviews) {
            if ([subview isKindOfClass:[UIView class]]) {
                overlayView = subview;
                break;
            }
        }
        if (!overlayView) {
            overlayView = [[UIView alloc] initWithFrame:existingBlurView.bounds];
            overlayView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
            [existingBlurView.contentView addSubview:overlayView];
        }
    }
    if (overlayView) {
        CGFloat alpha = isDarkMode ? 0.2 : 0.1;
        overlayView.backgroundColor = [UIColor colorWithWhite:(isDarkMode ? 0 : 1) alpha:alpha];
    }
}

+ (void)clearBackgroundRecursivelyInView:(UIView *)view {
    if (!view)
        return;

    BOOL shouldClear = YES;

    if ([view isKindOfClass:[UIVisualEffectView class]]) {
        shouldClear = NO;  // 不清除 UIVisualEffectView 本身的背景
    } else if (view.superview && [view.superview isKindOfClass:[UIVisualEffectView class]]) {
        shouldClear = NO;  // 不清除 UIVisualEffectView 的 contentView 的背景
    }

    if (shouldClear) {
        view.backgroundColor = [UIColor clearColor];
        view.opaque = NO;
    }

    for (UIView *subview in view.subviews) {
        [self clearBackgroundRecursivelyInView:subview];
    }
}

+ (BOOL)isDarkMode {
    return DYPlusThemeIsDark();
}

// 在主线程安全延迟执行：weak-strong dance，避免 owner 释放后回调继续执行
+ (void)dispatchAfter:(NSTimeInterval)delaySeconds owner:(id)owner block:(dispatch_block_t)block {
    if (delaySeconds < 0) delaySeconds = 0;
    __weak id weakOwner = owner;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delaySeconds * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        __strong id strongOwner = weakOwner;
        if (!strongOwner) return;
        if (block) block();
    });
}

@end

NSString *cleanShareURL(NSString *url) {
    if (!url || url.length == 0) {
        return url;
    }
    
    NSRange questionMarkRange = [url rangeOfString:@"?"];

    if (questionMarkRange.location != NSNotFound) {
        return [url substringToIndex:questionMarkRange.location];
    }

    return url;
}
