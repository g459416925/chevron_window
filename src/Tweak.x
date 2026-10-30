#import <UIKit/UIKit.h>
#import <CoreMotion/CoreMotion.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>
#import <notify.h>
#import <dlfcn.h>
#if __has_feature(ptrauth_calls)
#import <ptrauth.h>
#endif
#import "CV3PrivateAPI.h"
#import "CV3LiquidGlassSupport.h"
#import "CV3CoreSupport.h"

// 前向声明：图标缓存（完整定义见下方 Tweak.x 内 cv3IconCache；CV3FloatingAppWindow.inc 在本文件被
// 引入（早于该定义），其启动占位视图需要访问此缓存）。
static NSCache *cv3IconCache;
#import "CV3CameraSupport.h"
#import "CV3BridgeSupport.h"
#include <errno.h>
#include <fcntl.h>
#include <sys/stat.h>
#include <signal.h>
#include <unistd.h>

#pragma mark - Private API Declarations
@interface SBWindow : UIWindow
@end

@interface SBDeviceApplicationSceneWindow : SBWindow
@end

@interface SBSystemGestureManager : NSObject
+ (id)mainDisplayManager;
- (void)addGestureRecognizer:(id)arg1 withType:(unsigned long long)arg2;
- (void)removeGestureRecognizer:(id)arg1;
@end

@interface SpringBoard : UIApplication
@end

@interface SBDisplayItem : NSObject
@property (nonatomic, readonly, copy) NSString *bundleIdentifier;
@end

@interface SBMainWorkspace : NSObject
+ (id)sharedInstance;
- (id)activeDisplayItem;
- (NSSet *)activeDisplayItems;
@end

@interface SBIconController : NSObject
+ (id)sharedInstance;
- (id)iconManager;
- (id)model;
- (id)iconViewForIcon:(id)arg1 location:(id)arg2;
- (void)dismissSearchView;
@end

@interface SBIcon : NSObject
- (void)launchFromLocation:(NSInteger)location context:(id)context;
@end

@interface SBIconView : UIView
@end

@interface SBHHomeScreenView : UIView
@end

@interface SBIconListView : UIView
@end

@interface SBFWallpaperView : UIView
@end

@interface SBMainSwitcherGestureCoordinator : NSObject
- (void)_lockOrientation;
- (void)_releaseOrientationLock;
@end

static BOOL CV3LauncherOwnsHomeSearchTransition(void);

@interface SBIconModel : NSObject
- (id)leafIcons;
@end

@interface LSApplicationWorkspace : NSObject
+ (id)defaultWorkspace;
- (NSArray *)allInstalledApplications;
- (BOOL)openApplicationWithBundleID:(id)arg1;
@end

@interface SBControlCenterController : NSObject
+ (id)sharedInstance;
- (BOOL)isPresented;
@end

@interface SBCoverSheetPresentationManager : NSObject
+ (id)sharedInstance;
- (BOOL)isAnyCoverSheetVisible;
@end

@interface UIImage (Private)
+ (UIImage *)_applicationIconImageForBundleIdentifier:(NSString *)bundleIdentifier format:(int)format scale:(CGFloat)scale;
@end

#pragma mark - SceneKit Declarations for App Hosting
@interface UIApplication (Private)
- (BOOL)launchApplicationWithIdentifier:(NSString *)identifier suspended:(BOOL)suspended;
@end

@class FBScene;
@class CV3FloatingAppWindow;

static void CV3PostHostedState(NSString *bundleID, BOOL hosted);

@interface CV3HostedSceneSession : NSObject
@property (nonatomic, weak) CV3FloatingAppWindow *window;
@property (nonatomic, strong) NSTimer *continuityTimer;
@property (nonatomic, assign, getter=isActive) BOOL active;
- (instancetype)initWithWindow:(CV3FloatingAppWindow *)window;
- (void)setActive:(BOOL)active;
- (void)validateNow:(NSString *)reason;
- (void)invalidate;
@end

@interface SBApplication : NSObject
@property (nonatomic, readonly) NSString *bundleIdentifier;
- (int)pid;
- (id)processState;
- (FBScene *)mainScene;
- (void)_terminateWithReason:(int)arg1 description:(id)arg2;
@end

@interface SBApplicationController : NSObject
+ (instancetype)sharedInstance;
- (SBApplication *)applicationWithBundleIdentifier:(NSString *)bundleIdentifier;
@end

@interface FBSSceneSettings : NSObject
@end

@interface FBSMutableSceneSettings : FBSSceneSettings
@property (assign, nonatomic) BOOL foreground;
@property (assign, nonatomic) BOOL backgrounded;
@property (assign, nonatomic) CGRect frame;
@end

@interface UIMutableApplicationSceneSettings : FBSMutableSceneSettings
- (void)setInLiveResize:(BOOL)inLiveResize;
@end

@interface FBSceneHostManager : NSObject
- (UIView *)hostViewForRequester:(NSString *)requester enableAndOrderFront:(BOOL)orderFront;
- (void)enableHostingForRequester:(NSString *)requester orderFront:(BOOL)front;
- (void)disableHostingForRequester:(NSString *)requester;
@end

@interface FBScene : NSObject
@property (nonatomic, readonly) NSString *identifier;
@property (nonatomic, readonly) FBSSceneSettings *settings;
@property (nonatomic, readonly) FBSceneHostManager *hostManager; // 添加此属性
- (void)_setContentState:(NSInteger)state;
- (void)updateSettings:(FBSSceneSettings *)settings withTransitionContext:(id)context;
@end

@interface FBSceneManager : NSObject
+ (instancetype)sharedInstance;
@end

@interface _UISceneLayerHostContainerView : UIView
- (instancetype)initWithScene:(FBScene *)scene debugDescription:(NSString *)debugDescription;
- (void)_setPresentationContext:(id)context;
- (void)invalidate;
@end

@interface UIScenePresentationContext : NSObject
- (instancetype)_initWithDefaultValues;
@property (nonatomic, assign) NSUInteger presentedLayerTypes;
@property (nonatomic, assign) NSUInteger appearanceStyle;
@property (nonatomic, assign) BOOL clipsToBounds;
@end

#pragma mark - Foreground Sovereignty: RunningBoard & Process Management
@interface RBSProcessIdentity : NSObject
+ (instancetype)identityForEmbeddedApplicationIdentifier:(NSString *)arg1;
@end

@interface RBSTarget : NSObject
+ (instancetype)targetWithProcessIdentity:(RBSProcessIdentity *)arg1;
+ (instancetype)targetWithPid:(int)pid;
@end

@interface RBSLegacyAttribute : NSObject
+ (instancetype)attributeWithReason:(NSUInteger)reason flags:(NSUInteger)flags;
@end

@interface RBSAssertion : NSObject
- (instancetype)initWithExplanation:(NSString *)arg1 target:(RBSTarget *)arg2 attributes:(NSArray *)arg3;
- (BOOL)acquireWithError:(out NSError **)arg1;
- (void)invalidate;
@end

@interface RBSDomainAttribute : NSObject
+ (instancetype)attributeWithDomain:(NSString *)arg1 name:(NSString *)arg2;
@end

@interface BKSProcessAssertion : NSObject
- (instancetype)initWithBundleIdentifier:(NSString *)identifier
                                    flags:(NSUInteger)flags
                                   reason:(NSUInteger)reason
                                     name:(NSString *)name
                              withHandler:(id)handler;
- (BOOL)valid;
- (void)invalidate;
@end

@interface FBProcessTerminationContext : NSObject
@end

@interface FBProcess : NSObject
@property (nonatomic, readonly) NSString *bundleIdentifier;
- (void)terminateWithContext:(FBProcessTerminationContext *)arg1;
- (void)terminate;
@end

@interface FBProcessManager : NSObject
+ (instancetype)sharedInstance;
- (FBProcess *)processForBundleIdentifier:(NSString *)bundleIdentifier;
- (void)terminateProcess:(FBProcess *)arg1 withContext:(FBProcessTerminationContext *)arg2;
@end

#pragma mark - Data Model
@interface CV3AppInfo : NSObject
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSString *bundleId;
@property (nonatomic, strong) UIImage *icon;
@property (nonatomic, copy) NSString *pinyinInitial;
@property (nonatomic, copy) NSString *category; 
@property (nonatomic, assign) BOOL isPinned;
@property (nonatomic, assign) NSInteger unreadCount;
@property (nonatomic, assign) NSTimeInterval lastUsedDate; // 熵减逻辑：最后使用时间
- (void)generatePinyin;
@end
@implementation CV3AppInfo
- (void)generatePinyin {
    if (!self.name || self.name.length == 0) return;
    NSMutableString *ms = [self.name mutableCopy];
    // 转为带音标的拼音
    if (CFStringTransform((__bridge CFMutableStringRef)ms, NULL, kCFStringTransformMandarinLatin, NO)) {
        // 去掉音标
        if (CFStringTransform((__bridge CFMutableStringRef)ms, NULL, kCFStringTransformStripCombiningMarks, NO)) {
            // 提取首字母
            NSArray *parts = [ms componentsSeparatedByString:@" "];
            NSMutableString *initials = [NSMutableString string];
            for (NSString *part in parts) {
                if (part.length > 0) {
                    [initials appendString:[part substringToIndex:1]];
                }
            }
            self.pinyinInitial = [initials lowercaseString];
        }
    }
}
@end

// --- 新增：集中化样式配置 ---
struct {
    // UI 样式
    CGFloat iconCornerRadius;
    CGFloat iconShadowOpacity;
    CGFloat iconShadowRadius;
    // 物理引擎参数
    // 动画参数
    CGFloat durationMedium;
    // 窗口层级
    CGFloat floatingApp;
    CGFloat panel;
    CGFloat background;
    CGFloat keyboard;
    // 布局参数
    CGFloat panelW;
    CGFloat panelH;
    CGFloat triggerHotzoneWidth;
    CGFloat triggerBottomOffset;
    CGFloat safeAreaBreath;
    CGFloat cornerRadius;
    CGFloat minHeight;
    CGFloat shadowRadiusMask;
    CGFloat shadowOpacityMask;
    CGFloat maskAlpha;
    CGFloat floatingChromeCornerRadius;
    CGFloat resizeHandleHitArea;
    CGFloat resizeHandleWindowExpansion;
    CGFloat shadowOpacityFocused;
    CGFloat shadowOpacityUnfocused;
    CGFloat shadowRadiusFocused;
    CGFloat shadowRadiusUnfocused;
    CGFloat shadowRadiusPeak;
    CGFloat shadowOpacityPeak;
    CGFloat shadowOffsetFocusedY;
    CGFloat shadowOffsetUnfocusedY;
    CGFloat shadowOffsetPeakY;
    CGFloat dragLagShadowFactor;
    CGFloat dragLagShadowMaxOffset;
    CGFloat adaptiveCornerRadiusMin;
    CGFloat adaptiveCornerRadiusMax;
    CGFloat adaptiveCornerRadiusRatio;
    CGFloat dragLagShadowElevationFactor;
    CGFloat dragLagShadowElevationMax;
} static const CV3Style = {
    .iconCornerRadius = 13.0,
    .iconShadowOpacity = 0.3,
    .iconShadowRadius = 5.0,
    // 物理引擎参数
    // 动画参数
    .durationMedium = 0.3,
    // 窗口层级
    .floatingApp = 999.0,
    .panel = 2099.0,
    .background = -1.0,
    .keyboard = 10000.0,
    // 布局参数
    .panelW = 370.0,
    .panelH = 520.0,
    .triggerHotzoneWidth = 30.0,
    .triggerBottomOffset = 100.0,
    .safeAreaBreath = 10.0,
    .cornerRadius = 28.0,
    .minHeight = 300.0,
    .shadowRadiusMask = 180.0,
    .shadowOpacityMask = 0.85,
    .maskAlpha = 0.18,
    .floatingChromeCornerRadius = 18.0,
    .resizeHandleHitArea = 80.0,
    .resizeHandleWindowExpansion = 40.0,
    .shadowOpacityFocused = 0.18,
    .shadowOpacityUnfocused = 0.12,
    .shadowRadiusFocused = 26.0,
    .shadowRadiusUnfocused = 18.0,
    .shadowRadiusPeak = 40.0,
    .shadowOpacityPeak = 0.24,
    .shadowOffsetFocusedY = 12.0,
    .shadowOffsetUnfocusedY = 6.0,
    .shadowOffsetPeakY = 22.0,
    .dragLagShadowFactor = 0.04,
    .dragLagShadowMaxOffset = 30.0,
    .adaptiveCornerRadiusMin = 12.0,
    .adaptiveCornerRadiusMax = 28.0,
    .adaptiveCornerRadiusRatio = 0.06,
    .dragLagShadowElevationFactor = 0.005,
    .dragLagShadowElevationMax = 15.0
};

static const CGFloat kCV3PanelJellyStrength = 1.0;
static const NSTimeInterval kCV3PanelPresentDuration = 0.62;
static const NSTimeInterval kCV3PanelDismissDuration = 0.32;
static const CGFloat kCV3PanelTriggerDistance = 45.0;

// BounceIt 风格果冻弹跳（对齐设备上的 com.xu.bounceit16 v1.0.2 观感）。
// BounceIt 侧参数: zeta = 42/(2*sqrt(1666*2.5)) ≈ 0.33 → 过冲 ~34%、弹 ~2 下、收敛 ~0.48s。
// UIView 的 usingSpringWithDamping / UISpringTimingParameters.dampingRatio 与 zeta 同义。
// 这里取 0.38：面板/窗口是大面积 UI，同档观感下比系统小控件略收一点，收敛更快。
// 调法：想更弹 → 调小（0.33 = BounceIt 原档）；想更稳 → 调大（0.45）。
static const CGFloat kCV3BounceDamping = 0.38;

#pragma mark - Custom Cell
typedef NS_ENUM(NSInteger, CV3AppPanelProtectionState) {
    CV3AppPanelProtectionStateNone = 0,
    CV3AppPanelProtectionStateForeground,
    CV3AppPanelProtectionStateSplit
};

@interface CV3AppCell : UICollectionViewCell
@property (nonatomic, strong) UIView *iconBackdrop;
@property (nonatomic, strong) UIImageView *iconView;
@property (nonatomic, strong) UILabel *nameLabel;
@property (nonatomic, strong) UIView *nameBackdrop;
@property (nonatomic, strong) UIView *pinnedIndicator; 
@property (nonatomic, assign) NSInteger unreadCount;
@property (nonatomic, assign) BOOL isFirstResult; // 新增：是否为搜索首项
@property (nonatomic, copy) NSString *representedBundleId;
@property (nonatomic, strong) UIView *screenTimeOverlay;
- (void)setScreenTimeLimited:(BOOL)limited;
- (void)configureWithInfo:(CV3AppInfo *)info searchText:(NSString *)searchText isFirst:(BOOL)isFirst protectionState:(CV3AppPanelProtectionState)protectionState;
// 只刷新随外部状态变化的外观（保护态 / 未读 / 搜索高亮），不碰图标图与布局。
// 面板每秒一次的标记刷新走这里，避免 reloadItemsAtIndexPaths 重建 Cell。
- (void)applyDynamicAppearanceWithInfo:(CV3AppInfo *)info searchText:(NSString *)searchText isFirst:(BOOL)isFirst protectionState:(CV3AppPanelProtectionState)protectionState;
- (void)setIconImage:(UIImage *)image forBundleId:(NSString *)bundleId;
- (void)setUnreadCount:(NSInteger)unreadCount;
- (BOOL)startBreathing;
- (void)stopBreathing;
- (BOOL)hasBreathingAnimation;
@end

@implementation CV3AppCell
- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        CGFloat iconSize = 54.0;
        UIView *ivBack = [[UIView alloc] initWithFrame:CGRectMake((frame.size.width - iconSize)/2, 8, iconSize, iconSize)];
        self.iconBackdrop = ivBack;
        ivBack.backgroundColor = [[UIColor labelColor] colorWithAlphaComponent:0.08];
        ivBack.layer.cornerRadius = CV3Style.iconCornerRadius;
        ivBack.layer.shadowColor = [UIColor blackColor].CGColor;
        ivBack.layer.shadowOffset = CGSizeMake(0, 3);
        ivBack.layer.shadowOpacity = (float)CV3Style.iconShadowOpacity;
        ivBack.layer.shadowRadius = CV3Style.iconShadowRadius;
        ivBack.layer.shadowPath = [UIBezierPath bezierPathWithRoundedRect:CGRectMake(0, 0, iconSize, iconSize) cornerRadius:CV3Style.iconCornerRadius].CGPath;
        [self.contentView addSubview:ivBack];
        
        self.iconView = [[UIImageView alloc] initWithFrame:ivBack.frame];
        self.iconView.layer.cornerRadius = CV3Style.iconCornerRadius;
        self.iconView.clipsToBounds = YES;
        [self.contentView addSubview:self.iconView];

        self.nameBackdrop = [[UIView alloc] initWithFrame:CGRectZero];
        self.nameBackdrop.userInteractionEnabled = NO;
        self.nameBackdrop.backgroundColor = [UIColor colorWithRed:1.00 green:0.20 blue:0.25 alpha:0.14];
        self.nameBackdrop.layer.borderWidth = 1.0;
        self.nameBackdrop.layer.borderColor = [UIColor colorWithRed:1.00 green:0.22 blue:0.26 alpha:0.55].CGColor;
        self.nameBackdrop.layer.shadowColor = [UIColor colorWithRed:1.00 green:0.20 blue:0.25 alpha:0.35].CGColor;
        self.nameBackdrop.layer.shadowOffset = CGSizeMake(0, 1.5);
        self.nameBackdrop.layer.shadowRadius = 4.0;
        self.nameBackdrop.layer.shadowOpacity = 0.85;
        self.nameBackdrop.hidden = YES;
        [self.contentView addSubview:self.nameBackdrop];

        self.pinnedIndicator = [[UIView alloc] initWithFrame:CGRectMake(iconSize - 12, -4, 16, 16)];
        self.pinnedIndicator.backgroundColor = [UIColor cyanColor];
        self.pinnedIndicator.layer.cornerRadius = 8;
        self.pinnedIndicator.layer.borderWidth = 2.0;
        self.pinnedIndicator.layer.borderColor = [UIColor whiteColor].CGColor;
        self.pinnedIndicator.layer.shadowColor = [UIColor cyanColor].CGColor;
        self.pinnedIndicator.layer.shadowOffset = CGSizeZero;
        self.pinnedIndicator.layer.shadowOpacity = 0.8;
        self.pinnedIndicator.layer.shadowRadius = 4.0;
        self.pinnedIndicator.layer.shadowPath = [UIBezierPath bezierPathWithOvalInRect:CGRectMake(0, 0, 16, 16)].CGPath;
        self.pinnedIndicator.hidden = YES;
        [self.iconView addSubview:self.pinnedIndicator];

        self.nameLabel = [[UILabel alloc] initWithFrame:CGRectMake(2, iconSize + 12, frame.size.width - 4, 18)];
        self.nameLabel.textColor = [UIColor labelColor];
        self.nameLabel.font = [UIFont systemFontOfSize:10.0 weight:UIFontWeightMedium];
        self.nameLabel.textAlignment = NSTextAlignmentCenter;
        self.nameLabel.numberOfLines = 1;
        self.nameLabel.lineBreakMode = NSLineBreakByTruncatingTail;
        self.nameLabel.adjustsFontSizeToFitWidth = YES;
        self.nameLabel.minimumScaleFactor = 0.85;
        [self.contentView addSubview:self.nameLabel];
        
        if (@available(iOS 13.0, *)) {
            ivBack.layer.cornerCurve = kCACornerCurveContinuous;
            self.iconView.layer.cornerCurve = kCACornerCurveContinuous;
            self.pinnedIndicator.layer.cornerCurve = kCACornerCurveContinuous;
            self.nameBackdrop.layer.cornerCurve = kCACornerCurveContinuous;
        }

        // 呼吸动画不再在初始化时自启：面板显隐是唯一开关。
        // CV3Window -syncAppCellBreathing 负责在面板出现时挂上、收起时摘掉。
    }
    return self;
}

- (void)setHighlighted:(BOOL)highlighted {
    [super setHighlighted:highlighted];
    if (highlighted) {
        [UIView animateWithDuration:0.10 delay:0 options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction animations:^{
            self.contentView.transform = CGAffineTransformMakeScale(0.92, 0.92);
        } completion:nil];
    } else {
        [UIView animateWithDuration:0.30 delay:0 usingSpringWithDamping:0.78 initialSpringVelocity:0.6 options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction animations:^{
            self.contentView.transform = CGAffineTransformIdentity;
        } completion:nil];
    }
}

- (void)prepareForReuse {
    [super prepareForReuse];
    self.representedBundleId = nil;
    self.iconView.image = nil;
    [self setUnreadCount:0];
    [self setScreenTimeLimited:NO];
}

- (void)configureWithInfo:(CV3AppInfo *)info searchText:(NSString *)searchText isFirst:(BOOL)isFirst protectionState:(CV3AppPanelProtectionState)protectionState {
    self.representedBundleId = info.bundleId;
    self.iconView.image = info.icon;
    self.pinnedIndicator.hidden = !info.isPinned;
    self.isFirstResult = isFirst;
    if (info.isPinned) [self.iconView bringSubviewToFront:self.pinnedIndicator];

    [self applyDynamicAppearanceWithInfo:info searchText:searchText isFirst:isFirst protectionState:protectionState];
}

- (void)applyDynamicAppearanceWithInfo:(CV3AppInfo *)info searchText:(NSString *)searchText isFirst:(BOOL)isFirst protectionState:(CV3AppPanelProtectionState)protectionState {
    UIColor *splitColor = [UIColor colorWithRed:0.0 green:0.62 blue:1.0 alpha:1.0];
    UIColor *foregroundColor = [UIColor colorWithRed:1.0 green:0.28 blue:0.24 alpha:1.0];
    BOOL isProtected = (protectionState != CV3AppPanelProtectionStateNone);
    UIColor *protectionColor = (protectionState == CV3AppPanelProtectionStateForeground) ? foregroundColor : splitColor;
    self.iconBackdrop.backgroundColor = isProtected ? [protectionColor colorWithAlphaComponent:0.30] : [[UIColor labelColor] colorWithAlphaComponent:0.08];
    self.iconBackdrop.layer.borderWidth = isProtected ? 1.5 : 0.0;
    self.iconBackdrop.layer.borderColor = isProtected ? [protectionColor colorWithAlphaComponent:0.80].CGColor : [UIColor clearColor].CGColor;
    self.iconBackdrop.layer.shadowColor = isProtected ? protectionColor.CGColor : [UIColor blackColor].CGColor;
    self.iconBackdrop.layer.shadowOpacity = isProtected ? 0.55 : (float)CV3Style.iconShadowOpacity;
    self.iconBackdrop.layer.shadowRadius = isProtected ? 9.0 : CV3Style.iconShadowRadius;
    self.iconBackdrop.layer.shadowPath = [UIBezierPath bezierPathWithRoundedRect:self.iconBackdrop.bounds cornerRadius:CV3Style.iconCornerRadius].CGPath;
    self.iconView.alpha = isProtected ? 0.62 : 1.0;

    NSMutableParagraphStyle *ps = [[NSMutableParagraphStyle alloc] init];
    ps.alignment = NSTextAlignmentCenter;
    ps.lineBreakMode = NSLineBreakByTruncatingTail;

    UIColor *unreadRed = [UIColor colorWithRed:1.00 green:0.22 blue:0.26 alpha:1.0];
    UIColor *normalTextColor = (info.unreadCount > 0) ? unreadRed : (isProtected ? protectionColor : [UIColor labelColor]);

    if (searchText && searchText.length > 0) {
        NSMutableAttributedString *as = [[NSMutableAttributedString alloc] initWithString:info.name attributes:@{
            NSForegroundColorAttributeName: normalTextColor,
            NSKernAttributeName: @(0.15),
            NSParagraphStyleAttributeName: ps
        }];
        NSRange range = [info.name rangeOfString:searchText options:NSCaseInsensitiveSearch];
        if (range.location != NSNotFound) {
            [as addAttribute:NSForegroundColorAttributeName value:[UIColor colorWithRed:0.15 green:0.79 blue:0.25 alpha:1.0] range:range];
            [as addAttribute:NSFontAttributeName value:[UIFont systemFontOfSize:10.0 weight:UIFontWeightBold] range:range];
        }
        self.nameLabel.attributedText = as;
        
        if (isFirst) {
            self.iconView.layer.borderWidth = 1.5;
            self.iconView.layer.borderColor = (isProtected ? [protectionColor colorWithAlphaComponent:0.9] : [UIColor colorWithRed:0.15 green:0.79 blue:0.25 alpha:0.6]).CGColor;
        } else {
            self.iconView.layer.borderWidth = isProtected ? 1.5 : 0.0;
            self.iconView.layer.borderColor = isProtected ? [protectionColor colorWithAlphaComponent:0.9].CGColor : [UIColor clearColor].CGColor;
        }
    } else {
        NSMutableAttributedString *as = [[NSMutableAttributedString alloc] initWithString:info.name attributes:@{
            NSForegroundColorAttributeName: normalTextColor,
            NSFontAttributeName: [UIFont systemFontOfSize:10.0 weight:UIFontWeightMedium],
            NSKernAttributeName: @(0.15),
            NSParagraphStyleAttributeName: ps
        }];
        self.nameLabel.attributedText = as;
        self.iconView.layer.borderWidth = isProtected ? 1.5 : 0.0;
        self.iconView.layer.borderColor = isProtected ? [protectionColor colorWithAlphaComponent:0.9].CGColor : [UIColor clearColor].CGColor;
    }
    
    [self setUnreadCount:info.unreadCount];
}

- (void)setIconImage:(UIImage *)image forBundleId:(NSString *)bundleId {
    if (bundleId.length == 0 || ![self.representedBundleId isEqualToString:bundleId]) return;
    self.iconView.image = image;
}

// Screen Time 限额视觉：暗色蒙层 + 沙漏标记（纯 UI；限额判定由 CV3Window
// 查询 policy 后传入，与系统主屏限额图标观感一致：一眼可见、等时限结束即恢复）
- (void)setScreenTimeLimited:(BOOL)limited {
    if (!_screenTimeOverlay && limited) {
        UIView *overlay = [[UIView alloc] initWithFrame:self.iconView.bounds];
        overlay.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        overlay.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.45];
        overlay.userInteractionEnabled = NO;

        UIImageView *hourglass = [[UIImageView alloc]
            initWithImage:[UIImage systemImageNamed:@"hourglass"]];
        hourglass.tintColor = [UIColor whiteColor];
        hourglass.contentMode = UIViewContentModeScaleAspectFit;
        CGFloat s = 26.0;
        hourglass.frame = CGRectMake((CGRectGetWidth(overlay.bounds) - s) / 2.0,
                                     (CGRectGetHeight(overlay.bounds) - s) / 2.0, s, s);
        hourglass.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin |
                                     UIViewAutoresizingFlexibleRightMargin |
                                     UIViewAutoresizingFlexibleTopMargin |
                                     UIViewAutoresizingFlexibleBottomMargin;
        [overlay addSubview:hourglass];
        [self.iconView addSubview:overlay];
        _screenTimeOverlay = overlay;
    }
    _screenTimeOverlay.hidden = !limited;
    if (limited && !self.pinnedIndicator.hidden) {
        [self.iconView bringSubviewToFront:self.pinnedIndicator];
    }
}

- (void)setUnreadCount:(NSInteger)unreadCount {
    unreadCount = MAX(0, unreadCount);
    _unreadCount = unreadCount;
    BOOL hasUnread = unreadCount > 0;
    
    self.nameBackdrop.hidden = !hasUnread;
    
    if (self.nameLabel.attributedText) {
        NSMutableAttributedString *mas = [self.nameLabel.attributedText mutableCopy];
        UIColor *textColor = hasUnread ? [UIColor colorWithRed:1.00 green:0.22 blue:0.26 alpha:1.0] : nil;
        if (!textColor) {
            textColor = [UIColor whiteColor];
            if (@available(iOS 13.0, *)) {
                textColor = [UIColor labelColor];
            }
        }
        [mas addAttribute:NSForegroundColorAttributeName value:textColor range:NSMakeRange(0, mas.length)];
        self.nameLabel.attributedText = mas;
    }

    if (!hasUnread) {
        [self.nameBackdrop.layer removeAnimationForKey:@"unreadGlassPulse"];
        return;
    }

    // 测量 App 名称宽度，自适应计算 glass 玻璃框宽度
    NSString *name = self.nameLabel.text ?: @"";
    CGSize textSize = [name boundingRectWithSize:CGSizeMake(self.contentView.frame.size.width - 4.0, 18.0)
                                         options:NSStringDrawingUsesLineFragmentOrigin
                                      attributes:@{ NSFontAttributeName: self.nameLabel.font }
                                         context:nil].size;
    CGFloat backdropWidth = MIN(self.contentView.frame.size.width - 2.0, MAX(36.0, ceil(textSize.width) + 12.0));
    CGFloat backdropX = (self.contentView.frame.size.width - backdropWidth) / 2.0;
    CGRect backdropFrame = CGRectMake(backdropX, 54.0 + 11.0, backdropWidth, 20.0);
    
    self.nameBackdrop.frame = backdropFrame;
    self.nameBackdrop.layer.cornerRadius = 10.0;
    if (@available(iOS 13.0, *)) {
        self.nameBackdrop.layer.cornerCurve = kCACornerCurveContinuous;
    }
    self.nameBackdrop.layer.shadowPath = [UIBezierPath bezierPathWithRoundedRect:self.nameBackdrop.bounds cornerRadius:10.0].CGPath;

    if (UIAccessibilityIsReduceMotionEnabled() || [self.nameBackdrop.layer animationForKey:@"unreadGlassPulse"]) {
        return;
    }

    // 液态玻璃红框微幅呼吸脉冲动画 (Ambient Glass Pulse)
    CAKeyframeAnimation *glassPulse = [CAKeyframeAnimation animationWithKeyPath:@"transform.scale"];
    glassPulse.values = @[@1.0, @1.0, @1.06, @1.0, @1.0];
    glassPulse.keyTimes = @[@0.0, @0.60, @0.75, @0.90, @1.0];
    glassPulse.duration = 3.2;
    glassPulse.repeatCount = HUGE_VALF;
    glassPulse.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
    [self.nameBackdrop.layer addAnimation:glassPulse forKey:@"unreadGlassPulse"];
}

- (BOOL)hasBreathingAnimation {
    return [self.contentView.layer animationForKey:@"breathing"] != nil;
}

- (void)stopBreathing {
    [self.contentView.layer removeAnimationForKey:@"breathing"];
}

- (BOOL)startBreathing {
    // 面板收起时不再为空转；无障碍「减弱动态」下也不挂动画。
    if (UIAccessibilityIsReduceMotionEnabled()) return NO;
    // 幂等：同一轮可见期内重复调用不再重掷随机相位，避免图标跳变。
    if ([self.contentView.layer animationForKey:@"breathing"]) return NO;

    CGFloat lift = 7.0 + (arc4random_uniform(18) / 10.0);
    // 一个完整呼吸周期。原来 6.8~8.6s 观感近乎静止，中位压到 ~5.0s。
    CGFloat duration = 4.4 + (arc4random_uniform(14) / 10.0);
    CFTimeInterval beginTime = CACurrentMediaTime() + (arc4random_uniform(80) / 100.0);

    CAAnimationGroup *(^makeFloatGroup)(void) = ^CAAnimationGroup *{
        CAKeyframeAnimation *floatY = [CAKeyframeAnimation animationWithKeyPath:@"transform.translation.y"];
        floatY.values = @[@0.0, @(-lift * 0.42), @(-lift), @(-lift * 0.88), @(-lift * 0.36), @0.0];
        floatY.keyTimes = @[@0.0, @0.16, @0.38, @0.58, @0.82, @1.0];
        floatY.calculationMode = kCAAnimationCubic;

        CAKeyframeAnimation *scale = [CAKeyframeAnimation animationWithKeyPath:@"transform.scale"];
        scale.values = @[@1.0, @1.012, @1.026, @1.018, @1.006, @1.0];
        scale.keyTimes = floatY.keyTimes;
        scale.calculationMode = kCAAnimationCubic;

        CAAnimationGroup *group = [CAAnimationGroup animation];
        group.animations = @[floatY, scale];
        group.duration = duration;
        group.beginTime = beginTime;
        group.repeatCount = HUGE_VALF;
        group.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
        group.removedOnCompletion = NO;
        return group;
    };

    [self.contentView.layer addAnimation:makeFloatGroup() forKey:@"breathing"];
    return YES;
}
@end

#pragma mark - Root VC
@interface CV3RootViewController : UIViewController
@end

static void CV3WriteFocusedDiagnostic(NSString *message);
static BOOL CV3HasVisibleHostedWindow(void);
static void CV3DumpKeyboardForensics(NSString *reason);

static void CV3AppendKeyboardLayerTree(CALayer *layer,
                                       NSUInteger depth,
                                       NSMutableArray<NSString *> *lines) {
    if (!layer || depth > 8 || lines.count >= 96) return;
    BOOL markedKeyboard = [layer respondsToSelector:@selector(isKeyboardLayer)] &&
                          ((BOOL (*)(id, SEL))objc_msgSend)(layer, @selector(isKeyboardLayer));
    CATransform3D transform = layer.transform;
    CATransform3D subT = layer.sublayerTransform;
    [lines addObject:[NSString stringWithFormat:@"%*s%@ keyboard=%d frame=%@ bounds=%@ position=%@ anchor=%@ transform=[%g,%g,%g,%g,%g,%g,%g,%g,%g,%g,%g,%g,%g,%g,%g,%g] subT=[%g,%g,%g,%g,%g,%g,%g,%g,%g,%g,%g,%g,%g,%g,%g,%g] hidden=%d opacity=%.2f children=%lu",
                      (int)(depth * 2), "",
                      NSStringFromClass(layer.class),
                      markedKeyboard,
                      NSStringFromCGRect(layer.frame),
                      NSStringFromCGRect(layer.bounds),
                      NSStringFromCGPoint(layer.position),
                      NSStringFromCGPoint(layer.anchorPoint),
                      transform.m11, transform.m12, transform.m13, transform.m14,
                      transform.m21, transform.m22, transform.m23, transform.m24,
                      transform.m31, transform.m32, transform.m33, transform.m34,
                      transform.m41, transform.m42, transform.m43, transform.m44,
                      subT.m11, subT.m12, subT.m13, subT.m14,
                      subT.m21, subT.m22, subT.m23, subT.m24,
                      subT.m31, subT.m32, subT.m33, subT.m34,
                      subT.m41, subT.m42, subT.m43, subT.m44,
                      layer.hidden, layer.opacity,
                      (unsigned long)layer.sublayers.count]];
    for (CALayer *child in layer.sublayers) {
        CV3AppendKeyboardLayerTree(child, depth + 1, lines);
    }
}

static void CV3AppendKeyboardViewTree(UIView *view,
                                      NSUInteger depth,
                                      NSMutableArray<NSString *> *lines) {
    if (!view || depth > 10 || lines.count >= 128) return;
    [lines addObject:[NSString stringWithFormat:@"%*s%@:%p frame=%@ bounds=%@ center=%@ transform=%@ hidden=%d alpha=%.2f layer=%@",
                     (int)(depth * 2), "", NSStringFromClass(view.class), view,
                     NSStringFromCGRect(view.frame), NSStringFromCGRect(view.bounds),
                     NSStringFromCGPoint(view.center), NSStringFromCGAffineTransform(view.transform),
                     view.hidden, view.alpha, NSStringFromClass(view.layer.class)]];
    for (UIView *child in view.subviews) {
        CV3AppendKeyboardViewTree(child, depth + 1, lines);
    }
}

static BOOL CV3AppendDiagnosticDataDirectly(NSData *data, NSString *label) {
    NSArray<NSString *> *paths = @[
        @"/var/mobile/Library/Logs/ChevronV3_Logs.txt",
        @"/private/var/mobile/Library/Logs/ChevronV3_Logs.txt",
        @"/var/mobile/Documents/ChevronV3_Logs.txt",
    ];
    NSMutableArray<NSString *> *failures = [NSMutableArray array];

    for (NSString *path in paths) {
        struct stat fileInfo;
        if (stat(path.fileSystemRepresentation, &fileInfo) == 0 &&
            fileInfo.st_size + (off_t)data.length > 1024 * 1024) {
            NSString *previous = [path stringByAppendingString:@".previous"];
            unlink(previous.fileSystemRepresentation);
            rename(path.fileSystemRepresentation, previous.fileSystemRepresentation);
        }

        int fd = open(path.fileSystemRepresentation, O_WRONLY | O_CREAT | O_APPEND, 0644);
        if (fd < 0) {
            [failures addObject:[NSString stringWithFormat:@"%@ open=%d", path, errno]];
            continue;
        }

        const uint8_t *bytes = data.bytes;
        NSUInteger remaining = data.length;
        BOOL wroteAll = YES;
        while (remaining > 0) {
            ssize_t written = write(fd, bytes, remaining);
            if (written <= 0) {
                [failures addObject:[NSString stringWithFormat:@"%@ write=%d", path, errno]];
                wroteAll = NO;
                break;
            }
            bytes += written;
            remaining -= (NSUInteger)written;
        }
        close(fd);
        if (wroteAll) {
            return YES;
        }
    }

    NSLog(@"[ChevronProbe] direct-write label=%@ failed=%@",
          label ?: @"<nil>", [failures componentsJoinedByString:@"; "]);
    return NO;
}

static void CV3WriteBootstrapProbe(void) {
    // Deliberately outside the diagnostics gate: one line per launch keeps the
    // installed build and the restart history visible while logging is off.
    NSString *entry = [NSString stringWithFormat:
        @"[%@][ChevronProbe] springboard.bootstrap pid=%d version=%@\n",
        NSDate.date, NSProcessInfo.processInfo.processIdentifier, CV3_VERSION_STRING];
    NSData *data = [entry dataUsingEncoding:NSUTF8StringEncoding];
    BOOL wrote = CV3AppendDiagnosticDataDirectly(data, @"bootstrap");
    NSLog(@"[ChevronProbe] bootstrap-write success=%d", wrote);
}

// All historical split-window call sites feed the strict trace. Keeping this
// function active is important: Scene discovery, hosting, settings rewrites,
// first-frame gates and recovery failures were previously discarded here.
static void CV3LogToFile(NSString *format, ...) {
    if (!CV3DiagnosticLoggingEnabled()) return;
    va_list args;
    va_start(args, format);
    NSString *details = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);
    CV3WriteFocusedDiagnostic([NSString stringWithFormat:@"[SplitTrace] %@", details ?: @"<nil>"]);
}

static void CV3LogCameraGrantMutation(NSString *message) {
    CV3LogToFile(@"%@", [message stringByTrimmingCharactersInSet:
                          NSCharacterSet.newlineCharacterSet]);
}

static CFTimeInterval CV3LastHostedCameraAccessTime = 0;
static __thread BOOL CV3SuppressRouteChangeVolumeHUD = NO;

static void CV3HostedCameraAccessGranted(CFNotificationCenterRef center,
                                         void *observer,
                                         CFStringRef name,
                                         const void *object,
                                         CFDictionaryRef userInfo) {
    CV3LastHostedCameraAccessTime = CACurrentMediaTime();
    CV3LogToFile(@"[ChevronProbe] camera.grant-hit time=%.6f visibleWindows=%d",
                 CV3LastHostedCameraAccessTime, CV3HasVisibleHostedWindow());
}

static NSString *CV3VolumeChangeReason(id event) {
    NSDictionary *userInfo = nil;
    if ([event isKindOfClass:[NSDictionary class]]) {
        userInfo = event;
    } else if ([event respondsToSelector:@selector(userInfo)]) {
        userInfo = [event userInfo];
    }
    if (![userInfo isKindOfClass:[NSDictionary class]]) return nil;

    id reason = userInfo[@"AVSystemController_AudioVolumeChangeReasonNotificationParameter"];
    if ([reason isKindOfClass:[NSString class]]) return reason;
    for (id value in userInfo.allValues) {
        if ([value isKindOfClass:[NSString class]] &&
            [value caseInsensitiveCompare:@"RouteChange"] == NSOrderedSame) {
            return value;
        }
    }
    return nil;
}

// Scene updates can arrive in bursts while SpringBoard reconciles a hosted
// window. Rewriting the same effective settings in every callback makes the
// client app spend its main-thread budget handling scene/accessibility work.
static NSMutableDictionary *CV3SceneRewriteGate = nil;
static NSMutableDictionary *CV3SceneContentGate = nil;

static id CV3SafeSettingValue(id settings, NSString *key) {
    if (!settings || key.length == 0) return nil;
    @try {
        return [settings valueForKey:key];
    } @catch (__unused NSException *exception) {
        return nil;
    }
}

static NSString *CV3SceneSettingsFingerprint(id settings) {
    if (!settings) return @"<nil>";

    NSArray *keys = @[
        @"foreground", @"backgrounded", @"occluded", @"visibility",
        @"deactivationReasons", @"interfaceOrientation", @"deviceOrientation",
        @"interruptionPolicy", @"frame"
    ];
    NSMutableArray *parts = [NSMutableArray arrayWithCapacity:keys.count];
    for (NSString *key in keys) {
        id value = CV3SafeSettingValue(settings, key);
        [parts addObject:[NSString stringWithFormat:@"%@=%@", key, value ?: @"<missing>"]];
    }
    return [parts componentsJoinedByString:@";"];
}

static NSString *CV3DiagnosticValueDescription(id value) {
    if (!value) return @"<missing>";
    if ([value isKindOfClass:[NSNumber class]] ||
        [value isKindOfClass:[NSString class]] ||
        [value isKindOfClass:[NSValue class]]) {
        return [value description];
    }
    if ([value respondsToSelector:@selector(count)]) {
        return [NSString stringWithFormat:@"<%@:%lu>", NSStringFromClass([value class]),
                (unsigned long)CV3InvokeInteger(value, @selector(count), 0)];
    }
    return [NSString stringWithFormat:@"<%@:%p>", NSStringFromClass([value class]), value];
}

static NSString *CV3DiagnosticObjectFingerprint(id object) {
    if (!object) return @"<nil>";
    NSArray<NSString *> *keys = @[
        @"frame", @"bounds", @"referenceBounds", @"nativeBounds", @"screenBounds",
        @"size", @"pixelSize", @"scale", @"nativeScale",
        @"interfaceOrientation", @"deviceOrientation", @"orientation",
        @"interfaceOrientationMode", @"displayConfiguration",
        @"traitCollection", @"clientTraitCollection", @"effectiveTraitCollection"
    ];
    NSMutableArray<NSString *> *parts = [NSMutableArray arrayWithObject:
        [NSString stringWithFormat:@"class=%@ ptr=%p", NSStringFromClass([object class]), object]];
    for (NSString *key in keys) {
        id value = CV3SafeSettingValue(object, key);
        [parts addObject:[NSString stringWithFormat:@"%@=%@", key,
                          CV3DiagnosticValueDescription(value)]];
    }
    id displayConfiguration = CV3SafeSettingValue(object, @"displayConfiguration");
    if (displayConfiguration) {
        for (NSString *key in @[@"bounds", @"referenceBounds", @"nativeBounds",
                                @"screenBounds", @"size", @"pixelSize", @"scale", @"nativeScale"]) {
            id value = CV3SafeSettingValue(displayConfiguration, key);
            [parts addObject:[NSString stringWithFormat:@"display.%@=%@", key,
                              CV3DiagnosticValueDescription(value)]];
        }
    }
    return [parts componentsJoinedByString:@";"];
}

static NSString *CV3SceneGateKey(FBScene *scene, NSString *bundleID) {
    NSString *identifier = scene.identifier;
    if (identifier.length == 0) identifier = [NSString stringWithFormat:@"%p", scene];
    return [NSString stringWithFormat:@"%@|%@", identifier, bundleID ?: @"<unknown>"];
}

static BOOL CV3ShouldRewriteSceneSettings(FBScene *scene, NSString *bundleID, id settings) {
    NSString *key = CV3SceneGateKey(scene, bundleID);
    NSString *fingerprint = CV3SceneSettingsFingerprint(settings);
    NSTimeInterval now = CACurrentMediaTime();

    @synchronized ([NSObject class]) {
        if (!CV3SceneRewriteGate) CV3SceneRewriteGate = [NSMutableDictionary dictionary];
        NSDictionary *previous = CV3SceneRewriteGate[key];
        NSTimeInterval lastTime = [previous[@"time"] doubleValue];
        NSString *lastFingerprint = previous[@"fingerprint"];

        // A repeated effective state is redundant. A changed state is allowed
        // through, but still gets a short floor to avoid update storms.
        NSTimeInterval minimumInterval = [lastFingerprint isEqualToString:fingerprint] ? 0.90 : 0.20;
        if (previous && now - lastTime < minimumInterval) {
            CV3LogToFile(@"[Throttled][Scene] 跳过重复 Settings 提交 bundle=%@ age=%.3f fingerprintSame=%@",
                         bundleID, now - lastTime, [lastFingerprint isEqualToString:fingerprint] ? @"YES" : @"NO");
            return NO;
        }

        CV3SceneRewriteGate[key] = @{@"time": @(now), @"fingerprint": fingerprint};
    }
    return YES;
}

static BOOL CV3ShouldForceSceneContentState(FBScene *scene, NSString *bundleID) {
    NSString *key = CV3SceneGateKey(scene, bundleID);
    NSTimeInterval now = CACurrentMediaTime();
    @synchronized ([NSObject class]) {
        if (!CV3SceneContentGate) CV3SceneContentGate = [NSMutableDictionary dictionary];
        NSTimeInterval lastTime = [CV3SceneContentGate[key] doubleValue];
        if (lastTime > 0 && now - lastTime < 1.50) return NO;
        CV3SceneContentGate[key] = @(now);
    }
    return YES;
}

static void CV3WriteFocusedDiagnostic(NSString *message) {
    if (!CV3DiagnosticLoggingEnabled()) return;
    BOOL relevant = [message hasPrefix:@"[ChevronProbe]"] ||
        [message hasPrefix:@"[SplitTrace] [LiquidGlass]"] ||
        [message hasPrefix:@"[SplitTrace] [PreWarm]"] ||
        [message hasPrefix:@"[SplitTrace] [PanelAppearance]"] ||
        ([message hasPrefix:@"[SplitTrace] [Strict]"] && [message containsString:@"phase=coldLaunch"]) ||
        [message hasPrefix:@"[SplitTrace] [CanvasGate]"] ||
        [message hasPrefix:@"[SplitTrace] [SceneHost]"] ||
        [message hasPrefix:@"[SplitTrace] [Visibility]"] ||
        [message hasPrefix:@"[SplitTrace] [Scene] "] ||
        [message hasPrefix:@"[HomeBarTrace]"] ||
        [message hasPrefix:@"[SplitTrace] [Error]"] ||
        [message hasPrefix:@"[SplitTrace] [Recovery]"] ||
        [message hasPrefix:@"[SplitTrace] [ChevronProbe]"] ||
        [message hasPrefix:@"[StashAnimation]"] ||
        [message hasPrefix:@"[SplitTrace] [SystemUILevel]"] ||
        [message hasPrefix:@"[SplitTrace] [NotificationSplit]"] ||
        [message hasPrefix:@"[SplitTrace] [FullscreenLaunch]"] ||
        [message hasPrefix:@"[SplitTrace] [ZOrder]"] ||
        [message hasPrefix:@"[SplitTrace] [RotationLayout]"] ||
        [message hasPrefix:@"[SplitTrace] [ExposeRotation]"] ||
        [message hasPrefix:@"[SplitTrace] [OrientationShellPolicy]"] ||
        // Geometry attribution channels. These carry the numbers that decide
        // where a restored window lands and which axis the drop preview and the
        // icon proxy use; without them only the symptom is observable.
        [message hasPrefix:@"[SplitTrace] [OrientationSource]"] ||
        [message hasPrefix:@"[SplitTrace] [PhysicalSafeArea]"] ||
        [message hasPrefix:@"[SplitTrace] [StashFrameTrace]"] ||
        [message hasPrefix:@"[SplitTrace] [SplitPreviewTrace]"] ||
        [message hasPrefix:@"[SplitTrace] [StashIconTrace]"] ||
        [message hasPrefix:@"[SplitTrace] [BreathingTrace]"] ||
        [message hasPrefix:@"[SplitTrace] [PanelScrollTrace]"] ||
        [message hasPrefix:@"[SplitTrace] [EdgeSystemEnvironment]"] ||
        [message hasPrefix:@"[SplitTrace] [EdgeGestureEnvironment]"] ||
        [message hasPrefix:@"[SplitTrace] [HomeSearch]"] ||
        [message hasPrefix:@"[HomeSearch]"] ||
        [message hasPrefix:@"[SplitTrace] [LaunchChain]"] ||
        [message hasPrefix:@"[SplitTrace] [LauncherTouch]"] ||
        [message hasPrefix:@"[SplitTrace] [ScreenTimeGuard]"] ||
        [message hasPrefix:@"[SplitTrace] [Warning]"] ||
        [message hasPrefix:@"[SplitTrace] [Launcher]"] ||
        [message hasPrefix:@"[LauncherTouch]"] ||
        [message hasPrefix:@"[Launcher]"] ||
        [message hasPrefix:@"[SplitTrace] [RotationCentre]"] ||
        [message hasPrefix:@"[SplitTrace] [ViewportFit]"] ||
        [message hasPrefix:@"[SplitTrace] [SnapshotOrient]"] ||
        [message hasPrefix:@"[SplitTrace] [Warning][KeyboardDebug]"] ||
        [message hasPrefix:@"[Warning][KeyboardDebug]"] ||
        ([message hasPrefix:@"[SplitTrace] [Strict]"] &&
         ([message containsString:@"phase=orientation.shellSurfaceSync.begin"] ||
          [message containsString:@"phase=orientation.shellSurfaceSync.completed"] ||
          [message containsString:@"phase=orientation.request.received"] ||
          [message containsString:@"phase=orientation.request.completed"] ||
          [message containsString:@"phase=orientation.request.rejected"] ||
          [message containsString:@"phase=orientation.request.repair"])) ||
        ([message hasPrefix:@"[DEBUG-VIDEOFULLSCREEN]"] &&
         ([message containsString:@"phase=notification.received"] ||
          [message containsString:@"phase=notification.ignored"] ||
          [message containsString:@"phase=notification.suppressed"] ||
          [message containsString:@"phase=notification.unmatched"] ||
          [message containsString:@"phase=notification.matched.before"] ||
          [message containsString:@"phase=notification.matched.after"] ||
          [message containsString:@"phase=applyHosted.entry"] ||
          [message containsString:@"phase=applyHosted.shortCircuit"] ||
          [message containsString:@"phase=applyHosted.completed"])) ||
        [message containsString:@"phase=settingsLayout.orientationMap"] ||
        [message containsString:@"phase=settingsLayout.end modified=1"] ||
        ([message hasPrefix:@"[SplitTrace] [SurfaceOrientationAudit]"] &&
         [message containsString:@"event=change"]);
    if (!relevant) return;
    NSUInteger messageLimit = [message containsString:@"[KeyboardDebug]"] ? 8192 : 2048;
    if (message.length > messageLimit) message = [message substringToIndex:messageLimit];

    // This diagnostic build writes synchronously. The previous asynchronous
    // NSFileHandle path silently dropped records during SpringBoard startup.
    NSDate *eventDate = [NSDate date];
    CFTimeInterval eventMono = CACurrentMediaTime();
    BOOL eventOnMain = NSThread.isMainThread;
    static uint64_t sequence = 0;
    uint64_t currentSequence = __sync_add_and_fetch(&sequence, 1);
    NSString *entry = [NSString stringWithFormat:
        @"[%@][seq=%llu][mono=%.6f][thread=%@][clock=event-v3] %@\n",
        eventDate, currentSequence, eventMono,
        eventOnMain ? @"main" : @"background", message];
    CV3AppendDiagnosticDataDirectly(
        [entry dataUsingEncoding:NSUTF8StringEncoding], @"focused");
}

static void CV3WriteFormattedDiagnostic(NSString *format, va_list arguments) {
    if (!CV3DiagnosticLoggingEnabled()) return;
    NSString *message = [[NSString alloc] initWithFormat:format arguments:arguments];
    CV3WriteFocusedDiagnostic(message);
}

// StashAnimation / VideoFullscreen / HomeBarVisibility / WindowOrientation
// 四条通道的日志入口原本是四份逐字节相同的 va_list 转发实现；统一为一份，
// 通道名以宏别名保留，调用点前缀不变。
static void CV3LogDiag(NSString *format, ...) {
    va_list args;
    va_start(args, format);
    CV3WriteFormattedDiagnostic(format, args);
    va_end(args);
}

#define CV3LogStashAnimation CV3LogDiag
#define CV3LogVideoFullscreen CV3LogDiag
#define CV3LogHomeBarVisibility CV3LogDiag
#define CV3LogWindowOrientation CV3LogDiag

@implementation CV3RootViewController
@end

#pragma mark - Window Level Constants
// WindowLevel 参数已迁移至 CV3Style

#pragma mark - Helper: Color Extraction
static UIColor *CV3AverageColorFromImage(UIImage *image) {
    if (!image) return nil;
    CGSize size = {1, 1};
    UIGraphicsBeginImageContext(size);
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    if (!ctx) {
        UIGraphicsEndImageContext();
        return nil;
    }
    CGContextSetInterpolationQuality(ctx, kCGInterpolationMedium);
    [image drawInRect:(CGRect){.size = size} blendMode:kCGBlendModeCopy alpha:1];
    uint8_t *data = (uint8_t *)CGBitmapContextGetData(ctx);
    UIColor *color = nil;
    // 内存吃紧时 1x1 位图上下文仍可能失败（ctx 或 data 为空），直接返回 nil，
    // 避免对 NULL 位图平面取色导致 SIGSEGV。
    if (data) {
        color = [UIColor colorWithRed:data[0]/255.0 green:data[1]/255.0 blue:data[2]/255.0 alpha:1.0];
    }
    UIGraphicsEndImageContext();
    return color;
}

static CAGradientLayer *CV3EnsureGlassAccentLayer(UIView *hostView) {
    if (!hostView) return nil;
    NSString *layerName = @"CV3GlassAccentHighlight";
    for (CALayer *layer in hostView.layer.sublayers) {
        if ([[layer valueForKey:@"name"] isEqualToString:layerName] && [layer isKindOfClass:[CAGradientLayer class]]) {
            return (CAGradientLayer *)layer;
        }
    }

    CAGradientLayer *layer = [CAGradientLayer layer];
    [layer setValue:layerName forKey:@"name"];
    layer.startPoint = CGPointMake(0.0, 0.0);
    layer.endPoint = CGPointMake(1.0, 1.0);
    [hostView.layer insertSublayer:layer atIndex:0];
    return layer;
}

static void CV3ApplyGlassAccentStyle(UIView *surface,
                                     UIView *tintHost,
                                     CAGradientLayer *highlightLayer,
                                     __unused UIColor *accentColor,
                                     CGFloat cornerRadius,
                                     CGFloat intensity,
                                     BOOL selected) {
    if (!surface) return;

    intensity = MIN(1.0, MAX(0.0, intensity));
    CGFloat scale = [UIScreen mainScreen].scale;

    surface.backgroundColor = [UIColor clearColor];
    surface.layer.cornerRadius = cornerRadius;
    if (@available(iOS 13.0, *)) {
        surface.layer.cornerCurve = kCACornerCurveContinuous;
    }
    surface.layer.borderWidth = MAX(0.5 / scale, selected ? 1.0 / scale : 0.5 / scale);
    surface.layer.borderColor = [[UIColor whiteColor] colorWithAlphaComponent:(0.16 + intensity * 0.14 + (selected ? 0.10 : 0.0))].CGColor;

    UIView *resolvedTintHost = tintHost ?: surface;
    resolvedTintHost.backgroundColor = [[UIColor whiteColor] colorWithAlphaComponent:(0.03 + intensity * 0.05 + (selected ? 0.03 : 0.0))];
    resolvedTintHost.layer.cornerRadius = cornerRadius;
    if (@available(iOS 13.0, *)) {
        resolvedTintHost.layer.cornerCurve = kCACornerCurveContinuous;
    }

    CAGradientLayer *layer = highlightLayer ?: CV3EnsureGlassAccentLayer(resolvedTintHost);
    if (layer) {
        CGRect layerBounds = resolvedTintHost.bounds;
        if (CGRectIsEmpty(layerBounds)) layerBounds = surface.bounds;
        layer.frame = layerBounds;
        layer.cornerRadius = cornerRadius;
        if (@available(iOS 13.0, *)) {
            layer.cornerCurve = kCACornerCurveContinuous;
        }
        // Apple Design Material Rule 12: 顶部边缘天光折射高光 (Top-Edge Light Catching)
        layer.startPoint = CGPointMake(0.5, 0.0);
        layer.endPoint = CGPointMake(0.5, 1.0);
        layer.colors = @[
            (id)[[UIColor whiteColor] colorWithAlphaComponent:(0.22 + intensity * 0.18 + (selected ? 0.10 : 0.0))].CGColor,
            (id)[[UIColor whiteColor] colorWithAlphaComponent:(0.04 + intensity * 0.06)].CGColor,
            (id)[[UIColor blackColor] colorWithAlphaComponent:(0.04 + intensity * 0.06)].CGColor
        ];
        layer.locations = @[@0.0, @0.40, @1.0];
    }
}

#pragma mark - Floating App Window (MilkyWay2-style)
static NSString * const CV3FloatingWindowsDidChangeNotification = @"CV3FloatingWindowsDidChangeNotification";
static NSMutableArray *floatingWindows = nil;
static int CV3VideoOrientationNotificationToken = -1;
static int CV3PlaybackTraceNotificationToken = -1;
static int CV3HostedInteractionNotificationToken = -1;
static UIInterfaceOrientation CV3LastTrustedInterfaceOrientation = UIInterfaceOrientationPortrait;
static UIInterfaceOrientation CV3LastPhysicalDeviceInterfaceOrientation = UIInterfaceOrientationPortrait;
static BOOL CV3SuppressPresentationContextFanout = NO;
static BOOL CV3WorkspaceTransitionActive = NO;
static NSUInteger CV3WorkspaceTransitionProtectionToken = 0;
static NSMutableSet<NSString *> *CV3FullscreenLaunchBypassBundleIDs = nil;
static BOOL CV3SwitcherWindowVisible = NO;
static BOOL CV3MainSwitcherVisible = NO;
static BOOL CV3LockScreenPresented = NO;
static BOOL CV3GestureCoverSheetPresented = NO;
static BOOL CV3ControlCenterPresented = NO;
static BOOL CV3CoverSheetManagerPresented = NO;
static BOOL CV3CoverSheetControllerPresented = NO;
static __weak UIViewController *CV3GestureCoverSheetController;
static uint32_t CV3HostGeneration = 0;

static void CV3BeginFullscreenLaunchBypass(NSString *bundleID) {
    if (bundleID.length == 0) return;
    @synchronized ([NSObject class]) {
        if (!CV3FullscreenLaunchBypassBundleIDs) {
            CV3FullscreenLaunchBypassBundleIDs = [NSMutableSet set];
        }
        [CV3FullscreenLaunchBypassBundleIDs addObject:bundleID];
    }
}

static void CV3EndFullscreenLaunchBypass(NSString *bundleID) {
    if (bundleID.length == 0) return;
    @synchronized ([NSObject class]) {
        [CV3FullscreenLaunchBypassBundleIDs removeObject:bundleID];
    }
}

static BOOL CV3FullscreenLaunchBypassesFocusGuard(NSString *bundleID) {
    if (bundleID.length == 0) return NO;
    @synchronized ([NSObject class]) {
        return [CV3FullscreenLaunchBypassBundleIDs containsObject:bundleID];
    }
}

static NSString *CV3VideoOrientationSourceName(uint8_t source) {
    switch (source) {
        case 1: return @"sceneGeometry";
        case 2: return @"controller";
        case 3: return @"controllerRestore";
        case 4: return @"controllerDisappeared";
        case 5: return @"deviceKVC";
        default: return @"legacyOrUnknown";
    }
}

static BOOL CV3SwitcherPresentationActive(void) {
    return CV3SwitcherWindowVisible || CV3MainSwitcherVisible;
}

static BOOL CV3IsValidInterfaceOrientation(UIInterfaceOrientation orientation) {
    return orientation != UIInterfaceOrientationUnknown && orientation != 0;
}

static BOOL CV3IdentifierContainsExactBundleID(NSString *identifier, NSString *bundleID) {
    if (identifier.length == 0 || bundleID.length == 0) return NO;

    // FBScene identifiers commonly append an instance suffix such as "-default".
    // Keep dots significant so com.example.app never matches com.example.app.pro.
    NSCharacterSet *bundleCharacterSet = [NSCharacterSet characterSetWithCharactersInString:
                                          @"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789."];
    NSRange searchRange = NSMakeRange(0, identifier.length);
    while (searchRange.length > 0) {
        NSRange match = [identifier rangeOfString:bundleID options:0 range:searchRange];
        if (match.location == NSNotFound) return NO;

        BOOL validPrefix = match.location == 0 ||
            ![bundleCharacterSet characterIsMember:[identifier characterAtIndex:match.location - 1]];
        NSUInteger matchEnd = NSMaxRange(match);
        BOOL validSuffix = matchEnd == identifier.length ||
            ![bundleCharacterSet characterIsMember:[identifier characterAtIndex:matchEnd]];
        if (validPrefix && validSuffix) return YES;

        NSUInteger nextLocation = match.location + 1;
        searchRange = NSMakeRange(nextLocation, identifier.length - nextLocation);
    }
    return NO;
}

static const uint64_t CV3RequiredClientBridgeProtocolVersion = 0x2026090603ULL;
static const uint64_t CV3CanvasReadyFlag = (1ULL << 63);
static NSMutableSet<NSString *> *CV3ClientBridgeRelaunchPendingBundleIDs = nil;
static NSMutableSet<NSString *> *CV3ClientBridgeRelaunchAuthorizedBundleIDs = nil;

static NSString *CV3BridgeReadyNotificationNameForBundleID(NSString *bundleID) {
    return CV3BundleScopedNotificationName(@"com.xu.chevronv3.bridge-ready", bundleID);
}

static uint64_t CV3ClientBridgeProtocolVersionForBundleID(NSString *bundleID) {
    NSString *name = CV3BridgeReadyNotificationNameForBundleID(bundleID);
    if (name.length == 0) return 0;

    int token = -1;
    if (notify_register_check(name.UTF8String, &token) != NOTIFY_STATUS_OK) return 0;
    uint64_t version = 0;
    notify_get_state(token, &version);
    notify_cancel(token);
    return version;
}

static BOOL CV3EnsureFreshClientBridgeBeforeHosting(NSString *bundleID,
                                                     dispatch_block_t continuation) {
    if (bundleID.length == 0) return NO;
    if (!CV3ClientBridgeRelaunchPendingBundleIDs) {
        CV3ClientBridgeRelaunchPendingBundleIDs = [NSMutableSet set];
    }
    if (!CV3ClientBridgeRelaunchAuthorizedBundleIDs) {
        CV3ClientBridgeRelaunchAuthorizedBundleIDs = [NSMutableSet set];
    }

    if ([CV3ClientBridgeRelaunchAuthorizedBundleIDs containsObject:bundleID]) {
        [CV3ClientBridgeRelaunchAuthorizedBundleIDs removeObject:bundleID];
        return NO;
    }

    if ([CV3ClientBridgeRelaunchPendingBundleIDs containsObject:bundleID]) {
        return YES;
    }

    uint64_t loadedVersion = CV3ClientBridgeProtocolVersionForBundleID(bundleID);
    if (loadedVersion == CV3RequiredClientBridgeProtocolVersion) return NO;

    [CV3ClientBridgeRelaunchPendingBundleIDs addObject:bundleID];
    @try {
        id controller = [CV3ClassNamed(@"SBApplicationController") sharedInstance];
        SBApplication *application = CV3InvokeObject1(controller,
                                                      @selector(applicationWithBundleIdentifier:),
                                                      bundleID);
        [application _terminateWithReason:1 description:@"Reload ChevronV3VideoBridge"];
    } @catch (NSException *exception) {
        CV3LogToFile(@"[VideoBridge] 终止旧客户端失败 %@: %@", bundleID, exception);
    }

    CV3LogToFile(@"[VideoBridge] 检测到旧客户端协议=%llu，冷启动目标 App: %@",
                 loadedVersion,
                 bundleID);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.55 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        [CV3ClientBridgeRelaunchPendingBundleIDs removeObject:bundleID];
        [CV3ClientBridgeRelaunchAuthorizedBundleIDs addObject:bundleID];
        if (continuation) continuation();
    });
    return YES;
}

static UIInterfaceOrientation CV3InterfaceOrientationFromDevice(void) {
    UIDeviceOrientation deviceOrientation = [UIDevice currentDevice].orientation;
    switch (deviceOrientation) {
        case UIDeviceOrientationPortrait:
            return UIInterfaceOrientationPortrait;
        case UIDeviceOrientationPortraitUpsideDown:
            return UIInterfaceOrientationPortraitUpsideDown;
        case UIDeviceOrientationLandscapeLeft:
            return UIInterfaceOrientationLandscapeRight;
        case UIDeviceOrientationLandscapeRight:
            return UIInterfaceOrientationLandscapeLeft;
        default:
            return UIInterfaceOrientationUnknown;
    }
}

static UIDeviceOrientation CV3DeviceOrientationFromInterface(UIInterfaceOrientation orientation) {
    switch (orientation) {
        case UIInterfaceOrientationPortrait:
            return UIDeviceOrientationPortrait;
        case UIInterfaceOrientationPortraitUpsideDown:
            return UIDeviceOrientationPortraitUpsideDown;
        case UIInterfaceOrientationLandscapeLeft:
            return UIDeviceOrientationLandscapeRight;
        case UIInterfaceOrientationLandscapeRight:
            return UIDeviceOrientationLandscapeLeft;
        default:
            return UIDeviceOrientationUnknown;
    }
}

static UIInterfaceOrientation CV3TrustedInterfaceOrientation(UIWindowScene *preferredScene) {
    if (preferredScene && [preferredScene.session.role isEqualToString:@"_UIScreenBasedSceneSession"] &&
        CV3IsValidInterfaceOrientation(preferredScene.interfaceOrientation)) {
        CV3LastTrustedInterfaceOrientation = preferredScene.interfaceOrientation;
        return preferredScene.interfaceOrientation;
    }

    if (@available(iOS 13.0, *)) {
        for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
            if (![scene isKindOfClass:[UIWindowScene class]]) continue;
            UIWindowScene *windowScene = (UIWindowScene *)scene;
            if (![windowScene.session.role isEqualToString:@"_UIScreenBasedSceneSession"]) continue;
            if (CV3IsValidInterfaceOrientation(windowScene.interfaceOrientation)) {
                CV3LastTrustedInterfaceOrientation = windowScene.interfaceOrientation;
                return windowScene.interfaceOrientation;
            }
        }
    }

    if (CV3IsValidInterfaceOrientation(CV3LastTrustedInterfaceOrientation)) {
        return CV3LastTrustedInterfaceOrientation;
    }

    if (preferredScene && CV3IsValidInterfaceOrientation(preferredScene.interfaceOrientation)) {
        return preferredScene.interfaceOrientation;
    }

    return UIInterfaceOrientationPortrait;
}

static CGAffineTransform CV3RotationTransformForInterfaceOrientation(UIInterfaceOrientation orientation) {
    switch (orientation) {
        case UIInterfaceOrientationLandscapeLeft:
            return CGAffineTransformMakeRotation(-M_PI_2);
        case UIInterfaceOrientationLandscapeRight:
            return CGAffineTransformMakeRotation(M_PI_2);
        case UIInterfaceOrientationPortraitUpsideDown:
            return CGAffineTransformMakeRotation(M_PI);
        case UIInterfaceOrientationPortrait:
        default:
            return CGAffineTransformIdentity;
    }
}

typedef struct {
    UIInterfaceOrientation orientation;
    BOOL isLandscape;
    CGAffineTransform transform;
    CGRect sceneBounds;
    CGSize portraitSize;
    UIWindowScene *scene;
} CV3SceneRotationContext;

static CV3SceneRotationContext CV3MakeSceneRotationContext(UIWindowScene *scene) {
    UIInterfaceOrientation orientation = CV3TrustedInterfaceOrientation(scene);
    CGRect bounds = CGRectZero;
    if (scene && !CGRectIsEmpty(scene.coordinateSpace.bounds)) {
        bounds = scene.coordinateSpace.bounds;
    } else {
        bounds = [UIScreen mainScreen].bounds;
    }

    CGFloat shortSide = MIN(bounds.size.width, bounds.size.height);
    CGFloat longSide = MAX(bounds.size.width, bounds.size.height);

    CV3SceneRotationContext context;
    context.orientation = orientation;
    context.isLandscape = UIInterfaceOrientationIsLandscape(orientation);
    context.transform = CV3RotationTransformForInterfaceOrientation(orientation);
    context.sceneBounds = bounds;
    context.portraitSize = CGSizeMake(shortSide, longSide);
    context.scene = scene;
    return context;
}

static BOOL CV3SceneRotationContextNeedsApply(UIInterfaceOrientation currentOrientation,
                                              CGAffineTransform currentTransform,
                                              CV3SceneRotationContext context,
                                              BOOL force) {
    if (force) return YES;
    return currentOrientation != context.orientation ||
           !CGAffineTransformEqualToTransform(currentTransform, context.transform);
}

static BOOL CV3SetIntegerSetting(id settings, SEL getter, SEL setter, NSString *key, NSInteger value, BOOL force) {
    if (!settings) return NO;

    NSInteger currentValue = NSIntegerMin;
    @try {
        if (getter && [settings respondsToSelector:getter]) {
            NSMethodSignature *signature = [settings methodSignatureForSelector:getter];
            NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:signature];
            [invocation setTarget:settings];
            [invocation setSelector:getter];
            [invocation invoke];
            [invocation getReturnValue:&currentValue];
        } else if (key.length) {
            currentValue = [[settings valueForKey:key] integerValue];
        }
    } @catch (NSException *e) {}

    if (!force && currentValue == value) return NO;

    @try {
        if (setter && [settings respondsToSelector:setter]) {
            NSMethodSignature *signature = [settings methodSignatureForSelector:setter];
            NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:signature];
            [invocation setTarget:settings];
            [invocation setSelector:setter];
            [invocation setArgument:&value atIndex:2];
            [invocation invoke];
            return YES;
        }
    } @catch (NSException *e) {}

    if (key.length) {
        @try {
            [settings setValue:@(value) forKey:key];
            return YES;
        } @catch (NSException *e) {}
    }

    return NO;
}

static BOOL CV3SetObjectSetting(id settings, SEL getter, SEL setter, NSString *key, id value, BOOL force) {
    if (!settings || !value) return NO;

    id currentValue = nil;
    @try {
        if (getter && [settings respondsToSelector:getter]) {
            NSMethodSignature *signature = [settings methodSignatureForSelector:getter];
            NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:signature];
            [invocation setTarget:settings];
            [invocation setSelector:getter];
            [invocation invoke];
            __unsafe_unretained id returnedValue = nil;
            [invocation getReturnValue:&returnedValue];
            currentValue = returnedValue;
        } else if (key.length) {
            currentValue = [settings valueForKey:key];
        }
    } @catch (NSException *e) {}

    if (!force && currentValue && [currentValue isEqual:value]) return NO;

    @try {
        if (setter && [settings respondsToSelector:setter]) {
            NSMethodSignature *signature = [settings methodSignatureForSelector:setter];
            NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:signature];
            id argument = value;
            [invocation setTarget:settings];
            [invocation setSelector:setter];
            [invocation setArgument:&argument atIndex:2];
            [invocation invoke];
            return YES;
        }
    } @catch (NSException *e) {}

    if (key.length) {
        @try {
            [settings setValue:value forKey:key];
            return YES;
        } @catch (NSException *e) {}
    }

    return NO;
}

static BOOL CV3SetBoolSettingIfNeeded(id settings, SEL setter, NSString *key, BOOL value) {
    if (!settings || (!setter && key.length == 0)) return NO;

    BOOL hasCurrentValue = NO;
    BOOL currentValue = NO;
    if (key.length) {
        @try {
            currentValue = [[settings valueForKey:key] boolValue];
            hasCurrentValue = YES;
        } @catch (NSException *e) {}
    }

    if (hasCurrentValue && currentValue == value) return NO;

    @try {
        if (setter && [settings respondsToSelector:setter]) {
            NSMethodSignature *signature = [settings methodSignatureForSelector:setter];
            NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:signature];
            BOOL argument = value;
            [invocation setTarget:settings];
            [invocation setSelector:setter];
            [invocation setArgument:&argument atIndex:2];
            [invocation invoke];
            return YES;
        }
    } @catch (NSException *e) {}

    if (key.length) {
        @try {
            [settings setValue:@(value) forKey:key];
            return YES;
        } @catch (NSException *e) {}
    }

    return NO;
}

static BOOL CV3SetIntegerSettingIfNeeded(id settings, SEL setter, NSString *key, NSInteger value) {
    if (!settings || (!setter && key.length == 0)) return NO;

    BOOL hasCurrentValue = NO;
    NSInteger currentValue = NSIntegerMin;
    if (key.length) {
        @try {
            currentValue = [[settings valueForKey:key] integerValue];
            hasCurrentValue = YES;
        } @catch (NSException *e) {}
    }

    if (hasCurrentValue && currentValue == value) return NO;

    @try {
        if (setter && [settings respondsToSelector:setter]) {
            NSMethodSignature *signature = [settings methodSignatureForSelector:setter];
            NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:signature];
            NSInteger argument = value;
            [invocation setTarget:settings];
            [invocation setSelector:setter];
            [invocation setArgument:&argument atIndex:2];
            [invocation invoke];
            return YES;
        }
    } @catch (NSException *e) {}

    if (key.length) {
        @try {
            [settings setValue:@(value) forKey:key];
            return YES;
        } @catch (NSException *e) {}
    }

    return NO;
}

static BOOL CV3ApplyLockedOrientationTraitsToSettings(id settings, UIInterfaceOrientation orientation, BOOL force) {
    if (!settings) return NO;

    BOOL isLandscape = UIInterfaceOrientationIsLandscape(orientation);
    UITraitCollection *sizeClassTraits = [UITraitCollection traitCollectionWithTraitsFromCollections:@[
        [UITraitCollection traitCollectionWithHorizontalSizeClass:(isLandscape ? UIUserInterfaceSizeClassRegular : UIUserInterfaceSizeClassCompact)],
        [UITraitCollection traitCollectionWithVerticalSizeClass:(isLandscape ? UIUserInterfaceSizeClassCompact : UIUserInterfaceSizeClassRegular)],
        [UITraitCollection traitCollectionWithDisplayScale:[UIScreen mainScreen].scale]
    ]];

    BOOL modified = NO;
    modified |= CV3SetObjectSetting(settings,
                                    @selector(traitCollection),
                                    NSSelectorFromString(@"setTraitCollection:"),
                                    @"traitCollection",
                                    sizeClassTraits,
                                    force);
    modified |= CV3SetObjectSetting(settings,
                                    NSSelectorFromString(@"clientTraitCollection"),
                                    NSSelectorFromString(@"setClientTraitCollection:"),
                                    @"clientTraitCollection",
                                    sizeClassTraits,
                                    force);
    modified |= CV3SetObjectSetting(settings,
                                    NSSelectorFromString(@"preferredTraitCollection"),
                                    NSSelectorFromString(@"setPreferredTraitCollection:"),
                                    @"preferredTraitCollection",
                                    sizeClassTraits,
                                    force);
    modified |= CV3SetObjectSetting(settings,
                                    NSSelectorFromString(@"effectiveTraitCollection"),
                                    NSSelectorFromString(@"setEffectiveTraitCollection:"),
                                    @"effectiveTraitCollection",
                                    sizeClassTraits,
                                    force);

    return modified;
}

static BOOL CV3RestoreCrossOrientationMapOnSettings(id settings,
                                                     id resolver,
                                                     NSInteger mode,
                                                     BOOL hasMode) {
    if (!settings) return NO;

    BOOL modified = NO;
    SEL resolverSetter = NSSelectorFromString(@"setInterfaceOrientationMapResolver:");
    SEL modeSetter = NSSelectorFromString(@"setInterfaceOrientationMode:");
    @try {
        if ([settings respondsToSelector:resolverSetter]) {
            ((void (*)(id, SEL, id))objc_msgSend)(settings, resolverSetter, resolver);
            modified = YES;
        }
        if (hasMode && [settings respondsToSelector:modeSetter]) {
            ((void (*)(id, SEL, NSInteger))objc_msgSend)(settings, modeSetter, mode);
            modified = YES;
        }
    } @catch (NSException *exception) {}
    return modified;
}

static id CV3OrientationMapResolverFromSettings(id settings) {
    SEL getter = NSSelectorFromString(@"interfaceOrientationMapResolver");
    if (!settings || ![settings respondsToSelector:getter]) return nil;
    @try {
        return ((id (*)(id, SEL))objc_msgSend)(settings, getter);
    } @catch (__unused NSException *exception) {
        return nil;
    }
}

static BOOL CV3OrientationMapResolverMatches(id resolver,
                                              UIInterfaceOrientation presentationOrientation,
                                              UIInterfaceOrientation hostedOrientation) {
    if (!resolver ||
        !CV3IsValidInterfaceOrientation(presentationOrientation) ||
        !CV3IsValidInterfaceOrientation(hostedOrientation)) {
        return NO;
    }
    NSInteger target = CV3InvokeInteger(resolver,
                                         NSSelectorFromString(@"targetOrientation"),
                                         NSIntegerMin);
    NSInteger current = CV3InvokeInteger(resolver,
                                          NSSelectorFromString(@"currentOrientation"),
                                          NSIntegerMin);
    // BSCanonicalOrientationMapResolver exposes these values through KVC on
    // this OS build even though respondsToSelector: does not advertise the
    // accessors. The diagnostic trace reads the same keys and confirms the
    // committed resolver already contains the requested orientation pair.
    @try {
        if (target == NSIntegerMin) {
            id value = [resolver valueForKey:@"targetOrientation"];
            if ([value respondsToSelector:@selector(integerValue)]) target = [value integerValue];
        }
        if (current == NSIntegerMin) {
            id value = [resolver valueForKey:@"currentOrientation"];
            if ([value respondsToSelector:@selector(integerValue)]) current = [value integerValue];
        }
    } @catch (__unused NSException *exception) {}
    return target == (NSInteger)presentationOrientation &&
           current == (NSInteger)hostedOrientation;
}

static BOOL CV3ApplyCrossOrientationMapToSettings(id settings,
                                                   UIInterfaceOrientation presentationOrientation,
                                                   UIInterfaceOrientation hostedOrientation,
                                                   BOOL force) {
    if (!settings ||
        !CV3IsValidInterfaceOrientation(presentationOrientation) ||
        !CV3IsValidInterfaceOrientation(hostedOrientation) ||
        UIInterfaceOrientationIsLandscape(presentationOrientation) ==
            UIInterfaceOrientationIsLandscape(hostedOrientation)) {
        return NO;
    }

    Class resolverClass = NSClassFromString(@"BSCanonicalOrientationMapResolver");
    SEL initSelector = NSSelectorFromString(@"initWithTargetOrientation:currentOrientation:");
    SEL resolverGetter = NSSelectorFromString(@"interfaceOrientationMapResolver");
    SEL resolverSetter = NSSelectorFromString(@"setInterfaceOrientationMapResolver:");
    SEL modeSetter = NSSelectorFromString(@"setInterfaceOrientationMode:");
    if (!resolverClass ||
        ![resolverClass instancesRespondToSelector:initSelector] ||
        ![settings respondsToSelector:resolverSetter] ||
        ![settings respondsToSelector:modeSetter]) {
        CV3LogToFile(@"[OrientationMap] unavailable class=%@ init=%d resolverSetter=%d modeSetter=%d",
                     resolverClass, [resolverClass instancesRespondToSelector:initSelector],
                     [settings respondsToSelector:resolverSetter],
                     [settings respondsToSelector:modeSetter]);
        return NO;
    }

    if (!force && [settings respondsToSelector:resolverGetter] &&
        CV3OrientationMapResolverFromSettings(settings)) {
        return NO;
    }

    @try {
        id resolver = ((id (*)(id, SEL, NSInteger, NSInteger))objc_msgSend)(
            [resolverClass alloc], initSelector,
            (NSInteger)presentationOrientation, (NSInteger)hostedOrientation);
        if (!resolver) return NO;
        ((void (*)(id, SEL, NSInteger))objc_msgSend)(settings, modeSetter, 1);
        ((void (*)(id, SEL, id))objc_msgSend)(settings, resolverSetter, resolver);
        CV3LogToFile(@"[OrientationMap] applied target=%ld current=%ld resolver=%@",
                     (long)presentationOrientation, (long)hostedOrientation, resolver);
        return YES;
    } @catch (NSException *exception) {
        CV3LogToFile(@"[OrientationMap] exception=%@ target=%ld current=%ld",
                     exception, (long)presentationOrientation, (long)hostedOrientation);
        return NO;
    }
}

typedef NS_ENUM(NSInteger, CV3HostLifecycleState) {
    CV3HostLifecycleStateIdle = 0,
    CV3HostLifecycleStatePreparing,
    CV3HostLifecycleStateWaitingForScene,
    CV3HostLifecycleStatePrepared,
    CV3HostLifecycleStateLive,
    CV3HostLifecycleStateReleasing,
};

static NSString *CV3HostLifecycleStateName(CV3HostLifecycleState state) {
    switch (state) {
        case CV3HostLifecycleStatePreparing: return @"Preparing";
        case CV3HostLifecycleStateWaitingForScene: return @"WaitingForScene";
        case CV3HostLifecycleStatePrepared: return @"Prepared";
        case CV3HostLifecycleStateLive: return @"Live";
        case CV3HostLifecycleStateReleasing: return @"Releasing";
        case CV3HostLifecycleStateIdle:
        default: return @"Idle";
    }
}

@interface CV3FloatingAppWindow : UIWindow <UIGestureRecognizerDelegate>

@property (nonatomic, copy) NSString *bundleID;
@property (nonatomic, strong) UIVisualEffectView *glassBackdrop; // Transparent fallback behind hosted content
@property (nonatomic, strong) UIView *appContentWrapper;
@property (nonatomic, strong) UIView *rootTransformContainer;
@property (nonatomic, strong) UIView *clippingContainer; 
@property (nonatomic, strong) UIView *hostContainerProxy;
@property (nonatomic, strong) UIView *hostView;
@property (nonatomic, copy) NSString *sceneHostingRequester;
@property (nonatomic, strong) CV3HostedSceneSession *hostedSession;
@property (nonatomic, strong) UIView *homeBarView;
@property (nonatomic, strong) UIVisualEffectView *homeBarBlurView;
@property (nonatomic, strong) CAGradientLayer *homeBarGlowLayer;
@property (nonatomic, strong) UIView *homeBarPillIndicator;
@property (nonatomic, strong) NSTimer *homeBarAutoHideTimer;
@property (nonatomic, strong) UIViewPropertyAnimator *homeBarVisibilityAnimator;
@property (nonatomic, assign) BOOL homeBarAutoHidden;
@property (nonatomic, assign) CFTimeInterval lastHomeBarInteractionTraceTime;
@property (nonatomic, assign) NSInteger homeBarPlacement;
@property (nonatomic, assign) NSInteger homeBarResizeStartPlacement;
@property (nonatomic, assign) CGPoint homeBarResizeAxis;
@property (nonatomic, assign) CGPoint homeBarCommandAxis;
@property (nonatomic, assign) NSInteger homeBarPanMode;
@property (nonatomic, assign) CGFloat homeBarCommandProjection;
@property (nonatomic, strong) UIView *resizeHandle;
@property (nonatomic, strong) CAShapeLayer *resizeHandleLayer;
@property (nonatomic, assign) CGSize resizeHandleVisualSize;
@property (nonatomic, strong) FBScene *targetScene;
@property (nonatomic, assign) CGRect initialResizeFrame;
@property (nonatomic, assign) BOOL isStashed;
@property (nonatomic, assign) NSInteger stashedSide; // 0: None, 1: Left, 2: Right
@property (nonatomic, assign) CGRect preStashFrame;
@property (nonatomic, strong) UIView *stashGrabber;
@property (nonatomic, strong) UIVisualEffectView *stashIconBackdropView;
@property (nonatomic, strong) CAGradientLayer *stashIconHighlightLayer;
@property (nonatomic, strong) UIImageView *appIconMiniView;

// Snap & Visual FX Enhancements
@property (nonatomic, strong) CALayer *innerGlowLayer;
@property (nonatomic, strong) CALayer *cyanLayer;
@property (nonatomic, strong) CALayer *magentaLayer;
@property (nonatomic, assign) CGRect lastTargetSnapFrame;
@property (nonatomic, strong) UIColor *adaptiveAppColor;

// Pro Enhancements
@property (nonatomic, assign) BOOL isFocused;
@property (nonatomic, assign) BOOL isClosing;
@property (nonatomic, assign) BOOL sharedGeometryRetained;
@property (nonatomic, assign) BOOL isSuppressedByLockScreen;
@property (nonatomic, assign) BOOL isInLayout;
@property (nonatomic, assign) BOOL isMovingWindow;
@property (nonatomic, assign) NSTimeInterval moveSceneSyncSuppressedUntil;
@property (nonatomic, strong) UIView *splashView;
@property (nonatomic, strong) UIImageView *largeSplashIcon;
@property (nonatomic, assign) UIInterfaceOrientation targetOrientation;
@property (nonatomic, assign) UIInterfaceOrientation hostedContentOrientation;
@property (nonatomic, assign) UIInterfaceOrientation clientAcknowledgedOrientation;
@property (nonatomic, assign) BOOL prefersLandscapePresentation;
@property (nonatomic, assign) BOOL requiresLandscapeContent;
@property (nonatomic, assign) BOOL awaitingInitialRenderableContent;
@property (nonatomic, assign) BOOL contentVisibilityGateEnabled;
@property (nonatomic, assign) BOOL windowPresentationBlocked;
@property (nonatomic, assign) BOOL requestedWindowHidden;
- (void)refreshContentVisibilityGate;
@property (nonatomic, assign) CFTimeInterval coldLaunchStartTime;
@property (nonatomic, copy) NSString *coldLaunchTraceID;
@property (nonatomic, assign) BOOL coldLaunchSceneFoundRecorded;
@property (nonatomic, assign) BOOL coldLaunchHostAttachedRecorded;
@property (nonatomic, assign) BOOL coldLaunchCanvasMatchedRecorded;
@property (nonatomic, assign) BOOL coldLaunchCompletedRecorded;
@property (nonatomic, assign) CFTimeInterval lastInitialHostPresentationRefreshTime;
@property (nonatomic, assign) UIInterfaceOrientation mappedPresentationOrientation;
@property (nonatomic, assign) UIInterfaceOrientation mappedHostedOrientation;
@property (nonatomic, assign) NSTimeInterval lastCanvasMismatchLoggedAt;
@property (nonatomic, assign) CFTimeInterval initialCanvasSoftGateStartedAt;
@property (nonatomic, assign) BOOL initialRevealBufferDone;
@property (nonatomic, assign) BOOL initialRevealBufferInFlight;
@property (nonatomic, strong) UIView *launchPlaceholderView;
@property (nonatomic, assign) BOOL placeholderRevealAllowed;
@property (nonatomic, strong) id originalOrientationMapResolver;
@property (nonatomic, strong) id activeOrientationMapResolver;
@property (nonatomic, assign) NSInteger originalInterfaceOrientationMode;
@property (nonatomic, assign) BOOL hasOriginalInterfaceOrientationMode;
@property (nonatomic, assign) BOOL hasCapturedOrientationMapBaseline;
@property (nonatomic, assign) BOOL crossOrientationMapApplied;
@property (nonatomic, assign) BOOL hostPresentationRepublishPending;
@property (nonatomic, strong) UIView *pendingRepublishedHostView;
@property (nonatomic, copy) NSString *pendingRepublishedContextID;
@property (nonatomic, copy) NSString *pendingRepublishedRequester;
@property (nonatomic, assign) NSUInteger hostPresentationRepublishGeneration;
@property (nonatomic, assign) NSUInteger pendingRepublishedStableCount;
@property (nonatomic, assign) UIInterfaceOrientation lastLayoutOrientation;
@property (nonatomic, assign) CGAffineTransform baseRotationTransform;
@property (nonatomic, assign) CGRect preHostedLandscapePortraitFrame;
@property (nonatomic, assign) BOOL isFullscreenMode;
@property (nonatomic, assign) BOOL fullscreenLaunchPending;
@property (nonatomic, assign) BOOL preserveSceneForegroundOnClose;
@property (nonatomic, assign) BOOL isCompactMode;
@property (nonatomic, strong) UIView *liveResizeSnapshotView;
@property (nonatomic, strong) id rbsAssertion;
@property (nonatomic, copy) NSString *rbsAssertionAttributeName;
@property (nonatomic, copy) NSString *rbsAssertionLastAttemptedAttributeName;
@property (nonatomic, assign) NSUInteger rbsAssertionFailureCount;
@property (nonatomic, assign) NSTimeInterval rbsAssertionRetryAfter;
@property (nonatomic, assign) BOOL rbsAssertionUnsupported;
@property (nonatomic, assign) BOOL allowProcessTerminationOnClose;
@property (nonatomic, assign) CGRect preExposeFrame;
@property (nonatomic, assign) CGAffineTransform preExposeTransform;
@property (nonatomic, strong) UIView *exposeOverlayView;
@property (nonatomic, strong) UIView *exposeLiveContentContainer;
@property (nonatomic, weak) UIView *exposeContentOriginalSuperview;
@property (nonatomic, assign) NSInteger exposeContentOriginalIndex;
@property (nonatomic, assign) CGRect exposeContentOriginalBounds;
@property (nonatomic, assign) CGPoint exposeContentOriginalCenter;
@property (nonatomic, assign) CGAffineTransform exposeContentOriginalTransform;
@property (nonatomic, assign) UIViewAutoresizing exposeContentOriginalAutoresizingMask;
@property (nonatomic, assign) BOOL exposeContentOriginalUserInteractionEnabled;
@property (nonatomic, strong) NSTimer *assertionWatchdogTimer;
@property (nonatomic, strong) NSTimer *receptionTraceTimer;
@property (nonatomic, copy) NSString *lastReceptionTraceSignature;
@property (nonatomic, copy) NSString *lastViewportConstraintSignature;
@property (nonatomic, assign) CFTimeInterval lastViewportConstraintLogTime;
@property (nonatomic, assign) NSTimeInterval lastReceptionTraceHeartbeatTime;
@property (nonatomic, assign) NSUInteger sceneHostGeneration;
@property (nonatomic, assign) CV3HostLifecycleState hostLifecycleState;
@property (nonatomic, assign) NSUInteger hostContentFailureCount;
@property (nonatomic, assign) NSTimeInterval lastHostContentRecoveryAt;
@property (nonatomic, assign) BOOL hostContentRecoveryInFlight;
@property (nonatomic, assign) NSTimeInterval lastForegroundSceneRepairAt;
@property (nonatomic, assign) BOOL isLiveResizing;
@property (nonatomic, strong) CAGradientLayer *specularHighlight;
@property (nonatomic, strong) CADisplayLink *liquidDisplayLink;
@property (nonatomic, assign) BOOL hasCapturedBaseline;
@property (nonatomic, assign) CGFloat baseRoll;
@property (nonatomic, assign) CGFloat basePitch;
@property (nonatomic, strong) UIImage *stashedRestoreSnapshotImage;
@property (nonatomic, assign) UIInterfaceOrientation stashedRestoreSnapshotOrientation;
// Rendered rotation of the visible space when the snapshot was captured. The
// content orientation alone is not enough: a shell-axis flip rotates what the
// user actually sees without changing the orientation value, which is why a
// fullscreen video restored out of the icon came back upside down.
@property (nonatomic, assign) CGAffineTransform stashedRestoreSnapshotVisualRotation;
@property (nonatomic, copy) NSString *stashAnimationTraceID;
@property (nonatomic, assign) CFTimeInterval stashAnimationTraceStartTime;
@property (nonatomic, copy) NSString *lastOrientationTraceSignature;
@property (nonatomic, copy) NSString *lastSurfaceOrientationAuditSignature;
@property (nonatomic, assign) CFTimeInterval lastSurfaceOrientationAuditTime;

+ (CMMotionManager *)sharedMotionManager;
+ (CGRect)initialFrameForBundleID:(NSString *)bundleID
                           center:(CGPoint)center
                      windowScene:(UIWindowScene *)windowScene;
- (void)startLiquidMotion;
- (void)stopLiquidMotion;
- (instancetype)initWithBundleID:(NSString *)bundleID center:(CGPoint)center windowScene:(UIWindowScene *)windowScene;
- (void)updateSovereigntyAssertion;
- (void)updateAdaptiveColor;
- (void)setWindowFocused:(BOOL)focused;
- (void)promoteFloatingWindowInZOrder;
- (void)animateFocusShadow:(BOOL)focused;
- (void)restoreFromStash;
- (void)handleHideAction;
- (void)releaseSharedGeometryIfNeeded:(NSString *)reason;
- (void)enforceSceneForegroundState;
- (void)attemptToHostSceneWithRetries:(int)retries delay:(double)delay;
- (void)attemptToHostSceneWithRetries:(int)retries delay:(double)delay generation:(NSUInteger)generation;
- (void)detachHostedSceneForReason:(NSString *)reason clearScene:(BOOL)clearScene;
- (void)setHostLifecycleState:(CV3HostLifecycleState)state reason:(NSString *)reason;
- (void)setTargetOrientation:(UIInterfaceOrientation)orientation;
- (void)applyCurrentTransformWithScale:(CGFloat)scale;
- (void)handleTransitionGhosting;
- (void)refreshHostViewPresentation;
- (void)beginHostPresentationRepublishIfNeeded:(NSString *)reason;
- (void)acquireRepublishedHostViewForGeneration:(NSUInteger)generation
                                        oldHost:(UIView *)oldHost
                                   oldContextID:(NSString *)oldContextID
                                        retries:(NSInteger)retries;
- (void)pollRepublishedHostViewForGeneration:(NSUInteger)generation
                                     oldHost:(UIView *)oldHost
                                oldContextID:(NSString *)oldContextID
                                     retries:(NSInteger)retries;
- (void)synchronizeHostedContextLayerGeometry;
- (void)recordVideoFullscreenTrace:(NSString *)phase requestedOrientation:(UIInterfaceOrientation)orientation;
- (void)recordSplitWindowOrientationTrace:(NSString *)phase
                     requestedOrientation:(UIInterfaceOrientation)orientation
                                   source:(NSString *)source;
- (void)recordStrictSplitTrace:(NSString *)phase details:(NSString *)details;
- (void)recordProducerGeometryTrace:(NSString *)phase;
- (void)recordSurfaceOrientationAudit:(NSString *)phase force:(BOOL)force;
- (UIView *)hostViewForScene:(FBScene *)scene;
- (void)disableHostingForCurrentScene;
- (BOOL)hostViewHasRenderableContent;
- (void)recoverHostedPresentationIfNeeded:(NSString *)reason;
- (void)finishHostingWhenRenderableWithRetries:(NSInteger)retries;
- (void)finishHostingWhenRenderableWithRetries:(NSInteger)retries generation:(NSUInteger)generation;
- (void)applyStashedGrabberOrientation;
- (void)physicalDeviceOrientationDidChange:(NSNotification *)notification;
- (void)normalizeStashedGrabberLayout;
- (void)updateStashIconAppearance;
- (CGRect)safeAreaClampedFrame:(CGRect)frame preferredCenter:(CGPoint)preferredCenter preserveSize:(BOOL)preserveSize;
- (CGRect)restorableFrameForOrientation:(UIInterfaceOrientation)orientation preferredCenter:(CGPoint)preferredCenter;
- (CGRect)restorableFramePreservingStashedSizeForOrientation:(UIInterfaceOrientation)orientation preferredCenter:(CGPoint)preferredCenter;
- (CGRect)currentVisualShadowFrame;
- (UIImage *)snapshotImageForRestoreAnimation;
- (void)updateStashedRestoreSnapshotForOrientation:(UIInterfaceOrientation)orientation;
- (void)animateGenieSurfaceImage:(UIImage *)image
                      sourceFrame:(CGRect)sourceFrame
                        iconFrame:(CGRect)iconFrame
                       presenting:(BOOL)presenting
                       completion:(void (^)(void))completion;
- (void)updateResizeHandleAppearance;
- (void)createFloatingHomeBarIfNeeded;
- (void)updateFloatingHomeBarAppearance;
- (void)noteFloatingHomeBarInteraction;
- (void)scheduleFloatingHomeBarAutoHide;
- (void)homeBarAutoHideTimerFired:(NSTimer *)timer;
- (void)layoutFloatingHomeBarForBounds:(CGRect)bounds;
- (NSInteger)preferredHomeBarPlacementForScreenFrame:(CGRect)frame;
- (UIInterfaceOrientation)effectiveResizeOrientation;
- (CGRect)orientedDisplayBoundsForCurrentOrientation;
- (CGRect)physicalDisplaySafeRect;
- (void)resizeLimitsForAspect:(CGFloat)aspect minWidth:(CGFloat *)minWidth maxWidth:(CGFloat *)maxWidth;
- (CGRect)physicalSafeAreaClampedFrame:(CGRect)frame preferredCenter:(CGPoint)preferredCenter preserveSize:(BOOL)preserveSize;
- (CGRect)constrainedFloatingFrameForSize:(CGSize)size preferredCenter:(CGPoint)center;
- (void)startHomeBarResizeSessionIfNeeded;
- (void)handleHomeBarTap:(UITapGestureRecognizer *)gesture;
- (void)handleHomeBarResizePan:(UIPanGestureRecognizer *)gesture;
- (void)activateHostedAppFullscreenAndClose;
- (void)ensureLaunchSplashVisible;
- (void)recordColdLaunchMilestone:(NSString *)milestone details:(NSString *)details;
- (void)recordOrientationTrace:(NSString *)phase force:(BOOL)force;
- (void)recordReceptionTrace:(NSString *)phase force:(BOOL)force;
- (void)recordViewportConstraintAudit:(NSString *)phase force:(BOOL)force;
- (void)receptionTraceTimerFired:(NSTimer *)timer;
- (void)loadAppScene;
- (UIEdgeInsets)currentSafeAreaInsets;
- (void)dismissLaunchSplashAnimated;
- (void)enforcePortraitWindowGeometry;
- (void)applySceneRotationContext:(CV3SceneRotationContext)context force:(BOOL)force;
- (void)applyInterfaceOrientation:(UIInterfaceOrientation)orientation force:(BOOL)force;
- (CGRect)visiblePortraitContentFrame;
- (CGRect)currentHostedSceneBounds;
- (BOOL)applyHostedSceneLayoutToSettings:(id)settings force:(BOOL)force;
- (BOOL)syncHostedSceneLayoutForce:(BOOL)force;
- (void)applyHostedContentOrientation:(UIInterfaceOrientation)orientation source:(uint8_t)source;
- (BOOL)applyForegroundSovereigntyToSettings:(id)settings clearDeactivation:(BOOL)clearDeactivation forceLayout:(BOOL)forceLayout;
- (void)stabilizeForegroundForWorkspaceTransition:(NSString *)reason;
@end

static void CV3ReleaseKeyboardHostingForWindow(CV3FloatingAppWindow *window);

static void CV3PostHostedStateValue(NSString *bundleID, uint64_t state) {
    NSString *notificationName = CV3BundleScopedNotificationName(@"com.xu.chevronv3.hosted",
                                                                  bundleID);
    if (notificationName.length == 0) return;
    int token = -1;
    if (notify_register_check(notificationName.UTF8String, &token) != NOTIFY_STATUS_OK) return;
    uint64_t encodedState = ((uint64_t)CV3HostGeneration << 32) | (state & 0xFFFFFFFFULL);
    notify_set_state(token, encodedState);
    notify_post(notificationName.UTF8String);
    notify_cancel(token);
}

static void CV3PostHostedState(NSString *bundleID, BOOL hosted) {
    CV3PostHostedStateValue(bundleID, hosted ? 1 : 0);
}

static void CV3PublishHostGeneration(void) {
    CV3HostGeneration = arc4random();
    if (CV3HostGeneration == 0) CV3HostGeneration = 1;

    int token = -1;
    if (notify_register_check(CV3HostGenerationNotification, &token) != NOTIFY_STATUS_OK) return;
    notify_set_state(token, CV3HostGeneration);
    notify_post(CV3HostGenerationNotification);
    notify_cancel(token);
}

// --- Custom Resize Handle with Expanded Hit Area ---
@interface CV3ResizeHandleView : UIView
@end
@implementation CV3ResizeHandleView
- (BOOL)pointInside:(CGPoint)point withEvent:(UIEvent *)event {
    // 深度优化敏感度：使用全局常量扩充热区，确保盲操作也能精准捕捉
    CGFloat hitArea = CV3Style.resizeHandleHitArea;
    CGFloat widthDelta = MAX(0, hitArea - self.bounds.size.width);
    CGFloat heightDelta = MAX(0, hitArea - self.bounds.size.height);
    CGRect hitFrame = CGRectInset(self.bounds, -widthDelta/2.0, -heightDelta/2.0);
    return CGRectContainsPoint(hitFrame, point);
}
@end

// --- Custom Stash Grabber with Expanded Hit Area ---
@interface CV3StashGrabberView : UIView
@end
@implementation CV3StashGrabberView
- (BOOL)pointInside:(CGPoint)point withEvent:(UIEvent *)event {
    // 向外扩大 16pt 热区，确保靠近屏幕极边缘时容易捕抓 (满足 44pt 触控规范)
    CGRect hitFrame = CGRectInset(self.bounds, -16.0, -16.0);
    return CGRectContainsPoint(hitFrame, point);
}
@end

%hook UIWindow
- (NSString *)_role {
    if ([self isKindOfClass:[CV3FloatingAppWindow class]]) {
        return @"SBWindowRoleFloatingCanHostLaunchpad";
    }
    return %orig;
}

- (BOOL)_isHomeGestureSupported {
    if ([self isKindOfClass:[CV3FloatingAppWindow class]]) {
        return NO; // 核心：告知系统此窗口不支持 Home 手势，防止其拦截底部上滑并触发中断
    }
    return %orig;
}

- (BOOL)_shouldControlSceneDestruction {
    if ([self isKindOfClass:[CV3FloatingAppWindow class]]) {
        return NO; // 禁止系统自动销毁此窗口关联的场景
    }
    return %orig;
}

- (void)setAlpha:(CGFloat)alpha {
    if ([self isKindOfClass:[CV3FloatingAppWindow class]]) {
        CV3FloatingAppWindow *win = (CV3FloatingAppWindow *)self;
        if (alpha < 1.0 && !win.isClosing && !win.isStashed) {
            %orig(1.0);
            return;
        }
    }
    %orig(alpha);
}

static BOOL CV3PhysicalPointInside(UIWindow *selfWindow, CGPoint point, UIEvent *event) {
    if (![selfWindow isKindOfClass:[CV3FloatingAppWindow class]]) return NO;

    CV3FloatingAppWindow *floatingWindow = (CV3FloatingAppWindow *)selfWindow;
    if (floatingWindow.hidden || floatingWindow.alpha < 0.01 || floatingWindow.isClosing) return NO;

    if (floatingWindow.isStashed) {
        return CGRectContainsPoint(selfWindow.bounds, point);
    }

    if (floatingWindow.homeBarView && !floatingWindow.homeBarView.hidden && floatingWindow.homeBarView.alpha > 0.01) {
        CGRect homeBarFrame = CGRectInset([floatingWindow convertRect:floatingWindow.homeBarView.bounds
                                                              fromView:floatingWindow.homeBarView],
                                          -18.0,
                                          -18.0);
        if (CGRectContainsPoint(homeBarFrame, point)) return YES;
    }

    if (floatingWindow.stashGrabber.alpha > 0.5) {
        CGPoint pInGrabber = [floatingWindow convertPoint:point toView:floatingWindow.stashGrabber];
        if ([floatingWindow.stashGrabber pointInside:pInGrabber withEvent:event]) return YES;
    }

    if (floatingWindow.rootTransformContainer && !floatingWindow.rootTransformContainer.hidden && floatingWindow.rootTransformContainer.alpha > 0.01) {
        CGPoint pInRoot = [floatingWindow convertPoint:point toView:floatingWindow.rootTransformContainer];
        if ([floatingWindow.rootTransformContainer pointInside:pInRoot withEvent:event]) return YES;
    }

    CGRect bounds = selfWindow.bounds;
    CGFloat expansion = CV3Style.resizeHandleWindowExpansion;
    CGRect resizeExtraHitBox = CGRectMake(bounds.size.width - expansion, bounds.size.height - expansion, expansion * 2, expansion * 2);
    if (CGRectContainsPoint(resizeExtraHitBox, point)) return YES;
    
    return NO;
}

- (BOOL)pointInside:(CGPoint)point withEvent:(UIEvent *)event {
    if (![self isKindOfClass:[CV3FloatingAppWindow class]]) return %orig;
    if (((CV3FloatingAppWindow *)self).windowPresentationBlocked) return NO;
    
    // Z-order 点击透传退避算法：如果点击落在更顶层窗口的有效判定区内，则下层主动退避，交由上层响应
    if (floatingWindows && floatingWindows.count > 1) {
        NSInteger myIndex = [floatingWindows indexOfObject:self];
        if (myIndex != NSNotFound) {
            CGPoint screenPoint = [self convertPoint:point toView:nil];
            
            for (NSInteger i = myIndex + 1; i < floatingWindows.count; i++) {
                CV3FloatingAppWindow *upperWin = floatingWindows[i];
                if ([upperWin isKindOfClass:[CV3FloatingAppWindow class]] && !upperWin.hidden && !upperWin.isClosing) {
                    CGPoint localPoint = [upperWin convertPoint:screenPoint fromView:nil];
                    if (CV3PhysicalPointInside(upperWin, localPoint, event)) {
                        return NO;
                    }
                }
            }
        }
    }
    
    return CV3PhysicalPointInside(self, point, event);
}
%end

#import "CV3ScreenTimeGuard.inc"
#import "CV3FloatingAppWindow.inc"

static BOOL CV3ApplyVideoOrientationNotification(uint64_t bundleHash,
                                                 UIInterfaceOrientation orientation,
                                                 uint8_t source) {
    for (CV3FloatingAppWindow *window in [floatingWindows copy]) {
        if (![window isKindOfClass:[CV3FloatingAppWindow class]] || window.isClosing) continue;
        if (CV3StableBundleHash(window.bundleID) != bundleHash) continue;

        NSString *sourceName = CV3VideoOrientationSourceName(source);
        [window recordSplitWindowOrientationTrace:@"notification.before"
                             requestedOrientation:orientation
                                           source:sourceName];
        [window recordVideoFullscreenTrace:@"notification.matched.before" requestedOrientation:orientation];
        [window applyHostedContentOrientation:orientation source:source];
        [window recordVideoFullscreenTrace:@"notification.matched.after" requestedOrientation:orientation];
        [window recordSplitWindowOrientationTrace:@"notification.after"
                             requestedOrientation:orientation
                                           source:sourceName];
        return YES;
    }
    return NO;
}

static void CV3RegisterVideoOrientationBridge(void) {
    if (CV3VideoOrientationNotificationToken >= 0) return;

    int status = notify_register_dispatch(CV3VideoOrientationNotification,
                                          &CV3VideoOrientationNotificationToken,
                                          dispatch_get_main_queue(),
                                          ^(int token) {
        uint64_t state = 0;
        if (notify_get_state(token, &state) != NOTIFY_STATUS_OK) return;

        uint8_t payload = (uint8_t)((state >> 56) & 0xFFULL);
        // Payloads from pre-source builds contained only the orientation byte.
        // Continue accepting those while an already-running hosted app finishes.
        uint8_t source = payload > 0x0F ? (payload >> 4) : 0;
        UIInterfaceOrientation orientation = (UIInterfaceOrientation)(payload & 0x0F);
        uint64_t bundleHash = state & 0x00FFFFFFFFFFFFFFULL;
        if (!CV3IsValidInterfaceOrientation(orientation)) return;

        CV3LogVideoFullscreen(@"[DEBUG-VIDEOFULLSCREEN] phase=notification.received hash=%014llx requested=%ld source=%@ sourceCode=%u windows=%lu",
                              bundleHash,
                              (long)orientation,
                              CV3VideoOrientationSourceName(source),
                              source,
                              (unsigned long)floatingWindows.count);

        if (CV3ApplyVideoOrientationNotification(bundleHash, orientation, source)) return;
        CV3LogVideoFullscreen(@"[DEBUG-VIDEOFULLSCREEN] phase=notification.unmatched hash=%014llx requested=%ld source=%@ sourceCode=%u",
                              bundleHash,
                              (long)orientation,
                              CV3VideoOrientationSourceName(source),
                              source);
    });

    if (status != NOTIFY_STATUS_OK) {
        CV3VideoOrientationNotificationToken = -1;
        CV3LogToFile(@"[Error] VideoBridge Darwin 通知注册失败: %d", status);
    }
}

static NSString *CV3PlaybackTraceEventName(uint8_t event) {
    switch (event) {
        case 1: return @"BridgeLoaded";
        case 2: return @"HostedEnabled";
        case 3: return @"HostedDisabled";
        case 4: return @"WorkspaceShieldEnabled";
        case 5: return @"WorkspaceShieldDisabled";
        case 10: return @"UIApplicationDelegate.applicationWillResignActive";
        case 11: return @"UIApplicationDelegate.applicationDidEnterBackground";
        case 12: return @"UISceneDelegate.sceneWillResignActive";
        case 13: return @"UISceneDelegate.sceneDidEnterBackground";
        case 14: return @"_UISceneLifecycleMultiplexer.deactivation";
        case 15: return @"LifecycleNSNotification";
        case 20: return @"AVAudioSession.setActive(false)";
        case 21: return @"AVAudioSession.setActive(false,options)";
        case 22: return @"AVAudioSessionInterruption";
        case 30: return @"AVPlayer.pause";
        case 31: return @"AVPlayer.setRate(0)";
        case 32: return @"AVPlayer.setRate(0,time,hostTime)";
        case 33: return @"AVAudioPlayer.pause";
        case 34: return @"AVAudioPlayer.stop";
        default: return [NSString stringWithFormat:@"Unknown(%u)", event];
    }
}

static void CV3RegisterPlaybackTraceBridge(void) {
    if (CV3PlaybackTraceNotificationToken >= 0) return;
    int status = notify_register_dispatch(CV3PlaybackTraceNotification,
                                          &CV3PlaybackTraceNotificationToken,
                                          dispatch_get_main_queue(),
                                          ^(int token) {
        uint64_t state = 0;
        if (notify_get_state(token, &state) != NOTIFY_STATUS_OK) return;
        uint8_t event = (uint8_t)((state >> 56) & 0xFFULL);
        uint64_t bundleHash = state & 0x00FFFFFFFFFFFFFFULL;
        NSString *bundleID = nil;
        for (CV3FloatingAppWindow *window in [floatingWindows copy]) {
            if (CV3StableBundleHash(window.bundleID) == bundleHash) {
                bundleID = window.bundleID;
                break;
            }
        }
        CV3LogToFile(@"[Warning][PlaybackTrace] source=Client event=%@ bundle=%@ hash=%014llx workspaceActive=%d switcherVisible=%d floatingCount=%lu",
                     CV3PlaybackTraceEventName(event),
                     bundleID ?: @"UnmappedClient",
                     bundleHash,
                     CV3WorkspaceTransitionActive,
                     CV3SwitcherPresentationActive(),
                     (unsigned long)floatingWindows.count);
    });
    if (status != NOTIFY_STATUS_OK) {
        CV3PlaybackTraceNotificationToken = -1;
        CV3LogToFile(@"[Error][PlaybackTrace] Darwin trace registration failed: %d", status);
    }
}

static void CV3RegisterHostedInteractionBridge(void) {
    if (CV3HostedInteractionNotificationToken >= 0) return;
    int status = notify_register_dispatch(CV3HostedInteractionNotification,
                                          &CV3HostedInteractionNotificationToken,
                                          dispatch_get_main_queue(),
                                          ^(int token) {
        uint64_t bundleHash = 0;
        if (notify_get_state(token, &bundleHash) != NOTIFY_STATUS_OK) return;
        bundleHash &= 0x00FFFFFFFFFFFFFFULL;
        for (CV3FloatingAppWindow *window in [floatingWindows copy]) {
            if (![window isKindOfClass:[CV3FloatingAppWindow class]] ||
                window.isClosing || window.isStashed) continue;
            if (CV3StableBundleHash(window.bundleID) != bundleHash) continue;
            CV3LogHomeBarVisibility(@"[HomeBarTrace] phase=clientInteraction.received bundle=%@ hash=%014llx alpha=%.3f hidden=%d",
                                    window.bundleID, bundleHash,
                                    window.homeBarView.alpha, window.homeBarAutoHidden);
            [window noteFloatingHomeBarInteraction];
            return;
        }
        CV3LogHomeBarVisibility(@"[HomeBarTrace] phase=clientInteraction.unmatched hash=%014llx windows=%lu",
                                bundleHash, (unsigned long)floatingWindows.count);
    });
    if (status != NOTIFY_STATUS_OK) {
        CV3HostedInteractionNotificationToken = -1;
    }
}

static void CV3StabilizeFloatingWindowsForWorkspaceTransition(NSString *reason) {
    if (!floatingWindows || floatingWindows.count == 0) return;

    NSArray *windowsSnapshot = [floatingWindows copy];
    for (CV3FloatingAppWindow *win in windowsSnapshot) {
        if (![win isKindOfClass:[CV3FloatingAppWindow class]] || win.isClosing || win.isStashed) continue;
        [win.hostedSession validateNow:reason];
    }
}

static void CV3SetClientWorkspaceTransitionShield(BOOL enabled) {
    if (!floatingWindows || floatingWindows.count == 0) return;

    for (CV3FloatingAppWindow *win in [floatingWindows copy]) {
        if (![win isKindOfClass:[CV3FloatingAppWindow class]] || win.isClosing || win.isStashed) continue;
        // bit 0 = 正在托管，bit 1 = Home/App Switcher 转场隔离期。
        CV3PostHostedStateValue(win.bundleID, enabled ? 3 : 1);
    }
}

static void CV3EndWorkspaceTransitionProtection(NSString *reason);

static void CV3BeginWorkspaceTransitionProtection(NSString *reason) {
    if (!floatingWindows || floatingWindows.count == 0) return;

    CV3WorkspaceTransitionActive = YES;
    CV3WorkspaceTransitionProtectionToken++;
    NSUInteger token = CV3WorkspaceTransitionProtectionToken;

    CV3LogToFile(@"[Continuity] 开启 Workspace 转场保护: %@", reason ?: @"Unknown");
    CV3LogToFile(@"[Warning][PlaybackTrace] source=SpringBoard event=WorkspaceProtectionBegin reason=%@ switcherVisible=%d",
                 reason ?: @"Unknown", CV3SwitcherPresentationActive());
    CV3SetClientWorkspaceTransitionShield(YES);
    CV3StabilizeFloatingWindowsForWorkspaceTransition(reason ?: @"Begin");

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (token != CV3WorkspaceTransitionProtectionToken) return;
        if (CV3SwitcherPresentationActive()) {
            CV3WorkspaceTransitionActive = YES;
            CV3SetClientWorkspaceTransitionShield(YES);
            CV3StabilizeFloatingWindowsForWorkspaceTransition(@"SwitcherStillVisible");
            CV3LogToFile(@"[Continuity] Switcher 仍可见，取消 1.2 秒保护超时");
            return;
        }
        CV3WorkspaceTransitionActive = NO;
        CV3SetClientWorkspaceTransitionShield(NO);
        CV3StabilizeFloatingWindowsForWorkspaceTransition(@"ProtectionTimeout");
        CV3LogToFile(@"[Continuity] Workspace 转场保护超时收尾");
        CV3LogToFile(@"[Warning][PlaybackTrace] source=SpringBoard event=WorkspaceProtectionTimeout");
    });
}

%hook SBMainSwitcherGestureCoordinator
- (void)_lockOrientation {
    CV3BeginWorkspaceTransitionProtection(@"HomeGestureBegan");
    %orig;
}

- (void)_releaseOrientationLock {
    %orig;
    CV3EndWorkspaceTransitionProtection(@"HomeGestureEnded");
}
%end

static CV3FloatingAppWindow *CV3HostedFloatingWindowForBundleID(NSString *bundleID) {
    if (bundleID.length == 0 || !floatingWindows) return nil;
    for (id object in [floatingWindows copy]) {
        if (![object isKindOfClass:[CV3FloatingAppWindow class]]) continue;
        CV3FloatingAppWindow *window = (CV3FloatingAppWindow *)object;
        if (!window.isClosing && [window.bundleID isEqualToString:bundleID]) return window;
    }
    return nil;
}

static BOOL CV3FocusHostedFloatingWindowForBundleID(NSString *bundleID, NSString *source) {
    if (CV3FullscreenLaunchBypassesFocusGuard(bundleID)) {
        CV3LogToFile(@"[FullscreenLaunch] phase=focusGuard.bypassed bundle=%@ source=%@",
                     bundleID, source ?: @"Unknown");
        return NO;
    }
    if (![NSThread isMainThread]) {
        __block BOOL handled = NO;
        dispatch_sync(dispatch_get_main_queue(), ^{
            handled = CV3FocusHostedFloatingWindowForBundleID(bundleID, source);
        });
        return handled;
    }

    CV3FloatingAppWindow *window = CV3HostedFloatingWindowForBundleID(bundleID);
    if (!window) return NO;

    // Screen Time 限额闸门：被限额的 App 直接拒绝聚焦分屏
    if (!CV3ScreenTimeGateBundleID(bundleID,
                                   [NSString stringWithFormat:@"FocusHosted:%@", source ?: @"Unknown"])) {
        return YES;   // 已拒绝，视为已处理（阻止后续全屏启动）
    }

    CV3ExitExposeModeIfNeeded(window, YES);
    if (window.isStashed) [window restoreFromStash];
    [window promoteFloatingWindowInZOrder];
    [window setWindowFocused:YES];
    CV3LogToFile(@"[LaunchGuard] 已阻止全屏启动并聚焦分屏: %@ source=%@",
                 bundleID, source ?: @"Unknown");
    return YES;
}

static NSString *CV3BundleIdentifierFromIconObject(id icon) {
    if (!icon) return nil;
    NSArray<NSString *> *selectorNames = @[
        @"applicationBundleID", @"bundleIdentifier", @"leafIdentifier", @"displayIdentifier"
    ];
    for (NSString *selectorName in selectorNames) {
        id value = CV3InvokeObject(icon, NSSelectorFromString(selectorName));
        if ([value isKindOfClass:[NSString class]] && [value length] > 0) return value;
    }
    return nil;
}

static id CV3IconFromIconViewObject(id iconView) {
    for (NSString *selectorName in @[@"icon", @"representedIcon"]) {
        id icon = CV3InvokeObject(iconView, NSSelectorFromString(selectorName));
        if (icon) return icon;
    }
    return nil;
}

static BOOL CV3InterceptHostedIconObject(id icon, NSString *source) {
    return CV3FocusHostedFloatingWindowForBundleID(CV3BundleIdentifierFromIconObject(icon), source);
}

// 启动链探针（2026-10-12）：许总要求"从面板打开 app 严格复刻主屏打开的原生弹跳"，
// 需要在真机上观测"主屏点击图标"的完整调用链，找出可复现的触发点。
// 每个候选入口按帧逐条落盘（[SplitTrace] [LaunchChain] 已入白名单），
// 单帧超长由日志层截断保护。纯观测，不改变转发行为。
static void CV3LogLaunchChain(NSString *method, id iconOrView) {
    NSString *bundleID = CV3BundleIdentifierFromIconObject(CV3IconFromIconViewObject(iconOrView) ?: iconOrView);
    NSArray<NSString *> *stack = [NSThread callStackSymbols];
    NSInteger limit = MIN((NSInteger)stack.count, 26);
    for (NSInteger i = 0; i < limit; i++) {
        CV3LogToFile(@"[LaunchChain] method=%@ bundle=%@ frame#%ld %@",
                     method, bundleID ?: @"?", (long)i, stack[(NSUInteger)i]);
    }
}

%hook SBIcon
// iconprobe 实证（iOS 16.5.1）：location 实际是对象（typeEncoding v@:@@），
// 原 NSInteger 声明仅碰巧可转发；这里修正为 id。单参 launchFromLocation: 与
// -launch 在运行时不存在（曾为死 hook），已移除。
- (void)launchFromLocation:(id)location context:(id)context {
    if (CV3InterceptHostedIconObject(self, @"SBIcon.launchFromLocation:context:")) return;
    CV3LogLaunchChain(@"SBIcon.launchFromLocation:context:", self);
    CV3BeginWorkspaceTransitionProtection(@"IconLaunchBegan");
    %orig(location, context);
}
%end

%hook SBIconView
- (void)touchesBegan:(NSSet *)touches withEvent:(UIEvent *)event {
    CV3LogToFile(@"[EditProbe] SBIconView touchesBegan self=%@ gestures=%@", self, self.gestureRecognizers);
    if (CV3InterceptHostedIconObject(CV3IconFromIconViewObject(self), @"SBIconView.touch")) return;
    %orig(touches, event);
}

- (void)touchesMoved:(NSSet *)touches withEvent:(UIEvent *)event {
    CV3LogToFile(@"[EditProbe] SBIconView touchesMoved self=%@", self);
    if (CV3HostedFloatingWindowForBundleID(CV3BundleIdentifierFromIconObject(CV3IconFromIconViewObject(self)))) return;
    %orig(touches, event);
}

- (void)touchesEnded:(NSSet *)touches withEvent:(UIEvent *)event {
    CV3LogToFile(@"[EditProbe] SBIconView touchesEnded self=%@", self);
    if (CV3HostedFloatingWindowForBundleID(CV3BundleIdentifierFromIconObject(CV3IconFromIconViewObject(self)))) return;
    %orig(touches, event);
}

- (void)touchesCancelled:(NSSet *)touches withEvent:(UIEvent *)event {
    CV3LogToFile(@"[EditProbe] SBIconView touchesCancelled self=%@", self);
    if (CV3HostedFloatingWindowForBundleID(CV3BundleIdentifierFromIconObject(CV3IconFromIconViewObject(self)))) return;
    %orig(touches, event);
}
%end

// iOS 16.5.1 may route the edit gesture through a private recognizer action
// instead of the wallpaper handlers above.  Probe every long-press state
// transition, including the owning view and private target/action description.
%hook UILongPressGestureRecognizer
- (void)setState:(UIGestureRecognizerState)state {
    CV3LogToFile(@"[EditProbe] UILongPress state=%ld recognizer=%@ view=%@", (long)state, self, self.view);
    %orig(state);
}
%end

static void CV3EndWorkspaceTransitionProtection(NSString *reason) {
    if (!floatingWindows || floatingWindows.count == 0) return;

    if (CV3SwitcherPresentationActive()) {
        CV3WorkspaceTransitionActive = YES;
        CV3SetClientWorkspaceTransitionShield(YES);
        CV3StabilizeFloatingWindowsForWorkspaceTransition(reason ?: @"SwitcherVisible");
        return;
    }

    CV3WorkspaceTransitionProtectionToken++;
    NSUInteger token = CV3WorkspaceTransitionProtectionToken;

    CV3StabilizeFloatingWindowsForWorkspaceTransition(reason ?: @"End");

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.35 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (token != CV3WorkspaceTransitionProtectionToken) return;
        CV3WorkspaceTransitionActive = NO;
        CV3SetClientWorkspaceTransitionShield(NO);
        CV3StabilizeFloatingWindowsForWorkspaceTransition(@"ProtectionEnd");
        CV3LogToFile(@"[Continuity] 结束 Workspace 转场保护: %@", reason ?: @"Unknown");
        CV3LogToFile(@"[Warning][PlaybackTrace] source=SpringBoard event=WorkspaceProtectionEnd reason=%@",
                     reason ?: @"Unknown");
    });
}

#pragma mark - Main Window
@interface CV3Window : UIWindow <UIGestureRecognizerDelegate, UICollectionViewDataSource, UICollectionViewDelegate, UITextFieldDelegate>
@property (nonatomic, strong) UIView *panelContainer; 
@property (nonatomic, strong) UIVisualEffectView *appPanel; 
@property (nonatomic, strong) UICollectionView *collectionView;
@property (nonatomic, strong) UIView *edgeTriggerView; 
@property (nonatomic, strong) UIView *bezierContainer;
@property (nonatomic, strong) CAShapeLayer *bezierLayer;
@property (nonatomic, strong) UIVisualEffectView *bezierBlur;
// Liquid Glass（主面板专用）：backdrop 玻璃底 / 顶部光泽 / 渐变边缘高光
@property (nonatomic, strong) UIView *liquidGlassHost;
@property (nonatomic, strong) CALayer *liquidGlassBackdrop;
@property (nonatomic, strong) UIView *liquidGlassGlossView;
@property (nonatomic, strong) CAGradientLayer *liquidGlassGlossLayer;
@property (nonatomic, strong) CAGradientLayer *liquidGlassRim;
@property (nonatomic, assign) BOOL isPanelShowing;
@property (nonatomic, assign) BOOL isAnimating;
@property (nonatomic, assign) BOOL isProcessing; 
@property (nonatomic, assign) BOOL launchDebounce;
@property (nonatomic, assign) BOOL needsFullReload; 
@property (nonatomic, assign) BOOL isSuppressedBySystem; 
@property (nonatomic, strong) NSMutableArray<CV3AppInfo *> *apps;

@property (nonatomic, strong) NSTimer *heartbeatTimer;
@property (nonatomic, strong) NSTimer *panelStateRefreshTimer;
@property (nonatomic, assign) BOOL isKeyboardVisible;
@property (nonatomic, assign) BOOL observersRegistered;
@property (nonatomic, assign) BOOL hasBeenMoved;
@property (nonatomic, strong) UIView *resizingHandle;
@property (nonatomic, strong) CAShapeLayer *resizingHandleLayer; 
@property (nonatomic, strong) UITextField *searchField;
@property (nonatomic, strong) NSMutableArray<CV3AppInfo *> *filteredApps;
@property (nonatomic, strong) NSArray<CV3AppInfo *> *recentlyUsedApps; 
@property (nonatomic, strong) NSMutableSet *pinnedBundleIDs; 
@property (nonatomic, strong) UILabel *noResultsLabel;
@property (nonatomic, assign) NSUInteger appLoadGeneration;
@property (nonatomic, strong) UIScreenEdgePanGestureRecognizer *systemEdgePan;
@property (nonatomic, assign) NSUInteger edgeEnvironmentSequence;
@property (nonatomic, assign) BOOL edgeEnvironmentCancelled;
@property (nonatomic, strong) CAGradientLayer *triggerPreviewLayer;
@property (nonatomic, assign) UIInterfaceOrientation targetOrientation;
@property (nonatomic, assign) CGPoint lastTriggerPoint;
@property (nonatomic, assign) CGAffineTransform panelPresentationStartTransform;
@property (nonatomic, assign) CGAffineTransform appPanelPresentationStartTransform;
@property (nonatomic, strong) UIViewPropertyAnimator *panelVisibilityAnimator;
@property (nonatomic, copy) dispatch_block_t panelDismissCompletion;
@property (nonatomic, strong) CAShapeLayer *searchBackground;
@property (nonatomic, strong) UIScrollView *categoryBar; 
@property (nonatomic, copy) NSString *selectedCategory; 
@property (nonatomic, assign) CGAffineTransform baseRotationTransform; 
@property (nonatomic, strong) UIView *contrastBackdrop; 
@property (nonatomic, assign) CGPoint cachedTargetCenter; 

@property (nonatomic, assign) NSInteger interactionCount;


@property (nonatomic, assign) NSUInteger launchRequestGeneration;
@property (nonatomic, copy) NSString *panelPresentationSourceBundleID;


// 拖拽分屏支持
@property (nonatomic, strong) UIImageView *draggedIconView;
@property (nonatomic, strong) CV3AppInfo *draggedAppInfo;
@property (nonatomic, assign) CGPoint dragStartCenter;
@property (nonatomic, assign) CGPoint dragTouchOffset; // 新增：记录触碰点与图标中心的偏移量
@property (nonatomic, strong) UIView *splitDropPreviewView;
@property (nonatomic, strong) CAShapeLayer *splitDropPreviewLayer;

- (void)show;
- (void)requestPanelPresentationFromPoint:(CGPoint)point velocity:(CGFloat)velocity;
- (void)loadAppsAsync;
- (void)applyBackgroundTint:(UIColor *)color;
- (NSString *)_role; 
- (void)applyAgingEffectToCell:(CV3AppCell *)cell withInfo:(CV3AppInfo *)info;
- (void)refreshGlassAccentSurfaces;
- (void)applyGlassAccentToCategoryButton:(UIButton *)button selected:(BOOL)selected suggested:(BOOL)suggested;
- (void)applySceneRotationContext:(CV3SceneRotationContext)context force:(BOOL)force;
- (BOOL)isSystemUIActive;
- (void)setSystemUILevelSuppressed:(BOOL)suppressed;
// 图标呼吸动画的唯一裁决：读 isPanelShowing，命中就挂、否则摘。返回是否新挂了动画。
- (BOOL)applyBreathingToCell:(CV3AppCell *)cell;
- (void)syncAppCellBreathing;
@end

static NSCache *cv3IconCache = nil; 
static CV3Window *sharedWindow = nil;
static BOOL CV3PanelWakeGestureActive = NO;
static __weak UIViewController *CV3HomeScreenSpotlightController = nil;
static BOOL CV3SystemHomeSearchTriggered = NO;
static BOOL CV3HomeSearchDidAppear = NO;
static BOOL CV3HomeSearchDismissalInFlight = NO;
// The launcher edge gesture and Home Screen's pull-down Spotlight gesture
// compete for the same touch sequence.  This flag is raised as soon as the
// launcher gesture begins and remains raised until the panel is fully hidden.
static BOOL CV3HomeScreenPullDownSuppressed = NO;
static dispatch_block_t CV3PendingPanelPresentation = nil;
static NSUInteger CV3PanelPresentationGeneration = 0;
// Spotlight lifecycle forensics: how long a queued panel waited before it was
// released, and how long the dismissSearchView request took to actually remove
// Spotlight (a request that predates the observation by minutes is a bug lead).
static CFTimeInterval CV3PendingPanelQueuedAt = 0;
static CFTimeInterval CV3SearchDismissRequestedAt = 0;

static void CV3SetHomeScreenPullDownSuppressed(BOOL suppressed) {
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            CV3SetHomeScreenPullDownSuppressed(suppressed);
        });
        return;
    }

    CV3HomeScreenPullDownSuppressed = suppressed;
    CV3LogToFile(@"[HomeSearch] phase=suppression.changed suppressed=%d controller=%@ visible=%d",
                 suppressed,
                 CV3HomeScreenSpotlightController,
                 CV3HomeScreenSpotlightController.view.window != nil);
}

static BOOL CV3LauncherOwnsHomeSearchTransition(void) {
    return CV3HomeScreenPullDownSuppressed ||
           CV3PanelWakeGestureActive ||
           CV3PendingPanelPresentation != nil ||
           (sharedWindow && (sharedWindow.isPanelShowing || sharedWindow.isAnimating));
}

static void CV3PresentPendingPanelAfterHomeRestored(void) {
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            CV3PresentPendingPanelAfterHomeRestored();
        });
        return;
    }

    dispatch_block_t presentation = CV3PendingPanelPresentation;
    CV3PendingPanelPresentation = nil;
    CV3SystemHomeSearchTriggered = NO;
    CV3HomeSearchDismissalInFlight = NO;
    NSTimeInterval queuedFor = CV3PendingPanelQueuedAt > 0 ? CACurrentMediaTime() - CV3PendingPanelQueuedAt : -1;
    CV3PendingPanelQueuedAt = 0;
    CV3LogToFile(@"[HomeSearch] phase=dismiss.completion presentation=%d queuedFor=%.3f", presentation != nil, queuedFor);
    if (presentation) presentation();
}

static void CV3ReturnHomeThenPresentPendingPanel(void) {
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            CV3ReturnHomeThenPresentPendingPanel();
        });
        return;
    }
    if (!CV3PendingPanelPresentation || CV3HomeSearchDismissalInFlight) return;

    // dismissSearchView does not cancel Spotlight while its presentation is
    // still between viewWillAppear: and viewDidAppear:. Wait for the native
    // lifecycle boundary instead of marking a dismissal as in-flight before
    // SpringBoard can actually execute it.
    if (!CV3HomeScreenSpotlightController || !CV3HomeSearchDidAppear) {
        CV3LogToFile(@"[HomeSearch] phase=dismiss.awaitingAppearance controller=%@ appeared=%d",
                     CV3HomeScreenSpotlightController,
                     CV3HomeSearchDidAppear);
        return;
    }

    CV3HomeSearchDismissalInFlight = YES;
    CV3SearchDismissRequestedAt = CACurrentMediaTime();
    CV3LogToFile(@"[HomeSearch] phase=dismiss.request controller=%@ visible=%d",
                 CV3HomeScreenSpotlightController,
                 CV3HomeScreenSpotlightController.view.window != nil);
    SBIconController *iconController = [CV3ClassNamed(@"SBIconController") sharedInstance];
    [iconController dismissSearchView];
}

static void CV3QueuePanelPresentationAfterSystemGesture(dispatch_block_t presentation) {
    if (!presentation) return;
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            CV3QueuePanelPresentationAfterSystemGesture(presentation);
        });
        return;
    }

    CV3PanelPresentationGeneration += 1;
    NSUInteger generation = CV3PanelPresentationGeneration;
    CV3PendingPanelPresentation = [presentation copy];
    CV3PendingPanelQueuedAt = CACurrentMediaTime();
    CV3LogToFile(@"[HomeSearch] phase=pending.queued gen=%lu", (unsigned long)generation);

    // Present on the next run-loop turn. A longer delay lets SpringBoard enter
    // the interactive Spotlight transition before our panel becomes visible.
    dispatch_async(dispatch_get_main_queue(), ^{
        if (generation != CV3PanelPresentationGeneration || !CV3PendingPanelPresentation) return;
        UIViewController *controller = CV3HomeScreenSpotlightController;
        BOOL searchVisible = controller && controller.view.window && !controller.view.hidden;
        if (CV3SystemHomeSearchTriggered || searchVisible) {
            CV3ReturnHomeThenPresentPendingPanel();
        } else {
            CV3PresentPendingPanelAfterHomeRestored();
        }
    });
}

static BOOL CV3ShouldSuppressWallpaperLongPress(void) {
    // 该判定挂在 SBIconView touches*、layoutSubviews、手势注册等高频路径上，
    // 原实现每次调用都做 CFPreferencesAppSynchronize（磁盘 IPC），触屏期间会
    // 反复触发。改为 2 秒 TTL 缓存（与 CV3KbRotateFixEnabled 同模式）：调用点
    // 全部在主线程，静态缓存无需加锁；设置页改开关最迟 2 秒内生效。
    static BOOL cached = YES;
    static CFTimeInterval lastCheck = 0.0;
    CFTimeInterval now = CACurrentMediaTime();
    if (lastCheck != 0.0 && now - lastCheck < 2.0) return cached;
    lastCheck = now;

    cached = YES; // 默认开启：禁止主屏幕空白处长按，仅长按 App 允许编辑
    CFPreferencesAppSynchronize(CFSTR("com.xu.chevronv3"));
    CFPropertyListRef val = CFPreferencesCopyAppValue(CFSTR("CV3SuppressWallpaperLongPress"), CFSTR("com.xu.chevronv3"));
    if (val) {
        cached = [(__bridge id)val boolValue];
        CFRelease(val);
    }
    return cached;
}

static BOOL CV3IsEditTriggerFromAppOrContextMenu(id reason) {
    if (reason) {
        NSString *reasonStr = [NSString stringWithFormat:@"%@", reason];
        // 1. 优先判定壁纸/背景/空白处/ScrollView 长按 Reason
        if ([reasonStr rangeOfString:@"Wallpaper" options:NSCaseInsensitiveSearch].location != NSNotFound ||
            [reasonStr rangeOfString:@"Background" options:NSCaseInsensitiveSearch].location != NSNotFound ||
            [reasonStr rangeOfString:@"Empty" options:NSCaseInsensitiveSearch].location != NSNotFound ||
            [reasonStr rangeOfString:@"ScrollView" options:NSCaseInsensitiveSearch].location != NSNotFound ||
            [reasonStr rangeOfString:@"RootFolder" options:NSCaseInsensitiveSearch].location != NSNotFound ||
            [reasonStr rangeOfString:@"HomeScreenLongPress" options:NSCaseInsensitiveSearch].location != NSNotFound) {
            return NO;
        }
        
        // 2. 判定 App 图标上下文菜单或图标手势 Reason
        if ([reasonStr rangeOfString:@"ContextMenu" options:NSCaseInsensitiveSearch].location != NSNotFound ||
            [reasonStr rangeOfString:@"IconView" options:NSCaseInsensitiveSearch].location != NSNotFound ||
            [reasonStr rangeOfString:@"IconLongPress" options:NSCaseInsensitiveSearch].location != NSNotFound ||
            [reasonStr rangeOfString:@"Widget" options:NSCaseInsensitiveSearch].location != NSNotFound ||
            [reasonStr rangeOfString:@"Shortcut" options:NSCaseInsensitiveSearch].location != NSNotFound) {
            return YES;
        }
    }
    
    // 3. 堆栈特征识别：检查是否由 App 图标 (SBIconView) 或上下文菜单 (ContextMenu / SBUIAction) 触发
    NSArray<NSString *> *symbols = [NSThread callStackSymbols];
    for (NSString *sym in symbols) {
        if ([sym rangeOfString:@"SBIconView" options:NSCaseInsensitiveSearch].location != NSNotFound ||
            [sym rangeOfString:@"SBHIconView" options:NSCaseInsensitiveSearch].location != NSNotFound ||
            [sym rangeOfString:@"ContextMenu" options:NSCaseInsensitiveSearch].location != NSNotFound ||
            [sym rangeOfString:@"SBUIAction" options:NSCaseInsensitiveSearch].location != NSNotFound ||
            [sym rangeOfString:@"WidgetIcon" options:NSCaseInsensitiveSearch].location != NSNotFound ||
            [sym rangeOfString:@"handleIconView" options:NSCaseInsensitiveSearch].location != NSNotFound) {
            return YES;
        }
    }
    
    return NO;
}

// Do not disable every long-press recognizer on a Home Screen container.
// SBIconListView can also host the recognizer that forwards a press from an
// SBIconView; disabling that recognizer makes the iOS 10-style "long-press an
// app icon" path impossible.  Only return YES when UIKit/SpringBoard gives us
// a recognizable wallpaper/background action.  The dedicated
// *_handleWallpaperLongPress hooks below remain the fallback when Apple changes
// the private recognizer's description on a future point release.
static BOOL CV3IsWallpaperLongPressGesture(UIGestureRecognizer *gesture) {
    if (!gesture || ![gesture isKindOfClass:[UILongPressGestureRecognizer class]]) return NO;

    NSString *description = [[gesture description] lowercaseString];
    if ([description rangeOfString:@"wallpaper"].location != NSNotFound ||
        [description rangeOfString:@"background"].location != NSNotFound) {
        return YES;
    }

    // UIGestureRecognizer keeps target/action pairs in the private _targets
    // array.  Reading it is intentionally best-effort and guarded because the
    // exact target wrapper differs between iOS releases.
    @try {
        NSArray *targets = [gesture valueForKey:@"_targets"];
        for (id targetAction in targets) {
            NSString *targetDescription = [[targetAction description] lowercaseString];
            if ([targetDescription rangeOfString:@"wallpaper"].location != NSNotFound ||
                [targetDescription rangeOfString:@"background"].location != NSNotFound) {
                return YES;
            }
            id action = nil;
            if ([targetAction respondsToSelector:@selector(action)]) {
                action = [targetAction valueForKey:@"action"];
            }
            NSString *actionString = [[action description] lowercaseString];
            if ([actionString rangeOfString:@"wallpaper"].location != NSNotFound ||
                [actionString rangeOfString:@"background"].location != NSNotFound) {
                return YES;
            }
        }
    } @catch (__unused NSException *exception) {
        // Unknown private target representation: leave the recognizer alone.
    }
    return NO;
}

%hook SBHIconManager
- (void)_handleWallpaperLongPress:(id)gesture {
    CV3LogToFile(@"[EditTrace] SBHIconManager _handleWallpaperLongPress");
    if (CV3ShouldSuppressWallpaperLongPress()) {
        return;
    }
    %orig(gesture);
}

- (void)_handleWallpaperLongPressGestureRecognizer:(id)gesture {
    CV3LogToFile(@"[EditTrace] SBHIconManager _handleWallpaperLongPressGestureRecognizer");
    if (CV3ShouldSuppressWallpaperLongPress()) {
        return;
    }
    %orig(gesture);
}

- (void)_handleWallpaperLongPressGesture:(id)gesture {
    CV3LogToFile(@"[EditTrace] SBHIconManager _handleWallpaperLongPressGesture");
    if (CV3ShouldSuppressWallpaperLongPress()) {
        return;
    }
    %orig(gesture);
}

- (BOOL)_shouldAllowWallpaperLongPressAtPoint:(CGPoint)point {
    CV3LogToFile(@"[EditTrace] SBHIconManager _shouldAllowWallpaperLongPressAtPoint: (%f, %f)", point.x, point.y);
    if (CV3ShouldSuppressWallpaperLongPress()) {
        return NO;
    }
    return %orig(point);
}

- (BOOL)shouldAllowWallpaperLongPress {
    CV3LogToFile(@"[EditTrace] SBHIconManager shouldAllowWallpaperLongPress");
    if (CV3ShouldSuppressWallpaperLongPress()) {
        return NO;
    }
    return %orig;
}

- (BOOL)iconManager:(id)manager shouldAllowWallpaperLongPressAtPoint:(CGPoint)point {
    CV3LogToFile(@"[EditTrace] SBHIconManager iconManager:shouldAllowWallpaperLongPressAtPoint:");
    if (CV3ShouldSuppressWallpaperLongPress()) {
        return NO;
    }
    return %orig(manager, point);
}

- (UILongPressGestureRecognizer *)wallpaperLongPressGestureRecognizer {
    UILongPressGestureRecognizer *g = %orig;
    CV3LogToFile(@"[EditTrace] SBHIconManager wallpaperLongPressGestureRecognizer: %@", g);
    if (g && CV3ShouldSuppressWallpaperLongPress() && CV3IsWallpaperLongPressGesture(g)) {
        g.enabled = NO;
    }
    return g;
}

- (void)setIsEditing:(BOOL)editing {
    CV3LogToFile(@"[EditTrace] SBHIconManager setIsEditing: %d", editing);
    if (editing && CV3ShouldSuppressWallpaperLongPress()) {
        if (!CV3IsEditTriggerFromAppOrContextMenu(nil)) {
            CV3LogToFile(@"[Feature] 成功拦截壁纸/空白处长按编辑模式 (SBHIconManager setIsEditing:)");
            return;
        }
    }
    %orig(editing);
}

- (void)setIsEditing:(BOOL)editing withReason:(id)reason {
    CV3LogToFile(@"[EditTrace] SBHIconManager setIsEditing: %d withReason: %@", editing, reason);
    if (editing && CV3ShouldSuppressWallpaperLongPress()) {
        if (!CV3IsEditTriggerFromAppOrContextMenu(reason)) {
            CV3LogToFile(@"[Feature] 成功拦截壁纸/空白处长按编辑模式 (SBHIconManager setIsEditing:withReason: %@)", reason);
            return;
        }
    }
    %orig(editing, reason);
}

- (void)setIsEditing:(BOOL)editing location:(id)location {
    CV3LogToFile(@"[EditTrace] SBHIconManager setIsEditing: %d location: %@", editing, location);
    if (editing && CV3ShouldSuppressWallpaperLongPress()) {
        if (!CV3IsEditTriggerFromAppOrContextMenu(location)) {
            CV3LogToFile(@"[Feature] 成功拦截壁纸/空白处长按编辑模式 (SBHIconManager setIsEditing:location:)");
            return;
        }
    }
    %orig(editing, location);
}

- (void)setIsEditing:(BOOL)editing animated:(BOOL)animated {
    CV3LogToFile(@"[EditTrace] SBHIconManager setIsEditing: %d animated: %d", editing, animated);
    if (editing && CV3ShouldSuppressWallpaperLongPress()) {
        if (!CV3IsEditTriggerFromAppOrContextMenu(nil)) {
            CV3LogToFile(@"[Feature] 成功拦截壁纸/空白处长按编辑模式 (SBHIconManager setIsEditing:animated:)");
            return;
        }
    }
    %orig(editing, animated);
}
%end

%hook SBHHomeScreenView
- (void)addGestureRecognizer:(UIGestureRecognizer *)gestureRecognizer {
    CV3LogToFile(@"[EditProbe] SBHHomeScreenView addGesture class=%@ desc=%@", NSStringFromClass([gestureRecognizer class]), gestureRecognizer);
    if (CV3ShouldSuppressWallpaperLongPress() && CV3IsWallpaperLongPressGesture(gestureRecognizer)) {
        CV3LogToFile(@"[Feature] 成功禁用了 SBHHomeScreenView 上的 UILongPressGestureRecognizer (%@)", gestureRecognizer);
        gestureRecognizer.enabled = NO;
    }
    %orig(gestureRecognizer);
}

- (void)layoutSubviews {
    %orig;
    if (CV3ShouldSuppressWallpaperLongPress()) {
        for (UIGestureRecognizer *g in self.gestureRecognizers) {
            if (g.enabled && CV3IsWallpaperLongPressGesture(g)) {
                CV3LogToFile(@"[Feature] layoutSubviews 禁用了 SBHHomeScreenView 上的 UILongPressGestureRecognizer (%@)", g);
                g.enabled = NO;
            }
        }
    }
}

- (void)_handleWallpaperLongPress:(id)gesture {
    if (CV3ShouldSuppressWallpaperLongPress()) {
        CV3LogToFile(@"[Feature] 成功拦截 SBHHomeScreenView _handleWallpaperLongPress");
        return;
    }
    %orig(gesture);
}

- (void)handleWallpaperLongPress:(id)gesture {
    if (CV3ShouldSuppressWallpaperLongPress()) {
        CV3LogToFile(@"[Feature] 成功拦截 SBHHomeScreenView handleWallpaperLongPress");
        return;
    }
    %orig(gesture);
}

- (UILongPressGestureRecognizer *)wallpaperLongPressGestureRecognizer {
    UILongPressGestureRecognizer *g = %orig;
    if (g && CV3ShouldSuppressWallpaperLongPress() && CV3IsWallpaperLongPressGesture(g)) {
        g.enabled = NO;
    }
    return g;
}
%end

%hook SBIconListView
- (void)addGestureRecognizer:(UIGestureRecognizer *)gestureRecognizer {
    CV3LogToFile(@"[EditProbe] SBIconListView addGesture class=%@ desc=%@", NSStringFromClass([gestureRecognizer class]), gestureRecognizer);
    if (CV3ShouldSuppressWallpaperLongPress() && CV3IsWallpaperLongPressGesture(gestureRecognizer)) {
        CV3LogToFile(@"[Feature] 成功禁用了 SBIconListView 上的 UILongPressGestureRecognizer (%@)", gestureRecognizer);
        gestureRecognizer.enabled = NO;
    }
    %orig(gestureRecognizer);
}

- (void)layoutSubviews {
    %orig;
    if (CV3ShouldSuppressWallpaperLongPress()) {
        for (UIGestureRecognizer *g in self.gestureRecognizers) {
            if (g.enabled && CV3IsWallpaperLongPressGesture(g)) {
                CV3LogToFile(@"[Feature] layoutSubviews 禁用了 SBIconListView 上的 UILongPressGestureRecognizer (%@)", g);
                g.enabled = NO;
            }
        }
    }
}

- (void)_handleWallpaperLongPress:(id)gesture {
    if (CV3ShouldSuppressWallpaperLongPress()) {
        CV3LogToFile(@"[Feature] 成功拦截 SBIconListView _handleWallpaperLongPress");
        return;
    }
    %orig(gesture);
}

- (void)handleWallpaperLongPress:(id)gesture {
    if (CV3ShouldSuppressWallpaperLongPress()) {
        CV3LogToFile(@"[Feature] 成功拦截 SBIconListView handleWallpaperLongPress");
        return;
    }
    %orig(gesture);
}
%end

%hook SBFWallpaperView
- (void)addGestureRecognizer:(UIGestureRecognizer *)gestureRecognizer {
    if (CV3ShouldSuppressWallpaperLongPress() && CV3IsWallpaperLongPressGesture(gestureRecognizer)) {
        CV3LogToFile(@"[Feature] 成功禁用了 SBFWallpaperView 上的 UILongPressGestureRecognizer (%@)", gestureRecognizer);
        gestureRecognizer.enabled = NO;
    }
    %orig(gestureRecognizer);
}

- (void)layoutSubviews {
    %orig;
    if (CV3ShouldSuppressWallpaperLongPress()) {
        for (UIGestureRecognizer *g in self.gestureRecognizers) {
            if (g.enabled && CV3IsWallpaperLongPressGesture(g)) {
                CV3LogToFile(@"[Feature] layoutSubviews 禁用了 SBFWallpaperView 上的 UILongPressGestureRecognizer (%@)", g);
                g.enabled = NO;
            }
        }
    }
}
%end

%hook SBIconController
- (void)_handleWallpaperLongPress:(id)gesture {
    if (CV3ShouldSuppressWallpaperLongPress()) {
        CV3LogToFile(@"[Feature] 成功拦截主屏幕空白处长按编辑手势 (SBIconController)");
        return;
    }
    %orig(gesture);
}

- (void)handleWallpaperLongPress:(id)gesture {
    if (CV3ShouldSuppressWallpaperLongPress()) {
        return;
    }
    %orig(gesture);
}

- (UILongPressGestureRecognizer *)wallpaperLongPressGestureRecognizer {
    UILongPressGestureRecognizer *g = %orig;
    if (g && CV3ShouldSuppressWallpaperLongPress() && CV3IsWallpaperLongPressGesture(g)) {
        g.enabled = NO;
    }
    return g;
}

- (void)setIsEditing:(BOOL)editing {
    if (editing && CV3ShouldSuppressWallpaperLongPress()) {
        if (!CV3IsEditTriggerFromAppOrContextMenu(nil)) {
            CV3LogToFile(@"[Feature] 成功拦截壁纸/空白处长按编辑模式 (SBIconController setIsEditing:)");
            return;
        }
    }
    %orig(editing);
}

- (void)setIsEditing:(BOOL)editing withReason:(id)reason {
    if (editing && CV3ShouldSuppressWallpaperLongPress()) {
        if (!CV3IsEditTriggerFromAppOrContextMenu(reason)) {
            CV3LogToFile(@"[Feature] 成功拦截壁纸/空白处长按编辑模式 (SBIconController setIsEditing:withReason:)");
            return;
        }
    }
    %orig(editing, reason);
}

- (void)setIsEditing:(BOOL)editing animated:(BOOL)animated {
    if (editing && CV3ShouldSuppressWallpaperLongPress()) {
        if (!CV3IsEditTriggerFromAppOrContextMenu(nil)) {
            CV3LogToFile(@"[Feature] 成功拦截壁纸/空白处长按编辑模式 (SBIconController setIsEditing:animated:)");
            return;
        }
    }
    %orig(editing, animated);
}

%end

%hook SBHFolderController
- (void)setIsEditing:(BOOL)editing {
    if (editing && CV3ShouldSuppressWallpaperLongPress()) {
        if (!CV3IsEditTriggerFromAppOrContextMenu(nil)) {
            CV3LogToFile(@"[Feature] 成功拦截 SBHFolderController setIsEditing:");
            return;
        }
    }
    %orig(editing);
}
- (void)setIsEditing:(BOOL)editing animated:(BOOL)animated {
    if (editing && CV3ShouldSuppressWallpaperLongPress()) {
        if (!CV3IsEditTriggerFromAppOrContextMenu(nil)) {
            CV3LogToFile(@"[Feature] 成功拦截 SBHFolderController setIsEditing:animated:");
            return;
        }
    }
    %orig(editing, animated);
}
- (void)_handleWallpaperLongPress:(id)gesture {
    if (CV3ShouldSuppressWallpaperLongPress()) {
        CV3LogToFile(@"[Feature] 成功拦截 SBHFolderController _handleWallpaperLongPress");
        return;
    }
    %orig(gesture);
}
%end

%hook SBHFolderViewController
- (void)setIsEditing:(BOOL)editing {
    if (editing && CV3ShouldSuppressWallpaperLongPress()) {
        if (!CV3IsEditTriggerFromAppOrContextMenu(nil)) {
            CV3LogToFile(@"[Feature] 成功拦截 SBHFolderViewController setIsEditing:");
            return;
        }
    }
    %orig(editing);
}
- (void)setIsEditing:(BOOL)editing animated:(BOOL)animated {
    if (editing && CV3ShouldSuppressWallpaperLongPress()) {
        if (!CV3IsEditTriggerFromAppOrContextMenu(nil)) {
            CV3LogToFile(@"[Feature] 成功拦截 SBHFolderViewController setIsEditing:animated:");
            return;
        }
    }
    %orig(editing, animated);
}
- (void)_handleWallpaperLongPress:(id)gesture {
    if (CV3ShouldSuppressWallpaperLongPress()) {
        CV3LogToFile(@"[Feature] 成功拦截 SBHFolderViewController _handleWallpaperLongPress");
        return;
    }
    %orig(gesture);
}
%end

%hook SBHRootFolderController
- (void)setIsEditing:(BOOL)editing {
    if (editing && CV3ShouldSuppressWallpaperLongPress()) {
        if (!CV3IsEditTriggerFromAppOrContextMenu(nil)) {
            CV3LogToFile(@"[Feature] 成功拦截 SBHRootFolderController setIsEditing:");
            return;
        }
    }
    %orig(editing);
}
- (void)setIsEditing:(BOOL)editing animated:(BOOL)animated {
    if (editing && CV3ShouldSuppressWallpaperLongPress()) {
        if (!CV3IsEditTriggerFromAppOrContextMenu(nil)) {
            CV3LogToFile(@"[Feature] 成功拦截 SBHRootFolderController setIsEditing:animated:");
            return;
        }
    }
    %orig(editing, animated);
}
- (void)_handleWallpaperLongPress:(id)gesture {
    if (CV3ShouldSuppressWallpaperLongPress()) {
        CV3LogToFile(@"[Feature] 成功拦截 SBHRootFolderController _handleWallpaperLongPress");
        return;
    }
    %orig(gesture);
}
%end

%hook SBHRootFolderViewController
- (void)setIsEditing:(BOOL)editing {
    if (editing && CV3ShouldSuppressWallpaperLongPress()) {
        if (!CV3IsEditTriggerFromAppOrContextMenu(nil)) {
            CV3LogToFile(@"[Feature] 成功拦截 SBHRootFolderViewController setIsEditing:");
            return;
        }
    }
    %orig(editing);
}
- (void)setIsEditing:(BOOL)editing animated:(BOOL)animated {
    if (editing && CV3ShouldSuppressWallpaperLongPress()) {
        if (!CV3IsEditTriggerFromAppOrContextMenu(nil)) {
            CV3LogToFile(@"[Feature] 成功拦截 SBHRootFolderViewController setIsEditing:animated:");
            return;
        }
    }
    %orig(editing, animated);
}
- (void)_handleWallpaperLongPress:(id)gesture {
    if (CV3ShouldSuppressWallpaperLongPress()) {
        CV3LogToFile(@"[Feature] 成功拦截 SBHRootFolderViewController _handleWallpaperLongPress");
        return;
    }
    %orig(gesture);
}
%end

%hook SBHFolderView
- (void)_handleWallpaperLongPress:(id)gesture {
    if (CV3ShouldSuppressWallpaperLongPress()) {
        CV3LogToFile(@"[Feature] 成功拦截 SBHFolderView _handleWallpaperLongPress");
        return;
    }
    %orig(gesture);
}
- (void)handleWallpaperLongPress:(id)gesture {
    if (CV3ShouldSuppressWallpaperLongPress()) {
        CV3LogToFile(@"[Feature] 成功拦截 SBHFolderView handleWallpaperLongPress");
        return;
    }
    %orig(gesture);
}
- (UILongPressGestureRecognizer *)wallpaperLongPressGestureRecognizer {
    UILongPressGestureRecognizer *g = %orig;
    if (g && CV3ShouldSuppressWallpaperLongPress() && CV3IsWallpaperLongPressGesture(g)) {
        g.enabled = NO;
    }
    return g;
}
%end

%hook SBHRootFolderView
- (void)_handleWallpaperLongPress:(id)gesture {
    if (CV3ShouldSuppressWallpaperLongPress()) {
        CV3LogToFile(@"[Feature] 成功拦截 SBHRootFolderView _handleWallpaperLongPress");
        return;
    }
    %orig(gesture);
}
- (void)handleWallpaperLongPress:(id)gesture {
    if (CV3ShouldSuppressWallpaperLongPress()) {
        CV3LogToFile(@"[Feature] 成功拦截 SBHRootFolderView handleWallpaperLongPress");
        return;
    }
    %orig(gesture);
}
- (UILongPressGestureRecognizer *)wallpaperLongPressGestureRecognizer {
    UILongPressGestureRecognizer *g = %orig;
    if (g && CV3ShouldSuppressWallpaperLongPress()) {
        g.enabled = NO;
    }
    return g;
}
%end

%hook SBHHomeScreenViewController
- (void)_handleWallpaperLongPress:(id)gesture {
    if (CV3ShouldSuppressWallpaperLongPress()) {
        CV3LogToFile(@"[Feature] 成功拦截 SBHHomeScreenViewController _handleWallpaperLongPress");
        return;
    }
    %orig(gesture);
}
- (void)handleWallpaperLongPress:(id)gesture {
    if (CV3ShouldSuppressWallpaperLongPress()) {
        CV3LogToFile(@"[Feature] 成功拦截 SBHHomeScreenViewController handleWallpaperLongPress");
        return;
    }
    %orig(gesture);
}
- (void)setIsEditing:(BOOL)editing {
    if (editing && CV3ShouldSuppressWallpaperLongPress()) {
        if (!CV3IsEditTriggerFromAppOrContextMenu(nil)) {
            CV3LogToFile(@"[Feature] 成功拦截 SBHHomeScreenViewController setIsEditing:");
            return;
        }
    }
    %orig(editing);
}
- (void)setIsEditing:(BOOL)editing animated:(BOOL)animated {
    if (editing && CV3ShouldSuppressWallpaperLongPress()) {
        if (!CV3IsEditTriggerFromAppOrContextMenu(nil)) {
            CV3LogToFile(@"[Feature] 成功拦截 SBHHomeScreenViewController setIsEditing:animated:");
            return;
        }
    }
    %orig(editing, animated);
}
%end

@interface SBHomeScreenSpotlightViewController : UIViewController
@end

%hook SBHomeScreenSpotlightViewController
- (void)viewWillAppear:(BOOL)animated {
    CV3HomeScreenSpotlightController = self;
    CV3HomeSearchDidAppear = NO;
    if (CV3LauncherOwnsHomeSearchTransition()) {
        CV3SystemHomeSearchTriggered = YES;
    }
    CV3LogToFile(@"[HomeSearch] phase=viewWillAppear launcherOwns=%d suppressed=%d",
                 CV3LauncherOwnsHomeSearchTransition(), CV3HomeScreenPullDownSuppressed);
    %orig(animated);
}

- (void)viewDidAppear:(BOOL)animated {
    %orig(animated);
    CV3HomeScreenSpotlightController = self;
    CV3HomeSearchDidAppear = YES;
    CV3LogToFile(@"[HomeSearch] phase=viewDidAppear launcherOwns=%d suppressed=%d",
                 CV3LauncherOwnsHomeSearchTransition(), CV3HomeScreenPullDownSuppressed);
    if (CV3LauncherOwnsHomeSearchTransition()) {
        CV3SystemHomeSearchTriggered = YES;
        CV3ReturnHomeThenPresentPendingPanel();
    }
}

- (void)viewDidDisappear:(BOOL)animated {
    %orig(animated);
    CV3HomeSearchDidAppear = NO;
    NSTimeInterval sinceDismissRequest = CV3SearchDismissRequestedAt > 0 ? CACurrentMediaTime() - CV3SearchDismissRequestedAt : -1;
    CV3SearchDismissRequestedAt = 0;
    CV3LogToFile(@"[HomeSearch] phase=viewDidDisappear pending=%d suppressed=%d sinceDismissRequest=%.3f",
                 CV3PendingPanelPresentation != nil, CV3HomeScreenPullDownSuppressed, sinceDismissRequest);
    if (CV3HomeScreenSpotlightController == self) {
        CV3HomeScreenSpotlightController = nil;
    }
    if (CV3PendingPanelPresentation && CV3HomeSearchDismissalInFlight) {
        CV3PresentPendingPanelAfterHomeRestored();
    }
}
%end

static CGFloat CGPointDistance(CGPoint p1, CGPoint p2) {
    return sqrt(pow(p1.x - p2.x, 2) + pow(p1.y - p2.y, 2));
}

static const CGFloat kCV3PanelDragLiftScale = 1.025;
static const NSTimeInterval kCV3PanelDragLiftDuration = 0.22;
static const CGFloat kCV3PanelDragLiftDamping = 0.82;
static const CGFloat kCV3PanelDragLiftVelocity = 0.6;
static const NSTimeInterval kCV3PanelDragReleaseDuration = 0.52;
static const CGFloat kCV3PanelDragReleaseDamping = 0.88;
static const CGFloat kCV3PanelDragReleaseMinVelocity = 0.25;
static const CGFloat kCV3PanelDragReleaseMaxVelocity = 2.2;
static const CGFloat kCV3PanelDragReleaseVelocityDivisor = 1100.0;
static const CGFloat kCV3AppDragLongPressAllowableMovement = 6.0;
static const CGFloat kCV3AppDragScrollVelocityGate = 80.0;
static const CGFloat kCV3KeyboardCriticalResultsReserve = 60.0;
static const CGFloat kCV3KeyboardAvoidanceBreath = 10.0;

static CGFloat CV3ClampedSpringVelocity(CGFloat velocity, CGFloat divisor, CGFloat minVelocity, CGFloat maxVelocity) {
    CGFloat normalizedVelocity = fabs(velocity) / divisor;
    return MIN(maxVelocity, MAX(minVelocity, normalizedVelocity));
}

static BOOL CV3ScrollViewIsActivelyControlled(UIScrollView *scrollView) {
    return scrollView.tracking || scrollView.dragging || scrollView.decelerating;
}

static CGPoint CV3ClampedContentOffsetForScrollView(UIScrollView *scrollView, CGPoint contentOffset) {
    UIEdgeInsets inset;
    if (@available(iOS 11.0, *)) {
        inset = scrollView.adjustedContentInset;
    } else {
        inset = scrollView.contentInset;
    }

    CGFloat minX = -inset.left;
    CGFloat minY = -inset.top;
    CGFloat maxX = MAX(minX, scrollView.contentSize.width - scrollView.bounds.size.width + inset.right);
    CGFloat maxY = MAX(minY, scrollView.contentSize.height - scrollView.bounds.size.height + inset.bottom);

    contentOffset.x = MIN(maxX, MAX(minX, contentOffset.x));
    contentOffset.y = MIN(maxY, MAX(minY, contentOffset.y));
    return contentOffset;
}

static CV3AppInfo *CV3CopyAppInfo(CV3AppInfo *source) {
    if (!source) return nil;

    CV3AppInfo *info = [[CV3AppInfo alloc] init];
    info.name = source.name;
    info.bundleId = source.bundleId;
    info.icon = source.icon;
    info.pinyinInitial = source.pinyinInitial;
    info.category = source.category;
    info.isPinned = source.isPinned;
    info.unreadCount = source.unreadCount;
    info.lastUsedDate = source.lastUsedDate;
    return info;
}

#pragma mark - Helper: Color Extraction

static void CV3UpdateAdaptiveTint(NSString *bundleId) {
    if (!sharedWindow || !bundleId) return;
    [sharedWindow applyBackgroundTint:nil];
}

static BOOL CV3KeyboardSuppressedByPanel = NO;
static void CV3SetKeyboardSuppressedByPanel(BOOL suppressed);

@protocol LSApplicationWorkspaceObserverProtocol <NSObject>
@optional
- (void)applicationsDidInstall:(NSArray *)applications;
- (void)applicationsDidUninstall:(NSArray *)applications;
@end

@interface CV3AppObserver : NSObject <LSApplicationWorkspaceObserverProtocol>
+ (instancetype)sharedObserver;
@end

@implementation CV3AppObserver
+ (instancetype)sharedObserver {
    static CV3AppObserver *observer = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        observer = [[CV3AppObserver alloc] init];
    });
    return observer;
}

- (void)applicationsDidInstall:(NSArray *)applications {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (sharedWindow) {
            sharedWindow.needsFullReload = YES;
            if (sharedWindow.isPanelShowing) [sharedWindow loadAppsAsync];
        }
    });
}

- (void)applicationsDidUninstall:(NSArray *)applications {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (sharedWindow) {
            sharedWindow.needsFullReload = YES;
            if (sharedWindow.isPanelShowing) [sharedWindow loadAppsAsync];
        }
    });
}
@end

#pragma mark - Quick Access View (Keyboard Accessory)
@interface CV3QuickAccessView : UIView
@property (nonatomic, strong) NSArray<CV3AppInfo *> *apps;
@property (nonatomic, copy) void (^selectionHandler)(CV3AppInfo *info);
- (instancetype)initWithApps:(NSArray *)apps selectionHandler:(void (^)(CV3AppInfo *))handler;
@end

@implementation CV3QuickAccessView

- (CGSize)intrinsicContentSize {
    return CGSizeMake(UIViewNoIntrinsicMetric, 54.0);
}

- (CGSize)sizeThatFits:(CGSize)size {
    return CGSizeMake(size.width, 54.0);
}

- (instancetype)initWithApps:(NSArray *)apps selectionHandler:(void (^)(CV3AppInfo *))handler {
    self = [super initWithFrame:CGRectMake(0, 0, [UIScreen mainScreen].bounds.size.width, 54.0)];
    if (self) {
        self.apps = apps;
        self.selectionHandler = handler;
        self.clipsToBounds = YES;
        self.autoresizingMask = UIViewAutoresizingFlexibleWidth;
        
        UIVisualEffectView *blur = [[UIVisualEffectView alloc] initWithEffect:nil];
        blur.frame = self.bounds;
        blur.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        blur.clipsToBounds = YES;
        [self addSubview:blur];
        CV3ApplyGlassAccentStyle(blur,
                                 blur.contentView,
                                 CV3EnsureGlassAccentLayer(blur.contentView),
                                 nil,
                                 0.0,
                                 0.52,
                                 YES);
        // Liquid Glass：键盘候选条玻璃底（公用配方）
        BOOL quickAccessGlassCreated = NO;
        CV3LiquidGlassEnsureBackdrop(self,
                                     @"CV3QuickAccessLiquidGlassBackdrop",
                                     CV3LiquidGlassRecipeControl(),
                                     0.0,
                                     &quickAccessGlassCreated);
        if (quickAccessGlassCreated) {
            CV3LogToFile(@"[LiquidGlass] installed surface=quick-access size=%.0fx%.0f",
                         self.bounds.size.width, self.bounds.size.height);
        }
        
        UIScrollView *scroll = [[UIScrollView alloc] initWithFrame:self.bounds];
        scroll.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        scroll.showsHorizontalScrollIndicator = NO;
        [self addSubview:scroll];
        
        CGFloat x = 12.0;
        for (CV3AppInfo *info in apps) {
            UIButton *btn = [UIButton buttonWithType:UIButtonTypeCustom];
            btn.frame = CGRectMake(x, 7.0, 40.0, 40.0);
            btn.layer.cornerRadius = 10.0;
            if (@available(iOS 13.0, *)) {
                btn.layer.cornerCurve = kCACornerCurveContinuous;
            }
            btn.clipsToBounds = YES;
            CV3ApplyGlassAccentStyle(btn,
                                     btn,
                                     CV3EnsureGlassAccentLayer(btn),
                                     nil,
                                     10.0,
                                     0.34,
                                     NO);
            CV3LiquidGlassEnsureBackdrop(btn,
                                         @"CV3QuickAccessBtnLiquidGlassBackdrop",
                                         CV3LiquidGlassRecipeControl(),
                                         10.0,
                                         NULL);
            
            UIImage *iconImage = info.icon ?: (info.bundleId ? [cv3IconCache objectForKey:info.bundleId] : nil);
            [btn setImage:iconImage forState:UIControlStateNormal];
            btn.imageView.contentMode = UIViewContentModeScaleAspectFit;
            
            btn.tag = [apps indexOfObject:info];
            [btn addTarget:self action:@selector(appTapped:) forControlEvents:UIControlEventTouchUpInside];
            [scroll addSubview:btn];
            x += 50.0;
        }
        scroll.contentSize = CGSizeMake(x + 6.0, 54.0);
    }
    return self;
}

- (void)appTapped:(UIButton *)sender {
    if (self.selectionHandler && sender.tag < self.apps.count) {
        self.selectionHandler(self.apps[sender.tag]);
    }
}
@end

#import "CV3WorkspaceSupport.h"
#import "CV3Window.inc"

#pragma mark - Notification delivery -> floating split

static BOOL CV3LooksLikeBundleIdentifier(NSString *candidate) {
    if (![candidate isKindOfClass:[NSString class]] || candidate.length < 3 || candidate.length > 256) return NO;
    if (![candidate containsString:@"."] || [candidate containsString:@" "]) return NO;

    NSCharacterSet *allowed = [NSCharacterSet characterSetWithCharactersInString:
                               @"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-"];
    for (NSUInteger index = 0; index < candidate.length; index++) {
        if (![allowed characterIsMember:[candidate characterAtIndex:index]]) return NO;
    }
    return YES;
}

static NSString *CV3NotificationActionIdentifierFromObject(id object, NSUInteger depth) {
    if (!object || depth > 3) return nil;

    if ([object isKindOfClass:[NSDictionary class]]) {
        NSDictionary *dictionary = (NSDictionary *)object;
        for (NSString *key in @[@"actionIdentifier", @"identifier"]) {
            id value = dictionary[key];
            if ([value isKindOfClass:[NSString class]] && [value length] > 0) return value;
        }
        for (NSString *key in @[@"action", @"response", @"notificationAction", @"bulletinAction"]) {
            NSString *identifier = CV3NotificationActionIdentifierFromObject(dictionary[key], depth + 1);
            if (identifier.length > 0) return identifier;
        }
        return nil;
    }

    for (NSString *selectorName in @[@"actionIdentifier", @"identifier"]) {
        id value = CV3InvokeObject(object, NSSelectorFromString(selectorName));
        if ([value isKindOfClass:[NSString class]] && [value length] > 0) return value;
    }
    for (NSString *selectorName in @[@"action", @"response", @"notificationAction", @"bulletinAction"]) {
        id nested = CV3InvokeObject(object, NSSelectorFromString(selectorName));
        if (!nested || nested == object) continue;
        NSString *identifier = CV3NotificationActionIdentifierFromObject(nested, depth + 1);
        if (identifier.length > 0) return identifier;
    }
    return nil;
}

static NSString *CV3NotificationActionLaunchBundleID(id object, NSUInteger depth) {
    if (!object || depth > 3) return nil;

    if ([object isKindOfClass:[NSDictionary class]]) {
        NSDictionary *dictionary = (NSDictionary *)object;
        for (NSString *key in @[@"launchBundleID", @"bundleIdentifier", @"sectionIdentifier", @"sectionID"]) {
            id value = dictionary[key];
            if ([value isKindOfClass:[NSString class]] && CV3LooksLikeBundleIdentifier(value)) return value;
        }
        for (NSString *key in @[@"action", @"response", @"notificationAction", @"bulletinAction"]) {
            NSString *bundleID = CV3NotificationActionLaunchBundleID(dictionary[key], depth + 1);
            if (bundleID.length > 0) return bundleID;
        }
        return nil;
    }

    for (NSString *selectorName in @[@"launchBundleID", @"bundleIdentifier", @"sectionIdentifier", @"sectionID"]) {
        id value = CV3InvokeObject(object, NSSelectorFromString(selectorName));
        if ([value isKindOfClass:[NSString class]] && CV3LooksLikeBundleIdentifier(value)) return value;
    }
    for (NSString *selectorName in @[@"action", @"response", @"notificationAction", @"bulletinAction"]) {
        id nested = CV3InvokeObject(object, NSSelectorFromString(selectorName));
        if (!nested || nested == object) continue;
        NSString *bundleID = CV3NotificationActionLaunchBundleID(nested, depth + 1);
        if (bundleID.length > 0) return bundleID;
    }
    return nil;
}

static BOOL CV3NotificationActionIsDefaultOpen(id action, id parameters) {
    NSString *identifier = CV3NotificationActionIdentifierFromObject(action, 0);
    if (identifier.length == 0) {
        identifier = CV3NotificationActionIdentifierFromObject(parameters, 0);
    }

    if (identifier.length > 0) {
        return [identifier isEqualToString:@"com.apple.UNNotificationDefaultActionIdentifier"] ||
               [identifier isEqualToString:@"UNNotificationDefaultActionIdentifier"];
    }

    for (id object in @[action ?: [NSNull null], parameters ?: [NSNull null]]) {
        if (object == [NSNull null]) continue;
        SEL selector = NSSelectorFromString(@"isDefaultAction");
        if (CV3TargetRespondsToSelector(object, selector) &&
            ((BOOL (*)(id, SEL))objc_msgSend)(object, selector)) {
            return YES;
        }
    }

    return CV3NotificationActionLaunchBundleID(action, 0).length > 0;
}

static NSString *CV3NotificationBundleIDFromObject(id object, NSUInteger depth) {
    if (!object || depth > 5) return nil;

    if ([object isKindOfClass:[NSString class]]) {
        return CV3LooksLikeBundleIdentifier(object) ? object : nil;
    }

    if ([object isKindOfClass:[NSArray class]] || [object isKindOfClass:[NSSet class]]) {
        for (id child in object) {
            NSString *bundleID = CV3NotificationBundleIDFromObject(child, depth + 1);
            if (bundleID.length > 0) return bundleID;
        }
        return nil;
    }

    if ([object isKindOfClass:[NSDictionary class]]) {
        NSArray<NSString *> *preferredKeys = @[
            @"sectionIdentifier", @"sectionID", @"clientIdentifier", @"bundleIdentifier",
            @"applicationBundleIdentifier", @"applicationIdentifier", @"displayIdentifier",
            @"publisher", @"targetBundleIdentifier"
        ];
        NSDictionary *dictionary = (NSDictionary *)object;
        for (NSString *key in preferredKeys) {
            NSString *bundleID = CV3NotificationBundleIDFromObject(dictionary[key], depth + 1);
            if (bundleID.length > 0) return bundleID;
        }
        for (id value in [dictionary allValues]) {
            NSString *bundleID = CV3NotificationBundleIDFromObject(value, depth + 1);
            if (bundleID.length > 0) return bundleID;
        }
        return nil;
    }

    NSArray<NSString *> *selectors = @[
        @"sectionIdentifier", @"sectionID", @"clientIdentifier", @"bundleIdentifier",
        @"applicationBundleIdentifier", @"applicationIdentifier", @"displayIdentifier",
        @"publisher", @"targetBundleIdentifier", @"notificationRequest", @"notification",
        @"request", @"bulletin", @"content", @"userInfo", @"source", @"section",
        @"destination", @"target", @"displayItem", @"displayItems", @"item", @"items",
        @"entities", @"activatedEntities", @"application", @"applicationContext",
        @"transitionContext", @"layout", @"appLayout", @"identifier"
    ];
    for (NSString *selectorName in selectors) {
        id value = CV3InvokeObject(object, NSSelectorFromString(selectorName));
        NSString *bundleID = CV3NotificationBundleIDFromObject(value, depth + 1);
        if (bundleID.length > 0) return bundleID;
    }

    return nil;
}

static BOOL CV3DeviceIsLocked(void) {
    id lockManager = CV3InvokeObject(CV3ClassNamed(@"SBLockScreenManager"), @selector(sharedInstance));
    for (NSString *selectorName in @[@"isUILocked", @"isLocked"]) {
        SEL selector = NSSelectorFromString(selectorName);
        if (CV3TargetRespondsToSelector(lockManager, selector)) {
            return ((BOOL (*)(id, SEL))objc_msgSend)(lockManager, selector);
        }
    }
    return CV3LockScreenPresented;
}

static BOOL CV3HandleUnlockedBannerTap(id primaryObject, id secondaryObject, NSString *source) {
    if (![NSThread isMainThread]) {
        __block BOOL handled = NO;
        dispatch_sync(dispatch_get_main_queue(), ^{
            handled = CV3HandleUnlockedBannerTap(primaryObject, secondaryObject, source);
        });
        return handled;
    }

    BOOL locked = CV3DeviceIsLocked();
    CV3LogToFile(@"[NotificationSplit] phase=handler.enter source=%@ primary=%@ secondary=%@ locked=%d",
                 source ?: @"Unknown",
                 primaryObject ? NSStringFromClass([primaryObject class]) : @"nil",
                 secondaryObject ? NSStringFromClass([secondaryObject class]) : @"nil",
                 locked);
    if (locked) return NO;

    NSString *bundleID = CV3NotificationBundleIDFromObject(primaryObject, 0);
    if (bundleID.length == 0) bundleID = CV3NotificationBundleIDFromObject(secondaryObject, 0);
    if (bundleID.length == 0 || [bundleID isEqualToString:@"com.apple.springboard"]) {
        CV3LogToFile(@"[NotificationSplit] phase=resolver.miss source=%@ primary=%@ secondary=%@",
                     source ?: @"Unknown",
                     primaryObject ? NSStringFromClass([primaryObject class]) : @"nil",
                     secondaryObject ? NSStringFromClass([secondaryObject class]) : @"nil");
        return NO;
    }

    id appController = [CV3ClassNamed(@"SBApplicationController") sharedInstance];
    if ([appController respondsToSelector:@selector(applicationWithBundleIdentifier:)]) {
        id application = CV3InvokeObject1(appController,
                                          @selector(applicationWithBundleIdentifier:), bundleID);
        if (!application) {
            CV3LogToFile(@"[NotificationSplit] 忽略无法映射到应用的横幅点击: %@ (%@)", bundleID, source ?: @"Unknown");
            return NO;
        }
    }

    CV3ExitExposeModeIfNeeded(nil, NO);
    if (sharedWindow) CV3HidePanelImmediately(sharedWindow);
    BOOL opened = CV3OpenBundleInFloatingWindow(bundleID, source ?: @"UnlockedBannerTap");
    CV3LogToFile(@"[NotificationSplit] 灵动岛横幅点击开启分屏: %@ source=%@ success=%d",
                 bundleID, source ?: @"Unknown", opened);
    return opened;
}

static const char *CV3SimulatedNotificationName = "com.xu.chevronv3.simulate-notification";
static id CV3CapturedBulletinNotificationSource = nil;

static void CV3SetBulletinValue(id bulletin, NSString *key, id value) {
    if (!bulletin || key.length == 0 || !value) return;
    @try {
        [bulletin setValue:value forKey:key];
    } @catch (NSException *exception) {
        CV3LogToFile(@"[NotificationSplit][NativeTest] 无法设置 %@.%@: %@",
                     NSStringFromClass([bulletin class]), key, exception.reason);
    }
}

static id CV3CreateNativeTestBulletin(NSString *bundleID) {
    Class bulletinClass = CV3ClassNamed(@"BBBulletinRequest");
    if (!bulletinClass) {
        CV3LogToFile(@"[NotificationSplit][NativeTest] BBBulletinRequest 不存在");
        return nil;
    }

    id proxy = CV3InvokeObject1(CV3ClassNamed(@"LSApplicationProxy"),
                                @selector(applicationProxyForIdentifier:),
                                bundleID);
    if (!proxy) {
        proxy = CV3InvokeObject1(CV3ClassNamed(@"LSApplicationProxy"),
                                 @selector(applicationProxyForBundleIdentifier:),
                                 bundleID);
    }
    NSString *appName = CV3InvokeObject(proxy, @selector(localizedName));
    if (appName.length == 0) appName = bundleID;

    id bulletin = [[bulletinClass alloc] init];
    NSString *identifier = [[NSUUID UUID] UUIDString];
    NSDate *now = [NSDate date];
    CV3SetBulletinValue(bulletin, @"sectionID", bundleID);
    CV3SetBulletinValue(bulletin, @"section", bundleID);
    CV3SetBulletinValue(bulletin, @"bulletinID", identifier);
    CV3SetBulletinValue(bulletin, @"bulletinVersionID", identifier);
    CV3SetBulletinValue(bulletin, @"publisherBulletinID", identifier);
    CV3SetBulletinValue(bulletin, @"recordID", identifier);
    CV3SetBulletinValue(bulletin, @"title", appName);
    CV3SetBulletinValue(bulletin, @"subtitle", @"ChevronV3 原生通知测试");
    CV3SetBulletinValue(bulletin, @"message", @"点击顶部横幅可开启分屏窗口");
    CV3SetBulletinValue(bulletin, @"date", now);
    CV3SetBulletinValue(bulletin, @"publicationDate", now);
    CV3SetBulletinValue(bulletin, @"lastInterruptDate", now);
    CV3SetBulletinValue(bulletin, @"clearable", @YES);
    CV3SetBulletinValue(bulletin, @"showsUnreadIndicator", @YES);
    CV3SetBulletinValue(bulletin, @"turnsOnDisplay", @YES);
    CV3SetBulletinValue(bulletin, @"context", @{
        @"CV3NativeNotificationTest": @YES,
        @"bundleIdentifier": bundleID
    });

    Class actionClass = CV3ClassNamed(@"BBAction");
    id action = CV3InvokeObject(actionClass, @selector(action));
    if (!action && actionClass) action = [[actionClass alloc] init];
    if (action) {
        CV3SetBulletinValue(action, @"identifier", @"com.xu.chevronv3.native-test.open");
        CV3SetBulletinValue(action, @"launchBundleID", bundleID);
        CV3SetBulletinValue(bulletin, @"defaultAction", action);
    }

    return bulletin;
}

static BOOL CV3PublishBulletinThroughNotificationSource(id bulletin) {
    id source = CV3CapturedBulletinNotificationSource;
    SEL selector = NSSelectorFromString(@"observer:addBulletin:forFeed:playLightsAndSirens:withReply:");
    if (!source || !bulletin || ![source respondsToSelector:selector]) return NO;

    id observer = CV3InvokeObject(source, @selector(observer));
    dispatch_queue_t sourceQueue = nil;
    @try {
        sourceQueue = [source valueForKey:@"queue"];
        if (!sourceQueue) sourceQueue = [source valueForKey:@"_queue"];
    } @catch (__unused NSException *exception) {
        sourceQueue = nil;
    }
    if (!observer || !sourceQueue) {
        CV3LogToFile(@"[NotificationSplit][NativeTest] 原生通知源尚未就绪 observer=%@ queue=%@",
                     observer, sourceQueue);
        return NO;
    }

    dispatch_async(sourceQueue, ^{
        @try {
            void (^reply)(void) = ^{
                CV3LogToFile(@"[NotificationSplit][NativeTest] 原生通知已进入 NCNotificationDispatcher");
            };
            ((void (*)(id, SEL, id, id, NSUInteger, BOOL, id))objc_msgSend)(
                source, selector, observer, bulletin, (NSUInteger)2, YES, reply);
        } @catch (NSException *exception) {
            CV3LogToFile(@"[NotificationSplit][NativeTest] NotificationSource 发布异常: %@", exception);
        }
    });
    return YES;
}

static void CV3HandleSimulatedNotificationRequest(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        @try {
            NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:@"com.xu.chevronv3"];
            NSString *bundleID = [defaults stringForKey:@"CV3TestNotificationBundleID"];
            if (!CV3LooksLikeBundleIdentifier(bundleID)) bundleID = @"com.apple.MobileSMS";

            CV3LogToFile(@"[NotificationSplit][NativeTest] 收到原生通知请求: %@", bundleID);
            id bulletin = CV3CreateNativeTestBulletin(bundleID);
            if (!bulletin || !CV3PublishBulletinThroughNotificationSource(bulletin)) {
                CV3LogToFile(@"[Error][NotificationSplit][NativeTest] 原生通知发布失败 bundle=%@ bulletin=%@",
                             bundleID, bulletin);
            }
        } @catch (NSException *exception) {
            CV3LogToFile(@"[NotificationSplit][NativeTest] 处理测试通知异常: %@", exception);
        }
    });
}

static void CV3RegisterSimulatedNotificationBridge(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        int token = 0;
        int status = notify_register_dispatch(CV3SimulatedNotificationName,
                                              &token,
                                              dispatch_get_main_queue(),
                                              ^(int registeredToken) {
            CV3HandleSimulatedNotificationRequest();
        });
        if (status != NOTIFY_STATUS_OK) {
            CV3LogToFile(@"[NotificationSplit][Simulation] Darwin 通知注册失败: %d", status);
        }
    });
}

// These callbacks cover the banner implementations used across recent
// SpringBoard releases. If a callback is not used by the current OS, Logos
// leaves the original behavior untouched.
%hook NCBulletinNotificationSource
- (id)initWithDispatcher:(id)dispatcher observer:(id)observer queue:(id)queue {
    id source = %orig(dispatcher, observer, queue);
    if (source) {
        CV3CapturedBulletinNotificationSource = source;
        CV3LogToFile(@"[NotificationSplit][NativeTest] 已捕获系统 NCBulletinNotificationSource");
    }
    return source;
}

%end

%hook SBBannerController
- (void)bannerViewController:(id)viewController didReceiveResponse:(id)response {
    if (CV3HandleUnlockedBannerTap(response, viewController, @"SBBannerController.response")) return;
    %orig(viewController, response);
}

- (void)handleTapForBanner:(id)banner {
    if (CV3HandleUnlockedBannerTap(banner, nil, @"SBBannerController.tap")) return;
    %orig(banner);
}
%end

%hook SBBulletinBannerController
- (void)handleTapForBanner:(id)banner {
    if (CV3HandleUnlockedBannerTap(banner, nil, @"SBBulletinBannerController.tap")) return;
    %orig(banner);
}

- (void)_handleTapForBanner:(id)banner {
    if (CV3HandleUnlockedBannerTap(banner, nil, @"SBBulletinBannerController._tap")) return;
    %orig(banner);
}
%end

%hook SBNotificationBannerController
- (void)bannerViewController:(id)viewController didReceiveResponse:(id)response {
    if (CV3HandleUnlockedBannerTap(response, viewController, @"SBNotificationBannerController.response")) return;
    %orig(viewController, response);
}
%end

%hook SBNotificationBannerDestination
- (void)handleNotificationResponse:(id)response forNotificationRequest:(id)request {
    if (CV3HandleUnlockedBannerTap(response, request, @"SBNotificationBannerDestination.response")) return;
    %orig(response, request);
}

- (void)notificationResponse:(id)response forRequest:(id)request {
    if (CV3HandleUnlockedBannerTap(response, request, @"SBNotificationBannerDestination.notificationResponse")) return;
    %orig(response, request);
}

- (void)notificationViewController:(id)viewController
                     executeAction:(id)action
                    withParameters:(id)parameters
                        completion:(id)completion {
    NSString *actionIdentifier = CV3NotificationActionIdentifierFromObject(action, 0);
    if (actionIdentifier.length == 0) {
        actionIdentifier = CV3NotificationActionIdentifierFromObject(parameters, 0);
    }
    BOOL defaultOpenAction = CV3NotificationActionIsDefaultOpen(action, parameters);
    CV3LogToFile(@"[NotificationSplit] phase=destination.classify source=SBNotificationBannerDestination default=%d identifier=%@ viewController=%@ action=%@ parameters=%@ completion=%@",
                 defaultOpenAction,
                 actionIdentifier ?: @"nil",
                 viewController ? NSStringFromClass([viewController class]) : @"nil",
                 action ? NSStringFromClass([action class]) : @"nil",
                 parameters ? NSStringFromClass([parameters class]) : @"nil",
                 completion ? NSStringFromClass([completion class]) : @"nil");

    if (defaultOpenAction) {
        NSArray *resolutionContext = @[
            viewController ?: [NSNull null],
            action ?: [NSNull null],
            parameters ?: [NSNull null]
        ];
        if (CV3HandleUnlockedBannerTap(resolutionContext,
                                       nil,
                                       @"SBNotificationBannerDestination.executeDefaultAction")) {
            if (completion) ((void (^)(BOOL))completion)(YES);
            CV3LogToFile(@"[NotificationSplit] phase=destination.consumed source=SBNotificationBannerDestination.executeDefaultAction identifier=%@",
                         actionIdentifier ?: @"nil");
            return;
        }
    }

    CV3LogToFile(@"[NotificationSplit] phase=destination.passthrough source=SBNotificationBannerDestination reason=%@ identifier=%@",
                 defaultOpenAction ? @"defaultResolutionFailed" : @"interactiveAction",
                 actionIdentifier ?: @"nil");
    %orig(viewController, action, parameters, completion);
}
%end

%hook SBNCNotificationDispatcherDelegate
- (void)dispatcher:(id)dispatcher
launchForegroundApplicationForAction:(id)action
notificationRequest:(id)request
    fromDestination:(id)destination
      withParameters:(id)parameters {
    NSString *destinationClass = destination ? NSStringFromClass([destination class]) : @"nil";
    BOOL isBannerDestination = [destinationClass containsString:@"Banner"];
    CV3LogToFile(@"[NotificationSplit] phase=foregroundLaunch source=SBNCNotificationDispatcherDelegate destination=%@ action=%@ request=%@ banner=%d",
                 destinationClass,
                 action ? NSStringFromClass([action class]) : @"nil",
                 request ? NSStringFromClass([request class]) : @"nil",
                 isBannerDestination);
    if (isBannerDestination &&
        CV3HandleUnlockedBannerTap(request, action, @"SBNCNotificationDispatcherDelegate.foregroundLaunch")) {
        return;
    }
    %orig(dispatcher, action, request, destination, parameters);
}
%end

%hook LSApplicationWorkspace
- (BOOL)openApplicationWithBundleID:(NSString *)bundleID {
    // Screen Time 限额闸门：SB 进程内任何直连启动请求都不允许绕过限额
    if (!CV3ScreenTimeGateBundleID(bundleID, @"LSApplicationWorkspace.openApplication")) {
        return YES;   // 已拒绝，谎报已处理以免调用方走其他路径
    }
    if (CV3FocusHostedFloatingWindowForBundleID(bundleID, @"LSApplicationWorkspace.openApplication")) return YES;
    return %orig(bundleID);
}
%end

static NSTimeInterval lastLogTime = 0;
static BOOL CV3SceneRotationDispatching = NO;

static BOOL CV3IsSystemApertureSceneRole(NSString *role) {
    if (role.length == 0) return NO;
    return [role isEqualToString:@"SBWindowSceneSessionRoleSystemAperture"] ||
           [role isEqualToString:@"SBWindowSceneSessionRoleSystemApertureCurtain"] ||
           [role rangeOfString:@"SystemAperture" options:NSCaseInsensitiveSearch].location != NSNotFound;
}

static BOOL CV3IsCompactSystemApertureRect(CGRect rect, CGRect windowBounds) {
    if (CGRectIsNull(rect) || CGRectIsInfinite(rect) || CGRectIsEmpty(rect)) return NO;

    CGFloat width = CGRectGetWidth(rect);
    CGFloat height = CGRectGetHeight(rect);
    CGFloat horizontalOffset = fabs(CGRectGetMidX(rect) - CGRectGetMidX(windowBounds));

    // iPhone 14 Pro Max compact SystemAperture is roughly 159x37 pt, while its
    // outline container is roughly 179x49 pt. Keep tolerances broad enough for
    // Dynamic Type/scale variants, but narrow enough to exclude icons and banners.
    return width >= 130.0 && width <= 230.0 &&
           height >= 30.0 && height <= 70.0 &&
           CGRectGetMinY(rect) >= -6.0 && CGRectGetMinY(rect) <= 26.0 &&
           horizontalOffset <= 42.0;
}

static BOOL CV3LayerMatchesCompactApertureSize(CALayer *layer) {
    if (!layer) return NO;
    CGFloat width = CGRectGetWidth(layer.bounds);
    CGFloat height = CGRectGetHeight(layer.bounds);
    return width >= 130.0 && width <= 230.0 && height >= 30.0 && height <= 70.0;
}

static void CV3RemoveApertureOutlineFromLayerTree(CALayer *layer) {
    if (!layer) return;

    if (CV3LayerMatchesCompactApertureSize(layer)) {
        layer.borderWidth = 0.0;
        layer.borderColor = UIColor.clearColor.CGColor;
        layer.shadowOpacity = 0.0;
        layer.shadowRadius = 0.0;
        layer.shadowPath = nil;

        if ([layer isKindOfClass:[CAShapeLayer class]]) {
            CAShapeLayer *shapeLayer = (CAShapeLayer *)layer;
            shapeLayer.strokeColor = UIColor.clearColor.CGColor;
            shapeLayer.lineWidth = 0.0;
        }
    }

    for (CALayer *sublayer in [layer.sublayers copy]) {
        CV3RemoveApertureOutlineFromLayerTree(sublayer);
    }
}

static void CV3RemoveCompactApertureOutlineFromView(UIView *view, UIWindow *window) {
    if (!view || !window || view.hidden || view.alpha <= 0.01) return;

    CGRect rectInWindow = [view convertRect:view.bounds toView:window];
    if (CV3IsCompactSystemApertureRect(rectInWindow, window.bounds)) {
        CV3RemoveApertureOutlineFromLayerTree(view.layer);
    }

    for (UIView *subview in [view.subviews copy]) {
        CV3RemoveCompactApertureOutlineFromView(subview, window);
    }
}

static void CV3RemoveCompactSystemApertureOutline(UIWindow *window) {
    if (!window || !CV3IsSystemApertureSceneRole(window.windowScene.session.role)) return;

    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    CV3RemoveCompactApertureOutlineFromView(window, window);
    [CATransaction commit];
}

static void CV3ArrangeFloatingWindowsAfterRotation(BOOL animated) {
    if (!floatingWindows || floatingWindows.count < 2) return;

    NSMutableArray<CV3FloatingAppWindow *> *windows = [NSMutableArray array];
    for (id object in [floatingWindows copy]) {
        if (![object isKindOfClass:[CV3FloatingAppWindow class]]) continue;
        CV3FloatingAppWindow *window = (CV3FloatingAppWindow *)object;
        if (window.isClosing || window.isStashed || window.hidden || window.alpha <= 0.01) continue;
        [windows addObject:window];
    }
    if (windows.count < 2) return;

    CV3FloatingAppWindow *referenceWindow = windows.lastObject;
    CGRect displayBounds = CV3DisplayBoundsForWindow(referenceWindow);
    UIEdgeInsets safeArea = [referenceWindow currentSafeAreaInsets];
    CGFloat padding = CV3Style.safeAreaBreath;
    CGRect available = UIEdgeInsetsInsetRect(displayBounds,
        UIEdgeInsetsMake(safeArea.top + padding,
                         safeArea.left + padding,
                         safeArea.bottom + padding,
                         safeArea.right + padding));
    if (CGRectGetWidth(available) <= 1.0 || CGRectGetHeight(available) <= 1.0) return;

    CGFloat maxWidth = 1.0;
    CGFloat maxHeight = 1.0;
    for (CV3FloatingAppWindow *window in windows) {
        maxWidth = MAX(maxWidth, CGRectGetWidth(window.bounds));
        maxHeight = MAX(maxHeight, CGRectGetHeight(window.bounds));
    }

    const CGFloat spacing = 12.0;
    NSUInteger count = windows.count;
    NSUInteger bestColumns = 1;
    CGFloat bestScore = CGFLOAT_MAX;
    BOOL windowsArePortrait = maxHeight > maxWidth;
    for (NSUInteger columns = 1; columns <= count; columns++) {
        NSUInteger rows = (count + columns - 1) / columns;
        CGFloat cellWidth = (CGRectGetWidth(available) - spacing * (columns - 1)) / columns;
        CGFloat cellHeight = (CGRectGetHeight(available) - spacing * (rows - 1)) / rows;
        if (cellWidth <= 1.0 || cellHeight <= 1.0) continue;

        CGFloat widthOverlapRatio = MAX(0.0, maxWidth - cellWidth) / maxWidth;
        CGFloat heightOverlapRatio = MAX(0.0, maxHeight - cellHeight) / maxHeight;
        CGFloat score = widthOverlapRatio + heightOverlapRatio;
        // For equal-overlap layouts, place portrait windows in columns and
        // landscape windows in rows so their short edges meet.
        score += windowsArePortrait
            ? (CGFloat)(count - columns) * 0.0001
            : (CGFloat)(columns - 1) * 0.0001;
        if (score < bestScore) {
            bestScore = score;
            bestColumns = columns;
        }
    }

    NSUInteger rows = (count + bestColumns - 1) / bestColumns;
    CGFloat cellWidth = (CGRectGetWidth(available) - spacing * (bestColumns - 1)) / bestColumns;
    CGFloat cellHeight = (CGRectGetHeight(available) - spacing * (rows - 1)) / rows;
    NSMutableArray<NSValue *> *targetFrames = [NSMutableArray arrayWithCapacity:count];
    NSMutableArray<NSString *> *traceFrames = [NSMutableArray arrayWithCapacity:count];

    for (NSUInteger index = 0; index < count; index++) {
        NSUInteger row = index / bestColumns;
        NSUInteger column = index % bestColumns;
        NSUInteger firstIndexInRow = row * bestColumns;
        NSUInteger itemsInRow = MIN(bestColumns, count - firstIndexInRow);
        CGFloat rowWidth = cellWidth * itemsInRow + spacing * (itemsInRow - 1);
        CGFloat rowStartX = CGRectGetMidX(available) - rowWidth * 0.5;
        CGPoint center = CGPointMake(rowStartX + column * (cellWidth + spacing) + cellWidth * 0.5,
                                     CGRectGetMinY(available) + row * (cellHeight + spacing) + cellHeight * 0.5);
        CV3FloatingAppWindow *window = windows[index];
        CGRect proposed = CGRectMake(center.x - CGRectGetWidth(window.bounds) * 0.5,
                                     center.y - CGRectGetHeight(window.bounds) * 0.5,
                                     CGRectGetWidth(window.bounds),
                                     CGRectGetHeight(window.bounds));
        CGRect target = [window safeAreaClampedFrame:proposed preferredCenter:center preserveSize:YES];
        [targetFrames addObject:[NSValue valueWithCGRect:target]];
        [traceFrames addObject:[NSString stringWithFormat:@"%@=%@",
                                window.bundleID ?: @"nil", NSStringFromCGRect(target)]];
    }

    void (^applyLayout)(void) = ^{
        [windows enumerateObjectsUsingBlock:^(CV3FloatingAppWindow *window, NSUInteger index, BOOL *stop) {
            CGRect target = targetFrames[index].CGRectValue;
            window.center = CGPointMake(CGRectGetMidX(target), CGRectGetMidY(target));
        }];
    };
    if (animated) {
        [UIView animateWithDuration:0.55
                              delay:0
             usingSpringWithDamping:0.78
              initialSpringVelocity:0.35
                            options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction
                         animations:applyLayout
                         completion:nil];
    } else {
        applyLayout();
    }
    CV3LogToFile(@"[RotationLayout] count=%lu grid=%lux%lu available=%@ score=%.4f frames=[%@]",
                 (unsigned long)count,
                 (unsigned long)bestColumns,
                 (unsigned long)rows,
                 NSStringFromCGRect(available),
                 bestScore,
                 [traceFrames componentsJoinedByString:@", "]);
}

static void CV3ApplySceneRotationContextToProject(CV3SceneRotationContext context, NSString *reason, BOOL force) {
    if (!CV3IsValidInterfaceOrientation(context.orientation)) return;

    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            CV3ApplySceneRotationContextToProject(context, reason, force);
        });
        return;
    }
    if (CV3SceneRotationDispatching) return;

    BOOL needsDispatch = force;
    if (!needsDispatch && sharedWindow) {
        BOOL sharedIsLandscape = sharedWindow.bounds.size.width > sharedWindow.bounds.size.height;
        needsDispatch = CV3SceneRotationContextNeedsApply(sharedWindow.targetOrientation,
                                                          sharedWindow.baseRotationTransform,
                                                          context,
                                                          NO) ||
                        sharedIsLandscape != context.isLandscape;
    }
    if (!needsDispatch && floatingWindows) {
        for (CV3FloatingAppWindow *win in [floatingWindows copy]) {
            if (![win isKindOfClass:[CV3FloatingAppWindow class]] || win.isClosing) continue;
            if (CV3SceneRotationContextNeedsApply(win.lastLayoutOrientation,
                                                 win.baseRotationTransform,
                                                 context,
                                                 NO)) {
                needsDispatch = YES;
                break;
            }
        }
    }
    if (!needsDispatch) return;

    CV3SceneRotationDispatching = YES;
    CV3LastTrustedInterfaceOrientation = context.orientation;

    NSTimeInterval currentTime = [[NSDate date] timeIntervalSince1970];
    if (currentTime - lastLogTime > 0.5) {
        lastLogTime = currentTime;
        CV3LogToFile(@"[Orientation] 全局应用 UIScene 旋转: %ld, reason=%@",
                     (long)context.orientation,
                     reason ?: @"Unknown");
    }

    @try {
        if (sharedWindow) {
            [sharedWindow applySceneRotationContext:context force:force];
        }

        BOOL floatingOrientationChanged = NO;
        if (floatingWindows) {
            for (CV3FloatingAppWindow *win in [floatingWindows copy]) {
                if (![win isKindOfClass:[CV3FloatingAppWindow class]] || win.isClosing) continue;
                UIInterfaceOrientation previousOrientation = win.lastLayoutOrientation;
                CGAffineTransform previousRotation = win.baseRotationTransform;
                [win applySceneRotationContext:context force:force];
                if (previousOrientation != context.orientation ||
                    !CGAffineTransformEqualToTransform(previousRotation, win.baseRotationTransform)) {
                    floatingOrientationChanged = YES;
                    [win attachToCurrentActiveScene];
                }
            }
        }

        if (floatingOrientationChanged) {
            CV3ArrangeFloatingWindowsAfterRotation(YES);
        }

        CV3UpdateExposeForSceneRotation(context, YES);
    } @catch (NSException *e) {
        CV3LogToFile(@"[Error] 全局方向同步异常: %@", e);
    }

    CV3SceneRotationDispatching = NO;
}

%hook UIWindow
- (void)layoutSubviews {

    %orig;

    // SystemAperture rebuilds its compact presentation as Live Activities update.
    // Reapply after layout so the black island/content remains intact while only
    // the surrounding border, stroke and shadow are suppressed.
    CV3RemoveCompactSystemApertureOutline(self);

    // 增加递归保护：如果是 CV3Window 自身的 layoutSubviews，或者已经在处理中，则跳过
    static BOOL isUpdating = NO;
    if (isUpdating || (sharedWindow && self == sharedWindow)) return;

    // 仅监控处于前台且已激活的窗口场景
    if (self.windowScene && self.windowScene.activationState == UISceneActivationStateForegroundActive) {

        NSString *role = self.windowScene.session.role;

        // 终极白名单：在越狱环境下，仅有 _UIScreenBasedSceneSession 会报告真实的物理旋转方向。
        // 其他所有 Application 或系统覆盖层，在下拉通知栏/控制中心时都会被强制报告为竖屏。
        if (![role isEqualToString:@"_UIScreenBasedSceneSession"]) {
            return;
        }

        UIInterfaceOrientation currentOrientation = self.windowScene.interfaceOrientation;

        // 如果获取到了无效方向，直接忽略
        if (currentOrientation == UIInterfaceOrientationUnknown || currentOrientation == 0) {
            return;
        }

        if (sharedWindow && sharedWindow.isPanelShowing && (sharedWindow.isKeyboardVisible || sharedWindow.searchField.isFirstResponder)) {
            if (currentOrientation != CV3LastTrustedInterfaceOrientation) {
                CV3LogToFile(@"[Orientation] 物理旋转通知: %ld -> %ld, 正在强制收起键盘以对齐布局", (long)CV3LastTrustedInterfaceOrientation, (long)currentOrientation);
                dispatch_async(dispatch_get_main_queue(), ^{
                    [sharedWindow.searchField resignFirstResponder];
                    sharedWindow.isKeyboardVisible = NO;
                });
            } else {
                // 方向未发生改变（例如仅键盘弹起），跳过 layout 处理以防止闪烁或坐标重写
                return;
            }
        }

        isUpdating = YES;
        CV3SceneRotationContext context = CV3MakeSceneRotationContext(self.windowScene);
        context.orientation = currentOrientation;
        context.isLandscape = UIInterfaceOrientationIsLandscape(currentOrientation);
        context.transform = CV3RotationTransformForInterfaceOrientation(currentOrientation);
        // 使用异步确保当前 layout 周期执行完毕，避免重入导致的错位
        dispatch_async(dispatch_get_main_queue(), ^{
            CV3ApplySceneRotationContextToProject(context, @"UIWindowLayout", NO);
            isUpdating = NO;
        });
    }
}
%end

@interface SBWorkspaceTransitionRequest : NSObject
@end

@interface SBMainWorkspaceTransitionRequest : SBWorkspaceTransitionRequest
@property (nonatomic, assign) NSInteger source;
@end

%hook SBMainWorkspaceTransitionRequest
- (NSSet *)deactivatedEntities {
    NSSet *orig = %orig;
    if (floatingWindows && floatingWindows.count > 0 && orig.count > 0) {
        NSMutableSet *mutableDeactivated = [orig mutableCopy];
        BOOL modified = NO;

        for (id entity in orig) {
            NSString *bid = nil;
            if (CV3WorkspaceEntityMatchesFloatingWindow(entity, &bid)) {
                [mutableDeactivated removeObject:entity];
                modified = YES;
                CV3LogToFile(@"[Immortality] 成功从停用列表中剔除分屏应用: %@", bid);
            }
        }

        if (modified) return [mutableDeactivated copy];
    }
    return orig;
}

- (NSSet *)resigningEntities {
    NSSet *orig = %orig;
    if (floatingWindows && floatingWindows.count > 0 && orig.count > 0) {
        NSMutableSet *mutableResigning = [orig mutableCopy];
        BOOL modified = NO;

        for (id entity in orig) {
            NSString *bid = nil;
            if (CV3WorkspaceEntityMatchesFloatingWindow(entity, &bid)) {
                [mutableResigning removeObject:entity];
                modified = YES;
                CV3LogToFile(@"[Immortality] 成功从辞职(Resign)列表中剔除分屏应用: %@", bid);
            }
        }

        if (modified) return [mutableResigning copy];
    }
    return orig;
}

- (NSSet *)deactivatingApps {
    NSSet *originalApps = %orig;
    if (!floatingWindows || floatingWindows.count == 0 || originalApps.count == 0) return originalApps;

    NSMutableSet *filteredApps = [originalApps mutableCopy];
    for (id app in originalApps) {
        NSString *bundleID = CV3BundleIdentifierFromWorkspaceObject(app);
        for (CV3FloatingAppWindow *window in [floatingWindows copy]) {
            if (window.isClosing || window.isStashed) continue;
            if ([bundleID isEqualToString:window.bundleID]) {
                [filteredApps removeObject:app];
                [window.hostedSession validateNow:@"FilteredDeactivatingApps"];
                CV3LogToFile(@"[HostedSession] 已从 deactivatingApps 移除: %@", bundleID);
                break;
            }
        }
    }
    return [filteredApps copy];
}
%end
@interface SBAppLayout : NSObject
- (BOOL)containsItemWithBundleIdentifier:(NSString *)bundleIdentifier;
@end

static NSUInteger CV3SwitcherPadIdiomScopeDepth = 0;

%hook SBAppSwitcherSettings
- (long long)switcherStyle {
    return 2;
}

- (void)setSwitcherStyle:(long long)style {
    %orig(2);
}
%end

%hook SBFluidSwitcherViewController
- (BOOL)isDevicePad {
    return YES;
}
%end

%hook SBMainSwitcherControllerCoordinator
- (void)_loadContentViewControllerIfNecessaryForWindowScene:(id)windowScene {
    CV3SwitcherPadIdiomScopeDepth++;
    @try {
        %orig(windowScene);
    } @finally {
        if (CV3SwitcherPadIdiomScopeDepth > 0) CV3SwitcherPadIdiomScopeDepth--;
    }
}
%end

%hook UIDevice
- (UIUserInterfaceIdiom)userInterfaceIdiom {
    if (CV3SwitcherPadIdiomScopeDepth > 0 || CV3SwitcherPresentationActive()) {
        return UIUserInterfaceIdiomPad;
    }
    return %orig;
}
%end

@interface SBSwitcherModifier : NSObject
- (NSArray *)appLayouts;
- (id)activeAppLayout;
- (unsigned long long)activeAppLayoutIndex;
@end

@interface SBHomeGestureSwitcherModifier : SBSwitcherModifier
@end

static BOOL CV3SwitcherObjectMatchesHostedFloatingWindow(id object) {
    if (!object || !floatingWindows || floatingWindows.count == 0) return NO;

    @try {
        for (CV3FloatingAppWindow *window in [floatingWindows copy]) {
            if (![window isKindOfClass:[CV3FloatingAppWindow class]] || window.isClosing) continue;
            if (CV3TargetRespondsToSelector(object, @selector(containsItemWithBundleIdentifier:)) &&
                ((BOOL (*)(id, SEL, id))objc_msgSend)(object,
                                                     @selector(containsItemWithBundleIdentifier:),
                                                     window.bundleID)) {
                return YES;
            }
        }
    } @catch (NSException *exception) {
        CV3LogToFile(@"[Switcher] 卡片身份解析失败: %@", exception);
    }
    return NO;
}

static BOOL CV3SwitcherIndexMatchesHostedFloatingWindow(id modifier, NSUInteger index) {
    NSArray *layouts = CV3InvokeObject(modifier, @selector(appLayouts));
    if (![layouts isKindOfClass:[NSArray class]] || index >= layouts.count) return NO;
    return CV3SwitcherObjectMatchesHostedFloatingWindow(layouts[index]);
}

%hook SBHomeGestureSwitcherModifier
- (double)scaleForIndex:(unsigned long long)index {
    // Keep the original geometry even when the duplicate hosted card is invisible.
    // Returning a near-zero scale feeds inconsistent bounds into landscape layout.
    return %orig;
}

- (double)opacityForIndex:(unsigned long long)index {
    if (CV3SwitcherIndexMatchesHostedFloatingWindow(self, index)) return 0.0;
    return %orig;
}

- (double)dimmingAlphaForIndex:(unsigned long long)index {
    if (CV3SwitcherIndexMatchesHostedFloatingWindow(self, index)) return 0.0;
    return %orig;
}

- (double)cornerRadiusForIndex:(unsigned long long)index {
    return %orig;
}

- (double)shadowOpacityForIndex:(unsigned long long)index {
    if (CV3SwitcherIndexMatchesHostedFloatingWindow(self, index)) return 0.0;
    return %orig;
}

- (BOOL)isItemResizingAllowedForIndex:(unsigned long long)index {
    return %orig;
}

- (double)blurViewIconScaleForIndex:(unsigned long long)index {
    if (CV3SwitcherIndexMatchesHostedFloatingWindow(self, index)) return 0.0;
    return %orig;
}

- (BOOL)isWallpaperRequiredForIndex:(unsigned long long)index {
    if (CV3SwitcherIndexMatchesHostedFloatingWindow(self, index)) return NO;
    return %orig;
}

- (double)titleOpacityForIndex:(unsigned long long)index {
    if (CV3SwitcherIndexMatchesHostedFloatingWindow(self, index)) return 0.0;
    return %orig;
}

- (BOOL)shouldUseWallpaperGradientTreatmentForIndex:(unsigned long long)index {
    if (CV3SwitcherIndexMatchesHostedFloatingWindow(self, index)) return NO;
    return %orig;
}
%end

%hook FBSceneManager
- (void)destroyScene:(id)arg1 withTransitionContext:(id)arg2 {
    CV3FloatingAppWindow *windowToClose = nil;
    if (floatingWindows && floatingWindows.count > 0) {
        FBScene *scene = (FBScene *)arg1;
        for (CV3FloatingAppWindow *win in [floatingWindows copy]) {
            if (CV3IdentifierContainsExactBundleID(scene.identifier, win.bundleID) && !win.isClosing) {
                windowToClose = win;
                break;
            }
        }
    }
    if (windowToClose) {
        CV3LogToFile(@"[Lifecycle] 系统正在销毁托管场景 (%@)，在 FrontBoard 销毁前同步关闭分屏", windowToClose.bundleID);
        if ([NSThread isMainThread]) {
            [windowToClose closeWindow];
        } else {
            CV3LogToFile(@"[Lifecycle] destroyScene 从非主线程进入，切回主线程同步清理: %@", windowToClose.bundleID);
            dispatch_sync(dispatch_get_main_queue(), ^{
                [windowToClose closeWindow];
            });
        }
    }
    %orig;
}
%end

static BOOL CV3FocusHostedLaunchTargetFromObject(id request, NSString *source) {
    if (!request || !floatingWindows || floatingWindows.count == 0) return NO;

    NSArray<NSString *> *targetSelectors = @[
        @"activatingEntities", @"activatingApps", @"toEntity",
        @"targetEntity", @"destinationEntity", @"activatingDisplayItem",
        @"targetDisplayItem"
    ];
    for (NSString *selectorName in targetSelectors) {
        id target = CV3InvokeObject(request, NSSelectorFromString(selectorName));
        if (!target) continue;
        NSArray *candidates = nil;
        if ([target isKindOfClass:[NSArray class]]) candidates = target;
        else if ([target isKindOfClass:[NSSet class]]) candidates = [target allObjects];
        else candidates = @[target];

        for (id candidate in candidates) {
            NSString *bundleID = CV3BundleIdentifierFromWorkspaceObject(candidate);
            if (CV3FocusHostedFloatingWindowForBundleID(bundleID, source)) return YES;
        }
    }
    return NO;
}

%hook SBMainWorkspace
- (NSSet *)activeDisplayItems {
    NSSet *orig = %orig;
    if (floatingWindows && floatingWindows.count > 0) {
        NSMutableSet *mutableItems = [orig mutableCopy];
        BOOL modified = NO;
        
        for (CV3FloatingAppWindow *win in floatingWindows) {
            if (win.isClosing) continue;
            
            BOOL alreadyPresent = NO;
            for (id item in orig) {
                if ([item respondsToSelector:@selector(bundleIdentifier)] && [[item bundleIdentifier] isEqualToString:win.bundleID]) {
                    alreadyPresent = YES;
                    break;
                }
            }
            
            if (!alreadyPresent) {
                // [Fix] 动态构造 SBDisplayItem 并注入，确保系统在 TCC 和渲染管道中承认其活跃地位
                @try {
                    id item = CV3InvokeObject2(CV3ClassNamed(@"SBDisplayItem"),
                                               @selector(displayItemWithType:bundleIdentifier:),
                                               @"main",
                                               win.bundleID);
                    if (item) {
                        [mutableItems addObject:item];
                        modified = YES;
                        CV3LogToFile(@"[Workspace] 已成功向 ActiveItems 注入: %@", win.bundleID);
                    }
                } @catch (NSException *e) {
                    CV3LogToFile(@"[Error] 构造 SBDisplayItem 失败: %@", e);
                }
            }
        }
        
        if (modified) return [mutableItems copy];
    }
    return orig;
}

- (void)transaction:(id)arg1 willBeginLayoutTransitionWithContext:(id)arg2 {
    CV3ExitExposeModeIfNeeded(nil, NO);
    CV3ApplySceneRotationContextToProject(CV3MakeSceneRotationContext(nil), @"WorkspaceLayoutWillBegin", NO);
    CV3LogToFile(@"[Workspace] Layout 转换即将开始...");
    CV3BeginWorkspaceTransitionProtection(@"LayoutWillBegin");
    %orig;
    // 核心：在转换全周期高频维持分屏 App 的活跃度
    if (floatingWindows) {
        for (CV3FloatingAppWindow *win in floatingWindows) {
            if ([win isKindOfClass:[CV3FloatingAppWindow class]] && !win.isClosing) {
                // [Optimization] 仅执行挂载，不执行 refreshHostViewPresentation，避免转场瞬间的 Context 重置导致闪烁
                [win attachToCurrentActiveScene];
                CV3LogToFile(@"[Workspace] 转换启动瞬间锁定渲染: %@", win.bundleID);
            }
        }
    }
}

- (void)executeTransitionRequest:(id)arg1 {
    CV3ExitExposeModeIfNeeded(nil, NO);
    CV3ApplySceneRotationContextToProject(CV3MakeSceneRotationContext(nil), @"WorkspaceExecuteTransition", NO);
    if ([arg1 respondsToSelector:@selector(source)]) {
        CV3LogToFile(@"[Workspace] 执行转换请求, Source: %ld", (long)[(SBMainWorkspaceTransitionRequest *)arg1 source]);
    }
    if (CV3FocusHostedLaunchTargetFromObject(arg1, @"SBMainWorkspace.executeTransitionRequest")) return;
    CV3BeginWorkspaceTransitionProtection(@"ExecuteTransitionRequest");
    %orig(arg1);
}

- (void)workspace:(id)arg1 didExecuteTransitionRequest:(id)arg2 {
    %orig;
    CV3ExitExposeModeIfNeeded(nil, NO);
    CV3LogToFile(@"[Workspace] 转换请求已执行完毕，执行最终渲染对齐");
    CV3EndWorkspaceTransitionProtection(@"DidExecuteTransitionRequest");
    if (floatingWindows) {
        for (CV3FloatingAppWindow *win in floatingWindows) {
            if ([win isKindOfClass:[CV3FloatingAppWindow class]] && !win.isClosing) {
                // 转换后稍微延迟执行，确保系统状态稳定
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.15 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                    [win attachToCurrentActiveScene];
                    [win stabilizeForegroundForWorkspaceTransition:@"DidExecuteDelayedAlign"];
                    CV3LogToFile(@"[Workspace] 转换后延迟对齐完成: %@", win.bundleID);
                });
            }
        }
    }

    // 恢复对主窗口的场景同步及取色逻辑
    if (sharedWindow) {
        [sharedWindow attachToCurrentActiveScene];
        @try {
            id activeItem = CV3InvokeObject(self, @selector(activeDisplayItem));
            NSString *bid = CV3InvokeObject(activeItem, @selector(bundleIdentifier));
            if (bid.length > 0) CV3UpdateAdaptiveTint(bid);
        } @catch (NSException *e) {}
    }
}
%end
%hook SBLockScreenManager
- (void)lockScreenViewControllerDidPresent {
    %orig;
    CV3LockScreenPresented = YES;
    CV3ExitExposeModeIfNeeded(nil, NO);
    if (sharedWindow) [sharedWindow setSystemUILevelSuppressed:YES];
    if (floatingWindows) {
        for (CV3FloatingAppWindow *win in [floatingWindows copy]) {
            if ([win isKindOfClass:[CV3FloatingAppWindow class]]) {
                win.isSuppressedByLockScreen = YES;
                [win setHidden:YES];
            }
        }
    }
}
- (void)lockScreenViewControllerDidDismiss {
    %orig;
    CV3LockScreenPresented = NO;
    if (sharedWindow && ![sharedWindow isSystemUIActive]) {
        [sharedWindow setSystemUILevelSuppressed:NO];
    }
    if (floatingWindows) {
        for (CV3FloatingAppWindow *win in [floatingWindows copy]) {
            if (![win isKindOfClass:[CV3FloatingAppWindow class]]) continue;
            win.isSuppressedByLockScreen = NO;
            if (!win.isStashed && !win.isClosing) [win setHidden:NO];
        }
    }
}
%end

#pragma mark - Keep the launcher below Control Center and Notification Center
%hook SBControlCenterController
- (void)_willPresent {
    %orig;
    CV3ControlCenterPresented = YES;
    CV3ExitExposeModeIfNeeded(nil, NO);
    if (sharedWindow) {
        [sharedWindow setSystemUILevelSuppressed:YES];
    }
    // 控制中心弹出时，分屏不消失
    if (floatingWindows) {
        for (CV3FloatingAppWindow *win in floatingWindows) {
            if ([win isKindOfClass:[CV3FloatingAppWindow class]]) [win setHidden:NO];
        }
    }
}
- (void)_didDismiss {
    %orig;
    CV3ControlCenterPresented = NO;
    if (sharedWindow && ![sharedWindow isSystemUIActive]) {
        [sharedWindow setSystemUILevelSuppressed:NO];
    }
}
%end

%hook SBCoverSheetPresentationManager
- (void)setCoverSheetPresented:(BOOL)arg1 animated:(BOOL)arg2 {
    CV3CoverSheetManagerPresented = arg1;
    CV3GestureCoverSheetPresented = CV3CoverSheetManagerPresented || CV3CoverSheetControllerPresented;
    CV3LogToFile(@"[EdgeSystemEnvironment] source=coverSheetManager presented=%d", arg1);
    %orig;
    if (arg1) CV3ExitExposeModeIfNeeded(nil, NO);
    if (sharedWindow) {
        if (arg1 || [sharedWindow isSystemUIActive]) {
            [sharedWindow setSystemUILevelSuppressed:YES];
        } else {
            [sharedWindow setSystemUILevelSuppressed:NO];
        }
    }
    // 通知中心/下拉盖板时不隐藏分屏
    if (arg1 && floatingWindows) {
        for (CV3FloatingAppWindow *win in floatingWindows) {
            if ([win isKindOfClass:[CV3FloatingAppWindow class]]) [win setHidden:NO];
        }
    }
}
%end

@interface CSCoverSheetViewController : UIViewController
@end

%hook CSCoverSheetViewController
- (void)viewWillAppear:(BOOL)animated {
    CV3GestureCoverSheetController = self;
    CV3CoverSheetControllerPresented = YES;
    CV3GestureCoverSheetPresented = CV3CoverSheetManagerPresented || CV3CoverSheetControllerPresented;
    CV3LogToFile(@"[EdgeSystemEnvironment] source=coverSheetWillAppear presented=1");
    %orig;
    CV3ExitExposeModeIfNeeded(nil, NO);
    if (sharedWindow) {
        [sharedWindow setSystemUILevelSuppressed:YES];
    }
}
- (void)viewDidDisappear:(BOOL)animated {
    %orig;
    if (CV3GestureCoverSheetController == self) {
        CV3GestureCoverSheetController = nil;
        CV3CoverSheetControllerPresented = NO;
        CV3GestureCoverSheetPresented = CV3CoverSheetManagerPresented || CV3CoverSheetControllerPresented;
    }
    CV3LogToFile(@"[EdgeSystemEnvironment] source=coverSheetDidDisappear presented=%d", CV3GestureCoverSheetPresented);
    if (sharedWindow) {
        // 只有当没有其他系统 UI 活跃时才解除压制
        if (![sharedWindow isSystemUIActive]) {
            [sharedWindow setSystemUILevelSuppressed:NO];
        }
    }
}
%end

%hook SBIconController
- (void)_handleEditingGesture:(UILongPressGestureRecognizer *)gesture {
    UIView *gestureView = gesture.view;
    CGPoint point = gestureView ? [gesture locationInView:gestureView] : CGPointZero;
    UIView *hitView = gestureView ? [gestureView hitTest:point withEvent:nil] : nil;
    BOOL onIcon = NO;
    for (UIView *view = hitView; view; view = view.superview) {
        NSString *className = NSStringFromClass([view class]);
        if ([className rangeOfString:@"IconView" options:NSCaseInsensitiveSearch].location != NSNotFound) {
            onIcon = YES;
            break;
        }
    }
    CV3LogToFile(@"[EditProbe] SBIconController _handleEditingGesture state=%ld point=(%.1f,%.1f) hit=%@ onIcon=%d gestureView=%@",
                 (long)gesture.state, point.x, point.y, hitView, onIcon, gestureView);
    if (gesture.state == UIGestureRecognizerStateBegan &&
        CV3ShouldSuppressWallpaperLongPress() && !onIcon) {
        CV3LogToFile(@"[Feature] 拦截 SBIconContentView 空白处 _handleEditingGesture");
        return;
    }
    %orig(gesture);
}

// iconprobe 实证（iOS 16.5.1）：launchIcon:/launchIcon:fromLocation:/_launchIcon:fromLocation:
// 在运行时均不存在（曾为死 hook，从未生效），已移除。点击图标的真实内部入口是
// _launchFromIconView:withActions:（iconView 携带动画源）。在此拦截 hosted 图标：
// 对分屏中的 app 转为聚焦浮窗（与 SBIconView 触摸层拦截同源互补），
// 普通图标放行并进入与 SBIcon 启动一致的工作区过渡保护。
- (void)_launchFromIconView:(id)iconView withActions:(id)actions {
    if (CV3InterceptHostedIconObject(CV3IconFromIconViewObject(iconView),
                                    @"SBIconController._launchFromIconView")) return;
    CV3LogLaunchChain(@"SBIconController._launchFromIconView:withActions:", iconView);
    CV3BeginWorkspaceTransitionProtection(@"IconLaunchBegan");
    %orig(iconView, actions);
}

// 启动链探针：SBHIconManager delegate 启动回调（观测主屏点击的真实入口）。
- (void)iconManager:(id)manager launchIcon:(id)icon location:(id)location animated:(BOOL)animated completionHandler:(id)handler {
    CV3LogLaunchChain(@"SBIconController.iconManager:launchIcon:location:animated:completionHandler:", icon);
    %orig;
}

- (void)iconManager:(id)manager launchIconForIconView:(id)iconView withActions:(id)actions {
    CV3LogLaunchChain(@"SBIconController.iconManager:launchIconForIconView:withActions:", iconView);
    NSString *actionsDesc = actions ? [actions description] : @"-";
    if (actionsDesc.length > 700) actionsDesc = [actionsDesc substringToIndex:700];
    CV3LogToFile(@"[LaunchChain] params manager=%@ viewClass=%@ actions=%@ actionsClass=%@ desc=%@",
                 manager ? NSStringFromClass([manager class]) : @"nil",
                 iconView ? NSStringFromClass([iconView class]) : @"nil",
                 actions ? @"non-nil" : @"nil",
                 actions ? NSStringFromClass([actions class]) : @"-",
                 actionsDesc);
    %orig;
}
%end

static CV3FloatingAppWindow *CV3TopmostFloatingWindowAtScenePoint(CGPoint scenePoint,
                                                                  UIWindowScene *scene,
                                                                  UIEvent *event,
                                                                  NSMutableArray<NSString *> *diagnostics) {
    if (!floatingWindows || floatingWindows.count == 0) return nil;

    for (id object in [[floatingWindows reverseObjectEnumerator] allObjects]) {
        if (![object isKindOfClass:[CV3FloatingAppWindow class]]) continue;
        CV3FloatingAppWindow *window = (CV3FloatingAppWindow *)object;
        if (window.isClosing || window.isStashed || window.hidden || window.alpha <= 0.01) continue;

        CGPoint localPoint;
        if (scene) {
            localPoint = [window convertPoint:scenePoint fromCoordinateSpace:scene.coordinateSpace];
        } else {
            localPoint = [window convertPoint:scenePoint fromWindow:nil];
        }
        BOOL hit = CV3PhysicalPointInside(window, localPoint, event);
        if (diagnostics) {
            [diagnostics addObject:[NSString stringWithFormat:
                @"%@{hit=%d local=%@ frame=%@ bounds=%@ rootBounds=%@ rootTransform=%@}",
                window.bundleID ?: @"nil",
                hit,
                NSStringFromCGPoint(localPoint),
                NSStringFromCGRect(window.frame),
                NSStringFromCGRect(window.bounds),
                NSStringFromCGRect(window.rootTransformContainer.bounds),
                NSStringFromCGAffineTransform(window.rootTransformContainer.transform)]];
        }
        if (hit) return window;
    }
    return nil;
}

static void CV3HandleFloatingWindowGlobalTouch(UIEvent *event) {
    if (event.type != UIEventTypeTouches || !floatingWindows || floatingWindows.count == 0) return;

    for (UITouch *touch in event.allTouches) {
        if (touch.phase != UITouchPhaseBegan) continue;

        UIWindow *sourceWindow = touch.window;
        CGPoint point = [touch locationInView:sourceWindow];
        UIWindowScene *scene = sourceWindow.windowScene;
        if (scene) {
            point = [scene.coordinateSpace convertPoint:point fromCoordinateSpace:sourceWindow];
        } else if (sourceWindow) {
            point = [sourceWindow convertPoint:point toWindow:nil];
        }

        NSMutableArray<NSString *> *hitDiagnostics = [NSMutableArray array];
        CV3FloatingAppWindow *target = CV3TopmostFloatingWindowAtScenePoint(point,
                                                                            scene,
                                                                            event,
                                                                            hitDiagnostics);
        BOOL modelTopmost = target && floatingWindows.lastObject == target;
        CV3LogToFile(@"[ZOrder] phase=globalTouch.hitTest target=%@ sourceWindow=%@ scenePoint=%@ sceneBounds=%@ orientation=%ld candidates=[%@]",
                     target.bundleID ?: @"nil",
                     sourceWindow ? NSStringFromClass(sourceWindow.class) : @"nil",
                     NSStringFromCGPoint(point),
                     NSStringFromCGRect(scene ? scene.coordinateSpace.bounds : CGRectZero),
                     (long)(scene ? scene.interfaceOrientation : UIInterfaceOrientationUnknown),
                     [hitDiagnostics componentsJoinedByString:@", "]);
        if (target) {
            // This SpringBoard-side hit is the universal interaction signal.
            // Remote scene hosts do not always route touches through the
            // injected UIApplication (for example hardened or multi-process
            // apps), but every visible floating window is still identifiable
            // here by its physical content bounds.
            CV3LogHomeBarVisibility(@"[HomeBarTrace] phase=globalTouch.contentWake bundle=%@ sourceWindow=%@ alpha=%.3f hidden=%d",
                                    target.bundleID ?: @"nil",
                                    sourceWindow ? NSStringFromClass(sourceWindow.class) : @"nil",
                                    target.homeBarView.alpha,
                                    target.homeBarAutoHidden);
            [target noteFloatingHomeBarInteraction];
        }
        if (target && (!target.isFocused || !modelTopmost)) {
            CV3LogToFile(@"[ZOrder] phase=globalTouch.promote target=%@ sourceWindow=%@ point=%@ frame=%@ sceneBounds=%@ orientation=%ld focused=%d modelTopmost=%d",
                         target.bundleID ?: @"nil",
                         sourceWindow ? NSStringFromClass(sourceWindow.class) : @"nil",
                         NSStringFromCGPoint(point),
                         NSStringFromCGRect(target.frame),
                         NSStringFromCGRect(scene ? scene.coordinateSpace.bounds : CGRectZero),
                         (long)(scene ? scene.interfaceOrientation : UIInterfaceOrientationUnknown),
                         target.isFocused,
                         modelTopmost);
            [target setWindowFocused:YES];
        }
        break;
    }
}

%hook SpringBoard
- (void)sendEvent:(UIEvent *)event {
    CV3HandleFloatingWindowGlobalTouch(event);
    %orig(event);
}

- (BOOL)launchApplicationWithIdentifier:(NSString *)identifier suspended:(BOOL)suspended {
    // Screen Time 限额闸门：非 suspended 启动 = 前台化，不允许绕过限额
    if (!suspended &&
        !CV3ScreenTimeGateBundleID(identifier, @"SpringBoard.launchApplication")) {
        return YES;   // 已拒绝
    }
    if (!suspended && CV3FocusHostedFloatingWindowForBundleID(identifier,
                                                               @"SpringBoard.launchApplication")) return YES;

    if (!suspended) {
        CV3BeginWorkspaceTransitionProtection(@"ApplicationLaunchBegan");
    }
    return %orig(identifier, suspended);
}

- (void)applicationDidFinishLaunching:(id)application {
    %orig;

    if (sharedWindow) return;
    sharedWindow = [[CV3Window alloc] initWithFrame:[UIScreen mainScreen].bounds];
    sharedWindow.hidden = NO;
    sharedWindow.alpha = 1.0;
    [sharedWindow show];
    CV3ApplySceneRotationContextToProject(CV3MakeSceneRotationContext(sharedWindow.windowScene), @"SpringBoardLaunch", YES);
}
%end

@interface CV3PassthroughWindow : UIWindow
@end
static BOOL CV3ShouldSuppressKeyboardWindow(void);

@implementation CV3PassthroughWindow
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    if (CV3ShouldSuppressKeyboardWindow()) return nil;

    UIView *hitView = [super hitTest:point withEvent:event];
    if (hitView == self) return nil;
    return hitView;
}
@end

static CV3PassthroughWindow *cv3_keyboardWindow = nil;
static __weak CV3FloatingAppWindow *cv3_keyboardOwnerWindow = nil;
static NSHashTable<UIView *> *cv3_keyboardHostedViews = nil;

static BOOL CV3FloatingWindowRequiresLandscapeKeyboard(CV3FloatingAppWindow *window) {
    if (![window isKindOfClass:[CV3FloatingAppWindow class]] ||
        window.isClosing || window.isStashed || window.hidden) return NO;
    return UIInterfaceOrientationIsLandscape(window.hostedContentOrientation) &&
           UIInterfaceOrientationIsPortrait(window.windowScene.interfaceOrientation);
}

static BOOL CV3LandscapeHostedKeyboardRequired(void) {
    for (CV3FloatingAppWindow *window in [floatingWindows copy] ?: @[]) {
        if (CV3FloatingWindowRequiresLandscapeKeyboard(window)) return YES;
    }
    return NO;
}

static void CV3ApplyLandscapeKeyboardPresentation(UIWindow *keyboardWindow) {
    if (!keyboardWindow) return;
    BOOL shouldRotate = CV3LandscapeHostedKeyboardRequired();
    UIView *presentationView = nil;
    for (UIView *view in keyboardWindow.subviews) {
        if ([NSStringFromClass(view.class) isEqualToString:@"_UIScenePresentationView"]) {
            presentationView = view;
            break;
        }
    }
    if (!presentationView) {
        // 诊断：presentation view 未命中时不再静默（限流 2s）。
        // 实测层级为 SBFTouchPassThroughView -> _UIScenePresentationView，
        // 一层遍历会错过真正的承载视图。
        static CFTimeInterval lastKeyboardMissLogTime = 0;
        CFTimeInterval now = CACurrentMediaTime();
        if (now - lastKeyboardMissLogTime >= 2.0) {
            lastKeyboardMissLogTime = now;
            NSMutableArray<NSString *> *classes = [NSMutableArray array];
            for (UIView *view in keyboardWindow.subviews) {
                [classes addObject:NSStringFromClass(view.class)];
            }
            CV3LogToFile(@"[Warning][KeyboardDebug] medusaPresentationView.missed subviews=[%@] shouldRotate=%d windowBounds=%@ windowHidden=%d sceneOrientation=%ld",
                         [classes componentsJoinedByString:@","], shouldRotate,
                         NSStringFromCGRect(keyboardWindow.bounds), keyboardWindow.hidden,
                         (long)keyboardWindow.windowScene.interfaceOrientation);
        }
        return;
    }
    CGAffineTransform before = presentationView.transform;
    CGAffineTransform expected = shouldRotate ? CGAffineTransformMakeRotation((CGFloat)M_PI_2)
                                               : CGAffineTransformIdentity;
    BOOL differs = fabs(before.a - expected.a) > 0.001 || fabs(before.b - expected.b) > 0.001 ||
        fabs(before.c - expected.c) > 0.001 || fabs(before.d - expected.d) > 0.001;
    if (!differs) {
        // 诊断：命中但无需修改时也留痕（限流 2s），用于区分"未找到"与"已一致"。
        static CFTimeInterval lastKeyboardMatchLogTime = 0;
        CFTimeInterval now = CACurrentMediaTime();
        if (now - lastKeyboardMatchLogTime >= 2.0) {
            lastKeyboardMatchLogTime = now;
            CV3LogToFile(@"[Warning][KeyboardDebug] medusaPresentationView.match shouldRotate=%d transform=%@ windowBounds=%@ windowHidden=%d sceneOrientation=%ld",
                         shouldRotate, NSStringFromCGAffineTransform(before),
                         NSStringFromCGRect(keyboardWindow.bounds), keyboardWindow.hidden,
                         (long)keyboardWindow.windowScene.interfaceOrientation);
        }
        return;
    }
    presentationView.transform = expected;
    if (shouldRotate) {
        presentationView.center = CGPointMake(CGRectGetMidX(keyboardWindow.bounds), CGRectGetMidY(keyboardWindow.bounds));
    } else {
        presentationView.frame = keyboardWindow.bounds;
    }
    CV3LogToFile(@"[KeyboardDebug] medusaPresentationViewTransform applied=%d before=%@ after=%@ viewBounds=%@ viewFrame=%@ windowBounds=%@ sceneOrientation=%ld",
                 shouldRotate, NSStringFromCGAffineTransform(before),
                 NSStringFromCGAffineTransform(presentationView.transform),
                 NSStringFromCGRect(presentationView.bounds), NSStringFromCGRect(presentationView.frame),
                 NSStringFromCGRect(keyboardWindow.bounds), (long)keyboardWindow.windowScene.interfaceOrientation);
}

#pragma mark - 键盘现场取证（诊断专用，零行为改动）

static BOOL CV3KbSentinelExists(NSString *name) {
    NSArray<NSString *> *paths = @[
        [@"/rootfs/var/mobile/Library/Logs/" stringByAppendingString:name],
        [@"/var/mobile/Library/Logs/" stringByAppendingString:name],
        [@"/private/var/mobile/Library/Logs/" stringByAppendingString:name],
    ];
    NSFileManager *manager = [NSFileManager defaultManager];
    for (NSString *path in paths) {
        if ([manager fileExistsAtPath:path]) return YES;
    }
    return NO;
}

static BOOL CV3KbRotateFixEnabled(void) {
    static BOOL enabled = NO;
    static CFTimeInterval lastCheck = 0.0;
    CFTimeInterval now = CACurrentMediaTime();
    if (lastCheck != 0.0 && now - lastCheck < 2.0) return enabled;
    lastCheck = now;
    enabled = CV3KbSentinelExists(@"ChevronV3_KbRotateFix.enabled");
    return enabled;
}

static BOOL CV3TransformContainsRotation(CATransform3D transform) {
    return fabs(transform.m12) > 0.05 || fabs(transform.m21) > 0.05;
}

static NSString *CV3TransformShortDescription(CATransform3D transform) {
    return [NSString stringWithFormat:@"[%g,%g,%g,%g|%g,%g,%g,%g]",
            transform.m11, transform.m12, transform.m21, transform.m22,
            transform.m41, transform.m42, transform.m43, transform.m44];
}

static void CV3ScanRotationSuspects(CALayer *layer, NSUInteger depth,
                                    NSMutableArray<NSString *> *lines,
                                    NSUInteger *fixedCount, BOOL applyFix) {
    if (!layer || depth > 14 || lines.count >= 48) return;
    CATransform3D transform = layer.transform;
    CATransform3D subT = layer.sublayerTransform;
    CATransform3D presT = CATransform3DIdentity;
    CATransform3D presST = CATransform3DIdentity;
    CALayer *presentation = layer.presentationLayer;
    if (presentation) {
        presT = presentation.transform;
        presST = presentation.sublayerTransform;
    }
    BOOL rotated = CV3TransformContainsRotation(transform) || CV3TransformContainsRotation(subT) ||
                   CV3TransformContainsRotation(presT) || CV3TransformContainsRotation(presST);
    if (rotated) {
        [lines addObject:[NSString stringWithFormat:@"d=%lu %@ t=%@ st=%@ presT=%@ presST=%@ pos=%@ f=%@",
                          (unsigned long)depth, NSStringFromClass(layer.class),
                          CV3TransformShortDescription(transform), CV3TransformShortDescription(subT),
                          CV3TransformShortDescription(presT), CV3TransformShortDescription(presST),
                          NSStringFromCGPoint(layer.position), NSStringFromCGRect(layer.frame)]];
        if (applyFix && (CV3TransformContainsRotation(transform) || CV3TransformContainsRotation(subT))) {
            [CATransaction begin];
            [CATransaction setDisableActions:YES];
            if (CV3TransformContainsRotation(transform)) layer.transform = CATransform3DIdentity;
            if (CV3TransformContainsRotation(subT)) layer.sublayerTransform = CATransform3DIdentity;
            [CATransaction commit];
            *fixedCount = *fixedCount + 1;
        }
    }
    for (CALayer *child in layer.sublayers ?: @[]) {
        CV3ScanRotationSuspects(child, depth + 1, lines, fixedCount, applyFix);
    }
}

static UIView *CV3FindDescendantViewNamed(UIView *root, NSString *className, NSUInteger depth) {
    if (!root || depth > 14) return nil;
    if ([NSStringFromClass(root.class) isEqualToString:className]) return root;
    for (UIView *child in root.subviews ?: @[]) {
        UIView *found = CV3FindDescendantViewNamed(child, className, depth + 1);
        if (found) return found;
    }
    return nil;
}

// v160/v161 键盘旋转补偿实验（哨兵 ChevronV3_KbRotateFix.enabled 控制）：
// 实测键盘宿主视图（_UIKeyboardLayerHostView）及其全子树在本地无任何旋转分量
// （model/presentation 的 transform 与 sublayerTransform 均为 identity），
// 但屏幕上的键盘内容呈顺时针 90° 姿态 —— 旋转发生在远程内容/合成配置里。
//
// v160 首测（只施加 R(-90°)）结果：方向变化但内容被转出可视区（frame={(-251,251),{932,430}}）。
// v165：历史目标中心 {527,167} 只适用于当时的一组窗口几何。在 926x428
// 横屏宿主中，它会产生 frame.origin.x=64 的可见空白。补偿中心必须来自当前
// 父容器 bounds；同时保存 UIKit 原始几何，以便退出补偿时精确恢复。
static char kCV3KbFixOriginalTransformKey;
static char kCV3KbFixOriginalCenterKey;

static void CV3ApplyKeyboardRotationCompensation(UIView *keyboardHostView, BOOL enable) {
    if (!keyboardHostView) return;
    CGAffineTransform current = keyboardHostView.transform;
    CGAffineTransform compensation = CGAffineTransformMakeRotation((CGFloat)(-M_PI_2));
    BOOL alreadyCompensated =
        fabs(current.a - compensation.a) < 0.001 && fabs(current.b - compensation.b) < 0.001 &&
        fabs(current.c - compensation.c) < 0.001 && fabs(current.d - compensation.d) < 0.001;
    UIView *parentView = keyboardHostView.superview;
    CGRect parentBounds = parentView ? parentView.bounds : CGRectZero;
    CGPoint targetCenter = (!CGRectIsEmpty(parentBounds) && !CGRectIsNull(parentBounds))
        ? CGPointMake(CGRectGetMidX(parentBounds), CGRectGetMidY(parentBounds))
        : keyboardHostView.center;
    BOOL alreadyPlaced = alreadyCompensated &&
        fabs(keyboardHostView.center.x - targetCenter.x) < 0.5 &&
        fabs(keyboardHostView.center.y - targetCenter.y) < 0.5;
    if (enable) {
        if (alreadyPlaced) return;
        CGAffineTransform beforeTransform = current;
        CGPoint beforeCenter = keyboardHostView.center;
        if (!objc_getAssociatedObject(keyboardHostView, &kCV3KbFixOriginalTransformKey)) {
            objc_setAssociatedObject(keyboardHostView,
                                     &kCV3KbFixOriginalTransformKey,
                                     [NSValue valueWithCGAffineTransform:beforeTransform],
                                     OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            objc_setAssociatedObject(keyboardHostView,
                                     &kCV3KbFixOriginalCenterKey,
                                     [NSValue valueWithCGPoint:beforeCenter],
                                     OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        [CATransaction begin];
        [CATransaction setDisableActions:YES];
        keyboardHostView.transform = compensation;
        keyboardHostView.center = targetCenter;
        [CATransaction commit];
        CV3LogToFile(@"[Warning][KeyboardDebug] kbRotateFix.applied beforeT=%@ afterT=%@ beforeCenter=%@ afterCenter=%@ parentBounds=%@ bounds=%@ frame=%@ superview=%@",
                     NSStringFromCGAffineTransform(beforeTransform), NSStringFromCGAffineTransform(keyboardHostView.transform),
                     NSStringFromCGPoint(beforeCenter), NSStringFromCGPoint(keyboardHostView.center),
                     NSStringFromCGRect(parentBounds),
                     NSStringFromCGRect(keyboardHostView.bounds), NSStringFromCGRect(keyboardHostView.frame),
                     NSStringFromClass(keyboardHostView.superview.class));
    } else {
        NSValue *savedTransformValue = objc_getAssociatedObject(keyboardHostView, &kCV3KbFixOriginalTransformKey);
        NSValue *savedCenterValue = objc_getAssociatedObject(keyboardHostView, &kCV3KbFixOriginalCenterKey);
        if (!savedTransformValue || !savedCenterValue) return;
        CGAffineTransform originalTransform = savedTransformValue.CGAffineTransformValue;
        CGPoint originalCenter = savedCenterValue.CGPointValue;
        CGPoint beforeCenter = keyboardHostView.center;
        [CATransaction begin];
        [CATransaction setDisableActions:YES];
        keyboardHostView.transform = originalTransform;
        keyboardHostView.center = originalCenter;
        [CATransaction commit];
        objc_setAssociatedObject(keyboardHostView, &kCV3KbFixOriginalTransformKey, nil, OBJC_ASSOCIATION_ASSIGN);
        objc_setAssociatedObject(keyboardHostView, &kCV3KbFixOriginalCenterKey, nil, OBJC_ASSOCIATION_ASSIGN);
        CV3LogToFile(@"[Warning][KeyboardDebug] kbRotateFix.restored beforeT=%@ beforeCenter=%@ afterT=%@ afterCenter=%@",
                     NSStringFromCGAffineTransform(current), NSStringFromCGPoint(beforeCenter),
                     NSStringFromCGAffineTransform(originalTransform), NSStringFromCGPoint(originalCenter));
    }
}

static NSString *CV3KeyboardForensicsWindowLine(UIWindow *window) {
    UIWindowScene *scene = window.windowScene;
    NSString *sceneRole = scene ? (scene.session.role ?: @"nil") : @"scene=nil";
    return [NSString stringWithFormat:@"%@:%p sceneRole=%@ sceneOrient=%ld sceneBounds=%@ frame=%@ bounds=%@ transform=%@ hidden=%d alpha=%.2f level=%.1f root=%@",
            NSStringFromClass(window.class), window, sceneRole,
            (long)(scene ? scene.interfaceOrientation : 0),
            scene ? NSStringFromCGRect(scene.coordinateSpace.bounds) : @"nil",
            NSStringFromCGRect(window.frame), NSStringFromCGRect(window.bounds),
            NSStringFromCGAffineTransform(window.transform),
            window.hidden, window.alpha, window.windowLevel,
            window.rootViewController ? NSStringFromClass(window.rootViewController.class) : @"nil"];
}

static void CV3DumpKeyboardForensics(NSString *reason) {
    @try {
        @autoreleasepool {
            // 1) 场景清单（含键盘专属场景）
            NSMutableArray<NSString *> *sceneLines = [NSMutableArray array];
            for (UIScene *scene in [UIApplication sharedApplication].connectedScenes ?: [NSSet set]) {
                if (![scene isKindOfClass:[UIWindowScene class]]) continue;
                UIWindowScene *windowScene = (UIWindowScene *)scene;
                NSString *keyWindowClass = @"nil";
                if (@available(iOS 15.0, *)) {
                    if (windowScene.keyWindow) keyWindowClass = NSStringFromClass(windowScene.keyWindow.class);
                }
                [sceneLines addObject:[NSString stringWithFormat:@"role=%@ state=%ld orient=%ld bounds=%@ key=%@",
                    windowScene.session.role ?: @"nil",
                    (long)windowScene.activationState,
                    (long)windowScene.interfaceOrientation,
                    NSStringFromCGRect(windowScene.coordinateSpace.bounds),
                    keyWindowClass]];
            }
            CV3LogToFile(@"[Warning][KeyboardDebug] forensics.reason=%@ scenes=%lu [%@]",
                         reason, (unsigned long)sceneLines.count, [sceneLines componentsJoinedByString:@" | "]);

            // 2) 全窗口清单（application windows + 所有场景 windows 兜底）
            NSMutableOrderedSet<UIWindow *> *allWindows = [NSMutableOrderedSet orderedSet];
            for (UIWindow *window in [UIApplication sharedApplication].windows ?: @[]) {
                [allWindows addObject:window];
            }
            for (UIScene *scene in [UIApplication sharedApplication].connectedScenes ?: [NSSet set]) {
                if (![scene isKindOfClass:[UIWindowScene class]]) continue;
                UIWindowScene *windowScene = (UIWindowScene *)scene;
                if ([windowScene respondsToSelector:@selector(windows)]) {
                    for (UIWindow *window in windowScene.windows ?: @[]) {
                        [allWindows addObject:window];
                    }
                }
            }
            NSMutableArray<NSString *> *windowLines = [NSMutableArray array];
            NSMutableArray<UIWindow *> *keyboardWindows = [NSMutableArray array];
            for (UIWindow *window in allWindows) {
                [windowLines addObject:CV3KeyboardForensicsWindowLine(window)];
                NSString *className = NSStringFromClass(window.class);
                NSString *role = window.windowScene.session.role ?: @"";
                BOOL keyboardNamed = [className localizedCaseInsensitiveContainsString:@"keyboard"] ||
                    [className localizedCaseInsensitiveContainsString:@"TextEffects"] ||
                    [role localizedCaseInsensitiveContainsString:@"keyboard"];
                if (keyboardNamed) {
                    [keyboardWindows addObject:window];
                }
            }
            CV3LogToFile(@"[Warning][KeyboardDebug] forensics.windows count=%lu [%@]",
                         (unsigned long)allWindows.count, [windowLines componentsJoinedByString:@" | "]);

            // 2b) 键盘类窗口深度视图/图层树（键盘渲染载体的直接证据）
            for (UIWindow *window in keyboardWindows) {
                NSMutableArray<NSString *> *viewTree = [NSMutableArray array];
                NSMutableArray<NSString *> *layerTree = [NSMutableArray array];
                CV3AppendKeyboardViewTree(window.rootViewController.view ?: window, 0, viewTree);
                CV3AppendKeyboardLayerTree(window.layer, 0, layerTree);
                CV3LogToFile(@"[Warning][KeyboardDebug] forensics.kbWindow %@:%p views=[%@]",
                             NSStringFromClass(window.class), window,
                             [viewTree componentsJoinedByString:@" | "]);
                CV3LogToFile(@"[Warning][KeyboardDebug] forensics.kbWindow %@:%p layers=[%@]",
                             NSStringFromClass(window.class), window,
                             [layerTree componentsJoinedByString:@" | "]);
            }

            // 3) 浮窗宿主容器（键盘层若寄宿在此，transform 即旋转证据）
            for (CV3FloatingAppWindow *win in [floatingWindows copy] ?: @[]) {
                if (![win isKindOfClass:[CV3FloatingAppWindow class]] || win.isClosing) continue;
                NSMutableArray<NSString *> *viewTree = [NSMutableArray array];
                NSMutableArray<NSString *> *layerTree = [NSMutableArray array];
                if (win.hostView) {
                    CV3AppendKeyboardViewTree(win.hostView, 0, viewTree);
                    CV3AppendKeyboardLayerTree(win.hostView.layer, 0, layerTree);
                }
                CV3LogToFile(@"[Warning][KeyboardDebug] forensics.hosted bundle=%@ stashed=%d hidden=%d root=%@ proxy=%@ hostView=%@ hostedViews=[%@]",
                             win.bundleID, win.isStashed, win.hidden,
                             NSStringFromCGAffineTransform(win.rootTransformContainer.transform),
                             NSStringFromCGAffineTransform(win.hostContainerProxy.transform),
                             win.hostView,
                             [viewTree componentsJoinedByString:@" | "]);
                CV3LogToFile(@"[Warning][KeyboardDebug] forensics.hostedLayers bundle=%@ [%@]",
                             win.bundleID, [layerTree componentsJoinedByString:@" | "]);
                CV3LogToFile(@"[Warning][KeyboardDebug] forensics.hostedScene bundle=%@ %@",
                             win.bundleID, CV3SceneLayerManagerAudit(win.targetScene));

                // 3b) 键盘宿主视图专项：_UIKeyboardLayerHostView 位于容器第二层
                //（_UITouchPassthroughView 之下），承载层即 _UIDirectionalRotationLayer。
                UIView *kbHostView = win.hostView
                    ? CV3FindDescendantViewNamed(win.hostView, @"_UIKeyboardLayerHostView", 0)
                    : nil;
                if (kbHostView) {
                    CALayer *kbLayer = kbHostView.layer;
                    CALayer *kbPresentation = kbLayer.presentationLayer;
                    NSMutableArray<NSString *> *kvPairs = [NSMutableArray array];
                    for (NSString *key in @[@"_direction", @"direction", @"rotation", @"_rotation", @"angle", @"_angle",
                                            @"interfaceOrientation", @"_interfaceOrientation", @"orientation", @"_orientation",
                                            @"contentOrientation", @"_contentOrientation", @"deviceOrientation", @"_deviceOrientation"]) {
                        if ([kbLayer respondsToSelector:NSSelectorFromString(key)]) {
                            id value = nil;
                            @try { value = [kbLayer valueForKey:key]; } @catch (__unused NSException *exception) {}
                            if (value) [kvPairs addObject:[NSString stringWithFormat:@"%@=%@", key, value]];
                        }
                    }
                    CV3LogToFile(@"[Warning][KeyboardDebug] forensics.kbHostView bundle=%@ view=%@ frame=%@ center=%@ transform=%@ layer=%@ layerT=%@ layerST=%@ presT=%@ presST=%@ presFrame=%@ kv={%@}",
                                 win.bundleID, kbHostView,
                                 NSStringFromCGRect(kbHostView.frame), NSStringFromCGPoint(kbHostView.center),
                                 NSStringFromCGAffineTransform(kbHostView.transform),
                                 kbLayer,
                                 CV3TransformShortDescription(kbLayer.transform),
                                 CV3TransformShortDescription(kbLayer.sublayerTransform),
                                 kbPresentation ? CV3TransformShortDescription(kbPresentation.transform) : @"nil",
                                 kbPresentation ? CV3TransformShortDescription(kbPresentation.sublayerTransform) : @"nil",
                                 kbPresentation ? NSStringFromCGRect(kbPresentation.frame) : @"nil",
                                 [kvPairs componentsJoinedByString:@";"]);

                    NSMutableArray<NSString *> *suspects = [NSMutableArray array];
                    NSUInteger fixedCount = 0;
                    CV3ScanRotationSuspects(kbLayer, 0, suspects, &fixedCount, NO);
                    CV3LogToFile(@"[Warning][KeyboardDebug] forensics.rotationSuspects bundle=%@ applyFix=0 fixed=0 suspects=[%@]",
                                 win.bundleID,
                                 suspects.count ? [suspects componentsJoinedByString:@" | "] : @"<none>");

                }
            }

            // 4) CV3 键盘判定值
            CV3LogToFile(@"[Warning][KeyboardDebug] forensics.flags shouldRotate=%d cv3KeyboardWindow=%@ owner=%@ hostedCount=%lu",
                         CV3LandscapeHostedKeyboardRequired(),
                         cv3_keyboardWindow ? NSStringFromClass(cv3_keyboardWindow.class) : @"nil",
                         cv3_keyboardOwnerWindow ? cv3_keyboardOwnerWindow.bundleID : @"nil",
                         (unsigned long)cv3_keyboardHostedViews.count);
        }
    } @catch (NSException *exception) {
        CV3LogToFile(@"[Warning][KeyboardDebug] forensics.exception %@ reason=%@", exception, reason);
    }
}

static CV3FloatingAppWindow *CV3FloatingWindowOwningHostContainer(UIView *container) {
    if (!container || !floatingWindows) return nil;
    for (CV3FloatingAppWindow *window in [floatingWindows copy]) {
        if (![window isKindOfClass:[CV3FloatingAppWindow class]] || window.isClosing) continue;
        if (window.hostView == container) return window;
    }
    return nil;
}

static CV3FloatingAppWindow *CV3FloatingWindowOwningDescendantView(UIView *view) {
    for (UIView *ancestor = view; ancestor; ancestor = ancestor.superview) {
        CV3FloatingAppWindow *owner = CV3FloatingWindowOwningHostContainer(ancestor);
        if (owner) return owner;
    }
    return nil;
}

static BOOL CV3ApplyHostedKeyboardRotationCompensation(UIView *keyboardHostView,
                                                         NSString *phase) {
    if (!keyboardHostView || !CV3KbRotateFixEnabled()) return NO;
    CV3FloatingAppWindow *owner = CV3FloatingWindowOwningDescendantView(keyboardHostView);
    BOOL shouldApply = owner && CV3FloatingWindowRequiresLandscapeKeyboard(owner);
    CV3LogToFile(@"[Warning][KeyboardDebug] kbRotateFix.hostLayout phase=%@ owner=%@ shouldApply=%d window=%@ superview=%@ bounds=%@",
                 phase ?: @"unknown",
                 owner.bundleID ?: @"nil",
                 shouldApply,
                 NSStringFromClass(keyboardHostView.window.class),
                 NSStringFromClass(keyboardHostView.superview.class),
                 NSStringFromCGRect(keyboardHostView.bounds));
    if (!owner) return NO;
    // The same keyboard Host survives a landscape -> portrait transition.
    // A false decision must therefore restore the geometry saved by the true
    // decision; returning here leaves the -90 degree transform attached and
    // moves the portrait keyboard outside its 428x926 parent.
    CV3ApplyKeyboardRotationCompensation(keyboardHostView, shouldApply);
    return shouldApply;
}

static void CV3ReleaseKeyboardHostingForWindow(CV3FloatingAppWindow *window) {
    if (window && cv3_keyboardOwnerWindow != window) return;

    for (UIView *hostedView in cv3_keyboardHostedViews.allObjects) {
        [hostedView removeFromSuperview];
    }
    [cv3_keyboardHostedViews removeAllObjects];
    cv3_keyboardOwnerWindow = nil;

    if (cv3_keyboardWindow) {
        cv3_keyboardWindow.userInteractionEnabled = NO;
        cv3_keyboardWindow.alpha = 0.0;
        cv3_keyboardWindow.hidden = YES;
    }
}

static BOOL CV3ShouldSuppressKeyboardWindow(void) {
    if (!CV3KeyboardSuppressedByPanel) return NO;
    if (sharedWindow && sharedWindow.searchField && sharedWindow.searchField.isFirstResponder) return NO;
    return YES;
}

static void CV3SetKeyboardSuppressedByPanel(BOOL suppressed) {
    CV3KeyboardSuppressedByPanel = suppressed;
    if (!cv3_keyboardWindow) return;

    BOOL shouldSuppressWindow = CV3ShouldSuppressKeyboardWindow();
    cv3_keyboardWindow.userInteractionEnabled = !shouldSuppressWindow;
    cv3_keyboardWindow.alpha = shouldSuppressWindow ? 0.0 : 1.0;
    cv3_keyboardWindow.hidden = shouldSuppressWindow;
}

static UIWindowScene *CV3KeyboardHostScene(void) {
    if (@available(iOS 13.0, *)) {
        if (sharedWindow.windowScene &&
            sharedWindow.windowScene.activationState == UISceneActivationStateForegroundActive) {
            return sharedWindow.windowScene;
        }
    }
    return nil;
}

@interface CV3SnapshotView : UIView
@end
@implementation CV3SnapshotView
@end

%hook _UISceneLayerHostContainerView
- (void)layoutSubviews {
    %orig;
    BOOL isChevronHost = [self.accessibilityIdentifier isEqualToString:@"ChevronV3Host"];
    if (!isChevronHost) return;

    CV3FloatingAppWindow *ownerWindow = CV3FloatingWindowOwningHostContainer(self);
    if (!ownerWindow) return;

    NSMutableArray<NSString *> *hostSubviewDiagnostics = [NSMutableArray array];
    for (UIView *hostSubview in self.subviews) {
        [hostSubviewDiagnostics addObject:[NSString stringWithFormat:@"%@ frame=%@ bounds=%@ center=%@ transform=%@ hidden=%d alpha=%.2f layers=%lu",
                                          NSStringFromClass(hostSubview.class),
                                          NSStringFromCGRect(hostSubview.frame),
                                          NSStringFromCGRect(hostSubview.bounds),
                                          NSStringFromCGPoint(hostSubview.center),
                                          NSStringFromCGAffineTransform(hostSubview.transform),
                                          hostSubview.hidden,
                                          hostSubview.alpha,
                                          (unsigned long)hostSubview.layer.sublayers.count]];
    }
    NSMutableArray<NSString *> *hostLayerDiagnostics = [NSMutableArray array];
    CV3AppendKeyboardLayerTree(self.layer, 0, hostLayerDiagnostics);
    for (CALayer *hostLayer in self.layer.sublayers) {
        BOOL markedKeyboard = [hostLayer respondsToSelector:@selector(isKeyboardLayer)] &&
                              ((BOOL (*)(id, SEL))objc_msgSend)(hostLayer, @selector(isKeyboardLayer));
        NSString *layerClass = NSStringFromClass(hostLayer.class);
        if (markedKeyboard || [layerClass localizedCaseInsensitiveContainsString:@"keyboard"]) {
            [hostLayerDiagnostics addObject:[NSString stringWithFormat:@"%@ keyboard=%d frame=%@ bounds=%@ position=%@ transform=%@ hidden=%d opacity=%.2f",
                                             layerClass,
                                             markedKeyboard,
                                             NSStringFromCGRect(hostLayer.frame),
                                             NSStringFromCGRect(hostLayer.bounds),
                                             NSStringFromCGPoint(hostLayer.position),
                                             [NSString stringWithFormat:@"[%g,%g,%g,%g,%g,%g,%g,%g,%g,%g,%g,%g,%g,%g,%g,%g]",
                                              hostLayer.transform.m11, hostLayer.transform.m12,
                                              hostLayer.transform.m13, hostLayer.transform.m14,
                                              hostLayer.transform.m21, hostLayer.transform.m22,
                                              hostLayer.transform.m23, hostLayer.transform.m24,
                                              hostLayer.transform.m31, hostLayer.transform.m32,
                                              hostLayer.transform.m33, hostLayer.transform.m34,
                                              hostLayer.transform.m41, hostLayer.transform.m42,
                                              hostLayer.transform.m43, hostLayer.transform.m44],
                                             hostLayer.hidden,
                                             hostLayer.opacity]];
        }
    }
    CV3LogToFile(@"[Warning][KeyboardDebug] hostLayout host=%@ bounds=%@ frame=%@ center=%@ transform=%@ subviews=[%@] keyboardLayers=[%@]",
                 NSStringFromClass(self.class),
                 NSStringFromCGRect(self.bounds),
                 NSStringFromCGRect(self.frame),
                 NSStringFromCGPoint(self.center),
                 NSStringFromCGAffineTransform(self.transform),
                 [hostSubviewDiagnostics componentsJoinedByString:@" | "],
                 [hostLayerDiagnostics componentsJoinedByString:@" | "]);
    NSMutableArray<NSString *> *keyboardWindowDiagnostics = [NSMutableArray array];
    for (UIWindow *window in [UIApplication sharedApplication].windows ?: @[]) {
        NSString *className = NSStringFromClass(window.class);
        NSString *description = [window description] ?: @"";
        BOOL keyboardNamed = [className localizedCaseInsensitiveContainsString:@"keyboard"] ||
            [description localizedCaseInsensitiveContainsString:@"keyboard"] ||
            [window.accessibilityIdentifier localizedCaseInsensitiveContainsString:@"keyboard"];
        if (!keyboardNamed && window != cv3_keyboardWindow) continue;
        UIWindowScene *scene = window.windowScene;
        NSMutableArray<NSString *> *windowViewTree = [NSMutableArray array];
        NSMutableArray<NSString *> *windowLayerTree = [NSMutableArray array];
        CV3AppendKeyboardViewTree(window.rootViewController.view ?: window, 0, windowViewTree);
        CV3AppendKeyboardLayerTree(window.layer, 0, windowLayerTree);
        [keyboardWindowDiagnostics addObject:[NSString stringWithFormat:
            @"window=%@:%p scene=%@ sceneOrientation=%ld coordinateBounds=%@ bounds=%@ frame=%@ transform=%@ hidden=%d alpha=%.2f level=%.1f root=%@ views=[%@] layers=[%@]",
            className, window, scene, (long)scene.interfaceOrientation,
            NSStringFromCGRect(scene.coordinateSpace.bounds), NSStringFromCGRect(window.bounds),
            NSStringFromCGRect(window.frame), NSStringFromCGAffineTransform(window.transform),
            window.hidden, window.alpha, window.windowLevel,
            window.rootViewController ? NSStringFromClass(window.rootViewController.class) : @"nil",
            [windowViewTree componentsJoinedByString:@" | "],
            [windowLayerTree componentsJoinedByString:@" | "]]];
    }
    if (keyboardWindowDiagnostics.count > 0) {
        for (UIWindow *window in [UIApplication sharedApplication].windows ?: @[]) {
            if ([NSStringFromClass(window.class) isEqualToString:@"SBMedusaHostedKeyboardWindow"]) {
                CV3ApplyLandscapeKeyboardPresentation(window);
            }
        }
        CV3LogToFile(@"[Warning][KeyboardDebug] keyboardWindows %@",
                     [keyboardWindowDiagnostics componentsJoinedByString:@" | "]);
    }
    [ownerWindow synchronizeHostedContextLayerGeometry];

    for (UIView *subview in self.subviews) {
        Class keyboardHostClass = NSClassFromString(@"_UIKeyboardLayerHostView");
        BOOL isKeyboardLayer =
            (keyboardHostClass && [subview isKindOfClass:keyboardHostClass]) ||
            [NSStringFromClass([subview class]) containsString:@"Keyboard"];
        if (!isKeyboardLayer) {
            if (CGAffineTransformIsIdentity(subview.transform)) {
                subview.frame = self.bounds;
            } else {
                subview.bounds = CGRectMake(0, 0, self.bounds.size.width, self.bounds.size.height);
                subview.center = CGPointMake(self.bounds.size.width / 2.0, self.bounds.size.height / 2.0);
            }
            continue;
        }

        if (isKeyboardLayer) {
            if (cv3_keyboardHostedViews.count > 0 && cv3_keyboardOwnerWindow != ownerWindow) {
                CV3ReleaseKeyboardHostingForWindow(nil);
            }
            cv3_keyboardOwnerWindow = ownerWindow;
            if (!cv3_keyboardHostedViews) {
                cv3_keyboardHostedViews = [NSHashTable weakObjectsHashTable];
            }

            UIWindowScene *keyboardScene = nil;
            if (@available(iOS 13.0, *)) {
                keyboardScene = CV3KeyboardHostScene();
            }

            if (!cv3_keyboardWindow) {
                if (@available(iOS 15.0, *)) {
                    if (keyboardScene) {
                        cv3_keyboardWindow = [[CV3PassthroughWindow alloc] initWithWindowScene:keyboardScene];
                    } else {
                        cv3_keyboardWindow = [[CV3PassthroughWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
                    }
                } else {
                    cv3_keyboardWindow = [[CV3PassthroughWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
                }
                cv3_keyboardWindow.windowLevel = CV3Style.keyboard;
                cv3_keyboardWindow.backgroundColor = [UIColor clearColor];
                BOOL shouldSuppressKeyboardWindow = CV3ShouldSuppressKeyboardWindow();
                cv3_keyboardWindow.hidden = shouldSuppressKeyboardWindow;
                cv3_keyboardWindow.alpha = shouldSuppressKeyboardWindow ? 0.0 : 1.0;
                cv3_keyboardWindow.userInteractionEnabled = !shouldSuppressKeyboardWindow;
            } else if (@available(iOS 13.0, *)) {
                if (keyboardScene && cv3_keyboardWindow.windowScene != keyboardScene) {
                    CV3PassthroughWindow *oldKeyboardWindow = cv3_keyboardWindow;
                    oldKeyboardWindow.userInteractionEnabled = NO;
                    oldKeyboardWindow.alpha = 0.0;
                    oldKeyboardWindow.hidden = YES;
                    cv3_keyboardWindow = [[CV3PassthroughWindow alloc] initWithWindowScene:keyboardScene];
                    cv3_keyboardWindow.windowLevel = CV3Style.keyboard;
                    cv3_keyboardWindow.backgroundColor = [UIColor clearColor];
                    BOOL shouldSuppressKeyboardWindow = CV3ShouldSuppressKeyboardWindow();
                    cv3_keyboardWindow.hidden = shouldSuppressKeyboardWindow;
                    cv3_keyboardWindow.alpha = shouldSuppressKeyboardWindow ? 0.0 : 1.0;
                    cv3_keyboardWindow.userInteractionEnabled = !shouldSuppressKeyboardWindow;

                    for (UIView *hostedView in cv3_keyboardHostedViews.allObjects) {
                        if (hostedView != subview) {
                            [hostedView removeFromSuperview];
                            [cv3_keyboardWindow addSubview:hostedView];
                        }
                    }
                }
            }

            CGRect hostBounds = CGRectZero;
            if (@available(iOS 13.0, *)) {
                if (keyboardScene && !CGRectIsEmpty(keyboardScene.coordinateSpace.bounds)) {
                    hostBounds = keyboardScene.coordinateSpace.bounds;
                }
            }
            if (CGRectIsEmpty(hostBounds)) {
                hostBounds = [UIScreen mainScreen].bounds;
            }
            // The keyboard window must share the outer floating window's
            // physical rect. Keeping it at full-scene size makes UIKit apply
            // full-screen safe-area insets, which leaves the fixed left and
            // bottom gaps visible in the split input region.
            CGRect splitWindowFrame = [ownerWindow convertRect:ownerWindow.bounds toView:nil];
            if (!CGRectIsNull(splitWindowFrame) && !CGRectIsEmpty(splitWindowFrame)) {
                cv3_keyboardWindow.frame = splitWindowFrame;
                hostBounds = cv3_keyboardWindow.bounds;
            } else {
                cv3_keyboardWindow.frame = hostBounds;
            }

            UIInterfaceOrientation orientation = CV3TrustedInterfaceOrientation(keyboardScene);
            BOOL isLandscape = UIInterfaceOrientationIsLandscape(orientation);
            CGAffineTransform preservedTransform = subview.transform;
            CGRect preservedBounds = subview.bounds;
            CGPoint preservedCenter = subview.center;
            UIView *previousSuperview = subview.superview;
            CGRect keyboardHostBounds = self.bounds;
            // Capture the actual split input rect before removing the host from
            // the scene container. After reparenting, the old center is no
            // longer meaningful in keyboard-window coordinates and causes the
            // left/bottom inset visible in split-screen.
            CGRect splitInputRectInKeyboardWindow = cv3_keyboardWindow.bounds;
            BOOL hostAxesDiffer = (keyboardHostBounds.size.width > keyboardHostBounds.size.height) !=
                                  (hostBounds.size.width > hostBounds.size.height);
            CV3LogToFile(@"[Warning][KeyboardDebug] keyboardLayer found class=%@ hostScene=%@ orientation=%ld isLandscape=%d hostBounds=%@ oldSuperview=%@ oldTransform=%@ oldBounds=%@ oldCenter=%@ window=%@",
                         NSStringFromClass([subview class]),
                         keyboardScene,
                         (long)orientation,
                         isLandscape,
                         NSStringFromCGRect(hostBounds),
                         previousSuperview,
                         NSStringFromCGAffineTransform(preservedTransform),
                         NSStringFromCGRect(preservedBounds),
                         NSStringFromCGPoint(preservedCenter),
                         cv3_keyboardWindow);

            if (hostAxesDiffer) {
                // UIKit creates the keyboard in the scene's display axis, while a
                // hosted split window can use the opposite axis. Leaving the
                // original bounds in place produces the visible inset/crop seen
                // in split-screen: the keyboard background follows the split
                // window, but the key grid keeps its full-screen geometry. The
                // host container is the geometry authority here, so fit the
                // keyboard layer to that exact input region. Keep an existing
                // UIKit rotation, if any; only the axis-aligned case needs an
                // identity transform.
                if (CGAffineTransformIsIdentity(preservedTransform) &&
                    !CGRectIsNull(splitInputRectInKeyboardWindow) &&
                    !CGRectIsEmpty(splitInputRectInKeyboardWindow)) {
                    preservedBounds = CGRectMake(0, 0,
                                                 CGRectGetWidth(splitInputRectInKeyboardWindow),
                                                 CGRectGetHeight(splitInputRectInKeyboardWindow));
                    preservedCenter = CGPointMake(CGRectGetMidX(splitInputRectInKeyboardWindow),
                                                  CGRectGetMidY(splitInputRectInKeyboardWindow));
                }
                CV3LogToFile(@"[Warning][KeyboardDebug] keyboardLayer axis-fit.applied class=%@ hostBounds=%@ ownerBounds=%@ splitInputRect=%@ keyboardWindowBounds=%@ oldBounds=%@ oldCenter=%@ transform=%@",
                             NSStringFromClass([subview class]),
                             NSStringFromCGRect(keyboardHostBounds),
                             NSStringFromCGRect(ownerWindow.bounds),
                             NSStringFromCGRect(splitInputRectInKeyboardWindow),
                             NSStringFromCGRect(hostBounds),
                             NSStringFromCGRect(preservedBounds),
                             NSStringFromCGPoint(preservedCenter),
                             NSStringFromCGAffineTransform(preservedTransform));
            } else if (!isLandscape && CGAffineTransformIsIdentity(preservedTransform)) {
                preservedBounds = CGRectMake(0, 0, hostBounds.size.width, hostBounds.size.height);
                preservedCenter = CGPointMake(hostBounds.size.width / 2.0, hostBounds.size.height / 2.0);
            } else if (previousSuperview && previousSuperview != cv3_keyboardWindow) {
                preservedCenter = [previousSuperview convertPoint:preservedCenter toView:cv3_keyboardWindow];
                CV3LogToFile(@"[Warning][KeyboardDebug] converted keyboardLayer center=%@ fromSuperview=%@ toWindow=%@",
                             NSStringFromCGPoint(preservedCenter),
                             previousSuperview,
                             cv3_keyboardWindow);
            }

            if (subview.superview != cv3_keyboardWindow) {
                [subview removeFromSuperview];
                [cv3_keyboardWindow addSubview:subview];
            }
            [cv3_keyboardHostedViews addObject:subview];

            // In landscape the keyboard host view already carries UIKit's rotation
            // geometry. Resetting it to identity moves the keyboard off-screen.
            subview.transform = preservedTransform;
            subview.bounds = preservedBounds;
            subview.center = preservedCenter;
            CV3LogToFile(@"[Warning][KeyboardDebug] keyboardLayer applied transform=%@ bounds=%@ center=%@ superview=%@ windowFrame=%@",
                         NSStringFromCGAffineTransform(subview.transform),
                         NSStringFromCGRect(subview.bounds),
                         NSStringFromCGPoint(subview.center),
                         subview.superview,
                         NSStringFromCGRect(cv3_keyboardWindow.frame));
        }
    }
}

// 核心修复：防止系统在过渡期间将宿主容器透明化
- (void)setAlpha:(CGFloat)alpha {
    if (alpha < 1.0 && [self.accessibilityIdentifier isEqualToString:@"ChevronV3Host"]) {
        CV3LogToFile(@"[Container] 拦截系统透明化请求: alpha=%.2f", alpha);
        %orig(1.0);
        return;
    }
    %orig(alpha);
}

- (void)setHidden:(BOOL)hidden {
    if (hidden && [self.accessibilityIdentifier isEqualToString:@"ChevronV3Host"]) {
        CV3LogToFile(@"[Container] 拦截系统隐藏请求");
        %orig(NO);
        return;
    }
    %orig(hidden);
}
%end

%hook SBMedusaHostedKeyboardWindow
- (void)layoutSubviews {
    %orig;
    CV3ApplyLandscapeKeyboardPresentation((UIWindow *)self);
}
%end

// UIKit 在 didMoveToSuperview 之后才为该 Host 写入最终 428x926 几何，并会把
// 过早写入的 transform 重置为 identity。必须在 Host 自身完成原生布局后同步
// 施加补偿；此时祖先链、非零 bounds 与真实承载对象三者同时成立。
// 此路径不能依赖 cv3_keyboardOwnerWindow/cv3_keyboardWindow：原生 hosted
// keyboard 可以直接留在浮窗 hostView 中，使这两个 reparent 状态始终为 nil。
%hook _UIKeyboardLayerHostView

- (void)layoutSubviews {
    %orig;
    if (!CV3KbRotateFixEnabled()) return;
    UIView *keyboardHost = (UIView *)self;
    if (CGRectIsEmpty(keyboardHost.bounds) || CGRectIsNull(keyboardHost.bounds)) return;
    CV3ApplyHostedKeyboardRotationCompensation(keyboardHost, @"layoutSubviews.afterOrig");
}

%end

%hook SBApplication
- (BOOL)isBackgrounded {
    BOOL originalBackgrounded = %orig;
    CV3RecordApplicationForegroundState(self.bundleIdentifier, !originalBackgrounded);

    if (floatingWindows && floatingWindows.count > 0) {
        for (CV3FloatingAppWindow *win in floatingWindows) {
            if ([self.bundleIdentifier isEqualToString:win.bundleID] && !win.isClosing) {
                // 如果窗口被 Stash (侧边隐藏)，允许应用进入正常的后台挂起状态，减少 CPU/内存压力
                if (win.isStashed) return originalBackgrounded;
                return NO; // 核心：欺骗系统，让其认为该 App 始终在“前台”运行
            }
        }
    }
    return originalBackgrounded;
}

- (BOOL)isSuspended {
    BOOL originalSuspended = %orig;

    if (floatingWindows && floatingWindows.count > 0) {
        for (CV3FloatingAppWindow *win in floatingWindows) {
            if ([self.bundleIdentifier isEqualToString:win.bundleID] && !win.isClosing) {
                if (win.isStashed) return originalSuspended;
                return NO; 
            }
        }
    }
    return originalSuspended;
}
%end

%hook SBMainSwitcherViewController
- (void)viewWillAppear:(BOOL)animated {
    CV3MainSwitcherVisible = YES;
    CV3BeginWorkspaceTransitionProtection(@"SwitcherViewWillAppear");
    %orig(animated);
}

- (void)viewDidDisappear:(BOOL)animated {
    %orig(animated);
    CV3SwitcherWindowVisible = NO;
    CV3MainSwitcherVisible = NO;
    CV3EndWorkspaceTransitionProtection(@"SwitcherViewDidDisappear");
}

- (void)setSwitcherWindowVisible:(BOOL)arg1 {
    CV3SwitcherWindowVisible = arg1;
    if (CV3SwitcherPresentationActive()) {
        CV3BeginWorkspaceTransitionProtection(@"SwitcherWindowVisible");
    } else {
        CV3EndWorkspaceTransitionProtection(@"SwitcherWindowHidden");
    }
    %orig;
    // 核心：当 Switcher 窗口状态改变时，强制刷新所有分屏窗口的显示状态
    if (floatingWindows) {
        for (CV3FloatingAppWindow *win in floatingWindows) {
            if ([win isKindOfClass:[CV3FloatingAppWindow class]] && !win.isClosing) {
                [win setHidden:NO];
                win.windowLevel = CV3Style.floatingApp;
                if (CV3WorkspaceTransitionActive || arg1) {
                    [win stabilizeForegroundForWorkspaceTransition:@"SwitcherWindowVisible"];
                } else {
                    [win refreshHostViewPresentation];
                }
            }
        }
    }
}

- (void)_setMainSwitcherVisible:(BOOL)arg1 {
    CV3MainSwitcherVisible = arg1;
    if (CV3SwitcherPresentationActive()) {
        CV3BeginWorkspaceTransitionProtection(@"MainSwitcherVisible");
    } else {
        CV3EndWorkspaceTransitionProtection(@"MainSwitcherHidden");
    }
    %orig;
    if (floatingWindows) {
        for (CV3FloatingAppWindow *win in floatingWindows) {
            if ([win isKindOfClass:[CV3FloatingAppWindow class]] && !win.isClosing) {
                [win setHidden:NO];
                if (CV3WorkspaceTransitionActive || arg1) {
                    [win stabilizeForegroundForWorkspaceTransition:@"MainSwitcherVisible"];
                } else {
                    [win refreshHostViewPresentation];
                }
            }
        }
    }
}
%end

%hook FBScene
- (void)updateSettings:(id)arg1 withTransitionContext:(id)arg2 {
    CV3RecordSceneForegroundState((FBScene *)self, arg1, @"updateSettings");

    if (floatingWindows) {
        for (CV3FloatingAppWindow *win in floatingWindows) {
            if (CV3IdentifierContainsExactBundleID(self.identifier, win.bundleID) && !win.isClosing) {
                CV3LogToFile(@"[Strict] trace=%@ phase=fbscene.intercept.entry api=updateSettings transition=%@ incoming={%@} expanded={%@}",
                             win.coldLaunchTraceID, arg2 ?: @"nil", CV3SceneSettingsFingerprint(arg1),
                             CV3DiagnosticObjectFingerprint(arg1));
                // 如果窗口被 Stash (侧边隐藏)，且系统正在尝试将其置于后台，我们不再强制拉回前台
                // 这能有效避免系统判定应用“违规占据前台”而触发的杀进程行为 (0xDEAD10CC)
                if (win.isStashed) {
                    CV3LogToFile(@"[Strict] trace=%@ phase=fbscene.intercept.passThrough.stashed outgoing={%@}",
                                 win.coldLaunchTraceID, CV3SceneSettingsFingerprint(arg1));
                    %orig(arg1, arg2);
                    return;
                }

                id mutableSettings = [arg1 mutableCopy];
                BOOL modified = [win applyForegroundSovereigntyToSettings:mutableSettings
                                                         clearDeactivation:YES
                                                               forceLayout:NO];

                if (modified) {
                    if (CV3ShouldRewriteSceneSettings((FBScene *)self, win.bundleID, mutableSettings)) {
                        CV3LogToFile(@"[Warning][PlaybackTrace] source=SpringBoard event=FBSceneSettingsRewritten bundle=%@ transition=%@",
                                     win.bundleID, arg2 ? @"YES" : @"NO");
                        CV3LogToFile(@"[FBScene] 捕捉到 Settings 更新请求: %@", win.bundleID);
                    }
                    // The gate only throttles diagnostics. Passing arg1 here
                    // allowed FrontBoard's background settings to escape.
                    CV3LogToFile(@"[Strict] trace=%@ phase=fbscene.intercept.forward.rewritten outgoing={%@}",
                                 win.coldLaunchTraceID, CV3SceneSettingsFingerprint(mutableSettings));
                    %orig(mutableSettings, arg2);
                } else {
                    CV3LogToFile(@"[Strict] trace=%@ phase=fbscene.intercept.forward.unchanged outgoing={%@}",
                                 win.coldLaunchTraceID, CV3SceneSettingsFingerprint(arg1));
                    %orig(arg1, arg2);
                }
                [win recordStrictSplitTrace:@"fbscene.intercept.returned" details:@"api=updateSettings"];
                
                // [Anti-Ghosting] Detect transition and clear stale frames
                if (arg2 != nil && !CV3WorkspaceTransitionActive) {
                    [win performSelectorOnMainThread:@selector(handleTransitionGhosting) withObject:nil waitUntilDone:NO];
                }
                // [Optimization] 移除此处的 refreshHostViewPresentation。
                // 全局设置更新极其频繁，此处重置 Context 会导致画面掉帧或短暂暂停。
                // 我们已经在 enforceSceneForegroundState 中按需处理。
                return;
            }
        }
    }
    %orig;
}

- (void)updateSettings:(id)arg1 withTransitionContext:(id)arg2 completion:(id)arg3 {
    CV3RecordSceneForegroundState((FBScene *)self, arg1, @"updateSettingsCompletion");

    if (floatingWindows) {
        for (CV3FloatingAppWindow *win in floatingWindows) {
            if (CV3IdentifierContainsExactBundleID(self.identifier, win.bundleID) && !win.isClosing) {
                CV3LogToFile(@"[Strict] trace=%@ phase=fbscene.intercept.entry api=updateSettingsCompletion transition=%@ incoming={%@} expanded={%@}",
                             win.coldLaunchTraceID, arg2 ?: @"nil", CV3SceneSettingsFingerprint(arg1),
                             CV3DiagnosticObjectFingerprint(arg1));
                if (win.isStashed) {
                    CV3LogToFile(@"[Strict] trace=%@ phase=fbscene.intercept.passThrough.stashed api=completion outgoing={%@}",
                                 win.coldLaunchTraceID, CV3SceneSettingsFingerprint(arg1));
                    %orig(arg1, arg2, arg3);
                    return;
                }

                id mutableSettings = [arg1 mutableCopy];
                BOOL modified = [win applyForegroundSovereigntyToSettings:mutableSettings
                                                         clearDeactivation:YES
                                                               forceLayout:NO];

                if (modified) {
                    if (CV3ShouldRewriteSceneSettings((FBScene *)self, win.bundleID, mutableSettings)) {
                        CV3LogToFile(@"[Warning][PlaybackTrace] source=SpringBoard event=FBSceneSettingsRewrittenWithCompletion bundle=%@ transition=%@",
                                     win.bundleID, arg2 ? @"YES" : @"NO");
                        CV3LogToFile(@"[FBScene] 捕捉到 Settings 更新请求 (带 completion): %@", win.bundleID);
                    }
                    CV3LogToFile(@"[Strict] trace=%@ phase=fbscene.intercept.forward.rewritten api=completion outgoing={%@}",
                                 win.coldLaunchTraceID, CV3SceneSettingsFingerprint(mutableSettings));
                    %orig(mutableSettings, arg2, arg3);
                } else {
                    CV3LogToFile(@"[Strict] trace=%@ phase=fbscene.intercept.forward.unchanged api=completion outgoing={%@}",
                                 win.coldLaunchTraceID, CV3SceneSettingsFingerprint(arg1));
                    %orig(arg1, arg2, arg3);
                }
                [win recordStrictSplitTrace:@"fbscene.intercept.returned" details:@"api=updateSettingsCompletion"];
                
                // [Anti-Ghosting] Detect transition and clear stale frames
                if (arg2 != nil && !CV3WorkspaceTransitionActive) {
                    [win performSelectorOnMainThread:@selector(handleTransitionGhosting) withObject:nil waitUntilDone:NO];
                }
                // [Optimization] 移除此处的 refreshHostViewPresentation，理由同上。
                return;
            }
        }
    }
    %orig;
}

- (void)_setContentState:(NSInteger)arg1 {
    CV3RecordSceneContentState((FBScene *)self, arg1, @"_setContentState");

    if (floatingWindows) {
        for (CV3FloatingAppWindow *win in floatingWindows) {
            if (CV3IdentifierContainsExactBundleID(self.identifier, win.bundleID) && !win.isClosing) {
                // 如果窗口被 Stash (侧边隐藏)，允许场景进入非 Ready 状态，配合系统节能
                if (win.isStashed) {
                    %orig(arg1);
                    return;
                }
                if (arg1 != 2) {
                    if (CV3ShouldForceSceneContentState((FBScene *)self, win.bundleID)) {
                        CV3LogToFile(@"[Warning][PlaybackTrace] source=SpringBoard event=FBSceneContentStateDowngrade bundle=%@ requested=%ld forced=2",
                                     win.bundleID, (long)arg1);
                        CV3LogToFile(@"[FBScene] 拦截到 contentState 降级 -> %ld，强制恢复为 2: %@", (long)arg1, win.bundleID);
                    }
                    arg1 = 2;
                }
                break;
            }
        }
    }
    %orig(arg1);
}

- (BOOL)isInterrupted {
    if (floatingWindows) {
        for (CV3FloatingAppWindow *win in floatingWindows) {
            if (CV3IdentifierContainsExactBundleID(self.identifier, win.bundleID) && !win.isClosing) {
                if (win.isStashed) return %orig;
                return NO; // 核心：强制报告未中断，防止视频播放因手势判定而暂停
            }
        }
    }
    return %orig;
}
%end

%hook SBSystemGestureManager
- (void)addGestureRecognizer:(id)arg1 withType:(unsigned long long)arg2 {
    // 如果系统（Siri）尝试注册 112 槽位，并且当前有我们的手势占用，则主动让出槽位避免崩溃

    if (arg2 == 112 && sharedWindow && sharedWindow.systemEdgePan && arg1 != sharedWindow.systemEdgePan) {
        @try {
            [self removeGestureRecognizer:sharedWindow.systemEdgePan];
        } @catch (NSException *e) {}
    }
    %orig;
}

- (void)removeGestureRecognizer:(id)arg1 {
    %orig;
    // 如果系统移除了某个手势，我们尝试重新夺回 112 槽位
    if (sharedWindow && sharedWindow.systemEdgePan && arg1 != sharedWindow.systemEdgePan) {
        dispatch_async(dispatch_get_main_queue(), ^{
            @try {
                [[%c(SBSystemGestureManager) mainDisplayManager] addGestureRecognizer:sharedWindow.systemEdgePan withType:112];
            } @catch (NSException *e) {}
        });
    }
}
%end

%hook UIScenePresentationContext
- (void)setAppearanceStyle:(NSUInteger)arg1 {
    %orig(arg1);
    if (arg1 == 2 && !CV3SuppressPresentationContextFanout && !CV3WorkspaceTransitionActive) { // 2 = Interactive/Real-time
        for (CV3FloatingAppWindow *win in floatingWindows) {
            if (!win.isClosing) [win performSelectorOnMainThread:@selector(refreshHostViewPresentation) withObject:nil waitUntilDone:NO];
        }
    }
}
%end

static BOOL CV3HasVisibleHostedWindow(void) {
    for (CV3FloatingAppWindow *window in [floatingWindows copy]) {
        if ([window isKindOfClass:[CV3FloatingAppWindow class]] &&
            !window.isClosing && !window.isStashed && !window.hidden) {
            return YES;
        }
    }
    return NO;
}

static BOOL CV3ShouldSuppressHostedCameraRouteChangeHUD(id event) {
    NSString *reason = CV3VolumeChangeReason(event);
    if ([reason caseInsensitiveCompare:@"RouteChange"] != NSOrderedSame) return NO;
    CFTimeInterval elapsed = CACurrentMediaTime() - CV3LastHostedCameraAccessTime;
    return elapsed >= 0 && elapsed <= 3.0 && CV3HasVisibleHostedWindow();
}

%hook SBVolumeControl
- (void)_effectiveVolumeChanged:(id)event {
    BOOL previousSuppression = CV3SuppressRouteChangeVolumeHUD;
    BOOL suppress = CV3ShouldSuppressHostedCameraRouteChangeHUD(event);
    CV3SuppressRouteChangeVolumeHUD = previousSuppression || suppress;
    @try {
        %orig(event);
    } @finally {
        CV3SuppressRouteChangeVolumeHUD = previousSuppression;
    }
}

- (void)_presentVolumeHUDWithVolume:(float)volume {
    if (CV3SuppressRouteChangeVolumeHUD) {
        CV3LogToFile(@"[VolumeHUD] suppressed hosted-camera route-change HUD volume=%.3f", volume);
        return;
    }
    %orig(volume);
}
%end

%ctor {
    @autoreleasepool {
        CV3WriteBootstrapProbe();
        (void)CV3LogQueue();
        CV3LogToFile(@"[ChevronProbe] springboard.ctor pid=%d", NSProcessInfo.processInfo.processIdentifier);
        CV3LogVideoFullscreen([NSString stringWithFormat:@"[DEBUG-VIDEOFULLSCREEN] phase=logger.ready version=%@", CV3_VERSION_STRING]);
        CV3LogHomeBarVisibility([NSString stringWithFormat:@"[HomeBarTrace] phase=logger.ready version=%@", CV3_VERSION_STRING]);
        CV3LogWindowOrientation([NSString stringWithFormat:@"[WindowOrientationTrace] phase=logger.ready version=%@", CV3_VERSION_STRING]);
        CV3LogToFile([NSString stringWithFormat:@"[NotificationSplit] phase=logger.ready version=%@ path=/rootfs/var/mobile/Library/Logs/ChevronV3_Logs.txt", CV3_VERSION_STRING]);
        CV3SetCameraGrantMutationLogger(CV3LogCameraGrantMutation);
        CV3ResetCameraForegroundGrants();
        CV3PublishHostGeneration();
        CV3RegisterVideoOrientationBridge();
        CV3RegisterPlaybackTraceBridge();
        CV3RegisterHostedInteractionBridge();
        CV3RegisterSimulatedNotificationBridge();
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(), NULL,
            CV3HostedCameraAccessGranted,
            (__bridge CFStringRef)CV3HostedCameraAccessGrantedNotification,
            NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
        %init;
    }
}
