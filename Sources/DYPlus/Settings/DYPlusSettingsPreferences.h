#import <Foundation/Foundation.h>

@interface DYPlusSettingsPreferences : NSObject
+ (void)migrateLegacyOptions;
+ (NSInteger)choiceValueForKey:(NSString *)key;
+ (void)setChoiceValue:(NSInteger)value forKey:(NSString *)key;
@end
