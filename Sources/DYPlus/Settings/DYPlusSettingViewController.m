//
//  DYPlusSettingViewController.m
//  DYYY
//
//  设置页主文件：保留类扩展入口（isExiting 属性合成）、公共 C 函数与空 category 声明。
//  生命周期/外观/头像/搜索栏/table 搭建 → DYYYSettingViewControllerAppearance.m
//  清理/备份恢复/ABTest 配置 → DYYYSettingViewControllerBackup.m
//  data source/delegate/搜索过滤/图标颜色 → DYYYSettingViewControllerTable.m
//  颜色/样式选择/源码弹窗/长按和重置 → DYYYSettingViewControllerPresentation.m
//

#import "Settings/DYPlusSettingViewController.h"
#import "Settings/DYPlusSettingViewControllerPrivate.h"
#import "Integration/Headers/DYPlusAwemeHeaders.h"
#import "Core/UI/DYPlusUIContext.h"

void DYPlusPresentSettings(UIViewController *presenter) {
    if (!presenter || presenter.presentedViewController) return;
    UIViewController *root = presenter.navigationController.viewControllers.firstObject;
    if ([presenter isKindOfClass:DYPlusSettingViewController.class] || [root isKindOfClass:DYPlusSettingViewController.class]) return;
    UINavigationController *navigation = [[UINavigationController alloc]
        initWithRootViewController:[DYPlusSettingViewController new]];
    navigation.modalPresentationStyle = UIModalPresentationPageSheet;
    if (@available(iOS 15.0, *)) {
        navigation.sheetPresentationController.detents = @[UISheetPresentationControllerDetent.largeDetent];
        navigation.sheetPresentationController.prefersGrabberVisible = YES;
    }
    [presenter presentViewController:navigation animated:YES completion:nil];
}

// 获取顶层视图控制器
UIViewController *topView(void) { return DYPlusVisibleViewController(DYPlusActiveWindow().rootViewController); }

#ifndef AWESettingBaseViewController_DEFINED
#define AWESettingBaseViewController_DEFINED
@interface AWESettingBaseViewController (DYPlus_Addition)
@end
#endif

@implementation DYPlusSettingViewController
// 方法实现按功能域分布在 +Appearance/+Backup/+Table/+Presentation 各 category 中。
// 保留本实现体以完成 isExiting 属性的自动合成。
@end
