#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <CoreLocation/CoreLocation.h>

#import "Core/Utilities/DYPlusUtils.h"
#import "Core/Storage/DYPlusPaths.h"
#import "Core/UI/DYPlusTheme.h"
#import "Core/UI/DYPlusGlass.h"

#define DYPlusBottomAlertView_DEFINED
#define DYPlusToast_DEFINED
#define DYPlusFilterSettingsView_DEFINED
#define DYPlusUtils_DEFINED
#define DYPlusConfirmCloseView_DEFINED
#define DYPlusKeywordListView_DEFINED
#define DYPlusCustomInputView_DEFINED

#import "Integration/Headers/DYPlusAwemeHeaders.h"
#import "Services/Location/DYPlusCityManager.h"
#import "Services/Media/DYPlusManager.h"
#import "Settings/DYPlusSettingViewController.h"
#import "UI/Components/DYPlusToast.h"
#import "UI/Components/DYPlusBottomAlertView.h"
#import "UI/Components/DYPlusConfirmCloseView.h"
#import "Integration/Playback/DYPlusFloatSpeedButton.h"

extern void updateSpeedButtonVisibility(void);
extern void updateClearButtonVisibility(void);
extern void reloadClearButtonConfiguration(void);

@interface AWEPlayInteractionElementMaskView : UIView
@end

@interface AWEGradientView : UIView
@end

@interface AWEHotSearchInnerBottomView : UIView
@end

@interface AWEHotSpotBlurView : UIView
@end

@interface AWECodeGenCommonAnchorBasicInfoModel : NSObject
@property (nonatomic, copy) NSString *name;
@end

@interface AWEProfileMixItemCollectionViewCell : UIView
@property (nonatomic, copy) NSString *accessibilityLabel;
@end

@interface AWEFeedPauseRelatedWordComponent : NSObject
@property (nonatomic, strong) UIView *relatedView;
- (id)updateViewWithModel:(id)arg0;
- (id)pauseContentWithModel:(id)arg0;
- (id)recommendsWords;
- (void)showRelatedRecommendPanelControllerWithSelectedText:(id)arg0;
- (void)setupUI;
@end

@interface AWEPlayInteractionUserAvatarView : UIView
@end

@interface AWELiveAutoEnterStyleAView : UIView
@end

@interface DYPlusCityManager (DYPlusExt)
- (NSString *)generateRandomFourLevelAddressForCityCode:(NSString *)cityCode;
@end

#define DYPlusMediaTypeVideo MediaTypeVideo
#define DYPlusMediaTypeImage MediaTypeImage
#define DYPlusMediaTypeAudio MediaTypeAudio
#define DYPlusMediaTypeHeic MediaTypeHeic

@interface AWEIMReusableCommonCell : UIView
@property (nonatomic, strong) id currentContext;
@end

@interface AWEIMMessageComponentContext : NSObject
@property (nonatomic, strong) id message;
@end

@interface AWEIMGiphyMessage : NSObject
@property (nonatomic, strong) AWEURLModel *giphyURL;
@end

@interface AWEIMCustomMenuModel : NSObject
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy) NSString *imageName;
@property (nonatomic, copy) NSString *trackerName;
@property (nonatomic, copy) void (^willPerformMenuActionSelectorBlock)(id);
@end

@interface AWEPlayInteractionSpeedController : NSObject
- (id)playVideoViewController;
- (void)changeSpeed:(double)speed;
@end

@interface AWEPlayInteractionViewController (DYPlusSpeedAccess)
@property(nonatomic, strong) AWEAwemeModel *model;
- (id)awemeModel;
- (void)onPlayer:(id)arg0 didDoubleClick:(id)arg1;
- (id)controllerByProtocol:(Protocol *)protocol;
- (id)videoDelegate;
@end
