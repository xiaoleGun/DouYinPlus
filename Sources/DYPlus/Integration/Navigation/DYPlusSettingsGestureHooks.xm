//
//  DYPlusSettingsGestureHooks.xm
//  DYYY
//
//  设置页双指长按手势 hook（拆分自 DYYY.xm）。
//

#import "Integration/Common/DYPlusMainHooksShared.h"
#import "Settings/DYPlusSettingsNavigation.h"

%group DYPlusSettingsGesture
%hook UIWindow
- (instancetype)initWithFrame:(CGRect)frame {
	UIWindow *window = %orig(frame);
	if (window) {
		UILongPressGestureRecognizer *doubleFingerLongPressGesture = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(handleDoubleFingerLongPressGesture:)];
		doubleFingerLongPressGesture.numberOfTouchesRequired = 2;
		[window addGestureRecognizer:doubleFingerLongPressGesture];
	}
	return window;
}

%new
- (void)handleDoubleFingerLongPressGesture:(UILongPressGestureRecognizer *)gesture {
    if (gesture.state == UIGestureRecognizerStateBegan) DYPlusPresentSettings([DYPlusManager getActiveTopController]);
}

%new
- (void)closeSettings:(UIButton *)button {
	[button.superview.window.rootViewController dismissViewControllerAnimated:YES completion:nil];
}


%end

%end

%ctor {
    // DYYYSettingsGesture 组的初始化
    %init(DYPlusSettingsGesture);
}
