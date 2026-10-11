//
//  DYPlusMainHooksShared.h
//  DYYY
//
//  DYYY.xm 拆分后跨 hook 文件共享的声明：倍速、tab 高度、评论可见状态等
//  全局变量与 C 函数。定义位于 DYYYMainSupport.m。
//

#import "Integration/Common/DYPlusHookShared.h"

NS_ASSUME_NONNULL_BEGIN

// —— 全局变量（定义于 DYYYMainSupport.m）——
extern CGFloat tabHeight;
extern CGFloat originalTabHeight;
// 当前页面实际可见的底栏高度；推入隐藏底栏的页面、离屏或未挂载时为 0。
CGFloat DYPlusVisibleTabBarHeightForView(UIView *view);
extern BOOL dyplusCommentViewVisible;
extern BOOL dyplusCurrentLandscapeVideo;
extern __weak AWEPlayInteractionViewController *dyplusCurrentFullScreenInteractionVC;
extern __weak AWEAwemeModel *dyplusCurrentSpeedAweme;
extern BOOL dyplusLongPressFastSpeedActive;
extern BOOL dyplusLongPressLockedSpeedActive;

// —— 倍速相关函数 ——
BOOL DYPlusShouldHandleSpeedFeatures(void);
void DYPlusClearLongPressSpeedState(void);
void DYPlusRestoreFloatSpeedButtonForAwemeIfNeeded(AWEAwemeModel *aweme);
id DYPlusCurrentSpeedInteractionController(void);
void DYPlusEnsureFloatSpeedButton(AWEPlayInteractionViewController *interactionController);
void DYPlusRefreshFloatSpeedButton(void);
BOOL DYPlusApplyPlaybackSpeed(AWEPlayInteractionViewController *interactionController, double speed);
double DYPlusConfiguredPlaybackSpeed(void);
double DYPlusPreparedPlaybackSpeedForPlayer(id playerViewController);
void DYPlusApplyPreparedPlaybackSpeedToPlayer(id playerViewController);
void DYPlusScheduleConfiguredPlaybackSpeedRestore(void);
void DYPlusEndLockedLongPressSpeedAndRestoreIfNeeded(void);

// —— 全屏/评论可见状态 ——
BOOL DYPlusFullScreenCommentOriginalLayoutActive(void);
BOOL DYPlusLegacyCommentBlurActive(void);

NS_ASSUME_NONNULL_END
