#import "Core/Runtime/DYPlusRuntime.h"
#import "Integration/Common/DYPlusHookShared.h"

%hook AWELongVideoControlModel
- (bool)allowDownload {
	return YES;
}
%end

%hook AWELongVideoControlModel
- (long long)preventDownloadType {
	return 0;
}
%end

%hook AWEPlayInteractionProgressContainerView
- (void)layoutSubviews {
	%orig;
	if (DYPlusCachedBool(@"DYYYisEnableFullScreen")) {
		for (UIView *subview in self.subviews) {
			if ([subview class] == [UIView class]) {
				[subview setBackgroundColor:[UIColor clearColor]];
			}
		}
	}
}
%end

%hook AWEDPlayerProgressContainerView
- (void)layoutSubviews {
    %orig;
    if (DYPlusCachedBool(@"DYYYisEnableFullScreen")) {
        for (UIView *subview in self.subviews) {
            if ([subview isMemberOfClass:[UIView class]]) {
                UIColor *bgColor = subview.backgroundColor;
                if (bgColor) {
                    CGFloat h, s, v, a;
                    if ([bgColor getHue:&h saturation:&s brightness:&v alpha:&a]) {
                        if (v < 0.2) {
                            subview.backgroundColor = [UIColor clearColor];
                        }
                    }
                }
            }
        }
    }
}
%end

%hook AFDFastSpeedView
- (void)layoutSubviews {
    %orig;
    if (DYPlusCachedBool(@"DYYYisEnableFullScreen")) {
        for (UIView *subview in self.subviews) {
            if ([subview class] == [UIView class]) {
                [subview setBackgroundColor:[UIColor clearColor]];
            }
        }
    }
}
%end

%hook AWEPlayInteractionCoCreatorNewInfoView
- (void)layoutSubviews {
	if (DYPlusCachedBool(@"DYYYHideGongChuang")) {
		if ([self respondsToSelector:@selector(removeFromSuperview)]) {
			[self removeFromSuperview];
		}
		self.hidden = YES;
		return;
	}
	%orig;
}
%end

%hook AWEPlayInteractionStrongifyShareContentView

- (void)layoutSubviews {
	%orig;

	if (DYPlusCachedBool(@"DYYYHideShareContentView")) {
		UIView *parentView = self.superview;
		if (parentView) {
			parentView.hidden = YES;
		} else {
			self.hidden = YES;
		}
	}
}

%end

%hook AWEPlayInteractionRelatedVideoView
- (void)layoutSubviews {
	if (DYPlusCachedBool(@"DYYYHideBottomRelated")) {
		if ([self respondsToSelector:@selector(removeFromSuperview)]) {
			[self removeFromSuperview];
		}
		self.hidden = YES;
		return;
	}
	%orig;
}
%end

%hook AWEPlayInteractionListenFeedView
- (void)layoutSubviews {
    %orig;

    if (DYPlusCachedBool(@"DYYYHideMusicButton")) {
        [self removeFromSuperview];
        return;
    }
}
%end

%hook AWEPlayInteractionFollowPromptView

- (void)layoutSubviews {
    %orig;

    NSString *accessibilityLabel = self.accessibilityLabel;

    if ([accessibilityLabel isEqualToString:@"关注"]) {
        if (DYPlusCachedBool(@"DYYYHideAvatarButton")) {
            [self removeFromSuperview];
            return;
        }
    }
}

%end

%hook AWEPlayInteractionElementMaskView
- (void)layoutSubviews {
	%orig;

	if (DYPlusCachedBool(@"DYYYHideGradient")) {
		[self removeFromSuperview];
		return;
	}
}
%end

%hook AWEPlayInteractionUserAvatarElement

- (void)onFollowViewClicked:(UITapGestureRecognizer *)gesture {
    if (DYPlusCachedBool(@"DYYYfollowTips")) {
        dispatch_async(dispatch_get_main_queue(), ^{
            UIAlertController *alertController = [UIAlertController
                                                  alertControllerWithTitle:@"关注确认"
                                                  message:@"是否确认关注？"
                                                  preferredStyle:UIAlertControllerStyleAlert];
            
            UIAlertAction *cancelAction = [UIAlertAction
                                           actionWithTitle:@"取消"
                                           style:UIAlertActionStyleCancel
                                           handler:nil];
            
            UIAlertAction *confirmAction = [UIAlertAction
                                            actionWithTitle:@"确定"
                                            style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction * _Nonnull action) {
                %orig(gesture);
            }];
            
            [alertController addAction:cancelAction];
            [alertController addAction:confirmAction];
            
            UIViewController *topController = [DYPlusManager getActiveTopController];
            if (topController) {
                [topController presentViewController:alertController animated:YES completion:nil];
            }
        });
    }else {
        %orig;
    }
}

%end

%hook AWEPlayInteractionUserAvatarFollowController
- (void)onFollowViewClicked:(UITapGestureRecognizer *)gesture {
	if (DYPlusCachedBool(@"DYYYfollowTips")) {

		dispatch_async(dispatch_get_main_queue(), ^{
		UIAlertController *alertController = [UIAlertController
											  alertControllerWithTitle:@"关注确认"
											  message:@"是否确认关注？"
											  preferredStyle:UIAlertControllerStyleAlert];

		UIAlertAction *cancelAction = [UIAlertAction
									   actionWithTitle:@"取消"
									   style:UIAlertActionStyleCancel
									   handler:nil];

		UIAlertAction *confirmAction = [UIAlertAction
										actionWithTitle:@"确定"
										style:UIAlertActionStyleDefault
										handler:^(UIAlertAction * _Nonnull action) {
			%orig(gesture);
		}];

		[alertController addAction:cancelAction];
		[alertController addAction:confirmAction];

		UIViewController *topController = [DYPlusManager getActiveTopController];
		if (topController) {
			[topController presentViewController:alertController animated:YES completion:nil];
		}
		});
	} else {
		%orig;
	}
}

%end

%hook AWEDemaciaChapterProgressSlider

- (void)layoutSubviews {
	%orig;

	if (DYPlusCachedBool(@"DYYYHideChapterProgress")) {
		[self removeFromSuperview];
	}
}

%end

%hook AWEStoryProgressSlideView

- (void)layoutSubviews {
	%orig;

	BOOL shouldHide = DYPlusCachedBool(@"DYYYHideStoryProgressSlide");
	if (!shouldHide)
		return;
	__block UIView *targetView = nil;
	[self.subviews enumerateObjectsUsingBlock:^(__kindof UIView *_Nonnull obj, NSUInteger idx, BOOL *_Nonnull stop) {
	  if ([obj isKindOfClass:NSClassFromString(@"UISlider")] || obj.frame.size.height < 5) {
		  targetView = obj.superview;
		  *stop = YES;
	  }
	}];

	if (targetView) {
		targetView.hidden = YES;
	} else {
	}
}

%end

%hook AWEPlayInteractionUserAvatarElement

- (void)layoutSubviews {
    %orig;
    
    // 检查是否启用了自定义相册图片
    if (DYPlusCachedBool(@"DYYYEnableCustomAlbum")) {
        NSString *customImagePath = DYPlusPreferenceString(@"DYYYCustomAlbumImagePath");
        
        if (customImagePath && [[NSFileManager defaultManager] fileExistsAtPath:customImagePath]) {
            // 查找相册按钮
            for (UIView *subview in self.subviews) {
                if ([subview isKindOfClass:[UIButton class]] && 
                    [subview.accessibilityIdentifier isEqualToString:@"avatar_album_button"]) {
                    
                    UIButton *albumButton = (UIButton *)subview;
                    
                    // 计算按钮大小
                    CGFloat buttonSize = 40.0; // 默认中号
                    
                    if (DYPlusCachedBool(@"DYYYCustomAlbumSizeSmall")) {
                        buttonSize = 30.0;
                    } else if (DYPlusCachedBool(@"DYYYCustomAlbumSizeMedium")) {
                        buttonSize = 40.0;
                    } else if (DYPlusCachedBool(@"DYYYCustomAlbumSizeLarge")) {
                        buttonSize = 50.0;
                    }
                    
                    // 调整按钮尺寸
                    albumButton.frame = CGRectMake(albumButton.frame.origin.x,
                                                  albumButton.frame.origin.y,
                                                  buttonSize,
                                                  buttonSize);
                    
                    // 加载自定义图片
                    UIImage *customImage = [UIImage imageWithContentsOfFile:customImagePath];
                    if (customImage) {
                        // 创建圆形图片
                        UIGraphicsBeginImageContextWithOptions(CGSizeMake(buttonSize, buttonSize), NO, 0);
                        
                        // 创建圆形裁剪路径
                        UIBezierPath *circlePath = [UIBezierPath bezierPathWithOvalInRect:CGRectMake(0, 0, buttonSize, buttonSize)];
                        [circlePath addClip];
                        
                        // 绘制图片铺满整个圆形区域
                        [customImage drawInRect:CGRectMake(0, 0, buttonSize, buttonSize)];
                        
                        UIImage *roundedImage = UIGraphicsGetImageFromCurrentImageContext();
                        UIGraphicsEndImageContext();
                        
                        // 设置自定义图片
                        [albumButton setImage:roundedImage forState:UIControlStateNormal];
                        albumButton.backgroundColor = [UIColor clearColor];
                    }
                    
                    break;
                }
            }
        }
    }
}

%end

%hook AWEPlayInteractionSearchAnchorView

- (void)layoutSubviews {
	%orig;

	if (DYPlusCachedBool(@"DYYYHideInteractionSearch")) {
		[self removeFromSuperview];
		return;
	}
}

%end

%hook AWEPlayInteractionDescriptionScrollView

- (void)layoutSubviews {
	%orig;

	// 重置当前视图的变换矩阵，确保从初始状态开始调整
	self.transform = CGAffineTransformIdentity;

	// 从用户设置中获取描述文本的垂直偏移量
	NSString *descriptionOffsetValue = DYPlusPreferenceString(@"DYYYDescriptionVerticalOffset");
	CGFloat verticalOffset = 0;
	if (descriptionOffsetValue.length > 0) {
		verticalOffset = [descriptionOffsetValue floatValue];
	}

	// 获取父视图和祖父视图
	UIView *parentView = self.superview;
	UIView *grandParentView = nil;

	if (parentView) {
		grandParentView = parentView.superview;
	}

	// 如果找到祖父视图且用户设置了垂直偏移，则应用位移变换
	if (grandParentView && verticalOffset != 0) {
		CGAffineTransform translationTransform = CGAffineTransformMakeTranslation(0, verticalOffset);
		grandParentView.transform = translationTransform;
	}
}

%end

%hook AWEStoryProgressContainerView
- (BOOL)isHidden {
	BOOL originalValue = %orig;
	BOOL customHide = DYPlusCachedBool(@"DYYYHideDotsIndicator");
	return originalValue || customHide;
}

- (void)setHidden:(BOOL)hidden {
	BOOL forceHide = DYPlusCachedBool(@"DYYYHideDotsIndicator");
	%orig(forceHide ? YES : hidden);
}
%end

%hook AWEPlayInteractionUserAvatarView
- (void)layoutSubviews {
	%orig;

	// 检查是否开启了隐藏关注提示的选项
	if (DYPlusCachedBool(@"DYYYHideFollowPromptView")) {
		// 遍历所有子视图
		for (UIView *subview in self.subviews) {
			// 查找普通UIView类型的子视图（这些通常包含提示信息）
			if ([subview isMemberOfClass:[UIView class]]) {
				// 遍历找到的视图中的子视图并将其透明度设为0（隐藏它们）
				for (UIView *childView in subview.subviews) {
					childView.alpha = 0.0;
				}
			}
		}
	}
}
%end

%hook AWEPlayInteractionTemplateButtonGroup
- (void)layoutSubviews {
	if (DYPlusCachedBool(@"DYYYHideTemplateGroup")) {
		if ([self respondsToSelector:@selector(removeFromSuperview)]) {
			[self removeFromSuperview];
		}
		self.hidden = YES;
		return;
	}
	%orig;
}
%end
