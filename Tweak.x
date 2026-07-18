#import <UIKit/UIKit.h>
#import <CoreMotion/CoreMotion.h>
#import <QuartzCore/QuartzCore.h>
#import <AudioToolbox/AudioToolbox.h>
#import <objc/runtime.h>
#import <notify.h>
#import "CV3PrivateAPI.h"
#import "CV3CoreSupport.h"
#include <sys/stat.h>
#include <signal.h>

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
@end

@interface SBIcon : NSObject
- (void)launchFromLocation:(NSInteger)location context:(id)context;
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
@property (assign, nonatomic) NSInteger interruptionPolicy; // 0: None, 1: Suppress, 2: Defer
@end

@interface UIMutableApplicationSceneSettings : FBSMutableSceneSettings
@property (assign, nonatomic) UIEdgeInsets safeAreaInsetsPortrait;
@property (assign, nonatomic) UIEdgeInsets safeAreaInsetsLandscapeLeft;
@property (assign, nonatomic) UIEdgeInsets safeAreaInsetsLandscapeRight;
@property (assign, nonatomic) UIEdgeInsets safeAreaInsetsPortraitUpsideDown;
@property (assign, nonatomic) NSUInteger deactivationReasons;
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
@end

@interface RBSAssertion : NSObject
- (instancetype)initWithExplanation:(NSString *)arg1 target:(RBSTarget *)arg2 attributes:(NSArray *)arg3;
- (BOOL)acquireWithError:(out NSError **)arg1;
- (void)invalidate;
@end

@interface RBSDomainAttribute : NSObject
+ (instancetype)attributeWithDomain:(NSString *)arg1 name:(NSString *)arg2;
@end

@interface FBProcessTerminationContext : NSObject
@property (assign, nonatomic) unsigned long long exceptionCode;
@property (copy, nonatomic) NSString *explanation;
@property (assign, nonatomic) BOOL reportTermination;
@end

@interface FBProcess : NSObject
@property (nonatomic, readonly) int pid;
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
@property (nonatomic, strong) id sbIcon; 
@property (nonatomic, copy) NSString *pinyinInitial;
@property (nonatomic, copy) NSString *category; 
@property (nonatomic, assign) BOOL isPinned;
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
    CGFloat highlightAlpha;
    // 物理引擎参数
    CGFloat parallaxPanelFactor;
    CGFloat parallaxDecoFactor;
    CGFloat lerpFactor;
    CGFloat hapticThreshold;
    CGFloat tiltMaxAngle;
    CGFloat scrollTiltFactor;
    CGFloat momentumDamping;
    CGFloat maxStretch;
    CGFloat stretchDamping;
    // 动画参数
    CGFloat durationShort;
    CGFloat durationMedium;
    CGFloat durationLong;
    CGFloat springDamping;
    CGFloat springVelocity;
    // 窗口层级
    CGFloat maxBound;
    CGFloat floatingApp;
    CGFloat panel;
    CGFloat background;
    CGFloat keyboard;
    // 布局参数
    CGFloat panelW;
    CGFloat panelH;
    CGFloat triggerHotzoneWidth;
    CGFloat triggerVisualWidth;
    CGFloat triggerBottomOffset;
    CGFloat safeAreaBreath;
    CGFloat cornerRadius;
    CGFloat minHeight;
    CGFloat trafficCapsuleW;
    CGFloat trafficCapsuleH;
    CGFloat trafficDotSize;
    CGFloat windowHandleW;
    CGFloat windowHandleH;
    CGFloat shadowRadiusMask;
    CGFloat shadowOpacityMask;
    CGFloat maskAlpha;
    CGFloat floatingChromeH;
    CGFloat floatingChromeControlSize;
    CGFloat floatingChromeCornerRadius;
    CGFloat resizeHandleHitArea;
    CGFloat resizeHandleWindowExpansion;
    CGFloat trafficLightInactiveGray;
    CGFloat trafficLightInactiveAlpha;
    CGFloat multitaskingMenuFontSize;
    CGFloat multitaskingMenuIconSize;
    CGFloat menuTintR;
    CGFloat menuTintG;
    CGFloat menuTintB;
    CGFloat menuTintA;
    CGFloat menuBtnScale;
    CGFloat menuStartScale;
    CGFloat menuAnimDuration;
    CGFloat menuAnimDamping;
    CGFloat menuParabolicOffset;
    CGFloat menuSpecularAlpha;
    CGFloat transitionParallaxExpand;
    CGFloat transitionParallaxShrink;
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
    .highlightAlpha = 0.35,
    // 物理引擎参数
    .parallaxPanelFactor = 8.0,
    .parallaxDecoFactor = 11.0,
    .lerpFactor = 0.15,
    .hapticThreshold = 0.6,
    .tiltMaxAngle = 0.12,
    .scrollTiltFactor = 0.0015,
    .momentumDamping = 0.92,
    .maxStretch = 0.12,
    .stretchDamping = 3500.0,
    // 动画参数
    .durationShort = 0.15,
    .durationMedium = 0.3,
    .durationLong = 0.5,
    .springDamping = 0.6,
    .springVelocity = 0.8,
    // 窗口层级
    .maxBound = 2100.0,
    .floatingApp = 999.0,
    .panel = 2099.0,
    .background = -1.0,
    .keyboard = 10000.0,
    // 布局参数
    .panelW = 370.0,
    .panelH = 520.0,
    .triggerHotzoneWidth = 50.0,
    .triggerVisualWidth = 20.0,
    .triggerBottomOffset = 100.0,
    .safeAreaBreath = 10.0,
    .cornerRadius = 28.0,
    .minHeight = 300.0,
    .trafficCapsuleW = 64.0,
    .trafficCapsuleH = 24.0,
    .trafficDotSize = 8.0,
    .windowHandleW = 58.0,
    .windowHandleH = 18.0,
    .shadowRadiusMask = 180.0,
    .shadowOpacityMask = 0.85,
    .maskAlpha = 0.18,
    .floatingChromeH = 28.0,
    .floatingChromeControlSize = 12.0,
    .floatingChromeCornerRadius = 18.0,
    .resizeHandleHitArea = 80.0,
    .resizeHandleWindowExpansion = 40.0,
    .trafficLightInactiveGray = 0.78,
    .trafficLightInactiveAlpha = 0.35,
    .multitaskingMenuFontSize = 11.0,
    .multitaskingMenuIconSize = 13.0,
    .menuTintR = 0.0,
    .menuTintG = 0.8,
    .menuTintB = 1.0,
    .menuTintA = 0.02,
    .menuBtnScale = 0.94,
    .menuStartScale = 0.15,
    .menuAnimDuration = 0.38,
    .menuAnimDamping = 0.72,
    .menuParabolicOffset = 60.0,
    .menuSpecularAlpha = 0.25,
    .transitionParallaxExpand = 0.93,
    .transitionParallaxShrink = 1.05,
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
static const NSTimeInterval kCV3PanelDismissDuration = 0.30;
static const CGFloat kCV3PanelTriggerDistance = 45.0;

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
@property (nonatomic, strong) UIView *pinnedIndicator; 
@property (nonatomic, assign) BOOL isFirstResult; // 新增：是否为搜索首项
@property (nonatomic, copy) NSString *representedBundleId;
- (void)configureWithInfo:(CV3AppInfo *)info searchText:(NSString *)searchText isFirst:(BOOL)isFirst protectionState:(CV3AppPanelProtectionState)protectionState;
- (void)setIconImage:(UIImage *)image forBundleId:(NSString *)bundleId;
- (void)startBreathing;
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

        self.nameLabel = [[UILabel alloc] initWithFrame:CGRectMake(4, iconSize + 14, frame.size.width - 8, 28)];
        self.nameLabel.textColor = [UIColor labelColor];
        self.nameLabel.font = [UIFont systemFontOfSize:10.0 weight:UIFontWeightMedium];
        self.nameLabel.textAlignment = NSTextAlignmentCenter;
        self.nameLabel.numberOfLines = 2;
        [self.contentView addSubview:self.nameLabel];
        
        // 性能优化：在 Cell 初始化时启动动画，而不是在滚动 configure 时重复添加
        [self startBreathing];
    }
    return self;
}

- (void)prepareForReuse {
    [super prepareForReuse];
    self.representedBundleId = nil;
    self.iconView.image = nil;
}

- (void)configureWithInfo:(CV3AppInfo *)info searchText:(NSString *)searchText isFirst:(BOOL)isFirst protectionState:(CV3AppPanelProtectionState)protectionState {
    self.representedBundleId = info.bundleId;
    self.iconView.image = info.icon;
    self.pinnedIndicator.hidden = !info.isPinned;
    self.isFirstResult = isFirst;
    if (info.isPinned) [self.iconView bringSubviewToFront:self.pinnedIndicator];

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
    self.iconView.alpha = isProtected ? 0.62 : 1.0;

    if (searchText && searchText.length > 0) {
        NSMutableAttributedString *as = [[NSMutableAttributedString alloc] initWithString:info.name attributes:@{NSForegroundColorAttributeName: isProtected ? protectionColor : [UIColor labelColor]}];
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
        self.nameLabel.attributedText = nil;
        self.nameLabel.text = info.name;
        self.nameLabel.textColor = isProtected ? protectionColor : [UIColor labelColor];
        self.iconView.layer.borderWidth = isProtected ? 1.5 : 0.0;
        self.iconView.layer.borderColor = isProtected ? [protectionColor colorWithAlphaComponent:0.9].CGColor : [UIColor clearColor].CGColor;
    }
}

- (void)setIconImage:(UIImage *)image forBundleId:(NSString *)bundleId {
    if (bundleId.length == 0 || ![self.representedBundleId isEqualToString:bundleId]) return;
    self.iconView.image = image;
}

- (void)startBreathing {
    [self.contentView.layer removeAnimationForKey:@"breathing"];
    [self.iconBackdrop.layer removeAnimationForKey:@"breathing"];
    [self.iconView.layer removeAnimationForKey:@"breathing"];

    CGFloat lift = 7.0 + (arc4random_uniform(18) / 10.0);
    CGFloat duration = 6.8 + (arc4random_uniform(18) / 10.0);
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

    [self.iconBackdrop.layer addAnimation:makeFloatGroup() forKey:@"breathing"];
    [self.iconView.layer addAnimation:makeFloatGroup() forKey:@"breathing"];
}
@end

#pragma mark - Root VC
#import <UIKit/UIKit.h> // Explicitly import UIKit to ensure visibility of UIWindowScene

@interface CV3RootViewController : UIViewController
@end

static void CV3LogToFile(NSString *format, ...) {
    va_list args;
    va_start(args, format);
    NSString *message = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);

    // [Geek Advice] Log Leveling: Only log critical messages in Release mode
#ifndef DEBUG
    BOOL isCritical = [message containsString:@"[Lifecycle]"] || 
                     [message containsString:@"[Recovery]"] || 
                     [message containsString:@"[Orientation]"] || 
                     [message containsString:@"[Workspace]"] ||
                     [message containsString:@"[Scene]"] ||
                     [message containsString:@"[Error]"] ||
                     [message containsString:@"[Warning]"];
    if (!isCritical) return;
#endif

    // 立即输出到系统日志，作为第一层保障
    NSLog(@"[ChevronV3] %@", message);

    dispatch_async(CV3LogQueue(), ^{
        @try {
            NSFileManager *fm = [NSFileManager defaultManager];
            NSString *logPath = @"/var/mobile/Documents/ChevronV3_Logs.txt";
            NSString *parentDir = [logPath stringByDeletingLastPathComponent];
            
            // 确保父目录存在
            if (![fm fileExistsAtPath:parentDir]) {
                [fm createDirectoryAtPath:parentDir withIntermediateDirectories:YES attributes:nil error:nil];
            }

            if (![fm fileExistsAtPath:logPath]) {
                [fm createFileAtPath:logPath contents:nil attributes:nil];
            } else {
                // 日志轮转 (Log Rotation) - 限制在 10MB 以内，支持更详尽的追踪
                unsigned long long fileSize = [[fm attributesOfItemAtPath:logPath error:nil] fileSize];
                if (fileSize > 10 * 1024 * 1024) {
                    [fm removeItemAtPath:logPath error:nil];
                    [fm createFileAtPath:logPath contents:nil attributes:nil];
                }
            }
            
            NSFileHandle *handle = [NSFileHandle fileHandleForWritingAtPath:logPath];
            if (handle) {
                [handle seekToEndOfFile];
                NSString *timestamp = [NSDateFormatter localizedStringFromDate:[NSDate date] dateStyle:NSDateFormatterShortStyle timeStyle:NSDateFormatterMediumStyle];
                NSString *finalLog = [NSString stringWithFormat:@"[%@] %@\n", timestamp, message];
                [handle writeData:[finalLog dataUsingEncoding:NSUTF8StringEncoding]];
                [handle closeFile];
            }
        } @catch (NSException *e) {}
    });
}

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
    CGContextSetInterpolationQuality(ctx, kCGInterpolationMedium);
    [image drawInRect:(CGRect){.size = size} blendMode:kCGBlendModeCopy alpha:1];
    uint8_t *data = (uint8_t *)CGBitmapContextGetData(ctx);
    UIColor *color = [UIColor colorWithRed:data[0]/255.0 green:data[1]/255.0 blue:data[2]/255.0 alpha:1.0];
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
    surface.layer.borderColor = [[UIColor whiteColor] colorWithAlphaComponent:(0.14 + intensity * 0.12 + (selected ? 0.08 : 0.0))].CGColor;

    UIView *resolvedTintHost = tintHost ?: surface;
    resolvedTintHost.backgroundColor = [[UIColor whiteColor] colorWithAlphaComponent:(0.025 + intensity * 0.055 + (selected ? 0.025 : 0.0))];

    CAGradientLayer *layer = highlightLayer ?: CV3EnsureGlassAccentLayer(resolvedTintHost);
    if (layer) {
        CGRect layerBounds = resolvedTintHost.bounds;
        if (CGRectIsEmpty(layerBounds)) layerBounds = surface.bounds;
        layer.frame = layerBounds;
        layer.cornerRadius = cornerRadius;
        layer.startPoint = CGPointMake(0.0, 0.0);
        layer.endPoint = CGPointMake(1.0, 1.0);
        layer.colors = @[
            (id)[[UIColor whiteColor] colorWithAlphaComponent:(0.12 + intensity * 0.18 + (selected ? 0.06 : 0.0))].CGColor,
            (id)[[UIColor whiteColor] colorWithAlphaComponent:(0.025 + intensity * 0.055)].CGColor,
            (id)[[UIColor blackColor] colorWithAlphaComponent:(0.035 + intensity * 0.055)].CGColor
        ];
        layer.locations = @[@0.0, @0.52, @1.0];
    }
}

#pragma mark - Floating App Window (MilkyWay2-style)
static NSString * const CV3FloatingWindowsDidChangeNotification = @"CV3FloatingWindowsDidChangeNotification";
static NSMutableArray *floatingWindows = nil;
static const char *CV3VideoOrientationNotification = "com.xu.chevronv3.video-orientation";
static int CV3VideoOrientationNotificationToken = -1;
static UIInterfaceOrientation CV3LastTrustedInterfaceOrientation = UIInterfaceOrientationPortrait;
static BOOL CV3SuppressPresentationContextFanout = NO;
static BOOL CV3WorkspaceTransitionActive = NO;
static NSUInteger CV3WorkspaceTransitionProtectionToken = 0;

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

static uint64_t CV3StableBundleHash(NSString *bundleID) {
    const unsigned char *bytes = (const unsigned char *)bundleID.UTF8String;
    uint64_t hash = 1469598103934665603ULL;
    if (!bytes) return hash;
    while (*bytes) {
        hash ^= (uint64_t)*bytes++;
        hash *= 1099511628211ULL;
    }
    return hash & 0x00FFFFFFFFFFFFFFULL;
}

__attribute__((unused)) static UIInterfaceOrientation CV3InterfaceOrientationFromDevice(void) {
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

__attribute__((unused)) static UIDeviceOrientation CV3DeviceOrientationFromInterface(UIInterfaceOrientation orientation) {
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

@interface CV3FloatingAppWindow : UIWindow <UIGestureRecognizerDelegate>
@property (nonatomic, copy) NSString *bundleID;
@property (nonatomic, strong) UIVisualEffectView *glassBackdrop; // New: Fluid background
@property (nonatomic, strong) UIView *appContentWrapper;
@property (nonatomic, strong) UIView *rootTransformContainer;
@property (nonatomic, strong) UIView *clippingContainer; 
@property (nonatomic, strong) UIView *hostContainerProxy;
@property (nonatomic, strong) UIView *hostView;
@property (nonatomic, copy) NSString *sceneHostingRequester;
@property (nonatomic, strong) CV3HostedSceneSession *hostedSession;
@property (nonatomic, strong) UIView *windowChromeView;
@property (nonatomic, strong) UIView *chromeDragHandle;
@property (nonatomic, strong) UIButton *chromeCloseButton;
@property (nonatomic, strong) UIButton *chromeMinimizeButton;
@property (nonatomic, strong) UIButton *chromeModeButton;
@property (nonatomic, strong) UIVisualEffectView *multitaskingMenuView;
@property (nonatomic, assign) BOOL chromeControlsExpanded;
@property (nonatomic, strong) NSTimer *chromeCollapseTimer;
@property (nonatomic, strong) UIView *homeBarView;
@property (nonatomic, strong) UIVisualEffectView *homeBarBlurView;
@property (nonatomic, strong) CAGradientLayer *homeBarGlowLayer;
@property (nonatomic, assign) NSInteger homeBarPlacement;
@property (nonatomic, assign) NSInteger homeBarResizeStartPlacement;
@property (nonatomic, assign) CGPoint homeBarResizeAxis;
@property (nonatomic, assign) CGPoint homeBarCommandAxis;
@property (nonatomic, assign) NSInteger homeBarPanMode;
@property (nonatomic, assign) CGFloat homeBarCommandProjection;
@property (nonatomic, strong) UIView *resizeHandle;
@property (nonatomic, strong) CAShapeLayer *resizeHandleLayer;
@property (nonatomic, assign) CGSize resizeHandleVisualSize;
@property (nonatomic, strong) UIPanGestureRecognizer *windowResizePan;
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
@property (nonatomic, strong) UIVisualEffectView *snapPreviewView;
@property (nonatomic, strong) CALayer *innerGlowLayer;
@property (nonatomic, strong) CALayer *cyanLayer;
@property (nonatomic, strong) CALayer *magentaLayer;
@property (nonatomic, assign) CGRect lastTargetSnapFrame;
@property (nonatomic, strong) UIColor *adaptiveAppColor;

// Pro Enhancements
@property (nonatomic, assign) BOOL isFocused;
@property (nonatomic, assign) BOOL isClosing;
@property (nonatomic, assign) BOOL isInLayout;
@property (nonatomic, assign) BOOL isMovingWindow;
@property (nonatomic, assign) NSTimeInterval moveSceneSyncSuppressedUntil;
@property (nonatomic, assign) CGPoint lastVelocity;
@property (nonatomic, strong) UIView *crystalPreviewContainer;
@property (nonatomic, strong) UIView *splashView;
@property (nonatomic, strong) UIImageView *largeSplashIcon;
@property (nonatomic, assign) UIInterfaceOrientation targetOrientation;
@property (nonatomic, assign) UIInterfaceOrientation hostedContentOrientation;
@property (nonatomic, assign) UIInterfaceOrientation lastLayoutOrientation;
@property (nonatomic, assign) CGAffineTransform baseRotationTransform;
@property (nonatomic, assign) CGRect preFullscreenFrame;
@property (nonatomic, assign) CGRect preCompactFrame;
@property (nonatomic, assign) BOOL isFullscreenMode;
@property (nonatomic, assign) BOOL isCompactMode;
@property (nonatomic, strong) UIView *liveResizeSnapshotView;
@property (nonatomic, strong) RBSAssertion *rbsAssertion; 
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
@property (nonatomic, assign) BOOL isLiveResizing;
@property (nonatomic, strong) CAGradientLayer *specularHighlight;
@property (nonatomic, strong) CADisplayLink *liquidDisplayLink;
@property (nonatomic, assign) BOOL hasCapturedBaseline;
@property (nonatomic, assign) CGFloat baseRoll;
@property (nonatomic, assign) CGFloat basePitch;
@property (nonatomic, assign) NSTimeInterval collisionReleaseTime;
@property (nonatomic, assign) CGFloat collisionReleaseValue;
@property (nonatomic, assign) NSInteger collisionReleaseAxis;
@property (nonatomic, strong) UIImage *stashedRestoreSnapshotImage;
@property (nonatomic, assign) UIInterfaceOrientation stashedRestoreSnapshotOrientation;

+ (CMMotionManager *)sharedMotionManager;
- (void)startLiquidMotion;
- (void)stopLiquidMotion;
- (instancetype)initWithBundleID:(NSString *)bundleID center:(CGPoint)center windowScene:(UIWindowScene *)windowScene;
- (void)updateSovereigntyAssertion;
- (void)menuBtnTouchDown:(UIButton *)sender;
- (void)menuBtnTouchUp:(UIButton *)sender;
- (void)triggerCollisionImpulse;
- (void)updateAdaptiveColor;
- (void)setWindowFocused:(BOOL)focused;
- (void)promoteFloatingWindowInZOrder;
- (void)animateFocusShadow:(BOOL)focused;
- (void)restoreFromStash;
- (void)handleHideAction;
- (void)enforceSceneForegroundState;
- (void)attemptToHostSceneWithRetries:(int)retries delay:(double)delay;
- (void)setTargetOrientation:(UIInterfaceOrientation)orientation;
- (void)applyCurrentTransformWithScale:(CGFloat)scale;
- (void)handleTransitionGhosting;
- (void)refreshHostViewPresentation;
- (UIView *)hostViewForScene:(FBScene *)scene;
- (void)disableHostingForCurrentScene;
- (BOOL)hostViewHasRenderableContent;
- (void)finishHostingWhenRenderableWithRetries:(NSInteger)retries;
- (void)applyStashedGrabberOrientation;
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
- (void)layoutFloatingHomeBarForBounds:(CGRect)bounds;
- (NSInteger)preferredHomeBarPlacementForScreenFrame:(CGRect)frame;
- (CGRect)orientedDisplayBoundsForCurrentOrientation;
- (void)homeBarResizeLimitsForAspect:(CGFloat)aspect minWidth:(CGFloat *)minWidth maxWidth:(CGFloat *)maxWidth;
- (CGRect)constrainedFloatingFrameForSize:(CGSize)size preferredCenter:(CGPoint)center;
- (void)startHomeBarResizeSessionIfNeeded;
- (void)handleHomeBarTap:(UITapGestureRecognizer *)gesture;
- (void)handleHomeBarResizePan:(UIPanGestureRecognizer *)gesture;
- (void)activateHostedAppFullscreenAndClose;
- (void)dismissMultitaskingMenu;
- (void)ensureLaunchSplashVisible;
- (void)loadAppScene;
- (UIEdgeInsets)currentSafeAreaInsets;
- (void)dismissLaunchSplashAnimated;
- (void)enforcePortraitWindowGeometry;
- (void)applySceneRotationContext:(CV3SceneRotationContext)context force:(BOOL)force;
- (void)applyInterfaceOrientation:(UIInterfaceOrientation)orientation force:(BOOL)force;
- (void)applyTrustedOrientationNow;
- (CGRect)visiblePortraitContentFrame;
- (CGRect)currentHostedSceneBounds;
- (BOOL)applyHostedSceneLayoutToSettings:(id)settings force:(BOOL)force;
- (BOOL)syncHostedSceneLayoutForce:(BOOL)force;
- (void)applyHostedContentOrientation:(UIInterfaceOrientation)orientation;
- (BOOL)applyForegroundSovereigntyToSettings:(id)settings clearDeactivation:(BOOL)clearDeactivation forceLayout:(BOOL)forceLayout;
- (void)stabilizeForegroundForWorkspaceTransition:(NSString *)reason;
@end

static void CV3PostHostedStateValue(NSString *bundleID, uint64_t state) {
    if (bundleID.length == 0) return;

    NSString *notificationName = [NSString stringWithFormat:@"com.xu.chevronv3.hosted.%014llx",
                                  CV3StableBundleHash(bundleID)];
    int token = -1;
    if (notify_register_check(notificationName.UTF8String, &token) != NOTIFY_STATUS_OK) return;
    notify_set_state(token, state);
    notify_post(notificationName.UTF8String);
    notify_cancel(token);
}

static void CV3PostHostedState(NSString *bundleID, BOOL hosted) {
    CV3PostHostedStateValue(bundleID, hosted ? 1 : 0);
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

// --- Custom iPadOS Multitasking Capsule with Touch Redirection ---
@interface CV3TrafficCapsule : UIView
@property (nonatomic, strong) UIVisualEffectView *blurView;
@end

@implementation CV3TrafficCapsule
- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [UIColor clearColor];
        self.clipsToBounds = NO; // 不裁切超出的物理按钮热区
        
        UIBlurEffect *blurEffect = [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemThinMaterial];
        self.blurView = [[UIVisualEffectView alloc] initWithEffect:blurEffect];
        self.blurView.frame = self.bounds;
        self.blurView.layer.cornerRadius = frame.size.height / 2.0;
        self.blurView.layer.masksToBounds = YES;
        self.blurView.layer.borderColor = [[UIColor labelColor] colorWithAlphaComponent:0.08].CGColor;
        self.blurView.layer.borderWidth = 0.5;
        self.blurView.userInteractionEnabled = NO; // 极其重要：不阻拦子按钮的事件流
        [self addSubview:self.blurView];
    }
    return self;
}

- (BOOL)pointInside:(CGPoint)point withEvent:(UIEvent *)event {
    // 隐形判定盾牌：判定范围向外扩充 15.0 pt，提升边缘盲按响应率
    CGRect hitFrame = CGRectInset(self.bounds, -15.0, -15.0);
    return CGRectContainsPoint(hitFrame, point);
}

- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    if (self.hidden || !self.userInteractionEnabled || self.alpha < 0.01) return nil;
    
    // 如果在扩大的判定区域内，但点偏了没直接命中按钮，则根据横坐标区间，智能转发给对应的子按钮
    if ([self pointInside:point withEvent:event]) {
        UIView *hit = [super hitTest:point withEvent:event];
        if (hit && [hit isKindOfClass:[UIButton class]]) {
            return hit;
        }
        
        // 坐标重映射：根据局部的 X 坐标分配到 3 等分区间 (0 = 左, 1 = 中, 2 = 右)
        CGFloat x = point.x;
        x = MIN(MAX(0.0, x), self.bounds.size.width);
        NSInteger index = (NSInteger)(x / (self.bounds.size.width / 3.0));
        index = MIN(2, MAX(0, index));
        
        // 查找 tag 匹配 of 子按钮并重定向触控
        for (UIView *sub in self.subviews) {
            if ([sub isKindOfClass:[UIButton class]] && sub.tag == index) {
                return sub;
            }
        }
    }
    return [super hitTest:point withEvent:event];
}
@end


static void CV3UpdateFloatingBackdrop(UIWindowScene *preferredScene) {
    (void)preferredScene;
}

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

#import "CV3FloatingAppWindow.inc"

static void CV3RegisterVideoOrientationBridge(void) {
    if (CV3VideoOrientationNotificationToken >= 0) return;

    int status = notify_register_dispatch(CV3VideoOrientationNotification,
                                          &CV3VideoOrientationNotificationToken,
                                          dispatch_get_main_queue(),
                                          ^(int token) {
        uint64_t state = 0;
        if (notify_get_state(token, &state) != NOTIFY_STATUS_OK) return;

        UIInterfaceOrientation orientation = (UIInterfaceOrientation)((state >> 56) & 0xFFULL);
        uint64_t bundleHash = state & 0x00FFFFFFFFFFFFFFULL;
        if (!CV3IsValidInterfaceOrientation(orientation)) return;

        for (CV3FloatingAppWindow *window in [floatingWindows copy]) {
            if (![window isKindOfClass:[CV3FloatingAppWindow class]] || window.isClosing) continue;
            if (CV3StableBundleHash(window.bundleID) != bundleHash) continue;

            [window applyHostedContentOrientation:orientation];
            return;
        }
    });

    if (status != NOTIFY_STATUS_OK) {
        CV3VideoOrientationNotificationToken = -1;
        CV3LogToFile(@"[Error] VideoBridge Darwin 通知注册失败: %d", status);
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
    CV3SetClientWorkspaceTransitionShield(YES);
    CV3StabilizeFloatingWindowsForWorkspaceTransition(reason ?: @"Begin");

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (token != CV3WorkspaceTransitionProtectionToken) return;
        CV3WorkspaceTransitionActive = NO;
        CV3SetClientWorkspaceTransitionShield(NO);
        CV3StabilizeFloatingWindowsForWorkspaceTransition(@"ProtectionTimeout");
        CV3LogToFile(@"[Continuity] Workspace 转场保护超时收尾");
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

%hook SBIcon
- (void)launchFromLocation:(NSInteger)location context:(id)context {
    CV3BeginWorkspaceTransitionProtection(@"IconLaunchBegan");
    %orig(location, context);
}
%end

static void CV3EndWorkspaceTransitionProtection(NSString *reason) {
    if (!floatingWindows || floatingWindows.count == 0) return;

    CV3WorkspaceTransitionProtectionToken++;
    NSUInteger token = CV3WorkspaceTransitionProtectionToken;

    CV3StabilizeFloatingWindowsForWorkspaceTransition(reason ?: @"End");

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.35 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (token != CV3WorkspaceTransitionProtectionToken) return;
        CV3WorkspaceTransitionActive = NO;
        CV3SetClientWorkspaceTransitionShield(NO);
        CV3StabilizeFloatingWindowsForWorkspaceTransition(@"ProtectionEnd");
        CV3LogToFile(@"[Continuity] 结束 Workspace 转场保护: %@", reason ?: @"Unknown");
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
@property (nonatomic, assign) BOOL isPanelShowing;
@property (nonatomic, assign) BOOL isAnimating;
@property (nonatomic, assign) BOOL isProcessing; 
@property (nonatomic, assign) BOOL launchDebounce;
@property (nonatomic, assign) BOOL needsFullReload; 
@property (nonatomic, assign) BOOL isSuppressedBySystem; 
@property (nonatomic, strong) NSMutableArray<CV3AppInfo *> *apps;

@property (nonatomic, strong) UIImpactFeedbackGenerator *feedback;
@property (nonatomic, strong) UISelectionFeedbackGenerator *selectionFeedback;
@property (nonatomic, strong) NSTimer *heartbeatTimer;
@property (nonatomic, strong) NSTimer *panelStateRefreshTimer;
@property (nonatomic, assign) BOOL isKeyboardVisible; 
@property (nonatomic, assign) BOOL observersRegistered;
@property (nonatomic, assign) BOOL hasBeenMoved;
@property (nonatomic, strong) UIView *resizingHandle;
@property (nonatomic, strong) CAShapeLayer *resizingHandleLayer; 
@property (nonatomic, strong) UIView *trafficCapsule;
@property (nonatomic, strong) NSArray<UIView *> *trafficDots;
@property (nonatomic, strong) UITextField *searchField;
@property (nonatomic, strong) NSMutableArray<CV3AppInfo *> *filteredApps;
@property (nonatomic, strong) NSArray<CV3AppInfo *> *recentlyUsedApps; 
@property (nonatomic, strong) NSMutableSet *pinnedBundleIDs; 
@property (nonatomic, strong) UILabel *noResultsLabel;
@property (nonatomic, assign) NSUInteger appLoadGeneration;
@property (nonatomic, assign) CGFloat lastHapticX;
@property (nonatomic, strong) UIScreenEdgePanGestureRecognizer *systemEdgePan;
@property (nonatomic, strong) CAGradientLayer *triggerPreviewLayer;
@property (nonatomic, assign) UIInterfaceOrientation targetOrientation;
@property (nonatomic, assign) CGPoint lastTriggerPoint;
@property (nonatomic, assign) CGAffineTransform panelPresentationStartTransform;
@property (nonatomic, assign) CGAffineTransform appPanelPresentationStartTransform;
@property (nonatomic, strong) CAShapeLayer *searchBackground;
@property (nonatomic, strong) UIScrollView *categoryBar; 
@property (nonatomic, copy) NSString *selectedCategory; 
@property (nonatomic, assign) CGAffineTransform baseRotationTransform; 
@property (nonatomic, strong) UIView *contrastBackdrop; 
@property (nonatomic, assign) CGPoint cachedTargetCenter; 

@property (nonatomic, assign) NSInteger interactionCount;


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
@end

static NSCache *cv3IconCache = nil; 
static CV3Window *sharedWindow = nil;
static BOOL CV3PanelWakeGestureActive = NO;
static __weak UIViewController *CV3HomeScreenSpotlightController = nil;
static BOOL CV3SystemHomeSearchTriggered = NO;
static BOOL CV3HomeSearchDismissalInFlight = NO;
// The launcher edge gesture and Home Screen's pull-down Spotlight gesture
// compete for the same touch sequence.  This flag is raised as soon as the
// launcher gesture begins and remains raised until the panel is fully hidden.
static BOOL CV3HomeScreenPullDownSuppressed = NO;
static dispatch_block_t CV3PendingPanelPresentation = nil;
static NSUInteger CV3PanelPresentationGeneration = 0;

static void CV3SetHomeScreenPullDownSuppressed(BOOL suppressed) {
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            CV3SetHomeScreenPullDownSuppressed(suppressed);
        });
        return;
    }

    CV3HomeScreenPullDownSuppressed = suppressed;
    if (!suppressed) return;

    // If Spotlight already started in the same touch sequence, remove its
    // visible controller immediately.  The presentation hooks below prevent
    // it from being presented again while the panel owns the interaction.
    UIViewController *spotlightController = CV3HomeScreenSpotlightController;
    @try {
        if (spotlightController.view.window && !spotlightController.view.hidden) {
            spotlightController.view.hidden = YES;
            spotlightController.view.userInteractionEnabled = NO;
            [spotlightController dismissViewControllerAnimated:NO completion:nil];
        }
    } @catch (NSException *e) {
        CV3LogToFile(@"[Gesture] 屏蔽主屏下拉手势时回收 Spotlight 异常: %@", e);
    }
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

    CV3HomeSearchDismissalInFlight = YES;
    dispatch_block_t completion = ^{
        CV3PresentPendingPanelAfterHomeRestored();
    };

    id iconController = [CV3ClassNamed(@"SBIconController") sharedInstance];
    BOOL requestedDismissal = NO;

    @try {
        SEL selector = NSSelectorFromString(@"dismissSpotlightAnimated:completion:");
        if ([iconController respondsToSelector:selector]) {
            ((void (*)(id, SEL, BOOL, id))objc_msgSend)(iconController, selector, NO, completion);
            requestedDismissal = YES;
        } else {
            selector = NSSelectorFromString(@"dismissSpotlightAnimated:");
            if ([iconController respondsToSelector:selector]) {
                ((void (*)(id, SEL, BOOL))objc_msgSend)(iconController, selector, NO);
                requestedDismissal = YES;
            } else {
                selector = NSSelectorFromString(@"dismissSpotlight");
                if ([iconController respondsToSelector:selector]) {
                    ((void (*)(id, SEL))objc_msgSend)(iconController, selector);
                    requestedDismissal = YES;
                }
            }
        }
    } @catch (NSException *e) {
        requestedDismissal = NO;
    }

    UIViewController *spotlightController = CV3HomeScreenSpotlightController;
    if (!requestedDismissal && spotlightController.presentingViewController) {
        [spotlightController dismissViewControllerAnimated:NO completion:completion];
        requestedDismissal = YES;
    }

    // Older SpringBoard variants expose no dismissal completion. Give their
    // non-animated transition one run-loop window before presenting our panel.
    if (!requestedDismissal || ![iconController respondsToSelector:NSSelectorFromString(@"dismissSpotlightAnimated:completion:")]) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.20 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), completion);
    }
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

%hook SBIconController
- (void)presentSpotlightAnimated:(BOOL)animated completion:(id)completion {
    if (CV3HomeScreenPullDownSuppressed) {
        // Do not let the Home Screen pull-down transition start while the
        // launcher edge gesture/panel owns the touch sequence.
        CV3SystemHomeSearchTriggered = NO;
        if (completion) {
            id completionCopy = [completion copy];
            dispatch_async(dispatch_get_main_queue(), ^{
                ((void (^)(void))completionCopy)();
            });
        }
        return;
    }

    if (!CV3LauncherOwnsHomeSearchTransition()) {
        %orig(animated, completion);
        return;
    }

    CV3SystemHomeSearchTriggered = YES;
    id originalCompletion = [completion copy];
    dispatch_block_t wrappedCompletion = ^{
        if (originalCompletion) ((void (^)(void))originalCompletion)();
        CV3ReturnHomeThenPresentPendingPanel();
    };
    %orig(animated, wrappedCompletion);
}

- (void)presentSpotlightAnimated:(BOOL)animated {
    if (CV3HomeScreenPullDownSuppressed) {
        CV3SystemHomeSearchTriggered = NO;
        return;
    }

    if (CV3LauncherOwnsHomeSearchTransition()) {
        CV3SystemHomeSearchTriggered = YES;
    }
    %orig(animated);
    if (CV3LauncherOwnsHomeSearchTransition()) {
        dispatch_async(dispatch_get_main_queue(), ^{
            CV3ReturnHomeThenPresentPendingPanel();
        });
    }
}
%end

@interface SBHomeScreenSpotlightViewController : UIViewController
@end

%hook SBHomeScreenSpotlightViewController
- (void)viewWillAppear:(BOOL)animated {
    CV3HomeScreenSpotlightController = self;
    if (CV3HomeScreenPullDownSuppressed) {
        self.view.hidden = YES;
        self.view.userInteractionEnabled = NO;
        return;
    }
    self.view.hidden = NO;
    self.view.userInteractionEnabled = YES;
    if (CV3LauncherOwnsHomeSearchTransition()) {
        CV3SystemHomeSearchTriggered = YES;
    }
    %orig(animated);
}

- (void)viewDidAppear:(BOOL)animated {
    %orig(animated);
    CV3HomeScreenSpotlightController = self;
    if (CV3HomeScreenPullDownSuppressed) {
        self.view.hidden = YES;
        self.view.userInteractionEnabled = NO;
        [self dismissViewControllerAnimated:NO completion:nil];
        return;
    }
    if (CV3LauncherOwnsHomeSearchTransition()) {
        CV3SystemHomeSearchTriggered = YES;
        CV3ReturnHomeThenPresentPendingPanel();
    }
}

- (void)viewDidDisappear:(BOOL)animated {
    %orig(animated);
    if (!CV3HomeScreenPullDownSuppressed) {
        self.view.hidden = NO;
        self.view.userInteractionEnabled = YES;
    }
    if (CV3HomeScreenSpotlightController == self) {
        CV3HomeScreenSpotlightController = nil;
    }
    if (CV3PendingPanelPresentation) {
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
    info.sbIcon = source.sbIcon;
    info.pinyinInitial = source.pinyinInitial;
    info.category = source.category;
    info.isPinned = source.isPinned;
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

// Colors will be generated via macro/functions to avoid static constant color allocation issues, but for basic values we can define them as macros or functions.
#define kCV3ColorSystemGreen [UIColor colorWithRed:0.15 green:0.79 blue:0.25 alpha:1.0]
#define kCV3ColorSystemRed   [UIColor colorWithRed:1.00 green:0.37 blue:0.33 alpha:1.0]
#define kCV3ColorSystemYellow [UIColor colorWithRed:1.00 green:0.75 blue:0.18 alpha:1.0]


#pragma mark - Quick Access View (Keyboard Accessory)
@interface CV3QuickAccessView : UIView
@property (nonatomic, strong) NSArray<CV3AppInfo *> *apps;
@property (nonatomic, copy) void (^selectionHandler)(CV3AppInfo *info);
- (instancetype)initWithApps:(NSArray *)apps selectionHandler:(void (^)(CV3AppInfo *))handler;
@end

@implementation CV3QuickAccessView
- (instancetype)initWithApps:(NSArray *)apps selectionHandler:(void (^)(CV3AppInfo *))handler {
    self = [super initWithFrame:CGRectMake(0, 0, [UIScreen mainScreen].bounds.size.width, 60)];
    if (self) {
        self.apps = apps;
        self.selectionHandler = handler;
        self.clipsToBounds = YES;
        
        UIVisualEffectView *blur = [[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemUltraThinMaterial]];
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
        
        UIScrollView *scroll = [[UIScrollView alloc] initWithFrame:self.bounds];
        scroll.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        scroll.showsHorizontalScrollIndicator = NO;
        [self addSubview:scroll];
        
        CGFloat x = 10;
        for (CV3AppInfo *info in apps) {
            UIButton *btn = [UIButton buttonWithType:UIButtonTypeCustom];
            btn.frame = CGRectMake(x, 10, 40, 40);
            btn.layer.cornerRadius = 10;
            btn.clipsToBounds = YES;
            CV3ApplyGlassAccentStyle(btn,
                                     btn,
                                     CV3EnsureGlassAccentLayer(btn),
                                     nil,
                                     10.0,
                                     0.34,
                                     NO);
            [btn setImage:info.icon forState:UIControlStateNormal];
            btn.tag = [apps indexOfObject:info];
            [btn addTarget:self action:@selector(appTapped:) forControlEvents:UIControlEventTouchUpInside];
            [scroll addSubview:btn];
            x += 50;
        }
        scroll.contentSize = CGSizeMake(x, 60);
    }
    return self;
}
- (void)appTapped:(UIButton *)sender {
    if (self.selectionHandler) self.selectionHandler(self.apps[sender.tag]);
}
@end

#import "CV3WorkspaceSupport.h"
#import "CV3Window.inc"

#pragma mark - Notification tap -> floating split

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

static NSString *CV3PendingNotificationBundleID = nil;
static NSTimeInterval CV3PendingNotificationTimestamp = 0;

static BOOL CV3PendingNotificationIsFresh(void) {
    if (CV3PendingNotificationBundleID.length == 0 || CV3PendingNotificationTimestamp <= 0) return NO;

    NSTimeInterval age = [NSDate timeIntervalSinceReferenceDate] - CV3PendingNotificationTimestamp;
    return age >= 0.0 && age <= 10.0;
}

static BOOL CV3PendingNotificationMatchesBundleID(NSString *bundleID) {
    return bundleID.length > 0 &&
           CV3PendingNotificationIsFresh() &&
           [bundleID isEqualToString:CV3PendingNotificationBundleID];
}

static BOOL CV3HandleNotificationTap(id primaryObject, id secondaryObject, NSString *source) {
    NSString *bundleID = CV3NotificationBundleIDFromObject(primaryObject, 0);
    if (bundleID.length == 0) bundleID = CV3NotificationBundleIDFromObject(secondaryObject, 0);
    if (bundleID.length == 0) return NO;

    // A banner may contain several nested objects. Use the SpringBoard lookup
    // only as a diagnostic; a notification can arrive before SBApplication has
    // materialized its object, while sectionIdentifier is already authoritative.
    id appController = [CV3ClassNamed(@"SBApplicationController") sharedInstance];
    if ([appController respondsToSelector:@selector(applicationWithBundleIdentifier:)]) {
        id application = CV3InvokeObject1(appController,
                                          @selector(applicationWithBundleIdentifier:), bundleID);
        CV3LogToFile(@"[NotificationSplit] 识别通知应用: %@, SBApplication=%@", bundleID, application ? @"已找到" : @"未物化");
    }

    CV3PendingNotificationBundleID = nil;
    CV3PendingNotificationTimestamp = 0;
    CV3ExitExposeModeIfNeeded(nil, NO);
    if (sharedWindow) CV3HidePanelImmediately(sharedWindow);
    return CV3OpenBundleInFloatingWindow(bundleID, source);
}

static void CV3RememberNotificationBundle(id notificationObject, NSString *source) {
    NSString *bundleID = CV3NotificationBundleIDFromObject(notificationObject, 0);
    if (bundleID.length == 0) return;

    CV3PendingNotificationBundleID = [bundleID copy];
    CV3PendingNotificationTimestamp = [NSDate timeIntervalSinceReferenceDate];
    CV3LogToFile(@"[NotificationSplit] 记录待点击通知: %@ (%@)", bundleID, source ?: @"Unknown");
}

static BOOL CV3ConsumePendingNotificationForLaunch(NSString *bundleID) {
    BOOL matches = CV3PendingNotificationMatchesBundleID(bundleID);
    if (matches) {
        CV3PendingNotificationBundleID = nil;
        CV3PendingNotificationTimestamp = 0;
    }
    return matches;
}

static BOOL CV3RedirectPendingNotificationLaunch(NSString *bundleID) {
    if (!CV3ConsumePendingNotificationForLaunch(bundleID)) return NO;

    CV3LogToFile(@"[NotificationSplit] 拦截通知默认启动并改为分屏: %@", bundleID);
    CV3ExitExposeModeIfNeeded(nil, NO);
    if (sharedWindow) CV3HidePanelImmediately(sharedWindow);
    return CV3OpenBundleInFloatingWindow(bundleID, @"LaunchFromNotification");
}

static BOOL CV3RedirectPendingNotificationTransition(id transitionRequest, NSString *source) {
    if (!CV3PendingNotificationIsFresh()) return NO;

    NSString *bundleID = CV3NotificationBundleIDFromObject(transitionRequest, 0);
    if (bundleID.length == 0) {
        NSString *description = [transitionRequest description];
        if ([description containsString:CV3PendingNotificationBundleID]) {
            bundleID = CV3PendingNotificationBundleID;
        }
    }
    if (!CV3PendingNotificationMatchesBundleID(bundleID)) return NO;

    CV3PendingNotificationBundleID = nil;
    CV3PendingNotificationTimestamp = 0;
    CV3LogToFile(@"[NotificationSplit] 拦截通知 Workspace 转场并改为分屏: %@ (%@)", bundleID, source ?: @"Unknown");
    CV3ExitExposeModeIfNeeded(nil, NO);
    if (sharedWindow) CV3HidePanelImmediately(sharedWindow);
    return CV3OpenBundleInFloatingWindow(bundleID, source ?: @"WorkspaceTransitionFromNotification");
}

static const char *CV3SimulatedNotificationName = "com.xu.chevronv3.simulate-notification";
static id CV3CapturedBulletinServer = nil;
static id CV3CapturedBulletinNotificationSource = nil;

static void CV3SetUnsignedIntegerArgument(NSInvocation *invocation, NSUInteger index, unsigned long long value) {
    if (!invocation || index >= invocation.methodSignature.numberOfArguments) return;

    const char *type = [invocation.methodSignature getArgumentTypeAtIndex:index];
    while (type && (*type == 'r' || *type == 'n' || *type == 'N' || *type == 'o' ||
                    *type == 'O' || *type == 'R' || *type == 'V')) {
        type++;
    }

    if (!type) return;
    switch (type[0]) {
        case 'Q': {
            unsigned long long argument = value;
            [invocation setArgument:&argument atIndex:index];
            break;
        }
        case 'q': {
            long long argument = (long long)value;
            [invocation setArgument:&argument atIndex:index];
            break;
        }
        case 'L':
        case 'I': {
            unsigned int argument = (unsigned int)value;
            [invocation setArgument:&argument atIndex:index];
            break;
        }
        case 'l':
        case 'i': {
            int argument = (int)value;
            [invocation setArgument:&argument atIndex:index];
            break;
        }
        case 'S': {
            unsigned short argument = (unsigned short)value;
            [invocation setArgument:&argument atIndex:index];
            break;
        }
        case 's': {
            short argument = (short)value;
            [invocation setArgument:&argument atIndex:index];
            break;
        }
        case 'C':
        case 'B': {
            BOOL argument = value != 0;
            [invocation setArgument:&argument atIndex:index];
            break;
        }
        case 'c': {
            char argument = value != 0;
            [invocation setArgument:&argument atIndex:index];
            break;
        }
        default: {
            unsigned long long argument = value;
            [invocation setArgument:&argument atIndex:index];
            break;
        }
    }
}

static void CV3SetBulletinValue(id bulletin, NSString *key, id value) {
    if (!bulletin || key.length == 0 || !value) return;
    @try {
        [bulletin setValue:value forKey:key];
    } @catch (NSException *exception) {
        CV3LogToFile(@"[NotificationSplit][NativeTest] 无法设置 %@.%@: %@",
                     NSStringFromClass([bulletin class]), key, exception.reason);
    }
}

static __attribute__((unused)) id CV3CreateNativeTestBulletin(NSString *bundleID) {
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
    CV3SetBulletinValue(bulletin, @"message", @"点击此系统通知，应直接开启分屏窗口");
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

static id CV3BulletinServerFromObject(id object) {
    if (!object) return nil;
    if ([object respondsToSelector:NSSelectorFromString(@"publishBulletin:destinations:")]) return object;

    NSArray<NSString *> *selectors = @[
        @"bulletinServer", @"_bulletinServer", @"bbServer", @"_bbServer", @"server", @"_server"
    ];
    for (NSString *selectorName in selectors) {
        id candidate = CV3InvokeObject(object, NSSelectorFromString(selectorName));
        if ([candidate respondsToSelector:NSSelectorFromString(@"publishBulletin:destinations:")]) {
            return candidate;
        }
    }
    return nil;
}

static __attribute__((unused)) id CV3ResolveBulletinServer(void) {
    if ([CV3CapturedBulletinServer respondsToSelector:NSSelectorFromString(@"publishBulletin:destinations:")]) {
        return CV3CapturedBulletinServer;
    }

    Class serverClass = CV3ClassNamed(@"BBServer");
    id server = CV3BulletinServerFromObject(CV3InvokeObject(serverClass, @selector(sharedInstance)));
    if (server) return server;

    id bannerController = CV3InvokeObject(CV3ClassNamed(@"SBBulletinBannerController"), @selector(sharedInstance));
    id applicationDelegate = [UIApplication sharedApplication].delegate;
    id mainWorkspace = CV3InvokeObject(CV3ClassNamed(@"SBMainWorkspace"), @selector(sharedInstance));
    NSArray *roots = @[
        bannerController ?: [NSNull null],
        [UIApplication sharedApplication],
        applicationDelegate ?: [NSNull null],
        mainWorkspace ?: [NSNull null]
    ];
    for (id root in roots) {
        if (root == [NSNull null]) continue;
        server = CV3BulletinServerFromObject(root);
        if (server) return server;
    }
    return nil;
}

static __attribute__((unused)) BOOL CV3PublishBulletinWithServer(id server, id bulletin) {
    SEL selector = NSSelectorFromString(@"publishBulletin:destinations:");
    if (!server || !bulletin || ![server respondsToSelector:selector]) return NO;

    @try {
        NSMethodSignature *signature = [server methodSignatureForSelector:selector];
        if (!signature || signature.numberOfArguments < 4) return NO;
        NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:signature];
        invocation.target = server;
        invocation.selector = selector;
        __unsafe_unretained id bulletinArgument = bulletin;
        [invocation setArgument:&bulletinArgument atIndex:2];
        CV3SetUnsignedIntegerArgument(invocation, 3, 15ULL);
        [invocation invoke];
        return YES;
    } @catch (NSException *exception) {
        CV3LogToFile(@"[NotificationSplit][NativeTest] BBServer 发布异常: %@", exception);
        return NO;
    }
}

static __attribute__((unused)) BOOL CV3PublishBulletinWithBannerController(id bulletin) {
    id controller = CV3InvokeObject(CV3ClassNamed(@"SBBulletinBannerController"), @selector(sharedInstance));
    SEL selector = NSSelectorFromString(@"observer:addBulletin:forFeed:playLightsAndSirens:withReply:");
    if (!controller || ![controller respondsToSelector:selector]) return NO;

    @try {
        NSMethodSignature *signature = [controller methodSignatureForSelector:selector];
        if (!signature || signature.numberOfArguments < 7) return NO;
        NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:signature];
        invocation.target = controller;
        invocation.selector = selector;
        __unsafe_unretained id observer = nil;
        __unsafe_unretained id bulletinArgument = bulletin;
        __unsafe_unretained id reply = nil;
        [invocation setArgument:&observer atIndex:2];
        [invocation setArgument:&bulletinArgument atIndex:3];
        CV3SetUnsignedIntegerArgument(invocation, 4, 2);
        CV3SetUnsignedIntegerArgument(invocation, 5, 1);
        [invocation setArgument:&reply atIndex:6];
        [invocation invoke];
        return YES;
    } @catch (NSException *exception) {
        CV3LogToFile(@"[NotificationSplit][NativeTest] BannerController 发布异常: %@", exception);
        return NO;
    }
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

@interface CV3NotificationTestWindow : UIWindow
@property (nonatomic, weak) UIView *interactiveView;
@end

@implementation CV3NotificationTestWindow
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *interactiveView = self.interactiveView;
    if (!interactiveView || interactiveView.hidden || interactiveView.alpha < 0.01) return nil;
    CGPoint localPoint = [interactiveView convertPoint:point fromView:self];
    if (!CGRectContainsPoint(interactiveView.bounds, localPoint)) return nil;
    return [super hitTest:point withEvent:event];
}
@end

@interface CV3NotificationTestController : NSObject
@property (nonatomic, strong) CV3NotificationTestWindow *window;
@property (nonatomic, strong) UIControl *banner;
@property (nonatomic, copy) NSString *bundleID;
+ (instancetype)sharedController;
- (void)showForBundleID:(NSString *)bundleID;
@end

@implementation CV3NotificationTestController

+ (instancetype)sharedController {
    static CV3NotificationTestController *controller;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        controller = [[self alloc] init];
    });
    return controller;
}

- (void)dismissBanner {
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(dismissBanner) object:nil];
    CV3NotificationTestWindow *window = self.window;
    UIControl *banner = self.banner;
    self.banner = nil;
    self.window = nil;
    [UIView animateWithDuration:0.2 animations:^{
        banner.alpha = 0.0;
        banner.transform = CGAffineTransformMakeTranslation(0, -24.0);
    } completion:^(__unused BOOL finished) {
        window.hidden = YES;
    }];
}

- (void)openTestNotification {
    NSString *bundleID = [self.bundleID copy];
    [self dismissBanner];
    if (bundleID.length == 0) return;
    CV3HandleNotificationTap(@{ @"bundleIdentifier": bundleID }, nil, @"ChevronV3SafeTestBanner");
}

- (void)showForBundleID:(NSString *)bundleID {
    [self dismissBanner];
    self.bundleID = bundleID;

    UIWindowScene *activeScene = nil;
    if (@available(iOS 13.0, *)) {
        for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
            if ([scene isKindOfClass:[UIWindowScene class]] &&
                scene.activationState == UISceneActivationStateForegroundActive) {
                activeScene = (UIWindowScene *)scene;
                break;
            }
        }
    }

    CV3NotificationTestWindow *window;
    if (@available(iOS 13.0, *)) {
        if (!activeScene) {
            CV3LogToFile(@"[NotificationSplit][SafeTest] 未找到前台 UIWindowScene");
            return;
        }
        window = [[CV3NotificationTestWindow alloc] initWithWindowScene:activeScene];
    } else {
        window = [[CV3NotificationTestWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
    }
    window.frame = window.screen.bounds;
    window.backgroundColor = UIColor.clearColor;
    window.windowLevel = CV3Style.maxBound;

    UIViewController *rootController = [[UIViewController alloc] init];
    rootController.view.backgroundColor = UIColor.clearColor;
    window.rootViewController = rootController;

    CGFloat width = MIN(CGRectGetWidth(window.bounds) - 24.0, 430.0);
    CGFloat topInset = activeScene ? activeScene.windows.firstObject.safeAreaInsets.top : 20.0;
    UIControl *banner = [[UIControl alloc] initWithFrame:CGRectMake((CGRectGetWidth(window.bounds) - width) / 2.0,
                                                                   MAX(topInset + 6.0, 12.0),
                                                                   width,
                                                                   88.0)];
    banner.layer.cornerRadius = 18.0;
    if (@available(iOS 13.0, *)) banner.layer.cornerCurve = kCACornerCurveContinuous;
    banner.layer.masksToBounds = YES;
    [banner addTarget:self action:@selector(openTestNotification) forControlEvents:UIControlEventTouchUpInside];

    UIVisualEffectView *blur = [[UIVisualEffectView alloc] initWithEffect:
                                [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemMaterial]];
    blur.frame = banner.bounds;
    blur.userInteractionEnabled = NO;
    blur.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [banner addSubview:blur];

    UIImageView *iconView = [[UIImageView alloc] initWithFrame:CGRectMake(14.0, 18.0, 52.0, 52.0)];
    iconView.image = [UIImage _applicationIconImageForBundleIdentifier:bundleID format:2 scale:[UIScreen mainScreen].scale];
    iconView.layer.cornerRadius = 11.0;
    iconView.layer.masksToBounds = YES;
    [banner addSubview:iconView];

    id proxy = CV3InvokeObject1(CV3ClassNamed(@"LSApplicationProxy"),
                                @selector(applicationProxyForIdentifier:), bundleID);
    NSString *appName = CV3InvokeObject(proxy, @selector(localizedName));
    if (appName.length == 0) appName = bundleID;

    UILabel *titleLabel = [[UILabel alloc] initWithFrame:CGRectMake(78.0, 15.0, width - 94.0, 25.0)];
    titleLabel.font = [UIFont systemFontOfSize:15.0 weight:UIFontWeightSemibold];
    titleLabel.textColor = UIColor.labelColor;
    titleLabel.text = appName;
    [banner addSubview:titleLabel];

    UILabel *messageLabel = [[UILabel alloc] initWithFrame:CGRectMake(78.0, 39.0, width - 94.0, 36.0)];
    messageLabel.font = [UIFont systemFontOfSize:13.0 weight:UIFontWeightRegular];
    messageLabel.textColor = UIColor.secondaryLabelColor;
    messageLabel.numberOfLines = 2;
    messageLabel.text = @"ChevronV3 测试通知：点击后应直接开启分屏窗口";
    [banner addSubview:messageLabel];

    banner.alpha = 0.0;
    banner.transform = CGAffineTransformMakeTranslation(0, -24.0);
    [rootController.view addSubview:banner];
    window.interactiveView = banner;
    self.window = window;
    self.banner = banner;
    window.hidden = NO;

    [UIView animateWithDuration:0.28 delay:0.0 usingSpringWithDamping:0.82 initialSpringVelocity:0.2 options:0 animations:^{
        banner.alpha = 1.0;
        banner.transform = CGAffineTransformIdentity;
    } completion:nil];
    [self performSelector:@selector(dismissBanner) withObject:nil afterDelay:8.0];
    CV3LogToFile(@"[NotificationSplit][SafeTest] 已显示安全测试通知: %@", bundleID);
}

@end

static void CV3HandleSimulatedNotificationRequest(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        @try {
            NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:@"com.xu.chevronv3"];
            NSString *bundleID = [defaults stringForKey:@"CV3TestNotificationBundleID"];
            if (!CV3LooksLikeBundleIdentifier(bundleID)) bundleID = @"com.apple.MobileSMS";

            CV3LogToFile(@"[NotificationSplit][NativeTest] 收到原生通知请求: %@", bundleID);
            id bulletin = CV3CreateNativeTestBulletin(bundleID);
            if (!bulletin || !CV3PublishBulletinThroughNotificationSource(bulletin)) {
                CV3LogToFile(@"[NotificationSplit][NativeTest] 发布失败：系统原生通知源不可用");
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
- (void)presentBannerForNotificationRequest:(id)request {
    CV3RememberNotificationBundle(request, @"SBBannerController.present");
    %orig(request);
}

- (void)_presentBannerForNotificationRequest:(id)request {
    CV3RememberNotificationBundle(request, @"SBBannerController._present");
    %orig(request);
}

- (void)bannerViewController:(id)viewController didReceiveResponse:(id)response {
    if (CV3HandleNotificationTap(response, viewController, @"SBBannerController")) return;
    %orig(viewController, response);
}

- (void)handleTapForBanner:(id)banner {
    if (CV3HandleNotificationTap(banner, nil, @"SBBannerController.handleTap")) return;
    %orig(banner);
}
%end

%hook SBBulletinBannerController
- (void)_presentBannerForItem:(id)item {
    CV3RememberNotificationBundle(item, @"SBBulletinBannerController.present");
    %orig(item);
}

- (void)presentBannerForNotificationRequest:(id)request {
    CV3RememberNotificationBundle(request, @"SBBulletinBannerController.present");
    %orig(request);
}

- (void)handleTapForBanner:(id)banner {
    if (CV3HandleNotificationTap(banner, nil, @"SBBulletinBannerController.handleTap")) return;
    %orig(banner);
}

- (void)_handleTapForBanner:(id)banner {
    if (CV3HandleNotificationTap(banner, nil, @"SBBulletinBannerController._handleTap")) return;
    %orig(banner);
}
%end

%hook SBNotificationBannerController
- (void)bannerViewController:(id)viewController didReceiveResponse:(id)response {
    if (CV3HandleNotificationTap(response, viewController, @"SBNotificationBannerController")) return;
    %orig(viewController, response);
}
%end

%hook SBNotificationBannerDestination
- (void)postNotificationRequest:(id)request forCoalescedNotification:(id)notification {
    CV3RememberNotificationBundle(request ?: notification, @"SBNotificationBannerDestination.post");
    %orig(request, notification);
}

- (void)handleNotificationResponse:(id)response forNotificationRequest:(id)request {
    if (CV3HandleNotificationTap(response, request, @"SBNotificationBannerDestination")) return;
    %orig(response, request);
}

- (void)notificationResponse:(id)response forRequest:(id)request {
    if (CV3HandleNotificationTap(response, request, @"SBNotificationBannerDestination.response")) return;
    %orig(response, request);
}
%end

%hook NCNotificationViewController
- (void)notificationViewController:(id)viewController didReceiveResponse:(id)response {
    if (CV3HandleNotificationTap(response, viewController, @"NCNotificationViewController")) return;
    %orig(viewController, response);
}
%end

%hook NCNotificationAlertQueue
- (void)postNotificationRequest:(id)request forCoalescedNotification:(id)notification {
    CV3RememberNotificationBundle(request ?: notification, @"NCNotificationAlertQueue.post");
    %orig(request, notification);
}
%end

%hook NCNotificationShortLookViewController
- (void)setNotificationRequest:(id)request {
    CV3RememberNotificationBundle(request, @"NCNotificationShortLookViewController.setRequest");
    %orig(request);
}

- (void)_setNotificationRequest:(id)request {
    CV3RememberNotificationBundle(request, @"NCNotificationShortLookViewController._setRequest");
    %orig(request);
}

- (void)handleNotificationResponse:(id)response {
    if (CV3HandleNotificationTap(response, self, @"NCNotificationShortLookViewController.response")) return;
    %orig(response);
}
%end

%hook NCNotificationListCell
- (void)setNotificationRequest:(id)request {
    CV3RememberNotificationBundle(request, @"NCNotificationListCell.setRequest");
    %orig(request);
}

- (void)_setNotificationRequest:(id)request {
    CV3RememberNotificationBundle(request, @"NCNotificationListCell._setRequest");
    %orig(request);
}
%end

static BOOL CV3IsDefaultBulletinAction(id action, id bulletin) {
    if (!action || !bulletin) return NO;

    id defaultAction = CV3InvokeObject(bulletin, @selector(defaultAction));
    if (defaultAction == action) return YES;

    NSString *identifier = CV3InvokeObject(action, @selector(identifier));
    NSString *defaultIdentifier = CV3InvokeObject(defaultAction, @selector(identifier));
    if (identifier.length > 0 && defaultIdentifier.length > 0 &&
        [identifier isEqualToString:defaultIdentifier]) {
        return YES;
    }

    NSString *lowercaseIdentifier = identifier.lowercaseString;
    if ([lowercaseIdentifier containsString:@"defaultaction"] ||
        [lowercaseIdentifier containsString:@"default-action"]) {
        return YES;
    }

    NSString *launchBundleID = CV3InvokeObject(action, @selector(launchBundleID));
    NSString *sectionID = CV3NotificationBundleIDFromObject(bulletin, 0);
    return launchBundleID.length > 0 && [launchBundleID isEqualToString:sectionID];
}

// This is the common default-action runner used by real BulletinBoard
// notifications on iOS 14 through current releases. Recording the token here
// keeps custom notification buttons on their original path.
%hook NCBulletinActionRunner
- (void)executeAction:(id)action
           fromOrigin:(id)origin
             endpoint:(id)endpoint
       withParameters:(id)parameters
           completion:(id)completion {
    id bulletin = CV3InvokeObject(self, @selector(bulletin));
    id runnerAction = CV3InvokeObject(self, @selector(action)) ?: action;
    if (CV3IsDefaultBulletinAction(runnerAction, bulletin)) {
        NSString *bundleID = CV3NotificationBundleIDFromObject(bulletin, 0);
        if (bundleID.length > 0) {
            SEL forwardSelector = @selector(setShouldForwardAction:);
            if ([(id)self respondsToSelector:forwardSelector]) {
                ((void (*)(id, SEL, BOOL))objc_msgSend)(self, forwardSelector, NO);
            }

            CV3LogToFile(@"[NotificationSplit] 捕获系统原生通知默认点击并接管启动: %@", bundleID);
            %orig(action, origin, endpoint, parameters, completion);

            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.05 * NSEC_PER_SEC)),
                           dispatch_get_main_queue(), ^{
                BOOL opened = CV3HandleNotificationTap(bulletin, nil, @"NCBulletinActionRunner.defaultAction");
                CV3LogToFile(@"[NotificationSplit] 原生通知点击分屏结果: %@ success=%d", bundleID, opened);
            });
            return;
        }
    }
    %orig(action, origin, endpoint, parameters, completion);
}
%end

%hook LSApplicationWorkspace
- (BOOL)openApplicationWithBundleID:(NSString *)bundleID {
    if (CV3RedirectPendingNotificationLaunch(bundleID)) return YES;
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

        if (floatingWindows) {
            for (CV3FloatingAppWindow *win in [floatingWindows copy]) {
                if (![win isKindOfClass:[CV3FloatingAppWindow class]] || win.isClosing) continue;
                UIInterfaceOrientation previousOrientation = win.lastLayoutOrientation;
                CGAffineTransform previousRotation = win.baseRotationTransform;
                [win applySceneRotationContext:context force:force];
                if (previousOrientation != context.orientation ||
                    !CGAffineTransformEqualToTransform(previousRotation, win.baseRotationTransform)) {
                    [win attachToCurrentActiveScene];
                }
            }
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
@property (nonatomic, copy) NSSet *entities;
@end

@interface SBMainWorkspaceTransitionRequest : SBWorkspaceTransitionRequest
@property (nonatomic, copy) NSSet *deactivatedEntities;
@property (nonatomic, assign) NSInteger source;
- (BOOL)isAppearingBackgrounded;
- (BOOL)isAppearingInBackground;
@end

%hook SBMainWorkspaceTransitionRequest
- (BOOL)isAppearingBackgrounded {
    if (floatingWindows && floatingWindows.count > 0) {
        return NO; // 核心：防止系统认为转换请求会导致应用进入后台
    }
    return %orig;
}

- (BOOL)isAppearingInBackground {
    if (floatingWindows && floatingWindows.count > 0) {
        return NO; 
    }
    return %orig;
}

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

%hook SBAppLayout
- (BOOL)containsItemWithBundleIdentifier:(NSString *)bid {
    if (floatingWindows && floatingWindows.count > 0) {
        for (CV3FloatingAppWindow *win in floatingWindows) {
            if ([bid isEqualToString:win.bundleID] && !win.isClosing) {
                return YES; // 核心：欺骗系统，让其认为分屏应用始终是当前 Layout 的一部分，从而避免任何形式的自动停用
            }
        }
    }
    return %orig;
}
%end

static BOOL CV3SpoofPadIdiomDuringSwitcherLoad = NO;

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
    BOOL previousSpoofState = CV3SpoofPadIdiomDuringSwitcherLoad;
    CV3SpoofPadIdiomDuringSwitcherLoad = YES;
    @try {
        %orig(windowScene);
    } @finally {
        CV3SpoofPadIdiomDuringSwitcherLoad = previousSpoofState;
    }
}
%end

%hook UIDevice
- (UIUserInterfaceIdiom)userInterfaceIdiom {
    if (CV3SpoofPadIdiomDuringSwitcherLoad) {
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

%hook SBHomeGestureSwitcherModifier
- (double)scaleForIndex:(unsigned long long)index {
    if (floatingWindows && floatingWindows.count > 0) {
        if ([self respondsToSelector:@selector(appLayouts)]) {
            NSArray *layouts = [self appLayouts];
            if (index < layouts.count) {
                SBAppLayout *layout = layouts[index];
                if ([layout respondsToSelector:@selector(containsItemWithBundleIdentifier:)]) {
                    for (CV3FloatingAppWindow *win in floatingWindows) {
                        if (!win.isClosing && [layout containsItemWithBundleIdentifier:win.bundleID]) {
                            return 1.0;
                        }
                    }
                }
            }
        }
    }
    return %orig;
}

- (double)opacityForIndex:(unsigned long long)index {
    if (floatingWindows && floatingWindows.count > 0) {
        if ([self respondsToSelector:@selector(appLayouts)]) {
            NSArray *layouts = [self appLayouts];
            if (index < layouts.count) {
                SBAppLayout *layout = layouts[index];
                if ([layout respondsToSelector:@selector(containsItemWithBundleIdentifier:)]) {
                    for (CV3FloatingAppWindow *win in floatingWindows) {
                        if (!win.isClosing && [layout containsItemWithBundleIdentifier:win.bundleID]) {
                            return 1.0;
                        }
                    }
                }
            }
        }
    }
    return %orig;
}

- (double)dimmingAlphaForIndex:(unsigned long long)index {
    if (floatingWindows && floatingWindows.count > 0) {
        if ([self respondsToSelector:@selector(appLayouts)]) {
            NSArray *layouts = [self appLayouts];
            if (index < layouts.count) {
                SBAppLayout *layout = layouts[index];
                if ([layout respondsToSelector:@selector(containsItemWithBundleIdentifier:)]) {
                    for (CV3FloatingAppWindow *win in floatingWindows) {
                        if (!win.isClosing && [layout containsItemWithBundleIdentifier:win.bundleID]) {
                            return 0.0; // 禁止变暗
                        }
                    }
                }
            }
        }
    }
    return %orig;
}

- (double)cornerRadiusForIndex:(unsigned long long)index {
    if (floatingWindows && floatingWindows.count > 0) {
        if ([self respondsToSelector:@selector(appLayouts)]) {
            NSArray *layouts = [self appLayouts];
            if (index < layouts.count) {
                SBAppLayout *layout = layouts[index];
                if ([layout respondsToSelector:@selector(containsItemWithBundleIdentifier:)]) {
                    for (CV3FloatingAppWindow *win in floatingWindows) {
                        if (!win.isClosing && [layout containsItemWithBundleIdentifier:win.bundleID]) {
                            // 保持窗口原生圆角，防止系统在 Home 手势时强加巨大的圆角
                            return CV3Style.cornerRadius;
                        }
                    }
                }
            }
        }
    }
    return %orig;
}

- (double)shadowOpacityForIndex:(unsigned long long)index {
    if (floatingWindows && floatingWindows.count > 0) {
        if ([self respondsToSelector:@selector(appLayouts)]) {
            NSArray *layouts = [self appLayouts];
            if (index < layouts.count) {
                SBAppLayout *layout = layouts[index];
                if ([layout respondsToSelector:@selector(containsItemWithBundleIdentifier:)]) {
                    for (CV3FloatingAppWindow *win in floatingWindows) {
                        if (!win.isClosing && [layout containsItemWithBundleIdentifier:win.bundleID]) {
                            return 0.4; // 维持我们自己的阴影透明度
                        }
                    }
                }
            }
        }
    }
    return %orig;
}

- (BOOL)isItemResizingAllowedForIndex:(unsigned long long)index {
    if (floatingWindows && floatingWindows.count > 0) {
        if ([self respondsToSelector:@selector(appLayouts)]) {
            NSArray *layouts = [self appLayouts];
            if (index < layouts.count) {
                SBAppLayout *layout = layouts[index];
                for (CV3FloatingAppWindow *win in floatingWindows) {
                    if (!win.isClosing && [layout containsItemWithBundleIdentifier:win.bundleID]) {
                        return NO; // 禁止系统在手势期间调整分屏 App 的尺寸
                    }
                }
            }
        }
    }
    return %orig;
}

- (double)blurViewIconScaleForIndex:(unsigned long long)index {
    if (floatingWindows && floatingWindows.count > 0) {
        if ([self respondsToSelector:@selector(appLayouts)]) {
            NSArray *layouts = [self appLayouts];
            if (index < layouts.count) {
                SBAppLayout *layout = layouts[index];
                for (CV3FloatingAppWindow *win in floatingWindows) {
                    if (!win.isClosing && [layout containsItemWithBundleIdentifier:win.bundleID]) {
                        return 0.0; // 彻底禁止系统图标模糊层
                    }
                }
            }
        }
    }
    return %orig;
}

- (BOOL)isWallpaperRequiredForIndex:(unsigned long long)index {
    if (floatingWindows && floatingWindows.count > 0) {
        if ([self respondsToSelector:@selector(appLayouts)]) {
            NSArray *layouts = [self appLayouts];
            if (index < layouts.count) {
                SBAppLayout *layout = layouts[index];
                for (CV3FloatingAppWindow *win in floatingWindows) {
                    if (!win.isClosing && [layout containsItemWithBundleIdentifier:win.bundleID]) {
                        return NO; // 分屏应用不需要系统壁纸背景
                    }
                }
            }
        }
    }
    return %orig;
}

- (double)titleOpacityForIndex:(unsigned long long)index {
    if (floatingWindows && floatingWindows.count > 0) {
        if ([self respondsToSelector:@selector(appLayouts)]) {
            NSArray *layouts = [self appLayouts];
            if (index < layouts.count) {
                SBAppLayout *layout = layouts[index];
                for (CV3FloatingAppWindow *win in floatingWindows) {
                    if (!win.isClosing && [layout containsItemWithBundleIdentifier:win.bundleID]) {
                        return 0.0; // 隐藏系统在转场时强加的标题
                    }
                }
            }
        }
    }
    return %orig;
}

- (BOOL)shouldUseWallpaperGradientTreatmentForIndex:(unsigned long long)index {
    if (floatingWindows && floatingWindows.count > 0) {
        if ([self respondsToSelector:@selector(appLayouts)]) {
            NSArray *layouts = [self appLayouts];
            if (index < layouts.count) {
                SBAppLayout *layout = layouts[index];
                for (CV3FloatingAppWindow *win in floatingWindows) {
                    if (!win.isClosing && [layout containsItemWithBundleIdentifier:win.bundleID]) {
                        return NO; // 禁止系统渐变压制
                    }
                }
            }
        }
    }
    return %orig;
}
%end

%hook FBSceneManager
- (void)destroyScene:(id)arg1 withTransitionContext:(id)arg2 {
    if (floatingWindows && floatingWindows.count > 0) {
        FBScene *scene = (FBScene *)arg1;
        for (CV3FloatingAppWindow *win in floatingWindows) {
            if (CV3IdentifierContainsExactBundleID(scene.identifier, win.bundleID) && !win.isClosing) {
                CV3LogToFile(@"[Lifecycle] 系统尝试销毁托管场景 (%@)，清理渲染并准备恢复", win.bundleID);
                dispatch_async(dispatch_get_main_queue(), ^{
                    if (win.hostView) {
                        [win.hostView removeFromSuperview];
                        win.hostView = nil;
                    }
                    win.targetScene = nil;
                    if (!win.isStashed) {
                        [win ensureLaunchSplashVisible];
                        [win loadAppScene];
                    }
                });
                break;
            }
        }
    }
    %orig;
}
%end

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
    if (CV3RedirectPendingNotificationTransition(arg1, @"SBMainWorkspace.executeTransitionRequest")) return;
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
    CV3ExitExposeModeIfNeeded(nil, NO);
    if (sharedWindow) sharedWindow.hidden = YES;
    // 核心：分屏窗口在锁屏时不应被强制隐藏，除非用户手动操作
    if (floatingWindows) {
        for (CV3FloatingAppWindow *win in floatingWindows) {
            if ([win isKindOfClass:[CV3FloatingAppWindow class]]) {
                [win setHidden:NO];
                [win makeKeyAndVisible];
                win.windowLevel = CV3Style.floatingApp;
            }
        }
    }
}
- (void)lockScreenViewControllerDidDismiss {
    %orig;
    if (sharedWindow) sharedWindow.hidden = NO;
    if (floatingWindows) {
        for (CV3FloatingAppWindow *win in floatingWindows) {
            if ([win isKindOfClass:[CV3FloatingAppWindow class]]) [win setHidden:NO];
        }
    }
}
%end

#pragma mark - Fix: Auto-hide when Control Center or Notification Center is active
%hook SBControlCenterController
- (void)_willPresent {
    %orig;
    CV3ExitExposeModeIfNeeded(nil, NO);
    if (sharedWindow) {
        sharedWindow.isSuppressedBySystem = YES;
        sharedWindow.hidden = YES;
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
    if (sharedWindow) {
        sharedWindow.isSuppressedBySystem = NO;
        sharedWindow.hidden = NO;
    }
}
%end

%hook SBCoverSheetPresentationManager
- (void)setCoverSheetPresented:(BOOL)arg1 animated:(BOOL)arg2 {
    %orig;
    if (arg1) CV3ExitExposeModeIfNeeded(nil, NO);
    if (sharedWindow) {
        sharedWindow.isSuppressedBySystem = arg1;
        sharedWindow.hidden = arg1;
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
    %orig;
    CV3ExitExposeModeIfNeeded(nil, NO);
    if (sharedWindow) {
        sharedWindow.isSuppressedBySystem = YES;
        sharedWindow.hidden = YES;
    }
}
- (void)viewDidDisappear:(BOOL)animated {
    %orig;
    if (sharedWindow) {
        // 只有当没有其他系统 UI 活跃时才解除压制
        if (![sharedWindow isSystemUIActive]) {
            sharedWindow.isSuppressedBySystem = NO;
            sharedWindow.hidden = NO;
        }
    }
}
%end

%hook SBIconController
- (BOOL)isAppLibraryAllowed {
    return NO;
}

- (BOOL)isAppLibrarySupported {
    return NO;
}
%end

%hook SBFloatingDockDefaults
- (BOOL)appLibraryEnabled {
    return NO;
}
%end

%hook SBRootFolderController
- (id)trailingCustomViewController {
    return nil;
}
%end

%hook SBRootFolderView
- (id)trailingCustomView {
    return nil;
}
%end

%hook SpringBoard
- (BOOL)launchApplicationWithIdentifier:(NSString *)identifier suspended:(BOOL)suspended {
    // When a notification banner falls through to SpringBoard's normal app
    // launch path, convert that launch into a hosted window before the app can
    // take over the screen. The short-lived, bundle-matched token prevents
    // ordinary app launches from being affected.
    if (!suspended && CV3RedirectPendingNotificationLaunch(identifier)) return YES;

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

        UIWindowScene *fallbackScene = nil;
        for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
            if (![scene isKindOfClass:[UIWindowScene class]]) continue;

            UIWindowScene *windowScene = (UIWindowScene *)scene;
            NSString *role = windowScene.session.role;
            if ([role isEqualToString:@"SBWindowSceneSessionRoleSystemAperture"] ||
                [role isEqualToString:@"SBWindowSceneSessionRoleSystemApertureCurtain"] ||
                [role isEqualToString:@"UISceneSessionRolePlaceholder"] ||
                [[role lowercaseString] containsString:@"siri"]) {
                continue;
            }

            if (!fallbackScene) fallbackScene = windowScene;
            if (windowScene.activationState == UISceneActivationStateForegroundActive) {
                return windowScene;
            }
        }
        return fallbackScene;
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
    for (UIView *subview in self.subviews) {
        BOOL isKeyboardLayer = [NSStringFromClass([subview class]) containsString:@"Keyboard"];
        if ([self.accessibilityIdentifier isEqualToString:@"ChevronV3Host"] && !isKeyboardLayer) {
            if (CGAffineTransformIsIdentity(subview.transform)) {
                subview.frame = self.bounds;
            } else {
                subview.bounds = CGRectMake(0, 0, self.bounds.size.width, self.bounds.size.height);
                subview.center = CGPointMake(self.bounds.size.width / 2.0, self.bounds.size.height / 2.0);
            }
            continue;
        }

        if (isKeyboardLayer) {
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
            cv3_keyboardWindow.frame = hostBounds;

            UIInterfaceOrientation orientation = CV3TrustedInterfaceOrientation(keyboardScene);
            BOOL isLandscape = UIInterfaceOrientationIsLandscape(orientation);
            CGAffineTransform preservedTransform = subview.transform;
            CGRect preservedBounds = subview.bounds;
            CGPoint preservedCenter = subview.center;
            UIView *previousSuperview = subview.superview;
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

            if (!isLandscape && CGAffineTransformIsIdentity(preservedTransform)) {
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
- (void)setSwitcherWindowVisible:(BOOL)arg1 {
    if (arg1) {
        CV3BeginWorkspaceTransitionProtection(@"SwitcherWindowVisible");
    }
    %orig;
    // 核心：当 Switcher 窗口状态改变时，强制刷新所有分屏窗口的显示状态
    if (floatingWindows) {
        for (CV3FloatingAppWindow *win in floatingWindows) {
            if ([win isKindOfClass:[CV3FloatingAppWindow class]] && !win.isClosing) {
                [win setHidden:NO];
                [win makeKeyAndVisible];
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
    if (arg1) {
        CV3BeginWorkspaceTransitionProtection(@"MainSwitcherVisible");
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
                // 如果窗口被 Stash (侧边隐藏)，且系统正在尝试将其置于后台，我们不再强制拉回前台
                // 这能有效避免系统判定应用“违规占据前台”而触发的杀进程行为 (0xDEAD10CC)
                if (win.isStashed) {
                    %orig(arg1, arg2);
                    return;
                }

                id mutableSettings = [arg1 mutableCopy];
                BOOL modified = [win applyForegroundSovereigntyToSettings:mutableSettings
                                                         clearDeactivation:YES
                                                               forceLayout:NO];

                if (modified) {
                    CV3LogToFile(@"[FBScene] 捕捉到 Settings 更新请求: %@", win.bundleID);
                    %orig(mutableSettings, arg2);
                } else {
                    %orig(arg1, arg2);
                }
                
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
                if (win.isStashed) {
                    %orig(arg1, arg2, arg3);
                    return;
                }

                id mutableSettings = [arg1 mutableCopy];
                BOOL modified = [win applyForegroundSovereigntyToSettings:mutableSettings
                                                         clearDeactivation:YES
                                                               forceLayout:NO];

                if (modified) {
                    CV3LogToFile(@"[FBScene] 捕捉到 Settings 更新请求 (带 completion): %@", win.bundleID);
                    %orig(mutableSettings, arg2, arg3);
                } else {
                    %orig(arg1, arg2, arg3);
                }
                
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
                    CV3LogToFile(@"[FBScene] 拦截到 contentState 降级 -> %ld，强制恢复为 2: %@", (long)arg1, win.bundleID);
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

%ctor {
    @autoreleasepool {
        CV3RegisterVideoOrientationBridge();
        CV3RegisterSimulatedNotificationBridge();
        %init;
    }
}
