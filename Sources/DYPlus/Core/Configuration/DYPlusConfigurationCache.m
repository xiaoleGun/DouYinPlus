#import "Core/Utilities/DYPlusUtils.h"
#import <math.h>

#pragma mark - 配置内存缓存

NSMutableDictionary *DYPlusConfigCache(void) {
    static NSMutableDictionary *cache = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        cache = [NSMutableDictionary dictionary];
    });
    return cache;
}

typedef NS_ENUM(NSUInteger, DYPlusConfigKind) { DYPlusConfigBool, DYPlusConfigInteger, DYPlusConfigFloat, DYPlusConfigString };

static id DYPlusCachedConfigValue(NSString *key, DYPlusConfigKind kind) {
    if (key.length == 0) return nil;
    static NSString *const prefixes[] = { @"B:", @"I:", @"F:", @"S:" };
    NSMutableDictionary *cache = DYPlusConfigCache();
    NSString *cacheKey = [prefixes[kind] stringByAppendingString:key];
    // miss 的读取与写入同属一轮锁，避免失效后被并发的旧值重新填回。
    @synchronized (cache) {
        id value = cache[cacheKey];
        if (value) return value;
        id raw = [NSUserDefaults.standardUserDefaults objectForKey:key];
        BOOL numeric = [raw isKindOfClass:NSNumber.class] || [raw isKindOfClass:NSString.class];
        switch (kind) {
            case DYPlusConfigBool: value = @(numeric ? [raw boolValue] : NO); break;
            case DYPlusConfigInteger: value = @(numeric ? [raw integerValue] : 0); break;
            case DYPlusConfigFloat: {
                double number = numeric ? [raw doubleValue] : 0.0;
                value = @(isfinite(number) ? number : 0.0);
                break;
            }
            case DYPlusConfigString: value = [raw isKindOfClass:NSString.class] ? raw : @""; break;
        }
        cache[cacheKey] = value;
        return value;
    }
}

BOOL DYPlusCachedBool(NSString *key) { return [DYPlusCachedConfigValue(key, DYPlusConfigBool) boolValue]; }
NSInteger DYPlusCachedInteger(NSString *key) { return [DYPlusCachedConfigValue(key, DYPlusConfigInteger) integerValue]; }
CGFloat DYPlusCachedFloat(NSString *key) { return [DYPlusCachedConfigValue(key, DYPlusConfigFloat) doubleValue]; }
NSString *DYPlusCachedString(NSString *key) { return DYPlusCachedConfigValue(key, DYPlusConfigString) ?: @""; }

// 关键词列表预编译缓存（逗号分隔配置 → trim 后的字符串数组）
NSMutableDictionary *DYPlusKeywordListCache(void) {
    static NSMutableDictionary *cache = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        cache = [NSMutableDictionary dictionary];
    });
    return cache;
}

NSArray<NSString *> *DYPlusCachedKeywordList(NSString *configKey) {
    if (configKey.length == 0) return @[];
    NSMutableDictionary *cache = DYPlusKeywordListCache();
    @synchronized (cache) {
        NSArray *cached = cache[configKey];
        if (cached) return cached;
        NSString *raw = DYPlusCachedString(configKey);
        NSMutableArray *result = [NSMutableArray array];
        for (NSString *part in [raw componentsSeparatedByString:@","]) {
            NSString *trimmed = [part stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
            if (trimmed.length) [result addObject:trimmed];
        }
        NSArray *immutable = [result copy];
        cache[configKey] = immutable;
        return immutable;
    }
}
