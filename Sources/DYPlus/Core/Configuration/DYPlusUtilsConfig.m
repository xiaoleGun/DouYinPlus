//
//  DYPlusUtilsConfig.m
//  DYYY
//
//  缓存失效、历史特性键迁移、玻璃功能门控。
//  玻璃门控键常量也定义在本文件（DYYYGlassGatedKeySet 依赖它们）。
//

#import "Core/Utilities/DYPlusUtils.h"
#import "Core/Utilities/DYPlusUtilsPrivate.h"
#import "Settings/DYPlusSettingsPreferences.h"

NSString * const DYPlusKeyCommentHideBottomBar = @"DYYYHideCommentBottomBar";
NSString * const DYPlusKeyCommentMediaCleanBottomBar = @"DYYYCommentMediaCleanBottomBar";
NSString * const DYPlusKeyCommentGlass = @"DYYYCommentGlass";
NSString * const DYPlusKeyCommentGlassClear = @"DYYYCommentGlassClear";
NSString * const DYPlusKeySharePanelGlass = @"DYYYSharePanelGlass";
NSString * const DYPlusKeySharePanelGlassClear = @"DYYYSharePanelGlassClear";
NSString * const DYPlusKeyInnerNotiGlass = @"DYYYInnerNotiGlass";
NSString * const DYPlusKeyInnerNotiGlassClear = @"DYYYInnerNotiGlassClear";
NSString * const DYPlusKeyInnerNotiCorner = @"DYYYInnerNotiCorner";
NSString * const DYPlusKeyGlassTabBar = @"DYYYGlassTabBar";
NSString * const DYPlusKeyGlassTabBarClear = @"DYYYGlassTabBarClear";
NSString * const DYPlusKeyAudioVizPosition = @"DYYYAudioVizPosition";
NSString * const DYPlusKeyAudioVizStyle = @"DYYYAudioVizStyle";
NSString * const DYPlusKeyDetailHideBottomBar = @"DYYYDetailHideBottomBar";

NSSet<NSString *> *DYPlusGlassGatedKeySet(void) {
    static NSSet<NSString *> *set;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        set = [NSSet setWithObjects:
               DYPlusKeyCommentGlass,
               DYPlusKeyCommentGlassClear,
               DYPlusKeySharePanelGlass,
               DYPlusKeySharePanelGlassClear,
               DYPlusKeyInnerNotiGlass,
               DYPlusKeyInnerNotiGlassClear,
               DYPlusKeyInnerNotiCorner,
               DYPlusKeyGlassTabBar,
               DYPlusKeyGlassTabBarClear,
               DYPlusKeyAudioVizPosition,
               DYPlusKeyAudioVizStyle,
               nil];
    });
    return set;
}

BOOL DYPlusGlassOSAvailable(void) {
    static BOOL available;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        if (@available(iOS 26.0, *)) {
            available = YES;
        } else {
            available = NO;
        }
    });
    return available;
}

BOOL DYPlusGlassIsGatedKey(NSString *key) {
    return key.length && [DYPlusGlassGatedKeySet() containsObject:key];
}

BOOL DYPlusPrefBool(NSString *key) {
    if (DYPlusGlassIsGatedKey(key) && !DYPlusGlassOSAvailable()) return NO;
    return DYPlusCachedBool(key);
}

NSInteger DYPlusPrefInteger(NSString *key) {
    if (DYPlusGlassIsGatedKey(key) && !DYPlusGlassOSAvailable()) return 0;
    return DYPlusCachedInteger(key);
}

void DYPlusConfigCacheInvalidate(void) {
    @synchronized (DYPlusConfigCache()) {
        [DYPlusConfigCache() removeAllObjects];
    }
    // 关键词预编译缓存与配置缓存联动失效
    @synchronized (DYPlusKeywordListCache()) {
        [DYPlusKeywordListCache() removeAllObjects];
    }
}

static void DYPlusMigrateLegacyFeatureKeys(void) {
    NSDictionary<NSString *, NSString *> *mapping = @{
        @"DYKillerCommentGlass": DYPlusKeyCommentGlass,
        @"DYKillerCommentGlassClear": DYPlusKeyCommentGlassClear,
        @"DYKillerHideCommentBottomBar": DYPlusKeyCommentHideBottomBar,
        @"DYKillerCommentMediaCleanBottomBar": DYPlusKeyCommentMediaCleanBottomBar,
        @"DYKillerSharePanelGlass": DYPlusKeySharePanelGlass,
        @"DYKillerSharePanelGlassClear": DYPlusKeySharePanelGlassClear,
        @"DYKillerInnerNotiGlass": DYPlusKeyInnerNotiGlass,
        @"DYKillerInnerNotiGlassClear": DYPlusKeyInnerNotiGlassClear,
        @"DYKillerInnerNotiCorner": DYPlusKeyInnerNotiCorner,
        @"DYKillerGlassTabBar": DYPlusKeyGlassTabBar,
        @"DYKillerGlassTabBarClear": DYPlusKeyGlassTabBarClear,
        @"DYKillerAudioVizPosition": DYPlusKeyAudioVizPosition,
        @"DYKillerAudioVizStyle": DYPlusKeyAudioVizStyle,
        @"DYKillerHideChatVideoBottomBar": DYPlusKeyDetailHideBottomBar,
    };

    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    for (NSString *oldKey in mapping) {
        id value = [defaults objectForKey:oldKey];
        if (!value) continue;
        NSString *newKey = mapping[oldKey];
        if (![defaults objectForKey:newKey]) {
            [defaults setObject:value forKey:newKey];
        }
        [defaults removeObjectForKey:oldKey];
    }
    [defaults synchronize];
}

__attribute__((constructor))
static void DYPlusFeatureSupportCtor(void) {
    DYPlusMigrateLegacyFeatureKeys();
    [DYPlusSettingsPreferences migrateLegacyOptions];
}
