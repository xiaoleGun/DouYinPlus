#import <UIKit/UIKit.h>
#import "Settings/DYPlusSettingViewController.h"
#import "Settings/DYPlusSettingViewControllerPrivate.h"
#import "Settings/DYPlusSettingSectionProvider.h"
#import "Settings/DYPlusSettingsPreferences.h"
#import "Settings/DYPlusAboutViewController.h"
void DYPlusRunCoreRegressionTests(void);
void DYPlusSeedCrashRetention(void);
void DYPlusVerifyCrashRetention(void);
void DYPlusRunRemoteHandlerRegression(void);

static NSUInteger uiChecks;
static void Check(NSString *name, BOOL passed) {
    uiChecks++;
    printf("%s: %s\n", name.UTF8String, passed ? "PASS" : "FAIL");fflush(stdout);if(!passed)exit(1);
}
@interface DYPlusPreviewScene : UIResponder <UIWindowSceneDelegate>
@property(nonatomic,strong) UIWindow *window;
@property(nonatomic,strong) UINavigationController *nav;
@property(nonatomic,strong) DYPlusSettingViewController *settings;
@end
@implementation DYPlusPreviewScene
- (void)scene:(UIScene *)scene willConnectToSession:(UISceneSession *)session options:(UISceneConnectionOptions *)options {
    self.window = [[UIWindow alloc] initWithWindowScene:(UIWindowScene *)scene];
    NSArray *args = NSProcessInfo.processInfo.arguments;
    self.window.overrideUserInterfaceStyle = [args containsObject:@"dark"] ? UIUserInterfaceStyleDark : UIUserInterfaceStyleLight;
    self.settings = [DYPlusSettingViewController new];
    self.nav = [[UINavigationController alloc] initWithRootViewController:self.settings];
    self.window.rootViewController = self.nav;
    [self.window makeKeyAndVisible];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC), dispatch_get_main_queue(), ^{ [self verify:args]; });
}
- (void)verify:(NSArray *)args {
    if ([args containsObject:@"seed-retention"]) { DYPlusSeedCrashRetention(); exit(0); }
    if ([args containsObject:@"verify-retention"]) { DYPlusVerifyCrashRetention(); exit(0); }
    [UIView setAnimationsEnabled:NO];
    NSArray *catalog = [DYPlusSettingSectionProvider defaultSections];
    NSMutableSet *keys = [NSMutableSet new];
    for(NSArray *section in catalog) for(DYPlusSettingItem *item in section) {
        if(!item.key)continue; Check([@"unique-" stringByAppendingString:item.key], ![keys containsObject:item.key]);[keys addObject:item.key];
    }
    Check(@"home-six-categories", [self.settings tableView:self.settings.tableView numberOfRowsInSection:0] == 6);
    Check(@"single-about-entry", [self.settings tableView:self.settings.tableView numberOfRowsInSection:1] == 1);
    Check(@"public-home-title-douyinplus", [self.settings.title isEqual:@"DouYinPlus"]);
    UIStackView *homeHeader = (UIStackView *)self.settings.tableView.tableHeaderView.subviews.firstObject;
    Check(@"home-header-search-only", homeHeader.arrangedSubviews.count == 1
        && homeHeader.arrangedSubviews.firstObject == self.settings.searchBar);
    DYPlusSettingViewController *categoryPreview = [DYPlusSettingViewController new];
    categoryPreview.categoryIndex = 0;
    categoryPreview.categoryTitle = @"播放";
    categoryPreview.isCategoryPage = YES;
    [categoryPreview loadViewIfNeeded];
    UIStackView *categoryHeader = (UIStackView *)categoryPreview.tableView.tableHeaderView.subviews.firstObject;
    Check(@"category-header-search-only", categoryHeader.arrangedSubviews.count == 1
        && categoryHeader.arrangedSubviews.firstObject == categoryPreview.searchBar);
    [self.nav setOverrideTraitCollection:[UITraitCollection traitCollectionWithPreferredContentSizeCategory:UIContentSizeCategoryAccessibilityExtraExtraExtraLarge]
                 forChildViewController:self.settings];
    [self.settings refreshTextLayout];
    Check(@"large-text-keeps-search-visible", !self.settings.searchBar.hidden);
    [self.settings.view layoutIfNeeded];
    Check(@"compact-search-header-height", fabs(CGRectGetHeight(self.settings.tableView.tableHeaderView.frame) - 72.0) < 0.5);
    [self.nav setOverrideTraitCollection:nil forChildViewController:self.settings];
    [self.settings refreshTextLayout];
    DYPlusAboutViewController *about = [DYPlusAboutViewController new];
    [about loadViewIfNeeded];
    UITableViewCell *aboutEntry = [self.settings tableView:self.settings.tableView cellForRowAtIndexPath:[NSIndexPath indexPathForRow:0 inSection:1]];
    Check(@"public-about-title-douyinplus", [about.title isEqual:@"关于 DouYinPlus"] && [aboutEntry.textLabel.text isEqual:@"关于 DouYinPlus"]);
    [DYPlusSettingsPreferences setChoiceValue:2 forKey:@"DYYYDefaultQuality"];
    Check(@"quality-choice-1080p", [DYPlusSettingsPreferences choiceValueForKey:@"DYYYDefaultQuality"]==2
        && ![NSUserDefaults.standardUserDefaults boolForKey:@"DYYYEnableVideoHighestQuality"]);
    [DYPlusSettingsPreferences setChoiceValue:0 forKey:@"DYYYClearButtonPreset"];
    Check(@"size-mutual-exclusion", [NSUserDefaults.standardUserDefaults boolForKey:@"DYYYCustomAlbumSizeSmall"]
        && ![NSUserDefaults.standardUserDefaults boolForKey:@"DYYYCustomAlbumSizeMedium"]);
    [NSUserDefaults.standardUserDefaults removeObjectForKey:@"DYYYCommentCopyText"];
    [NSUserDefaults.standardUserDefaults setBool:YES forKey:@"DYYYEnableCommentCopyText"];
    [DYPlusSettingsPreferences migrateLegacyOptions];
    Check(@"old-copy-option-migrated", [NSUserDefaults.standardUserDefaults boolForKey:@"DYYYCommentCopyText"]
        && ![NSUserDefaults.standardUserDefaults objectForKey:@"DYYYEnableCommentCopyText"]);
    [self.settings filterContentForSearchText:@"玻璃"];
    Check(@"global-search-hits", self.settings.filteredSections.count>0);
    if([args containsObject:@"category"]) [self.settings openCategoryAtIndex:2];
    if([args containsObject:@"about"]) [self.settings showAboutPage];
    if([args containsObject:@"search"]) { self.settings.searchBar.text = @"玻璃"; [self.settings searchBar:self.settings.searchBar textDidChange:@"玻璃"]; }
    if([args containsObject:@"group"]) {
        DYPlusSettingViewController *category = (DYPlusSettingViewController *)self.nav.topViewController;
        if(category == self.settings) [self.settings openCategoryAtIndex:0];
        category = (DYPlusSettingViewController *)self.nav.topViewController;
        [category loadViewIfNeeded];
        [category openGroupAtIndex:0];
    }
    if([args containsObject:@"large"]) {
        self.window.rootViewController = self.nav;
        [self.nav setOverrideTraitCollection:[UITraitCollection traitCollectionWithPreferredContentSizeCategory:UIContentSizeCategoryAccessibilityExtraExtraExtraLarge] forChildViewController:self.nav.topViewController];
    }
    printf("UI SUMMARY: %lu PASS, 0 FAIL\n", (unsigned long)uiChecks); fflush(stdout);
    DYPlusRunCoreRegressionTests();
    DYPlusRunRemoteHandlerRegression();
    if ([args containsObject:@"test"]) exit(0);
    [self.nav.topViewController loadViewIfNeeded];
    [self.window layoutIfNeeded];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC / 2), dispatch_get_main_queue(), ^{
        UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithBounds:self.window.bounds];
        UIImage *image = [renderer imageWithActions:^(UIGraphicsImageRendererContext *context) {
            [self.window drawViewHierarchyInRect:self.window.bounds afterScreenUpdates:YES];
        }];
        NSString *path = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject stringByAppendingPathComponent:@"preview.png"];
        [UIImagePNGRepresentation(image) writeToFile:path atomically:YES];
        printf("APP WINDOW CAPTURE: %s\n", path.UTF8String); fflush(stdout);
        [UIView setAnimationsEnabled:YES];
    });
    printf("READY settings-preview\n");fflush(stdout);
}
@end
@interface DYPlusPreviewApp : UIResponder <UIApplicationDelegate>
@end
@implementation DYPlusPreviewApp
- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)options { return YES; }
@end
int main(int argc,char **argv){@autoreleasepool{return UIApplicationMain(argc,argv,nil,NSStringFromClass(DYPlusPreviewApp.class));}}
