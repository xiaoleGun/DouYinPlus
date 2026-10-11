#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN
@interface DYPlusSettingsArchive : NSObject
@property(nonatomic, copy, readonly) NSDictionary<NSString *, id> *preferences;
@property(nonatomic, copy, readonly) NSDictionary<NSString *, NSData *> *icons;
+ (nullable NSData *)readFileURL:(NSURL *)url error:(NSError **)error;
+ (nullable instancetype)decodeData:(NSData *)data error:(NSError **)error;
+ (nullable NSData *)encodePreferences:(NSDictionary *)preferences icons:(NSDictionary<NSString *, NSData *> *)icons error:(NSError **)error;
- (BOOL)applyToDefaults:(NSUserDefaults *)defaults iconsDirectory:(NSString *)directory error:(NSError **)error;
+ (NSArray<NSString *> *)allowedIconNames;
@end
NS_ASSUME_NONNULL_END
