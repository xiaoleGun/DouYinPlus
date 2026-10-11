#import <Foundation/Foundation.h>

// 声明全局变量
extern BOOL abTestBlockEnabled;
extern BOOL abTestPatchEnabled;
extern NSDictionary *gFixedABTestData;
extern BOOL gDataLoaded;
extern BOOL gFileExists;
extern BOOL gABTestDataFixed;

// 声明函数
#ifdef __cplusplus
extern "C" {
#endif
void ensureABTestDataLoaded(void);
void checkForRemoteConfigUpdate(BOOL notify);
void DYPlusInvalidateABTestData(void);
NSDictionary *loadFixedABTestData(void);
NSDictionary *getCurrentABTestData(void);
#ifdef __cplusplus
}
#endif
