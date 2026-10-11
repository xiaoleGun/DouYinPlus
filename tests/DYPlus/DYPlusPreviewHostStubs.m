#import <UIKit/UIKit.h>
#import "Services/Media/DYPlusManager.h"
#import "Core/Utilities/DYPlusUtils.h"
#import "UI/Components/DYPlusBottomAlertView.h"
#import "UI/Components/DYPlusFilterSettingsView.h"
#import "Diagnostics/DYPlusSelfTest.h"
#import "Integration/System/DYPlusABTestHook.h"
#import "Core/Utilities/DYPlusUtilsPrivate.h"
BOOL abTestBlockEnabled, abTestPatchEnabled, gDataLoaded, gFileExists, gABTestDataFixed;
NSDictionary *gFixedABTestData;
void ensureABTestDataLoaded(void) {}
void DYPlusInvalidateABTestData(void) {}
NSDictionary *getCurrentABTestData(void) { return @{}; }
void checkForRemoteConfigUpdate(BOOL notify) {}
NSDictionary *loadFixedABTestData(void) { return @{}; }
@implementation DYPlusManager
+ (void)showToast:(NSString *)text { NSLog(@"%@",text); }
+ (BOOL)isDarkMode { return [DYPlusUtils isDarkMode]; }
+ (UIWindow *)getActiveWindow {
    for(UIWindowScene *scene in UIApplication.sharedApplication.connectedScenes)for(UIWindow *w in scene.windows)if(w.isKeyWindow)return w;return nil;
}
+ (UIViewController *)getActiveTopController { return [self getActiveWindow].rootViewController; }
+ (UIColor *)colorWithHexString:(NSString *)hex { return UIColor.systemBlueColor; }
@end
@implementation DYPlusBottomAlertView
@end
@implementation DYPlusFilterSettingsView
@end
@implementation DYPlusSelfTest
+ (void)presentFromViewController:(UIViewController *)controller { }
@end
