// CV3LiquidGlassSupport.h
// Liquid Glass 公用实现（2026-10-16 抽取）——参考 byg.iosios.net.liquidas 的配方：
// CABackdropLayer + CAFilter 链（gaussianBlur 玻璃底 + colorSaturate vibrance），非 Metal。
//
// 消费方：主面板 appPanel / 分类胶囊 / 分屏浮窗外壳（clippingContainer）/ 浮窗控制条（HomeBar）。
// 约定：CABackdropLayer 显示“其后方的合成内容”，因此 backdrop 永远插在宿主 layer 的 index 0（最底层），
// 宿主的新增内容（子视图/层）天然覆盖在玻璃之上。宿主不裁剪圆角时（如 HomeBar），依赖 Ensure 传入
// cornerRadius > 0 让 backdrop 自裁。
#ifndef CV3_LIQUID_GLASS_SUPPORT_H
#define CV3_LIQUID_GLASS_SUPPORT_H

#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import "CV3PrivateAPI.h"

typedef struct {
    CGFloat blurRadius;     // gaussianBlur 半径
    CGFloat saturation;     // colorSaturate 强度（vibrance）
    CGFloat backdropScale;  // 背板放大（透镜边缘感）
} CV3LiquidGlassRecipe;

static inline CV3LiquidGlassRecipe CV3LiquidGlassRecipeMake(CGFloat blurRadius, CGFloat saturation, CGFloat backdropScale) {
    CV3LiquidGlassRecipe recipe;
    recipe.blurRadius = blurRadius;
    recipe.saturation = saturation;
    recipe.backdropScale = backdropScale;
    return recipe;
}

// 预设配方：主面板 / 分屏浮窗外壳 / 小控件（分类胶囊、控制条）
static inline CV3LiquidGlassRecipe CV3LiquidGlassRecipePanel(void)   { return CV3LiquidGlassRecipeMake(26.0, 1.8, 1.12); }
static inline CV3LiquidGlassRecipe CV3LiquidGlassRecipeWindow(void)  { return CV3LiquidGlassRecipeMake(20.0, 1.6, 1.08); }
static inline CV3LiquidGlassRecipe CV3LiquidGlassRecipeControl(void) { return CV3LiquidGlassRecipeMake(16.0, 1.8, 1.10); }

// 原子工厂：创建一个配置好的 CABackdropLayer（windowServerAware + blur/saturate 滤镜链 + 透镜缩放）。
// 失败（私有类缺失 / 滤镜创建失败）返回 nil，调用方必须判空。
static inline CALayer *CV3LiquidGlassCreateBackdrop(CV3LiquidGlassRecipe recipe, NSUInteger *outFilterCount) {
    Class backdropClass = CV3ClassNamed(@"CABackdropLayer");
    if (!backdropClass) return nil;

    CALayer *backdrop = (CALayer *)[backdropClass new];
    if (!backdrop) return nil;
    @try {
        [backdrop setValue:@(YES) forKey:@"windowServerAware"];
    } @catch (NSException *e) {}

    NSMutableArray *filters = [NSMutableArray array];
    Class filterClass = CV3ClassNamed(@"CAFilter");

    id blur = CV3InvokeObject1(filterClass, NSSelectorFromString(@"filterWithType:"), @"gaussianBlur");
    if (blur) {
        @try { [blur setValue:@(recipe.blurRadius) forKey:@"inputRadius"]; } @catch (NSException *e) {}
        [filters addObject:blur];
    }
    id saturate = CV3InvokeObject1(filterClass, NSSelectorFromString(@"filterWithType:"), @"colorSaturate");
    if (saturate) {
        @try { [saturate setValue:@(recipe.saturation) forKey:@"inputAmount"]; } @catch (NSException *e) {}
        [filters addObject:saturate];
    }
    if (filters.count == 0) return nil;

    @try {
        [backdrop setValue:filters forKey:@"filters"];
    } @catch (NSException *e) {
        return nil;
    }

    backdrop.transform = CATransform3DMakeScale(recipe.backdropScale, recipe.backdropScale, 1.0);
    if (outFilterCount) *outFilterCount = filters.count;
    return backdrop;
}

// 幂等安装：确保 host.layer 最底层存在名为 name 的玻璃底；已存在时仅同步几何（bounds/position/圆角）。
// cornerRadius > 0 时给 backdrop 自身开 masksToBounds（宿主不裁剪圆角的场合）。outCreated 可为 NULL。
static inline CALayer *CV3LiquidGlassEnsureBackdrop(UIView *host,
                                                    NSString *name,
                                                    CV3LiquidGlassRecipe recipe,
                                                    CGFloat cornerRadius,
                                                    BOOL *outCreated) {
    if (!host || name.length == 0) return nil;

    CALayer *backdrop = nil;
    for (CALayer *layer in host.layer.sublayers) {
        if ([[layer valueForKey:@"name"] isEqualToString:name]) {
            backdrop = layer;
            break;
        }
    }

    BOOL created = NO;
    if (!backdrop) {
        backdrop = CV3LiquidGlassCreateBackdrop(recipe, NULL);
        if (!backdrop) return nil;
        [backdrop setValue:name forKey:@"name"];
        [host.layer insertSublayer:backdrop atIndex:0];
        created = YES;
    }

    if (cornerRadius > 0.0) {
        backdrop.cornerRadius = cornerRadius;
        if (@available(iOS 13.0, *)) {
            backdrop.cornerCurve = kCACornerCurveContinuous;
        }
        backdrop.masksToBounds = YES;
    }

    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    backdrop.bounds = host.bounds;
    backdrop.position = CGPointMake(CGRectGetMidX(host.bounds), CGRectGetMidY(host.bounds));
    [CATransaction commit];

    if (outCreated) *outCreated = created;
    return backdrop;
}

#endif
