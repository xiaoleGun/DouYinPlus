#import "Core/Network/DYPlusRemoteConfiguration.h"
static const NSUInteger DYPlusRemoteLimit = 8 * 1024 * 1024;
static NSError *DYPlusRemoteError(NSString *message) {
    return [NSError errorWithDomain:@"DYPlus.RemoteConfiguration" code:1 userInfo:@{NSLocalizedDescriptionKey:message}];
}
NSDictionary *DYPlusDecodeRemoteConfiguration(NSData *data, NSError **error) {
    if (![data isKindOfClass:NSData.class] || !data.length || data.length > DYPlusRemoteLimit) {
        if (error) *error = DYPlusRemoteError(@"配置为空或超过 8MB");
        return nil;
    }
    id object = [NSJSONSerialization JSONObjectWithData:data options:0 error:error];
    if (![object isKindOfClass:NSDictionary.class]) {
        if (error) *error = DYPlusRemoteError(@"配置必须是 JSON 对象");
        return nil;
    }
    return object;
}
static BOOL DYPlusValidRemoteURL(NSURL *url) {
    return [url.scheme.lowercaseString isEqualToString:@"https"] && url.host.length > 0 && !url.user.length && !url.password.length;
}
@interface DYPlusRemoteConfigurationTask : NSObject <NSURLSessionDataDelegate>
@property(nonatomic, strong) NSURLSession *session;
@property(nonatomic, strong) NSMutableData *data;
@property(nonatomic, strong) NSURLResponse *response;
@property(nonatomic, strong) NSError *failure;
@property(nonatomic, copy) void (^completion)(NSData *, NSURLResponse *, NSError *);
@end
@implementation DYPlusRemoteConfigurationTask
- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)task didReceiveResponse:(NSURLResponse *)response completionHandler:(void (^)(NSURLSessionResponseDisposition))completionHandler {
    BOOL valid = [response isKindOfClass:NSHTTPURLResponse.class] && ((NSHTTPURLResponse *)response).statusCode == 200
        && DYPlusValidRemoteURL(response.URL) && response.expectedContentLength <= (int64_t)DYPlusRemoteLimit;
    self.response = response;
    if (!valid) self.failure = DYPlusRemoteError(@"配置响应不是 HTTPS 200，或超过 8MB");
    completionHandler(valid ? NSURLSessionResponseAllow : NSURLSessionResponseCancel);
}
- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)task didReceiveData:(NSData *)data {
    if (data.length > DYPlusRemoteLimit - self.data.length) {
        self.failure = DYPlusRemoteError(@"配置下载超过 8MB");
        [task cancel];
        return;
    }
    [self.data appendData:data];
}
- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task willPerformHTTPRedirection:(NSHTTPURLResponse *)response newRequest:(NSURLRequest *)request completionHandler:(void (^)(NSURLRequest *))completionHandler {
    if (!DYPlusValidRemoteURL(request.URL)) self.failure = DYPlusRemoteError(@"拒绝非 HTTPS 或含凭据的重定向");
    completionHandler(self.failure ? nil : request);
}
- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didCompleteWithError:(NSError *)error {
    void (^completion)(NSData *, NSURLResponse *, NSError *) = self.completion;
    self.completion = nil;
    NSError *failure = self.failure ?: error;
    if (completion) completion(failure ? nil : [self.data copy], self.response, failure);
    [session finishTasksAndInvalidate];
    self.session = nil;
    self.data = nil;
}
@end
void DYPlusFetchRemoteConfiguration(NSURL *url, void (^completion)(NSData *, NSURLResponse *, NSError *)) {
    if (!completion) return;
    if (!DYPlusValidRemoteURL(url)) { completion(nil, nil, DYPlusRemoteError(@"配置地址必须为不含凭据的 HTTPS URL")); return; }
    DYPlusRemoteConfigurationTask *delegate = [DYPlusRemoteConfigurationTask new];
    delegate.completion = completion;
    delegate.data = [NSMutableData data];
    NSURLSessionConfiguration *configuration = NSURLSessionConfiguration.ephemeralSessionConfiguration;
    configuration.timeoutIntervalForRequest = 15;
    configuration.timeoutIntervalForResource = 30;
    configuration.URLCache = nil;
    configuration.HTTPCookieStorage = nil;
    configuration.URLCredentialStorage = nil;
    configuration.requestCachePolicy = NSURLRequestReloadIgnoringLocalCacheData;
    NSOperationQueue *queue = [NSOperationQueue new];
    queue.maxConcurrentOperationCount = 1;
    queue.qualityOfService = NSQualityOfServiceUtility;
    delegate.session = [NSURLSession sessionWithConfiguration:configuration delegate:delegate delegateQueue:queue];
    [[delegate.session dataTaskWithURL:url] resume];
}
