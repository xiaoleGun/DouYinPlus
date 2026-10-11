//
//  DYPlusSocialStatsShared.h
//  DYYY
//
//  社交/视频统计拆分后的共享声明：配置键宏、跨文件 C 函数与全局变量、
//  私有类接口。对外入口（showVideoStatsEditAlert）同时声明在 AwemeHeaders.h。
//

#import <UIKit/UIKit.h>
#import "Integration/Headers/DYPlusAwemeHeaders.h"

NS_ASSUME_NONNULL_BEGIN

#pragma mark - 配置键

#define DYPLUS_VIDEO_SPECIFIC_STATS_KEY @"DYYYVideoSpecificStats"
#define DYPLUS_SOCIAL_STATS_ENABLED_KEY @"DYYYEnableSocialStatsCustom"
#define DYPLUS_SOCIAL_FOLLOWERS_KEY @"DYYYCustomFollowers"
#define DYPLUS_SOCIAL_LIKES_KEY @"DYYYCustomLikes"
#define DYPLUS_SOCIAL_FOLLOWING_KEY @"DYYYCustomFollowing"
#define DYPLUS_SOCIAL_MUTUAL_KEY @"DYYYCustomMutual"
#define DYPLUS_VIDEO_STATS_ENABLED_KEY @"DYYYEnableVideoStatsCustom"
#define DYPLUS_VIDEO_LIKES_KEY @"DYYYVideoCustomLikes"
#define DYPLUS_VIDEO_COMMENTS_KEY @"DYYYVideoCustomComments"
#define DYPLUS_VIDEO_COLLECTS_KEY @"DYYYVideoCustomCollects"
#define DYPLUS_VIDEO_SHARES_KEY @"DYYYVideoCustomShares"
#define DYPLUS_VIDEO_RECOMMENDS_KEY @"DYYYVideoCustomRecommends"

#pragma mark - 私有类接口

@interface AWEProfileSocialStatisticView : UIView
- (void)setFansCount:(NSNumber *)count;
- (void)setPraiseCount:(NSNumber *)count;
- (void)setFollowingCount:(NSNumber *)count;
- (void)setFriendCount:(NSNumber *)count;
- (void)p_updateSocialStatisticContent:(BOOL)animated;
@end

@interface AWEProfileHeaderMyProfileViewController : UIViewController
- (void)reloadSettings;
@end

@interface AWEFeedTableCell : UIView
- (void)setNeedsLayout;
- (void)layoutIfNeeded;
@end

@interface AWEAwemeDetailController : UIViewController
@end

@interface DYPlusVideoEditViewController : UIViewController <UITextFieldDelegate, UIGestureRecognizerDelegate>
@property (nonatomic, strong, nullable) NSString *videoId;
@property (nonatomic, strong, nullable) NSDictionary *existingStats;
@property (nonatomic, strong) NSMutableDictionary *currentValues;
@end

#pragma mark - 跨文件 C 函数

// 特定视频统计数据（DYYYVideoStatsHooks.xm 定义）
void ensureVideoSpecificStatsInitialized(void);
id getCustomStatForVideo(NSString *videoId, NSString *statKey);

// 设置同步与刷新（DYYYVideoStatsHooks.xm 定义）
void syncVideoStatsFromSettings(void);
void refreshAwemeStatisticsModels(void);

// 社交/视频统计设置加载（DYYYSocialStatsHooks.xm 定义；编辑器保存后调用）
void loadCustomSocialStats(void);

// 菜单与列表（DYYYVideoStatsMenu.m 定义）
void showVideoStatsContextMenu(UIViewController *viewController);
void showVideoStatsListController(UIViewController *parentVC);
void showVideoStatsEditAlert(UIViewController *viewController);

#pragma mark - 跨文件全局变量

// DYYYVideoStatsHooks.xm 定义；DYYYSocialStatsHooks.xm 的 loadCustomSocialStats 与 %ctor 访问。
extern BOOL videoStatsEnabled;
extern NSString *customVideoRecommends;
extern NSString *customVideoLikes;
extern NSString *customVideoComments;
extern NSString *customVideoCollects;
extern NSString *customVideoShares;
extern NSNumber *cachedVideoRecommendsNumber;
extern NSNumber *cachedVideoLikesNumber;
extern NSNumber *cachedVideoCommentsNumber;
extern NSNumber *cachedVideoCollectsNumber;
extern NSNumber *cachedVideoSharesNumber;
extern NSMutableDictionary *videoSpecificStats;
extern dispatch_once_t videoSpecificStatsOnceToken;

NS_ASSUME_NONNULL_END
