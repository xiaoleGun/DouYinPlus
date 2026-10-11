#import "Services/Media/DYPlusManagerPrivate.h"
#import "Core/UI/DYPlusTheme.h"
#import "Core/UI/DYPlusColorParser.h"
#import "Core/UI/DYPlusUIContext.h"

@interface DYPlusManager (UI)
@end

@implementation DYPlusManager (UI)

+ (UIColor *)colorWithHexString:(NSString *)hexString {
    return DYPlusColorFromString(hexString);
}


+ (UIWindow *)getActiveWindow { return DYPlusActiveWindow(); }

+ (UIViewController *)getActiveTopController { return DYPlusVisibleViewController(DYPlusActiveWindow().rootViewController); }

+ (void)showToast:(NSString *)text {
    Class toastClass = NSClassFromString(@"DUXToast");
    if (toastClass && [toastClass respondsToSelector:@selector(showText:)]) {
        [toastClass performSelector:@selector(showText:) withObject:text];
    }
}

+ (BOOL)isDarkMode {
    return DYPlusThemeIsDark();
}

@end
