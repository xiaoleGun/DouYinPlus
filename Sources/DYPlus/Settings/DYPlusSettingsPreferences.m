#import "Settings/DYPlusSettingsPreferences.h"
#import "Core/Utilities/DYPlusUtils.h"

@implementation DYPlusSettingsPreferences

+ (NSDictionary<NSString *, NSArray<NSString *> *> *)choiceGroups {
    return @{
        @"DYYYDefaultQuality": @[@"DYYYDefaultQualityBest", @"DYYYDefaultQualityOriginal", @"DYYYDefaultQuality1080p", @"DYYYDefaultQuality720p"],
        @"DYYYClearButtonPreset": @[@"DYYYCustomAlbumSizeSmall", @"DYYYCustomAlbumSizeMedium", @"DYYYCustomAlbumSizeLarge"],
        @"DYYYDateTimeFormat": @[@"DYYYDateTimeFormat_YMDHM", @"DYYYDateTimeFormat_MDHM", @"DYYYDateTimeFormat_HMS", @"DYYYDateTimeFormat_HM", @"DYYYDateTimeFormat_YMD"]
    };
}

+ (void)migrateLegacyOptions {
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    NSDictionary *aliases = @{@"DYYYEnableCommentCopyText": @"DYYYCommentCopyText",
                              @"DYYYEnableNotificationTransparency": @"DYYYInnerNotiGlass",
                              @"DYYYtopbartransparent": @"DYYYTopBarTransparent"};
    for (NSString *oldKey in aliases) {
        NSString *key = aliases[oldKey];
        if (![defaults objectForKey:key] && [defaults objectForKey:oldKey]) {
            [defaults setObject:[defaults objectForKey:oldKey] forKey:key];
        }
        [defaults removeObjectForKey:oldKey];
    }
    DYPlusConfigCacheInvalidate();
}

+ (NSInteger)choiceValueForKey:(NSString *)key {
    if ([key isEqualToString:@"DYYYDefaultQuality"] && [NSUserDefaults.standardUserDefaults boolForKey:@"DYYYEnableVideoHighestQuality"]) return 0;
    NSArray *keys = [self choiceGroups][key];
    if (!keys) return [NSUserDefaults.standardUserDefaults integerForKey:key];
    for (NSUInteger i = 0; i < keys.count; i++) {
        if ([NSUserDefaults.standardUserDefaults boolForKey:keys[i]]) return (NSInteger)i;
    }
    return [key isEqualToString:@"DYYYClearButtonPreset"] ? 1 : 0;
}

+ (void)setChoiceValue:(NSInteger)value forKey:(NSString *)key {
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    NSArray *keys = [self choiceGroups][key];
    if (value < 0 || (keys && value >= (NSInteger)keys.count)) return;
    [defaults setInteger:value forKey:key];
    for (NSUInteger i = 0; i < keys.count; i++) [defaults setBool:i == (NSUInteger)value forKey:keys[i]];
    if ([key isEqualToString:@"DYYYDefaultQuality"]) {
        [defaults setBool:value == 0 forKey:@"DYYYEnableVideoHighestQuality"];
    }
    if ([key isEqualToString:@"DYYYDateTimeFormat"]) [defaults setBool:YES forKey:@"DYYYShowDateTime"];
    if ([key isEqualToString:@"DYYYClearButtonPreset"]) {
        [defaults removeObjectForKey:@"DYYYEnableFloatClearButtonSize"];
    }
    DYPlusConfigCacheInvalidate();
    for (NSString *changed in keys ?: @[key]) {
        [[NSNotificationCenter defaultCenter] postNotificationName:@"DYYYSettingChanged" object:nil
                                                         userInfo:@{@"key":changed, @"enabled":@([defaults boolForKey:changed])}];
    }
}

@end
