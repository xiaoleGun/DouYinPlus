//
//  DYPlusSpeedHooks.xm
//  DYYY
//
//  倍速 hook（拆分自 DYYY.xm）。
//

#import "Integration/Common/DYPlusMainHooksShared.h"

%hook AWEAwemePlayVideoViewController

- (void)setIsAutoPlay:(BOOL)arg0 {
    %orig(arg0);
    DYPlusApplyPreparedPlaybackSpeedToPlayer(self);
}

%end

%hook AWEPlayInteractionSpeedController

static CGFloat currentLongPressSpeed = 0;
static BOOL isGestureActive = NO;

- (CGFloat)longPressFastSpeedValue {
    float longPressSpeed = DYPlusGetFloat(@"DYYYLongPressSpeed");
    if (longPressSpeed == 0) {
        longPressSpeed = 2.0;
    }
    return longPressSpeed;
}

- (void)changeSpeed:(double)speed {
    float longPressSpeed = DYPlusGetFloat(@"DYYYLongPressSpeed");

    if (isGestureActive && currentLongPressSpeed > 0) {
        %orig(currentLongPressSpeed);
        return;
    }

    if (speed == 2.0 && longPressSpeed != 0 && longPressSpeed != 2.0) {
        %orig(longPressSpeed);
        return;
    }

    if (speed <= 1.0 && dyplusLongPressLockedSpeedActive) {
        DYPlusEndLockedLongPressSpeedAndRestoreIfNeeded();
    }

    %orig(speed);
}

- (void)handleLongPressFastSpeed:(UILongPressGestureRecognizer *)gesture {
    BOOL enableSpeedGesture = DYPlusGetBool(@"DYYYEnableLongPressSpeedGesture");
    CGPoint location = [gesture locationInView:gesture.view];
    static CGFloat initialTouchY = 0;
    BOOL isBeginning = gesture.state == UIGestureRecognizerStateBegan;
    BOOL isEnding = gesture.state == UIGestureRecognizerStateEnded ||
                    gesture.state == UIGestureRecognizerStateCancelled ||
                    gesture.state == UIGestureRecognizerStateFailed;

    if (isBeginning) {
        dyplusLongPressFastSpeedActive = YES;
        dyplusLongPressLockedSpeedActive = NO;
    } else if (isEnding) {
        isGestureActive = NO;
        currentLongPressSpeed = 0;
        initialTouchY = 0;
        dyplusLongPressFastSpeedActive = NO;
    }

    %orig;

    if (isEnding) {
        DYPlusScheduleConfiguredPlaybackSpeedRestore();
    }

    if (!enableSpeedGesture) {
        return;
    }

    if (isBeginning) {
        initialTouchY = location.y;
        isGestureActive = YES;

        float longPressSpeed = DYPlusGetFloat(@"DYYYLongPressSpeed");
        if (longPressSpeed == 0) {
            longPressSpeed = 2.0;
        }
        currentLongPressSpeed = longPressSpeed;
    }
    else if (gesture.state == UIGestureRecognizerStateChanged && isGestureActive) {
        CGFloat deltaY = location.y - initialTouchY;
        CGFloat threshold = 10.0;

        if (fabs(deltaY) > threshold) {
            CGFloat speedChange;
            speedChange = (deltaY > 0) ? 0.25 : -0.25;

            CGFloat newSpeed = currentLongPressSpeed + speedChange;
            newSpeed = MAX(0.5, MIN(3.0, newSpeed));

            if (newSpeed != currentLongPressSpeed) {
                currentLongPressSpeed = newSpeed;
                initialTouchY = location.y;
                [self changeSpeed:currentLongPressSpeed];
            }
        }
    }
}

- (void)handleLongPressLockedSpeedBegan {
    dyplusLongPressFastSpeedActive = YES;
    dyplusLongPressLockedSpeedActive = NO;
    %orig;
}

- (void)handleLongPressLockedDoubleSpeedChanged:(id)arg1 gesture:(UIGestureRecognizer *)gesture {
    dyplusLongPressFastSpeedActive = YES;
    dyplusLongPressLockedSpeedActive = NO;
    %orig(arg1, gesture);
}

- (void)handleLongPressLockedDoubleSpeedEnded:(id)arg1 gesture:(UIGestureRecognizer *)gesture {
    %orig(arg1, gesture);
    dyplusLongPressFastSpeedActive = NO;
    dyplusLongPressLockedSpeedActive = YES;
}

- (void)longPressSpeedControlDidChangeSpeed:(double)speed {
    %orig(speed);
    if (speed <= 1.0 && dyplusLongPressLockedSpeedActive) {
        DYPlusEndLockedLongPressSpeedAndRestoreIfNeeded();
    }
}
%end

%ctor {
    // 初始化本文件的未分组 hook
    %init;
}
