#import <UIKit/UIKit.h>
#import "Core/Runtime/DYPlusRuntime.h"
#import "Core/Storage/DYPlusSettingsArchive.h"
#import "Core/Utilities/DYPlusUtils.h"
#import "Core/Storage/DYPlusPaths.h"
#import "Core/UI/DYPlusColorParser.h"
#import "Core/Network/DYPlusRemoteConfiguration.h"
#import "Core/UI/DYPlusUIContext.h"
#import "Core/Network/DYPlusDownloadResponse.h"

static NSUInteger checks;
static void Require(NSString *name, BOOL condition) {
    checks++;
    printf("core-%s: %s\n", name.UTF8String, condition ? "PASS" : "FAIL");
    fflush(stdout);
    if (!condition) exit(1);
}
static NSData *JSON(id object) { return [NSJSONSerialization dataWithJSONObject:object options:0 error:nil]; }
static DYPlusSettingsArchive *Decode(id object) { return [DYPlusSettingsArchive decodeData:JSON(object) error:nil]; }

@interface DYPlusFakePlayer : NSObject
- (BOOL)scalar;
- (NSInteger)integer;
- (NSNumber *)boxed;
- (NSString *)text;
- (double)unsupported;
- (id)badObject;
- (BOOL)throwing;
@end
@implementation DYPlusFakePlayer
- (BOOL)scalar { return YES; }
- (NSInteger)integer { return -1; }
- (NSNumber *)boxed { return @NO; }
- (NSString *)text { return @"YES"; }
- (double)unsupported { return 1.0; }
- (id)badObject { return @[]; }
- (BOOL)throwing { [NSException raise:@"Test" format:@"expected"]; return NO; }
@end

@interface DYPlusFailingDefaults : NSUserDefaults
@property(nonatomic) BOOL failOnce;
@end
@implementation DYPlusFailingDefaults
- (void)setObject:(id)object forKey:(NSString *)key {
    if (self.failOnce && [key isEqualToString:@"DYYYFail"]) {
        self.failOnce = NO;
        [NSException raise:@"Test" format:@"simulated preference write failure"];
    }
    [super setObject:object forKey:key];
}
@end

void DYPlusRunCoreRegressionTests(void) {
    checks = 0;
    Require(@"download-response-valid", DYPlusDownloadResponse(JSON(@{@"code":@200, @"data":@{@"images":@[@"https://example.invalid/image.jpg"]}}), nil) != nil);
    Require(@"download-response-array-root", DYPlusDownloadResponse(JSON(@[]), nil) == nil);
    Require(@"download-response-null-code", DYPlusDownloadResponse(JSON(@{@"code":NSNull.null, @"data":@{}}), nil) == nil);
    Require(@"download-response-null-payload", DYPlusDownloadResponse(JSON(@{@"data":NSNull.null}), nil) == nil);
    Require(@"download-response-malformed-list", DYPlusDownloadResponse(JSON(@{@"data":@{@"images":@"not array"}}), nil) == nil);
    Require(@"download-response-null-item", DYPlusDownloadResponse(JSON(@{@"data":@{@"videos":@[NSNull.null]}}), nil) == nil);
    Require(@"download-response-file-url", DYPlusDownloadResponse(JSON(@{@"data":@{@"images":@[@"file:///tmp/example"]}}), nil) == nil);
    Require(@"download-response-http-url", DYPlusDownloadResponse(JSON(@{@"data":@{@"images":@[@"http://example.invalid/image"]}}), nil) == nil);
    Require(@"download-response-null-level", DYPlusDownloadResponse(JSON(@{@"data":@{@"videos":@[@{@"url":@"https://example.invalid/video", @"level":NSNull.null}]}}), nil) == nil);
    Require(@"active-window", DYPlusActiveWindow() != nil);
    UIViewController *visible = [UIViewController new];
    UINavigationController *navigation = [[UINavigationController alloc] initWithRootViewController:visible];
    UITabBarController *tabs = [UITabBarController new];
    tabs.viewControllers = @[navigation];
    Require(@"nested-navigation-context", DYPlusVisibleViewController(tabs) == visible);
    Require(@"nil-navigation-context", DYPlusVisibleViewController(nil) == nil);
    Require(@"remote-object-valid", [DYPlusDecodeRemoteConfiguration(JSON(@{@"x":@1}), nil) isEqual:@{@"x":@1}]);
    Require(@"remote-array-rejected", DYPlusDecodeRemoteConfiguration(JSON(@[]), nil) == nil);
    Require(@"remote-over-8MB-rejected", DYPlusDecodeRemoteConfiguration([NSMutableData dataWithLength:8*1024*1024+1], nil) == nil);
    __block BOOL invalidURL = NO;
    DYPlusFetchRemoteConfiguration([NSURL URLWithString:@"http://example.com"], ^(NSData *data, NSURLResponse *response, NSError *error) { invalidURL = error != nil && data == nil; });
    Require(@"remote-http-rejected", invalidURL);
    __block BOOL credentials = NO;
    DYPlusFetchRemoteConfiguration([NSURL URLWithString:@"https://user:password@example.com"], ^(NSData *data, NSURLResponse *response, NSError *error) { credentials = error != nil; });
    Require(@"remote-url-credentials-rejected", credentials);
    CGFloat red = 0, green = 0, blue = 0, alpha = 0;
    UIColor *color = DYPlusColorFromString(@"#80FF0000");
    [color getRed:&red green:&green blue:&blue alpha:&alpha];
    Require(@"color-argb", red == 1 && green == 0 && blue == 0 && fabs(alpha - 128/255.0) < 0.001);
    Require(@"color-short-hex", [DYPlusColorFromString(@"#f00") isEqual:DYPlusColorFromString(@"ff0000")]);
    Require(@"color-invalid-fallback", [DYPlusColorFromString(@"gggggggg") isEqual:UIColor.blackColor]);
    Require(@"color-nil-fallback", [DYPlusColorFromString(nil) isEqual:UIColor.blackColor]);
    Require(@"color-gradient-cached", DYPlusColorFromString(@"rainbow") == DYPlusColorFromString(@"rainbow"));
    Require(@"color-nested-pattern-safe", DYPlusColorFromString(@"rainbow,#ff0000") != nil);
    DYPlusFakePlayer *player = [DYPlusFakePlayer new];
    BOOL value = NO;
    Require(@"BOOL-selector", DYPlusReadBooleanSelector(player, @selector(scalar), &value) && value);
    Require(@"integer-selector", DYPlusReadBooleanSelector(player, @selector(integer), &value) && value);
    Require(@"NSNumber-selector", DYPlusReadBooleanSelector(player, @selector(boxed), &value) && !value);
    Require(@"NSString-selector", DYPlusReadBooleanSelector(player, @selector(text), &value) && value);
    Require(@"reject-double-selector", !DYPlusReadBooleanSelector(player, @selector(unsupported), &value));
    Require(@"reject-object-selector", !DYPlusReadBooleanSelector(player, @selector(badObject), &value));
    Require(@"missing-selector", !DYPlusReadBooleanSelector(player, NSSelectorFromString(@"missing"), &value));
    Require(@"throwing-selector", !DYPlusReadBooleanSelector(player, @selector(throwing), &value));
    Require(@"nil-selector-target", !DYPlusReadBooleanSelector(nil, @selector(scalar), &value));
    Require(@"null-selector-result", !DYPlusReadBooleanSelector(player, @selector(scalar), NULL));

    NSData *oldColor = [NSKeyedArchiver archivedDataWithRootObject:UIColor.redColor requiringSecureCoding:NO error:nil];
    Require(@"legacy-color", DYPlusUnarchiveColor(oldColor) != nil);
    Require(@"malformed-color", DYPlusUnarchiveColor([@"not archive" dataUsingEncoding:NSUTF8StringEncoding]) == nil);
    NSData *wrongColor = [NSKeyedArchiver archivedDataWithRootObject:@{@"x":@1} requiringSecureCoding:YES error:nil];
    Require(@"wrong-color-class", DYPlusUnarchiveColor(wrongColor) == nil);
    NSData *stats = [NSKeyedArchiver archivedDataWithRootObject:@{@"good":@2, @"negative":@-1, @"tooMuch":@1000000001, @"bad":@"x"} requiringSecureCoding:YES error:nil];
    Require(@"safe-stats-filter", [DYPlusUnarchiveUsageStats(stats) isEqual:@{@"good":@2}]);
    Require(@"nil-stats", DYPlusUnarchiveUsageStats(nil).count == 0);

    NSDictionary *original = @{@"DYYYBool":@YES, @"DYYYNumber":@1.25, @"DYYYText":@"测试",
        @"DYYYData":oldColor, @"DYYYDate":[NSDate dateWithTimeIntervalSince1970:12345],
        @"DYYYArray":@[@1, oldColor], @"DYYYDictionary":@{@"type":@"data", @"value":@"ordinary", @"nested":@[@2]}};
    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(4, 4)];
    NSData *png = [renderer PNGDataWithActions:^(UIGraphicsImageRendererContext *context) { [UIColor.redColor setFill]; UIRectFill(CGRectMake(0,0,4,4)); }];
    NSData *encoded = [DYPlusSettingsArchive encodePreferences:original icons:@{@"like_before.png":png} error:nil];
    DYPlusSettingsArchive *archive = [DYPlusSettingsArchive decodeData:encoded error:nil];
    NSMutableDictionary *envelope = [[NSJSONSerialization JSONObjectWithData:encoded options:0 error:nil] mutableCopy];
    Require(@"dyplus-export-marker", [envelope[@"DYPlusArchiveVersion"] isEqual:@1] && !envelope[@"DouYinPlusArchiveVersion"]);
    envelope[@"DouYinPlusArchiveVersion"] = envelope[@"DYPlusArchiveVersion"];
    [envelope removeObjectForKey:@"DYPlusArchiveVersion"];
    Require(@"douyinplus-v1-compatible", [Decode(envelope).preferences isEqual:original]);
    envelope[@"DYPlusArchiveVersion"] = @1;
    Require(@"reject-ambiguous-brand-markers", Decode(envelope) == nil);
    Require(@"legacy-data-directory-kept", [[DYPlusPaths dyplusRootDir].lastPathComponent isEqual:@"DYYY"]);
    Require(@"archive-roundtrip-binary-date-nesting", [archive.preferences isEqual:original]);
    Require(@"archive-roundtrip-icons", [archive.icons[@"like_before.png"] isEqual:png]);
    Require(@"legacy-json-compatible", [Decode(@{@"DYYYBool":@YES, @"DYYYText":@"x"}).preferences isEqual:@{@"DYYYBool":@YES, @"DYYYText":@"x"}]);
    Require(@"legacy-icons-compatible", Decode(@{@"DYYYIconsBase64":@{@"like_before.png":[png base64EncodedStringWithOptions:0]}}).icons.count == 1);
    Require(@"reject-host-preferences", Decode(@{@"HostAccount":@"evil"}) == nil);
    Require(@"reject-array-root", Decode(@[]) == nil);
    Require(@"reject-null-value", Decode(@{@"DYYYx":NSNull.null}) == nil);
    Require(@"reject-traversal-icon", Decode(@{@"DYYYIconsBase64":@{@"../outside.png":[png base64EncodedStringWithOptions:0]}}) == nil);
    Require(@"reject-absolute-icon", Decode(@{@"DYYYIconsBase64":@{@"/tmp/outside.png":[png base64EncodedStringWithOptions:0]}}) == nil);
    Require(@"reject-unknown-icon", Decode(@{@"DYYYIconsBase64":@{@"unknown.png":[png base64EncodedStringWithOptions:0]}}) == nil);
    Require(@"reject-invalid-base64", Decode(@{@"DYYYIconsBase64":@{@"like_before.png":@"!!!"}}) == nil);
    Require(@"reject-invalid-image", Decode(@{@"DYYYIconsBase64":@{@"like_before.png":@"YWJj"}}) == nil);
    Require(@"reject-extra-modern-keys", Decode(@{@"DouYinPlusArchiveVersion":@1, @"preferences":@{}, @"unexpected":@{}}) == nil);
    Require(@"reject-future-version", Decode(@{@"DouYinPlusArchiveVersion":@2, @"preferences":@{}, @"icons":@{}}) == nil);
    Require(@"reject-unknown-type", Decode(@{@"DouYinPlusArchiveVersion":@1, @"preferences":@{@"DYYYx":@{@"type":@"unknown", @"value":@1}}, @"icons":@{}}) == nil);
    id deep = @"x"; for (int index=0;index<15;index++) deep = @[deep];
    Require(@"reject-deep-value", Decode(@{@"DYYYDeep":deep}) == nil);
    Require(@"reject-data-over-8MB", [DYPlusSettingsArchive encodePreferences:@{@"DYYYData":[NSMutableData dataWithLength:8*1024*1024+1]} icons:@{} error:nil] == nil);
    Require(@"reject-archive-over-32MB", [DYPlusSettingsArchive decodeData:[NSMutableData dataWithLength:32*1024*1024+1] error:nil] == nil);
    Require(@"reject-http-file-import", [DYPlusSettingsArchive readFileURL:[NSURL URLWithString:@"https://example.com"] error:nil] == nil);
    Require(@"reject-NaN-value", [DYPlusSettingsArchive encodePreferences:@{@"DYYYFloat":@(NAN)} icons:@{} error:nil] == nil);
    Require(@"reject-key-over-128", Decode(@{[@"DYYY" stringByPaddingToLength:129 withString:@"x" startingAtIndex:0]:@1}) == nil);

    NSFileManager *files = NSFileManager.defaultManager;
    NSString *directory = [[DYPlusPaths tempDir] stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
    [files createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:nil];
    NSString *iconDirectory = [directory stringByAppendingPathComponent:@"Icons"];
    DYPlusFailingDefaults *defaults = [[DYPlusFailingDefaults alloc] initWithSuiteName:@"com.xiaolegun.dyplus.regression-fixtures"];
    [defaults setObject:@"keep" forKey:@"HostAccount"];
    Require(@"apply-valid-archive", [archive applyToDefaults:defaults iconsDirectory:iconDirectory error:nil]);
    Require(@"host-defaults-preserved", [[defaults stringForKey:@"HostAccount"] isEqual:@"keep"]);
    Require(@"binary-defaults-preserved", [[defaults dataForKey:@"DYYYData"] isEqual:oldColor]);
    Require(@"icon-written", [[NSData dataWithContentsOfFile:[iconDirectory stringByAppendingPathComponent:@"like_before.png"]] isEqual:png]);
    NSString *outside = [directory stringByAppendingPathComponent:@"outside.png"];
    [@"unchanged" writeToFile:outside atomically:YES encoding:NSUTF8StringEncoding error:nil];
    NSString *linkRoot = [directory stringByAppendingPathComponent:@"Linked"];
    [files createSymbolicLinkAtPath:linkRoot withDestinationPath:iconDirectory error:nil];
    Require(@"reject-symlink-directory", ![archive applyToDefaults:defaults iconsDirectory:linkRoot error:nil]);
    NSString *iconPath = [iconDirectory stringByAppendingPathComponent:@"like_before.png"];
    [files removeItemAtPath:iconPath error:nil];
    [files createSymbolicLinkAtPath:iconPath withDestinationPath:outside error:nil];
    Require(@"reject-symlink-icon", ![archive applyToDefaults:defaults iconsDirectory:iconDirectory error:nil]);
    Require(@"outside-file-preserved", [[NSString stringWithContentsOfFile:outside encoding:NSUTF8StringEncoding error:nil] isEqual:@"unchanged"]);
    [files removeItemAtPath:iconPath error:nil];
    [png writeToFile:iconPath atomically:YES];
    [defaults setObject:@9 forKey:@"DYYYFail"];
    defaults.failOnce = YES;
    NSData *bluePNG = [renderer PNGDataWithActions:^(UIGraphicsImageRendererContext *context) { [UIColor.blueColor setFill]; UIRectFill(CGRectMake(0,0,4,4)); }];
    Require(@"rollback-fixture-different", ![bluePNG isEqual:png]);
    DYPlusSettingsArchive *failArchive = [DYPlusSettingsArchive decodeData:[DYPlusSettingsArchive encodePreferences:@{@"DYYYFail":@2} icons:@{@"like_before.png":bluePNG} error:nil] error:nil];
    Require(@"write-exception-reported", ![failArchive applyToDefaults:defaults iconsDirectory:iconDirectory error:nil]);
    Require(@"preferences-rolled-back", [defaults integerForKey:@"DYYYFail"] == 9);
    Require(@"icons-rolled-back", [[NSData dataWithContentsOfFile:iconPath] isEqual:png]);
    [defaults removePersistentDomainForName:@"com.xiaolegun.dyplus.regression-fixtures"];

    NSUserDefaults *standard = NSUserDefaults.standardUserDefaults;
    [standard setObject:@[@"invalid"] forKey:@"DYYYRegressionTyped"];
    Require(@"uncached-string-reject-array", DYPlusPreferenceString(@"DYYYRegressionTyped") == nil);
    [standard setObject:@2.5 forKey:@"DYYYRegressionNumber"];
    Require(@"uncached-string-legacy-number", [DYPlusPreferenceString(@"DYYYRegressionNumber") isEqual:@"2.5"]);
    [standard removeObjectForKey:@"DYYYRegressionNumber"];
    DYPlusConfigCacheInvalidate();
    Require(@"typed-cache-reject-array", !DYPlusCachedBool(@"DYYYRegressionTyped") && DYPlusCachedInteger(@"DYYYRegressionTyped")==0 && DYPlusCachedString(@"DYYYRegressionTyped").length==0);
    [standard setObject:@"old" forKey:@"DYYYRegressionTyped"];
    DYPlusConfigCacheInvalidate();
    Require(@"typed-cache-first-read", [DYPlusCachedString(@"DYYYRegressionTyped") isEqual:@"old"]);
    [standard setObject:@"new" forKey:@"DYYYRegressionTyped"];
    Require(@"typed-cache-hit", [DYPlusCachedString(@"DYYYRegressionTyped") isEqual:@"old"]);
    DYPlusConfigCacheInvalidate();
    Require(@"typed-cache-invalidation", [DYPlusCachedString(@"DYYYRegressionTyped") isEqual:@"new"]);
    [standard setObject:@" one, two ,,  " forKey:@"DYYYRegressionTyped"];
    DYPlusConfigCacheInvalidate();
    Require(@"keyword-trimming", [DYPlusCachedKeywordList(@"DYYYRegressionTyped") isEqual:@[@"one", @"two"]]);
    dispatch_apply(2000, dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0), ^(size_t index) {
        if (index % 11 == 0) DYPlusConfigCacheInvalidate(); else { DYPlusCachedBool(@"DYYYRegressionTyped"); DYPlusCachedKeywordList(@"DYYYRegressionTyped"); }
    });
    Require(@"cache-concurrent-no-deadlock", YES);
    [standard removeObjectForKey:@"DYYYRegressionTyped"];
    DYPlusConfigCacheInvalidate();

    __weak UIViewController *released = nil;
    @autoreleasepool {
        UIViewController *root = [UIViewController new];
        released = root;
        UIViewController *child = [UIViewController new];
        Require(@"hierarchy-root", DYPlusAllViewControllersInHierarchy(root).count == 1);
        [root addChildViewController:child];
        Require(@"hierarchy-fresh", DYPlusAllViewControllersInHierarchy(root).count == 2);
        [child removeFromParentViewController];
        Require(@"hierarchy-removal-fresh", DYPlusAllViewControllersInHierarchy(root).count == 1);
    }
    Require(@"hierarchy-not-retained", released == nil);

    NSString *preserved = [[DYPlusPaths dyplusRootDir] stringByAppendingPathComponent:@"regression-preserved.txt"];
    [@"keep" writeToFile:preserved atomically:YES encoding:NSUTF8StringEncoding error:nil];
    NSString *tempLink = [[DYPlusPaths tempDir] stringByAppendingPathComponent:@"external-link"];
    [files createSymbolicLinkAtPath:tempLink withDestinationPath:preserved error:nil];
    Require(@"cleanup-reject-broad-directory", [DYPlusUtils clearDirectoryContents:[DYPlusPaths dyplusRootDir]] == 0);
    Require(@"cleanup-preserves-root-file", [files fileExistsAtPath:preserved]);
    [DYPlusUtils clearDirectoryContents:[DYPlusPaths tempDir]];
    Require(@"cleanup-does-not-follow-symlink", [files fileExistsAtPath:preserved] && ![files fileExistsAtPath:directory]);
    [files removeItemAtPath:preserved error:nil];
    printf("CORE SUMMARY: %lu PASS, 0 FAIL\n", (unsigned long)checks); fflush(stdout);
}
