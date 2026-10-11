#import <Foundation/Foundation.h>
#ifdef __cplusplus
extern "C" {
#endif
NSDictionary *DYPlusDecodeRemoteConfiguration(NSData *data, NSError **error);
void DYPlusFetchRemoteConfiguration(NSURL *url, void (^completion)(NSData *data, NSURLResponse *response, NSError *error));
#ifdef __cplusplus
}
#endif
