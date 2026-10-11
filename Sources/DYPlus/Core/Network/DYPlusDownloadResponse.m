#import "Core/Network/DYPlusDownloadResponse.h"
#import "Core/Network/DYPlusRemoteConfiguration.h"
static NSDictionary *DYPlusDownloadFail(NSError **error, NSString *message) {
    if (error) *error = [NSError errorWithDomain:@"DYPlus.DownloadResponse" code:1 userInfo:@{NSLocalizedDescriptionKey:message}];
    return nil;
}
static BOOL DYPlusDownloadURL(id text) {
    if (![text isKindOfClass:NSString.class] || [text length] > 8192) return NO;
    NSURL *url = [NSURL URLWithString:text];
    return [url.scheme.lowercaseString isEqualToString:@"https"] && url.host.length && !url.user.length && !url.password.length;
}
NSDictionary *DYPlusDownloadResponse(NSData *data, NSError **error) {
    NSDictionary *json = DYPlusDecodeRemoteConfiguration(data, error);
    if (!json) return nil;
    id code = json[@"code"];
    if (code && ![code isKindOfClass:NSNumber.class] && ![code isKindOfClass:NSString.class]) return DYPlusDownloadFail(error, @"接口状态码格式错误");
    if (code && [code integerValue] != 0 && [code integerValue] != 200) {
        id message = json[@"msg"];
        return DYPlusDownloadFail(error, [message isKindOfClass:NSString.class] ? [message substringToIndex:MIN([message length], 256)] : @"接口返回错误");
    }
    NSDictionary *payload = json[@"data"];
    if (![payload isKindOfClass:NSDictionary.class]) return DYPlusDownloadFail(error, @"接口资源格式错误");
    NSMutableDictionary *result = [NSMutableDictionary dictionary];
    for (NSString *key in @[@"videos", @"images", @"video_list"]) {
        id array = payload[key] ?: @[];
        if (![array isKindOfClass:NSArray.class] || [array count] > 100) return DYPlusDownloadFail(error, @"资源列表格式错误或超过 100 项");
        NSMutableArray *clean = [NSMutableArray array];
        for (id item in array) {
            if ([key isEqualToString:@"images"]) {
                if (!DYPlusDownloadURL(item)) return DYPlusDownloadFail(error, @"图片必须是有效 HTTPS 链接");
                [clean addObject:item];
            } else {
                if (![item isKindOfClass:NSDictionary.class] || !DYPlusDownloadURL(item[@"url"])) return DYPlusDownloadFail(error, @"视频必须是有效 HTTPS 链接");
                id level = item[@"level"] ?: @"默认清晰度";
                if (![level isKindOfClass:NSString.class] || [level length] > 128) return DYPlusDownloadFail(error, @"清晰度名称无效");
                [clean addObject:@{@"url":item[@"url"], @"level":level}];
            }
        }
        result[key] = clean;
    }
    if ([result[@"videos"] count] + [result[@"images"] count] + [result[@"video_list"] count] == 0) return DYPlusDownloadFail(error, @"接口没有可下载资源");
    return result;
}
