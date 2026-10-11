//
//  DYPlusAutoPlayHooks.xm
//  DYYY
//
//  详情页自动播放开关 hook（拆分自 DYYY.xm）。
//

#import "Integration/Common/DYPlusMainHooksShared.h"

%group AutoPlay

%hook AWEAwemeDetailTableViewController
- (BOOL)hasIphoneAutoPlaySwitch {
    // 检查是否启用自动播放功能
    BOOL enabled = DYPlusCachedBool(@"DYYYisEnableAutoPlay");
    if (!enabled) {
        return %orig; // 未启用时保持原来的行为
    }
    return YES; // 启用时强制返回YES
}
%end




%end

%ctor {
    // 始终初始化AutoPlay组
    %init(AutoPlay);
}
