//
//  DYPlusUtilsPrivate.h
//  DYYY
//
//  DYYYUtils 拆分后跨文件共享的内部 C 函数声明。仅限 Sources/Core 内部文件引用，
//  不要暴露到业务层：业务层统一通过 DYYYUtils.h。
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// 配置内存缓存（DYPConfigurationCache.m 持有，DYYYUtilsConfig.m 负责失效）。
NSMutableDictionary *DYPlusConfigCache(void);

// 关键词列表预编译缓存（DYPConfigurationCache.m 持有，同上）。
NSMutableDictionary *DYPlusKeywordListCache(void);

NS_ASSUME_NONNULL_END
