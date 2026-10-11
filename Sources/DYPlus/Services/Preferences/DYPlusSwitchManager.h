#import <Foundation/Foundation.h>

// 使用前向声明替代 UIKit 头文件以降低编译依赖
@class UISwitch;
@class UITableView;

NS_ASSUME_NONNULL_BEGIN

@class DYPlusSettingItem;

@interface DYPlusSwitchManager : NSObject

+ (instancetype)sharedManager;

// 处理开关切换
- (void)handleSwitchToggled:(UISwitch *)sender 
                  withItem:(DYPlusSettingItem *)item 
                   section:(NSInteger)section 
                       row:(NSInteger)row
                 tableView:(UITableView *)tableView
          settingSections:(NSArray<NSArray<DYPlusSettingItem *> *> *)settingSections;

// 更新互斥开关（按钮大小）
- (void)updateMutuallyExclusiveSwitches:(NSInteger)section 
                        excludingItemKey:(NSString *)excludedKey
                               tableView:(UITableView *)tableView
                        settingSections:(NSArray<NSArray<DYPlusSettingItem *> *> *)settingSections;

// 更新子开关状态
- (void)updateSubSwitchesInSection:(NSInteger)section 
                          withKeys:(NSArray<NSString *> *)keys 
                           enabled:(BOOL)enabled
                         tableView:(UITableView *)tableView
                  settingSections:(NSArray<NSArray<DYPlusSettingItem *> *> *)settingSections;

// 更新开关依赖关系
- (void)updateSwitchDependencies:(NSString *)key 
                       isEnabled:(BOOL)enabled 
                         section:(NSInteger)section
                       tableView:(UITableView *)tableView
                settingSections:(NSArray<NSArray<DYPlusSettingItem *> *> *)settingSections;

// 处理特殊开关逻辑
- (void)updateAreaSubSwitchesUI:(NSInteger)section 
                        enabled:(BOOL)enabled
                      tableView:(UITableView *)tableView
               settingSections:(NSArray<NSArray<DYPlusSettingItem *> *> *)settingSections;

- (void)updateAreaMainSwitchUI:(NSInteger)section
                     tableView:(UITableView *)tableView
              settingSections:(NSArray<NSArray<DYPlusSettingItem *> *> *)settingSections;

- (void)updateDateTimeFormatSubSwitchesUI:(NSInteger)section 
                                  enabled:(BOOL)enabled
                                tableView:(UITableView *)tableView
                         settingSections:(NSArray<NSArray<DYPlusSettingItem *> *> *)settingSections;

- (void)updateDateTimeFormatMainSwitchUI:(NSInteger)section
                               tableView:(UITableView *)tableView
                        settingSections:(NSArray<NSArray<DYPlusSettingItem *> *> *)settingSections;

- (void)updateDateTimeFormatExclusiveSwitch:(NSInteger)section 
                                 currentKey:(NSString *)currentKey
                                  tableView:(UITableView *)tableView
                           settingSections:(NSArray<NSArray<DYPlusSettingItem *> *> *)settingSections;

// 处理特殊开关类型
- (void)handleSpecialSwitchTypes:(DYPlusSettingItem *)item 
                          sender:(UISwitch *)sender
                         section:(NSInteger)section
                       tableView:(UITableView *)tableView
                settingSections:(NSArray<NSArray<DYPlusSettingItem *> *> *)settingSections;

@end

NS_ASSUME_NONNULL_END