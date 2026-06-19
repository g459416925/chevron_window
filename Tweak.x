#import <UIKit/UIKit.h>
#import <CoreMotion/CoreMotion.h>
#import <QuartzCore/QuartzCore.h>
#import <AudioToolbox/AudioToolbox.h>
#import <objc/runtime.h>
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
- (void)launchApplicationWithIdentifier:(NSString *)identifier suspended:(BOOL)suspended;
@end

@class FBScene;

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
- (void)enableHostingForRequester:(id)arg1 priority:(long long)arg2;
- (UIView *)hostView;
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
    CGFloat floatingChromeH;
    CGFloat floatingChromeControlSize;
    CGFloat floatingChromeCornerRadius;
    CGFloat resizeHandleHitArea;
    CGFloat resizeHandleWindowExpansion;
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
    .floatingChromeH = 28.0,
    .floatingChromeControlSize = 12.0,
    .floatingChromeCornerRadius = 18.0,
    .resizeHandleHitArea = 80.0,
    .resizeHandleWindowExpansion = 40.0
};

#pragma mark - Custom Cell
@interface CV3AppCell : UICollectionViewCell
@property (nonatomic, strong) UIImageView *iconView;
@property (nonatomic, strong) UILabel *nameLabel;
@property (nonatomic, strong) CAGradientLayer *iconHighlight;
@property (nonatomic, strong) UIView *pinnedIndicator; 
@property (nonatomic, assign) CGPoint iconOffset; // 新增：图标视差偏移
@property (nonatomic, assign) BOOL isFirstResult; // 新增：是否为搜索首项
- (void)configureWithInfo:(CV3AppInfo *)info searchText:(NSString *)searchText isFirst:(BOOL)isFirst;
- (void)startBreathing;
- (void)startPulse; 
- (void)stopPulse;  
@end

@implementation CV3AppCell
- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        CGFloat iconSize = 54.0;
        UIView *ivBack = [[UIView alloc] initWithFrame:CGRectMake((frame.size.width - iconSize)/2, 8, iconSize, iconSize)];
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

        self.iconHighlight = [CAGradientLayer layer];
        self.iconHighlight.frame = self.iconView.bounds;
        self.iconHighlight.colors = @[(id)[[UIColor labelColor] colorWithAlphaComponent:0.0].CGColor,
                                      (id)[[UIColor labelColor] colorWithAlphaComponent:CV3Style.highlightAlpha].CGColor,
                                      (id)[[UIColor labelColor] colorWithAlphaComponent:0.0].CGColor];
        self.iconHighlight.startPoint = CGPointMake(0, 0);
        self.iconHighlight.endPoint = CGPointMake(1, 1);
        self.iconHighlight.opacity = 0; 
        [self.iconView.layer addSublayer:self.iconHighlight];

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

- (void)setIconOffset:(CGPoint)offset {
    _iconOffset = offset;
    // 应用反向视差位移，模拟物理深度
    CGAffineTransform t = CGAffineTransformMakeTranslation(offset.x, offset.y);
    self.iconView.transform = t;
}

- (void)configureWithInfo:(CV3AppInfo *)info searchText:(NSString *)searchText isFirst:(BOOL)isFirst {
    self.iconView.image = info.icon;
    self.pinnedIndicator.hidden = !info.isPinned;
    self.isFirstResult = isFirst;
    if (info.isPinned) [self.iconView bringSubviewToFront:self.pinnedIndicator];

    if (searchText && searchText.length > 0) {
        NSMutableAttributedString *as = [[NSMutableAttributedString alloc] initWithString:info.name attributes:@{NSForegroundColorAttributeName: [UIColor labelColor]}];
        NSRange range = [info.name rangeOfString:searchText options:NSCaseInsensitiveSearch];
        if (range.location != NSNotFound) {
            [as addAttribute:NSForegroundColorAttributeName value:[UIColor colorWithRed:0.15 green:0.79 blue:0.25 alpha:1.0] range:range];
            [as addAttribute:NSFontAttributeName value:[UIFont systemFontOfSize:10.0 weight:UIFontWeightBold] range:range];
        }
        self.nameLabel.attributedText = as;
        
        // 如果是首选结果，开启强烈脉冲
        if (isFirst) {
            [self startPulse];
            self.iconView.layer.borderWidth = 1.5;
            self.iconView.layer.borderColor = [[UIColor colorWithRed:0.15 green:0.79 blue:0.25 alpha:0.6] CGColor];
        } else {
            [self stopPulse];
            self.iconView.layer.borderWidth = 0;
        }
    } else {
        self.nameLabel.attributedText = nil;
        self.nameLabel.text = info.name;
        self.nameLabel.textColor = [UIColor labelColor];
        self.iconView.layer.borderWidth = 0;
    }
}
- (void)startBreathing {
    [self.contentView.layer removeAnimationForKey:@"breathing"];
    CAKeyframeAnimation *anim = [CAKeyframeAnimation animationWithKeyPath:@"transform.translation.y"];
    CGFloat offset = 2.0 + (arc4random_uniform(20) / 10.0);
    anim.values = @[@0, @(-offset), @0, @(offset), @0];
    anim.duration = 3.5 + (arc4random_uniform(20) / 10.0);
    anim.repeatCount = HUGE_VALF;
    anim.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
    anim.beginTime = CACurrentMediaTime() + (arc4random_uniform(100) / 25.0);
    [self.contentView.layer addAnimation:anim forKey:@"breathing"];
}

- (void)startPulse {
    [self.iconHighlight removeAnimationForKey:@"pulse"];
    CABasicAnimation *pulse = [CABasicAnimation animationWithKeyPath:@"opacity"];
    pulse.fromValue = @(0.05);
    pulse.toValue = @(0.25);
    pulse.duration = 2.0 + (arc4random_uniform(10) / 10.0);
    pulse.autoreverses = YES;
    pulse.repeatCount = HUGE_VALF;
    pulse.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
    [self.iconHighlight addAnimation:pulse forKey:@"pulse"];
}

- (void)stopPulse {
    [self.iconHighlight removeAnimationForKey:@"pulse"];
    self.iconHighlight.opacity = 0;
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

#pragma mark - Floating App Window (MilkyWay2-style)
static NSMutableArray *floatingWindows = nil;
static UIInterfaceOrientation CV3LastTrustedInterfaceOrientation = UIInterfaceOrientationPortrait;
static BOOL CV3SuppressPresentationContextFanout = NO;
static BOOL CV3WorkspaceTransitionActive = NO;
static NSUInteger CV3WorkspaceTransitionProtectionToken = 0;

static BOOL CV3IsValidInterfaceOrientation(UIInterfaceOrientation orientation) {
    return orientation != UIInterfaceOrientationUnknown && orientation != 0;
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
@property (nonatomic, strong) UIView *windowChromeView;
@property (nonatomic, strong) UIView *chromeDragHandle;
@property (nonatomic, strong) UIButton *chromeCloseButton;
@property (nonatomic, strong) UIButton *chromeMinimizeButton;
@property (nonatomic, strong) UIButton *chromeModeButton;
@property (nonatomic, strong) UIVisualEffectView *multitaskingMenuView;
@property (nonatomic, assign) BOOL chromeControlsExpanded;
@property (nonatomic, strong) NSTimer *chromeCollapseTimer;
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
@property (nonatomic, assign) CGPoint lastVelocity;
@property (nonatomic, strong) UIView *crystalPreviewContainer;
@property (nonatomic, strong) UIView *splashView;
@property (nonatomic, strong) UIImageView *largeSplashIcon;
@property (nonatomic, assign) UIInterfaceOrientation targetOrientation;
@property (nonatomic, assign) UIInterfaceOrientation lastLayoutOrientation;
@property (nonatomic, assign) CGAffineTransform baseRotationTransform;
@property (nonatomic, assign) CGRect preFullscreenFrame;
@property (nonatomic, assign) CGRect preCompactFrame;
@property (nonatomic, assign) BOOL isFullscreenMode;
@property (nonatomic, assign) BOOL isCompactMode;
@property (nonatomic, strong) UIView *liveResizeSnapshotView;
@property (nonatomic, strong) RBSAssertion *rbsAssertion; 
@property (nonatomic, assign) BOOL allowProcessTerminationOnClose;

- (instancetype)initWithBundleID:(NSString *)bundleID center:(CGPoint)center windowScene:(UIWindowScene *)windowScene;
- (void)triggerCollisionImpulse;
- (void)updateAdaptiveColor;
- (void)setWindowFocused:(BOOL)focused;
- (void)restoreFromStash;
- (void)setTargetOrientation:(UIInterfaceOrientation)orientation;
- (void)applyCurrentTransformWithScale:(CGFloat)scale;
- (void)handleTransitionGhosting;
- (void)refreshHostViewPresentation;
- (void)normalizeStashedGrabberLayout;
- (void)updateResizeHandleAppearance;
- (void)updateFloatingChromeAppearance;
- (void)layoutFloatingChromeForSize:(CGSize)size;
- (void)setChromeControlsExpanded:(BOOL)expanded animated:(BOOL)animated;
- (void)scheduleChromeControlsCollapse;
- (void)handleChromeControlTouchDown:(id)sender;
- (void)handleChromeControlTap:(id)sender;
- (void)attachMoveLongPressToChromeButton:(UIButton *)button;
- (UIButton *)chromeButtonWithTitle:(NSString *)title action:(SEL)action;
- (void)handleChromeCloseAction:(id)sender;
- (void)handleChromeMinimizeAction:(id)sender;
- (void)handleChromeModeAction:(id)sender;
- (void)toggleMultitaskingMenu;
- (void)dismissMultitaskingMenu;
- (void)handleFullscreenMenuAction:(id)sender;
- (void)handleCompactMenuAction:(id)sender;
- (void)handleCloseMenuAction:(id)sender;
- (UIButton *)multitaskingMenuButtonWithTitle:(NSString *)title symbol:(NSString *)symbol action:(SEL)action;
- (void)ensureLaunchSplashVisible;
- (void)dismissLaunchSplashAnimated;
- (void)enforcePortraitWindowGeometry;
- (void)applyInterfaceOrientation:(UIInterfaceOrientation)orientation force:(BOOL)force;
- (void)applyTrustedOrientationNow;
- (CGRect)visiblePortraitContentFrame;
- (CGRect)currentHostedSceneBounds;
- (BOOL)applyHostedSceneLayoutToSettings:(id)settings force:(BOOL)force;
- (BOOL)syncHostedSceneLayoutForce:(BOOL)force;
- (BOOL)applyForegroundSovereigntyToSettings:(id)settings clearDeactivation:(BOOL)clearDeactivation forceLayout:(BOOL)forceLayout;
- (void)stabilizeForegroundForWorkspaceTransition:(NSString *)reason;
@end

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
    
    if (CGRectContainsPoint(selfWindow.bounds, point)) return YES;
    
    CV3FloatingAppWindow *floatingWindow = (CV3FloatingAppWindow *)selfWindow;
    if (floatingWindow.rootTransformContainer &&
        CGRectContainsPoint(floatingWindow.rootTransformContainer.frame, point)) {
        return YES;
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

static void CV3StabilizeFloatingWindowsForWorkspaceTransition(NSString *reason) {
    if (!floatingWindows || floatingWindows.count == 0) return;

    NSArray *windowsSnapshot = [floatingWindows copy];
    for (CV3FloatingAppWindow *win in windowsSnapshot) {
        if (![win isKindOfClass:[CV3FloatingAppWindow class]] || win.isClosing || win.isStashed) continue;
        [win stabilizeForegroundForWorkspaceTransition:reason];
    }
}

static void CV3BeginWorkspaceTransitionProtection(NSString *reason) {
    if (!floatingWindows || floatingWindows.count == 0) return;

    CV3WorkspaceTransitionActive = YES;
    CV3WorkspaceTransitionProtectionToken++;
    NSUInteger token = CV3WorkspaceTransitionProtectionToken;

    CV3LogToFile(@"[Continuity] 开启 Workspace 转场保护: %@", reason ?: @"Unknown");
    CV3StabilizeFloatingWindowsForWorkspaceTransition(reason ?: @"Begin");

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (token != CV3WorkspaceTransitionProtectionToken) return;
        CV3WorkspaceTransitionActive = NO;
        CV3StabilizeFloatingWindowsForWorkspaceTransition(@"ProtectionTimeout");
        CV3LogToFile(@"[Continuity] Workspace 转场保护超时收尾");
    });
}

static void CV3EndWorkspaceTransitionProtection(NSString *reason) {
    if (!floatingWindows || floatingWindows.count == 0) return;

    CV3WorkspaceTransitionProtectionToken++;
    NSUInteger token = CV3WorkspaceTransitionProtectionToken;

    CV3StabilizeFloatingWindowsForWorkspaceTransition(reason ?: @"End");

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.35 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (token != CV3WorkspaceTransitionProtectionToken) return;
        CV3WorkspaceTransitionActive = NO;
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
@property (nonatomic, strong) CAGradientLayer *specularHighlight;
@property (nonatomic, strong) CMMotionManager *motionManager;
@property (nonatomic, strong) CADisplayLink *liquidDisplayLink;
@property (nonatomic, strong) UIView *bezierContainer;
@property (nonatomic, strong) CAShapeLayer *bezierLayer;
@property (nonatomic, strong) UIVisualEffectView *bezierBlur;
@property (nonatomic, strong) CALayer *cyanLayer;
@property (nonatomic, strong) CALayer *magentaLayer;
@property (nonatomic, strong) UIView *whiteFilter; 
@property (nonatomic, strong) UIView *dispersionContainer; 
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
@property (nonatomic, assign) BOOL isKeyboardVisible; 
@property (nonatomic, assign) BOOL observersRegistered;
@property (nonatomic, assign) BOOL hasBeenMoved;
@property (nonatomic, strong) UIView *dimmingView;
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
@property (nonatomic, strong) NSIndexPath *lastWaveHapticIndexPath;
@property (nonatomic, strong) CAShapeLayer *searchBackground;
@property (nonatomic, strong) UIScrollView *categoryBar; 
@property (nonatomic, copy) NSString *selectedCategory; 
@property (nonatomic, assign) CGAffineTransform baseRotationTransform; 
@property (nonatomic, strong) UIView *contrastBackdrop; 
@property (nonatomic, strong) CALayer *innerGlowLayer; 
@property (nonatomic, assign) CGPoint cachedTargetCenter; 
@property (nonatomic, assign) CGFloat currentDecoDX; 
@property (nonatomic, assign) CGFloat currentDecoDY; 
@property (nonatomic, assign) CGFloat baseRoll; 
@property (nonatomic, assign) CGFloat basePitch; 
@property (nonatomic, assign) BOOL hasCapturedBaseline; 

// 建议 1：光纤导光图层 (Fiber-Optic Glows)
@property (nonatomic, strong) CAGradientLayer *redGlow, *yellowGlow, *greenGlow;

#pragma mark - 创意：光学玻璃与引力场支持
@property (nonatomic, strong) UIView *refractionView; // 光学折射容器
@property (nonatomic, strong) CIFilter *distortionFilter; // 位移畸变滤镜
@property (nonatomic, assign) BOOL isMagneticLayoutActive; // 引力布局状态

// 建议 1-3：主动交互系统 (Active Interactive System)
@property (nonatomic, strong) CAShapeLayer *trailLayer; 
@property (nonatomic, strong) UIView *lightWaveView;
@property (nonatomic, assign) NSInteger interactionCount; 

// 终极融合系统属性
@property (nonatomic, strong) UIView *projectionView; // 呼吸投影层
@property (nonatomic, assign) BOOL isInPredictiveMode; // 交互黑洞预知模式
@property (nonatomic, assign) CGPoint lastVelocity; // 惯性偏移计算

// 拖拽分屏支持
@property (nonatomic, strong) UIImageView *draggedIconView;
@property (nonatomic, strong) CV3AppInfo *draggedAppInfo;
@property (nonatomic, assign) CGPoint dragStartCenter;
@property (nonatomic, assign) CGPoint dragTouchOffset; // 新增：记录触碰点与图标中心的偏移量

- (void)show;
- (void)loadAppsAsync;
- (void)applyBackgroundTint:(UIColor *)color;
- (NSString *)_role; 
- (void)triggerCollisionImpulse; 
- (void)updateMagneticLayout;
- (void)emitLightWaveFromPoint:(CGPoint)point;
- (void)applyAgingEffectToCell:(CV3AppCell *)cell withInfo:(CV3AppInfo *)info;
@end

static NSCache *cv3IconCache = nil; 
static CV3Window *sharedWindow = nil;

static CGFloat CGPointDistance(CGPoint p1, CGPoint p2) {
    return sqrt(pow(p1.x - p2.x, 2) + pow(p1.y - p2.y, 2));
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
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        UIImage *icon = [UIImage _applicationIconImageForBundleIdentifier:bundleId format:10 scale:[UIScreen mainScreen].scale];
        UIColor *avgColor = CV3AverageColorFromImage(icon);
        if (avgColor) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [sharedWindow applyBackgroundTint:avgColor];
            });
        }
    });
}

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
        
        UIVisualEffectView *blur = [[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemUltraThinMaterial]];
        blur.frame = self.bounds;
        [self addSubview:blur];
        
        UIScrollView *scroll = [[UIScrollView alloc] initWithFrame:self.bounds];
        scroll.showsHorizontalScrollIndicator = NO;
        [self addSubview:scroll];
        
        CGFloat x = 10;
        for (CV3AppInfo *info in apps) {
            UIButton *btn = [UIButton buttonWithType:UIButtonTypeCustom];
            btn.frame = CGRectMake(x, 10, 40, 40);
            btn.layer.cornerRadius = 10;
            btn.clipsToBounds = YES;
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

#import "CV3Window.inc"

static NSTimeInterval lastLogTime = 0;

%hook UIWindow
- (void)layoutSubviews {

    %orig;

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
        CV3LastTrustedInterfaceOrientation = currentOrientation;

        NSTimeInterval currentTime = [[NSDate date] timeIntervalSince1970];

        BOOL shouldLog = (currentTime - lastLogTime > 0.5);
        if (shouldLog) {
            lastLogTime = currentTime;

            CV3LogToFile(@"[Orientation] 采信并应用方向改变: %ld, 来源 Role: %@", (long)currentOrientation, role);
        }

        BOOL isLandscape = UIInterfaceOrientationIsLandscape(currentOrientation);
        CGAffineTransform targetRotation = CV3RotationTransformForInterfaceOrientation(currentOrientation);
        BOOL needsDispatch = NO;
        if (sharedWindow) {
            BOOL sharedIsLandscape = sharedWindow.bounds.size.width > sharedWindow.bounds.size.height;
            needsDispatch = (sharedWindow.targetOrientation != currentOrientation || sharedIsLandscape != isLandscape);
        }
        if (!needsDispatch && floatingWindows) {
            for (CV3FloatingAppWindow *win in floatingWindows) {
                if (![win isKindOfClass:[CV3FloatingAppWindow class]] || win.isClosing) continue;
                BOOL winRotationChanged = !CGAffineTransformEqualToTransform(win.baseRotationTransform, targetRotation);
                if (win.lastLayoutOrientation != currentOrientation || winRotationChanged) {
                    needsDispatch = YES;
                    break;
                }
            }
        }
        if (!needsDispatch) return;

        isUpdating = YES;
        // 使用异步确保当前 layout 周期执行完毕，避免重入导致的错位
        dispatch_async(dispatch_get_main_queue(), ^{
            @try {
                if (sharedWindow) {
                    BOOL sharedOrientationChanged = (sharedWindow.targetOrientation != currentOrientation);
                    BOOL currentIsLandscape = sharedWindow.bounds.size.width > sharedWindow.bounds.size.height;
                    if (sharedOrientationChanged || isLandscape != currentIsLandscape) {
                        sharedWindow.targetOrientation = currentOrientation;
                        if (isLandscape != currentIsLandscape) {
                            CGRect b = sharedWindow.bounds;
                            sharedWindow.bounds = CGRectMake(0, 0, b.size.height, b.size.width);
                        }
                        [sharedWindow attachToCurrentActiveScene];
                        [sharedWindow setNeedsLayout];
                    }
                }
                
                if (floatingWindows) {
                    for (CV3FloatingAppWindow *win in floatingWindows) {
                        if ([win isKindOfClass:[CV3FloatingAppWindow class]] && !win.isClosing) {
                            UIInterfaceOrientation previousOrientation = win.lastLayoutOrientation;
                            CGAffineTransform previousRotation = win.baseRotationTransform;
                            [win applyInterfaceOrientation:currentOrientation force:NO];
                            if (previousOrientation != currentOrientation ||
                                !CGAffineTransformEqualToTransform(previousRotation, win.baseRotationTransform)) {
                                [win attachToCurrentActiveScene];
                            }
                        }
                    }
                }
            } @catch (NSException *e) {
                CV3LogToFile(@"[Error] 方向同步队列异常: %@", e);
            }
            isUpdating = NO;
        });
    }
}
%end

#import "CV3WorkspaceSupport.h"

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
            if ([scene.identifier containsString:win.bundleID] && !win.isClosing) {
                CV3LogToFile(@"[Lifecycle] 系统尝试销毁托管场景 (%@)，已放行并准备自动恢复流程", win.bundleID);
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
    if ([arg1 respondsToSelector:@selector(source)]) {
        CV3LogToFile(@"[Workspace] 执行转换请求, Source: %ld", (long)[(SBMainWorkspaceTransitionRequest *)arg1 source]);
    }
    CV3BeginWorkspaceTransitionProtection(@"ExecuteTransitionRequest");
    %orig(arg1);
}

- (void)workspace:(id)arg1 didExecuteTransitionRequest:(id)arg2 {
    %orig;
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

%hook SpringBoard
- (void)applicationDidFinishLaunching:(id)application {
    %orig;

    if (sharedWindow) return;
    sharedWindow = [[CV3Window alloc] initWithFrame:[UIScreen mainScreen].bounds];
    sharedWindow.hidden = NO;
    sharedWindow.alpha = 1.0;
    [sharedWindow show];
}
%end

@interface CV3PassthroughWindow : UIWindow
@end
@implementation CV3PassthroughWindow
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *hitView = [super hitTest:point withEvent:event];
    if (hitView == self) return nil;
    return hitView;
}
@end

static CV3PassthroughWindow *cv3_keyboardWindow = nil;

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
            if (!cv3_keyboardWindow) {
                if (@available(iOS 15.0, *)) {
                    UIWindowScene *ws = nil;
                    for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
                        if ([scene isKindOfClass:[UIWindowScene class]]) {
                            ws = (UIWindowScene *)scene;
                            break;
                        }
                    }
                    cv3_keyboardWindow = [[CV3PassthroughWindow alloc] initWithWindowScene:ws];
                } else {
                    cv3_keyboardWindow = [[CV3PassthroughWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
                }
                cv3_keyboardWindow.windowLevel = CV3Style.keyboard;
                cv3_keyboardWindow.backgroundColor = [UIColor clearColor];
                cv3_keyboardWindow.hidden = NO;
            }
            if (subview.superview != cv3_keyboardWindow) {
                [subview removeFromSuperview];
                [cv3_keyboardWindow addSubview:subview];
            }
            subview.transform = CGAffineTransformIdentity;
            subview.frame = [UIScreen mainScreen].bounds;
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
    if (floatingWindows && floatingWindows.count > 0) {
        for (CV3FloatingAppWindow *win in floatingWindows) {
            if ([self.bundleIdentifier isEqualToString:win.bundleID] && !win.isClosing) {
                // 如果窗口被 Stash (侧边隐藏)，允许应用进入正常的后台挂起状态，减少 CPU/内存压力
                if (win.isStashed) return %orig;
                return NO; // 核心：欺骗系统，让其认为该 App 始终在“前台”运行
            }
        }
    }
    return %orig;
}

- (BOOL)isSuspended {
    if (floatingWindows && floatingWindows.count > 0) {
        for (CV3FloatingAppWindow *win in floatingWindows) {
            if ([self.bundleIdentifier isEqualToString:win.bundleID] && !win.isClosing) {
                if (win.isStashed) return %orig;
                return NO; 
            }
        }
    }
    return %orig;
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
    if (floatingWindows) {
        for (CV3FloatingAppWindow *win in floatingWindows) {
            if ([self.identifier containsString:win.bundleID] && !win.isClosing) {
                // 如果窗口被 Stash (侧边隐藏)，且系统正在尝试将其置于后台，我们不再强制拉回前台
                // 这能有效避免系统判定应用“违规占据前台”而触发的杀进程行为 (0xDEAD10CC)
                if (win.isStashed) {
                    %orig(arg1, arg2);
                    return;
                }

                id mutableSettings = [arg1 mutableCopy];
                BOOL isTransitioning = (arg2 != nil);
                BOOL clearDeactivation = (!isTransitioning || CV3WorkspaceTransitionActive);
                BOOL modified = [win applyForegroundSovereigntyToSettings:mutableSettings
                                                         clearDeactivation:clearDeactivation
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
    if (floatingWindows) {
        for (CV3FloatingAppWindow *win in floatingWindows) {
            if ([self.identifier containsString:win.bundleID] && !win.isClosing) {
                if (win.isStashed) {
                    %orig(arg1, arg2, arg3);
                    return;
                }

                id mutableSettings = [arg1 mutableCopy];
                BOOL isTransitioning = (arg2 != nil);
                BOOL clearDeactivation = (!isTransitioning || CV3WorkspaceTransitionActive);
                BOOL modified = [win applyForegroundSovereigntyToSettings:mutableSettings
                                                         clearDeactivation:clearDeactivation
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
    if (floatingWindows) {
        for (CV3FloatingAppWindow *win in floatingWindows) {
            if ([self.identifier containsString:win.bundleID] && !win.isClosing) {
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
            if ([self.identifier containsString:win.bundleID] && !win.isClosing) {
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
