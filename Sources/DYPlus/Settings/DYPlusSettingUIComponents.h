#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface DYPlusSliderRelay : NSObject
@property (nonatomic, copy) void (^block)(UISlider *slider);
- (void)changed:(UISlider *)sender;
@end

@interface DYPlusSliderViewController : UIViewController
- (instancetype)initWithTitle:(NSString *)title
                        value:(NSInteger)value
                   completion:(void (^)(NSInteger value))completion;
@end

NS_ASSUME_NONNULL_END
