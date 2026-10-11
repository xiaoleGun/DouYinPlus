#import <Foundation/Foundation.h>
// Test the real delegate's receive/redirect paths without making external requests.
@interface DYPlusRemoteConfigurationTask : NSObject <NSURLSessionDataDelegate>
@property(nonatomic, strong) NSMutableData *data;
@property(nonatomic, strong) NSURLResponse *response;
@property(nonatomic, strong) NSError *failure;
@property(nonatomic, copy) void (^completion)(NSData *, NSURLResponse *, NSError *);
@end
@interface DYPlusFakeDownloadTask : NSObject
@property(nonatomic) BOOL cancelled;
- (void)cancel;
@end
@implementation DYPlusFakeDownloadTask
- (void)cancel { self.cancelled = YES; }
@end
@interface DYPlusFakeSession : NSObject
- (void)finishTasksAndInvalidate;
@end
@implementation DYPlusFakeSession
- (void)finishTasksAndInvalidate {}
@end

static void Verify(BOOL valid, NSString *name) {
    printf("remote-handler-%s: %s\n", name.UTF8String, valid ? "PASS" : "FAIL"); fflush(stdout);
    if (!valid) exit(1);
}
void DYPlusRunRemoteHandlerRegression(void) {
    NSURLSession *session = (NSURLSession *)(id)[DYPlusFakeSession new];
    NSURLSessionTask *taskReference = (NSURLSessionTask *)(id)[DYPlusFakeDownloadTask new];
    NSURL *url = [NSURL URLWithString:@"https://example.invalid/config.json"];
    DYPlusRemoteConfigurationTask *reader = [DYPlusRemoteConfigurationTask new];
    reader.data = [NSMutableData data];
    NSHTTPURLResponse *response = [[NSHTTPURLResponse alloc] initWithURL:url statusCode:200 HTTPVersion:@"HTTP/1.1" headerFields:@{}];
    __block NSURLSessionResponseDisposition disposition = NSURLSessionResponseCancel;
    [reader URLSession:session dataTask:(NSURLSessionDataTask *)taskReference didReceiveResponse:response completionHandler:^(NSURLSessionResponseDisposition value) { disposition = value; }];
    Verify(disposition == NSURLSessionResponseAllow && !reader.failure, @"https-200");
    NSData *body = [@"{}" dataUsingEncoding:NSUTF8StringEncoding];
    [reader URLSession:session dataTask:(NSURLSessionDataTask *)taskReference didReceiveData:body];
    __block NSUInteger completions = 0;
    __block BOOL roundtrip = NO;
    reader.completion = ^(NSData *data, NSURLResponse *received, NSError *error) { completions++; roundtrip = [data isEqual:body] && !error && received == response; };
    [reader URLSession:session task:taskReference didCompleteWithError:nil];
    [reader URLSession:session task:taskReference didCompleteWithError:nil];
    Verify(roundtrip && completions == 1, @"completion-once");
    reader = [DYPlusRemoteConfigurationTask new]; reader.data = [NSMutableData data];
    response = [[NSHTTPURLResponse alloc] initWithURL:url statusCode:404 HTTPVersion:@"HTTP/1.1" headerFields:@{}];
    [reader URLSession:session dataTask:(NSURLSessionDataTask *)taskReference didReceiveResponse:response completionHandler:^(NSURLSessionResponseDisposition value) { disposition = value; }];
    Verify(disposition == NSURLSessionResponseCancel && reader.failure != nil, @"http-error-rejected");
    reader = [DYPlusRemoteConfigurationTask new]; reader.data = [NSMutableData data];
    response = [[NSHTTPURLResponse alloc] initWithURL:url statusCode:200 HTTPVersion:@"HTTP/1.1" headerFields:@{@"Content-Length":@"8388609"}];
    [reader URLSession:session dataTask:(NSURLSessionDataTask *)taskReference didReceiveResponse:response completionHandler:^(NSURLSessionResponseDisposition value) { disposition = value; }];
    Verify(disposition == NSURLSessionResponseCancel && reader.failure != nil, @"content-length-cap");
    reader = [DYPlusRemoteConfigurationTask new]; reader.data = [NSMutableData data];
    DYPlusFakeDownloadTask *task = [DYPlusFakeDownloadTask new];
    [reader URLSession:session dataTask:(NSURLSessionDataTask *)(id)task didReceiveData:[NSMutableData dataWithLength:8*1024*1024+1]];
    Verify(task.cancelled && reader.failure && reader.data.length == 0, @"streaming-byte-cap");
    reader = [DYPlusRemoteConfigurationTask new]; reader.data = [NSMutableData data];
    __block BOOL redirectRejected = NO;
    [reader URLSession:session task:taskReference willPerformHTTPRedirection:response newRequest:[NSURLRequest requestWithURL:[NSURL URLWithString:@"http://example.invalid/unsafe"]]
        completionHandler:^(NSURLRequest *request) { redirectRejected = request == nil; }];
    Verify(redirectRejected && reader.failure, @"http-redirect-rejected");
    printf("REMOTE HANDLERS: 6 PASS, 0 FAIL\n"); fflush(stdout);
}
