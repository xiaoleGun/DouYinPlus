#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import "Core/Utilities/DYPlusUtils.h"

// 仅保留显式开启的版本字符串兼容选项。不可伪造系统能力判断，
// 更不能让 isOperatingSystemAtLeastVersion: 对未来版本始终返回 YES。
%hook UIDevice
- (NSString *)systemVersion {
    if (@available(iOS 26.0, *)) {
        if (DYPlusCachedBool(@"DYYYSpoofLiquidGlass")) return @"26.0";
    }
    return %orig;
}
%end

