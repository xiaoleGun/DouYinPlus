#import "Settings/DYPlusSettingViewController.h"
#import "Settings/DYPlusSettingViewControllerPrivate.h"
#import "Settings/DYPlusSettingSectionProvider.h"
#import "Services/Media/DYPlusManager.h"
#import "Core/Utilities/DYPlusUtils.h"
#import "Integration/System/DYPlusABTestHook.h"
#import "Core/Storage/DYPlusPaths.h"
#import "Settings/DYPlusBranding.h"
#import "Settings/DYPlusAboutViewController.h"
#import "Settings/DYPlusSettingsPreferences.h"
#import <Photos/Photos.h>
#import <objc/runtime.h>

@interface DYPlusImagePickerDelegate : NSObject <UIImagePickerControllerDelegate, UINavigationControllerDelegate>
@property(nonatomic, copy) void (^completionBlock)(NSDictionary *info);
@end
@implementation DYPlusImagePickerDelegate
- (void)imagePickerController:(UIImagePickerController *)picker didFinishPickingMediaWithInfo:(NSDictionary *)info {
    if (self.completionBlock) self.completionBlock(info);
    [picker dismissViewControllerAnimated:YES completion:nil];
}
- (void)imagePickerControllerDidCancel:(UIImagePickerController *)picker { [picker dismissViewControllerAnimated:YES completion:nil]; }
@end

@implementation DYPlusSettingViewController (Appearance)

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = self.isCategoryPage ? self.categoryTitle : DYPlusProductName;
    self.expandedSections = [NSMutableSet set];
    self.expandedGroups = [NSMutableSet set];
    self.feedbackGenerator = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight];
    [self setupAppearance];
    [self setupSectionTitles];
    [self ensureCustomAlbumSizeDefault];
    [self setupSettingItems];
    [self setupSearchBar];
    [self setupTableView];
    [self setupFooterLabel];
    if (@available(iOS 17.0, *)) {
        [self registerForTraitChanges:@[UITraitPreferredContentSizeCategory.class]
                         withHandler:^(DYPlusSettingViewController *controller, __unused UITraitCollection *previous) {
            [controller refreshTextLayout];
        }];
    }
    ensureABTestDataLoaded();
}

- (void)ensureCustomAlbumSizeDefault {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    BOOL large = [defaults objectForKey:@"DYYYCustomAlbumSizeLarge"] ? [defaults boolForKey:@"DYYYCustomAlbumSizeLarge"] : NO;
    BOOL medium = [defaults objectForKey:@"DYYYCustomAlbumSizeMedium"] ? [defaults boolForKey:@"DYYYCustomAlbumSizeMedium"] : NO;
    BOOL small = [defaults objectForKey:@"DYYYCustomAlbumSizeSmall"] ? [defaults boolForKey:@"DYYYCustomAlbumSizeSmall"] : NO;

    // 如果都没设置过，默认“中”为YES，其它NO
    if (!large && !medium && !small) {
        [defaults setBool:NO forKey:@"DYYYCustomAlbumSizeLarge"];
        [defaults setBool:YES forKey:@"DYYYCustomAlbumSizeMedium"];
        [defaults setBool:NO forKey:@"DYYYCustomAlbumSizeSmall"];
        [defaults synchronize];
    } else {
        // 保证互斥：如果有多个为YES，只保留第一个为YES
        NSArray *keys = @[@"DYYYCustomAlbumSizeLarge", @"DYYYCustomAlbumSizeMedium", @"DYYYCustomAlbumSizeSmall"];
        NSMutableArray *onKeys = [NSMutableArray array];
        for (NSString *key in keys) {
            if ([defaults boolForKey:key]) {
                [onKeys addObject:key];
            }
        }
        if (onKeys.count > 1) {
            // 只保留第一个为YES，其它设为NO
            for (NSInteger i = 1; i < onKeys.count; i++) {
                [defaults setBool:NO forKey:onKeys[i]];
            }
            [defaults synchronize];
        }
    }
}


- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    self.isExiting = NO;
    [self.tableView reloadData];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [self.view endEditing:YES];
    self.isExiting = self.isBeingDismissed || self.navigationController.isBeingDismissed;
}

- (void)backButtonTapped:(id)sender {
    if (self.navigationController.viewControllers.count > 1) [self.navigationController popViewControllerAnimated:YES];
    else [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)setupAppearance {
    self.view.backgroundColor = UIColor.systemGroupedBackgroundColor;
    UIColor *accent = [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *traits) {
        return traits.userInterfaceStyle == UIUserInterfaceStyleDark
            ? [UIColor colorWithRed:1.0 green:0.451 blue:0.624 alpha:1.0]
            : [UIColor colorWithRed:0.659 green:0.063 blue:0.267 alpha:1.0];
    }];
    self.view.tintColor = accent;
    self.navigationController.navigationBar.tintColor = accent;
    self.navigationController.navigationBar.prefersLargeTitles = YES;
    self.navigationItem.backButtonDisplayMode = UINavigationItemBackButtonDisplayModeMinimal;
    self.navigationItem.largeTitleDisplayMode = self.isCategoryPage
        ? UINavigationItemLargeTitleDisplayModeNever : UINavigationItemLargeTitleDisplayModeAlways;
    UINavigationBarAppearance *appearance = [UINavigationBarAppearance new];
    [appearance configureWithDefaultBackground];
    self.navigationController.navigationBar.standardAppearance = appearance;
    self.navigationController.navigationBar.scrollEdgeAppearance = appearance;
    if (!self.isCategoryPage && self.navigationController.viewControllers.count <= 1) {
        self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"完成"
            style:UIBarButtonItemStylePlain target:self action:@selector(backButtonTapped:)];
    }
}

- (void)setupSearchBar {
    self.searchBar = [[UISearchBar alloc] init];
    self.searchBar.delegate = self;
    self.searchBar.placeholder = self.isCategoryPage ? @"搜索当前分类" : @"搜索所有设置";
    self.searchBar.searchBarStyle = UISearchBarStyleMinimal;
    self.searchBar.searchTextField.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
    self.searchBar.searchTextField.adjustsFontForContentSizeCategory = NO;
    [self refreshTextLayout];
}

- (void)refreshTextLayout {
    if (@available(iOS 17.0, *)) {
        self.searchBar.traitOverrides.preferredContentSizeCategory = UIContentSizeCategoryLarge;
    }
    // 搜索是导航控件，字号限制到 24pt；列表正文仍完整支持最大辅助字体。
    self.searchBar.searchTextField.font = [[UIFontMetrics metricsForTextStyle:UIFontTextStyleBody]
        scaledFontForFont:[UIFont systemFontOfSize:17.0] maximumPointSize:24.0 compatibleWithTraitCollection:self.traitCollection];
    UIImageSymbolConfiguration *icon = [UIImageSymbolConfiguration configurationWithPointSize:19.0 weight:UIImageSymbolWeightRegular];
    [self.searchBar setImage:[UIImage systemImageNamed:@"magnifyingglass" withConfiguration:icon] forSearchBarIcon:UISearchBarIconSearch state:UIControlStateNormal];
    self.searchBar.searchTextField.attributedPlaceholder = [[NSAttributedString alloc] initWithString:self.searchBar.placeholder ?: @"搜索设置"
        attributes:@{NSForegroundColorAttributeName:DYPlusSecondaryTextColor()}];
    [self.tableView reloadData];
    [self.view setNeedsLayout];
}

- (void)traitCollectionDidChange:(UITraitCollection *)previous {
    [super traitCollectionDidChange:previous];
    if (![previous.preferredContentSizeCategory isEqual:self.traitCollection.preferredContentSizeCategory]) [self refreshTextLayout];
}

- (void)setupTableView {
    self.tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStyleInsetGrouped];
    self.tableView.translatesAutoresizingMaskIntoConstraints = NO;
    self.tableView.delegate = self;
    self.tableView.dataSource = self;
    self.tableView.backgroundColor = UIColor.systemGroupedBackgroundColor;
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = 58.0;
    self.tableView.keyboardDismissMode = UIScrollViewKeyboardDismissModeOnDrag;
    [self.view addSubview:self.tableView];
    [NSLayoutConstraint activateConstraints:@[
        [self.tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.tableView.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [self.tableView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor]
    ]];
    UIView *header = [[UIView alloc] initWithFrame:CGRectMake(0, 0, self.view.bounds.size.width, 72)];
    header.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[self.searchBar]];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [self.searchBar.heightAnchor constraintEqualToConstant:56.0].active = YES;
    [header addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[
        [stack.leadingAnchor constraintEqualToAnchor:header.leadingAnchor constant:20.0],
        [stack.trailingAnchor constraintEqualToAnchor:header.trailingAnchor constant:-20.0],
        [stack.topAnchor constraintEqualToAnchor:header.topAnchor constant:8.0],
        [stack.bottomAnchor constraintEqualToAnchor:header.bottomAnchor constant:-8.0]
    ]];
    self.tableView.tableHeaderView = header;
    UILongPressGestureRecognizer *longPress = [[UILongPressGestureRecognizer alloc]
        initWithTarget:self action:@selector(handleLongPress:)];
    [self.tableView addGestureRecognizer:longPress];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    UIView *header = self.tableView.tableHeaderView;
    if (header) {
        CGFloat width = CGRectGetWidth(self.tableView.bounds);
        UIStackView *stack = (UIStackView *)header.subviews.firstObject;
        CGSize size = [stack systemLayoutSizeFittingSize:CGSizeMake(MAX(1.0, width - 40.0), UILayoutFittingCompressedSize.height)
            withHorizontalFittingPriority:UILayoutPriorityRequired verticalFittingPriority:UILayoutPriorityFittingSizeLevel];
        size.height += 16.0;
        if (fabs(header.frame.size.height - size.height) > 0.5 || fabs(header.frame.size.width - width) > 0.5) {
            header.frame = CGRectMake(0, 0, width, MAX(72.0, size.height));
            self.tableView.tableHeaderView = header;
        }
    }
    UIView *footer = self.tableView.tableFooterView;
    if (footer && self.footerLabel.text.length) {
        CGFloat width = CGRectGetWidth(self.tableView.bounds);
        CGSize text = [self.footerLabel sizeThatFits:CGSizeMake(MAX(1.0, width - 48.0), CGFLOAT_MAX)];
        CGFloat height = MAX(72.0, ceil(text.height) + 24.0);
        if (fabs(footer.frame.size.height - height) > 0.5 || fabs(footer.frame.size.width - width) > 0.5) {
            footer.frame = CGRectMake(0, 0, width, height);
            self.footerLabel.frame = CGRectInset(footer.bounds, 24.0, 12.0);
            self.tableView.tableFooterView = footer;
        }
    }
}

- (void)setupSettingItems {
    NSArray *allSections = [DYPlusSettingSectionProvider defaultSections];
    NSMutableArray *sections = [NSMutableArray array];
    for (NSArray *section in allSections) {
        NSMutableArray *items = [NSMutableArray array];
        for (DYPlusSettingItem *item in section) {
            if (item.type == DYPlusSettingItemTypeGroupHeader || DYPlusGlassOSAvailable()
                || !DYPlusGlassIsGatedKey(item.key)) [items addObject:item];
        }
        [sections addObject:items];
    }
    if (self.isCategoryPage && self.categoryIndex >= 0 && self.categoryIndex < (NSInteger)sections.count) {
        NSMutableArray *groups = [NSMutableArray array];
        NSMutableArray *titles = [NSMutableArray array];
        NSMutableArray *current = nil;
        for (DYPlusSettingItem *item in sections[self.categoryIndex]) {
            if (item.type == DYPlusSettingItemTypeGroupHeader) {
                current = [NSMutableArray array];
                [groups addObject:current];
                [titles addObject:item.title];
            } else {
                if (!current) {
                    current = [NSMutableArray array];
                    [groups addObject:current];
                    [titles addObject:self.categoryTitle];
                }
                [current addObject:item];
            }
        }
        NSMutableArray *keptGroups = [NSMutableArray array];
        NSMutableArray *keptTitles = [NSMutableArray array];
        for (NSUInteger i = 0; i < groups.count; i++) {
            if ([groups[i] count]) { [keptGroups addObject:groups[i]]; [keptTitles addObject:titles[i]]; }
        }
        self.settingSections = keptGroups;
        self.sectionTitles = keptTitles;
        if (self.isGroupPage && self.groupIndex >= 0 && self.groupIndex < (NSInteger)keptGroups.count) {
            self.settingSections = @[keptGroups[self.groupIndex]];
            self.sectionTitles = [@[keptTitles[self.groupIndex]] mutableCopy];
        }
    } else {
        self.settingSections = sections;
    }
}

- (void)setupSectionTitles {
    self.sectionTitles = [@[@"播放", @"手势与快捷", @"界面与玻璃", @"内容过滤", @"评论与直播", @"数据与维护"] mutableCopy];
}

- (void)setupFooterLabel {
    if (self.isCategoryPage) { self.tableView.tableFooterView = nil; return; }
    UIView *footer = [[UIView alloc] initWithFrame:CGRectMake(0, 0, self.view.bounds.size.width, 72.0)];
    UILabel *label = [[UILabel alloc] initWithFrame:CGRectInset(footer.bounds, 24.0, 12.0)];
    label.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    label.font = [UIFont preferredFontForTextStyle:UIFontTextStyleFootnote];
    label.adjustsFontForContentSizeCategory = YES;
    label.textColor = DYPlusSecondaryTextColor();
    label.textAlignment = NSTextAlignmentCenter;
    label.numberOfLines = 0;
    label.text = self.isCategoryPage ? nil : @"备份与恢复位于「数据与维护」";
    [footer addSubview:label];
    self.footerLabel = label;
    self.tableView.tableFooterView = footer;
}

- (void)openCategoryAtIndex:(NSInteger)index {
    if (index < 0 || index >= (NSInteger)self.settingSections.count) return;
    DYPlusSettingViewController *page = [DYPlusSettingViewController new];
    page.isCategoryPage = YES;
    page.categoryIndex = index;
    page.categoryTitle = self.sectionTitles[index];
    [self.navigationController pushViewController:page animated:YES];
}

- (void)showAboutPage {
    [self.navigationController pushViewController:[DYPlusAboutViewController new] animated:YES];
}

- (void)openGroupAtIndex:(NSInteger)index {
    if (index < 0 || index >= (NSInteger)self.settingSections.count) return;
    DYPlusSettingViewController *page = [DYPlusSettingViewController new];
    page.isCategoryPage = YES;
    page.isGroupPage = YES;
    page.groupIndex = index;
    page.categoryIndex = self.categoryIndex;
    page.categoryTitle = self.sectionTitles[index];
    [self.navigationController pushViewController:page animated:YES];
}

- (void)imagePickerController:(UIImagePickerController *)picker didFinishPickingMediaWithInfo:(NSDictionary<UIImagePickerControllerInfoKey, id> *)info {
    [picker dismissViewControllerAnimated:YES completion:nil];
    
    UIImage *selectedImage = info[UIImagePickerControllerEditedImage] ?: info[UIImagePickerControllerOriginalImage];
    if (!selectedImage) {
        [DYPlusManager showToast:@"无法获取所选图片"];
        return;
    }
    
    BOOL isCustomAlbumPicker = [objc_getAssociatedObject(picker, "isCustomAlbumPicker") boolValue];
    if (isCustomAlbumPicker) {
        NSString *customAlbumImagePath = [self saveCustomAlbumImage:selectedImage];
        if (customAlbumImagePath) {
            [[NSUserDefaults standardUserDefaults] setObject:customAlbumImagePath forKey:@"DYYYCustomAlbumImagePath"];
            [[NSUserDefaults standardUserDefaults] synchronize];
            [DYPlusManager showToast:@"自定义相册图片已设置"];
            [self.tableView reloadData];
            [[NSNotificationCenter defaultCenter] postNotificationName:@"DYYYCustomAlbumSettingChanged" object:nil];
        } else {
            [DYPlusManager showToast:@"保存自定义相册图片失败"];
        }
    } else {
        NSString *avatarPath = [self avatarImagePath];
        NSData *imageData = UIImageJPEGRepresentation(selectedImage, 0.8);
        [imageData writeToFile:avatarPath atomically:YES];
        self.avatarImageView.image = selectedImage;
    }
}

- (void)imagePickerControllerDidCancel:(UIImagePickerController *)picker {
    [picker dismissViewControllerAnimated:YES completion:nil];
}

- (NSString *)avatarImagePath {
    NSString *documentsPath = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
    return [documentsPath stringByAppendingPathComponent:@"DYYYAvatar.jpg"];
}

- (NSString *)saveCustomAlbumImage:(UIImage *)image {
    NSString *dyplusFolder = [DYPlusPaths iconsDir];
    
    NSError *error;
    [[NSFileManager defaultManager] createDirectoryAtPath:dyplusFolder 
                              withIntermediateDirectories:YES 
                                               attributes:nil 
                                                    error:&error];
    if (error) {
        return nil;
    }
    
    NSString *imagePath = [dyplusFolder stringByAppendingPathComponent:@"custom_album_image.png"];
    NSData *imageData = UIImagePNGRepresentation(image);
    if ([imageData writeToFile:imagePath atomically:YES]) {
        return imagePath;
    }
    
    return nil;
}

#pragma mark - Dealloc

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    if (self.tableView) {
        self.tableView.delegate = nil;
        self.tableView.dataSource = nil;
    }
    if (self.searchBar) {
        self.searchBar.delegate = nil;
    }
}

@end
