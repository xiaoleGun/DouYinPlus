#import "Settings/DYPlusSettingViewController.h"
#import "Settings/DYPlusSettingViewControllerPrivate.h"
#import "Settings/DYPlusSettingViewControllerActions.h"
#import "Settings/DYPlusSettingItem.h"
#import "Core/Utilities/DYPlusUtils.h"
#import "Core/Storage/DYPlusPaths.h"
#import "Settings/DYPlusSettingsPreferences.h"
#import "Settings/DYPlusBranding.h"

@implementation DYPlusSettingViewController (Table)

- (void)searchBar:(UISearchBar *)searchBar textDidChange:(NSString *)searchText {
    self.isSearching = searchText.length > 0;
    [self filterContentForSearchText:searchText];
    [self.tableView reloadData];
}
- (void)filterContentForSearchText:(NSString *)searchText {
    NSMutableArray *sections = [NSMutableArray array];
    NSMutableArray *titles = [NSMutableArray array];
    for (NSUInteger i = 0; i < self.settingSections.count; i++) {
        NSMutableArray *hits = [NSMutableArray array];
        DYPlusSettingItem *group = nil;
        for (DYPlusSettingItem *item in self.settingSections[i]) {
            if (item.type == DYPlusSettingItemTypeGroupHeader) { group = item; continue; }
            NSString *text = [NSString stringWithFormat:@"%@ %@ %@", item.title, group.title ?: @"", self.sectionTitles[i]];
            if ([text localizedStandardContainsString:searchText] || [item.key localizedStandardContainsString:searchText]) {
                if (group && ![hits containsObject:group]) [hits addObject:group];
                [hits addObject:item];
            }
        }
        if (hits.count) { [sections addObject:hits]; [titles addObject:self.sectionTitles[i]]; }
    }
    self.filteredSections = sections;
    self.filteredSectionTitles = titles;
    if (self.isSearching && !sections.count) {
        UILabel *empty = [UILabel new];
        empty.text = @"没有找到相关设置\n试试“倍速”“玻璃”或“评论”";
        empty.numberOfLines = 0;
        empty.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
        empty.adjustsFontForContentSizeCategory = YES;
        empty.textColor = DYPlusSecondaryTextColor();
        empty.textAlignment = NSTextAlignmentCenter;
        self.tableView.backgroundView = empty;
    } else self.tableView.backgroundView = nil;
}
- (void)searchBarSearchButtonClicked:(UISearchBar *)searchBar { [searchBar resignFirstResponder]; }

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    if (!self.isCategoryPage && !self.isSearching) return 2;
    if (self.isCategoryPage && !self.isGroupPage && !self.isSearching) return 1;
    return self.isSearching ? self.filteredSections.count : self.settingSections.count;
}
- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    if (!self.isCategoryPage && !self.isSearching) return section == 0 ? @"体验偏好" : @"项目";
    if (self.isCategoryPage && !self.isGroupPage && !self.isSearching) return @"偏好分组";
    return self.isSearching ? self.filteredSectionTitles[section] : self.sectionTitles[section];
}
- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section { return nil; }
- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section { return UITableViewAutomaticDimension; }
- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath { return UITableViewAutomaticDimension; }
- (NSArray<DYPlusSettingItem *> *)visibleItemsForSection:(NSInteger)section {
    NSArray *sections = self.isSearching ? self.filteredSections : self.settingSections;
    return section >= 0 && section < (NSInteger)sections.count ? sections[section] : @[];
}
- (NSIndexPath *)visibleIndexPathForSettingKey:(NSString *)key {
    if (!self.isCategoryPage && !self.isSearching) return nil;
    NSArray *sections = self.isSearching ? self.filteredSections : self.settingSections;
    for (NSUInteger s = 0; s < sections.count; s++) {
        NSArray *items = [self visibleItemsForSection:s];
        for (NSUInteger r = 0; r < items.count; r++) {
            if ([((DYPlusSettingItem *)items[r]).key isEqualToString:key])
                return [NSIndexPath indexPathForRow:r inSection:s];
        }
    }
    return nil;
}
- (void)toggleGroupHeaderAtIndexPath:(NSIndexPath *)indexPath { }
- (NSArray<NSIndexPath *> *)rowsForSection:(NSInteger)section {
    if (!self.isCategoryPage && !self.isSearching) return @[];
    NSMutableArray *paths = [NSMutableArray array];
    for (NSUInteger row = 0; row < [self visibleItemsForSection:section].count; row++)
        [paths addObject:[NSIndexPath indexPathForRow:row inSection:section]];
    return paths;
}
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (!self.isCategoryPage && !self.isSearching) return section == 0 ? self.settingSections.count : 1;
    if (self.isCategoryPage && !self.isGroupPage && !self.isSearching) return self.settingSections.count;
    return [self visibleItemsForSection:section].count;
}

- (NSString *)iconNameForSection:(NSInteger)section {
    NSArray *names = @[@"play.rectangle", @"hand.tap", @"slider.horizontal.3",
                       @"line.3.horizontal.decrease", @"bubble.left.and.bubble.right", @"externaldrive"];
    return section >= 0 && section < (NSInteger)names.count ? names[section] : @"slider.horizontal.3";
}
- (UIColor *)iconColorForSection:(NSInteger)section { return self.view.tintColor; }
- (UIImage *)iconImageForSettingItem:(DYPlusSettingItem *)item { return nil; }
- (UIColor *)colorForSettingItem:(DYPlusSettingItem *)item { return UIColor.labelColor; }

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"NativeSetting"];
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"NativeSetting"];
    cell.textLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
    cell.textLabel.adjustsFontForContentSizeCategory = YES;
    cell.textLabel.numberOfLines = 0;
    cell.textLabel.textColor = UIColor.labelColor;
    cell.detailTextLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleFootnote];
    cell.detailTextLabel.adjustsFontForContentSizeCategory = YES;
    cell.detailTextLabel.numberOfLines = 0;
    cell.detailTextLabel.textColor = DYPlusSecondaryTextColor();
    cell.detailTextLabel.text = nil;
    cell.imageView.image = nil;
    cell.accessoryView = nil;
    cell.accessoryType = UITableViewCellAccessoryNone;
    cell.selectionStyle = UITableViewCellSelectionStyleDefault;
    cell.backgroundColor = UIColor.secondarySystemGroupedBackgroundColor;
    cell.layer.mask = nil;
    cell.accessibilityTraits = UIAccessibilityTraitNone;
    if (!self.isCategoryPage && !self.isSearching) {
        NSArray *summaries = @[@"倍速、画质、进度与清屏", @"长按、双击与快捷操作",
            @"底栏、液态玻璃与页面布局", @"广告、关键词与内容筛选",
            @"评论保存、消息与直播", @"备份、隐私与功能自检"];
        if (indexPath.section == 0) {
            cell.textLabel.text = self.sectionTitles[indexPath.row];
            cell.detailTextLabel.text = summaries[indexPath.row];
            cell.imageView.image = [UIImage systemImageNamed:[self iconNameForSection:indexPath.row]];
        } else {
            cell.textLabel.text = [@"关于 " stringByAppendingString:DYPlusProductName];
            cell.detailTextLabel.text = @"xiaoleGun · 原作者致谢 · 源代码";
            cell.imageView.image = [UIImage systemImageNamed:@"info.circle"];
        }
        cell.imageView.tintColor = self.view.tintColor;
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        return cell;
    }
    if (self.isCategoryPage && !self.isGroupPage && !self.isSearching) {
        cell.textLabel.text = self.sectionTitles[indexPath.row];
        NSMutableArray *summary = [NSMutableArray array];
        for (DYPlusSettingItem *option in self.settingSections[indexPath.row]) {
            if (summary.count == 2) break;
            [summary addObject:option.title];
        }
        cell.detailTextLabel.text = [summary componentsJoinedByString:@"、"];
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        return cell;
    }
    NSArray *items = [self visibleItemsForSection:indexPath.section];
    if (indexPath.row >= (NSInteger)items.count) return cell;
    DYPlusSettingItem *item = items[indexPath.row];
    cell.textLabel.text = item.title;
    if (item.type == DYPlusSettingItemTypeGroupHeader) {
        cell.accessibilityTraits = UIAccessibilityTraitHeader;
        cell.textLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleHeadline];
        cell.textLabel.textColor = DYPlusSecondaryTextColor();
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        return cell;
    }
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    if (item.type == DYPlusSettingItemTypeSwitch) {
        UISwitch *toggle = [UISwitch new];
        NSDictionary *parents = @{@"DYYYCommentGlassClear": @"DYYYCommentGlass",
                                   @"DYYYInnerNotiGlassClear": @"DYYYInnerNotiGlass",
                                   @"DYYYGlassTabBarClear": @"DYYYGlassTabBar",
                                   @"DYYYSharePanelGlassClear": @"DYYYSharePanelGlass"};
        NSString *parent = parents[item.key];
        if ([item.key hasPrefix:@"DYYYisEnableArea"] && ![item.key isEqualToString:@"DYYYisEnableArea"]) parent = @"DYYYisEnableArea";
        if (parent) toggle.enabled = [defaults boolForKey:parent];
        [toggle setOn:[defaults boolForKey:item.key]];
        toggle.accessibilityLabel = item.title;
        toggle.tag = indexPath.section * 1000 + indexPath.row;
        [toggle addTarget:self action:@selector(switchToggled:) forControlEvents:UIControlEventValueChanged];
        cell.accessoryView = toggle;
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
    } else {
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        if (item.type == DYPlusSettingItemTypeChoice) {
            NSInteger value = [DYPlusSettingsPreferences choiceValueForKey:item.key];
            cell.detailTextLabel.text = value >= 0 && value < (NSInteger)item.options.count ? item.options[value] : @"默认";
        } else if (item.type == DYPlusSettingItemTypeSlider) {
            NSNumber *stored = [defaults objectForKey:item.key];
            NSInteger percent = stored ? stored.integerValue : item.defaultInteger;
            cell.detailTextLabel.text = percent == 0 ? @"抖音默认" : percent == 100 ? @"胶囊" : [NSString stringWithFormat:@"%ld%%", (long)percent];
        } else if (item.type == DYPlusSettingItemTypeTextField) {
            id value = [defaults objectForKey:item.key];
            cell.detailTextLabel.text = value ? [value description] : (item.placeholder ?: @"未设置");
            if ([item.key hasPrefix:@"DYYYIcon"] || [item.key isEqualToString:@"DYYYCustomAlbumImage"])
                cell.detailTextLabel.text = @"选择或清除自定义图片";
        } else if (item.type == DYPlusSettingItemTypeSpeedPicker) {
            id value = [defaults objectForKey:item.key];
            cell.detailTextLabel.text = value ? [NSString stringWithFormat:@"%.2f×", [value doubleValue]] : @"跟随默认";
        } else if ([item.key isEqualToString:@"DYYYScheduleStyle"]) {
            cell.detailTextLabel.text = [defaults stringForKey:item.key] ?: @"默认";
        }
    }
    if ([item.key isEqualToString:@"DYYYEnableVideoHighestQuality"]) {
        cell.detailTextLabel.text = @"优先选择最高码率视频源";
    }
    if ([item.key isEqualToString:@"DYYYEnableFloatClearButtonSize"]) {
        cell.detailTextLabel.text = [NSString stringWithFormat:@"%@ · 数值优先于预设", cell.detailTextLabel.text ?: @"默认"];
    }
    return cell;
}
@end
