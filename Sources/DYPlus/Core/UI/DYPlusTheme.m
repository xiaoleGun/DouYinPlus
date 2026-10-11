#import "Core/UI/DYPlusTheme.h"
#import <objc/message.h>

BOOL DYPlusThemeIsDark(void) {
    Class themeManagerClass = NSClassFromString(@"AWEUIThemeManager");
    if (themeManagerClass) {
        SEL isLightSelector = sel_registerName("isLightTheme");
        if ([themeManagerClass respondsToSelector:isLightSelector]) {
            BOOL (*isLightFn)(id, SEL) = (BOOL (*)(id, SEL))objc_msgSend;
            return !isLightFn(themeManagerClass, isLightSelector);
        }
    }

    if (@available(iOS 13.0, *)) {
        UIUserInterfaceStyle style = UIScreen.mainScreen.traitCollection.userInterfaceStyle;
        if (style == UIUserInterfaceStyleUnspecified) {
            style = UITraitCollection.currentTraitCollection.userInterfaceStyle;
        }
        return style == UIUserInterfaceStyleDark;
    }
    return NO;
}

UIColor *DYPlusThemeBackgroundColor(void) {
    return [UIColor colorWithWhite:0.0 alpha:0.2];
}

UIColor *DYPlusThemeSurfaceColor(void) {
    if (DYPlusThemeIsDark()) {
        return [UIColor colorWithRed:30.0 / 255.0
                               green:30.0 / 255.0
                                blue:30.0 / 255.0
                               alpha:1.0];
    }
    return UIColor.whiteColor;
}

UIColor *DYPlusThemePrimaryTextColor(void) {
    if (DYPlusThemeIsDark()) {
        return [UIColor colorWithRed:230.0 / 255.0
                               green:230.0 / 255.0
                                blue:235.0 / 255.0
                               alpha:1.0];
    }
    return [UIColor colorWithRed:45.0 / 255.0
                           green:47.0 / 255.0
                            blue:56.0 / 255.0
                           alpha:1.0];
}

UIColor *DYPlusThemeSecondaryTextColor(void) {
    if (DYPlusThemeIsDark()) {
        return [UIColor colorWithRed:160.0 / 255.0
                               green:160.0 / 255.0
                                blue:165.0 / 255.0
                               alpha:1.0];
    }
    return [UIColor colorWithRed:124.0 / 255.0
                           green:124.0 / 255.0
                            blue:130.0 / 255.0
                           alpha:1.0];
}

UIColor *DYPlusThemeSeparatorColor(void) {
    if (DYPlusThemeIsDark()) {
        return [UIColor colorWithRed:60.0 / 255.0
                               green:60.0 / 255.0
                                blue:60.0 / 255.0
                               alpha:1.0];
    }
    return [UIColor colorWithRed:230.0 / 255.0
                           green:230.0 / 255.0
                            blue:230.0 / 255.0
                           alpha:1.0];
}

UIColor *DYPlusThemeAccentColor(void) {
    return [UIColor colorWithRed:11.0 / 255.0
                           green:223.0 / 255.0
                            blue:154.0 / 255.0
                           alpha:1.0];
}

UIBlurEffectStyle DYPlusThemeBlurStyle(void) {
    return DYPlusThemeIsDark() ? UIBlurEffectStyleDark : UIBlurEffectStyleLight;
}

CGFloat DYPlusThemeBlurAlpha(void) {
    return DYPlusThemeIsDark() ? 0.3 : 0.2;
}
