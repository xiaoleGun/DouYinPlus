#import "Settings/DYPlusSettingViewController.h"

NS_ASSUME_NONNULL_BEGIN

@interface DYPlusSettingViewController (Actions)

- (void)iconButtonTapped:(UIButton *)sender;
- (void)animatedSwitchToggled:(UISwitch *)sender;
- (void)tableView:(UITableView *)tableView willDisplayCell:(UITableViewCell *)cell forRowAtIndexPath:(NSIndexPath *)indexPath;
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath;
- (void)handleIconSelection:(DYPlusSettingItem *)item;
- (void)showIconOptionsDialogWithTitle:(NSString *)title previewImage:(UIImage *)previewImage saveFilename:(NSString *)saveFilename;
- (void)showChoiceForItem:(DYPlusSettingItem *)item fromIndexPath:(NSIndexPath *)indexPath;
- (void)showSliderForItem:(DYPlusSettingItem *)item fromIndexPath:(NSIndexPath *)indexPath;
- (void)showSpeedPickerForItem:(DYPlusSettingItem *)item fromIndexPath:(NSIndexPath *)indexPath;
- (void)switchToggled:(UISwitch *)sender;
- (void)updateClearButtonSubSwitchesUI:(NSInteger)section enabled:(BOOL)enabled;
- (void)updateLongPressSubSwitchesUI:(NSInteger)section enabled:(BOOL)enabled;
- (void)textFieldDidChange:(UITextField *)textField;
- (void)avatarTextFieldDidChange:(UITextField *)textField;
- (void)headerTapped:(UIButton *)sender;

@end

NS_ASSUME_NONNULL_END
