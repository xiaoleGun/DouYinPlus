#import "Settings/DYPlusSettingItem.h"

@implementation DYPlusSettingItem

+ (instancetype)itemWithTitle:(NSString *)title key:(NSString *)key type:(NSInteger)type {
    return [self itemWithTitle:title key:key type:type placeholder:nil];
}

+ (instancetype)itemWithTitle:(NSString *)title key:(NSString *)key type:(NSInteger)type placeholder:(NSString *)placeholder {
    DYPlusSettingItem *item = [[DYPlusSettingItem alloc] init];
    item.title = title;
    item.key = key;
    item.type = type;
    item.placeholder = placeholder;
    return item;
}

+ (instancetype)itemWithTitle:(NSString *)title key:(NSString *)key type:(NSInteger)type options:(NSArray<NSString *> *)options {
    DYPlusSettingItem *item = [self itemWithTitle:title key:key type:type];
    item.options = options;
    return item;
}

+ (instancetype)itemWithTitle:(NSString *)title key:(NSString *)key type:(NSInteger)type defaultInteger:(NSInteger)defaultInteger {
    DYPlusSettingItem *item = [self itemWithTitle:title key:key type:type];
    item.defaultInteger = defaultInteger;
    return item;
}

+ (instancetype)itemWithGroupTitle:(NSString *)title {
    DYPlusSettingItem *item = [[DYPlusSettingItem alloc] init];
    item.title = title;
    item.key = nil;
    item.type = DYPlusSettingItemTypeGroupHeader;
    return item;
}

@end
