#import "Core/UI/DYPlusUIContext.h"
UIWindow *DYPlusActiveWindow(void) {
    UIWindow *fallback = nil;
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class] || scene.activationState != UISceneActivationStateForegroundActive) continue;
        for (UIWindow *window in ((UIWindowScene *)scene).windows) {
            if (window.isKeyWindow && !window.hidden) return window;
            if (!fallback && !window.hidden && window.alpha > 0 && window.windowLevel == UIWindowLevelNormal && window.rootViewController) fallback = window;
        }
    }
    return fallback;
}
UIViewController *DYPlusVisibleViewController(UIViewController *root) {
    UIViewController *current = root;
    NSHashTable *visited = [NSHashTable hashTableWithOptions:NSPointerFunctionsObjectPointerPersonality];
    for (NSUInteger depth = 0; current && depth < 64; depth++) {
        if ([visited containsObject:current]) break;
        [visited addObject:current];
        UIViewController *next = nil;
        if (current.presentedViewController && !current.presentedViewController.isBeingDismissed) next = current.presentedViewController;
        else if ([current isKindOfClass:UINavigationController.class]) next = ((UINavigationController *)current).visibleViewController;
        else if ([current isKindOfClass:UITabBarController.class]) next = ((UITabBarController *)current).selectedViewController;
        if (!next || next == current) break;
        current = next;
    }
    return current;
}
