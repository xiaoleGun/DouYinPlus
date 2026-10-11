//
//  DYPlusLongPressPanelSupport.m
//  DYYY
//
//  长按面板辅助 category 实现（UIView 快照）。
//

#import "Integration/Menus/DYPlusLongPressPanelSupport.h"

@implementation UIView (DYPlusSnapshot)
- (UIImage *)dyplus_snapshotImage {
    UIGraphicsBeginImageContextWithOptions(self.bounds.size, NO, [UIScreen mainScreen].scale);
    [self.layer renderInContext:UIGraphicsGetCurrentContext()];
    UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return image;
}
@end
