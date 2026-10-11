#import "Integration/Common/DYPlusHookShared.h"
#import "Settings/DYPlusBranding.h"
#import "Settings/DYPlusSettingsNavigation.h"

%hook AWESearchAnchorListModel

- (BOOL)hideWords {
	return DYPlusCachedBool(@"DYYYHideCommentViews");
}

- (void)setHideWords:(BOOL)arg1 {
	if (DYPlusCachedBool(@"DYYYHideCommentViews")) {
		%orig(YES);
	} else {
		%orig(arg1);
	}
}

- (void)setScene:(id)arg1 {
	if (DYPlusCachedBool(@"DYYYHideCommentViews")) {
		NSDictionary *customScene = @{@"hideComments" : @YES};
		%orig(customScene);
	} else {
		%orig(arg1);
	}
}
%end

%hook AWEGeneralSearchModel
- (instancetype)initWithDictionary:(id)dict error:(NSError **)error {
	id orig = %orig;

	BOOL noAds = DYPlusGetBool(@"DYYYNoAds");
	if (!noAds || !orig) {
		return orig;
	}

	if ([DYPlusUtils isAdvertisementContainerModel:orig] || [DYPlusUtils isAdvertisementRawData:dict]) {
		return nil;
	}

	return orig;
}
%end

%hook AwemeAdManager
- (void)showAd {
	if (DYPlusCachedBool(@"DYYYNoAds"))
		return;
	%orig;
}
%end

%hook AWEVersionUpdateManager

- (void)startVersionUpdateWorkflow:(id)arg1 completion:(id)arg2 {
	if (DYPlusCachedBool(@"DYYYNoUpdates")) {
		if (arg2) {
			void (^completionBlock)(void) = arg2;
			completionBlock();
		}
	} else {
		%orig;
	}
}

- (id)workflow {
	return DYPlusCachedBool(@"DYYYNoUpdates") ? nil : %orig;
}

- (id)badgeModule {
	return DYPlusCachedBool(@"DYYYNoUpdates") ? nil : %orig;
}

%end

%hook AFDProfileAvatarFunctionManager
- (BOOL)shouldShowSaveAvatarItem {
	BOOL shouldEnable = DYPlusCachedBool(@"DYYYEnableSaveAvatar");
	if (shouldEnable) {
		return YES;
	}
	return %orig;
}
%end

%hook AWESettingsViewModel

- (NSArray *)sectionDataArray {
    NSArray *originalSections = %orig;
    
    BOOL sectionExists = NO;
    for (AWESettingSectionModel *section in originalSections) {
        if ([section.sectionHeaderTitle isEqualToString:DYPlusProductName]) {
            sectionExists = YES;
            break;
        }
    }
    
    if (!sectionExists) {
        AWESettingItemModel *dyplusItem = [[%c(AWESettingItemModel) alloc] init];
        dyplusItem.identifier = DYPlusProductName;
        dyplusItem.title = DYPlusProductName;
        dyplusItem.detail = [@"v" stringByAppendingString:DYPlusProductVersion];
        dyplusItem.type = 0;
        dyplusItem.iconImageName = @"noticesettting_like";
        dyplusItem.cellType = 26;
        dyplusItem.colorStyle = 2;
        dyplusItem.isEnable = YES;
        
        dyplusItem.cellTappedBlock = ^{ DYPlusPresentSettings(self.controllerDelegate); };
        
        AWESettingSectionModel *dyplusSection = [[%c(AWESettingSectionModel) alloc] init];
        dyplusSection.sectionHeaderTitle = DYPlusProductName;
        dyplusSection.sectionHeaderHeight = 40;
        dyplusSection.type = 0;
        dyplusSection.itemArray = @[dyplusItem];
        
        NSMutableArray<AWESettingSectionModel *> *newSections = [NSMutableArray arrayWithArray:originalSections];
        [newSections insertObject:dyplusSection atIndex:0];
        
        return newSections;
    }
    
    return originalSections;
}

%end

%hook AWEIMPhotoPickerFunctionModel

- (void)setUseShadowIcon:(BOOL)arg1 {
	BOOL enabled = DYPlusCachedBool(@"DYYYisAutoSelectOriginalPhoto");
	if (enabled) {
		%orig(YES);
	} else {
		%orig(arg1);
	}
}

- (BOOL)isSelected {
	BOOL enabled = DYPlusCachedBool(@"DYYYisAutoSelectOriginalPhoto");
	if (enabled) {
		return YES;
	}
	return %orig;
}

%end

%hook AWEFeedModuleService
- (BOOL)getFeedIphoneAutoPlayState {
    // 检查是否启用自动播放功能
    BOOL enabled = DYPlusCachedBool(@"DYYYisEnableAutoPlay");
    if (!enabled) {
        return %orig; // 未启用时保持原来的行为
    }
    return YES; // 启用时强制返回YES
}
%end
