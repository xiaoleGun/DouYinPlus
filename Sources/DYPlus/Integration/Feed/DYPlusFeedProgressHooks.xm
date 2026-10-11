#import "Core/Runtime/DYPlusRuntime.h"
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import "Services/Media/DYPlusManager.h"
#import "Integration/Headers/DYPlusAwemeHeaders.h"
#import "Core/Utilities/DYPlusUtils.h"

@interface AWEFeedProgressSlider (DYPlusProgressLabel)
- (NSString *)dyplus_formatTimeFromSeconds:(CGFloat)seconds;
- (CGFloat)dyplus_modelDurationInSeconds;
- (CGFloat)dyplus_durationFromModel:(id)model;
- (CGFloat)dyplus_scheduleVerticalOffset;
- (void)dyplus_removeScheduleLabels;
- (void)dyplus_updateScheduleLabelsWithCurrentTime:(CGFloat)currentTime totalDuration:(CGFloat)totalDuration;
- (UIColor *)dyplus_labelColor;
@end

@interface AWEPlayInteractionProgressController (DYPlusProgressLabel)
- (void)dyplus_syncScheduleLabelsWithCurrentTime:(CGFloat)currentTime totalDuration:(CGFloat)totalDuration;
@end

@interface AWEDProgressCoreContainer : UIView
@end

@interface AWEDProgressCoreContainer (DYPlusProgressLabel)
- (void)dyplus_syncScheduleLabelsWithCurrentTime:(CGFloat)currentTime totalDuration:(CGFloat)totalDuration;
@end

@interface UIView (DYPlusProgressLabelLegacy)
- (void)dyplus_updateScheduleLabelsLegacyWithCurrentTime:(CGFloat)currentTime totalDuration:(CGFloat)totalDuration model:(id)model;
@end

@implementation UIView (DYPlusProgressLabelLegacy)

- (NSString *)dyplus_legacyFormatTimeFromSeconds:(CGFloat)seconds {
    CGFloat safeSeconds = seconds;
    if (safeSeconds < 0) {
        safeSeconds = 0;
    }

    NSInteger total = (NSInteger)floor(safeSeconds);
    NSInteger hours = total / 3600;
    NSInteger minutes = (total % 3600) / 60;
    NSInteger secs = total % 60;

    if (hours > 0) {
        return [NSString stringWithFormat:@"%02ld:%02ld:%02ld", (long)hours, (long)minutes, (long)secs];
    }
    return [NSString stringWithFormat:@"%02ld:%02ld", (long)minutes, (long)secs];
}

- (CGFloat)dyplus_legacyScheduleVerticalOffset {
    CGFloat verticalOffset = -12.5;
    NSString *offsetValueString = DYPlusPreferenceString(@"DYYYTimelineVerticalPosition");
    if (offsetValueString.length > 0) {
        CGFloat configuredOffset = [offsetValueString floatValue];
        if (configuredOffset != 0) {
            verticalOffset = configuredOffset;
        }
    }
    return verticalOffset;
}

- (CGFloat)dyplus_legacyModelDurationInSeconds:(id)model {
    if (!model) {
        return 0;
    }
    if ([model respondsToSelector:@selector(videoDuration)]) {
        CGFloat videoDurationMs = [[model valueForKey:@"videoDuration"] doubleValue];
        if (videoDurationMs > 0) {
            return videoDurationMs / 1000.0;
        }
    }
    if ([model respondsToSelector:@selector(duration)]) {
        CGFloat duration = [[model valueForKey:@"duration"] doubleValue];
        if (duration > 0) {
            if (duration > 100000) {
                return duration / 1000.0;
            }
            return duration;
        }
    }
    return 0;
}

- (void)dyplus_updateScheduleLabelsLegacyWithCurrentTime:(CGFloat)currentTime totalDuration:(CGFloat)totalDuration model:(id)model {
    if (![[NSUserDefaults standardUserDefaults] boolForKey:@"DYYYisShowScheduleDisplay"]) {
        UIView *parentView = self.superview;
        if (parentView) {
            [[parentView viewWithTag:10001] removeFromSuperview];
            [[parentView viewWithTag:10002] removeFromSuperview];
        }
        return;
    }

    if (![NSThread isMainThread]) {
        __weak __typeof(self) weakSelf = self;
        dispatch_async(dispatch_get_main_queue(), ^{
          [weakSelf dyplus_updateScheduleLabelsLegacyWithCurrentTime:currentTime totalDuration:totalDuration model:model];
        });
        return;
    }

    UIView *parentView = self.superview;
    if (!parentView) {
        return;
    }
    [parentView layoutIfNeeded];
    [self layoutIfNeeded];

    NSString *scheduleStyle = DYPlusPreferenceString(@"DYYYScheduleStyle");
    BOOL showRightRemainingTime = [scheduleStyle isEqualToString:@"进度条右侧剩余"];
    BOOL showRightCompleteTime = [scheduleStyle isEqualToString:@"进度条右侧完整"];
    BOOL showLeftRemainingTime = [scheduleStyle isEqualToString:@"进度条左侧剩余"];
    BOOL showLeftCompleteTime = [scheduleStyle isEqualToString:@"进度条左侧完整"];

    // 默认左右都显示
    BOOL shouldShowLeftLabel = !showRightRemainingTime && !showRightCompleteTime;
    BOOL shouldShowRightLabel = !showLeftRemainingTime && !showLeftCompleteTime;

    CGFloat modelDuration = [self dyplus_legacyModelDurationInSeconds:model];
    CGFloat effectiveTotalDuration = totalDuration > 0 ? totalDuration : modelDuration;
    if (effectiveTotalDuration < 0) {
        effectiveTotalDuration = 0;
    }

    CGFloat effectiveCurrentTime = currentTime;
    if (effectiveCurrentTime < 0) {
        effectiveCurrentTime = 0;
    }
    if (effectiveTotalDuration > 0 && effectiveCurrentTime > effectiveTotalDuration) {
        effectiveCurrentTime = effectiveTotalDuration;
    }

    CGRect sliderFrameInParent = [self convertRect:self.bounds toView:parentView];
    if (CGRectGetWidth(sliderFrameInParent) <= 1.0 || CGRectGetHeight(sliderFrameInParent) <= 1.0) {
        return;
    }
    CGFloat labelYPosition = CGRectGetMinY(sliderFrameInParent) + [self dyplus_legacyScheduleVerticalOffset];
    CGFloat labelHeight = 15.0;
    UIFont *labelFont = [UIFont systemFontOfSize:8];
    NSString *labelColorHex = DYPlusPreferenceString(@"DYYYProgressLabelColor");

    UILabel *leftLabel = (UILabel *)[parentView viewWithTag:10001];
    if (leftLabel && ![leftLabel isKindOfClass:[UILabel class]]) {
        [leftLabel removeFromSuperview];
        leftLabel = nil;
    }

    if (shouldShowLeftLabel) {
        if (!leftLabel) {
            leftLabel = [[UILabel alloc] init];
            leftLabel.backgroundColor = [UIColor clearColor];
            leftLabel.tag = 10001;
            [parentView addSubview:leftLabel];
        }
        leftLabel.font = labelFont;

        NSString *newLeftText = nil;
        if (showLeftRemainingTime) {
            newLeftText = [self dyplus_legacyFormatTimeFromSeconds:MAX(effectiveTotalDuration - effectiveCurrentTime, 0)];
        } else if (showLeftCompleteTime) {
            newLeftText = [NSString stringWithFormat:@"%@/%@", [self dyplus_legacyFormatTimeFromSeconds:effectiveCurrentTime], [self dyplus_legacyFormatTimeFromSeconds:effectiveTotalDuration]];
        } else {
            newLeftText = [self dyplus_legacyFormatTimeFromSeconds:effectiveCurrentTime];
        }

        if (![leftLabel.text isEqualToString:newLeftText]) {
            leftLabel.text = newLeftText;
        }
        [leftLabel sizeToFit];
        leftLabel.frame = CGRectMake(CGRectGetMinX(sliderFrameInParent), labelYPosition, CGRectGetWidth(leftLabel.bounds), labelHeight);

        if (labelColorHex && labelColorHex.length > 0) {
            @try {
                UIColor *labelColor = [DYPlusManager colorWithHexString:labelColorHex];
                if (labelColor) {
                    leftLabel.textColor = labelColor;
                }
            } @catch (NSException *exception) {
            }
        }
    } else {
        [leftLabel removeFromSuperview];
    }

    UILabel *rightLabel = (UILabel *)[parentView viewWithTag:10002];
    if (rightLabel && ![rightLabel isKindOfClass:[UILabel class]]) {
        [rightLabel removeFromSuperview];
        rightLabel = nil;
    }

    if (shouldShowRightLabel) {
        if (!rightLabel) {
            rightLabel = [[UILabel alloc] init];
            rightLabel.backgroundColor = [UIColor clearColor];
            rightLabel.tag = 10002;
            [parentView addSubview:rightLabel];
        }
        rightLabel.font = labelFont;

        NSString *newRightText = nil;
        if (showRightRemainingTime) {
            newRightText = [self dyplus_legacyFormatTimeFromSeconds:MAX(effectiveTotalDuration - effectiveCurrentTime, 0)];
        } else if (showRightCompleteTime) {
            newRightText = [NSString stringWithFormat:@"%@/%@", [self dyplus_legacyFormatTimeFromSeconds:effectiveCurrentTime], [self dyplus_legacyFormatTimeFromSeconds:effectiveTotalDuration]];
        } else {
            newRightText = [self dyplus_legacyFormatTimeFromSeconds:effectiveTotalDuration];
        }

        if (![rightLabel.text isEqualToString:newRightText]) {
            rightLabel.text = newRightText;
        }
        [rightLabel sizeToFit];
        CGFloat rightLabelX = MAX(CGRectGetMaxX(sliderFrameInParent) - CGRectGetWidth(rightLabel.bounds), CGRectGetMinX(sliderFrameInParent));
        rightLabel.frame = CGRectMake(rightLabelX, labelYPosition, CGRectGetWidth(rightLabel.bounds), labelHeight);

        if (labelColorHex && labelColorHex.length > 0) {
            @try {
                UIColor *labelColor = [DYPlusManager colorWithHexString:labelColorHex];
                if (labelColor) {
                    rightLabel.textColor = labelColor;
                }
            } @catch (NSException *exception) {
            }
        }
    } else {
        [rightLabel removeFromSuperview];
    }
}

@end

%hook AWEFeedProgressSlider

%new
- (BOOL)dyplus_isUpdatingLabels {
    NSNumber *flag = objc_getAssociatedObject(self, _cmd);
    return [flag boolValue];
}

%new
- (void)setDyyy_isUpdatingLabels:(BOOL)flag {
    objc_setAssociatedObject(self, @selector(dyplus_isUpdatingLabels), @(flag), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

%new
- (CGRect)dyplus_originalSliderFrame {
    NSValue *value = objc_getAssociatedObject(self, _cmd);
    if (value) {
        return [value CGRectValue];
    }
    return CGRectZero;
}

%new
- (void)setDyyy_originalSliderFrame:(CGRect)frame {
    objc_setAssociatedObject(self, @selector(dyplus_originalSliderFrame), [NSValue valueWithCGRect:frame], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

%new
- (NSString *)dyplus_formatTimeFromSeconds:(CGFloat)seconds {
    CGFloat safeSeconds = seconds;
    if (safeSeconds < 0) {
        safeSeconds = 0;
    }

    NSInteger total = (NSInteger)floor(safeSeconds);
    NSInteger hours = total / 3600;
    NSInteger minutes = (total % 3600) / 60;
    NSInteger secs = total % 60;

    if (hours > 0) {
        return [NSString stringWithFormat:@"%02ld:%02ld:%02ld", (long)hours, (long)minutes, (long)secs];
    }
    return [NSString stringWithFormat:@"%02ld:%02ld", (long)minutes, (long)secs];
}

%new
- (CGFloat)dyplus_modelDurationInSeconds {
    id delegate = self.progressSliderDelegate;
    if (delegate && [delegate respondsToSelector:@selector(model)]) {
        id model = [delegate valueForKey:@"model"];
        CGFloat duration = [self dyplus_durationFromModel:model];
        if (duration > 0) {
            return duration;
        }
    }
    
    return 0;
}

%new
- (CGFloat)dyplus_durationFromModel:(id)model {
    if (!model) {
        return 0;
    }
    
    if ([model respondsToSelector:@selector(videoDuration)]) {
        CGFloat videoDurationMs = [[model valueForKey:@"videoDuration"] doubleValue];
        if (videoDurationMs > 0) {
            return videoDurationMs / 1000.0;
        }
    }
    
    if ([model respondsToSelector:@selector(duration)]) {
        CGFloat duration = [[model valueForKey:@"duration"] doubleValue];
        if (duration > 0) {
            if (duration > 100000) {
                return duration / 1000.0;
            }
            return duration;
        }
    }
    
    return 0;
}

%new
- (CGFloat)dyplus_scheduleVerticalOffset {
    CGFloat verticalOffset = -12.5;
    NSString *offsetValueString = DYPlusPreferenceString(@"DYYYTimelineVerticalPosition");
    if (offsetValueString.length > 0) {
        CGFloat configuredOffset = [offsetValueString floatValue];
        if (configuredOffset != 0) {
            verticalOffset = configuredOffset;
        }
    }
    return verticalOffset;
}

%new
- (UIColor *)dyplus_labelColor {
    NSString *labelColorHex = DYPlusPreferenceString(@"DYYYProgressLabelColor");
    UIColor *labelColor = [UIColor whiteColor];
    if (labelColorHex && labelColorHex.length > 0) {
        @try {
            labelColor = [DYPlusManager colorWithHexString:labelColorHex];
        } @catch (NSException *exception) {
        }
    }
    return labelColor;
}

%new
- (void)dyplus_removeScheduleLabels {
    UIView *parentView = self.superview;
    if (!parentView) {
        return;
    }
    [parentView layoutIfNeeded];
    [self layoutIfNeeded];
    [[parentView viewWithTag:10001] removeFromSuperview];
    [[parentView viewWithTag:10002] removeFromSuperview];
}

%new
- (void)dyplus_updateScheduleLabelsWithCurrentTime:(CGFloat)currentTime totalDuration:(CGFloat)totalDuration {
    if (![[NSUserDefaults standardUserDefaults] boolForKey:@"DYYYisShowScheduleDisplay"]) {
        [self dyplus_removeScheduleLabels];
        return;
    }

    if (![NSThread isMainThread]) {
        __weak __typeof(self) weakSelf = self;
        dispatch_async(dispatch_get_main_queue(), ^{
          [weakSelf dyplus_updateScheduleLabelsWithCurrentTime:currentTime totalDuration:totalDuration];
        });
        return;
    }

    UIView *parentView = self.superview;
    if (!parentView) {
        return;
    }
    [parentView layoutIfNeeded];
    [self layoutIfNeeded];

    NSString *scheduleStyle = DYPlusPreferenceString(@"DYYYScheduleStyle");
    BOOL showRightRemainingTime = [scheduleStyle isEqualToString:@"进度条右侧剩余"];
    BOOL showRightCompleteTime = [scheduleStyle isEqualToString:@"进度条右侧完整"];
    BOOL showLeftRemainingTime = [scheduleStyle isEqualToString:@"进度条左侧剩余"];
    BOOL showLeftCompleteTime = [scheduleStyle isEqualToString:@"进度条左侧完整"];

    // 默认（scheduleStyle 为空）时左右都显示；只有明确指定右侧模式才只显示右侧；只有明确指定左侧模式才只显示左侧
    BOOL shouldShowLeftLabel = !showRightRemainingTime && !showRightCompleteTime;
    BOOL shouldShowRightLabel = !showLeftRemainingTime && !showLeftCompleteTime;

    CGFloat modelDuration = [self dyplus_modelDurationInSeconds];
    CGFloat effectiveTotalDuration = totalDuration > 0 ? totalDuration : modelDuration;
    if (effectiveTotalDuration < 0) {
        effectiveTotalDuration = 0;
    }

    CGFloat effectiveCurrentTime = currentTime;
    if (effectiveCurrentTime < 0) {
        effectiveCurrentTime = 0;
    }
    if (effectiveTotalDuration > 0 && effectiveCurrentTime > effectiveTotalDuration) {
        effectiveCurrentTime = effectiveTotalDuration;
    }

    CGRect sliderFrameInParent = [self convertRect:self.bounds toView:parentView];
    if (CGRectGetWidth(sliderFrameInParent) <= 1.0 || CGRectGetHeight(sliderFrameInParent) <= 1.0) {
        return;
    }
    CGFloat labelYPosition = CGRectGetMinY(sliderFrameInParent) + [self dyplus_scheduleVerticalOffset];
    CGFloat labelHeight = 15.0;
    UIFont *labelFont = [UIFont systemFontOfSize:8];
    UIColor *labelColor = [self dyplus_labelColor];

    UILabel *leftLabel = (UILabel *)[parentView viewWithTag:10001];
    if (leftLabel && ![leftLabel isKindOfClass:[UILabel class]]) {
        [leftLabel removeFromSuperview];
        leftLabel = nil;
    }

    if (shouldShowLeftLabel) {
        if (!leftLabel) {
            leftLabel = [[UILabel alloc] init];
            leftLabel.backgroundColor = [UIColor clearColor];
            leftLabel.tag = 10001;
            [parentView addSubview:leftLabel];
        }

        leftLabel.font = labelFont;
        leftLabel.textColor = labelColor;

        NSString *newLeftText = nil;
        if (showLeftRemainingTime) {
            newLeftText = [self dyplus_formatTimeFromSeconds:MAX(effectiveTotalDuration - effectiveCurrentTime, 0)];
        } else if (showLeftCompleteTime) {
            newLeftText = [NSString stringWithFormat:@"%@/%@", [self dyplus_formatTimeFromSeconds:effectiveCurrentTime], [self dyplus_formatTimeFromSeconds:effectiveTotalDuration]];
        } else {
            newLeftText = [self dyplus_formatTimeFromSeconds:effectiveCurrentTime];
        }

        if (![leftLabel.text isEqualToString:newLeftText]) {
            leftLabel.text = newLeftText;
        }
        [leftLabel sizeToFit];
        leftLabel.frame = CGRectMake(CGRectGetMinX(sliderFrameInParent), labelYPosition, CGRectGetWidth(leftLabel.bounds), labelHeight);
    } else {
        [leftLabel removeFromSuperview];
    }

    UILabel *rightLabel = (UILabel *)[parentView viewWithTag:10002];
    if (rightLabel && ![rightLabel isKindOfClass:[UILabel class]]) {
        [rightLabel removeFromSuperview];
        rightLabel = nil;
    }

    if (shouldShowRightLabel) {
        if (!rightLabel) {
            rightLabel = [[UILabel alloc] init];
            rightLabel.backgroundColor = [UIColor clearColor];
            rightLabel.tag = 10002;
            [parentView addSubview:rightLabel];
        }

        rightLabel.font = labelFont;
        rightLabel.textColor = labelColor;

        NSString *newRightText = nil;
        if (showRightRemainingTime) {
            newRightText = [self dyplus_formatTimeFromSeconds:MAX(effectiveTotalDuration - effectiveCurrentTime, 0)];
        } else if (showRightCompleteTime) {
            newRightText = [NSString stringWithFormat:@"%@/%@", [self dyplus_formatTimeFromSeconds:effectiveCurrentTime], [self dyplus_formatTimeFromSeconds:effectiveTotalDuration]];
        } else {
            newRightText = [self dyplus_formatTimeFromSeconds:effectiveTotalDuration];
        }

        if (![rightLabel.text isEqualToString:newRightText]) {
            rightLabel.text = newRightText;
        }
        [rightLabel sizeToFit];
        CGFloat rightLabelX = MAX(CGRectGetMaxX(sliderFrameInParent) - CGRectGetWidth(rightLabel.bounds), CGRectGetMinX(sliderFrameInParent));
        rightLabel.frame = CGRectMake(rightLabelX, labelYPosition, CGRectGetWidth(rightLabel.bounds), labelHeight);
    } else {
        [rightLabel removeFromSuperview];
    }
}

- (id)initWithFrame:(CGRect)frame {
    id result = %orig;
    [[NSNotificationCenter defaultCenter] addObserver:self
                                            selector:@selector(handleSettingChanged:)
                                                name:@"DYYYSettingChanged"
                                              object:nil];
    return result;
}

%new
- (void)handleSettingChanged:(NSNotification *)notification {
    @try {
        NSDictionary *userInfo = notification.userInfo;
        if (!userInfo) return;
        
        NSString *key = userInfo[@"key"];
        if (!key) return;
        
        if ([key isEqualToString:@"DYYYHideVideoProgress"] || 
            [key isEqualToString:@"DYYYisShowScheduleDisplay"] ||
            [key isEqualToString:@"DYYYScheduleStyle"] ||
            [key isEqualToString:@"DYYYProgressLabelColor"] ||
            [key isEqualToString:@"DYYYTimelineVerticalPosition"]) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [self dyplus_updateScheduleLabelsWithCurrentTime:0 totalDuration:0];
            });
        }
    } @catch (NSException *exception) {
        NSLog(@"[DYYY] 处理设置更改异常: %@", exception);
    }
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self name:@"DYYYSettingChanged" object:nil];
    %orig;
}

- (void)layoutSubviews {
    %orig;
    
    if ([[NSUserDefaults standardUserDefaults] boolForKey:@"DYYYisShowScheduleDisplay"]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self dyplus_updateScheduleLabelsWithCurrentTime:0 totalDuration:0];
        });
    }
}

- (void)setAlpha:(CGFloat)alpha {
    if ([[NSUserDefaults standardUserDefaults] boolForKey:@"DYYYisShowScheduleDisplay"]) {
        if ([[NSUserDefaults standardUserDefaults] boolForKey:@"DYYYHideVideoProgress"]) {
            %orig(0);
        } else {
            %orig(1.0);
        }
    } else {
        %orig;
    }
}

- (void)setLimitUpperActionArea:(BOOL)arg1 {
    %orig;
    
    dispatch_async(dispatch_get_main_queue(), ^{
        [self dyplus_updateScheduleLabelsWithCurrentTime:0 totalDuration:0];
    });
}

%end


%hook AWEPlayInteractionProgressController

%new
- (void)dyplus_syncScheduleLabelsWithCurrentTime:(CGFloat)currentTime totalDuration:(CGFloat)totalDuration {
    if (![[NSUserDefaults standardUserDefaults] boolForKey:@"DYYYisShowScheduleDisplay"]) {
        return;
    }

    id progressSlider = self.progressSlider;
    if (!progressSlider) {
        return;
    }

    // 先尝试调用 AWEFeedProgressSlider 的专用方法
    if ([progressSlider respondsToSelector:@selector(dyplus_updateScheduleLabelsWithCurrentTime:totalDuration:)]) {
        [progressSlider dyplus_updateScheduleLabelsWithCurrentTime:currentTime totalDuration:totalDuration];
    }

    // 再调用 legacy fallback 方法（兼容非 AWEFeedProgressSlider 类型的进度条）
    if ([progressSlider isKindOfClass:[UIView class]]) {
        id model = nil;
        if ([self respondsToSelector:@selector(model)]) {
            model = [self valueForKey:@"model"];
        }
        [(UIView *)progressSlider dyplus_updateScheduleLabelsLegacyWithCurrentTime:currentTime totalDuration:totalDuration model:model];
    }
}

- (void)updateProgressSliderWithTime:(CGFloat)arg1 totalDuration:(CGFloat)arg2 {
    %orig;
    [self dyplus_syncScheduleLabelsWithCurrentTime:arg1 totalDuration:arg2];
}

- (void)setHidden:(BOOL)hidden {
    %orig;
    BOOL hideVideoProgress = [[NSUserDefaults standardUserDefaults] boolForKey:@"DYYYHideVideoProgress"];
    BOOL showScheduleDisplay = [[NSUserDefaults standardUserDefaults] boolForKey:@"DYYYisShowScheduleDisplay"];
    if (hideVideoProgress && showScheduleDisplay && !hidden) {
        self.alpha = 0;
    }
}

%end


%hook AWEDProgressCoreContainer

%new
- (void)dyplus_syncScheduleLabelsWithCurrentTime:(CGFloat)currentTime totalDuration:(CGFloat)totalDuration {
    if (![[NSUserDefaults standardUserDefaults] boolForKey:@"DYYYisShowScheduleDisplay"]) {
        return;
    }

    id progressSlider = nil;
    if ([self respondsToSelector:@selector(progressSlider)]) {
        progressSlider = [self valueForKey:@"progressSlider"];
    }
    
    if (!progressSlider) {
        return;
    }

    // 先尝试调用 AWEFeedProgressSlider 的专用方法
    if ([progressSlider respondsToSelector:@selector(dyplus_updateScheduleLabelsWithCurrentTime:totalDuration:)]) {
        [progressSlider dyplus_updateScheduleLabelsWithCurrentTime:currentTime totalDuration:totalDuration];
    }

    // 再调用 legacy fallback 方法（兼容非 AWEFeedProgressSlider 类型的进度条）
    if ([progressSlider isKindOfClass:[UIView class]]) {
        id model = nil;
        if ([self respondsToSelector:@selector(model)]) {
            model = [self valueForKey:@"model"];
        }
        [(UIView *)progressSlider dyplus_updateScheduleLabelsLegacyWithCurrentTime:currentTime totalDuration:totalDuration model:model];
    }
}

- (void)updateProgressSliderWithTime:(CGFloat)arg1 totalDuration:(CGFloat)arg2 {
    %orig;
    [self dyplus_syncScheduleLabelsWithCurrentTime:arg1 totalDuration:arg2];
}

%end
