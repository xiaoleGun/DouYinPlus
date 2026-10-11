#import "Core/Storage/DYPlusSettingsArchive.h"
#import <ImageIO/ImageIO.h>
#import <math.h>

static const NSUInteger DYPlusArchiveLimit = 32 * 1024 * 1024;
static const NSUInteger DYPlusValueDataLimit = 8 * 1024 * 1024;
static const NSUInteger DYPlusIconLimit = 4 * 1024 * 1024;

static BOOL DYPlusArchiveFail(NSError **error, NSString *message) {
    if (error) *error = [NSError errorWithDomain:@"DYPlus.SettingsArchive" code:1
                                     userInfo:@{NSLocalizedDescriptionKey:message}];
    return NO;
}

static BOOL DYPlusPreferenceKey(id key) {
    return [key isKindOfClass:NSString.class] && [key hasPrefix:@"DYYY"] && [key length] <= 128
        && ![key isEqualToString:@"DYYYIconsBase64"];
}

static id DYPlusEncodeValue(id value, NSUInteger depth, NSError **error) {
    if (depth > 12) { DYPlusArchiveFail(error, @"设置嵌套过深"); return nil; }
    if ([value isKindOfClass:NSString.class]) {
        if ([value length] <= 256 * 1024) return value;
    } else if ([value isKindOfClass:NSNumber.class]) {
        if (isfinite([value doubleValue])) return value;
    } else if ([value isKindOfClass:NSData.class]) {
        if ([value length] <= DYPlusValueDataLimit) return @{@"type":@"data", @"value":[value base64EncodedStringWithOptions:0]};
    } else if ([value isKindOfClass:NSDate.class]) {
        double seconds = [value timeIntervalSince1970];
        if (isfinite(seconds)) return @{@"type":@"date", @"value":@(seconds)};
    } else if ([value isKindOfClass:NSArray.class] && [value count] <= 1024) {
        NSMutableArray *array = [NSMutableArray array];
        for (id child in value) {
            id encoded = DYPlusEncodeValue(child, depth + 1, error);
            if (!encoded) return nil;
            [array addObject:encoded];
        }
        return @{@"type":@"array", @"value":array};
    } else if ([value isKindOfClass:NSDictionary.class] && [value count] <= 1024) {
        NSMutableDictionary *dictionary = [NSMutableDictionary dictionary];
        for (id key in value) {
            if (![key isKindOfClass:NSString.class] || [key length] > 256) { DYPlusArchiveFail(error, @"字典键无效"); return nil; }
            id encoded = DYPlusEncodeValue(value[key], depth + 1, error);
            if (!encoded) return nil;
            dictionary[key] = encoded;
        }
        return @{@"type":@"dictionary", @"value":dictionary};
    }
    DYPlusArchiveFail(error, @"设置值类型或大小不受支持");
    return nil;
}

static id DYPlusDecodeValue(id value, NSUInteger depth, NSError **error) {
    if (depth > 12) { DYPlusArchiveFail(error, @"设置嵌套过深"); return nil; }
    if ([value isKindOfClass:NSString.class] || [value isKindOfClass:NSNumber.class]) return DYPlusEncodeValue(value, depth, error);
    if (![value isKindOfClass:NSDictionary.class] || [value count] != 2) { DYPlusArchiveFail(error, @"设置值格式无效"); return nil; }
    id type = value[@"type"], payload = value[@"value"];
    if (![type isKindOfClass:NSString.class]) { DYPlusArchiveFail(error, @"设置值缺少类型"); return nil; }
    if ([type isEqualToString:@"data"] && [payload isKindOfClass:NSString.class]
        && [payload length] <= ((DYPlusValueDataLimit + 2) / 3) * 4) {
        NSData *data = [[NSData alloc] initWithBase64EncodedString:payload options:0];
        if (data && data.length <= DYPlusValueDataLimit) return data;
    } else if ([type isEqualToString:@"date"] && [payload isKindOfClass:NSNumber.class] && isfinite([payload doubleValue])) {
        return [NSDate dateWithTimeIntervalSince1970:[payload doubleValue]];
    } else if ([type isEqualToString:@"array"] && [payload isKindOfClass:NSArray.class] && [payload count] <= 1024) {
        NSMutableArray *array = [NSMutableArray array];
        for (id item in payload) {
            id decoded = DYPlusDecodeValue(item, depth + 1, error);
            if (!decoded) return nil;
            [array addObject:decoded];
        }
        return array;
    } else if ([type isEqualToString:@"dictionary"] && [payload isKindOfClass:NSDictionary.class] && [payload count] <= 1024) {
        NSMutableDictionary *dictionary = [NSMutableDictionary dictionary];
        for (id key in payload) {
            if (![key isKindOfClass:NSString.class] || [key length] > 256) { DYPlusArchiveFail(error, @"字典键无效"); return nil; }
            id decoded = DYPlusDecodeValue(payload[key], depth + 1, error);
            if (!decoded) return nil;
            dictionary[key] = decoded;
        }
        return dictionary;
    }
    DYPlusArchiveFail(error, @"设置值格式或大小无效");
    return nil;
}

static BOOL DYPlusValidIcon(NSData *data) {
    if (![data isKindOfClass:NSData.class] || !data.length || data.length > DYPlusIconLimit) return NO;
    CGImageSourceRef source = CGImageSourceCreateWithData((__bridge CFDataRef)data, NULL);
    if (!source) return NO;
    CFStringRef type = CGImageSourceGetType(source);
    BOOL staticPNG = type && CGImageSourceGetCount(source) == 1 && CFEqual(type, CFSTR("public.png"));
    NSDictionary *properties = CFBridgingRelease(CGImageSourceCopyPropertiesAtIndex(source, 0, NULL));
    CFRelease(source);
    long long width = [properties[(__bridge NSString *)kCGImagePropertyPixelWidth] longLongValue];
    long long height = [properties[(__bridge NSString *)kCGImagePropertyPixelHeight] longLongValue];
    return staticPNG && width > 0 && height > 0 && width <= 2048 && height <= 2048;
}

@interface DYPlusSettingsArchive ()
@property(nonatomic, copy, readwrite) NSDictionary<NSString *, id> *preferences;
@property(nonatomic, copy, readwrite) NSDictionary<NSString *, NSData *> *icons;
@end

@implementation DYPlusSettingsArchive

+ (NSArray<NSString *> *)allowedIconNames {
    return @[@"like_before.png", @"like_after.png", @"comment.png", @"unfavorite.png",
             @"favorite.png", @"share.png", @"qingping.png", @"custom_album_image.png"];
}

+ (NSData *)readFileURL:(NSURL *)url error:(NSError **)error {
    if (!url.isFileURL) { DYPlusArchiveFail(error, @"只能导入本地文件"); return nil; }
    BOOL access = [url startAccessingSecurityScopedResource];
    NSInputStream *stream = [NSInputStream inputStreamWithURL:url];
    NSMutableData *data = [NSMutableData data];
    @try {
        [stream open];
        uint8_t buffer[64 * 1024];
        NSInteger length;
        while ((length = [stream read:buffer maxLength:sizeof(buffer)]) > 0) {
            if (data.length + (NSUInteger)length > DYPlusArchiveLimit) { DYPlusArchiveFail(error, @"备份文件超过 32MB"); return nil; }
            [data appendBytes:buffer length:(NSUInteger)length];
        }
        if (length < 0) { if (error) *error = stream.streamError; return nil; }
        return data;
    } @finally {
        [stream close];
        if (access) [url stopAccessingSecurityScopedResource];
    }
}

+ (instancetype)decodeData:(NSData *)data error:(NSError **)error {
    if (![data isKindOfClass:NSData.class] || !data.length || data.length > DYPlusArchiveLimit) { DYPlusArchiveFail(error, @"备份为空或超过 32MB"); return nil; }
    id root = [NSJSONSerialization JSONObjectWithData:data options:0 error:error];
    if (![root isKindOfClass:NSDictionary.class]) { DYPlusArchiveFail(error, @"备份必须是 JSON 对象"); return nil; }
    // 新品牌导出使用 DYPlus，旧 DouYinPlus v1 和 DYYY 扁平格式继续可读。
    id version = root[@"DYPlusArchiveVersion"] ?: root[@"DouYinPlusArchiveVersion"];
    BOOL modern = version != nil;
    if (modern && (![version isEqual:@1] || [root count] != 3 ||
        ![root[@"icons"] isKindOfClass:NSDictionary.class])) { DYPlusArchiveFail(error, @"备份版本不受支持"); return nil; }
    id settings = modern ? root[@"preferences"] : root;
    id encodedIcons = modern ? root[@"icons"] : root[@"DYYYIconsBase64"];
    if (![settings isKindOfClass:NSDictionary.class] || [settings count] > 1024
        || (encodedIcons && ![encodedIcons isKindOfClass:NSDictionary.class])) { DYPlusArchiveFail(error, @"备份结构无效"); return nil; }
    NSMutableDictionary *preferences = [NSMutableDictionary dictionary];
    for (id key in settings) {
        if (!modern && [key isEqualToString:@"DYYYIconsBase64"]) continue;
        if (!DYPlusPreferenceKey(key)) { DYPlusArchiveFail(error, @"备份包含非插件设置键"); return nil; }
        id value = modern ? DYPlusDecodeValue(settings[key], 0, error) : settings[key];
        if (!value || !DYPlusEncodeValue(value, 0, error)) return nil;
        preferences[key] = value;
    }
    NSMutableDictionary *icons = [NSMutableDictionary dictionary];
    if ([encodedIcons count] > self.allowedIconNames.count) { DYPlusArchiveFail(error, @"图标数量过多"); return nil; }
    for (id name in encodedIcons) {
        id string = encodedIcons[name];
        if (![self.allowedIconNames containsObject:name] || ![string isKindOfClass:NSString.class]
            || [string length] > ((DYPlusIconLimit + 2) / 3) * 4) { DYPlusArchiveFail(error, @"图标文件名或大小无效"); return nil; }
        NSData *image = [[NSData alloc] initWithBase64EncodedString:string options:0];
        if (!DYPlusValidIcon(image)) { DYPlusArchiveFail(error, @"图标损坏或超过 2048 像素 / 4MB"); return nil; }
        icons[name] = image;
    }
    DYPlusSettingsArchive *archive = [self new];
    archive.preferences = preferences;
    archive.icons = icons;
    return archive;
}

+ (NSData *)encodePreferences:(NSDictionary *)preferences icons:(NSDictionary<NSString *,NSData *> *)icons error:(NSError **)error {
    if (preferences.count > 1024) { DYPlusArchiveFail(error, @"设置数量过多"); return nil; }
    NSMutableDictionary *encoded = [NSMutableDictionary dictionary];
    for (id key in preferences) {
        if (!DYPlusPreferenceKey(key)) { DYPlusArchiveFail(error, @"只能备份插件设置"); return nil; }
        id value = DYPlusEncodeValue(preferences[key], 0, error);
        if (!value) return nil;
        encoded[key] = value;
    }
    NSMutableDictionary *images = [NSMutableDictionary dictionary];
    for (NSString *name in icons) {
        if (![self.allowedIconNames containsObject:name] || !DYPlusValidIcon(icons[name])) { DYPlusArchiveFail(error, @"图标损坏或过大，请先更换较小图片"); return nil; }
        images[name] = [icons[name] base64EncodedStringWithOptions:0];
    }
    NSData *data = [NSJSONSerialization dataWithJSONObject:@{@"DYPlusArchiveVersion":@1, @"preferences":encoded, @"icons":images}
                                                 options:NSJSONWritingPrettyPrinted error:error];
    if (data.length > DYPlusArchiveLimit) { DYPlusArchiveFail(error, @"备份文件超过 32MB"); return nil; }
    return data;
}

- (BOOL)applyToDefaults:(NSUserDefaults *)defaults iconsDirectory:(NSString *)directory error:(NSError **)error {
    if (!defaults || !directory.isAbsolutePath) return DYPlusArchiveFail(error, @"恢复目标无效");
    NSFileManager *files = NSFileManager.defaultManager;
    for (NSString *key in self.preferences) {
        if (!DYPlusPreferenceKey(key) || ![NSPropertyListSerialization propertyList:self.preferences[key] isValidForFormat:NSPropertyListBinaryFormat_v1_0])
            return DYPlusArchiveFail(error, @"设置值不可写入");
    }
    if ([[files attributesOfItemAtPath:directory error:nil][NSFileType] isEqual:NSFileTypeSymbolicLink])
        return DYPlusArchiveFail(error, @"图标目录不能是符号链接");
    if (![files createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:error]) return NO;
    NSString *root = [directory stringByResolvingSymlinksInPath];
    NSMutableDictionary *oldIcons = [NSMutableDictionary dictionary];
    NSMutableDictionary *oldPreferences = [NSMutableDictionary dictionary];
    for (NSString *name in self.icons) {
        NSString *path = [directory stringByAppendingPathComponent:name];
        NSDictionary *attributes = [files attributesOfItemAtPath:path error:nil];
        if (![self.class.allowedIconNames containsObject:name] || [attributes[NSFileType] isEqual:NSFileTypeSymbolicLink]
            || (attributes && ![attributes[NSFileType] isEqual:NSFileTypeRegular])
            || ![[path stringByResolvingSymlinksInPath] hasPrefix:[root stringByAppendingString:@"/"]])
            return DYPlusArchiveFail(error, @"图标目标路径无效");
        if ([attributes fileSize] > DYPlusArchiveLimit) return DYPlusArchiveFail(error, @"现有图标过大，无法安全回滚");
        NSData *data = attributes ? [NSData dataWithContentsOfFile:path options:NSDataReadingMappedIfSafe error:error] : nil;
        if (attributes && !data) return NO;
        oldIcons[name] = data ?: (id)NSNull.null;
    }
    for (NSString *key in self.preferences) oldPreferences[key] = [defaults objectForKey:key] ?: (id)NSNull.null;
    NSMutableArray *written = [NSMutableArray array];
    BOOL success = YES;
    @try {
        for (NSString *name in self.icons) {
            if (![self.icons[name] writeToFile:[directory stringByAppendingPathComponent:name] options:NSDataWritingAtomic error:error]) { success = NO; break; }
            [written addObject:name];
        }
        if (success) for (NSString *key in self.preferences) {
            if ([key isEqualToString:@"DYYYCustomAlbumImagePath"]) {
                NSString *path = [directory stringByAppendingPathComponent:@"custom_album_image.png"];
                if ([files fileExistsAtPath:path]) [defaults setObject:path forKey:key];
                else [defaults removeObjectForKey:key];
            } else [defaults setObject:self.preferences[key] forKey:key];
        }
    } @catch (__unused NSException *exception) { success = DYPlusArchiveFail(error, @"设置恢复失败"); }
    if (!success) {
        for (NSString *key in oldPreferences) {
            id value = oldPreferences[key];
            if (value == NSNull.null) [defaults removeObjectForKey:key]; else [defaults setObject:value forKey:key];
        }
        for (NSString *name in written) {
            NSString *path = [directory stringByAppendingPathComponent:name];
            id data = oldIcons[name];
            if (data == NSNull.null) [files removeItemAtPath:path error:nil]; else [data writeToFile:path atomically:YES];
        }
    }
    return success;
}
@end
