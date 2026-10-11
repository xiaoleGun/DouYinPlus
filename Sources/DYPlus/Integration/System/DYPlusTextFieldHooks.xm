#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import "Services/Media/DYPlusManager.h"
#import "Core/Utilities/DYPlusUtils.h"
#import "Integration/Headers/DYPlusAwemeHeaders.h"
#import "Core/UI/DYPlusTheme.h"

// ===== 键盘外观适配 =====
%hook UITextField

- (void)willMoveToWindow:(UIWindow *)newWindow {
	%orig;
	if (newWindow) {
		// 根据当前是否为深色模式来设置键盘样式
		BOOL darkModeEnabled = DYPlusThemeIsDark();
		self.keyboardAppearance = darkModeEnabled ? UIKeyboardAppearanceDark : UIKeyboardAppearanceLight;
	}
}

- (BOOL)becomeFirstResponder {
	// 当输入框获取焦点时设置键盘样式
	BOOL darkModeEnabled = DYPlusThemeIsDark();
	self.keyboardAppearance = darkModeEnabled ? UIKeyboardAppearanceDark : UIKeyboardAppearanceLight;
	return %orig;
}

%end
