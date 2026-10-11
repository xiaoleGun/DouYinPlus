#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

static inline UIColor *DYPlusSecondaryTextColor(void) {
    return [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *traits) {
        return traits.userInterfaceStyle == UIUserInterfaceStyleDark
            ? [UIColor colorWithRed:0.773 green:0.773 blue:0.800 alpha:1.0]
            : [UIColor colorWithRed:0.349 green:0.349 blue:0.388 alpha:1.0];
    }];
}

#define DYPlusProductName @"DouYinPlus"
#define DYPlusPackageIdentifier @"com.xiaolegun.douyinplus"
#define DYPlusAuthorName @"xiaoleGun"
#define DYPlusProductVersion @"0.1"
#define DYPlusRepositoryURL @"https://github.com/xiaoleGun/DouYinPlus"
