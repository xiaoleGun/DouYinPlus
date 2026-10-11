#import <UIKit/UIKit.h>
#ifdef __cplusplus
extern "C" {
#endif
// UI context must be queried on the main thread. Returned values are not cached.
UIWindow *DYPlusActiveWindow(void);
UIViewController *DYPlusVisibleViewController(UIViewController *root);
#ifdef __cplusplus
}
#endif
