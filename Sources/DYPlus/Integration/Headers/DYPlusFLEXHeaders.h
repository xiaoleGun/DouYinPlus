#ifndef FLEXHeaders_h
#define FLEXHeaders_h

// 原始的FLEX头文件
#import <Vendor/FLEX/FLEX.h>

@interface DYYYFLEXObjectExplorerViewController (DYPlus_Additions)
- (void)DYPlus_showAnalysisResults:(id)results forClass:(Class)cls;
- (void)DYPlus_analyzeUIHierarchy;
@end

@interface DYYYFLEXManager (DYPlus_Additions)
@end

@interface DYPlusObjectExplorerFactory : NSObject
+ (DYYYFLEXObjectExplorerViewController *)createExplorerForObject:(id)object;
@end

#endif /* FLEXHeaders_h */