//
//  DYPlusLongPressPanelSupport.h
//  DYYY
//
//  长按面板拆分后的共享声明：辅助 category 与快照方法。
//  实现见 DYYYLongPressPanelSupport.m，hook 见 DYYYLongPressPanelHooks.xm /
//  DYYYLongPressPanelCellHooks.xm。
//

#import <UIKit/UIKit.h>
#import "Integration/Headers/DYPlusAwemeHeaders.h"
#import "UI/Components/DYPlusCustomInputView.h"

NS_ASSUME_NONNULL_BEGIN

@class DYPlusBottomAlertView;
@class DYPlusToast;

// 自定义分类声明
@interface AWELongPressPanelViewGroupModel (DYPlus)
@property (nonatomic, assign) BOOL isDYPlusCustomGroup;
@end

@interface AWEModernLongPressPanelTableViewController (DYYY_FLEX)
- (void)fixFLEXMenu:(AWEAwemeModel *)awemeModel;
- (NSArray *)applyOriginalArrayFilters:(NSArray *)originalArray;
- (NSArray<NSNumber *> *)calculateButtonDistribution:(NSInteger)totalButtons;
- (AWELongPressPanelViewGroupModel *)createCustomGroup:(NSArray<AWELongPressPanelBaseViewModel *> *)buttons;
@end

@interface AWEModernLongPressPanelTableViewController (DYPlusBackgroundColorView)
@property (nonatomic, strong) UIView *dyplus_backgroundColorView;
@end

// AWEPlayInteractionViewController的方法声明
@interface AWEPlayInteractionViewController (DYPlusExtension)
- (NSString *)dyplus_getAwemeId:(AWEAwemeModel *)model;
- (void)setAwemeModel:(AWEAwemeModel *)awemeModel;
- (void)dyplus_forceRefreshPlayer:(AWEAwemeModel *)awemeModel;
- (UIView *)dyplus_findPlayerView:(UIView *)view;
- (void)dyplus_handleForceRefreshPlayer:(NSNotification *)notification;
- (void)dyplus_switchToAwemeModel:(NSNotification *)notification;
- (BOOL)dyplus_isSameAwemeModel:(AWEAwemeModel *)model1 target:(AWEAwemeModel *)model2;
- (void)dyplus_refreshPlayerWithAwemeModel:(AWEAwemeModel *)awemeModel;
- (void)dyplus_tryRefreshPlayerView:(AWEAwemeModel *)awemeModel;
@end

@interface UIView (DYPlusSnapshot)
- (UIImage *)dyplus_snapshotImage;
@end

NS_ASSUME_NONNULL_END
