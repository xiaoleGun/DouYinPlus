#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class DYPlusSettingItem;

@interface DYPlusSettingSectionProvider : NSObject

+ (NSArray<NSArray<DYPlusSettingItem *> *> *)defaultSections;

@end

NS_ASSUME_NONNULL_END
