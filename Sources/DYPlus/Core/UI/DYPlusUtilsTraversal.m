//
//  DYPlusUtilsTraversal.m
//  DYYY
//
//  视图/控制器层级遍历、玻璃 flex 判断。
//

#import "Core/Utilities/DYPlusUtils.h"

@interface UIView (DYPlusGlassFlexPrivate)
- (UIView *)_flexInteractionGestureView;
@end

@implementation DYPlusGlassFlexView

- (UIView *)_flexInteractionGestureView {
    UIView *source = self.flexSourceView;
    if (source && source.window) return source;
    return [super _flexInteractionGestureView];
}

@end

UIView *DYPlusGlassFlexResolvedSource(UIView *glass) {
    if (![glass respondsToSelector:@selector(_flexInteractionGestureView)]) return nil;
    return [glass _flexInteractionGestureView];
}

BOOL DYPlusGlassFlexInstalled(UIView *glass) {
    static NSMapTable *cache = nil;
    static dispatch_once_t onceToken;
    static NSString *const suffix = @"FlexInteraction";
    dispatch_once(&onceToken, ^{
        cache = [[NSMapTable alloc] initWithKeyOptions:NSPointerFunctionsOpaquePersonality
                                         valueOptions:NSPointerFunctionsStrongMemory
                                             capacity:16];
    });

    for (id<UIInteraction> interaction in glass.interactions) {
        Class interactionClass = [interaction class];
        NSNumber *cached = [cache objectForKey:(__bridge id)(__bridge void *)interactionClass];
        if (!cached) {
            BOOL matches = [NSStringFromClass(interactionClass) containsString:suffix];
            cached = @(matches);
            [cache setObject:cached forKey:(__bridge id)(__bridge void *)interactionClass];
        }
        if (cached.boolValue) return YES;
    }
    return NO;
}

@interface DYPlusUtils (Traversal)
+ (void)findSubviewsOfClass:(Class)targetClass inView:(UIView *)view result:(NSMutableArray<UIView *> *)result;
@end

@implementation DYPlusUtils (Traversal)

+ (UIViewController *)findViewControllerFromView:(UIView *)view {
    if (!view) return nil;
    UIResponder *responder = view;
    while (responder) {
        if ([responder isKindOfClass:[UIViewController class]]) {
            return (UIViewController *)responder;
        }
        responder = responder.nextResponder;
    }
    return nil;
}

+ (UIViewController *)findViewControllerOfClass:(Class)targetClass inViewController:(UIViewController *)vc {
    if (!targetClass || !vc) {
        return nil;
    }
    for (UIViewController *candidate in DYPlusAllViewControllersInHierarchy(vc)) {
        if ([candidate isKindOfClass:targetClass]) return candidate;
    }
    return nil;
}

+ (NSArray<UIView *> *)findAllSubviewsOfClass:(Class)targetClass inContainer:(UIView *)container {
    NSMutableArray<UIView *> *foundViews = [NSMutableArray array];
    [self findSubviewsOfClass:targetClass inView:container result:foundViews];
    return [foundViews copy];
}

+ (void)findSubviewsOfClass:(Class)targetClass inView:(UIView *)view result:(NSMutableArray<UIView *> *)result {
    if ([view isKindOfClass:targetClass]) {
        [result addObject:view];
    }

    for (UIView *subview in view.subviews) {
        [self findSubviewsOfClass:targetClass inView:subview result:result];
    }
}

@end
