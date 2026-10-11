#import "Settings/DYPlusAboutViewController.h"
#import "Settings/DYPlusBranding.h"

@implementation DYPlusAboutViewController
- (instancetype)init {
    return [super initWithStyle:UITableViewStyleInsetGrouped];
}
- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = [@"关于 " stringByAppendingString:DYPlusProductName];
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = 64.0;
}
- (NSArray<NSArray<NSArray<NSString *> *> *> *)rows {
    return @[
        @[@[@"作者", DYPlusAuthorName, @""], @[@"版本", DYPlusProductVersion, @""],
          @[@"软件包", DYPlusPackageIdentifier, @""]],
        @[@[@"huami1314", @"DYYY 原作者", @"https://github.com/huami1314/DYYY"],
          @[@"Wtrwx", @"DYYY 原作与社区贡献", @"https://github.com/Wtrwx/DYYY"],
          @[@"pxx917144686", @"DYYY++ 功能与调试工具", @"https://github.com/pxx917144686"],
          @[@"HierarchThurs", @"DYKiller 玻璃与界面改进", @"https://github.com/HierarchThurs/DYKiller"]],
        @[@[@"源代码", @"查看项目与贡献记录", DYPlusRepositoryURL],
          @[@"许可与署名", @"MIT + Commons Clause · 上游许可保留", @"https://github.com/xiaoleGun/DouYinPlus/blob/main/LICENSE"]]
    ];
}
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return self.rows.count; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return self.rows[section].count; }
- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    return @[@"项目资料", @"感谢原作者与上游项目", @"项目链接"][section];
}
- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    return section == 1 ? [NSString stringWithFormat:@"感谢原作者、维护者和社区提供的代码与经验。%@ 在这些工作的基础上继续改进。", DYPlusProductName] : nil;
}
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"About"];
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"About"];
    NSArray *row = self.rows[indexPath.section][indexPath.row];
    cell.textLabel.text = row[0];
    cell.textLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
    cell.textLabel.adjustsFontForContentSizeCategory = YES;
    cell.textLabel.numberOfLines = 0;
    cell.detailTextLabel.text = row[1];
    cell.detailTextLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleFootnote];
    cell.detailTextLabel.adjustsFontForContentSizeCategory = YES;
    cell.detailTextLabel.numberOfLines = 0;
    cell.detailTextLabel.textColor = DYPlusSecondaryTextColor();
    cell.accessoryType = [row[2] length] ? UITableViewCellAccessoryDisclosureIndicator : UITableViewCellAccessoryNone;
    cell.selectionStyle = [row[2] length] ? UITableViewCellSelectionStyleDefault : UITableViewCellSelectionStyleNone;
    return cell;
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    NSString *url = self.rows[indexPath.section][indexPath.row][2];
    if (url.length) [UIApplication.sharedApplication openURL:[NSURL URLWithString:url] options:@{} completionHandler:nil];
}
@end
