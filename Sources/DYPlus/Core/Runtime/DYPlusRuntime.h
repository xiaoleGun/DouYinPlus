#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN
#ifdef __cplusplus
extern "C" {
#endif
BOOL DYPlusReadBooleanSelector(id _Nullable object, SEL selector, BOOL * _Nullable value);
NSString * _Nullable DYPlusPreferenceString(NSString *key);
id _Nullable DYPlusUnarchiveObject(NSData * _Nullable data, NSSet<Class> *classes);
UIColor * _Nullable DYPlusUnarchiveColor(NSData * _Nullable data);
NSMutableDictionary<NSString *, NSNumber *> *DYPlusUnarchiveUsageStats(NSData * _Nullable data);
#ifdef __cplusplus
}
#endif
NS_ASSUME_NONNULL_END
