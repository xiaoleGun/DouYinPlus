#if __has_include(<UIKit/UIKit.h>)
#import <UIKit/UIKit.h>
#else
#import <Foundation/Foundation.h>

#ifndef CGFLOAT_DEFINED
typedef double CGFloat;
#define CGFLOAT_DEFINED 1
#endif

@interface UIView : NSObject @end
@interface UIViewController : NSObject @end
@interface UIColor : NSObject @end
@interface UIFont : NSObject @end
@interface UIButton : UIView @end
@interface UILabel : UIView @end
@interface UITextView : UIView @end
#endif

#if __has_include(<Photos/Photos.h>)
#import <Photos/Photos.h>
#endif

#define DYPlusGetBool(key) [[NSUserDefaults standardUserDefaults] boolForKey:key]
#define DYPlusGetFloat(key) [[NSUserDefaults standardUserDefaults] floatForKey:key]
#define DYPlusGetInteger(key) [[NSUserDefaults standardUserDefaults] integerForKey:key]
#define DYPlusGetString(key) [[NSUserDefaults standardUserDefaults] stringForKey:key]
#define DYPLUS_IGNORE_GLOBAL_ALPHA_TAG 114514

// 配置内存缓存：供高频 hook 读取，NSUserDefaults 写入时失效
#ifdef __cplusplus
extern "C" {
#endif
BOOL DYPlusCachedBool(NSString *key);
NSString *DYPlusCachedString(NSString *key);
NSArray<NSString *> *DYPlusCachedKeywordList(NSString *configKey);
void DYPlusConfigCacheInvalidate(void);
#ifdef __cplusplus
}
#endif

typedef NS_ENUM(NSInteger, MediaType) {
  MediaTypeVideo,
  MediaTypeImage,
  MediaTypeAudio,
  MediaTypeHeic
};

// ===== 领域头文件（自 AwemeHeaders.h 拆分；声明内容原样保留）=====
#import "Integration/Headers/DYPlusAwemeHeadersModel.h"
#import "Integration/Headers/DYPlusAwemeHeadersUI.h"
#import "Integration/Headers/DYPlusAwemeHeadersFeed.h"
#import "Integration/Headers/DYPlusAwemeHeadersComment.h"
#import "Integration/Headers/DYPlusAwemeHeadersLive.h"
#import "Integration/Headers/DYPlusAwemeHeadersPlayback.h"
#import "Integration/Headers/DYPlusAwemeHeadersService.h"
#import "Integration/Headers/DYPlusAwemeHeadersPanel.h"

void showVideoStatsEditAlert(UIViewController *viewController);
