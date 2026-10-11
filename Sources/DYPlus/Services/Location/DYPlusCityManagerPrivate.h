#import "Services/Location/DYPlusCityManager.h"

@interface DYPlusCityManager ()
@property (nonatomic, strong) NSDictionary<NSString *, NSString *> *provincesDict;
@property (nonatomic, strong) NSDictionary<NSString *, NSString *> *citiesDict;
@property (nonatomic, strong) NSDictionary<NSString *, NSDictionary<NSString *, NSString *> *> *allDistrictsDict;
@property (nonatomic, strong) NSDictionary<NSString *, NSArray<NSString *> *> *allStreetsDict;
- (void)loadGeoData;
@end
