#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@class UIGlassEffect;

#ifdef __cplusplus
extern "C" {
#endif

UIGlassEffect * _Nullable DYPlusGlassMakeEffect(BOOL clear,
                                              UIUserInterfaceStyle style,
                                              BOOL interactive) API_AVAILABLE(ios(26.0));

BOOL DYPlusGlassNeedsUpdate(UIVisualEffectView *glass,
                          BOOL clear,
                          UIUserInterfaceStyle style) API_AVAILABLE(ios(26.0));

void DYPlusGlassInstallEffect(UIVisualEffectView *glass,
                            UIGlassEffect *effect,
                            BOOL clear,
                            UIUserInterfaceStyle style) API_AVAILABLE(ios(26.0));

void DYPlusGlassRunAnimation(UIViewController * _Nullable controller,
                           BOOL animated,
                           dispatch_block_t changes);

UIVisualEffectView *DYPlusGlassMakeShell(void);
void DYPlusGlassPlaceShell(UIVisualEffectView *glass, UIView *slot);
void DYPlusGlassEnsureBackmost(UIView *slot, UIView *glass);

UIUserInterfaceStyle DYPlusGlassStyleForView(UIView *view);
UIUserInterfaceStyle DYPlusGlassOverrideStyle(BOOL clear,
                                             UIUserInterfaceStyle style);
UIColor * _Nullable DYPlusGlassTintForStyle(UIUserInterfaceStyle style);

#ifdef __cplusplus
}
#endif

NS_ASSUME_NONNULL_END
