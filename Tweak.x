#import <UIKit/UIKit.h>
#import <CoreMotion/CoreMotion.h>
#import <QuartzCore/QuartzCore.h>
#import <AudioToolbox/AudioToolbox.h>
#import <objc/runtime.h>
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
        ivBack.layer.cornerRadius = 13;
        ivBack.layer.shadowColor = [UIColor blackColor].CGColor;
        ivBack.layer.shadowOffset = CGSizeMake(0, 3);
        ivBack.layer.shadowOpacity = 0.3;
        ivBack.layer.shadowRadius = 5.0;
        [self.contentView addSubview:ivBack];
        
        self.iconView = [[UIImageView alloc] initWithFrame:ivBack.frame];
        self.iconView.layer.cornerRadius = 13;
        self.iconView.clipsToBounds = YES;
        [self.contentView addSubview:self.iconView];

        self.iconHighlight = [CAGradientLayer layer];
        self.iconHighlight.frame = self.iconView.bounds;
        self.iconHighlight.colors = @[(id)[[UIColor labelColor] colorWithAlphaComponent:0.0].CGColor,
                                      (id)[[UIColor labelColor] colorWithAlphaComponent:0.35].CGColor,
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
        self.pinnedIndicator.hidden = YES;
        [self.iconView addSubview:self.pinnedIndicator];

        self.nameLabel = [[UILabel alloc] initWithFrame:CGRectMake(4, iconSize + 14, frame.size.width - 8, 28)];
        self.nameLabel.textColor = [UIColor labelColor];
        self.nameLabel.font = [UIFont systemFontOfSize:10.0 weight:UIFontWeightMedium];
        self.nameLabel.textAlignment = NSTextAlignmentCenter;
        self.nameLabel.numberOfLines = 2;
        [self.contentView addSubview:self.nameLabel];
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

    [self startBreathing];
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

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
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
struct {
    CGFloat maxBound;
    CGFloat floatingApp;
    CGFloat panel;
    CGFloat background;
    CGFloat keyboard;
} static const kChevronWindowLevels = {
    .maxBound = 2100.0,
    .floatingApp = 2098.5,
    .panel = 2099.0,
    .background = -1.0,
    .keyboard = 10000.0
};

#pragma mark - Layout & Physics Constants
struct {
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
    CGFloat resizeHandleHitArea;
    CGFloat resizeHandleWindowExpansion;
} static const kChevronLayoutConstants = {
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
    .windowHandleW = 44.0,
    .windowHandleH = 6.0,
    .resizeHandleHitArea = 140.0,
    .resizeHandleWindowExpansion = 80.0
};

struct {
    CGFloat parallaxPanelFactor;
    CGFloat parallaxDecoFactor;
    CGFloat lerpFactor;
    CGFloat hapticThreshold;
    CGFloat tiltMaxAngle;
    CGFloat scrollTiltFactor;
    CGFloat momentumDamping;
    CGFloat maxStretch;
    CGFloat stretchDamping;
} static const kChevronPhysicsConstants = {
    .parallaxPanelFactor = 8.0,
    .parallaxDecoFactor = 11.0,
    .lerpFactor = 0.15,
    .hapticThreshold = 0.6,
    .tiltMaxAngle = 0.12,
    .scrollTiltFactor = 0.0015,
    .momentumDamping = 0.92,
    .maxStretch = 0.12,
    .stretchDamping = 3500.0
};

struct {
    CGFloat durationShort;
    CGFloat durationMedium;
    CGFloat durationLong;
    CGFloat springDamping;
    CGFloat springVelocity;
} static const __attribute__((unused)) kChevronAnimationConstants = {
    .durationShort = 0.15,
    .durationMedium = 0.3,
    .durationLong = 0.5,
    .springDamping = 0.6,
    .springVelocity = 0.8
};

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

@interface CV3FloatingAppWindow : UIWindow <UIGestureRecognizerDelegate>
@property (nonatomic, copy) NSString *bundleID;
@property (nonatomic, strong) UIVisualEffectView *glassBackdrop; // New: Fluid background
@property (nonatomic, strong) UIView *rootTransformContainer;
@property (nonatomic, strong) UIView *clippingContainer; 
@property (nonatomic, strong) UIView *hostContainerProxy;
@property (nonatomic, strong) UIView *hostView;
@property (nonatomic, strong) UIView *resizeHandle;
@property (nonatomic, strong) CAShapeLayer *resizeHandleLayer;
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
@property (nonatomic, assign) CGPoint lastVelocity;
@property (nonatomic, strong) UIView *crystalPreviewContainer;
@property (nonatomic, strong) UIView *splashView;
@property (nonatomic, strong) UIImageView *largeSplashIcon;
@property (nonatomic, assign) UIInterfaceOrientation targetOrientation;
@property (nonatomic, assign) UIInterfaceOrientation lastLayoutOrientation;
@property (nonatomic, assign) CGAffineTransform baseRotationTransform;
@property (nonatomic, strong) UIView *liveResizeSnapshotView;
@property (nonatomic, strong) RBSAssertion *rbsAssertion; 

- (instancetype)initWithBundleID:(NSString *)bundleID center:(CGPoint)center windowScene:(UIWindowScene *)windowScene;
- (void)triggerCollisionImpulse;
- (void)updateAdaptiveColor;
- (void)setWindowFocused:(BOOL)focused;
- (void)restoreFromStash;
- (void)applyCurrentTransformWithScale:(CGFloat)scale;
@end

// --- Custom Resize Handle with Expanded Hit Area ---
@interface CV3ResizeHandleView : UIView
@end
@implementation CV3ResizeHandleView
- (BOOL)pointInside:(CGPoint)point withEvent:(UIEvent *)event {
    // 深度优化敏感度：使用全局常量扩充热区，确保盲操作也能精准捕捉
    CGFloat hitArea = kChevronLayoutConstants.resizeHandleHitArea;
    CGFloat widthDelta = MAX(0, hitArea - self.bounds.size.width);
    CGFloat heightDelta = MAX(0, hitArea - self.bounds.size.height);
    CGRect hitFrame = CGRectInset(self.bounds, -widthDelta/2.0, -heightDelta/2.0);
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

// 核心增强：允许触控溢出窗口边界 (针对缩放把手)
- (BOOL)pointInside:(CGPoint)point withEvent:(UIEvent *)event {
    if (![self isKindOfClass:[CV3FloatingAppWindow class]]) return %orig;
    
    if (CGRectContainsPoint(self.bounds, point)) return YES;
    
    // 专门为右下角缩放把手留出外部“吸附热区”
    // 使用 kChevronLayoutConstants.resizeHandleWindowExpansion 确保与把手热区同步
    // 我们将捕捉范围扩大到以右下角为顶点的正方形区域，确保手指即便在窗口外很远也能“吸住”
    CGRect bounds = self.bounds;
    CGFloat expansion = kChevronLayoutConstants.resizeHandleWindowExpansion;
    CGRect resizeExtraHitBox = CGRectMake(bounds.size.width - expansion, bounds.size.height - expansion, expansion * 2, expansion * 2);
    if (CGRectContainsPoint(resizeExtraHitBox, point)) return YES;
    
    return NO;
}
%end

@implementation CV3FloatingAppWindow
- (instancetype)initWithBundleID:(NSString *)bundleID center:(CGPoint)center windowScene:(UIWindowScene *)windowScene {
    if (windowScene) {
        self = [super initWithWindowScene:windowScene];
    } else {
        self = [super initWithFrame:CGRectMake(0, 0, 300, 500)];
    }
    
    if (self) {
        CGRect screen = [UIScreen mainScreen].bounds;
        // 始终获取竖屏比例作为基准计算，确保弹出的窗口比例正确
        CGFloat portraitW = MIN(screen.size.width, screen.size.height);
        CGFloat portraitH = MAX(screen.size.width, screen.size.height);
        
        // 默认逻辑尺寸：宽占屏幕 45%，高按屏幕比例缩放
        CGFloat logicalW = portraitW * 0.45;
        CGFloat logicalH = logicalW * (portraitH / portraitW);
        
        UIInterfaceOrientation currentOrientation = windowScene ? windowScene.interfaceOrientation : UIInterfaceOrientationPortrait;
        BOOL isLandscape = UIInterfaceOrientationIsLandscape(currentOrientation);
        
        // 物理尺寸
        CGFloat physicalW = isLandscape ? logicalH : logicalW;
        CGFloat physicalH = isLandscape ? logicalW : logicalH;
        
        self.frame = CGRectMake(0, 0, physicalW, physicalH);
        self.lastLayoutOrientation = currentOrientation;
        self.targetOrientation = currentOrientation;
        
        self.bundleID = bundleID;
        self.center = center;
        self.windowLevel = kChevronWindowLevels.floatingApp; // 覆盖在面板之上，但不超过控制中心 (kChevronWindowLevels.maxBound)
        self.backgroundColor = [UIColor clearColor];
        self.alpha = 1.0;
        
        // 动态阴影容器
        self.layer.shadowColor = [UIColor blackColor].CGColor;
        self.layer.shadowOffset = CGSizeMake(0, 10);
        self.layer.shadowOpacity = 0.4;
        self.layer.shadowRadius = 20.0;
        self.layer.cornerRadius = kChevronLayoutConstants.cornerRadius;
        if (@available(iOS 13.0, *)) {
            self.layer.cornerCurve = kCACornerCurveContinuous;
        }
        
        // 核心修复：引入旋转根容器 (Root Transform Container)
        // 该容器用于隔离系统 UIWindow 的 Transform 问题，承载全方位的视觉旋转
        self.rootTransformContainer = [[UIView alloc] initWithFrame:self.bounds];
        self.rootTransformContainer.backgroundColor = [UIColor clearColor];
        [self addSubview:self.rootTransformContainer];

        // 核心修复：引入非缩放裁剪层 (Clipping Container)
        // 该层的大小始终等于窗口大小，负责强制执行圆角裁剪，不受内部缩放影响
        self.clippingContainer = [[UIView alloc] initWithFrame:self.bounds];
        self.clippingContainer.layer.cornerRadius = kChevronLayoutConstants.cornerRadius;
        if (@available(iOS 13.0, *)) {
            self.clippingContainer.layer.cornerCurve = kCACornerCurveContinuous;
        }
        self.clippingContainer.layer.masksToBounds = YES;
        self.clippingContainer.backgroundColor = [UIColor clearColor];
        [self.rootTransformContainer addSubview:self.clippingContainer];

        // 核心修复：引入液态玻璃背景 (已移入 clippingContainer 以实现完美剪裁)
        self.glassBackdrop = [[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemThinMaterial]];
        self.glassBackdrop.frame = self.clippingContainer.bounds;
        self.glassBackdrop.layer.cornerRadius = kChevronLayoutConstants.cornerRadius;
        if (@available(iOS 13.0, *)) {
            self.glassBackdrop.layer.cornerCurve = kCACornerCurveContinuous;
        }
        self.glassBackdrop.layer.masksToBounds = YES;
        self.glassBackdrop.backgroundColor = [UIColor clearColor];
        [self.clippingContainer insertSubview:self.glassBackdrop atIndex:0];

        // 代理容器：用来隔离系统的布局覆盖，承载真实的缩放和裁剪
        self.hostContainerProxy = [[UIView alloc] initWithFrame:self.bounds];
        self.hostContainerProxy.backgroundColor = [UIColor clearColor];
        // 核心修复：应用三线性过滤 (Trilinear Filtering)
        // 在非整数缩放比下，三线性过滤能显著减少文本和细线的锯齿，提升渲染清晰度
        self.hostContainerProxy.layer.magnificationFilter = kCAFilterTrilinear;
        self.hostContainerProxy.layer.minificationFilter = kCAFilterTrilinear;
        
        [self.clippingContainer addSubview:self.hostContainerProxy];

        // --- Liquid Glass Visuals (Moved to clippingContainer to maintain structural integrity during fluid drags) ---
        self.innerGlowLayer = [CALayer layer];
        self.innerGlowLayer.frame = self.clippingContainer.bounds;
        self.innerGlowLayer.borderColor = [[UIColor labelColor] colorWithAlphaComponent:0.45].CGColor;
        self.innerGlowLayer.borderWidth = 0.3;
        self.innerGlowLayer.cornerRadius = kChevronLayoutConstants.cornerRadius;
        if (@available(iOS 13.0, *)) {
            self.innerGlowLayer.cornerCurve = kCACornerCurveContinuous;
        }
        [self.clippingContainer.layer addSublayer:self.innerGlowLayer];

        self.cyanLayer = [CALayer layer];
        self.cyanLayer.frame = self.clippingContainer.bounds;
        self.cyanLayer.borderColor = [[UIColor cyanColor] colorWithAlphaComponent:0.15].CGColor;
        self.cyanLayer.borderWidth = 0.4;
        self.cyanLayer.cornerRadius = kChevronLayoutConstants.cornerRadius;
        if (@available(iOS 13.0, *)) {
            self.cyanLayer.cornerCurve = kCACornerCurveContinuous;
        }
        [self.clippingContainer.layer addSublayer:self.cyanLayer];

        self.magentaLayer = [CALayer layer];
        self.magentaLayer.frame = self.clippingContainer.bounds;
        self.magentaLayer.borderColor = [[UIColor magentaColor] colorWithAlphaComponent:0.15].CGColor;
        self.magentaLayer.borderWidth = 0.4;
        self.magentaLayer.cornerRadius = kChevronLayoutConstants.cornerRadius;
        if (@available(iOS 13.0, *)) {
            self.magentaLayer.cornerCurve = kCACornerCurveContinuous;
        }
        [self.clippingContainer.layer addSublayer:self.magentaLayer];
        
        // 右下角缩放与移动把手 (同心圆/Stage Manager 风格)
        self.resizeHandle = [[CV3ResizeHandleView alloc] initWithFrame:CGRectMake(260, 460, 60, 60)];
        self.resizeHandle.backgroundColor = [UIColor clearColor]; // 已通过 CV3ResizeHandleView 优化热区，无需背景色即可接收触控
        [self.rootTransformContainer addSubview:self.resizeHandle];
        
        self.resizeHandleLayer = [CAShapeLayer layer];
        self.resizeHandleLayer.strokeColor = [[UIColor whiteColor] colorWithAlphaComponent:0.3].CGColor;
        self.resizeHandleLayer.fillColor = [UIColor clearColor].CGColor;
        self.resizeHandleLayer.lineWidth = 2.0;
        self.resizeHandleLayer.lineCap = kCALineCapRound;
        [self.resizeHandle.layer addSublayer:self.resizeHandleLayer];
        
        // 1. 缩放手势 (Pan)
        UIPanGestureRecognizer *resizePan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handleResizePan:)];
        resizePan.delegate = self;
        [self.resizeHandle addGestureRecognizer:resizePan];

        // 2. 移动手势 (Long Press)
        // 核心移植：将原本顶部的拖拽功能集成到把手上，通过长按触发移动
        UILongPressGestureRecognizer *moveLongPress = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(handleMoveLongPress:)];
        moveLongPress.minimumPressDuration = 0.45; // 稍微长于普通点击，短于 Stash 关闭
        moveLongPress.delegate = self;
        [self.resizeHandle addGestureRecognizer:moveLongPress];

        // 3. 隐藏手势 (Tap)
        UITapGestureRecognizer *resizeTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleHideAction)];
        resizeTap.delegate = self;
        [self.resizeHandle addGestureRecognizer:resizeTap];
        
        // 确保 Pan 手势在长按触发移动时失败，防止缩放与位移冲突
        [resizePan requireGestureRecognizerToFail:moveLongPress];
        
        self.resizeHandle.userInteractionEnabled = YES;
        
        // 侧边隐藏拉手 (Grabber -> Prism Switcher)
        self.stashGrabber = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 44, 44)]; // Wider for icon
        self.stashGrabber.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.3];
        self.stashGrabber.layer.cornerRadius = 12;
        self.stashGrabber.layer.borderWidth = 0.5;
        self.stashGrabber.layer.borderColor = [[UIColor whiteColor] colorWithAlphaComponent:0.2].CGColor;
        self.stashGrabber.alpha = 0; // 初始隐藏
        [self.rootTransformContainer addSubview:self.stashGrabber];

        self.appIconMiniView = [[UIImageView alloc] initWithFrame:CGRectMake(4, 4, 36, 36)];
        self.appIconMiniView.layer.cornerRadius = 8;
        self.appIconMiniView.clipsToBounds = YES;
        [self.stashGrabber addSubview:self.appIconMiniView];

        UITapGestureRecognizer *restoreTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleRestoreTap:)];
        [self.stashGrabber addGestureRecognizer:restoreTap];

        UIPanGestureRecognizer *restorePan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handleStashPan:)];
        [self.stashGrabber addGestureRecognizer:restorePan];

        // 核心功能：长按结束分屏
        UILongPressGestureRecognizer *stashClose = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(handleStashLongPress:)];
        stashClose.minimumPressDuration = 0.8; 
        [self.stashGrabber addGestureRecognizer:stashClose];

        self.stashGrabber.userInteractionEnabled = YES;
        // Snap Preview View (Hidden by default)
        self.snapPreviewView = [[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemUltraThinMaterial]];
        self.snapPreviewView.backgroundColor = [[UIColor cyanColor] colorWithAlphaComponent:0.1];
        self.snapPreviewView.layer.cornerRadius = kChevronLayoutConstants.cornerRadius;
        self.snapPreviewView.layer.masksToBounds = YES;
        self.snapPreviewView.layer.borderWidth = 1.5;
        self.snapPreviewView.layer.borderColor = [[UIColor cyanColor] colorWithAlphaComponent:0.3].CGColor;
        self.snapPreviewView.alpha = 0;

        [self clampToScreenBounds];
        [self updateAdaptiveColor];

        // --- Setup Splash View (App Startup Experience) ---
        CGRect screenBounds = [UIScreen mainScreen].bounds;
        self.splashView = [[UIView alloc] initWithFrame:screenBounds];
        self.splashView.backgroundColor = [UIColor clearColor];
        self.splashView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        [self.hostContainerProxy addSubview:self.splashView];

        UIVisualEffectView *splashBlur = [[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemThinMaterial]];
        splashBlur.frame = self.splashView.bounds;
        splashBlur.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        [self.splashView addSubview:splashBlur];

        self.largeSplashIcon = [[UIImageView alloc] initWithFrame:CGRectMake(0, 0, 80, 80)];
        self.largeSplashIcon.center = CGPointMake(screenBounds.size.width/2.0, screenBounds.size.height/2.0);
        self.largeSplashIcon.layer.cornerRadius = 18;
        self.largeSplashIcon.clipsToBounds = YES;
        self.largeSplashIcon.alpha = 0; // 初始透明，由 updateAdaptiveColor 激活
        [self.splashView addSubview:self.largeSplashIcon];

        // 启动时的呼吸缩放动画
        CABasicAnimation *pulse = [CABasicAnimation animationWithKeyPath:@"transform.scale"];
        pulse.fromValue = @0.95;
        pulse.toValue = @1.05;
        pulse.duration = 1.2;
        pulse.autoreverses = YES;
        pulse.repeatCount = HUGE_VALF;
        [self.largeSplashIcon.layer addAnimation:pulse forKey:@"splashPulse"];

        [self loadAppScene];
        
        // Auto-focus on creation
        [self setWindowFocused:YES];

        // 核心修复：监听 Scene 变更与系统通知，确保窗口持久存在
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(attachToCurrentActiveScene) name:UISceneDidActivateNotification object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(enforceSceneForegroundState) name:UISceneDidEnterBackgroundNotification object:nil];
    }
    return self;
}

- (void)setHidden:(BOOL)hidden {
    // 核心修复：禁止系统强制隐藏窗口（除非是明确的关闭操作或 Stash）
    if (hidden && !self.isStashed && !self.isClosing) {
        CV3LogToFile(@"[Visibility] 拦截系统隐藏请求: %@", self.bundleID);
        [super setHidden:NO];
        [self attachToCurrentActiveScene];
        return;
    }
    CV3LogToFile(@"[Visibility] 窗口 Hidden 状态变更 -> %d: %@", hidden, self.bundleID);
    [super setHidden:hidden];
}

- (void)attachToCurrentActiveScene {
    CV3LogToFile(@"[Scene] 开始尝试同步挂载场景: %@", self.bundleID);
    @try {
        UIWindowScene *targetScene = nil;
        
        // 1. 终极优先：获取 SpringBoard 核心主场景 (SBWindowSceneSessionRoleMain)
        if ([NSClassFromString(@"SBWindowScene") respondsToSelector:@selector(mainDisplayWindowScene)]) {
            targetScene = [NSClassFromString(@"SBWindowScene") performSelector:@selector(mainDisplayWindowScene)];
        }
        
        // 2. 备选方案：遍历场景并严格过滤非显示角色
        if (!targetScene) {
            for (UIScene *scene in [[UIApplication sharedApplication].connectedScenes allObjects]) {
                if ([scene isKindOfClass:[UIWindowScene class]]) {
                    UIWindowScene *ws = (UIWindowScene *)scene;
                    NSString *role = ws.session.role;
                    
                    // 核心修正：严格排除灵动岛相关的幕帘场景
                    // 这些场景在上滑 Home 条时会活跃，但会导致我们的窗口被系统优化掉
                    if ([role containsString:@"Aperture"] || [role containsString:@"Curtain"]) {
                        continue;
                    }
                    
                    if (ws.activationState == UISceneActivationStateForegroundActive) {
                        targetScene = ws;
                        break;
                    }
                }
            }
        }
        
        // 3. 强制同步场景挂载。
        if (targetScene && (self.windowScene != targetScene || !self.windowScene)) {
            NSString *role = targetScene.session.role ?: @"Unknown";
            CV3LogToFile(@"[Scene] 成功将窗口 (%@) 挂载至主场景: %@ (Role: %@)", self.bundleID, targetScene, role);
            self.windowScene = targetScene;
            [self setHidden:NO];
            [self setNeedsLayout];
            [self layoutIfNeeded];
        } else if (!targetScene) {
            CV3LogToFile(@"[Scene] 警告：未能找到可用的显示级 targetScene: %@", self.bundleID);
        }
        
        // 4. 无论如何，强制维持内部 App 场景的活跃状态
        [self enforceSceneForegroundState];
    } @catch (NSException *e) {
        CV3LogToFile(@"[Error] attachToCurrentActiveScene 异常: %@", e);
    }
}

- (void)refreshHostViewPresentation {
    if (!self.targetScene || !self.hostView) {
        return;
    }
    
    @try {
        // 核心修复：使用更全面的层级位掩码 (31 = 1|2|4|8|16)
        // Bit 0 (1) 是主画面层，之前使用的 26 缺少了主画面位，可能导致某些转场后画面无法刷新
        UIScenePresentationContext *context = [[%c(UIScenePresentationContext) alloc] _initWithDefaultValues];
        if ([context respondsToSelector:@selector(setPresentedLayerTypes:)]) {
            [context setPresentedLayerTypes:31]; 
        }
        if ([context respondsToSelector:@selector(setAppearanceStyle:)]) {
            [context setAppearanceStyle:2];
        }
        if ([context respondsToSelector:@selector(setClipsToBounds:)]) {
            [context setClipsToBounds:YES];
        }
        
        if ([self.hostView respondsToSelector:@selector(_setPresentationContext:)]) {
            [self.hostView performSelector:@selector(_setPresentationContext:) withObject:context];
        }
        
        self.hostView.alpha = 1.0;
        self.hostView.hidden = NO;
        
    } @catch (NSException *e) {
        CV3LogToFile(@"[Error] 热刷新渲染失败: %@", e);
    }
}

- (void)enforceSceneForegroundState {
    if (!self.targetScene) return;
    
    @try {
        // 核心增强：除了检查 isValid，还检查是否还在连接状态
        BOOL sceneValid = [self.targetScene respondsToSelector:@selector(isValid)] ? [(id)self.targetScene isValid] : YES;
        
        if (!sceneValid) {
            CV3LogToFile(@"[Recovery] 场景失效，触发重连机制: %@", self.bundleID);
            if (self.hostView) {
                [self.hostView removeFromSuperview];
                self.hostView = nil;
            }
            [self loadAppScene];
            return;
        }

        // 预防性重置：如果检测到 HostView 存在但可能已“冻结”，强制触发层级重新同步
        if (self.hostView && self.hostView.superview) {
            // 通过检查渲染层级是否还具备 Presentation Context 来判断冻结
            if ([self.hostView respondsToSelector:@selector(presentationContext)] && ![self.hostView performSelector:@selector(presentationContext)]) {
                CV3LogToFile(@"[Recovery] 检测到 HostView 渲染层断连，强制修复: %@", self.bundleID);
                [self.hostView removeFromSuperview];
                [self attemptToHostSceneWithRetries:1 delay:0]; // 快速尝试重建
                return;
            }
        }

        FBSMutableSceneSettings *settings = [[self.targetScene settings] mutableCopy];
        BOOL needsUpdate = NO;
        
        // 兼容性检查：优先通过 KVC 获取
        BOOL currentBackgrounded = YES;
        @try {
            currentBackgrounded = [[settings valueForKey:@"backgrounded"] boolValue];
        } @catch (NSException *e) {}

        if (currentBackgrounded) {
            CV3LogToFile(@"[Lifecycle] 检测到 App 被设为 Backgrounded，强制拉回: %@", self.bundleID);
            [settings setBackgrounded:NO];
            needsUpdate = YES;
        }

        @try {
            BOOL currentForeground = [[settings valueForKey:@"foreground"] boolValue];
            if (!currentForeground) {
                CV3LogToFile(@"[Lifecycle] 检测到 App 被设为非 Foreground，强制拉回: %@", self.bundleID);
                [settings setForeground:YES];
                needsUpdate = YES;
            }
        } @catch (NSException *e) {}
        
        if (needsUpdate) {
            // [Foreground Sovereignty] Final Hardening: Force occluded=NO and visibility=2 to ensure hardware access (Camera/Mic)
            @try {
                if ([settings respondsToSelector:@selector(setOccluded:)]) {
                    [settings setValue:@NO forKey:@"occluded"];
                }
                if ([settings respondsToSelector:@selector(setVisibility:)]) {
                    [settings setValue:@2 forKey:@"visibility"];
                }
                // 禁止分屏 App 触发自动锁屏
                if ([settings respondsToSelector:@selector(setIdleTimerDisabled:)]) {
                    [settings setValue:@YES forKey:@"idleTimerDisabled"];
                }
                
                // [Foreground Sovereignty] Force interruptionPolicy to 1 (Suppress)
                // This is critical for camera/mic apps and video playback to prevent the system from pausing capture/playback.
                if ([settings respondsToSelector:@selector(setInterruptionPolicy:)]) {
                    [settings setInterruptionPolicy:1];
                } else {
                    @try { [settings setValue:@1 forKey:@"interruptionPolicy"]; } @catch (NSException *e) {}
                }

                // [Deactivation Immunity] Clear deactivationReasons in foreground enforcement
                if ([settings respondsToSelector:@selector(setDeactivationReasons:)]) {
                    @try { [settings setValue:@0 forKey:@"deactivationReasons"]; } @catch (NSException *e) {}
                }
            } @catch (NSException *e) {}

            [self.targetScene updateSettings:settings withTransitionContext:nil];
            if ([self.targetScene respondsToSelector:@selector(_setContentState:)]) {
                [self.targetScene _setContentState:2]; 
            }
            
            // [Optimization] 只有在设置真正发生变更时，才重置 Presentation Context。
            // 避免在每个 Scene 背景化通知中都触发 Context 重置，减少画面暂停的可能性。
            if (self.hostView && [self.hostView respondsToSelector:@selector(_setPresentationContext:)]) {
                UIScenePresentationContext *context = [[%c(UIScenePresentationContext) alloc] _initWithDefaultValues];
                if ([context respondsToSelector:@selector(setPresentedLayerTypes:)]) [context setPresentedLayerTypes:31];
                if ([context respondsToSelector:@selector(setAppearanceStyle:)]) [context setAppearanceStyle:2];
                if ([context respondsToSelector:@selector(setClipsToBounds:)]) [context setClipsToBounds:YES];
                [self.hostView performSelector:@selector(_setPresentationContext:) withObject:context];
                CV3LogToFile(@"[Lifecycle] 已同步更新 %@ 渲染上下文", self.bundleID);
            }
        }
    } @catch (NSException *e) {
        CV3LogToFile(@"[Error] enforceSceneForegroundState 异常: %@", e);
    }
}

- (void)updateSovereigntyAssertion {
    if (!self.bundleID || self.isClosing) return;

    @try {
        if (self.rbsAssertion) {
            [self.rbsAssertion invalidate];
            self.rbsAssertion = nil;
        }

        RBSProcessIdentity *identity = [%c(RBSProcessIdentity) identityForEmbeddedApplicationIdentifier:self.bundleID];
        RBSTarget *target = [%c(RBSTarget) targetWithProcessIdentity:identity];
        
        // 动态决策优先级：
        // 1. 活跃聚焦 (isFocused): UserInteractive (最高优，模拟当前前台 App)
        // 2. 隐藏挂起 (isStashed): UserInitiated (中优，防止被强杀但允许 CPU 降频)
        // 3. 普通分屏: UserInteractive (维持渲染流畅)
        NSString *attributeName = (self.isStashed) ? @"UserInitiated" : @"UserInteractive";
        
        RBSDomainAttribute *attr = [%c(RBSDomainAttribute) attributeWithDomain:@"com.apple.common" name:attributeName];
        
        self.rbsAssertion = [[%c(RBSAssertion) alloc] initWithExplanation:[NSString stringWithFormat:@"ChevronV3 Sovereignty (%@) for %@", attributeName, self.bundleID] 
                                                                   target:target 
                                                               attributes:@[attr]];
        
        NSError *error = nil;
        if ([self.rbsAssertion acquireWithError:&error]) {
            CV3LogToFile(@"[Immortality] 已动态更新 %@ 优先级断连 -> %@", self.bundleID, attributeName);
        } else {
            CV3LogToFile(@"[Error] RBSAssertion (%@) 更新失败: %@", attributeName, error);
        }
    } @catch (NSException *e) {
        CV3LogToFile(@"[Error] updateSovereigntyAssertion 异常: %@", e);
    }
}

- (void)setWindowFocused:(BOOL)focused {
    if (self.isFocused == focused) return;
    self.isFocused = focused;
    
    [self updateSovereigntyAssertion]; // 同步更新优先级
    
    [UIView animateWithDuration:0.5 delay:0 usingSpringWithDamping:0.8 initialSpringVelocity:0.5 options:UIViewAnimationOptionBeginFromCurrentState animations:^{
        if (focused) {
            [self applyCurrentTransformWithScale:1.02];
            self.layer.shadowOpacity = 0.7;
            self.layer.shadowRadius = 30.0;
            self.hostContainerProxy.alpha = 1.0;
            
            // Focus Pulse for Inner Glow
            CABasicAnimation *pulse = [CABasicAnimation animationWithKeyPath:@"opacity"];
            pulse.fromValue = @0.4;
            pulse.toValue = @1.0;
            pulse.duration = 1.5;
            pulse.autoreverses = YES;
            pulse.repeatCount = HUGE_VALF;
            [self.innerGlowLayer addAnimation:pulse forKey:@"focusPulse"];
        } else {
            [self applyCurrentTransformWithScale:1.0];
            self.layer.shadowOpacity = 0.4;
            self.layer.shadowRadius = 20.0;
            self.hostContainerProxy.alpha = 0.85; // Dim inactive windows
            [self.innerGlowLayer removeAnimationForKey:@"focusPulse"];
        }
    } completion:nil];
    
    if (focused) {
        [self makeKeyAndVisible];
        // Dim other windows
        for (CV3FloatingAppWindow *win in floatingWindows) {
            if (win != self && [win isKindOfClass:[CV3FloatingAppWindow class]]) [win setWindowFocused:NO];
        }
    }
}

- (void)handleGrabberLongPress:(UILongPressGestureRecognizer *)gesture {
    if (gesture.state == UIGestureRecognizerStateBegan) {
        UIImpactFeedbackGenerator *gen = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleHeavy];
        [gen impactOccurred];
        
        // Show Thumbnail Preview (Crystal Switcher)
        if (!self.crystalPreviewContainer) {
            self.crystalPreviewContainer = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 120, 200)];
            self.crystalPreviewContainer.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.4];
            self.crystalPreviewContainer.layer.cornerRadius = 15;
            self.crystalPreviewContainer.layer.borderWidth = 0.5;
            self.crystalPreviewContainer.layer.borderColor = [self.adaptiveAppColor colorWithAlphaComponent:0.5].CGColor;
            self.crystalPreviewContainer.clipsToBounds = YES;
            
            UIView *preview = [[UIView alloc] initWithFrame:self.crystalPreviewContainer.bounds];
            preview.backgroundColor = self.adaptiveAppColor;
            preview.alpha = 0.3;
            [self.crystalPreviewContainer addSubview:preview];
            
            UIImageView *icon = [[UIImageView alloc] initWithFrame:CGRectMake(40, 80, 40, 40)];
            icon.image = self.appIconMiniView.image;
            [self.crystalPreviewContainer addSubview:icon];
        }
        
        CGPoint grabberPos = [self.stashGrabber.superview convertPoint:self.stashGrabber.center toView:nil];
        
        self.crystalPreviewContainer.center = CGPointMake(self.stashedSide == 1 ? grabberPos.x + 100 : grabberPos.x - 100, grabberPos.y);
        self.crystalPreviewContainer.alpha = 0;
        self.crystalPreviewContainer.transform = CGAffineTransformMakeScale(0.5, 0.5);
        
        UIWindow *keyWin = nil;
        if (@available(iOS 15.0, *)) {
            keyWin = self.windowScene.keyWindow;
        }
        if (!keyWin) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
            keyWin = [UIApplication sharedApplication].keyWindow;
#pragma clang diagnostic pop
        }
        
        [keyWin addSubview:self.crystalPreviewContainer];
        
        [UIView animateWithDuration:0.4 delay:0 usingSpringWithDamping:0.7 initialSpringVelocity:0.5 options:0 animations:^{
            self.crystalPreviewContainer.alpha = 1.0;
            self.crystalPreviewContainer.transform = CGAffineTransformIdentity;
        } completion:nil];
        
    } else if (gesture.state == UIGestureRecognizerStateEnded || gesture.state == UIGestureRecognizerStateCancelled) {
        [UIView animateWithDuration:0.3 animations:^{
            self.crystalPreviewContainer.alpha = 0;
            self.crystalPreviewContainer.transform = CGAffineTransformMakeScale(0.5, 0.5);
        } completion:^(BOOL finished) {
            [self.crystalPreviewContainer removeFromSuperview];
        }];
    }
}

- (void)handleHideAction {
    UIImpactFeedbackGenerator *gen = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight];
    [gen impactOccurred];

    CGRect screen = [UIScreen mainScreen].bounds;
    BOOL isNearLeft = (self.center.x < screen.size.width / 2.0);
    self.preStashFrame = self.frame;
    self.isStashed = YES;
    self.stashedSide = isNearLeft ? 1 : 2;
    [self updateSovereigntyAssertion]; // 降低优先级以配合系统节能

    [UIView animateWithDuration:0.6 delay:0 usingSpringWithDamping:0.8 initialSpringVelocity:0.5 options:0 animations:^{
        // 核心：将窗口物理尺寸缩小为 44x44 图标大小
        CGFloat targetX = isNearLeft ? 0 : screen.size.width - 44;
        CGFloat targetY = self.frame.origin.y + self.frame.size.height/2.0 - 22;
        self.frame = CGRectMake(targetX, targetY, 44, 44);
        
        // 视觉销毁：内容缩放并淡出
        self.clippingContainer.transform = CGAffineTransformMakeScale(0.01, 0.01);
        self.clippingContainer.alpha = 0;
        
        // 玻璃背景转化为图标底色
        self.glassBackdrop.alpha = 0.8;
        self.glassBackdrop.transform = CGAffineTransformIdentity;
        self.glassBackdrop.frame = self.bounds;
        self.glassBackdrop.layer.cornerRadius = 12;

        self.stashGrabber.alpha = 1.0;
        self.stashGrabber.frame = self.bounds;
        self.appIconMiniView.frame = CGRectInset(self.bounds, 4, 4);
        
        // 隐藏不需要的装饰
        self.resizeHandle.alpha = 0;
    } completion:^(BOOL finished) {
        // 真正从层级中移除画面渲染，释放资源
        [self.hostView removeFromSuperview];
    }];
}

- (void)updateAdaptiveColor {
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        UIImage *icon = [UIImage _applicationIconImageForBundleIdentifier:self.bundleID format:10 scale:[UIScreen mainScreen].scale];
        UIColor *avgColor = CV3AverageColorFromImage(icon);
        dispatch_async(dispatch_get_main_queue(), ^{
            self.adaptiveAppColor = avgColor ?: [UIColor labelColor];
            self.appIconMiniView.image = icon;
            if (self.largeSplashIcon) {
                self.largeSplashIcon.image = icon;
                [UIView animateWithDuration:0.5 animations:^{
                    self.largeSplashIcon.alpha = 1.0;
                }];
            }

            [UIView animateWithDuration:0.8 animations:^{
                self.innerGlowLayer.borderColor = [self.adaptiveAppColor colorWithAlphaComponent:0.6].CGColor;
                self.innerGlowLayer.borderWidth = 0.8;
                self.stashGrabber.layer.borderColor = [self.adaptiveAppColor colorWithAlphaComponent:0.5].CGColor;
            }];
        });
    });
}
- (void)triggerCollisionImpulseAtPoint:(CGPoint)point {
    [CATransaction begin];
    [CATransaction setAnimationDuration:0.12];
    [CATransaction setAnimationTimingFunction:[CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseOut]];
    
    CAKeyframeAnimation *cyanAnim = [CAKeyframeAnimation animationWithKeyPath:@"transform.translation"];
    cyanAnim.values = @[[NSValue valueWithCGPoint:CGPointMake(-4, -4)], [NSValue valueWithCGPoint:CGPointZero]];
    [self.cyanLayer addAnimation:cyanAnim forKey:@"collision"];
    
    CAKeyframeAnimation *magAnim = [CAKeyframeAnimation animationWithKeyPath:@"transform.translation"];
    magAnim.values = @[[NSValue valueWithCGPoint:CGPointMake(4, 4)], [NSValue valueWithCGPoint:CGPointZero]];
    [self.magentaLayer addAnimation:magAnim forKey:@"collision"];
    
    CAKeyframeAnimation *glowAnim = [CAKeyframeAnimation animationWithKeyPath:@"borderWidth"];
    glowAnim.values = @[@2.5, @0.8];
    [self.innerGlowLayer addAnimation:glowAnim forKey:@"collision"];
    
    [CATransaction commit];
    
    // --- Collision Sparks (Particle System) ---
    CAEmitterLayer *emitter = [CAEmitterLayer layer];
    emitter.emitterPosition = point;
    emitter.emitterShape = kCAEmitterLayerPoint;
    emitter.renderMode = kCAEmitterLayerAdditive;
    
    CAEmitterCell *cell = [CAEmitterCell emitterCell];
    cell.contents = (id)[self sparkImageWithColor:self.adaptiveAppColor].CGImage;
    cell.birthRate = 45;
    cell.lifetime = 0.5;
    cell.lifetimeRange = 0.2;
    cell.velocity = 150;
    cell.velocityRange = 80;
    cell.emissionRange = M_PI * 2.0;
    cell.scale = 0.05;
    cell.scaleSpeed = -0.1;
    cell.alphaSpeed = -1.5;
    
    emitter.emitterCells = @[cell];
    
    UIWindow *keyWin = nil;
    if (@available(iOS 15.0, *)) {
        keyWin = self.windowScene.keyWindow;
    }
    if (!keyWin) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        keyWin = [UIApplication sharedApplication].keyWindow;
#pragma clang diagnostic pop
    }
    
    [keyWin.layer addSublayer:emitter];
    
    // Stop and remove emitter after a short burst
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        emitter.birthRate = 0;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [emitter removeFromSuperlayer];
        });
    });

    UIImpactFeedbackGenerator *rigid = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleRigid];
    [rigid impactOccurredWithIntensity:1.0];
}

- (UIImage *)sparkImageWithColor:(UIColor *)color {
    CGFloat size = 20.0;
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(size, size), NO, 0);
    CGContextRef context = UIGraphicsGetCurrentContext();
    CGContextAddEllipseInRect(context, CGRectMake(0, 0, size, size));
    [color setFill];
    CGContextFillPath(context);
    UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return image;
}

- (void)triggerCollisionImpulse {
    [self triggerCollisionImpulseAtPoint:self.center];
}

- (void)applyCurrentTransformWithScale:(CGFloat)scale {
    CGAffineTransform transform = self.baseRotationTransform;
    if (scale != 1.0) {
        transform = CGAffineTransformScale(transform, scale, scale);
    }
    self.transform = CGAffineTransformIdentity; // Keep physical upright
    self.rootTransformContainer.transform = transform;
}

- (void)layoutSubviews {
    if (self.isStashed) return; // 核心：隐藏状态下跳过布局更新，防止干扰图标状态

    UIInterfaceOrientation orientation = self.targetOrientation != UIInterfaceOrientationUnknown ? self.targetOrientation : UIInterfaceOrientationPortrait;
    BOOL isLandscape = UIInterfaceOrientationIsLandscape(orientation);
    
    // 1. 物理外壳跟随旋转：确保 UIWindow 的 bounds 与当前设备方向完全匹配
    // 物理宽度在横屏下应该是较大的那个值
    BOOL currentBoundsIsLandscape = self.bounds.size.width > self.bounds.size.height;
    if (isLandscape && !currentBoundsIsLandscape) {
        self.bounds = CGRectMake(0, 0, self.bounds.size.height, self.bounds.size.width);
    } else if (!isLandscape && currentBoundsIsLandscape) {
        self.bounds = CGRectMake(0, 0, self.bounds.size.height, self.bounds.size.width);
    }

    [super layoutSubviews];
    
    // 物理尺寸 (Physical Dimensions) - 此时物理外壳已经根据方向完成了翻转
    CGFloat physicalW = self.bounds.size.width;
    CGFloat physicalH = self.bounds.size.height;
    
    // 2. 坐标系判定：检查系统是否已经通过 _shouldAutorotate 为我们自动旋转了坐标轴
    // 如果系统场景报告的方向已经是横屏，那么 Identity 变换就是横向的。
    // 如果系统场景强制报告竖屏（挂载在 SpringBoard），我们需要手动通过 rootTransformContainer 旋转 90 度。
    UIInterfaceOrientation sceneOrientation = self.windowScene ? self.windowScene.interfaceOrientation : UIInterfaceOrientationPortrait;
    
    CGAffineTransform targetRotation = CGAffineTransformIdentity;
    if (sceneOrientation != orientation) {
        // 只有当窗口场景坐标轴与目标方向不一致时，才需要手动补偿旋转矩阵
        switch (orientation) {
            case UIInterfaceOrientationLandscapeLeft: targetRotation = CGAffineTransformMakeRotation(-M_PI_2); break;
            case UIInterfaceOrientationLandscapeRight: targetRotation = CGAffineTransformMakeRotation(M_PI_2); break;
            case UIInterfaceOrientationPortraitUpsideDown: targetRotation = CGAffineTransformMakeRotation(M_PI); break;
            default: targetRotation = CGAffineTransformIdentity; break;
        }
    }
    self.baseRotationTransform = targetRotation;

    // 逻辑尺寸 (Logical Dimensions)
    // 如果我们需要手动旋转矩阵，那么逻辑尺寸需要对调；如果系统已经转好了，物理即逻辑。
    BOOL needsManualRotation = !CGAffineTransformIsIdentity(targetRotation);
    CGFloat logicalW = needsManualRotation ? physicalH : physicalW;
    CGFloat logicalH = needsManualRotation ? physicalW : physicalH;
    
    // 3. 同步根旋转容器
    self.rootTransformContainer.bounds = CGRectMake(0, 0, logicalW, logicalH);
    self.rootTransformContainer.center = CGPointMake(physicalW / 2.0, physicalH / 2.0);
    [self applyCurrentTransformWithScale:self.isFocused ? 1.02 : 1.0];

    // 4. 更新子组件布局 (基于逻辑坐标系)
    self.clippingContainer.bounds = self.rootTransformContainer.bounds;
    self.clippingContainer.center = CGPointMake(logicalW / 2.0, logicalH / 2.0);
    
    self.glassBackdrop.bounds = CGRectMake(0, 0, logicalW * 1.1, logicalH * 1.1);
    self.glassBackdrop.center = CGPointMake(logicalW / 2.0, logicalH / 2.0);

    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    self.innerGlowLayer.frame = self.clippingContainer.bounds;
    self.cyanLayer.frame = self.clippingContainer.bounds;
    self.magentaLayer.frame = self.clippingContainer.bounds;
    for (UIView *subview in self.glassBackdrop.subviews) {
        if ([NSStringFromClass([subview class]) containsString:@"Backdrop"]) {
            subview.transform = CGAffineTransformMakeScale(1.15, 1.15);
        }
    }
    [CATransaction commit];

    self.resizeHandle.frame = CGRectMake(logicalW - 60, logicalH - 60, 60, 60);
    
    CGFloat arcRadius = 18.0;
    CGFloat centerAngle = M_PI_4;
    CGFloat halfSweep = M_PI / 8.0; 
    self.resizeHandleLayer.path = [UIBezierPath bezierPathWithArcCenter:CGPointMake(32, 32) radius:arcRadius startAngle:centerAngle - halfSweep endAngle:centerAngle + halfSweep clockwise:YES].CGPath;
    self.resizeHandleLayer.fillColor = [UIColor clearColor].CGColor;
    self.resizeHandleLayer.strokeColor = [[UIColor whiteColor] colorWithAlphaComponent:0.3].CGColor;
    self.resizeHandleLayer.lineWidth = 2.0;

    // 5. 更新内部 App 场景 (基于物理方向与逻辑比例，防止挤压)
    if (self.hostContainerProxy) {
        CGRect rawScreenBounds = [UIScreen mainScreen].bounds;
        
        // 核心：遵循竖屏时的“等比物理缩放”规范 (MilkyWay Style)
        // App 应该始终认为自己在操作“全屏”，由我们进行整体物理压缩
        CGFloat fullScreenW = isLandscape ? MAX(rawScreenBounds.size.width, rawScreenBounds.size.height) : MIN(rawScreenBounds.size.width, rawScreenBounds.size.height);
        CGFloat fullScreenH = isLandscape ? MIN(rawScreenBounds.size.width, rawScreenBounds.size.height) : MAX(rawScreenBounds.size.width, rawScreenBounds.size.height);
        CGRect fullScreenBounds = CGRectMake(0, 0, fullScreenW, fullScreenH);
        
        // 计算缩放比：窗口逻辑尺寸 / 屏幕物理尺寸
        // 为了实现“等比物理缩放”，我们必须取 X 和 Y 缩放比例中的最小值，或者确保逻辑比例与物理比例一致
        CGFloat scaleX = logicalW / fullScreenW;
        CGFloat scaleY = logicalH / fullScreenH;
        
        // 核心：强制执行等比缩放 (Uniform Scaling)
        CGFloat uniformScale = MIN(scaleX, scaleY);
        
        if (self.targetScene) {
            @try {
                FBSMutableSceneSettings *settings = [[self.targetScene settings] mutableCopy];
                BOOL needsUpdate = NO;
                if (!CGRectEqualToRect(settings.frame, fullScreenBounds)) {
                    [settings setFrame:fullScreenBounds];
                    needsUpdate = YES;
                }
                
                if ([settings respondsToSelector:@selector(setInterfaceOrientation:)]) {
                    [settings performSelector:@selector(setInterfaceOrientation:) withObject:@(orientation)];
                    needsUpdate = YES;
                } else {
                    @try { [settings setValue:@(orientation) forKey:@"interfaceOrientation"]; needsUpdate = YES; } @catch (NSException *e) {}
                }

                if (needsUpdate) [self.targetScene updateSettings:settings withTransitionContext:nil];
            } @catch (NSException *e) {}
        }

        // 应用全屏分辨率到代理容器，并实施等比物理缩放
        self.hostContainerProxy.transform = CGAffineTransformIdentity;
        self.hostContainerProxy.bounds = fullScreenBounds; 
        if (self.hostView) {
            self.hostView.transform = CGAffineTransformIdentity;
            self.hostView.frame = fullScreenBounds;
        }
        
        self.hostContainerProxy.layer.anchorPoint = CGPointMake(0.5, 0.5);
        self.hostContainerProxy.center = CGPointMake(logicalW / 2.0, logicalH / 2.0);
        self.hostContainerProxy.transform = CGAffineTransformMakeScale(uniformScale, uniformScale);
    }
}

- (void)clampToScreenBounds {
    if (self.isStashed) return; // 隐藏状态下跳过钳位，允许 origin.x 超出屏幕
    
    UIWindow *keyWindow = nil;
    if (@available(iOS 15.0, *)) {
        keyWindow = self.windowScene.keyWindow;
    } else {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        keyWindow = [UIApplication sharedApplication].keyWindow;
#pragma clang diagnostic pop
    }
    UIEdgeInsets safeArea = keyWindow ? keyWindow.safeAreaInsets : UIEdgeInsetsMake(47, 0, 34, 0);
    CGRect screenBounds = [UIScreen mainScreen].bounds;
    
    CGRect frame = self.frame;
    if (frame.origin.x < safeArea.left) frame.origin.x = safeArea.left;
    if (frame.origin.y < safeArea.top) frame.origin.y = safeArea.top;
    if (CGRectGetMaxX(frame) > screenBounds.size.width - safeArea.right) frame.origin.x = screenBounds.size.width - safeArea.right - frame.size.width;
    if (CGRectGetMaxY(frame) > screenBounds.size.height - safeArea.bottom) frame.origin.y = screenBounds.size.height - safeArea.bottom - frame.size.height;
    
    // 核心修复：严禁在有 Transform (如缩放/旋转) 的情况下直接设置 frame。
    // 使用 center 进行平移钳位，确保不会触发无限抖动。
    self.center = CGPointMake(CGRectGetMidX(frame), CGRectGetMidY(frame));
}

- (FBScene *)getSceneForBundleID:(NSString *)bundleID {
    @try {
        SBApplication *app = [[%c(SBApplicationController) sharedInstance] applicationWithBundleIdentifier:bundleID];
        if ([app respondsToSelector:@selector(mainScene)]) {
            FBScene *scene = [app mainScene];
            // 核心修复：严禁返回已失效或正在销毁的场景，强制触发重试逻辑等待新场景创建
            if (scene && [scene respondsToSelector:@selector(isValid)] && ![(id)scene isValid]) {
                CV3LogToFile(@"[Debug] 忽略无效的旧场景: %@", bundleID);
            } else if (scene) {
                return scene;
            }
        }
        
        FBSceneManager *manager = [%c(FBSceneManager) sharedInstance];
        
        // iOS 16 fallback: check if 'scenes' property exists (returns NSSet)
        if ([manager respondsToSelector:@selector(scenes)]) {
            id scenesSet = [manager valueForKey:@"scenes"];
            if ([scenesSet isKindOfClass:[NSSet class]]) {
                for (FBScene *scene in scenesSet) {
                    if ([scene.identifier containsString:bundleID]) {
                        if ([scene respondsToSelector:@selector(isValid)] && ![(id)scene isValid]) continue;
                        return scene;
                    }
                }
            }
        }
        
        NSDictionary *scenes = nil;
        
        @try {
            id workspace = [manager valueForKey:@"_workspace"];
            scenes = [workspace valueForKey:@"_allScenesByID"];
        } @catch (NSException *e) {
            scenes = nil;
        }
        
        if (!scenes) {
            @try {
                scenes = [manager valueForKey:@"_scenesByID"];
            } @catch (NSException *e) {
                scenes = nil;
            }
        }
        
        for (NSString *key in scenes.allKeys) {
            if ([key containsString:bundleID]) {
                FBScene *scene = scenes[key];
                if ([scene respondsToSelector:@selector(isValid)] && ![(id)scene isValid]) continue;
                return scene;
            }
        }
    } @catch (NSException *e) {
        CV3LogToFile(@"[Error] getSceneForBundleID failed: %@", e);
    }
    return nil;
}

- (void)attemptToHostSceneWithRetries:(int)retries delay:(double)delay {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        @try {
            FBScene *targetScene = [self getSceneForBundleID:self.bundleID];
            
            if (targetScene) {
                self.targetScene = targetScene;
                CV3LogToFile(@"[Debug] 找到场景: %@ (retries left: %d)", self.bundleID, retries);
                
                // Step 1: 确保 Scene 已准备好被托管
                FBSMutableSceneSettings *settings = [[targetScene settings] mutableCopy];
                [settings setBackgrounded:NO];
                [settings setForeground:YES];
                
                // [Foreground Sovereignty] Force occluded=NO and visibility=2 to ensure hardware access and rendering
                @try {
                    if ([settings respondsToSelector:@selector(setOccluded:)]) {
                        [settings setValue:@NO forKey:@"occluded"];
                    }
                    if ([settings respondsToSelector:@selector(setVisibility:)]) {
                        [settings setValue:@2 forKey:@"visibility"];
                    }
                } @catch (NSException *e) {}
                
                if ([settings respondsToSelector:@selector(setFrame:)]) {
                    [settings setFrame:[UIScreen mainScreen].bounds];
                }
                
                [targetScene updateSettings:settings withTransitionContext:nil];
                
                if ([targetScene respondsToSelector:@selector(_setContentState:)]) {
                    [targetScene _setContentState:2]; // Ready
                }
                
                // Step 2: 使用 _UISceneLayerHostContainerView 创建渲染视图
                @try {
                    _UISceneLayerHostContainerView *hostedView = [[%c(_UISceneLayerHostContainerView) alloc] initWithScene:targetScene debugDescription:@"ChevronV3Host"];
                    UIScenePresentationContext *context = [[%c(UIScenePresentationContext) alloc] _initWithDefaultValues];
                    if ([context respondsToSelector:@selector(setPresentedLayerTypes:)]) {
                        [context setPresentedLayerTypes:31]; // 尝试强制渲染所有类型
                    }
                    if ([context respondsToSelector:@selector(setAppearanceStyle:)]) {
                        [context setAppearanceStyle:2];
                    }
                    if ([context respondsToSelector:@selector(setClipsToBounds:)]) {
                        [context setClipsToBounds:YES];
                    }
                    
                    if ([hostedView respondsToSelector:@selector(_setPresentationContext:)]) {
                        [hostedView _setPresentationContext:context];
                    }
                    
                    if (hostedView) {
                        hostedView.layer.cornerRadius = kChevronLayoutConstants.cornerRadius;
                        hostedView.layer.masksToBounds = YES;
                        
                        self.hostView = hostedView;
                        self.hostView.accessibilityIdentifier = @"ChevronV3Host";
                        
                        // 核心：将真实画面插入 Splash 之下，确保过渡动画淡出时能自然显露内容
                        if (self.splashView) {
                            [self.hostContainerProxy insertSubview:hostedView belowSubview:self.splashView];
                        } else {
                            [self.hostContainerProxy addSubview:hostedView];
                        }
                        
                        [self bringSubviewToFront:self.resizeHandle];
                        CV3LogToFile(@"[Debug] 成功通过 _UISceneLayerHostContainerView 创建渲染视图");
                        
                        [self syncWindowBoundsToClient];

                        // --- Transition: Splash to Real Content ---
                        if (self.splashView) {
                            [UIView animateWithDuration:0.8 delay:0.2 options:UIViewAnimationOptionCurveEaseInOut animations:^{
                                self.splashView.alpha = 0;
                                self.largeSplashIcon.transform = CGAffineTransformMakeScale(1.5, 1.5);
                            } completion:^(BOOL finished) {
                                [self.splashView removeFromSuperview];
                                self.splashView = nil;
                            }];
                        }
                    } else {
                        CV3LogToFile(@"[Error] _UISceneLayerHostContainerView 创建失败");
                    }
                } @catch (NSException *e) {
                    CV3LogToFile(@"[Error] 获取 SceneContainerView 失败: %@", e);
                }
            } else {
                CV3LogToFile(@"[Debug] 未找到场景: %@", self.bundleID);
                if (retries > 0) {
                    [self attemptToHostSceneWithRetries:retries - 1 delay:delay * 1.2];
                } else {
                    CV3LogToFile(@"[Error] targetScene not found after launch for %@", self.bundleID);
                    // 核心修复：重试失败后，也要尝试清理 Splash 状态，允许用户看到可能的错误状态或尝试手动恢复
                    if (self.splashView) {
                        [self.splashView removeFromSuperview];
                        self.splashView = nil;
                    }
                }
            }
        } @catch (NSException *e) {
            CV3LogToFile(@"[Error] Floating window load scene failed: %@", e);
        }
    });
}

- (void)loadAppScene {
    dispatch_async(dispatch_get_main_queue(), ^{
        @try {
            [[UIApplication sharedApplication] launchApplicationWithIdentifier:self.bundleID suspended:YES];
            
            // [Foreground Sovereignty] Inject RunningBoard assertion to prevent process suspension
            if (self.rbsAssertion) {
                [self.rbsAssertion invalidate];
                self.rbsAssertion = nil;
            }
            
            @try {
                RBSProcessIdentity *identity = [%c(RBSProcessIdentity) identityForEmbeddedApplicationIdentifier:self.bundleID];
                RBSTarget *target = [%c(RBSTarget) targetWithProcessIdentity:identity];
                
                // 使用 UserInteractive 域和 Foreground 属性，模拟原生前台 App 的优先级
                RBSDomainAttribute *foregroundAttr = [%c(RBSDomainAttribute) attributeWithDomain:@"com.apple.common" name:@"UserInteractive"];
                
                self.rbsAssertion = [[%c(RBSAssertion) alloc] initWithExplanation:[NSString stringWithFormat:@"ChevronV3 Sovereignty for %@", self.bundleID] 
                                                                           target:target 
                                                                       attributes:@[foregroundAttr]];
                
                NSError *error = nil;
                if ([self.rbsAssertion acquireWithError:&error]) {
                    CV3LogToFile(@"[Immortality] 成功为 %@ 注入前台优先级断连 (RBSAssertion)", self.bundleID);
                } else {
                    CV3LogToFile(@"[Error] RBSAssertion 注入失败: %@", error);
                }
            } @catch (NSException *e) {
                CV3LogToFile(@"[Error] RBSAssertion 流程异常: %@", e);
            }

            // Start polling with initial delay of 0.3s, up to 10 retries (more resilient for cold starts)
            [self attemptToHostSceneWithRetries:10 delay:0.3];
            
            // [Safety] 增加全局超时保护：如果 12 秒后还没进入内容，强制移除 Splash，防止界面永久卡死
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(12.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                if (self.splashView) {
                    CV3LogToFile(@"[Safety] 触发启动超时强制恢复: %@", self.bundleID);
                    [UIView animateWithDuration:0.5 animations:^{
                        self.splashView.alpha = 0;
                    } completion:^(BOOL finished) {
                        if (self.splashView) {
                            [self.splashView removeFromSuperview];
                            self.splashView = nil;
                        }
                    }];
                }
            });
        } @catch (NSException *e) {
            CV3LogToFile(@"[Error] Floating window launch failed: %@", e);
        }
    });
}

- (void)handleMoveLongPress:(UILongPressGestureRecognizer *)gesture {
    static CGPoint initialTouchOffset;
    static CGPoint lastVelocity;
    static NSTimeInterval lastTime;
    
    CGPoint currentPoint = [gesture locationInView:nil];
    CGRect screen = [UIScreen mainScreen].bounds;
    
    if (gesture.state == UIGestureRecognizerStateBegan) {
        [self setWindowFocused:YES];
        CGPoint centerInWindow = self.center;
        initialTouchOffset = CGPointMake(currentPoint.x - centerInWindow.x, currentPoint.y - centerInWindow.y);
        
        [UIView animateWithDuration:0.3 animations:^{
            self.layer.shadowOpacity = 0.8;
            self.layer.shadowRadius = 35.0;
            [self applyCurrentTransformWithScale:1.05]; // 拖拽时轻微放大提升手感
        }];
        
        self.lastTargetSnapFrame = CGRectZero;
        lastTime = CACurrentMediaTime();
        lastVelocity = CGPointZero;
        
        UIImpactFeedbackGenerator *gen = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium];
        [gen impactOccurred];
    }
    
    if (gesture.state == UIGestureRecognizerStateChanged) {
        NSTimeInterval now = CACurrentMediaTime();
        CGFloat dt = now - lastTime;
        if (dt > 0) {
            lastVelocity = CGPointMake((currentPoint.x - (self.center.x + initialTouchOffset.x)) / dt, (currentPoint.y - (self.center.y + initialTouchOffset.y)) / dt);
        }
        lastTime = now;

        // 1. 更新位置
        self.center = CGPointMake(currentPoint.x - initialTouchOffset.x, currentPoint.y - initialTouchOffset.y);
        
        // --- 灵动岛引力场 ---
        CGPoint islandCenter = CGPointMake(screen.size.width / 2.0, 54.0);
        CGFloat islandDist = sqrt(pow(self.center.x - islandCenter.x, 2) + pow(self.center.y - islandCenter.y, 2));
        
        if (islandDist < 120.0) {
            CGFloat pull = (120.0 - islandDist) / 120.0;
            CGAffineTransform islandPull = CGAffineTransformMakeTranslation((islandCenter.x - self.center.x) * pull * 0.4, (islandCenter.y - self.center.y) * pull * 0.4);
            [CATransaction begin];
            [CATransaction setDisableActions:YES];
            self.innerGlowLayer.affineTransform = islandPull;
            [CATransaction commit];
            if (islandDist < 65.0) {
                static NSTimeInterval lastIslandHaptic = 0;
                if (now - lastIslandHaptic > 0.6) {
                    UISelectionFeedbackGenerator *gen = [[UISelectionFeedbackGenerator alloc] init];
                    [gen selectionChanged];
                    lastIslandHaptic = now;
                }
            }
        } else {
            [CATransaction begin];
            [CATransaction setDisableActions:YES];
            self.innerGlowLayer.affineTransform = CGAffineTransformIdentity;
            [CATransaction commit];
        }

        // 2. 惯性畸变 (Liquid Glass)
        CGFloat velMag = sqrt(lastVelocity.x * lastVelocity.x + lastVelocity.y * lastVelocity.y);
        CGFloat rawStretch = velMag / kChevronPhysicsConstants.stretchDamping;
        CGFloat stretch = kChevronPhysicsConstants.maxStretch * (1.0 - exp(-rawStretch)); 
        CGFloat angle = atan2(lastVelocity.y, lastVelocity.x);
        
        [CATransaction begin];
        [CATransaction setDisableActions:YES];
        CGAffineTransform stretchTransform = CGAffineTransformIdentity;
        stretchTransform = CGAffineTransformRotate(stretchTransform, angle);
        stretchTransform = CGAffineTransformScale(stretchTransform, 1.0 + stretch, 1.0 - (stretch * 0.3));
        stretchTransform = CGAffineTransformRotate(stretchTransform, -angle);
        self.glassBackdrop.transform = stretchTransform;
        [CATransaction commit];
        
        // --- Magnetic Window Alignment ---
        CGFloat magnetThreshold = 30.0;
        for (CV3FloatingAppWindow *other in floatingWindows) {
            if (other == self || other.isStashed || ![other isKindOfClass:[CV3FloatingAppWindow class]]) continue;
            CGRect otherFrame = other.frame;
            if (fabs(CGRectGetMaxX(self.frame) - otherFrame.origin.x) < magnetThreshold) {
                self.center = CGPointMake(otherFrame.origin.x - self.frame.size.width / 2.0 - 5.0, self.center.y);
            } else if (fabs(self.frame.origin.x - CGRectGetMaxX(otherFrame)) < magnetThreshold) {
                self.center = CGPointMake(CGRectGetMaxX(otherFrame) + self.frame.size.width / 2.0 + 5.0, self.center.y);
            }
        }
    }
    
    if (gesture.state == UIGestureRecognizerStateEnded || gesture.state == UIGestureRecognizerStateCancelled) {
        CGFloat velMag = sqrt(lastVelocity.x * lastVelocity.x + lastVelocity.y * lastVelocity.y);
        if (velMag > 2500.0) {
            BOOL towardLeft = (lastVelocity.x < -1800 && self.center.x < 150);
            BOOL towardRight = (lastVelocity.x > 1800 && self.center.x > screen.size.width - 150);
            BOOL towardTop = (lastVelocity.y < -1800 && self.center.y < 150);
            
            if (towardLeft || towardRight || towardTop) {
                [[[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium] impactOccurred];
                [UIView animateWithDuration:0.45 delay:0 options:UIViewAnimationOptionCurveEaseIn animations:^{
                    self.center = CGPointMake(self.center.x + lastVelocity.x * 0.15, self.center.y + lastVelocity.y * 0.15);
                    self.transform = CGAffineTransformScale(self.transform, 0.01, 0.01);
                    self.alpha = 0;
                } completion:^(BOOL finished) {
                    [self closeWindow];
                }];
                return;
            }
        }

        [UIView animateWithDuration:0.5 delay:0 usingSpringWithDamping:0.7 initialSpringVelocity:0.5 options:UIViewAnimationOptionCurveEaseInOut animations:^{
            [self applyCurrentTransformWithScale:1.0];
            self.glassBackdrop.transform = CGAffineTransformIdentity;
            self.innerGlowLayer.affineTransform = CGAffineTransformIdentity;
            self.layer.shadowOpacity = 0.4;
            self.layer.shadowRadius = 20.0;
            
            CGRect targetFrame = self.frame;
            if (self.frame.origin.x < -self.frame.size.width / 2.0) {
                self.isStashed = YES;
                self.stashedSide = 1;
                [self updateSovereigntyAssertion];
                self.preStashFrame = self.frame;
                targetFrame.origin.x = -self.frame.size.width + 44; 
                self.stashGrabber.alpha = 1.0;
                self.stashGrabber.frame = CGRectMake(self.frame.size.width - 44, self.frame.size.height/2 - 22, 44, 44);
                self.clippingContainer.alpha = 0;
                self.glassBackdrop.alpha = 0.5;
            } else if (self.frame.origin.x + self.frame.size.width > screen.size.width + self.frame.size.width / 2.0) {
                self.isStashed = YES;
                self.stashedSide = 2;
                [self updateSovereigntyAssertion];
                self.preStashFrame = self.frame;
                targetFrame.origin.x = screen.size.width - 44;
                self.stashGrabber.alpha = 1.0;
                self.stashGrabber.frame = CGRectMake(0, self.frame.size.height/2 - 22, 44, 44);
                self.clippingContainer.alpha = 0;
                self.glassBackdrop.alpha = 0.5;
            } else {
                [self clampToScreenBounds];
            }
            
            if (!CGRectEqualToRect(targetFrame, self.frame)) {
                self.frame = targetFrame;
                if (self.isStashed) {
                    [self updateGrabberStack];
                    for (CV3FloatingAppWindow *win in floatingWindows) {
                        if (win != self && [win isKindOfClass:[CV3FloatingAppWindow class]] && win.isStashed) [win updateGrabberStack];
                    }
                }
            }
        } completion:nil];
    }
}

- (void)updateGrabberStack {
    // 移除旧的堆叠视觉
    for (UIView *sub in self.stashGrabber.subviews) {
        if (sub.tag == 99) [sub removeFromSuperview];
    }
    
    int stashedCount = 0;
    NSMutableArray *otherStashedWindows = [NSMutableArray array];
    for (CV3FloatingAppWindow *win in floatingWindows) {
        if (win.isStashed && win.stashedSide == self.stashedSide && win != self) {
            stashedCount++;
            [otherStashedWindows addObject:win];
        }
    }
    
    if (stashedCount > 0) {
        // 建议：Prism Stacking (棱镜堆叠视觉)
        // ... (保持原有的图标堆叠视觉逻辑) ...
    }

    // 核心修复：由于窗口本身已缩小为图标，堆叠时需要移动整个窗口的位置
    CGFloat stackOffset = 48.0; // 每个图标之间的垂直间距
    CGRect currentFrame = self.frame;
    currentFrame.origin.y = self.preStashFrame.origin.y + self.preStashFrame.size.height/2.0 - 22 + (stashedCount * stackOffset);

    [UIView animateWithDuration:0.4 delay:0 usingSpringWithDamping:0.8 initialSpringVelocity:0 options:0 animations:^{
        self.frame = currentFrame;
    } completion:nil];
    }
- (void)handleRestoreTap:(UITapGestureRecognizer *)gesture {
    [self restoreFromStash];
}

- (void)restoreFromStash {
    // 强制提升 WindowLevel 并置顶，确保成为主焦点，但不能超过控制中心 (kChevronWindowLevels.maxBound)
    self.windowLevel = kChevronWindowLevels.floatingApp; 
    [self makeKeyAndVisible];
    [self setWindowFocused:YES];

    if (self.isStashed) {
        UIImpactFeedbackGenerator *gen = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight];
        [gen impactOccurred];
        
        // 核心：重新渲染画面，将其挂载回代理层
        if (self.hostView && self.hostView.superview != self.hostContainerProxy) {
            [self.hostContainerProxy addSubview:self.hostView];
            self.hostView.frame = self.hostContainerProxy.bounds;
        }

        [UIView animateWithDuration:0.5 delay:0 usingSpringWithDamping:0.8 initialSpringVelocity:0.5 options:0 animations:^{
            self.isStashed = NO;
            self.frame = self.preStashFrame;
            self.stashedSide = 0;
            [self updateSovereigntyAssertion]; // 恢复高优先级

            self.stashGrabber.alpha = 0;
            self.clippingContainer.alpha = 1.0;
            self.clippingContainer.transform = CGAffineTransformIdentity;
            
            self.glassBackdrop.alpha = 1.0;
            self.glassBackdrop.transform = CGAffineTransformIdentity;
            
            self.resizeHandle.alpha = 1.0;
            
            [self clampToScreenBounds];
            [self setNeedsLayout];
            [self layoutIfNeeded];
        } completion:^(BOOL finished) {
            // 通知其他窗口更新堆叠状态
            for (CV3FloatingAppWindow *win in floatingWindows) {
                if (win.isStashed) [win updateGrabberStack];
            }
        }];
    } else {
        // 如果没有被隐藏，则执行轻微的脉冲动画提醒用户它已置顶
        [self triggerCollisionImpulse];
    }
}

- (void)handleStashLongPress:(UILongPressGestureRecognizer *)gesture {
    if (!self.isStashed) return;
    if (gesture.state == UIGestureRecognizerStateBegan) {
        UIImpactFeedbackGenerator *gen = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleHeavy];
        [gen impactOccurred];
        
        [UIView animateWithDuration:0.4 delay:0 usingSpringWithDamping:0.8 initialSpringVelocity:0.5 options:0 animations:^{
            self.transform = CGAffineTransformMakeScale(0.01, 0.01);
            self.alpha = 0;
        } completion:^(BOOL finished) {
            [self closeWindow];
        }];
    }
}

- (void)handleStashPan:(UIPanGestureRecognizer *)gesture {
    if (!self.isStashed) return;
    
    CGPoint translation = [gesture translationInView:nil];
    CGRect screen = [UIScreen mainScreen].bounds;
    
    if (gesture.state == UIGestureRecognizerStateBegan) {
        [UIView animateWithDuration:0.2 animations:^{
            [self applyCurrentTransformWithScale:1.15];
            self.layer.shadowOpacity = 0.8;
            self.layer.shadowRadius = 15.0;
        }];
        UIImpactFeedbackGenerator *gen = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium];
        [gen impactOccurred];
    } else if (gesture.state == UIGestureRecognizerStateChanged) {
        // 核心修复：使用增量平移 (Incremental Translation) 替代绝对位置设置，解决“跳动”问题
        self.center = CGPointMake(self.center.x + translation.x, self.center.y + translation.y);
        [gesture setTranslation:CGPointZero inView:nil];
    } else if (gesture.state == UIGestureRecognizerStateEnded || gesture.state == UIGestureRecognizerStateCancelled) {
        [UIView animateWithDuration:0.5 delay:0 usingSpringWithDamping:0.7 initialSpringVelocity:0.5 options:0 animations:^{
            [self applyCurrentTransformWithScale:1.0];
            self.layer.shadowOpacity = 0.4;
            self.layer.shadowRadius = 5.0;
            
            // 自由拖动位置：保持在安全区域内，但不强制吸附至侧边
            UIWindow *keyWindow = nil;
            if (@available(iOS 15.0, *)) {
                keyWindow = self.windowScene.keyWindow;
            }
            UIEdgeInsets safeArea = keyWindow ? keyWindow.safeAreaInsets : UIEdgeInsetsMake(47, 0, 34, 0);
            
            CGRect frame = self.frame;
            if (frame.origin.x < safeArea.left) frame.origin.x = safeArea.left;
            if (frame.origin.y < safeArea.top) frame.origin.y = safeArea.top;
            if (CGRectGetMaxX(frame) > screen.size.width - safeArea.right) frame.origin.x = screen.size.width - safeArea.right - frame.size.width;
            if (CGRectGetMaxY(frame) > screen.size.height - safeArea.bottom) frame.origin.y = screen.size.height - safeArea.bottom - frame.size.height;
            self.frame = frame;
            
            // 重要：更新 preStashFrame，确保从当前图标位置还原
            CGRect psf = self.preStashFrame;
            psf.origin.x = self.frame.origin.x + 22 - psf.size.width / 2.0;
            psf.origin.y = self.frame.origin.y + 22 - psf.size.height / 2.0;
            self.preStashFrame = psf;
            
            // 重新判定 stashedSide 以便堆叠逻辑参考 (以中线为界)
            self.stashedSide = (self.center.x < screen.size.width / 2.0) ? 1 : 2;
            [self updateSovereigntyAssertion]; // 确保 Stash 态优先级同步
            
        } completion:^(BOOL finished) {
            UIImpactFeedbackGenerator *gen = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight];
            [gen impactOccurred];
            
            for (CV3FloatingAppWindow *win in floatingWindows) {
                if (win.isStashed) [win updateGrabberStack];
            }
        }];
    }
}

- (void)syncWindowBoundsToClient {
    if (self.bundleID) {
        NSString *path = @"/var/mobile/Library/Preferences/com.xu.chevronv3.plist";
        NSMutableDictionary *dict = [NSMutableDictionary dictionaryWithContentsOfFile:path] ?: [NSMutableDictionary dictionary];
        
        dict[[NSString stringWithFormat:@"isHosted_%@", self.bundleID]] = @(!self.hidden);
        dict[[NSString stringWithFormat:@"currentWidth_%@", self.bundleID]] = @(self.bounds.size.width);
        dict[[NSString stringWithFormat:@"currentHeight_%@", self.bundleID]] = @(self.bounds.size.height);
        
        [dict writeToFile:path atomically:YES];
        
        // 赋予全局可读权限，确保沙盒内的 App 能读取到尺寸数据
        chmod([path UTF8String], 0644);
        
        CV3LogToFile(@"宿主窗口 (%@) 尺寸已同步: 宽度=%.1f, 高度=%.1f", self.bundleID, self.bounds.size.width, self.bounds.size.height);
        
        CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), (CFStringRef)@"com.xu.chevronv3/SizeChanged", NULL, NULL, YES);
    }
}

- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    if (self.isClosing || self.isStashed) return [super hitTest:point withEvent:event];

    // 1. 深度优化：由于 App 渲染视图往往具备极高的触控优先级（尤其是带滚动的视图），
    // 我们必须在 hitTest 阶段显式干预，优先判定装饰性交互组件。
    
    // 检查右下角缩放/移动热区 (最高优先级)
    CGPoint pInResize = [self convertPoint:point toView:self.resizeHandle];
    if ([self.resizeHandle pointInside:pInResize withEvent:event]) {
        return self.resizeHandle;
    }

    // 2. 检查侧边 Stash 区域 (仅在 Stashed 时，但此处主要处理 Active 状态)
    if (self.stashGrabber.alpha > 0.5) {
        CGPoint pInGrabber = [self convertPoint:point toView:self.stashGrabber];
        if ([self.stashGrabber pointInside:pInGrabber withEvent:event]) {
            return self.stashGrabber;
        }
    }

    return [super hitTest:point withEvent:event];
}

- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)gesture {
    return YES;
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldBeRequiredToFailByGestureRecognizer:(UIGestureRecognizer *)otherGestureRecognizer {
    // 强制要求其他手势（即来自宿主 App 内部的手势）在我们自己的控制手势面前失败
    // 这可以防止拖拽或缩放/位移窗口时，底下的 App 还在疯狂滚动
    if (gestureRecognizer.view == self.resizeHandle) {
        return YES;
    }
    return NO;
}

- (void)handleResizePan:(UIPanGestureRecognizer *)gesture {
    static BOOL hasTriggeredTopHaptic = NO;
    static BOOL hasTriggeredBottomHaptic = NO;
    static BOOL hasTriggeredSideHaptic = NO;

    if (gesture.state == UIGestureRecognizerStateBegan) {
        self.initialResizeFrame = self.frame;
        hasTriggeredTopHaptic = NO;
        hasTriggeredBottomHaptic = NO;
        hasTriggeredSideHaptic = NO;
        
        UIImpactFeedbackGenerator *gen = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight];
        [gen impactOccurred];

        // --- Suggestion 4: Pixel-Perfect Live Mapping (Snapshot) ---
        // 在缩放开始瞬间捕获当前画面，作为“占位层”防止实时重绘导致的闪烁或黑边
        if (self.hostView) {
            self.liveResizeSnapshotView = [self.hostView snapshotViewAfterScreenUpdates:NO];
            self.liveResizeSnapshotView.frame = self.hostContainerProxy.bounds;
            self.liveResizeSnapshotView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
            [self.hostContainerProxy addSubview:self.liveResizeSnapshotView];
            self.hostView.alpha = 0; // 隐藏真实内容，直到缩放结束
        }

        [CATransaction begin];
        [CATransaction setAnimationDuration:0.2];
        self.resizeHandleLayer.strokeColor = [[UIColor cyanColor] colorWithAlphaComponent:0.8].CGColor;
        self.resizeHandleLayer.lineWidth = 3.5;
        self.resizeHandleLayer.shadowColor = [UIColor cyanColor].CGColor;
        self.resizeHandleLayer.shadowOffset = CGSizeZero;
        self.resizeHandleLayer.shadowOpacity = 0.8;
        self.resizeHandleLayer.shadowRadius = 5.0;
        [CATransaction commit];
    }
    
    CGPoint translation = [gesture translationInView:nil];
    CGPoint velocity = [gesture velocityInView:nil];
    
    if (gesture.state == UIGestureRecognizerStateChanged || gesture.state == UIGestureRecognizerStateEnded) {
        CGRect screenBounds = [UIScreen mainScreen].bounds;
        CGFloat aspect = screenBounds.size.height / screenBounds.size.width;
        
        // 核心优化：基于物理像素比例 (Normalized Physical Pixel Ratio)
        // 将屏幕物理宽度定义为 1.0，设定缩放阈值
        CGFloat minAllowedWidth = screenBounds.size.width * 0.4;
        CGFloat maxAllowedWidth = screenBounds.size.width * 0.9;
        
        CGPoint initialCenter = CGPointMake(CGRectGetMidX(self.initialResizeFrame), CGRectGetMidY(self.initialResizeFrame));
        CGPoint initialHandlePos = CGPointMake(CGRectGetMaxX(self.initialResizeFrame), CGRectGetMaxY(self.initialResizeFrame));
        CGPoint currentHandlePos = CGPointMake(initialHandlePos.x + translation.x, initialHandlePos.y + translation.y);
        
        CGFloat initialDist = sqrt(pow(initialHandlePos.x - initialCenter.x, 2) + pow(initialHandlePos.y - initialCenter.y, 2));
        CGFloat currentDist = sqrt(pow(currentHandlePos.x - initialCenter.x, 2) + pow(currentHandlePos.y - initialCenter.y, 2));
        
        CGFloat rawScaleFactor = initialDist > 0 ? (currentDist / initialDist) : 1.0;
        CGFloat scaleFactor = 1.0 + (rawScaleFactor - 1.0) * 1.25; 
        
        CGFloat targetWidth = self.initialResizeFrame.size.width * scaleFactor;
        
        // --- Suggestion 5: Multi-Window Gravity (Repulsion) ---
        // 检查与其他窗口的间距，如果过近则产生排斥力
        for (CV3FloatingAppWindow *other in floatingWindows) {
            if (other == self || other.isStashed || ![other isKindOfClass:[CV3FloatingAppWindow class]]) continue;
            
            CGFloat distance = sqrt(pow(self.center.x - other.center.x, 2) + pow(self.center.y - other.center.y, 2));
            CGFloat minGap = (self.bounds.size.width + other.bounds.size.width) / 2.0 + 20.0;
            
            if (distance < minGap) {
                // 产生排斥阻尼：缩放速度被窗口间的“压力”抵消
                targetWidth *= (0.8 + 0.2 * (distance / minGap));
                
                // 视觉融合：相互渗透 Glow 颜色
                [UIView animateWithDuration:0.2 animations:^{
                    self.innerGlowLayer.borderColor = [other.adaptiveAppColor colorWithAlphaComponent:0.8].CGColor;
                    other.innerGlowLayer.borderColor = [self.adaptiveAppColor colorWithAlphaComponent:0.8].CGColor;
                }];
            }
        }

        CGFloat finalWidth = targetWidth;
        
        if (targetWidth < minAllowedWidth) {
            finalWidth = minAllowedWidth - (minAllowedWidth - targetWidth) * 0.3;
        } else if (targetWidth > maxAllowedWidth) {
            finalWidth = maxAllowedWidth + (targetWidth - maxAllowedWidth) * 0.3;
        }
        
        CGFloat finalHeight = finalWidth * aspect;
        
        CGRect newFrame;
        newFrame.size = CGSizeMake(finalWidth, finalHeight);
        newFrame.origin.x = initialCenter.x - finalWidth / 2.0;
        newFrame.origin.y = initialCenter.y - finalHeight / 2.0;
        
        UIWindow *keyWin = nil;
        if (@available(iOS 15.0, *)) { keyWin = self.windowScene.keyWindow; }
        if (!keyWin) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
            keyWin = [UIApplication sharedApplication].keyWindow;
#pragma clang diagnostic pop
        }
        UIEdgeInsets safeArea = keyWin ? keyWin.safeAreaInsets : UIEdgeInsetsMake(47, 0, 34, 0);
        
        // 核心修复：缩放过程中暂时禁用安全区域的强制钳位，防止窗口边缘与安全区域边界（如灵动岛）发生高频物理冲突导致抖动
        if (gesture.state == UIGestureRecognizerStateChanged) {
            newFrame.origin.y = initialCenter.y - finalHeight / 2.0;
            
            // --- 建议实现：边界触觉反馈 ---
            if (newFrame.origin.y < safeArea.top && !hasTriggeredTopHaptic) {
                UISelectionFeedbackGenerator *gen = [[UISelectionFeedbackGenerator alloc] init];
                [gen selectionChanged];
                hasTriggeredTopHaptic = YES;
            } else if (newFrame.origin.y >= safeArea.top) {
                hasTriggeredTopHaptic = NO;
            }

            if (CGRectGetMaxY(newFrame) > screenBounds.size.height - safeArea.bottom && !hasTriggeredBottomHaptic) {
                UISelectionFeedbackGenerator *gen = [[UISelectionFeedbackGenerator alloc] init];
                [gen selectionChanged];
                hasTriggeredBottomHaptic = YES;
            } else if (CGRectGetMaxY(newFrame) <= screenBounds.size.height - safeArea.bottom) {
                hasTriggeredBottomHaptic = NO;
            }

            // --- 建议实现：两侧边界触觉反馈 ---
            BOOL hitSide = (newFrame.origin.x < safeArea.left || CGRectGetMaxX(newFrame) > screenBounds.size.width - safeArea.right);
            if (hitSide && !hasTriggeredSideHaptic) {
                UISelectionFeedbackGenerator *gen = [[UISelectionFeedbackGenerator alloc] init];
                [gen selectionChanged];
                hasTriggeredSideHaptic = YES;
            } else if (!hitSide) {
                hasTriggeredSideHaptic = NO;
            }
        } else {
            // --- 建议实现：Island Snapping (灵动岛吸附) ---
            CGFloat snapThreshold = 25.0;
            if (fabs(newFrame.origin.y - safeArea.top) < snapThreshold) {
                newFrame.origin.y = safeArea.top;
                UISelectionFeedbackGenerator *gen = [[UISelectionFeedbackGenerator alloc] init];
                [gen selectionChanged];
            }

            // --- 建议实现：物理比例吸附 (Ratio Snap Points) ---
            // 在 0.5 (小窗口模式) 和 0.8 (大窗口模式) 增加吸附感
            CGFloat currentRatio = finalWidth / screenBounds.size.width;
            CGFloat targetSnapRatio = -1.0;
            
            if (fabs(currentRatio - 0.5) < 0.03) targetSnapRatio = 0.5;
            else if (fabs(currentRatio - 0.8) < 0.03) targetSnapRatio = 0.8;
            
            if (targetSnapRatio > 0) {
                finalWidth = screenBounds.size.width * targetSnapRatio;
                finalHeight = finalWidth * aspect;
                newFrame.size = CGSizeMake(finalWidth, finalHeight);
                newFrame.origin.x = initialCenter.x - finalWidth / 2.0;
                newFrame.origin.y = initialCenter.y - finalHeight / 2.0;
                
                UIImpactFeedbackGenerator *snapHaptic = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium];
                [snapHaptic impactOccurred];
                CV3LogToFile(@"[Physical] 触发物理比例吸附: %.1f", targetSnapRatio);
            }

            if (newFrame.origin.x < safeArea.left) newFrame.origin.x = safeArea.left;
            if (newFrame.origin.y < safeArea.top) newFrame.origin.y = safeArea.top;
            if (CGRectGetMaxX(newFrame) > screenBounds.size.width - safeArea.right) 
                newFrame.origin.x = screenBounds.size.width - safeArea.right - finalWidth;
            if (CGRectGetMaxY(newFrame) > screenBounds.size.height - safeArea.bottom) 
                newFrame.origin.y = screenBounds.size.height - safeArea.bottom - finalHeight;
        }
            
        [CATransaction begin];
        [CATransaction setDisableActions:YES];
        
        self.bounds = CGRectMake(0, 0, finalWidth, finalHeight);
        self.center = CGPointMake(CGRectGetMidX(newFrame), CGRectGetMidY(newFrame));
        
        // 核心修复：缩放时强制重置灵动岛引力特效，防止装饰层发生位移纠缠
        self.innerGlowLayer.affineTransform = CGAffineTransformIdentity;
        
        // --- Suggestion 3: Resize Stress Distortion ---
        // 根据缩放速度计算“应力畸变” (Chromatic Aberration)
        CGFloat velMag = sqrt(velocity.x * velocity.x + velocity.y * velocity.y);
        CGFloat stress = MIN(15.0, velMag / 200.0); // 最大 15pt 的偏移
        
        CGAffineTransform cyanTransform = CGAffineTransformMakeTranslation(-stress * 0.5, -stress * 0.5);
        CGAffineTransform magentaTransform = CGAffineTransformMakeTranslation(stress * 0.5, stress * 0.5);
        
        self.cyanLayer.affineTransform = cyanTransform;
        self.magentaLayer.affineTransform = magentaTransform;
        
        // 增加动态模糊感 (通过拉伸背景实现模拟)
        if (velMag > 500) {
            CGFloat blurStretch = 1.0 + (velMag / 5000.0);
            self.glassBackdrop.transform = CGAffineTransformMakeScale(blurStretch, blurStretch);
        } else {
            // 原有的挤压特效逻辑
            if (targetWidth < minAllowedWidth) {
                CGFloat squeeze = 1.0 - (minAllowedWidth - targetWidth) / minAllowedWidth * 0.15;
                self.glassBackdrop.transform = CGAffineTransformMakeScale(squeeze, squeeze);
            } else {
                self.glassBackdrop.transform = CGAffineTransformIdentity;
            }
        }
        
        if (self.targetScene) {
            @try {
                FBSMutableSceneSettings *settings = [[self.targetScene settings] mutableCopy];
                if ([settings respondsToSelector:@selector(setInLiveResize:)]) {
                    [settings performSelector:@selector(setInLiveResize:) withObject:@YES];
                    [self.targetScene updateSettings:settings withTransitionContext:nil];
                }
            } @catch (NSException *e) {}
        }
        
        [CATransaction commit];
        
        if (gesture.state == UIGestureRecognizerStateEnded) {
            // --- Clean up Suggestion 4 (Snapshot) ---
            [UIView animateWithDuration:0.3 animations:^{
                self.hostView.alpha = 1.0;
                if (self.liveResizeSnapshotView) self.liveResizeSnapshotView.alpha = 0;
            } completion:^(BOOL finished) {
                [self.liveResizeSnapshotView removeFromSuperview];
                self.liveResizeSnapshotView = nil;
            }];

            // --- Clean up Suggestion 3 (Distortion) ---
            [UIView animateWithDuration:0.4 delay:0 usingSpringWithDamping:0.7 initialSpringVelocity:0.5 options:0 animations:^{
                self.cyanLayer.affineTransform = CGAffineTransformIdentity;
                self.magentaLayer.affineTransform = CGAffineTransformIdentity;
                self.glassBackdrop.transform = CGAffineTransformIdentity;
                self.innerGlowLayer.borderColor = [self.adaptiveAppColor colorWithAlphaComponent:0.6].CGColor;
            } completion:nil];

            if (self.targetScene) {
                @try {
                    FBSMutableSceneSettings *settings = [[self.targetScene settings] mutableCopy];
                    if ([settings respondsToSelector:@selector(setInLiveResize:)]) {
                        [settings performSelector:@selector(setInLiveResize:) withObject:@NO];
                        [self.targetScene updateSettings:settings withTransitionContext:nil];
                    }
                } @catch (NSException *e) {}
            }

            [CATransaction begin];
            [CATransaction setAnimationDuration:0.3];
            self.resizeHandleLayer.strokeColor = [[UIColor whiteColor] colorWithAlphaComponent:0.3].CGColor;
            self.resizeHandleLayer.lineWidth = 2.0;
            self.resizeHandleLayer.shadowOpacity = 0; 
            [CATransaction commit];

            [UIView animateWithDuration:0.5 delay:0 usingSpringWithDamping:0.7 initialSpringVelocity:0.5 options:0 animations:^{
                if (finalWidth < minAllowedWidth || finalWidth > maxAllowedWidth) {
                    CGFloat bounceWidth = fmin(maxAllowedWidth, fmax(minAllowedWidth, finalWidth));
                    CGFloat bounceHeight = bounceWidth * aspect;
                    
                    self.bounds = CGRectMake(0, 0, bounceWidth, bounceHeight);
                    
                    CGRect bounceFrame;
                    bounceFrame.size = CGSizeMake(bounceWidth, bounceHeight);
                    bounceFrame.origin.x = initialCenter.x - bounceWidth / 2.0;
                    bounceFrame.origin.y = initialCenter.y - bounceHeight / 2.0;
                    
                    if (bounceFrame.origin.x < safeArea.left) bounceFrame.origin.x = safeArea.left;
                    if (bounceFrame.origin.y < safeArea.top) bounceFrame.origin.y = safeArea.top;
                    if (CGRectGetMaxX(bounceFrame) > screenBounds.size.width - safeArea.right) 
                        bounceFrame.origin.x = screenBounds.size.width - safeArea.right - bounceWidth;
                    if (CGRectGetMaxY(bounceFrame) > screenBounds.size.height - safeArea.bottom) 
                        bounceFrame.origin.y = screenBounds.size.height - safeArea.bottom - bounceHeight;
                        
                    self.center = CGPointMake(CGRectGetMidX(bounceFrame), CGRectGetMidY(bounceFrame));
                }
            } completion:nil];
            
            self.initialResizeFrame = self.frame;
            [self syncWindowBoundsToClient];
        }
    }
}

- (void)closeWindow {
    self.isClosing = YES;
    self.hidden = YES;
    [self syncWindowBoundsToClient];

    // [Foreground Sovereignty] Invalidate RBSAssertion
    if (self.rbsAssertion) {
        [self.rbsAssertion invalidate];
        self.rbsAssertion = nil;
        CV3LogToFile(@"[Immortality] 已释放 %@ 的前台优先级断连", self.bundleID);
    }

    if (self.hostView) {
        // [Geek Advice] Explicitly disable hosting for the requester to release FBScene resources
        @try {
            if (self.targetScene && [self.targetScene respondsToSelector:@selector(hostManager)]) {
                id hm = [self.targetScene performSelector:@selector(hostManager)];
                if ([hm respondsToSelector:@selector(enableHostingForRequester:priority:)]) {
                    // 禁用托管，释放资源
                    [hm performSelector:@selector(enableHostingForRequester:priority:) withObject:nil withObject:(id)0];
                }
            }
        } @catch (NSException *e) {
            CV3LogToFile(@"[Error] Failed to disable hosting during closeWindow: %@", e);
        }

        // [New] Reset Scene Settings to Background before destroying
        if (self.targetScene) {
            @try {
                FBSMutableSceneSettings *settings = [[self.targetScene settings] mutableCopy];
                if ([settings respondsToSelector:@selector(setForeground:)]) [settings setForeground:NO];
                if ([settings respondsToSelector:@selector(setBackgrounded:)]) [settings setBackgrounded:YES];
                [self.targetScene updateSettings:settings withTransitionContext:nil];
                CV3LogToFile(@"[Aggressive] 已将 Scene 设置为后台状态: %@", self.bundleID);
            } @catch (NSException *e) {
                CV3LogToFile(@"[Error] Reset scene settings failed: %@", e);
            }
        }

        if ([self.hostView respondsToSelector:@selector(invalidate)]) {
            [self.hostView performSelector:@selector(invalidate)];
        }
        [self.hostView removeFromSuperview];
        self.hostView = nil;
    }

    // [Aggressive Termination] Option A: Force kill the application to stop all system-level services
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.15 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (!self.bundleID) return;
        
        @try {
            // 1. First attempt: Official SBApplication termination
            SBApplication *app = [[%c(SBApplicationController) sharedInstance] applicationWithBundleIdentifier:self.bundleID];
            if (app && [app respondsToSelector:@selector(_terminateWithReason:description:)]) {
                CV3LogToFile(@"[Aggressive] 正在通过 SBApplication 终止应用: %@", self.bundleID);
                [app _terminateWithReason:1 description:@"ChevronV3 Close"];
            }

            // 2. Second attempt: FBProcessManager with Context
            FBProcessManager *procMgr = [%c(FBProcessManager) sharedInstance];
            FBProcess *proc = [procMgr processForBundleIdentifier:self.bundleID];
            if (proc) {
                CV3LogToFile(@"[Aggressive] 发现活动进程 %d, 正在执行 FBProcess 终止...", proc.pid);
                
                @try {
                    FBProcessTerminationContext *context = [[%c(FBProcessTerminationContext) alloc] init];
                    context.explanation = @"ChevronV3 User Request";
                    context.exceptionCode = 0xDEADBEEF;
                    context.reportTermination = NO;
                    
                    if ([procMgr respondsToSelector:@selector(terminateProcess:withContext:)]) {
                        [procMgr terminateProcess:proc withContext:context];
                    } else if ([proc respondsToSelector:@selector(terminateWithContext:)]) {
                        [proc terminateWithContext:context];
                    } else {
                        [proc terminate];
                    }
                } @catch (NSException *inner) {
                    CV3LogToFile(@"[Error] FBProcess termination failed: %@", inner);
                }

                // 3. Final fallback: SIGKILL (The most aggressive way)
                // We check if the process is still alive after a tiny delay
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                    FBProcess *recheck = [[%c(FBProcessManager) sharedInstance] processForBundleIdentifier:self.bundleID];
                    if (recheck && recheck.pid > 0) {
                        CV3LogToFile(@"[Aggressive] 进程 %d 依然存活，发送 SIGKILL 强杀！", recheck.pid);
                        kill(recheck.pid, SIGKILL);
                    } else {
                        CV3LogToFile(@"[Aggressive] 应用 %@ 已成功退出。", self.bundleID);
                    }
                });
            }
        } @catch (NSException *e) {
            CV3LogToFile(@"[Error] 终止流程异常: %@", e);
        }
    });
    
    self.windowScene = nil; // Clear scene attachment
    [floatingWindows removeObject:self];
}@end

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

@implementation CV3Window

- (void)applyBackgroundTint:(UIColor *)color {
    [UIView animateWithDuration:0.8 animations:^{
        // 使用极低的不透明度（6%）注入色彩，保持玻璃质感
        self.dimmingView.backgroundColor = [color colorWithAlphaComponent:0.06];
    }];
}

- (void)handleDoubleTap:(UITapGestureRecognizer *)gesture {
    // 建议 5：搜索极速启动
    // 如果搜索框有内容且有结果，双击面板直接启动第一个
    if (self.searchField.text.length > 0 && self.filteredApps.count > 0) {
        [self launchApp:self.filteredApps[0]];
        return;
    }
    
    [self.feedback impactOccurred];
    [self.searchField becomeFirstResponder];
}

// 统一 App 启动逻辑
- (void)launchApp:(CV3AppInfo *)info {
    if (self.launchDebounce) return;
    self.launchDebounce = YES;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.4 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        self.launchDebounce = NO;
    });

    UIImpactFeedbackGenerator *launcherImpact = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium];
    [launcherImpact impactOccurred];

    if (info.bundleId) {
        NSString *bid = [info.bundleId copy];
        
        // 核心修复：检测是否已有该应用的分屏窗口，如果有则直接激活而非全屏开启
        CV3FloatingAppWindow *existingWindow = nil;
        for (CV3FloatingAppWindow *win in floatingWindows) {
            if ([win.bundleID isEqualToString:bid]) {
                existingWindow = win;
                break;
            }
        }
        
        if (existingWindow) {
            CV3LogToFile(@"[Info] Launcher 检测到已有分屏窗口: %@", bid);
            [self animateSpotlight:NO fromPoint:self.panelContainer.center velocity:0.0];
            [existingWindow restoreFromStash];
            return;
        }

        // 记录使用频率（带时间戳）
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
            NSMutableDictionary *usage = [[defaults dictionaryForKey:@"CV3AppUsageData"] mutableCopy] ?: [NSMutableDictionary dictionary];
            NSMutableArray *timestamps = [usage[bid] mutableCopy] ?: [NSMutableArray array];
            [timestamps addObject:@([[NSDate date] timeIntervalSince1970])];
            if (timestamps.count > 20) [timestamps removeObjectAtIndex:0];
            usage[bid] = timestamps;
            [defaults setObject:usage forKey:@"CV3AppUsageData"];
            [defaults synchronize];
        });

        [self.searchField resignFirstResponder];
        [self animateSpotlight:NO fromPoint:self.panelContainer.center velocity:0.0];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.05 * NSEC_PER_SEC)), dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
            [[NSClassFromString(@"LSApplicationWorkspace") defaultWorkspace] openApplicationWithBundleID:bid];
        });
    }
}

- (void)searchTextChanged:(UITextField *)textField {
    [self filterApps];
}

// 建议 2：透视穿孔效果 (Holographic Punch-through)
- (void)updateRefractionEffect {
    if (!self.isPanelShowing) return;
    // 使用 CIFilter 模拟光学穿孔效果
    self.distortionFilter = [CIFilter filterWithName:@"CIDisplacementDistortion"];
    [self.distortionFilter setValue:[CIImage imageWithColor:[CIColor colorWithRed:0 green:0 blue:0]] forKey:kCIInputImageKey];
    // 动态调整畸变参数
    self.refractionView.layer.filters = @[self.distortionFilter];
}

// 建议 2：应用“衰老”效果 (Entropy Archive)
- (void)applyAgingEffectToCell:(CV3AppCell *)cell withInfo:(CV3AppInfo *)info {
    NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
    NSTimeInterval age = now - info.lastUsedDate;
    
    // 超过 7 天未使用的应用变灰
    if (age > 7 * 24 * 3600) {
        cell.alpha = 0.6;
        cell.iconView.layer.borderColor = [UIColor grayColor].CGColor;
    } else {
        cell.alpha = 1.0;
    }
}

- (void)filterApps {
    self.interactionCount++;
    
    NSString *text = [self.searchField.text lowercaseString];
    
    BOOL hasSearch = (text && text.length > 0);
    BOOL isRecentlyUsed = [self.selectedCategory isEqualToString:@"最近使用"];
    BOOL isPinnedView = [self.selectedCategory isEqualToString:@"置顶"];
    BOOL hasCategory = (self.selectedCategory && ![self.selectedCategory isEqualToString:@"全部"] && !isRecentlyUsed && !isPinnedView);

    NSMutableArray *res = [NSMutableArray array];
    
    if (isRecentlyUsed) {
        for (CV3AppInfo *info in self.recentlyUsedApps) {
            if (!hasSearch || ([info.name rangeOfString:text options:NSCaseInsensitiveSearch].location != NSNotFound ||
                               [info.bundleId rangeOfString:text options:NSCaseInsensitiveSearch].location != NSNotFound ||
                               (info.pinyinInitial && [info.pinyinInitial rangeOfString:text].location != NSNotFound))) {
                [res addObject:info];
            }
        }
    } else if (isPinnedView) {
        for (CV3AppInfo *info in self.apps) {
            if (info.isPinned) {
                if (!hasSearch || ([info.name rangeOfString:text options:NSCaseInsensitiveSearch].location != NSNotFound ||
                                   [info.bundleId rangeOfString:text options:NSCaseInsensitiveSearch].location != NSNotFound ||
                                   (info.pinyinInitial && [info.pinyinInitial rangeOfString:text].location != NSNotFound))) {
                    [res addObject:info];
                }
            }
        }
    } else {
        for (CV3AppInfo *info in self.apps) {
            BOOL matchSearch = YES;
            if (hasSearch) {
                matchSearch = ([info.name rangeOfString:text options:NSCaseInsensitiveSearch].location != NSNotFound ||
                               [info.bundleId rangeOfString:text options:NSCaseInsensitiveSearch].location != NSNotFound ||
                               (info.pinyinInitial && [info.pinyinInitial rangeOfString:text].location != NSNotFound));
            }
            
            BOOL matchCategory = YES;
            if (hasCategory) {
                matchCategory = [info.category isEqualToString:self.selectedCategory];
            }
            
            if (matchSearch && matchCategory) {
                // 应用衰老效果
                [self applyAgingEffectToCell:nil withInfo:info];
                [res addObject:info];
            }
        }
    }

    self.filteredApps = res;
    
    [self.collectionView reloadData];
    
    // 调用引力布局
    [self updateMagneticLayout];
    
    // 建议 4 & 5：涟漪动效与首项吸附
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.01 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self animateIconsStaggered];
        if (hasSearch && self.filteredApps.count > 0) {
            [self.feedback impactOccurredWithIntensity:0.75];
        }
    });

    // 优化：仅在必要时刷新 inputAccessoryView
    if (!hasSearch) {
        if (!self.searchField.inputAccessoryView && self.apps.count > 0) {
            NSArray *topApps = [self.apps subarrayWithRange:NSMakeRange(0, MIN(5, self.apps.count))];
            __weak typeof(self) weakSelf = self;
            self.searchField.inputAccessoryView = [[CV3QuickAccessView alloc] initWithApps:topApps selectionHandler:^(CV3AppInfo *appInfo) {
                [weakSelf launchApp:appInfo];
            }];
            [self.searchField reloadInputViews];
        }
    } else {
        if (self.searchField.inputAccessoryView) {
            self.searchField.inputAccessoryView = nil;
            [self.searchField reloadInputViews];
        }
    }
    self.noResultsLabel.hidden = (self.filteredApps.count > 0);
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    if (textField == self.searchField) {
        if (self.filteredApps.count > 0) {
            [self launchApp:self.filteredApps[0]];
        } else {
            [textField resignFirstResponder];
        }
        return NO;
    }
    return YES;
}

- (void)textFieldDidBeginEditing:(UITextField *)textField {
    if (textField == self.searchField) {
        UIView *container = textField.superview;
        
        // 建议2：搜索框液态响应 (Liquid Search Focus)
        // 面板圆角呼吸动画：28pt -> 32pt -> 28pt
        CABasicAnimation *cornerAnim = [CABasicAnimation animationWithKeyPath:@"cornerRadius"];
        cornerAnim.fromValue = @(kChevronLayoutConstants.cornerRadius);
        cornerAnim.toValue = @(32.0);
        cornerAnim.duration = 0.6;
        cornerAnim.autoreverses = YES;
        cornerAnim.repeatCount = HUGE_VALF;
        cornerAnim.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
        [self.appPanel.layer addAnimation:cornerAnim forKey:@"liquidCorner"];
        [self.innerGlowLayer addAnimation:cornerAnim forKey:@"liquidCorner"];
        [self.dispersionContainer.layer addAnimation:cornerAnim forKey:@"liquidCorner"];

        // 1. 基础缩放与阴影动画
        [UIView animateWithDuration:0.5 delay:0 options:UIViewAnimationOptionAutoreverse | UIViewAnimationOptionRepeat | UIViewAnimationOptionAllowUserInteraction animations:^{
            container.transform = CGAffineTransformMakeScale(1.02, 1.02);
            self.searchBackground.shadowColor = [UIColor labelColor].CGColor;
            self.searchBackground.shadowOffset = CGSizeZero;
            self.searchBackground.shadowOpacity = 0.4;
            self.searchBackground.shadowRadius = 8.0;
        } completion:nil];

        // 2. 液态形变路径动画 (Deformation)
        CGRect b = self.searchBackground.bounds;
        UIBezierPath *liquidPath = [UIBezierPath bezierPath];
        CGFloat offset = 4.0;
        [liquidPath moveToPoint:CGPointMake(10, 0)];
        [liquidPath addQuadCurveToPoint:CGPointMake(b.size.width-10, 0) controlPoint:CGPointMake(b.size.width/2, -offset)];
        [liquidPath addQuadCurveToPoint:CGPointMake(b.size.width, 10) controlPoint:CGPointMake(b.size.width+offset, 0)];
        [liquidPath addQuadCurveToPoint:CGPointMake(b.size.width, b.size.height-10) controlPoint:CGPointMake(b.size.width-offset, b.size.height/2)];
        [liquidPath addQuadCurveToPoint:CGPointMake(b.size.width-10, b.size.height) controlPoint:CGPointMake(b.size.width, b.size.height+offset)];
        [liquidPath addQuadCurveToPoint:CGPointMake(10, b.size.height) controlPoint:CGPointMake(b.size.width/2, b.size.height-offset)];
        [liquidPath addQuadCurveToPoint:CGPointMake(0, b.size.height-10) controlPoint:CGPointMake(-offset, b.size.height)];
        [liquidPath addQuadCurveToPoint:CGPointMake(0, 10) controlPoint:CGPointMake(offset, b.size.height/2)];
        [liquidPath addQuadCurveToPoint:CGPointMake(10, 0) controlPoint:CGPointMake(0, -offset)];
        [liquidPath closePath];

        CABasicAnimation *pathAnim = [CABasicAnimation animationWithKeyPath:@"path"];
        pathAnim.toValue = (id)liquidPath.CGPath;
        pathAnim.duration = 0.4;
        pathAnim.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
        pathAnim.fillMode = kCAFillModeForwards;
        pathAnim.removedOnCompletion = NO;
        [self.searchBackground addAnimation:pathAnim forKey:@"liquidPath"];

        // 3. 边框颜色流转
        CABasicAnimation *colorAnim = [CABasicAnimation animationWithKeyPath:@"strokeColor"];
        colorAnim.fromValue = (id)self.searchBackground.strokeColor;
        colorAnim.toValue = (id)[[UIColor cyanColor] colorWithAlphaComponent:0.6].CGColor;
        colorAnim.duration = 1.5;
        colorAnim.autoreverses = YES;
        colorAnim.repeatCount = HUGE_VALF;
        [self.searchBackground addAnimation:colorAnim forKey:@"colorFlow"];
    }
}

- (void)textFieldDidEndEditing:(UITextField *)textField {
    if (textField == self.searchField) {
        UIView *container = textField.superview;
        [container.layer removeAllAnimations];
        [self.searchBackground removeAllAnimations];
        [self.appPanel.layer removeAnimationForKey:@"liquidCorner"];
        [self.innerGlowLayer removeAnimationForKey:@"liquidCorner"];
        [self.dispersionContainer.layer removeAnimationForKey:@"liquidCorner"];

        [UIView animateWithDuration:0.3 animations:^{
            container.transform = CGAffineTransformIdentity;
            self.searchBackground.shadowOpacity = 0;
            self.searchBackground.shadowRadius = 0;
            self.searchBackground.path = [UIBezierPath bezierPathWithRoundedRect:self.searchBackground.bounds cornerRadius:10].CGPath;
            self.searchBackground.strokeColor = [[UIColor whiteColor] colorWithAlphaComponent:0.1].CGColor;
        }];
    }
}

- (void)collectionView:(UICollectionView *)cv didHighlightItemAtIndexPath:(NSIndexPath *)indexPath {
    UICollectionViewCell *cell = [cv cellForItemAtIndexPath:indexPath];
    [UIView animateWithDuration:0.2 delay:0 options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction animations:^{
        // 放大 1.1x 并向上漂浮 5pt，模拟 macOS Dock 的悬停/追踪感
        cell.transform = CGAffineTransformMakeScale(1.1, 1.1);
        cell.contentView.transform = CGAffineTransformMakeTranslation(0, -5);
    } completion:nil];
}

- (void)collectionView:(UICollectionView *)cv didUnhighlightItemAtIndexPath:(NSIndexPath *)indexPath {
    UICollectionViewCell *cell = [cv cellForItemAtIndexPath:indexPath];
    [UIView animateWithDuration:0.4 delay:0 usingSpringWithDamping:0.5 initialSpringVelocity:0.5 options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction animations:^{
        cell.transform = CGAffineTransformIdentity;
        cell.contentView.transform = CGAffineTransformIdentity;
    } completion:nil];
}

- (void)collectionView:(UICollectionView *)cv didSelectItemAtIndexPath:(NSIndexPath *)indexPath {
    UICollectionViewCell *cell = [cv cellForItemAtIndexPath:indexPath];
    
    // 立即提供物理点击感：微缩动画
    [UIView animateWithDuration:0.15 delay:0 options:UIViewAnimationOptionBeginFromCurrentState animations:^{
        cell.transform = CGAffineTransformMakeScale(0.9, 0.9);
    } completion:^(BOOL finished) {
        [UIView animateWithDuration:0.3 delay:0 usingSpringWithDamping:0.5 initialSpringVelocity:0.5 options:0 animations:^{
            cell.transform = CGAffineTransformIdentity;
        } completion:nil];
    }];

    if (indexPath.item < self.filteredApps.count) {
        [self launchApp:self.filteredApps[indexPath.item]];
    }
}

- (CGSize)calculateMaxPanelSize {
    UIInterfaceOrientation orientation = self.targetOrientation != UIInterfaceOrientationUnknown ? self.targetOrientation : UIInterfaceOrientationPortrait;
    BOOL isLandscape = (orientation == UIInterfaceOrientationLandscapeLeft || orientation == UIInterfaceOrientationLandscapeRight);
    UIEdgeInsets safe = self.safeAreaInsets;
    CGFloat w = self.bounds.size.width;
    CGFloat h = self.bounds.size.height;
    CGFloat maxW, maxH;
    
    if (isLandscape) {
        maxW = h - (safe.top + safe.bottom + kChevronLayoutConstants.safeAreaBreath * 2);
        maxH = w - (safe.left + safe.right + kChevronLayoutConstants.safeAreaBreath * 2);
    } else {
        maxW = w - (safe.left + safe.right + kChevronLayoutConstants.safeAreaBreath * 2);
        maxH = h - (safe.top + safe.bottom + kChevronLayoutConstants.safeAreaBreath * 2);
    }
    return CGSizeMake(maxW, maxH);
}

- (NSString *)_role {
    return @"SBWindowRoleFloatingCanHostLaunchpad"; 
}

- (BOOL)_canAffectStatusBarAppearance { return NO; }

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldReceiveTouch:(UITouch *)touch {
    // 允许调整大小手势
    if (gestureRecognizer.view == self.resizingHandle) {
        return YES;
    }

    // 拦截面板移动手势
    if (gestureRecognizer.view == self.panelContainer && ![gestureRecognizer isKindOfClass:[UIScreenEdgePanGestureRecognizer class]]) {
        CGPoint location = [touch locationInView:self.panelContainer];
        // 限制：仅标题栏（顶部 45pt）才允许触发移动
        // 同时确保不在右下角的调整把手区域（虽然 45pt 已经排除了大部分，但为了严谨性保留逻辑）
        BOOL isHeader = (location.y <= 45.0);
        BOOL isHandle = CGRectContainsPoint(self.resizingHandle.frame, location);

        if (!isHeader || isHandle) {
            return NO;
        }
    }

    return YES;
}

- (NSString *)currentActiveBundleID {
    @try {
        id workspace = [NSClassFromString(@"SBMainWorkspace") sharedInstance];
        id activeItem = nil;
        if ([workspace respondsToSelector:@selector(activeDisplayItem)]) {
            activeItem = [workspace performSelector:@selector(activeDisplayItem)];
        }
        if (activeItem && [activeItem respondsToSelector:@selector(bundleIdentifier)]) {
            return [activeItem performSelector:@selector(bundleIdentifier)];
        }
    } @catch (NSException *e) {}
    return nil;
}

- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)gesture {
    if (gesture == self.systemEdgePan) {
        // 使用与 handleEdgeInteraction 一致的安全绝对坐标系
        CGPoint location = [gesture locationInView:nil];
        
        UIWindow *keyWindow = nil;
        if (@available(iOS 15.0, *)) {
            keyWindow = self.windowScene.keyWindow;
        } else {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
            keyWindow = [UIApplication sharedApplication].keyWindow;
#pragma clang diagnostic pop
        }
        
        // 动态获取准确的安全区域和边界
        UIEdgeInsets safeArea = keyWindow ? keyWindow.safeAreaInsets : self.safeAreaInsets;
        // 如果系统返回的 safeArea 全是 0，提供硬编码的兜底防线
        if (safeArea.top == 0 && safeArea.bottom == 0) {
            safeArea = UIEdgeInsetsMake(47, 0, 34, 0); // iPhone 14 Pro Max 典型值兜底
        }

        CGSize screenSize = [UIScreen mainScreen].bounds.size;
        
        // 根据当前的 edges 动态拦截
        if (self.systemEdgePan.edges == UIRectEdgeLeft || self.systemEdgePan.edges == UIRectEdgeRight) {
            // 垂直方向边缘（Portrait）: 限制 Y 轴
            if (location.y < safeArea.top + 10 || location.y > screenSize.height - safeArea.bottom - 10) {
                return NO;
            }
        } else if (self.systemEdgePan.edges == UIRectEdgeTop || self.systemEdgePan.edges == UIRectEdgeBottom) {
            // 水平方向边缘（Landscape）: 限制 X 轴
            if (location.x < safeArea.left + 10 || location.x > screenSize.width - safeArea.right - 10) {
                return NO;
            }
        }
        
        return YES;
    }
    return YES;
}


- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldBeRequiredToFailByGestureRecognizer:(UIGestureRecognizer *)otherGestureRecognizer {
    return NO;
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldRequireFailureOfGestureRecognizer:(UIGestureRecognizer *)otherGestureRecognizer {
    return NO;
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)otherGestureRecognizer {
    if (gestureRecognizer == self.systemEdgePan || otherGestureRecognizer == self.systemEdgePan) {
        return YES; // 允许与其他手势并发，避免被系统侧滑手势完全阻断
    }

    // 禁止拖拽手势与调整大小手势同时发生
    if (([gestureRecognizer isKindOfClass:[UIPanGestureRecognizer class]] && otherGestureRecognizer.view == self.resizingHandle) ||
        (gestureRecognizer.view == self.resizingHandle && [otherGestureRecognizer isKindOfClass:[UIPanGestureRecognizer class]])) {
        return NO;
    }
    return YES;
}
- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        if (!cv3IconCache) {
            cv3IconCache = [[NSCache alloc] init];
            cv3IconCache.countLimit = 150; // 防御 Jetsam: 限制最大缓存数量
            cv3IconCache.totalCostLimit = 150 * 1024 * 1024; // 防御 Jetsam: 限制最大成本 (约 150MB)
        }
        [self applyAdaptiveLevel];
        self.backgroundColor = [UIColor clearColor];
        self.apps = [NSMutableArray array];
        self.feedback = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleHeavy];
        self.selectionFeedback = [[UISelectionFeedbackGenerator alloc] init];
        self.motionManager = [[CMMotionManager alloc] init];
        self.motionManager.deviceMotionUpdateInterval = 1.0 / 120.0;
        
        // 初始化边缘预警层
        self.triggerPreviewLayer = [CAGradientLayer layer];
        self.triggerPreviewLayer.type = kCAGradientLayerRadial;
        self.triggerPreviewLayer.colors = @[(id)[[UIColor cyanColor] colorWithAlphaComponent:0.3].CGColor, (id)[UIColor clearColor].CGColor];
        self.triggerPreviewLayer.startPoint = CGPointMake(0.5, 0.5);
        self.triggerPreviewLayer.endPoint = CGPointMake(1, 1);
        self.triggerPreviewLayer.opacity = 0;
        [self.layer addSublayer:self.triggerPreviewLayer];
        
        CV3RootViewController *rootVC = [[CV3RootViewController alloc] init];
        rootVC.view.backgroundColor = [UIColor clearColor];
        self.rootViewController = rootVC;
        self.baseRotationTransform = CGAffineTransformIdentity;
        
        // 加载置顶应用数据
        NSArray *savedPinned = [[NSUserDefaults standardUserDefaults] objectForKey:@"CV3PinnedApps"];
        self.pinnedBundleIDs = savedPinned ? [NSMutableSet setWithArray:savedPinned] : [NSMutableSet set];

        [self setupUI];
        
        // 注册应用安装/卸载观察者
        id ws = [NSClassFromString(@"LSApplicationWorkspace") defaultWorkspace];
        if ([ws respondsToSelector:@selector(addObserver:)]) {
            [ws performSelector:@selector(addObserver:) withObject:[CV3AppObserver sharedObserver]];
        }
    }
    return self;
}

- (void)setupUI {
    CGRect bounds = self.bounds;

    self.edgeTriggerView = [[UIView alloc] initWithFrame:CGRectZero];
    self.edgeTriggerView.backgroundColor = [UIColor clearColor];
    self.edgeTriggerView.userInteractionEnabled = NO;
    self.edgeTriggerView.autoresizingMask = UIViewAutoresizingNone;
    [self.rootViewController.view addSubview:self.edgeTriggerView];
    
    // 创建边缘手势
    self.systemEdgePan = [[UIScreenEdgePanGestureRecognizer alloc] initWithTarget:self action:@selector(handleEdgeInteraction:)];
    self.systemEdgePan.edges = UIRectEdgeRight;
    self.systemEdgePan.delegate = self;
    
    @try {
        SBSystemGestureManager *manager = [%c(SBSystemGestureManager) mainDisplayManager];
        [manager addGestureRecognizer:self.systemEdgePan withType:112];
    } @catch (NSException *e) {}
    
    self.dimmingView = [[UIView alloc] initWithFrame:bounds];
    self.dimmingView.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.15];
    self.dimmingView.alpha = 0;
    self.dimmingView.userInteractionEnabled = NO; // 初始关闭
    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleDimmingTap:)];
    [self.dimmingView addGestureRecognizer:tap];
    [self.rootViewController.view addSubview:self.dimmingView];
    
    self.bezierContainer = [[UIView alloc] initWithFrame:bounds];
    self.bezierContainer.alpha = 0;
    self.bezierContainer.userInteractionEnabled = NO;
    self.bezierContainer.autoresizingMask = UIViewAutoresizingNone;
    [self.rootViewController.view addSubview:self.bezierContainer];
    
    self.bezierBlur = [[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemUltraThinMaterial]];
    self.bezierBlur.frame = bounds;
    self.bezierBlur.autoresizingMask = UIViewAutoresizingNone;
    [self.bezierContainer addSubview:self.bezierBlur];
    self.bezierLayer = [CAShapeLayer layer];
    self.bezierLayer.fillColor = [UIColor labelColor].CGColor;
    self.bezierBlur.layer.mask = self.bezierLayer; 
    
    self.panelContainer = [[UIView alloc] initWithFrame:CGRectMake(0, 0, kChevronLayoutConstants.panelW, kChevronLayoutConstants.panelH)];
    self.panelContainer.backgroundColor = [UIColor clearColor];
    self.panelContainer.hidden = YES;
    self.panelContainer.layer.shadowColor = [UIColor blackColor].CGColor;
    self.panelContainer.layer.shadowOffset = CGSizeMake(0, 0); // 居中阴影，四周扩散
    self.panelContainer.layer.shadowOpacity = 0.7; // 加深不透明度凸显聚焦
    self.panelContainer.layer.shadowRadius = 60; // 扩大阴影半径
    self.panelContainer.autoresizingMask = UIViewAutoresizingNone;
    [self.rootViewController.view addSubview:self.panelContainer];
    
    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handlePanelDrag:)];
    pan.delegate = self;
    [self.panelContainer addGestureRecognizer:pan];

    // 添加双击手势用于快速激活搜索
    UITapGestureRecognizer *doubleTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleDoubleTap:)];
    doubleTap.numberOfTapsRequired = 2;
    doubleTap.delegate = self;
    [self.panelContainer addGestureRecognizer:doubleTap];

    self.appPanel = [[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemUltraThinMaterial]];    self.appPanel.frame = self.panelContainer.bounds;
    self.appPanel.backgroundColor = [[UIColor clearColor] colorWithAlphaComponent:0.0]; // 移除黄色测试色
    self.appPanel.layer.cornerRadius = kChevronLayoutConstants.cornerRadius;
    if (@available(iOS 13.0, *)) {
        self.appPanel.layer.cornerCurve = kCACornerCurveContinuous;
    }
    self.appPanel.layer.masksToBounds = YES;
    self.appPanel.layer.borderWidth = 0.4;
    self.appPanel.layer.borderColor = [[UIColor labelColor] colorWithAlphaComponent:0.2].CGColor;
    
    // 1. 对比度增强层 (Contrast Booster): 极淡的黑色，用于压住背景杂色，让 App 图标更浮出
    self.contrastBackdrop = [[UIView alloc] initWithFrame:self.appPanel.bounds];
    self.contrastBackdrop.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.025];
    self.contrastBackdrop.userInteractionEnabled = NO;
    [self.appPanel.contentView addSubview:self.contrastBackdrop];

    // 2. 冰川蓝注入层 (Ice Tint): 抵消毛玻璃自带的脏灰感，提升视觉通透度
    self.whiteFilter = [[UIView alloc] initWithFrame:self.appPanel.bounds];
    self.whiteFilter.backgroundColor = [UIColor colorWithRed:0.0 green:0.8 blue:1.0 alpha:0.012];
    self.whiteFilter.userInteractionEnabled = NO;
    [self.appPanel.contentView addSubview:self.whiteFilter];

    // 3. 极致精致感：0.3pt 白色内发光 (Inner Glow)
    // 这种极细的高亮边框能赋予面板物理实体的“边缘折射”感
    self.innerGlowLayer = [CALayer layer];
    self.innerGlowLayer.frame = self.appPanel.bounds;
    self.innerGlowLayer.borderColor = [[UIColor labelColor] colorWithAlphaComponent:0.45].CGColor;
    self.innerGlowLayer.borderWidth = 0.3;
    self.innerGlowLayer.cornerRadius = kChevronLayoutConstants.cornerRadius;
    if (@available(iOS 13.0, *)) {
        self.innerGlowLayer.cornerCurve = kCACornerCurveContinuous;
    }
    [self.appPanel.layer addSublayer:self.innerGlowLayer];

    self.specularHighlight = [CAGradientLayer layer];
    self.specularHighlight.frame = self.appPanel.bounds;
    self.specularHighlight.colors = @[(id)[[UIColor labelColor] colorWithAlphaComponent:0.0].CGColor, (id)[[UIColor labelColor] colorWithAlphaComponent:0.07].CGColor, (id)[[UIColor labelColor] colorWithAlphaComponent:0.0].CGColor];
    [self.appPanel.layer addSublayer:self.specularHighlight];

    self.dispersionContainer = [[UIView alloc] initWithFrame:self.appPanel.bounds];
    self.dispersionContainer.layer.cornerRadius = kChevronLayoutConstants.cornerRadius;
    if (@available(iOS 13.0, *)) {
        self.dispersionContainer.layer.cornerCurve = kCACornerCurveContinuous;
    }
    self.dispersionContainer.layer.masksToBounds = YES;
    self.dispersionContainer.userInteractionEnabled = NO;
    [self.appPanel.contentView addSubview:self.dispersionContainer];
    
    self.cyanLayer = [CALayer layer]; 
    self.cyanLayer.frame = CGRectInset(self.dispersionContainer.bounds, -0.3, -0.3);
    
    // 创意：光学折射层 (Negative Lens Effect)
    self.refractionView = [[UIView alloc] initWithFrame:self.appPanel.bounds];
    self.refractionView.userInteractionEnabled = NO;
    self.refractionView.layer.compositingFilter = @"overlayBlendMode";
    [self.appPanel.contentView addSubview:self.refractionView];

    self.cyanLayer.borderColor = [[UIColor cyanColor] colorWithAlphaComponent:0.12].CGColor; 
    self.cyanLayer.borderWidth = 0.3; 
    [self.dispersionContainer.layer addSublayer:self.cyanLayer];
    
    self.magentaLayer = [CALayer layer]; 
    self.magentaLayer.frame = CGRectInset(self.dispersionContainer.bounds, 0.3, 0.3); 
    self.magentaLayer.borderColor = [[UIColor magentaColor] colorWithAlphaComponent:0.12].CGColor; 
    self.magentaLayer.borderWidth = 0.3; 
    [self.dispersionContainer.layer addSublayer:self.magentaLayer];

    [self.panelContainer addSubview:self.appPanel];

    // 终极融合系统：初始化全屏投影层
    self.projectionView = [[UIView alloc] initWithFrame:self.bounds];
    self.projectionView.userInteractionEnabled = NO;
    self.projectionView.layer.compositingFilter = @"plusLighterBlendMode";
    self.projectionView.alpha = 0.3;
    [self.rootViewController.view insertSubview:self.projectionView atIndex:0];

    // 建议 1-3：主动交互图层初始化
    self.trailLayer = [CAShapeLayer layer];
    self.trailLayer.strokeColor = [[UIColor whiteColor] colorWithAlphaComponent:0.4].CGColor;
    self.trailLayer.lineWidth = 4.0;
    self.trailLayer.lineCap = kCALineCapRound;
    [self.rootViewController.view.layer addSublayer:self.trailLayer];
    
    self.lightWaveView = [[UIView alloc] initWithFrame:self.bounds];
    self.lightWaveView.userInteractionEnabled = NO;
    self.lightWaveView.backgroundColor = [UIColor clearColor];
    [self.rootViewController.view addSubview:self.lightWaveView];

    // 建议 1：初始化光纤导光图层 (Fiber-Optic Setup)
    // 这些光晕位于最底层，用于模拟玻璃内部的导光效果
    NSArray *glowColors = @[[UIColor colorWithRed:1.00 green:0.37 blue:0.33 alpha:1.0], 
                           [UIColor colorWithRed:1.00 green:0.75 blue:0.18 alpha:1.0], 
                           [UIColor colorWithRed:0.15 green:0.79 blue:0.25 alpha:1.0]];
    for (int i = 0; i < 3; i++) {
        CAGradientLayer *glow = [CAGradientLayer layer];
        glow.frame = CGRectMake(0, 0, 150, 150);
        glow.type = kCAGradientLayerRadial;
        glow.colors = @[(id)[glowColors[i] colorWithAlphaComponent:0.08].CGColor, (id)[UIColor clearColor].CGColor];
        glow.startPoint = CGPointMake(0.5, 0.5);
        glow.endPoint = CGPointMake(1.0, 1.0);
        glow.hidden = YES; // 初始隐藏，仅在面板显示时激活
        [self.appPanel.layer insertSublayer:glow atIndex:0];
        if (i == 0) self.redGlow = glow;
        else if (i == 1) self.yellowGlow = glow;
        else self.greenGlow = glow;
    }

    self.trafficCapsule = [[UIView alloc] initWithFrame:CGRectMake(16, 14, kChevronLayoutConstants.trafficCapsuleW, kChevronLayoutConstants.trafficCapsuleH)];
    self.trafficCapsule.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.08];
    self.trafficCapsule.layer.cornerRadius = kChevronLayoutConstants.trafficCapsuleH / 2.0;
    [self.panelContainer addSubview:self.trafficCapsule];
    
    NSMutableArray *dots = [NSMutableArray array];
    NSArray *tc = @[[UIColor colorWithRed:1.00 green:0.37 blue:0.33 alpha:1.0], [UIColor colorWithRed:1.00 green:0.75 blue:0.18 alpha:1.0], [UIColor colorWithRed:0.15 green:0.79 blue:0.25 alpha:1.0]];
    for (int i = 0; i < 3; i++) {
        UIButton *dotBtn = [UIButton buttonWithType:UIButtonTypeCustom];
        // 扩展热区：每个按钮占据更大的点击范围 (约 17.3x24)
        CGFloat btnW = (kChevronLayoutConstants.trafficCapsuleW - 12) / 3.0;
        dotBtn.frame = CGRectMake(6 + i * btnW, 0, btnW, kChevronLayoutConstants.trafficCapsuleH);
        
        // 视觉圆点作为子视图，保持原有 8x8 外观
        UIView *visualDot = [[UIView alloc] initWithFrame:CGRectMake((btnW - kChevronLayoutConstants.trafficDotSize)/2, (kChevronLayoutConstants.trafficCapsuleH - kChevronLayoutConstants.trafficDotSize)/2, kChevronLayoutConstants.trafficDotSize, kChevronLayoutConstants.trafficDotSize)];
        visualDot.backgroundColor = tc[i];
        visualDot.layer.cornerRadius = kChevronLayoutConstants.trafficDotSize / 2.0;
        visualDot.userInteractionEnabled = NO;
        [dotBtn addSubview:visualDot];
        
        dotBtn.tag = i;
        [dotBtn addTarget:self action:@selector(handleTrafficLight:) forControlEvents:UIControlEventTouchDown];
        
        // 增加按钮点击的微缩视觉反馈
        [dotBtn addTarget:self action:@selector(btnTouchDown:) forControlEvents:UIControlEventTouchDown];
        [dotBtn addTarget:self action:@selector(btnTouchUp:) forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside | UIControlEventTouchCancel];
        
        [self.trafficCapsule addSubview:dotBtn];
        [dots addObject:visualDot]; // 存储视觉圆点用于颜色更新
    }
    self.trafficDots = dots;

#pragma mark - Search Bar Setup
    UIView *searchContainer = [[UIView alloc] initWithFrame:CGRectMake(15, 50, kChevronLayoutConstants.panelW - 30, 36)];
    searchContainer.backgroundColor = [UIColor clearColor];
    [self.appPanel.contentView addSubview:searchContainer];

    // 液态背景层
    self.searchBackground = [CAShapeLayer layer];
    self.searchBackground.frame = searchContainer.bounds;
    self.searchBackground.path = [UIBezierPath bezierPathWithRoundedRect:searchContainer.bounds cornerRadius:10].CGPath;
    self.searchBackground.fillColor = [[UIColor labelColor] colorWithAlphaComponent:0.06].CGColor;
    self.searchBackground.strokeColor = [[UIColor labelColor] colorWithAlphaComponent:0.1].CGColor;
    self.searchBackground.lineWidth = 0.4;
    [searchContainer.layer addSublayer:self.searchBackground];
    
    self.searchField = [[UITextField alloc] initWithFrame:CGRectInset(searchContainer.bounds, 10, 0)];
    self.searchField.placeholder = @"搜索应用...";
    self.searchField.textColor = [UIColor labelColor];
    self.searchField.font = [UIFont systemFontOfSize:14];
    self.searchField.tintColor = [UIColor labelColor];
    // 设置占位符颜色
    self.searchField.attributedPlaceholder = [[NSAttributedString alloc] initWithString:@"搜索应用..." attributes:@{NSForegroundColorAttributeName: [UIColor secondaryLabelColor]}];
    [self.searchField addTarget:self action:@selector(searchTextChanged:) forControlEvents:UIControlEventEditingChanged];
    self.searchField.delegate = self;
    self.searchField.returnKeyType = UIReturnKeySearch;
    self.searchField.clearButtonMode = UITextFieldViewModeWhileEditing; // 启用清空按钮
    [searchContainer addSubview:self.searchField];

#pragma mark - No Results Label Setup
    self.noResultsLabel = [[UILabel alloc] initWithFrame:CGRectMake(0, 150, kChevronLayoutConstants.panelW, 40)];
    self.noResultsLabel.text = @"未找到相关应用";
    self.noResultsLabel.textColor = [UIColor secondaryLabelColor];
    self.noResultsLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightMedium];
    self.noResultsLabel.textAlignment = NSTextAlignmentCenter;
    self.noResultsLabel.hidden = YES;
    [self.appPanel.contentView addSubview:self.noResultsLabel];

    self.selectedCategory = @"全部";
    self.categoryBar = [[UIScrollView alloc] initWithFrame:CGRectMake(15, 96, kChevronLayoutConstants.panelW - 30, 40)];
    self.categoryBar.showsHorizontalScrollIndicator = NO;
    self.categoryBar.backgroundColor = [UIColor clearColor];
    [self.appPanel.contentView addSubview:self.categoryBar];

    self.resizingHandle = [[CV3ResizeHandleView alloc] initWithFrame:CGRectMake(kChevronLayoutConstants.panelW - 40, kChevronLayoutConstants.panelH - 40, 40, 40)];
    self.resizingHandle.backgroundColor = [UIColor clearColor];
    [self.panelContainer addSubview:self.resizingHandle];
    
    self.resizingHandleLayer = [CAShapeLayer layer];
    // 视觉优化：将把手弧度中心与面板 28pt 圆角中心对齐 (12, 12)
    // 半径统一调整为 24pt，与分屏窗口保持一致的 4pt 平行间距
    CGFloat panelArcRadius = 24.0;
    CGFloat panelCenterAngle = M_PI_4;
    CGFloat panelHalfSweep = M_PI / 8.0; 
    self.resizingHandleLayer.path = [UIBezierPath bezierPathWithArcCenter:CGPointMake(12, 12) 
                                                                  radius:panelArcRadius 
                                                              startAngle:panelCenterAngle - panelHalfSweep 
                                                                endAngle:panelCenterAngle + panelHalfSweep 
                                                               clockwise:YES].CGPath;
    self.resizingHandleLayer.fillColor = [UIColor clearColor].CGColor;
    self.resizingHandleLayer.strokeColor = [[UIColor labelColor] colorWithAlphaComponent:0.3].CGColor;
    self.resizingHandleLayer.lineWidth = 2.0;
    [self.resizingHandle.layer addSublayer:self.resizingHandleLayer];
    
    UIPanGestureRecognizer *resizePan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handleResize:)];
    resizePan.delegate = self;
    [self.resizingHandle addGestureRecognizer:resizePan];

    UICollectionViewFlowLayout *layout = [[UICollectionViewFlowLayout alloc] init];
    layout.itemSize = CGSizeMake(80, 100);
    layout.minimumInteritemSpacing = 5.0;
    layout.minimumLineSpacing = 10.0;
    // 调整 CollectionView 的 y 起点以避开搜索框和分类栏 (从 96 移至 140)
    self.collectionView = [[UICollectionView alloc] initWithFrame:CGRectMake(0, 140, kChevronLayoutConstants.panelW, kChevronLayoutConstants.panelH-140) collectionViewLayout:layout];
    self.collectionView.dataSource = self; self.collectionView.delegate = self;
    self.collectionView.backgroundColor = [UIColor clearColor];
    self.collectionView.delaysContentTouches = NO; // 关键：禁用触碰延迟实现即时反馈
    self.collectionView.showsVerticalScrollIndicator = NO;   // 隐藏纵向滚动条
    self.collectionView.showsHorizontalScrollIndicator = NO; // 隐藏横向滚动条
    self.collectionView.keyboardDismissMode = UIScrollViewKeyboardDismissModeOnDrag; // 滚动时自动收起键盘
    [self.collectionView registerClass:[CV3AppCell class] forCellWithReuseIdentifier:@"C"];
    [self.appPanel.contentView addSubview:self.collectionView];

    // 增加实时波纹追踪手势 (Fish-eye Effect)
    UILongPressGestureRecognizer *waveTracker = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(handleWaveGesture:)];
    waveTracker.minimumPressDuration = 0; // 触碰即开始追踪
    waveTracker.delegate = self;
    waveTracker.cancelsTouchesInView = NO; // 不拦截点击事件
    [self.collectionView addGestureRecognizer:waveTracker];

    // 增加长按置顶手势
    UILongPressGestureRecognizer *pinLongPress = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(handleAppLongPress:)];
    pinLongPress.minimumPressDuration = 0.6;
    pinLongPress.delegate = self;
    [self.collectionView addGestureRecognizer:pinLongPress];
}

- (void)triggerCollisionImpulse {
    // 建议 3：Chromatic Collision Impulse (边缘色散碰撞脉冲)
    // 模拟物理冲击导致的镜头组瞬时偏移
    [CATransaction begin];
    [CATransaction setAnimationDuration:0.12];
    [CATransaction setAnimationTimingFunction:[CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseOut]];
    
    // 青色/品红层向相反方向剧烈抖动后回弹
    CAKeyframeAnimation *cyanAnim = [CAKeyframeAnimation animationWithKeyPath:@"transform.translation"];
    cyanAnim.values = @[[NSValue valueWithCGPoint:CGPointMake(-4, -4)], [NSValue valueWithCGPoint:CGPointZero]];
    [self.cyanLayer addAnimation:cyanAnim forKey:@"collision"];
    
    CAKeyframeAnimation *magAnim = [CAKeyframeAnimation animationWithKeyPath:@"transform.translation"];
    magAnim.values = @[[NSValue valueWithCGPoint:CGPointMake(4, 4)], [NSValue valueWithCGPoint:CGPointZero]];
    [self.magentaLayer addAnimation:magAnim forKey:@"collision"];
    
    // 内发光瞬间增强，模拟碰撞火花
    CAKeyframeAnimation *glowAnim = [CAKeyframeAnimation animationWithKeyPath:@"borderWidth"];
    glowAnim.values = @[@2.0, @0.3];
    [self.innerGlowLayer addAnimation:glowAnim forKey:@"collision"];
    
    [CATransaction commit];
    
    // 触觉反馈：刚性碰撞
    UIImpactFeedbackGenerator *rigid = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleRigid];
    [rigid impactOccurredWithIntensity:1.0];
}

// 建议 2：Magnetic Search Attraction (磁极引力搜索)
- (void)updateMagneticLayout {
    self.isMagneticLayoutActive = (self.searchField.text.length > 0);
    
    if (self.isMagneticLayoutActive) {
        CGPoint center = CGPointMake(self.collectionView.bounds.size.width / 2, self.collectionView.bounds.size.height / 2);
        
        [UIView animateWithDuration:0.5 delay:0 usingSpringWithDamping:0.7 initialSpringVelocity:0.5 options:0 animations:^{
            NSArray *visibleCells = [self.collectionView visibleCells];
            for (UICollectionViewCell *cell in visibleCells) {
                NSIndexPath *indexPath = [self.collectionView indexPathForCell:cell];
                CGFloat weight = 1.0 - (indexPath.item / (CGFloat)self.filteredApps.count);
                
                CGFloat tx = (center.x - cell.center.x) * weight * 0.5;
                CGFloat ty = (center.y - cell.center.y) * weight * 0.5;
                cell.transform = CGAffineTransformMakeTranslation(tx, ty);
            }
        } completion:nil];
    } else {
        [UIView animateWithDuration:0.3 animations:^{
            for (UICollectionViewCell *cell in [self.collectionView visibleCells]) {
                cell.transform = CGAffineTransformIdentity;
            }
        }];
    }
}

- (void)handleAppLongPress:(UILongPressGestureRecognizer *)gesture {
    CGPoint pointInCollection = [gesture locationInView:self.collectionView];
    CGPoint pointInWindow = [gesture locationInView:self];
    
    if (gesture.state == UIGestureRecognizerStateBegan) {
        NSIndexPath *indexPath = [self.collectionView indexPathForItemAtPoint:pointInCollection];
        if (indexPath && indexPath.item < self.filteredApps.count) {
            CV3AppCell *cell = (CV3AppCell *)[self.collectionView cellForItemAtIndexPath:indexPath];
            self.draggedAppInfo = self.filteredApps[indexPath.item];
            
            [self.feedback impactOccurredWithIntensity:0.85];
            
            // 锁定 CollectionView 滚动，防止拖拽时面板跟着滑动
            self.collectionView.scrollEnabled = NO;
            
            // 创建拖拽的浮动图标
            if (cell.iconView.image) {
                self.draggedIconView = [[UIImageView alloc] initWithImage:cell.iconView.image];
                CGRect iconFrameInWindow = [self convertRect:cell.iconView.bounds fromView:cell.iconView];
                self.draggedIconView.frame = iconFrameInWindow;
                self.dragStartCenter = self.draggedIconView.center;
                
                // 核心修复：记录初始触碰偏移量，解决“跳动”问题
                self.dragTouchOffset = CGPointMake(pointInWindow.x - self.dragStartCenter.x, pointInWindow.y - self.dragStartCenter.y);
                
                [self addSubview:self.draggedIconView];
                
                [UIView animateWithDuration:0.2 animations:^{
                    self.draggedIconView.transform = CGAffineTransformMakeScale(1.2, 1.2);
                    self.draggedIconView.alpha = 0.9;
                }];
                cell.alpha = 0.3; // 降低原cell透明度
            }
        }
    } else if (gesture.state == UIGestureRecognizerStateChanged) {
        if (self.draggedIconView) {
            // 应用偏移量，使图标跟随手指但保持初始抓取点
            self.draggedIconView.center = CGPointMake(pointInWindow.x - self.dragTouchOffset.x, pointInWindow.y - self.dragTouchOffset.y);
        }
    } else if (gesture.state == UIGestureRecognizerStateEnded || gesture.state == UIGestureRecognizerStateCancelled) {
        // 恢复 CollectionView 滚动
        self.collectionView.scrollEnabled = YES;
        
        if (self.draggedIconView && self.draggedAppInfo) {
            // 判断是否拖出面板边界 (修正坐标系不匹配问题)
            CGPoint pointInContainer = [self.panelContainer convertPoint:pointInWindow fromView:self];
            BOOL isOutside = !CGRectContainsPoint(self.panelContainer.bounds, pointInContainer);
            
            if (isOutside && gesture.state == UIGestureRecognizerStateEnded) {
                [self.feedback impactOccurredWithIntensity:1.0];
                CV3LogToFile(@"[Info] 拖拽出面板，使用自带 App Hosting 开启: %@", self.draggedAppInfo.bundleId);
                
                NSString *bundleID = [self.draggedAppInfo.bundleId copy];
                dispatch_async(dispatch_get_main_queue(), ^{
                    if (!floatingWindows) {
                        floatingWindows = [NSMutableArray array];
                    }
                    
                    // 核心修复：检测是否已有该应用的分屏窗口
                    CV3FloatingAppWindow *existingWindow = nil;
                    for (CV3FloatingAppWindow *win in floatingWindows) {
                        if ([win.bundleID isEqualToString:bundleID]) {
                            existingWindow = win;
                            break;
                        }
                    }
                    
                    if (existingWindow) {
                        CV3LogToFile(@"[Info] 检测到已有分屏窗口，执行还原与聚焦: %@", bundleID);
                        [existingWindow restoreFromStash];
                    } else {
                        // 将坐标从 CV3Window 转换到屏幕坐标
                        CGPoint screenPoint = [self convertPoint:pointInWindow toWindow:nil];
                        CV3FloatingAppWindow *floatingWindow = [[CV3FloatingAppWindow alloc] initWithBundleID:bundleID center:screenPoint windowScene:self.windowScene];
                        [floatingWindows addObject:floatingWindow];
                        [floatingWindow makeKeyAndVisible];
                    }
                });
                
                // 移除浮动视图并隐藏面板
                [UIView animateWithDuration:0.3 animations:^{
                    self.draggedIconView.alpha = 0;
                    self.draggedIconView.transform = CGAffineTransformMakeScale(0.1, 0.1);
                } completion:^(BOOL finished) {
                    [self.draggedIconView removeFromSuperview];
                    self.draggedIconView = nil;
                    self.draggedAppInfo = nil;
                    [self loadAppsAsync];
                }];
                
                [self animateSpotlight:NO fromPoint:self.panelContainer.center velocity:0.0];
                
            } else {
                // 如果没有拖出去，保留原有的“置顶/取消置顶”逻辑，并动画弹回
                if ([self.pinnedBundleIDs containsObject:self.draggedAppInfo.bundleId]) {
                    [self.pinnedBundleIDs removeObject:self.draggedAppInfo.bundleId];
                } else {
                    [self.pinnedBundleIDs addObject:self.draggedAppInfo.bundleId];
                }
                
                [[NSUserDefaults standardUserDefaults] setObject:[self.pinnedBundleIDs allObjects] forKey:@"CV3PinnedApps"];
                [[NSUserDefaults standardUserDefaults] synchronize];
                
                [UIView animateWithDuration:0.3 delay:0 usingSpringWithDamping:0.7 initialSpringVelocity:0.5 options:0 animations:^{
                    self.draggedIconView.center = self.dragStartCenter;
                    self.draggedIconView.transform = CGAffineTransformIdentity;
                } completion:^(BOOL finished) {
                    [self.draggedIconView removeFromSuperview];
                    self.draggedIconView = nil;
                    self.draggedAppInfo = nil;
                    [self loadAppsAsync];
                }];
            }
        }
    }
}

- (void)handleWaveGesture:(UILongPressGestureRecognizer *)gesture {
    CGPoint location = [gesture locationInView:self.collectionView];
    
    if (gesture.state == UIGestureRecognizerStateBegan) {
        self.lastWaveHapticIndexPath = nil;
        [self.selectionFeedback prepare];
    }

    if (gesture.state == UIGestureRecognizerStateBegan || gesture.state == UIGestureRecognizerStateChanged) {
        NSArray *cells = [self.collectionView visibleCells];
        UICollectionViewCell *closestCell = nil;
        CGFloat minDistance = CGFLOAT_MAX;

        for (UICollectionViewCell *cell in cells) {
            CGPoint cellCenter = cell.center;
            CGFloat dx = location.x - cellCenter.x;
            CGFloat dy = location.y - cellCenter.y;
            CGFloat distance = sqrt(dx*dx + dy*dy);
            
            if (distance < minDistance) {
                minDistance = distance;
                closestCell = cell;
            }

            CGFloat radius = 150.0;
            CGFloat maxScale = 1.25;
            
            if (distance < radius) {
                CGFloat ratio = (radius - distance) / radius;
                CGFloat smoothRatio = 0.5 * (1.0 + cos(M_PI * (1.0 - ratio))); 
                CGFloat scale = 1.0 + (maxScale - 1.0) * smoothRatio;
                
                // 建议 1：Dynamic Lean (3D 鱼眼姿态偏移)
                // 增加 M34 透视感
                CATransform3D transform = CATransform3DIdentity;
                transform.m34 = -1.0 / 500.0;
                
                // 根据手指偏移量计算旋转角度（最大 25 度）
                CGFloat angleX = (dy / radius) * (M_PI / 7.0) * smoothRatio;
                CGFloat angleY = -(dx / radius) * (M_PI / 7.0) * smoothRatio;
                
                transform = CATransform3DRotate(transform, angleX, 1, 0, 0);
                transform = CATransform3DRotate(transform, angleY, 0, 1, 0);
                transform = CATransform3DScale(transform, scale, scale, 1.0);

                // 建议 4：Pressure Wavefronts (触控压感波动 - 物理推开效果)
                // 计算远离手指的推力位移
                CGFloat pushAmount = 18.0 * smoothRatio;
                CGFloat pushX = (distance > 0) ? -(dx / distance) * pushAmount : 0;
                CGFloat pushY = (distance > 0) ? -(dy / distance) * pushAmount : 0;

                [UIView animateWithDuration:0.1 delay:0 options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction animations:^{
                    cell.layer.transform = transform;
                    // 应用“推开”位移 + 基础浮动偏移
                    cell.contentView.transform = CGAffineTransformMakeTranslation(pushX, pushY - 10 * smoothRatio);
                    
                    if ([cell isKindOfClass:[CV3AppCell class]]) {
                        CV3AppCell *appCell = (CV3AppCell *)cell;
                        [CATransaction begin];
                        [CATransaction setDisableActions:YES];
                        appCell.iconHighlight.opacity = smoothRatio * 0.4;
                        CGFloat offsetX = dx / radius;
                        CGFloat offsetY = dy / radius;
                        appCell.iconHighlight.startPoint = CGPointMake(0.5 - offsetX, 0.5 - offsetY);
                        appCell.iconHighlight.endPoint = CGPointMake(1.0 - offsetX, 1.0 - offsetY);
                        [CATransaction commit];
                    }
                } completion:nil];
            } else {
                [UIView animateWithDuration:0.2 delay:0 options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction animations:^{
                    cell.layer.transform = CATransform3DIdentity;
                    cell.contentView.transform = CGAffineTransformIdentity;
                    if ([cell isKindOfClass:[CV3AppCell class]]) {
                        ((CV3AppCell *)cell).iconHighlight.opacity = 0;
                    }
                } completion:nil];
            }
        }

        if (closestCell && minDistance < 40.0) {
            NSIndexPath *indexPath = [self.collectionView indexPathForCell:closestCell];
            if (indexPath && (!self.lastWaveHapticIndexPath || ![indexPath isEqual:self.lastWaveHapticIndexPath])) {
                [self.selectionFeedback selectionChanged];
                self.lastWaveHapticIndexPath = indexPath;
            }
        }
    } else {
        [UIView animateWithDuration:0.4 delay:0 usingSpringWithDamping:0.6 initialSpringVelocity:0.5 options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction animations:^{
            for (UICollectionViewCell *cell in [self.collectionView visibleCells]) {
                cell.layer.transform = CATransform3DIdentity;
                cell.contentView.transform = CGAffineTransformIdentity;
                if ([cell isKindOfClass:[CV3AppCell class]]) {
                    ((CV3AppCell *)cell).iconHighlight.opacity = 0;
                }
            }
        } completion:nil];
    }
}

- (void)handleCategoryTap:(UIButton *)sender {
    [self.selectionFeedback selectionChanged]; // 模拟物理拨轮的刻度感
    
    // 从标题中解析出原始分类名，如从 "社交 (12)" 解析出 "社交"
    NSString *fullTitle = sender.titleLabel.text;
    NSString *categoryName = fullTitle;
    if ([fullTitle containsString:@" ("]) {
        categoryName = [fullTitle componentsSeparatedByString:@" ("][0];
    }
    self.selectedCategory = categoryName;
    
    // 更新按钮状态
    for (UIView *sub in self.categoryBar.subviews) {
        if ([sub isKindOfClass:[UIButton class]]) {
            UIButton *btn = (UIButton *)sub;
            NSString *btnFullTitle = btn.titleLabel.text;
            NSString *btnCatName = btnFullTitle;
            if ([btnFullTitle containsString:@" ("]) {
                btnCatName = [btnFullTitle componentsSeparatedByString:@" ("][0];
            }
            
            BOOL isSelected = [btnCatName isEqualToString:self.selectedCategory];
            btn.backgroundColor = isSelected ? [[UIColor labelColor] colorWithAlphaComponent:0.2] : [[UIColor labelColor] colorWithAlphaComponent:0.06];
            btn.layer.borderColor = isSelected ? [[UIColor cyanColor] colorWithAlphaComponent:0.5].CGColor : [[UIColor labelColor] colorWithAlphaComponent:0.1].CGColor;
        }
    }
    
    [self filterApps];
}

#pragma mark - Helper: Time-based Category Priority
static NSInteger CV3GetTimePriorityForCategory(NSString *cat) {
    NSDateComponents *components = [[NSCalendar currentCalendar] components:NSCalendarUnitHour fromDate:[NSDate date]];
    NSInteger hour = [components hour];
    
    // 定义关键字与时段的匹配权重
    // 0: 默认, 100: 高优
    
    // 早上 (6-12): 办公、效率、新闻、财务
    if (hour >= 6 && hour < 12) {
        if ([cat containsString:@"Efficiency"] || [cat containsString:@"效率"] || 
            [cat containsString:@"Productivity"] || [cat containsString:@"生产力"] ||
            [cat containsString:@"News"] || [cat containsString:@"新闻"] ||
            [cat containsString:@"Finance"] || [cat containsString:@"财务"]) return 100;
    }
    // 下午 (12-18): 购物、食物、工具、生活
    else if (hour >= 12 && hour < 18) {
        if ([cat containsString:@"Shopping"] || [cat containsString:@"购物"] || 
            [cat containsString:@"Food"] || [cat containsString:@"美食"] ||
            [cat containsString:@"Utilities"] || [cat containsString:@"工具"] ||
            [cat containsString:@"Lifestyle"] || [cat containsString:@"生活"]) return 100;
    }
    // 晚上 (18-23): 社交、游戏、娱乐、视频、音乐
    else if (hour >= 18 && hour < 23) {
        if ([cat containsString:@"Social"] || [cat containsString:@"社交"] || 
            [cat containsString:@"Game"] || [cat containsString:@"游戏"] ||
            [cat containsString:@"Entertainment"] || [cat containsString:@"娱乐"] ||
            [cat containsString:@"Video"] || [cat containsString:@"视频"] ||
            [cat containsString:@"Music"] || [cat containsString:@"音乐"]) return 100;
    }
    // 深夜 (23-6): 健康、天气、图书
    else {
        if ([cat containsString:@"Health"] || [cat containsString:@"健康"] || 
            [cat containsString:@"Weather"] || [cat containsString:@"天气"] ||
            [cat containsString:@"Book"] || [cat containsString:@"图书"]) return 100;
    }
    
    return 0;
}

- (void)updateCategoryBar {
    for (UIView *sub in self.categoryBar.subviews) [sub removeFromSuperview];
    
    // 1. 统计每个分类下的应用数量
    NSMutableDictionary *counts = [NSMutableDictionary dictionary];
    for (CV3AppInfo *info in self.apps) {
        if (info.category) {
            counts[info.category] = @([counts[info.category] integerValue] + 1);
        }
    }
    
    // 2. 排序逻辑：时间权重 > 应用数量 > 字母
    NSMutableArray *sortedCategories = [[counts allKeys] mutableCopy];
    [sortedCategories sortUsingComparator:^NSComparisonResult(NSString *c1, NSString *c2) {
        NSInteger p1 = CV3GetTimePriorityForCategory(c1);
        NSInteger p2 = CV3GetTimePriorityForCategory(c2);
        
        if (p1 != p2) return p1 > p2 ? NSOrderedAscending : NSOrderedDescending;
        
        NSInteger count1 = [counts[c1] integerValue];
        NSInteger count2 = [counts[c2] integerValue];
        if (count1 != count2) return count1 > count2 ? NSOrderedAscending : NSOrderedDescending;
        
        return [c1 localizedCaseInsensitiveCompare:c2];
    }];
    
    // 3. 始终确保“全部”排在第一位，“置顶”排在第二位，“最近使用”排在第三位
    if (self.recentlyUsedApps.count > 0) {
        [sortedCategories insertObject:@"最近使用" atIndex:0];
    }
    if (self.pinnedBundleIDs.count > 0) {
        [sortedCategories insertObject:@"置顶" atIndex:0];
    }
    [sortedCategories insertObject:@"全部" atIndex:0];
    
    CGFloat x = 0;
    for (NSString *cat in sortedCategories) {
        UIButton *btn = [UIButton buttonWithType:UIButtonTypeCustom];
        
        // 显示分类名和数量
        NSString *displayTitle = cat;
        if ([cat isEqualToString:@"最近使用"]) {
            displayTitle = [NSString stringWithFormat:@"%@ (%ld)", cat, (long)self.recentlyUsedApps.count];
        } else if ([cat isEqualToString:@"置顶"]) {
            displayTitle = [NSString stringWithFormat:@"%@ (%ld)", cat, (long)self.pinnedBundleIDs.count];
        } else if (![cat isEqualToString:@"全部"]) {
            displayTitle = [NSString stringWithFormat:@"%@ (%ld)", cat, (long)[counts[cat] integerValue]];
        }
        [btn setTitle:displayTitle forState:UIControlStateNormal];
        
        btn.titleLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightMedium];
        [btn setTitleColor:[UIColor labelColor] forState:UIControlStateNormal];
        
        // 如果是当前时段推荐的分类，增加一个微弱的发光边框暗示
        BOOL isSuggested = CV3GetTimePriorityForCategory(cat) > 0;
        
        CGSize size = [displayTitle sizeWithAttributes:@{NSFontAttributeName: btn.titleLabel.font}];
        CGFloat w = size.width + 24;
        btn.frame = CGRectMake(x, 5, w, 28);
        btn.layer.cornerRadius = 14;
        
        BOOL isSelected = [cat isEqualToString:self.selectedCategory];
        btn.backgroundColor = isSelected ? [[UIColor labelColor] colorWithAlphaComponent:0.2] : [[UIColor labelColor] colorWithAlphaComponent:0.06];
        btn.layer.borderWidth = isSuggested ? 1.0 : 0.5;
        btn.layer.borderColor = isSelected ? [[UIColor cyanColor] colorWithAlphaComponent:0.5].CGColor : 
                                (isSuggested ? [[UIColor labelColor] colorWithAlphaComponent:0.3].CGColor : [[UIColor labelColor] colorWithAlphaComponent:0.1].CGColor);
        
        [btn addTarget:self action:@selector(handleCategoryTap:) forControlEvents:UIControlEventTouchUpInside];
        [self.categoryBar addSubview:btn];
        x += w + 8;
    }
    self.categoryBar.contentSize = CGSizeMake(x, 40);
}

- (void)handlePanelDrag:(UIPanGestureRecognizer *)gesture {
    CGPoint location = [gesture locationInView:self.panelContainer];
    
    // 智能模糊抽离 (Smart Blur Easing) 计算
    
    
    if (gesture.state == UIGestureRecognizerStateBegan) {
        if (location.y > 45.0) { return; }
        self.hasBeenMoved = YES;
        [UIView animateWithDuration:0.3 delay:0 usingSpringWithDamping:0.5 initialSpringVelocity:1.0 options:0 animations:^{
            CGAffineTransform currentTransform = self.panelContainer.transform;
            self.panelContainer.transform = CGAffineTransformScale(currentTransform, 1.05, 1.05);
        } completion:nil];
    }

    if (gesture.state == UIGestureRecognizerStateChanged) {
        CGPoint translation = [gesture translationInView:self.panelContainer.superview];
        CGPoint newCenter = CGPointMake(self.panelContainer.center.x + translation.x, self.panelContainer.center.y + translation.y);
        
        CGRect bounds = self.bounds;
        CGRect panelBounds = self.panelContainer.bounds;
        CGFloat halfW = (panelBounds.size.width * 1.05) / 2.0;
        CGFloat halfH = (panelBounds.size.height * 1.05) / 2.0;
        
        newCenter.x = MAX(halfW - panelBounds.size.width * 0.4, MIN(bounds.size.width - halfW + panelBounds.size.width * 0.4, newCenter.x));
        newCenter.y = MAX(halfH - panelBounds.size.height * 0.4, MIN(bounds.size.height - halfH + panelBounds.size.height * 0.4, newCenter.y));
        
        self.panelContainer.center = newCenter;
        [gesture setTranslation:CGPointZero inView:self.panelContainer.superview];
    }
    if (gesture.state == UIGestureRecognizerStateEnded || gesture.state == UIGestureRecognizerStateCancelled) {
        // 恢复原始缩放，但不重置 transform（保留旋转）
        CGAffineTransform current = self.panelContainer.transform;
        
        // 磁吸靠边 (Magnetic Snapping) 逻辑
        CGRect screenBounds = self.bounds;
        UIEdgeInsets safe = self.safeAreaInsets;
        CGFloat threshold = 60.0; // 磁吸阈值
        
        CGPoint currentCenter = self.panelContainer.center;
        CGPoint targetCenter = currentCenter;
        
        CGRect panelBounds = self.panelContainer.bounds;
        CGSize sizeInRoot = CGRectApplyAffineTransform(panelBounds, self.panelContainer.transform).size;
        CGFloat rootHalfW = sizeInRoot.width / 2.0;
        CGFloat rootHalfH = sizeInRoot.height / 2.0;

        // 检查左/右磁吸
        if (currentCenter.x < (safe.left + rootHalfW + threshold)) {
            targetCenter.x = safe.left + rootHalfW;
        } else if (currentCenter.x > (screenBounds.size.width - safe.right - rootHalfW - threshold)) {
            targetCenter.x = screenBounds.size.width - safe.right - rootHalfW;
        }
        
        // 检查顶/底磁吸
        if (currentCenter.y < (safe.top + rootHalfH + threshold)) {
            targetCenter.y = safe.top + rootHalfH;
        } else if (currentCenter.y > (screenBounds.size.height - safe.bottom - rootHalfH - threshold)) {
            targetCenter.y = screenBounds.size.height - safe.bottom - rootHalfH;
        }

        // 提前应用回弹钳位约束，避免在 Block 中捕获为只读变量
        CGRect b = self.bounds;
        CGRect pb = self.panelContainer.bounds;
        CGFloat hW = pb.size.width * 0.4;
        CGFloat hH = pb.size.height * 0.4;
        targetCenter.x = MAX(hW, MIN(b.size.width - hW, targetCenter.x));
        targetCenter.y = MAX(hH, MIN(b.size.height - hH, targetCenter.y));

        // 建议1：触觉反馈深度耦合 (Haptic Coupling)
        // 如果检测到位置发生了磁吸偏移，触发一次刚性震动和碰撞脉冲 (C3)
        if (!CGPointEqualToPoint(currentCenter, targetCenter)) {
            [self triggerCollisionImpulse];
        }

        [UIView animateWithDuration:0.5 delay:0 usingSpringWithDamping:0.6 initialSpringVelocity:1.0 options:0 animations:^{
            self.panelContainer.transform = CGAffineTransformScale(current, 1/1.05, 1/1.05);
            self.appPanel.alpha = 1.0; // 恢复全透明度
            self.panelContainer.center = targetCenter;
        } completion:nil];
    }
}

- (void)handleDimmingTap:(UITapGestureRecognizer *)tap {
    [self animateSpotlight:NO fromPoint:self.panelContainer.center velocity:0.0];
}

- (void)handleResize:(UIPanGestureRecognizer *)gesture {
    // 增加 resize 锁
    self.isProcessing = YES; 

    // 建议：把手动态激活 (Handle Flare)
    // 根据手势状态切换把手视觉样式
    if (gesture.state == UIGestureRecognizerStateBegan) {
        [self.feedback impactOccurredWithIntensity:0.5];
        [CATransaction begin];
        [CATransaction setAnimationDuration:0.25];
        self.resizingHandleLayer.strokeColor = [[UIColor cyanColor] colorWithAlphaComponent:0.8].CGColor;
        self.resizingHandleLayer.lineWidth = 3.5;
        [CATransaction commit];
    } else if (gesture.state == UIGestureRecognizerStateEnded || gesture.state == UIGestureRecognizerStateCancelled) {
        [CATransaction begin];
        [CATransaction setAnimationDuration:0.4];
        self.resizingHandleLayer.strokeColor = [[UIColor labelColor] colorWithAlphaComponent:0.3].CGColor;
        self.resizingHandleLayer.lineWidth = 2.0;
        [CATransaction commit];
    }

    // 建议 4：Animation Transaction Safety (避免坐标跳变)
    CGRect currentBounds = self.panelContainer.layer.presentationLayer ? self.panelContainer.layer.presentationLayer.bounds : self.panelContainer.bounds;

    if (gesture) {
        // 1. 获取屏幕坐标系的平移，确保拖拽感在所有旋转下保持一致
        CGPoint translation = [gesture translationInView:self];
        
        // 2. 将屏幕位移映射回面板局部坐标系
        CGAffineTransform inv = CGAffineTransformInvert(self.baseRotationTransform);
        CGPoint localTranslation = CGPointApplyAffineTransform(translation, inv);

        CGFloat rawW = currentBounds.size.width + localTranslation.x;
        CGFloat rawH = currentBounds.size.height + localTranslation.y;
        
#pragma mark - 核心修复：基于投影的全方位边界钳位
        CGRect screenBounds = self.bounds;
        UIEdgeInsets safe = self.safeAreaInsets;
        CGFloat breath = kChevronLayoutConstants.safeAreaBreath;
        UIInterfaceOrientation orientation = self.targetOrientation != UIInterfaceOrientationUnknown ? self.targetOrientation : UIInterfaceOrientationPortrait;
        BOOL isLandscape = UIInterfaceOrientationIsLandscape(orientation);
        
        // 定义屏幕内的绝对安全矩形边界
        CGRect safeFrame = CGRectMake(safe.left + breath, 
                                      safe.top + breath, 
                                      screenBounds.size.width - safe.left - safe.right - 2*breath, 
                                      screenBounds.size.height - safe.top - safe.bottom - 2*breath);

        CGPoint center = self.panelContainer.layer.presentationLayer ? self.panelContainer.layer.presentationLayer.position : self.panelContainer.center;
        
        // 计算屏幕安全区域内允许的最大半宽高 (相对于中心点)
        CGFloat rootAllowedHalfW = MIN(center.x - safeFrame.origin.x, CGRectGetMaxX(safeFrame) - center.x);
        CGFloat rootAllowedHalfH = MIN(center.y - safeFrame.origin.y, CGRectGetMaxY(safeFrame) - center.y);
        
        // 将屏幕限制映射回面板本地坐标
        // 关键点：横屏下，屏幕宽度限制 (rootAllowedHalfW) 对应面板高度限制 (maxH)
        CGFloat maxW, maxH;
        if (isLandscape) {
            maxW = rootAllowedHalfH * 2.0;
            maxH = rootAllowedHalfW * 2.0;
        } else {
            maxW = rootAllowedHalfW * 2.0;
            maxH = rootAllowedHalfH * 2.0;
        }

#pragma mark - 智能自动推移 (Auto-Push)
        // 如果想要达到的尺寸超过了当前位置允许的最大尺寸，尝试平移中心点以换取空间
        CGFloat preferredW = MAX(50.0, rawW);
        CGFloat preferredH = MAX(50.0, rawH);
        
        // 计算投影后的首选尺寸
        CGRect prefLocalBounds = CGRectMake(0, 0, preferredW, preferredH);
        CGSize prefSizeInRoot = CGRectApplyAffineTransform(prefLocalBounds, self.baseRotationTransform).size;
        CGFloat prefHalfW = prefSizeInRoot.width / 2.0;
        CGFloat prefHalfH = prefSizeInRoot.height / 2.0;
        
        // 计算为了容纳这个尺寸，中心点理想的摆放位置（钳位在屏幕内）
        CGPoint idealCenter = center;
        idealCenter.x = MAX(safeFrame.origin.x + prefHalfW, MIN(CGRectGetMaxX(safeFrame) - prefHalfW, idealCenter.x));
        idealCenter.y = MAX(safeFrame.origin.y + prefHalfH, MIN(CGRectGetMaxY(safeFrame) - prefHalfH, idealCenter.y));
        
        // 应用中心点位移（推移）
        if (!CGPointEqualToPoint(center, idealCenter)) {
            self.panelContainer.center = idealCenter;
            center = idealCenter; // 更新当前参考中心
            
            // 重新计算推移后的可用空间
            rootAllowedHalfW = MIN(center.x - safeFrame.origin.x, CGRectGetMaxX(safeFrame) - center.x);
            rootAllowedHalfH = MIN(center.y - safeFrame.origin.y, CGRectGetMaxY(safeFrame) - center.y);
            if (isLandscape) {
                maxW = rootAllowedHalfH * 2.0;
                maxH = rootAllowedHalfW * 2.0;
            } else {
                maxW = rootAllowedHalfW * 2.0;
                maxH = rootAllowedHalfW * 2.0;
            }
        }

        // 尝试计算新尺寸（带最大值强制钳位）
        CGFloat targetW = MIN(maxW, preferredW);
        CGFloat targetH = MIN(maxH, preferredH);

#pragma mark - 最小值与果冻效果逻辑
        CGFloat minW = 175.0;
        CGFloat minH = isLandscape ? 270.0 : 380.0;
        
        CGFloat finalW = targetW, finalH = targetH;
        if (rawW < minW) {
            finalW = minW - ((minW - rawW) * 0.3);
        }
        if (rawH < minH) {
            finalH = minH - ((minH - rawH) * 0.3);
        }

        // 极限反馈判定（在 Begin/Ended 时已经处理了基础颜色，这里处理 Drag 过程中的 Limit 反馈）
        BOOL atLimit = (rawW < minW || rawH < minH || rawW > maxW || rawH > maxH);
        if (atLimit && gesture.state == UIGestureRecognizerStateChanged) {
            static BOOL lastAtLimit = NO;
            if (!lastAtLimit) [self.feedback impactOccurredWithIntensity:0.65];
            lastAtLimit = YES;
            
            [CATransaction begin];
            [CATransaction setDisableActions:YES];
            self.resizingHandleLayer.strokeColor = [[UIColor redColor] colorWithAlphaComponent:0.8].CGColor; // 触底/触顶变红提示
            [CATransaction commit];
        } else if (gesture.state == UIGestureRecognizerStateChanged) {
            [CATransaction begin];
            [CATransaction setDisableActions:YES];
            self.resizingHandleLayer.strokeColor = [[UIColor cyanColor] colorWithAlphaComponent:0.8].CGColor;
            [CATransaction commit];
        }

        self.panelContainer.bounds = CGRectMake(0, 0, finalW, finalH);
        [gesture setTranslation:CGPointZero inView:self];
    }

    self.appPanel.bounds = self.panelContainer.bounds;
    self.appPanel.center = CGPointMake(CGRectGetMidX(self.panelContainer.bounds), CGRectGetMidY(self.panelContainer.bounds));
    CGRect updatedBounds = self.panelContainer.bounds;
    
#pragma mark - UI 智能自适应逻辑
    // 如果高度太小（不足以舒适容纳分类栏），则隐藏分类栏并上移 CollectionView
    BOOL hideCategories = (updatedBounds.size.height < 320.0);
    self.categoryBar.alpha = hideCategories ? 0 : 1.0;
    CGFloat collectionViewY = hideCategories ? 96.0 : 140.0;

    // 动态调整搜索框和 CollectionView
    UIView *searchContainer = self.searchField.superview;
    searchContainer.frame = CGRectMake(15, 50, updatedBounds.size.width - 30, 36);
    self.searchField.frame = CGRectInset(searchContainer.bounds, 10, 0);
    self.searchBackground.frame = searchContainer.bounds;
    self.searchBackground.path = [UIBezierPath bezierPathWithRoundedRect:searchContainer.bounds cornerRadius:10].CGPath;

    self.categoryBar.frame = CGRectMake(15, 96, updatedBounds.size.width - 30, 40);
    self.collectionView.frame = CGRectMake(0, collectionViewY, updatedBounds.size.width, updatedBounds.size.height - collectionViewY);
    self.noResultsLabel.frame = CGRectMake(0, 150, updatedBounds.size.width, 40);

    [self updateResizingHandleFrame];

    // 关键修复：同步更新所有装饰层并禁用隐式动画，消除“追赶感”和“固定宽高”问题
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    
    self.contrastBackdrop.frame = self.appPanel.bounds;
    self.whiteFilter.frame = self.appPanel.bounds;
    self.innerGlowLayer.frame = self.appPanel.bounds;
    self.dispersionContainer.frame = self.appPanel.bounds;
    self.specularHighlight.frame = self.appPanel.bounds;
    self.cyanLayer.frame = CGRectInset(self.dispersionContainer.bounds, -0.3, -0.3);
    self.magentaLayer.frame = CGRectInset(self.dispersionContainer.bounds, 0.3, 0.3);
    
    [CATransaction commit];

    [self.collectionView.collectionViewLayout invalidateLayout];

    if (gesture && (gesture.state == UIGestureRecognizerStateEnded || gesture.state == UIGestureRecognizerStateCancelled)) {
#pragma mark - 弹簧回弹 (Snapback)
        UIInterfaceOrientation orientation = self.targetOrientation != UIInterfaceOrientationUnknown ? self.targetOrientation : UIInterfaceOrientationPortrait;
        BOOL isLandscape = UIInterfaceOrientationIsLandscape(orientation);

        CGFloat minW = 175.0;
        CGFloat minH = isLandscape ? 270.0 : 380.0;
        CGRect currentBounds = self.panelContainer.bounds;

        if (currentBounds.size.width < minW || currentBounds.size.height < minH) {
            CGRect targetBounds = CGRectMake(0, 0, MAX(minW, currentBounds.size.width), MAX(minH, currentBounds.size.height));
            [UIView animateWithDuration:0.5 delay:0 usingSpringWithDamping:0.6 initialSpringVelocity:0.8 options:UIViewAnimationOptionBeginFromCurrentState animations:^{
                self.panelContainer.bounds = targetBounds;
                [self handleResize:nil]; // 触发内部层同步
            } completion:^(BOOL f){ self.isProcessing = NO; }];
        } else {
            self.isProcessing = NO;
        }
    }
 else if (!gesture) {
        self.isProcessing = NO;
    }
}

- (void)btnTouchDown:(UIButton *)sender {
    [UIView animateWithDuration:0.2 delay:0 options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction animations:^{
        sender.transform = CGAffineTransformMakeScale(0.85, 0.85);
    } completion:nil];
}

- (void)btnTouchUp:(UIButton *)sender {
    [UIView animateWithDuration:0.4 delay:0 usingSpringWithDamping:0.5 initialSpringVelocity:0.5 options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction animations:^{
        sender.transform = CGAffineTransformIdentity;
    } completion:nil];
}

- (CGPoint)calculateTargetCenter {
    UIEdgeInsets safe = self.safeAreaInsets;
    CGRect bounds = self.bounds;
    CGFloat w = bounds.size.width;
    CGFloat h = bounds.size.height;
    
    // 计算安全区域内的有效绘图区
    CGRect safeBounds = CGRectMake(safe.left + kChevronLayoutConstants.safeAreaBreath, 
                                   safe.top + kChevronLayoutConstants.safeAreaBreath, 
                                   w - safe.left - safe.right - 2 * kChevronLayoutConstants.safeAreaBreath, 
                                   h - safe.top - safe.bottom - 2 * kChevronLayoutConstants.safeAreaBreath);
                                   
    return CGPointMake(CGRectGetMidX(safeBounds), CGRectGetMidY(safeBounds));
}

- (void)handleTrafficLight:(UIButton *)sender {
    // 立即反馈
    [self.feedback impactOccurred];
    [self updateTrafficLightsFocus:NO];

    if (sender.tag == 0 || sender.tag == 1) {
        // 直接触发，不再通过 dispatch_after 延迟，以匹配点击背景的极速响应
        [self animateSpotlight:NO fromPoint:self.panelContainer.center velocity:0.0];
    } else if (sender.tag == 2) {
        // 最大化/重置逻辑也同步触发
        [UIView animateWithDuration:0.4 delay:0 usingSpringWithDamping:0.8 initialSpringVelocity:0.8 options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction animations:^{
            CGSize maxSize = [self calculateMaxPanelSize];
            CGFloat targetW = MIN(kChevronLayoutConstants.panelW, maxSize.width);
            CGFloat targetH = MIN(kChevronLayoutConstants.panelH, maxSize.height);
            targetH = MAX(targetH, kChevronLayoutConstants.minHeight);
            
            self.panelContainer.bounds = CGRectMake(0, 0, targetW, targetH);
            self.panelContainer.center = [self calculateTargetCenter];
            [self handleResize:nil];
        } completion:nil];
    }
}

- (void)updateResizingHandleFrame {
    // 确保把手始终在面板的右下角
    CGRect bounds = self.panelContainer.bounds;
    self.resizingHandle.bounds = CGRectMake(0, 0, 40, 40);
    self.resizingHandle.center = CGPointMake(bounds.size.width - 20, bounds.size.height - 20);
}

- (void)layoutSubviews {
    [super layoutSubviews];

    UIEdgeInsets safe = self.safeAreaInsets;
    CGRect bounds = self.bounds;
    CGFloat w = bounds.size.width;
    CGFloat h = bounds.size.height;

    // 计算安全区域内的有效绘图区
    CGPoint targetCenter = [self calculateTargetCenter];
    self.cachedTargetCenter = targetCenter; // 建议3：实时预热缓存

    // 1. 设置触发区域
    self.edgeTriggerView.backgroundColor = [UIColor clearColor];
    UIInterfaceOrientation orientation = self.targetOrientation != UIInterfaceOrientationUnknown ? self.targetOrientation : UIInterfaceOrientationPortrait;

    switch (orientation) {
        case UIInterfaceOrientationLandscapeLeft:
            self.systemEdgePan.edges = UIRectEdgeTop;
            self.edgeTriggerView.frame = CGRectMake(0, 0, w, kChevronLayoutConstants.triggerHotzoneWidth);
            break;
        case UIInterfaceOrientationLandscapeRight:
            self.systemEdgePan.edges = UIRectEdgeBottom;
            self.edgeTriggerView.frame = CGRectMake(0, h - kChevronLayoutConstants.triggerHotzoneWidth, w, kChevronLayoutConstants.triggerHotzoneWidth);
            break;
        case UIInterfaceOrientationPortraitUpsideDown:
            self.systemEdgePan.edges = UIRectEdgeLeft;
            self.edgeTriggerView.frame = CGRectMake(0, safe.top, kChevronLayoutConstants.triggerHotzoneWidth, h - safe.top - kChevronLayoutConstants.triggerBottomOffset);
            break;
        case UIInterfaceOrientationPortrait:
        default:
            self.systemEdgePan.edges = UIRectEdgeRight;
            self.edgeTriggerView.frame = CGRectMake(w - kChevronLayoutConstants.triggerHotzoneWidth, safe.top, kChevronLayoutConstants.triggerHotzoneWidth, h - safe.top - kChevronLayoutConstants.triggerBottomOffset);
            break;
    }

    [self.rootViewController.view bringSubviewToFront:self.edgeTriggerView];

    // 2. 面板容器
    self.dimmingView.frame = bounds;
    self.panelContainer.backgroundColor = [UIColor clearColor];

    // 动态计算面板尺寸 (使用常量并确保不超出安全区域)
    CGSize maxSize = [self calculateMaxPanelSize];

    CGFloat targetW = MIN(kChevronLayoutConstants.panelW, maxSize.width);
    CGFloat targetH = MIN(kChevronLayoutConstants.panelH, maxSize.height);
    targetH = MAX(targetH, kChevronLayoutConstants.minHeight);

    CGRect panelBounds = CGRectMake(0, 0, targetW, targetH);    
    // 计算目标旋转
    CGAffineTransform targetRotation = CGAffineTransformIdentity;
    switch (orientation) {
        case UIInterfaceOrientationLandscapeLeft: targetRotation = CGAffineTransformMakeRotation(-M_PI_2); break;
        case UIInterfaceOrientationLandscapeRight: targetRotation = CGAffineTransformMakeRotation(M_PI_2); break;
        case UIInterfaceOrientationPortraitUpsideDown: targetRotation = CGAffineTransformMakeRotation(M_PI); break;
        default: targetRotation = CGAffineTransformIdentity; break;
    }

    // 更新基础变换属性
    self.baseRotationTransform = targetRotation;
    
    // 只有在未拖动过且非正在动画时，或者旋转方向改变时，才强制同步 bounds
    BOOL orientationChanged = !CGAffineTransformEqualToTransform(self.panelContainer.transform, targetRotation);
    BOOL shouldForceLayout = (!self.hasBeenMoved && !self.isAnimating) || orientationChanged;

    if (shouldForceLayout && (!CGRectEqualToRect(self.panelContainer.bounds, panelBounds) || orientationChanged)) {
        [UIView animateWithDuration:0.35 delay:0 usingSpringWithDamping:0.8 initialSpringVelocity:0.5 options:UIViewAnimationOptionCurveEaseInOut | UIViewAnimationOptionBeginFromCurrentState animations:^{
            // 在动画中更新基础旋转，防止重写
            self.panelContainer.transform = targetRotation;
            self.panelContainer.bounds = panelBounds;
            
            // 重置视差形变，防止修改 frame 时发生坐标跳变 (Geometry Jump)
            self.appPanel.transform = CGAffineTransformIdentity;
            self.trafficCapsule.transform = CGAffineTransformIdentity;
            self.resizingHandle.transform = CGAffineTransformIdentity;

            // 调整子组件大小以匹配容器
            self.appPanel.frame = self.panelContainer.bounds;
            
            UIView *searchContainer = self.searchField.superview;
            searchContainer.frame = CGRectMake(15, 50, targetW - 30, 36);
            self.searchField.frame = CGRectInset(searchContainer.bounds, 10, 0);
            self.searchBackground.frame = searchContainer.bounds;
            self.searchBackground.path = [UIBezierPath bezierPathWithRoundedRect:searchContainer.bounds cornerRadius:10].CGPath;

            self.categoryBar.frame = CGRectMake(15, 96, targetW - 30, 40);
            self.collectionView.frame = CGRectMake(0, 140, targetW, targetH - 140);
            self.noResultsLabel.frame = CGRectMake(0, 150, targetW, 40);
            
            self.trafficCapsule.frame = CGRectMake(16, 14, kChevronLayoutConstants.trafficCapsuleW, kChevronLayoutConstants.trafficCapsuleH);
            [self updateResizingHandleFrame];
            
            [CATransaction begin];
            [CATransaction setDisableActions:YES];
            self.contrastBackdrop.frame = self.appPanel.bounds;
            self.whiteFilter.frame = self.appPanel.bounds;
            self.innerGlowLayer.frame = self.appPanel.bounds;
            self.dispersionContainer.frame = self.appPanel.bounds;
            self.specularHighlight.frame = self.appPanel.bounds;
            self.cyanLayer.frame = CGRectInset(self.appPanel.bounds, -0.3, -0.3);
            self.magentaLayer.frame = CGRectInset(self.appPanel.bounds, 0.3, 0.3);
            [CATransaction commit];

            [self.collectionView.collectionViewLayout invalidateLayout];
            
            if (!self.hasBeenMoved) {
                if (CGPointDistance(self.panelContainer.center, targetCenter) > 0.5) {
                    self.panelContainer.center = targetCenter;
                }
            }
        } completion:nil];
    } else {
        // 如果已经拖动过，仅在旋转时更新 transform
        if (orientationChanged && !self.isAnimating) {
             [UIView animateWithDuration:0.35 animations:^{
                self.panelContainer.transform = targetRotation;
             }];
        }
        
        if (!self.isAnimating && !self.hasBeenMoved) {
            // 建议1：锚点平滑补偿 (Anchor Smoothing)
            if (CGPointDistance(self.panelContainer.center, targetCenter) > 0.5) {
                [UIView animateWithDuration:0.15 delay:0 options:UIViewAnimationOptionCurveEaseOut | UIViewAnimationOptionBeginFromCurrentState animations:^{
                    self.panelContainer.center = targetCenter;
                } completion:nil];
            }
        } else if (self.isPanelShowing && !self.isAnimating) {
            // 保持在屏幕内的钳位逻辑
            CGPoint currentCenter = self.panelContainer.center;
            CGRect currentBounds = self.panelContainer.bounds;
            
            // 考虑旋转后的实际尺寸
            CGSize sizeInRoot = CGRectApplyAffineTransform(currentBounds, self.panelContainer.transform).size;
            CGFloat rootHalfW = sizeInRoot.width / 2.0;
            CGFloat rootHalfH = sizeInRoot.height / 2.0;

            CGFloat clampedX = MAX(rootHalfW, MIN(w - rootHalfW, currentCenter.x));
            CGFloat clampedY = MAX(rootHalfH, MIN(h - rootHalfH, currentCenter.y));
            
            if (fabs(currentCenter.x - clampedX) > 0.5 || fabs(currentCenter.y - clampedY) > 0.5) {
                self.panelContainer.center = CGPointMake(clampedX, clampedY);
            }
        }
    }

    // 3. 特效层
    self.bezierContainer.frame = bounds; // 覆盖全屏以实现贝塞尔绘制
    self.bezierBlur.frame = self.bezierContainer.bounds;
    self.bezierContainer.backgroundColor = [UIColor clearColor];
    
    // 4. 面板主体
    self.appPanel.backgroundColor = [UIColor clearColor];

    // 5. 辅助视图
    self.trafficCapsule.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.08];
    self.resizingHandle.backgroundColor = [UIColor clearColor];
    
    for (UIView *subview in self.appPanel.subviews) {
        if ([NSStringFromClass([subview class]) containsString:@"Backdrop"]) {
            subview.transform = CGAffineTransformMakeScale(1.15, 1.15);
        }
    }
}



- (void)handleEdgeInteraction:(UIPanGestureRecognizer *)gesture {
    // 使用 locationInView:nil 获取绝对屏幕坐标，规避旋转后的坐标系偏移风险
    CGPoint location = [gesture locationInView:nil];
    CGPoint translation = [gesture translationInView:nil];
    CGPoint velocity = [gesture velocityInView:nil];

#pragma mark - 动态方向感知拉伸计算
    UIInterfaceOrientation orientation = self.targetOrientation != UIInterfaceOrientationUnknown ? self.targetOrientation : UIInterfaceOrientationPortrait;
    CGFloat stretch = 0;
    CGFloat vel = 0;

    switch (orientation) {
        case UIInterfaceOrientationLandscapeLeft:
            stretch = translation.y; // 下划
            vel = velocity.y;
            break;
        case UIInterfaceOrientationLandscapeRight:
            stretch = -translation.y; // 上划
            vel = -velocity.y;
            break;
        case UIInterfaceOrientationPortraitUpsideDown:
            stretch = translation.x; // 右划 (左边缘)
            vel = velocity.x;
            break;
        case UIInterfaceOrientationPortrait:
        default:
            stretch = -translation.x; // 左划 (右边缘)
            vel = -velocity.x;
            break;
    }

    if (gesture.state == UIGestureRecognizerStateBegan) {
        // 1. 手势预警效果 (Trigger Preview Flare)
        [CATransaction begin];
        [CATransaction setAnimationDuration:0.2];
        self.triggerPreviewLayer.frame = CGRectMake(location.x - 75, location.y - 75, 150, 150);
        self.triggerPreviewLayer.opacity = 1.0;
        [CATransaction commit];

        // 建议3：布局预热 (Layout Pre-warming)
        self.cachedTargetCenter = [self calculateTargetCenter];

        if (!self.isPanelShowing) {
            [self.feedback impactOccurred];
            [self.selectionFeedback prepare];
            self.lastHapticX = 0;
            self.bezierContainer.alpha = 1.0;
            
            [CATransaction begin];
            [CATransaction setDisableActions:YES];
            self.bezierLayer.path = [self pathForStretch:0 atPoint:location velocity:CGPointZero orientation:orientation].CGPath;
            [CATransaction commit];
            
            self.bezierLayer.shadowOpacity = 0.0;
        }
    } else if (gesture.state == UIGestureRecognizerStateChanged) {
        // 动态同步预警层位置
        [CATransaction begin];
        [CATransaction setDisableActions:YES];
        self.triggerPreviewLayer.position = location;
        [CATransaction commit];

        if (self.bezierContainer.alpha > 0) {
            [CATransaction begin];
            [CATransaction setDisableActions:YES];
            self.bezierLayer.path = [self pathForStretch:MAX(0, stretch) atPoint:location velocity:velocity orientation:orientation].CGPath;
            [CATransaction commit];

            // 仅进行手势拉伸图形绘制，延迟 dimmingView 等呈现准备工作至阈值触发后
            // 建议 3：Tactile Granularity (触觉颗粒感)
            CGFloat hapticInterval = MAX(8.0, 20.0 - (stretch / 45.0) * 12.0);
            if (fabs(stretch - self.lastHapticX) > hapticInterval) {
                UIImpactFeedbackGenerator *rigid = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleRigid];
                [rigid impactOccurredWithIntensity:0.3 + (stretch / 45.0) * 0.4];
                
                AudioServicesPlaySystemSound(1104); 
                self.lastHapticX = stretch;
            }

            if (stretch > 45) { 
                [self animateSpotlight:YES fromPoint:location velocity:vel]; 
                gesture.enabled = NO; gesture.enabled = YES; 
            }
        }
    } else if (gesture.state == UIGestureRecognizerStateEnded || gesture.state == UIGestureRecognizerStateCancelled) {
        // 移除预警效果
        [CATransaction begin];
        [CATransaction setAnimationDuration:0.3];
        self.triggerPreviewLayer.opacity = 0;
        [CATransaction commit];

        if (self.bezierContainer.alpha > 0 && !self.isPanelShowing && vel > 300 && gesture.state != UIGestureRecognizerStateCancelled) {
            [self animateSpotlight:YES fromPoint:location velocity:vel];
        } else if (!self.isPanelShowing) {
            // 修复：确保中断时重置所有状态
            [UIView animateWithDuration:0.4 animations:^{
                self.panelContainer.hidden = YES;
                self.panelContainer.alpha = 0;
                self.dimmingView.alpha = 0;
                self.isAnimating = NO;
            }];
            
            // Jelly Physics for Exit
            CASpringAnimation *spring = [CASpringAnimation animationWithKeyPath:@"path"];
            spring.damping = 12;
            spring.stiffness = 300;
            spring.mass = 1.0;
            spring.duration = spring.settlingDuration;
            spring.fromValue = (id)self.bezierLayer.path;
            spring.toValue = (id)[self pathForStretch:0 atPoint:location velocity:CGPointZero orientation:orientation].CGPath;
            [self.bezierLayer addAnimation:spring forKey:@"bounceBack"];
            
            [CATransaction begin];
            [CATransaction setDisableActions:YES];
            self.bezierLayer.path = [self pathForStretch:0 atPoint:location velocity:CGPointZero orientation:orientation].CGPath;
            [CATransaction commit];
        }
        [UIView animateWithDuration:0.5 delay:0.15 options:UIViewAnimationOptionCurveEaseInOut animations:^{ 
            self.bezierContainer.alpha = 0; 
            if (!self.isPanelShowing) self.dimmingView.alpha = 0;
        } completion:nil];
    }
}


- (UIBezierPath *)pathForStretch:(CGFloat)stretch atPoint:(CGPoint)point velocity:(CGPoint)velocity orientation:(UIInterfaceOrientation)orientation {
    CGFloat s = MIN(stretch * 0.7, 95); 
    CGFloat baseW = 130 + stretch * 0.2;
    CGFloat cp1Offset = 65 + stretch * 0.5;
    CGFloat cp2Offset = 45 + stretch * 0.2;
    
    UIBezierPath *path = [UIBezierPath bezierPath];

    CGRect b = self.bounds;

    if (orientation == UIInterfaceOrientationLandscapeLeft) {
        // 顶部拉伸 (LandscapeLeft, Home在右)
        CGFloat leftX = point.x - baseW;
        CGFloat rightX = point.x + baseW;
        CGFloat peakY = s;
        [path moveToPoint:CGPointMake(0, 0)]; // 从左上角开始
        [path addLineToPoint:CGPointMake(leftX, 0)]; // 直线到左边起点
        [path addCurveToPoint:CGPointMake(point.x, peakY) controlPoint1:CGPointMake(point.x - cp1Offset, 0) controlPoint2:CGPointMake(point.x - cp2Offset, peakY)];
        [path addCurveToPoint:CGPointMake(rightX, 0) controlPoint1:CGPointMake(point.x + cp2Offset, peakY) controlPoint2:CGPointMake(point.x + cp1Offset, 0)];
        [path addLineToPoint:CGPointMake(b.size.width, 0)]; // 直线到右上角
        [path addLineToPoint:CGPointMake(0, 0)]; // 闭合
    } else if (orientation == UIInterfaceOrientationLandscapeRight) {
        // 底部拉伸 (LandscapeRight, Home在左)
        CGFloat leftX = point.x - baseW;
        CGFloat rightX = point.x + baseW;
        CGFloat peakY = b.size.height - s;
        [path moveToPoint:CGPointMake(0, b.size.height)]; // 左下角
        [path addLineToPoint:CGPointMake(leftX, b.size.height)];
        [path addCurveToPoint:CGPointMake(point.x, peakY) controlPoint1:CGPointMake(point.x - cp1Offset, b.size.height) controlPoint2:CGPointMake(point.x - cp2Offset, peakY)];
        [path addCurveToPoint:CGPointMake(rightX, b.size.height) controlPoint1:CGPointMake(point.x + cp2Offset, peakY) controlPoint2:CGPointMake(point.x + cp1Offset, b.size.height)];
        [path addLineToPoint:CGPointMake(b.size.width, b.size.height)]; // 右下角
        [path addLineToPoint:CGPointMake(0, b.size.height)]; // 闭合
    } else if (orientation == UIInterfaceOrientationPortraitUpsideDown) {
        // 左边缘拉伸
        CGFloat topY = point.y - baseW;
        CGFloat bottomY = point.y + baseW;
        CGFloat peakX = s;
        [path moveToPoint:CGPointMake(0, 0)]; // 左上角
        [path addLineToPoint:CGPointMake(0, topY)];
        [path addCurveToPoint:CGPointMake(peakX, point.y) controlPoint1:CGPointMake(0, point.y - cp1Offset) controlPoint2:CGPointMake(peakX, point.y - cp2Offset)];
        [path addCurveToPoint:CGPointMake(0, bottomY) controlPoint1:CGPointMake(peakX, point.y + cp2Offset) controlPoint2:CGPointMake(0, point.y + cp1Offset)];
        [path addLineToPoint:CGPointMake(0, b.size.height)]; // 左下角
        [path addLineToPoint:CGPointMake(0, 0)]; // 闭合
    } else {
        // 右边缘拉伸 (Portrait)
        CGFloat topY = point.y - baseW;
        CGFloat bottomY = point.y + baseW;
        CGFloat peakX = b.size.width - s;
        [path moveToPoint:CGPointMake(b.size.width, 0)]; // 右上角
        [path addLineToPoint:CGPointMake(b.size.width, topY)];
        [path addCurveToPoint:CGPointMake(peakX, point.y) controlPoint1:CGPointMake(b.size.width, point.y - cp1Offset) controlPoint2:CGPointMake(peakX, point.y - cp2Offset)];
        [path addCurveToPoint:CGPointMake(b.size.width, bottomY) controlPoint1:CGPointMake(peakX, point.y + cp2Offset) controlPoint2:CGPointMake(b.size.width, point.y + cp1Offset)];
        [path addLineToPoint:CGPointMake(b.size.width, b.size.height)]; // 右下角
        [path addLineToPoint:CGPointMake(b.size.width, 0)]; // 闭合
    }

    [path closePath];
    return path;
}

- (void)updateTrafficLightsFocus:(BOOL)active {
    NSArray *tc = @[[UIColor colorWithRed:1.00 green:0.37 blue:0.33 alpha:1.0], [UIColor colorWithRed:1.00 green:0.75 blue:0.18 alpha:1.0], [UIColor colorWithRed:0.15 green:0.79 blue:0.25 alpha:1.0]];
    UIColor *gray = [[UIColor labelColor] colorWithAlphaComponent:0.2];
    
    // 移除嵌套动画，改为直接设置颜色或使用极简动画，防止阻塞主线程交互
    for (int i = 0; i < self.trafficDots.count; i++) {
        self.trafficDots[i].backgroundColor = active ? tc[i] : gray;
    }
}

- (void)animateSpotlight:(BOOL)visible fromPoint:(CGPoint)point velocity:(CGFloat)velocity {
    if (self.isAnimating) return;
    self.isPanelShowing = visible; self.isAnimating = YES;
    if (visible) {
        self.dimmingView.alpha = 1.0; // 阈值触发时同步显示遮罩
        self.lastTriggerPoint = point;
        self.hasCapturedBaseline = NO; // 重置基准姿态捕获标志
        [self loadAppsAsync];
        [self updateTrafficLightsFocus:YES];
        self.dimmingView.userInteractionEnabled = YES; // 显示时开启拦截
        self.panelContainer.hidden = NO; self.panelContainer.center = point;
        
        // 恢复所有高开销特效图层的显示
        self.dispersionContainer.hidden = NO;
        self.cyanLayer.hidden = NO;
        self.magentaLayer.hidden = NO;
        self.innerGlowLayer.hidden = NO;
        self.contrastBackdrop.hidden = NO;
        self.whiteFilter.hidden = NO;
        self.specularHighlight.hidden = NO;

        // 预先应用正确的旋转变换和尺寸
        CGAffineTransform initialRotation = CGAffineTransformIdentity;
        UIInterfaceOrientation orientation = self.targetOrientation != UIInterfaceOrientationUnknown ? self.targetOrientation : UIInterfaceOrientationPortrait;
        switch (orientation) {
            case UIInterfaceOrientationLandscapeLeft: initialRotation = CGAffineTransformMakeRotation(-M_PI_2); break;
            case UIInterfaceOrientationLandscapeRight: initialRotation = CGAffineTransformMakeRotation(M_PI_2); break;
            case UIInterfaceOrientationPortraitUpsideDown: initialRotation = CGAffineTransformMakeRotation(M_PI); break;
            default: initialRotation = CGAffineTransformIdentity; break;
        }

        // 根据速度计算非对称形变 (Squash & Stretch)
        CGAffineTransform squashTransform = CGAffineTransformIdentity;
        if (fabs(velocity) > 0) {
            CGFloat stretchAmount = MIN(fabs(velocity) / 2500.0, 0.35); // 最大 35% 拉伸
            // X轴拉伸，Y轴挤压，方向由 velocity 符号决定（如果是向内拉出则 X 拉伸）
            squashTransform = CGAffineTransformMakeScale(1.0 + stretchAmount, 1.0 - stretchAmount * 0.5);
        }

        CGAffineTransform startTransform = CGAffineTransformConcat(squashTransform, initialRotation);

        // 计算当前环境下合法的尺寸 (同步 layoutSubviews 逻辑)
        CGSize maxSize = [self calculateMaxPanelSize];        
        CGFloat targetW = MIN(kChevronLayoutConstants.panelW, maxSize.width);
        CGFloat targetH = MIN(kChevronLayoutConstants.panelH, maxSize.height);
        targetH = MAX(targetH, kChevronLayoutConstants.minHeight);
        
        // 重置视差形变，防止修改 frame 时发生坐标跳变 (Geometry Jump)
        self.appPanel.transform = CGAffineTransformIdentity;
        self.trafficCapsule.transform = CGAffineTransformIdentity;
        self.resizingHandle.transform = CGAffineTransformIdentity;

        // 设置初始 bounds 和子组件大小，防止在 layoutSubviews 锁定期间出现错位
        self.panelContainer.bounds = CGRectMake(0, 0, targetW, targetH);
        self.appPanel.frame = self.panelContainer.bounds;
        
        UIView *searchContainer = self.searchField.superview;
        searchContainer.frame = CGRectMake(15, 50, targetW - 30, 36);
        self.searchField.frame = CGRectInset(searchContainer.bounds, 10, 0);
        self.searchBackground.frame = searchContainer.bounds;
        self.searchBackground.path = [UIBezierPath bezierPathWithRoundedRect:searchContainer.bounds cornerRadius:10].CGPath;

        self.categoryBar.frame = CGRectMake(15, 96, targetW - 30, 40);
        self.collectionView.frame = CGRectMake(0, 140, targetW, targetH - 140);
        self.noResultsLabel.frame = CGRectMake(0, 150, targetW, 40);
        
        self.trafficCapsule.frame = CGRectMake(16, 14, kChevronLayoutConstants.trafficCapsuleW, kChevronLayoutConstants.trafficCapsuleH);
        [self updateResizingHandleFrame];
        self.contrastBackdrop.frame = self.appPanel.bounds;
        self.innerGlowLayer.frame = self.appPanel.bounds;
        self.specularHighlight.frame = self.appPanel.bounds;
        self.cyanLayer.frame = CGRectInset(self.appPanel.bounds, -0.3, -0.3);
        self.magentaLayer.frame = CGRectInset(self.appPanel.bounds, 0.3, 0.3);
        [self.collectionView.collectionViewLayout invalidateLayout];

        self.panelContainer.transform = CGAffineTransformScale(startTransform, 0.4, 0.4);
        self.panelContainer.alpha = 0;

        [CATransaction begin];
        [CATransaction setDisableActions:YES];
        // 建议 4：初始状态强制背景层放大，模拟凝聚感
        for (UIView *subview in self.appPanel.subviews) {
            if ([NSStringFromClass([subview class]) containsString:@"Backdrop"]) {
                subview.transform = CGAffineTransformMakeScale(1.5, 1.5);
            }
        }
        [CATransaction commit];

        // 建议3：使用预热缓存的中心点 (Layout Pre-warming)
        CGPoint targetCenter = (self.cachedTargetCenter.x > 0) ? self.cachedTargetCenter : [self calculateTargetCenter];

        [UIView animateWithDuration:0.75 delay:0 usingSpringWithDamping:0.65 initialSpringVelocity:1.2 options:0 animations:^{
            self.dimmingView.alpha = 1.0;
            self.panelContainer.center = targetCenter;
            self.panelContainer.transform = initialRotation;
            self.panelContainer.alpha = 1;
            
            [CATransaction begin];
            [CATransaction setDisableActions:YES];
            // 模糊层回缩，创造液态归位视觉
            for (UIView *subview in self.appPanel.subviews) {
                if ([NSStringFromClass([subview class]) containsString:@"Backdrop"]) {
                    subview.transform = CGAffineTransformMakeScale(1.15, 1.15);
                }
            }
            [CATransaction commit];
            
            // 实时汲取当前活跃 App 的色调注入遮罩
            CV3UpdateAdaptiveTint([self currentActiveBundleID]);
        } completion:^(BOOL f){ 
            self.isAnimating = NO; 
            [self startLiquidMotion]; 
        }];
    } else {
        // 关键修复：不要同步收起键盘，因为 resignFirstResponder 是重度同步操作，会阻塞动画开始
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.searchField resignFirstResponder];
        });

        [self updateTrafficLightsFocus:NO];
        [self stopLiquidMotion];
        self.dimmingView.userInteractionEnabled = NO; // 隐藏时关闭拦截
        
        // 获取当前的旋转状态
        CGAffineTransform currentRotation = self.panelContainer.transform;
        
        [UIView animateWithDuration:0.5 delay:0 usingSpringWithDamping:0.85 initialSpringVelocity:0.5 options:0 animations:^{ 
            self.dimmingView.alpha = 0;
            self.panelContainer.alpha = 0; 
            self.panelContainer.center = self.lastTriggerPoint; // 回退到存储的触发点
            self.panelContainer.transform = CGAffineTransformScale(currentRotation, 0.5, 0.5);
            
            [CATransaction begin];
            [CATransaction setDisableActions:YES];
            // 消失时再次放大模糊层，模拟消散
            for (UIView *subview in self.appPanel.subviews) {
                if ([NSStringFromClass([subview class]) containsString:@"Backdrop"]) {
                    subview.transform = CGAffineTransformMakeScale(1.5, 1.5);
                }
            }
            [CATransaction commit];
        } completion:^(BOOL f){ 
            self.isAnimating = NO; 
            self.panelContainer.hidden = YES; 
            // 显式挂起所有重度开销图层，确保 GPU 零消耗
            self.dispersionContainer.hidden = YES;
            self.cyanLayer.hidden = YES;
            self.magentaLayer.hidden = YES;
            self.innerGlowLayer.hidden = YES;
            self.contrastBackdrop.hidden = YES;
            self.whiteFilter.hidden = YES;
            self.specularHighlight.hidden = YES;
        }];
    }
}

- (void)animateIconsStaggered {
    NSArray *items = [self.collectionView visibleCells];
    NSArray *sorted = [items sortedArrayUsingComparator:^NSComparisonResult(UICollectionViewCell *a, UICollectionViewCell *b) {
        return [[self.collectionView indexPathForCell:a] compare:[self.collectionView indexPathForCell:b]];
    }];
    for (int i = 0; i < sorted.count; i++) {
        UIView *v = sorted[i]; v.transform = CGAffineTransformMakeScale(0.2, 0.2); v.alpha = 0;
        [UIView animateWithDuration:0.6 delay:i*0.015 usingSpringWithDamping:0.45 initialSpringVelocity:1.5 options:0 animations:^{ v.transform = CGAffineTransformIdentity; v.alpha = 1; } completion:nil];
    }
}

- (void)startLiquidMotion {
    if (!self.motionManager.isDeviceMotionAvailable) return;

    // [Geek Advice] Align with 120Hz display refresh rate using CADisplayLink
    [self.motionManager startDeviceMotionUpdates];

    if (self.liquidDisplayLink) {
        [self.liquidDisplayLink invalidate];
    }

    self.liquidDisplayLink = [CADisplayLink displayLinkWithTarget:self selector:@selector(updateLiquidMotion:)];
    [self.liquidDisplayLink addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
}

- (void)updateLiquidMotion:(CADisplayLink *)sender {
    CMDeviceMotion *m = self.motionManager.deviceMotion;
    if (!m) return;

    if (!self.hasCapturedBaseline) {
        self.baseRoll = m.attitude.roll;
        self.basePitch = m.attitude.pitch;
        self.hasCapturedBaseline = YES;
        // 面板显示时激活光效
        [CATransaction begin]; [CATransaction setDisableActions:YES];
        self.redGlow.hidden = NO; self.yellowGlow.hidden = NO; self.greenGlow.hidden = NO;
        [CATransaction commit];
    }

    CGFloat deltaRoll = m.attitude.roll - self.baseRoll;
    CGFloat deltaPitch = m.attitude.pitch - self.basePitch;

    [CATransaction begin]; [CATransaction setDisableActions:YES];

    // 建议 1：Fiber-Optic Light Leak (光纤导光实时姿态)
    // 光束顺着倾斜方向在面板内部流动，具有更高的位移敏感度
    CGFloat glowShift = 45.0;
    self.redGlow.position = CGPointMake(40 + deltaRoll * glowShift, 25 + deltaPitch * glowShift);
    self.yellowGlow.position = CGPointMake(65 + deltaRoll * glowShift, 25 + deltaPitch * glowShift);
    self.greenGlow.position = CGPointMake(90 + deltaRoll * glowShift, 25 + deltaPitch * glowShift);

    self.specularHighlight.startPoint = CGPointMake(0.5 - deltaRoll*1.5, 0.5 - deltaPitch*1.5);
    self.specularHighlight.endPoint = CGPointMake(1.5 - deltaRoll*1.5, 1.5 - deltaPitch*1.5);

    CGFloat dx = deltaRoll * 1.2;
    CGFloat dy = deltaPitch * 1.2;
    self.cyanLayer.transform = CATransform3DMakeTranslation(-dx, -dy, 0);
    self.magentaLayer.transform = CATransform3DMakeTranslation(dx, dy, 0);

    // 建议2：视差解耦 (Parallax Decoupling) 2.0 - 多平面深度体系
    // 核心原理：层级越高（越靠近用户），位移系数越大
    CGFloat panelDX = deltaRoll * kChevronPhysicsConstants.parallaxPanelFactor;
    CGFloat panelDY = deltaPitch * kChevronPhysicsConstants.parallaxPanelFactor;
    self.appPanel.transform = CGAffineTransformMakeTranslation(panelDX, panelDY);

    // 建议 3：Glow & Content Depth (发光与内容深度差)
    // 内发光层位移略大于面板，创造玻璃边缘的折射感
    CGFloat glowDX = panelDX * 1.15;
    CGFloat glowDY = panelDY * 1.15;
    self.innerGlowLayer.affineTransform = CGAffineTransformMakeTranslation(glowDX, glowDY);

    // 建议 2：Gravity-Aware Icons (重力图标视差)
    // 遍历可见 cell，应用反向视差，系数设为最高以凸显浮空感
    NSArray *visibleCells = [self.collectionView visibleCells];
    for (UICollectionViewCell *cell in visibleCells) {
        if ([cell isKindOfClass:[CV3AppCell class]]) {
            // 图标位移系数 3.5x，创造明显的层次差
            ((CV3AppCell *)cell).iconOffset = CGPointMake(-deltaRoll * 3.5, -deltaPitch * 3.5);
        }
    }

    // 装饰件深度视差 (Layered Decoration Parallax) + 惯性衰减 (Inertial Damping)
    CGFloat targetDecoDX = deltaRoll * kChevronPhysicsConstants.parallaxDecoFactor;
    CGFloat targetDecoDY = deltaPitch * kChevronPhysicsConstants.parallaxDecoFactor;

    // 惯性平滑逻辑：使用插值 (Lerp) 实现物理质量感
    CGFloat oldDecoDX = self.currentDecoDX;
    CGFloat oldDecoDY = self.currentDecoDY;
    self.currentDecoDX += (targetDecoDX - self.currentDecoDX) * kChevronPhysicsConstants.lerpFactor;
    self.currentDecoDY += (targetDecoDY - self.currentDecoDY) * kChevronPhysicsConstants.lerpFactor;

    // 建议：触觉阻尼 (Haptic Damping Feedback)
    CGFloat frameDisplacement = hypot(self.currentDecoDX - oldDecoDX, self.currentDecoDY - oldDecoDY);
    if (frameDisplacement > kChevronPhysicsConstants.hapticThreshold) { 
        static NSTimeInterval lastHapticTime = 0;
        NSTimeInterval now = CACurrentMediaTime();
        if (now - lastHapticTime > 0.1) { 
            [self.selectionFeedback selectionChanged];
            lastHapticTime = now;
        }
    }

    CGAffineTransform decoParallax = CGAffineTransformMakeTranslation(self.currentDecoDX, self.currentDecoDY);
    self.trafficCapsule.transform = decoParallax;
    self.resizingHandle.transform = decoParallax;

    // 建议：边缘折射干扰 (Edge Refraction Flicker)
    CGFloat tilt = sqrt(m.attitude.roll * m.attitude.roll + m.attitude.pitch * m.attitude.pitch);
    if (tilt > 1.1) { 
        CGFloat flicker = 0.15 * sin(CACurrentMediaTime() * 18.0); 
        CGFloat boost = (tilt - 1.1) * 0.6 + flicker;

        self.cyanLayer.borderColor = [[UIColor cyanColor] colorWithAlphaComponent:MIN(0.6, 0.12 + MAX(0, boost))].CGColor;
        self.magentaLayer.borderColor = [[UIColor magentaColor] colorWithAlphaComponent:MIN(0.6, 0.12 + MAX(0, boost))].CGColor;
        self.innerGlowLayer.borderColor = [[UIColor labelColor] colorWithAlphaComponent:MIN(1.0, 0.45 + MAX(0, boost))].CGColor;
        self.innerGlowLayer.borderWidth = 0.3 + MAX(0, boost) * 1.5;
    } else {
        self.cyanLayer.borderColor = [[UIColor cyanColor] colorWithAlphaComponent:0.12].CGColor;
        self.magentaLayer.borderColor = [[UIColor magentaColor] colorWithAlphaComponent:0.12].CGColor;
        self.innerGlowLayer.borderColor = [[UIColor labelColor] colorWithAlphaComponent:0.45].CGColor;
        self.innerGlowLayer.borderWidth = 0.3;
    }

    [CATransaction commit];
}

- (void)stopLiquidMotion {
    [self.motionManager stopDeviceMotionUpdates];

    if (self.liquidDisplayLink) {
        [self.liquidDisplayLink invalidate];
        self.liquidDisplayLink = nil;
    }

    [CATransaction begin]; [CATransaction setDisableActions:YES];
    self.redGlow.hidden = YES; self.yellowGlow.hidden = YES; self.greenGlow.hidden = YES;
    [CATransaction commit];
}

// 建议 1：微流体记忆 (Viscous Residue Memory)
- (void)showTrailingResidueFromPoint:(CGPoint)startPoint toPoint:(CGPoint)endPoint {
    UIBezierPath *path = [UIBezierPath bezierPath];
    [path moveToPoint:startPoint];
    [path addQuadCurveToPoint:endPoint controlPoint:CGPointMake((startPoint.x + endPoint.x)/2, startPoint.y)];
    self.trailLayer.path = path.CGPath;
    
    [UIView animateWithDuration:0.5 animations:^{ self.trailLayer.opacity = 0; } completion:^(BOOL f) {
        self.trailLayer.path = nil; self.trailLayer.opacity = 1.0;
    }];
}

// 建议 2：光照探测器 (Luminous Proximity)
- (void)emitLightWaveFromPoint:(CGPoint)point {
    UIView *wave = [[UIView alloc] initWithFrame:CGRectMake(point.x, point.y, 20, 20)];
    wave.backgroundColor = [[UIColor whiteColor] colorWithAlphaComponent:0.3];
    wave.layer.cornerRadius = 10;
    [self.lightWaveView addSubview:wave];
    [UIView animateWithDuration:0.8 animations:^{
        wave.transform = CGAffineTransformMakeScale(20, 20);
        wave.alpha = 0;
    } completion:^(BOOL f){ [wave removeFromSuperview]; }];
}



// 建议 3：交互黑洞预知系统 (Black Hole Predictive System)
- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    [super touchesBegan:touches withEvent:event];
    if (!self.isPanelShowing) {
        UITouch *touch = [touches anyObject];
        // 探测靠近边界的行为（1cm 距离阈值）
        if ([touch locationInView:self].x > self.bounds.size.width - 50) {
            self.isInPredictiveMode = YES;
            // 移除 panelContainer.hidden = NO 和 alpha 设置
        }
    }
}


- (void)scrollViewDidEndDecelerating:(UIScrollView *)scrollView {
    [UIView animateWithDuration:0.4 delay:0 usingSpringWithDamping:0.6 initialSpringVelocity:0.5 options:0 animations:^{
        self.collectionView.layer.transform = CATransform3DIdentity;
        self.collectionView.alpha = 1.0;
    } completion:nil];
}

- (void)scrollViewDidEndDragging:(UIScrollView *)scrollView willDecelerate:(BOOL)decelerate {
    if (!decelerate) {
        [self scrollViewDidEndDecelerating:scrollView];
    }
}

- (BOOL)shouldIncludeApp:(id)appProxy {
    // 1. 必须是用户应用
    if ([appProxy respondsToSelector:@selector(isUserApplication)] && ![appProxy performSelector:@selector(isUserApplication)]) {
        return NO;
    }
    
    // 2. 必须有图标
    NSString *bundleId = [appProxy performSelector:@selector(bundleIdentifier)];
    UIImage *icon = [UIImage _applicationIconImageForBundleIdentifier:bundleId format:10 scale:[UIScreen mainScreen].scale];
    if (!icon) return NO;

    // 3. 排除特定系统组件（通过 Bundle ID 前缀）
    static NSArray *excludedPrefixes = nil;
    if (!excludedPrefixes) {
        excludedPrefixes = @[@"com.apple.webapp", @"com.apple.tips", @"com.apple.stocks"];
    }
    for (NSString *prefix in excludedPrefixes) {
        if ([bundleId hasPrefix:prefix]) return NO;
    }

    return YES;
}

- (void)loadAppsAsync {
    dispatch_async(dispatch_get_global_queue(0,0), ^{
        // 建议1：增量更新机制。如果不需要全量重载且列表不为空，则跳过重型资源获取过程
        if (!self.needsFullReload && self.apps.count > 0) {
            CV3LogToFile(@"[Debug] 命中增量更新，仅刷新置顶与排序状态");
        } else {
            CV3LogToFile(@"[Debug] 执行全量应用资源同步 (needsFullReload=%d)", self.needsFullReload);
            [cv3IconCache removeAllObjects];
            
            NSMutableArray *temp = [NSMutableArray array];
            // 尝试从 SpringBoard 获取真正的桌面可见图标模型
            id iconController = [NSClassFromString(@"SBIconController") sharedInstance];
            id iconModel = nil;
            if ([iconController respondsToSelector:@selector(iconManager)]) {
                id iconManager = [iconController performSelector:@selector(iconManager)];
                if ([iconManager respondsToSelector:@selector(model)]) {
                    iconModel = [iconManager performSelector:@selector(model)];
                }
            }
            if (!iconModel && [iconController respondsToSelector:@selector(model)]) {
                iconModel = [iconController performSelector:@selector(model)];
            }
            
            if (iconModel && [iconModel respondsToSelector:@selector(leafIcons)]) {
                id leafIcons = [iconModel performSelector:@selector(leafIcons)];
                for (id icon in leafIcons) {
                    if ([icon respondsToSelector:@selector(isApplicationIcon)] && [icon performSelector:@selector(isApplicationIcon)]) {
                        NSString *bundleId = nil;
                        if ([icon respondsToSelector:@selector(applicationBundleID)]) {
                            bundleId = [icon performSelector:@selector(applicationBundleID)];
                        } else if ([icon respondsToSelector:@selector(leafIdentifier)]) {
                            bundleId = [icon performSelector:@selector(leafIdentifier)];
                        }
                        
                        NSString *name = nil;
                        if ([icon respondsToSelector:@selector(displayNameForLocation:)]) {
                            name = [icon performSelector:@selector(displayNameForLocation:) withObject:nil];
                        }
                        if (!name && [icon respondsToSelector:@selector(displayName)]) {
                            name = [icon performSelector:@selector(displayName)];
                        }
                        
                        if (!bundleId || !name) continue;
                        
                        CV3AppInfo *info = [[CV3AppInfo alloc] init];
                        info.name = name;
                        info.bundleId = bundleId;
                        info.sbIcon = icon; 
                        [info generatePinyin];
                        
                        @try {
                            Class LSAP = NSClassFromString(@"LSApplicationProxy");
                            id proxy = nil;
                            if ([LSAP respondsToSelector:@selector(applicationProxyForIdentifier:)]) {
                                proxy = [LSAP performSelector:@selector(applicationProxyForIdentifier:) withObject:bundleId];
                            } else if ([LSAP respondsToSelector:@selector(applicationProxyForBundleIdentifier:)]) {
                                proxy = [LSAP performSelector:@selector(applicationProxyForBundleIdentifier:) withObject:bundleId];
                            }
                            if (proxy && [proxy respondsToSelector:@selector(genre)]) {
                                info.category = [proxy performSelector:@selector(genre)];
                            }
                        } @catch (NSException *e) {}
                        if (!info.category) info.category = @"其他";
                        
                        info.icon = [UIImage _applicationIconImageForBundleIdentifier:bundleId format:10 scale:[UIScreen mainScreen].scale];
                        if (info.icon) {
                            [cv3IconCache setObject:info.icon forKey:bundleId];
                            [temp addObject:info];
                        }
                    }
                }
            }
            
            if (temp.count == 0) {
                id ws = [NSClassFromString(@"LSApplicationWorkspace") defaultWorkspace];
                for (id p in [ws performSelector:@selector(allInstalledApplications)]) {
                    if (![self shouldIncludeApp:p]) continue;
                    NSString *bundleId = [p performSelector:@selector(bundleIdentifier)];
                    NSString *name = [p performSelector:@selector(localizedName)];
                    CV3AppInfo *info = [[CV3AppInfo alloc] init];
                    info.name = name;
                    info.bundleId = bundleId;
                    info.icon = [UIImage _applicationIconImageForBundleIdentifier:bundleId format:10 scale:[UIScreen mainScreen].scale];
                    if (info.icon) {
                        [cv3IconCache setObject:info.icon forKey:bundleId];
                        [temp addObject:info];
                    }
                }
            }
            self.apps = temp;
            self.needsFullReload = NO;
        }

        // 始终刷新置顶状态与使用频率排序
        NSDictionary *usageData = [[NSUserDefaults standardUserDefaults] dictionaryForKey:@"CV3AppUsageData"];
        NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
        NSTimeInterval sevenDaysInSeconds = 7 * 24 * 3600;

        for (CV3AppInfo *info in self.apps) {
            info.isPinned = [self.pinnedBundleIDs containsObject:info.bundleId];
            NSArray *ts = usageData[info.bundleId];
            if (ts && ts.count > 0) {
                info.lastUsedDate = [[ts lastObject] doubleValue];
            } else {
                info.lastUsedDate = 0;
            }
        }

        [self.apps sortUsingComparator:^NSComparisonResult(CV3AppInfo *obj1, CV3AppInfo *obj2) {
            // 1. 置顶优先
            if (obj1.isPinned != obj2.isPinned) return obj1.isPinned ? NSOrderedAscending : NSOrderedDescending;
            
            // 2. 熵减逻辑：最近使用过且频率高的排在前面
            NSArray *ts1 = usageData[obj1.bundleId];
            NSArray *ts2 = usageData[obj2.bundleId];
            
            // 计算 7 天内的加权分数（最近的权重大）
            double score1 = 0; for (NSNumber *ts in ts1) { double diff = now - [ts doubleValue]; if (diff < sevenDaysInSeconds) score1 += (1.0 / (diff / 3600.0 + 1.0)); }
            double score2 = 0; for (NSNumber *ts in ts2) { double diff = now - [ts doubleValue]; if (diff < sevenDaysInSeconds) score2 += (1.0 / (diff / 3600.0 + 1.0)); }
            
            if (score1 != score2) return score1 > score2 ? NSOrderedAscending : NSOrderedDescending;
            
            // 3. 最后使用时间兜底
            if (obj1.lastUsedDate != obj2.lastUsedDate) return obj1.lastUsedDate > obj2.lastUsedDate ? NSOrderedAscending : NSOrderedDescending;
            
            // 4. 拼音/名称排序
            return [obj1.name localizedCaseInsensitiveCompare:obj2.name];
        }];
        
        dispatch_async(dispatch_get_main_queue(), ^{ 
            self.recentlyUsedApps = [self.apps subarrayWithRange:NSMakeRange(0, MIN(12, self.apps.count))];
            [self updateCategoryBar]; 
            [self filterApps]; 
            [self animateIconsStaggered]; 
        });
    });
}

- (void)handleMemoryWarning {
    CV3LogToFile(@"[Warning] Received Memory Warning, clearing icon cache and pausing tasks...");
    [cv3IconCache removeAllObjects];
    self.needsFullReload = YES; 
}

- (void)show {
    [self attachToCurrentActiveScene];
    self.hidden = NO;
    
    [[NSNotificationCenter defaultCenter] addObserver:self 
                                             selector:@selector(attachToCurrentActiveScene) 
                                                 name:UISceneDidActivateNotification 
                                               object:nil];
                                               
    [[NSNotificationCenter defaultCenter] addObserver:self 
                                             selector:@selector(handleMemoryWarning) 
                                                 name:UIApplicationDidReceiveMemoryWarningNotification 
                                               object:nil];
                                               
    if (!self.heartbeatTimer) {
        self.heartbeatTimer = [NSTimer scheduledTimerWithTimeInterval:5.0 target:self selector:@selector(monitorState) userInfo:nil repeats:YES];
        [[NSRunLoop mainRunLoop] addTimer:self.heartbeatTimer forMode:NSRunLoopCommonModes];
    }
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(keyboardWillShow:) name:UIKeyboardWillShowNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(keyboardWillHide:) name:UIKeyboardWillHideNotification object:nil];
}



- (void)keyboardWillShow:(NSNotification *)notification {
    self.isKeyboardVisible = YES;
    
    NSDictionary *userInfo = notification.userInfo;
    CGRect keyboardFrame = [userInfo[UIKeyboardFrameEndUserInfoKey] CGRectValue];
    double duration = [userInfo[UIKeyboardAnimationDurationUserInfoKey] doubleValue];
    UIViewAnimationOptions options = [userInfo[UIKeyboardAnimationCurveUserInfoKey] unsignedIntegerValue] << 16;
    
    // 建议2：最小化键盘避让 (Minimized Displacement)
    // 不再以面板底部为基准，而是以“搜索框 + 关键结果区”的可见性为基准
    UIView *searchContainer = self.searchField.superview;
    // 计算搜索框底部在屏幕坐标系中的位置 (额外预留 60pt 给顶部几条搜索结果)
    CGRect searchFrameInScreen = [searchContainer.superview convertRect:searchContainer.frame toView:nil];
    CGFloat criticalBottom = CGRectGetMaxY(searchFrameInScreen) + 60.0;
    CGFloat keyboardTop = keyboardFrame.origin.y;
    
    CGFloat overlap = criticalBottom - keyboardTop;
    
    if (overlap > 0) { // 仅当搜索框或关键区域被遮挡时才移动
        CGFloat offset = overlap + 10.0; // 仅推移刚好避开的距离，增加 10pt 呼吸间距
        
        [UIView animateWithDuration:duration delay:0 options:options animations:^{
            CGPoint center = self.panelContainer.center;
            UIInterfaceOrientation orientation = self.targetOrientation != UIInterfaceOrientationUnknown ? self.targetOrientation : UIInterfaceOrientationPortrait;
            
            switch (orientation) {
                case UIInterfaceOrientationLandscapeLeft: center.x += offset; break;
                case UIInterfaceOrientationLandscapeRight: center.x -= offset; break;
                case UIInterfaceOrientationPortraitUpsideDown: center.y += offset; break;
                case UIInterfaceOrientationPortrait:
                default: center.y -= offset; break;
            }
            self.panelContainer.center = center;
        } completion:nil];
    }
}

- (void)keyboardWillHide:(NSNotification *)notification {
    self.isKeyboardVisible = NO;
    
    NSDictionary *userInfo = notification.userInfo;
    double duration = [userInfo[UIKeyboardAnimationDurationUserInfoKey] doubleValue];
    UIViewAnimationOptions options = [userInfo[UIKeyboardAnimationCurveUserInfoKey] unsignedIntegerValue] << 16;
    
    [UIView animateWithDuration:duration delay:0 options:options animations:^{
        // 自动回弹至由安全区域决定的目标中心（除非用户手动大幅挪动过）
        if (!self.hasBeenMoved) {
            self.panelContainer.center = [self calculateTargetCenter];
        } else {
            // 如果用户手动挪动过，则尝试执行反向推回逻辑，或者保持现状（这里选择回弹钳位以保证可用性）
            [self setNeedsLayout];
            [self layoutIfNeeded];
        }
    } completion:nil];
}

- (void)monitorState {
    @try {
        [self attachToCurrentActiveScene];
        
        // 核心修复：同步监控所有浮动窗口的持久状态
        for (CV3FloatingAppWindow *win in floatingWindows) {
            if ([win respondsToSelector:@selector(attachToCurrentActiveScene)]) {
                [win attachToCurrentActiveScene];
            }
        }
    } @catch (NSException *e) {
    }
}

- (BOOL)_shouldAutorotateToInterfaceOrientation:(long long)orientation { return NO; }

- (BOOL)isSystemUIActive {
    @try {
        // 检查控制中心 (使用类查找并转换类型)
        Class ccClass = NSClassFromString(@"SBControlCenterController");
        if (ccClass && [ccClass respondsToSelector:@selector(sharedInstance)]) {
            id cc = [ccClass performSelector:@selector(sharedInstance)];
            if (cc && [cc respondsToSelector:@selector(isPresented)] && [cc isPresented]) {
                return YES;
            }
        }
        
        // 检查通知栏/锁屏 (Cover Sheet)
        Class csClass = NSClassFromString(@"SBCoverSheetPresentationManager");
        if (csClass && [csClass respondsToSelector:@selector(sharedInstance)]) {
            id cs = [csClass performSelector:@selector(sharedInstance)];
            if (cs && [cs respondsToSelector:@selector(isAnyCoverSheetVisible)] && [cs isAnyCoverSheetVisible]) {
                return YES;
            }
        }
    } @catch (NSException *e) {
        CV3LogToFile(@"[Error] isSystemUIActive 检查失败: %@", e);
    }
    return NO;
}

- (void)attachToCurrentActiveScene {
    // 异步确保不在敏感的系统转换周期内执行同步 UI 操作
    dispatch_async(dispatch_get_main_queue(), ^{
        // 增加内部保护，防止异步任务堆叠
        if (self.isProcessing) return;
        self.isProcessing = YES;

        @try {
            UIWindowScene *targetScene = nil;
            if ([NSClassFromString(@"SBWindowScene") respondsToSelector:@selector(mainDisplayWindowScene)]) {
                targetScene = [NSClassFromString(@"SBWindowScene") performSelector:@selector(mainDisplayWindowScene)];
                if (targetScene) {
                    NSString *role = targetScene.session.role;
                    if ([role isEqualToString:@"SBWindowSceneSessionRoleSystemAperture"] ||
                        [role isEqualToString:@"SBWindowSceneSessionRoleSystemApertureCurtain"] ||
                        [role isEqualToString:@"UISceneSessionRolePlaceholder"] ||
                        [[role lowercaseString] containsString:@"siri"]) {
                        targetScene = nil;
                    }
                }
            }
            
            if (!targetScene) {
                for (UIScene *scene in [[UIApplication sharedApplication].connectedScenes allObjects]) {
                    if ([scene isKindOfClass:[UIWindowScene class]]) {
                        NSString *role = scene.session.role;
                        if ([role isEqualToString:@"SBWindowSceneSessionRoleSystemAperture"] ||
                            [role isEqualToString:@"SBWindowSceneSessionRoleSystemApertureCurtain"] ||
                            [role isEqualToString:@"UISceneSessionRolePlaceholder"] ||
                            [[role lowercaseString] containsString:@"siri"]) continue;
                        
                        if (scene.activationState == UISceneActivationStateForegroundActive) {
                            targetScene = (UIWindowScene *)scene;
                            break;
                        }
                    }
                }
            }

            if (targetScene) {
                BOOL needsLayoutUpdate = NO;
                if (self.windowScene != targetScene) {
                    self.windowScene = targetScene;
                    needsLayoutUpdate = YES;
                }
                
                CGRect targetBounds = targetScene.coordinateSpace.bounds;
                if (!CGRectEqualToRect(self.frame, targetBounds)) {
                    self.frame = targetBounds;
                    needsLayoutUpdate = YES;
                }

                // 核心修复：调用 setHidden 触发重写后的压制检查
                if (self.hidden) {
                    self.hidden = NO;
                    needsLayoutUpdate = YES;
                }
                
                [self applyAdaptiveLevel];

                if (needsLayoutUpdate) {
                    [self setNeedsLayout];
                }
            }
        } @catch (NSException *e) {}
        self.isProcessing = NO;
    });
}

- (void)applyAdaptiveLevel {
    // 建议：层级对齐 (Level Alignment)
    // 根据 GEMINI.md 规范，锁定在 panel (2099) 以确保覆盖所有第三方 App，且保持在控制中心之下
    CGFloat targetLevel = kChevronWindowLevels.panel; 
    
    if (self.windowLevel != targetLevel) {
        self.windowLevel = targetLevel;
    }
}

- (NSInteger)collectionView:(id)c numberOfItemsInSection:(NSInteger)s { return self.filteredApps.count; }
- (id)collectionView:(id)c cellForItemAtIndexPath:(id)i {
    CV3AppCell *cell = [c dequeueReusableCellWithReuseIdentifier:@"C" forIndexPath:i];
    NSInteger index = [(NSIndexPath *)i item];
    CV3AppInfo *info = self.filteredApps[index];
    
    // 增加首项判断逻辑，用于开启搜索首项高亮
    BOOL isFirst = (index == 0 && self.searchField.text.length > 0);
    [cell configureWithInfo:info searchText:self.searchField.text isFirst:isFirst];
    
    // 关键：为最近使用的应用增加“脉冲呼吸”光效
    BOOL isRecent = NO;
    for (CV3AppInfo *recent in self.recentlyUsedApps) {
        if ([recent.bundleId isEqualToString:info.bundleId]) {
            isRecent = YES;
            break;
        }
    }
    
    if (isRecent) {
        [cell startPulse];
    } else {
        [cell stopPulse];
    }
    
    // 应用“熵减”衰老视觉效果
    [self applyAgingEffectToCell:cell withInfo:info];
    
    return cell;
}


- (BOOL)_canBecomeKeyWindow { return YES; }
- (BOOL)canBecomeKeyWindow { return YES; }
- (BOOL)_ignoresHitTest { return NO; }
- (BOOL)_shouldIsolate { return YES; }

#pragma mark - 强制压制逻辑：深度抑制，防止在系统 UI 活跃时出现
- (void)setHidden:(BOOL)hidden {
    if (!hidden && self.isSuppressedBySystem) {
        CV3LogToFile(@"[Debug] 拦截到非法的 unhide 请求 (当前处于系统压制状态)");
        [super setHidden:YES];
        self.alpha = 0;
        self.windowLevel = kChevronWindowLevels.background; // 降到最低层
        return;
    }
    
    [super setHidden:hidden];
    
    // 状态同步
    if (hidden) {
        self.alpha = 0;
    } else {
        self.alpha = 1.0;
        [self applyAdaptiveLevel];
    }
}

#pragma mark - 尝试绕过 App 级触控黑洞的私有方法
- (BOOL)_isSecure { return YES; }
- (BOOL)_isWindowServerHostingManaged { return YES; }
- (BOOL)_wantsSceneAssociation { return YES; }

- (UIView *)hitTest:(CGPoint)point withEvent:(id)e {
    if (self.isPanelShowing) {
        // 1. 优先检查搜索框及其容器（最高优先级，防止被拖拽拦截）
        UIView *searchContainer = self.searchField.superview;
        CGPoint pInSearch = [self convertPoint:point toView:searchContainer];
        if (CGRectContainsPoint(searchContainer.bounds, pInSearch)) {
            UIView *hit = [searchContainer hitTest:pInSearch withEvent:e];
            return hit ?: searchContainer;
        }

        // 2. 检查面板区域
        // 核心修复：移除严格的 bounds 检查，允许点击因视差（Parallax）而超出容器物理边界的组件
        CGPoint p = [self convertPoint:point toView:self.panelContainer];
        UIView *hit = [self.panelContainer hitTest:p withEvent:e];
        if (hit) return hit;

        // 如果点中了面板物理边界内但没有具体子视图响应，返回面板容器以便处理拖拽
        if (CGRectContainsPoint(self.panelContainer.bounds, p)) {
            return self.panelContainer;
        }
        
        // 检查遮罩层
        CGPoint pInDimming = [self convertPoint:point toView:self.dimmingView];
        if (CGRectContainsPoint(self.dimmingView.bounds, pInDimming)) {
            return self.dimmingView;
        }
        return nil;
    }

    // 触控透传架构: 当面板隐藏时，CV3Window 的 hitTest 返回 nil，实现完全透传，
    // 让底层 App 窗口直接接收并处理手势，由 hostWindow 上的 systemEdgePan 触发。
    return nil;
}

@end

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

        // 如果 windowScene 的方向与当前设定的方向一致，直接跳过，防止重算导致的“回跳”
        if (sharedWindow && sharedWindow.targetOrientation == currentOrientation) return;

        NSTimeInterval currentTime = [[NSDate date] timeIntervalSince1970];

        if (currentTime - lastLogTime > 0.5) {
            lastLogTime = currentTime;

            CV3LogToFile(@"[Debug] 采信并应用方向改变: %ld, 来源 Role: %@", (long)currentOrientation, role);

            isUpdating = YES;
            // 使用异步确保当前 layout 周期执行完毕，避免重入导致的错位
            dispatch_async(dispatch_get_main_queue(), ^{
                if (sharedWindow) {
                    sharedWindow.targetOrientation = currentOrientation;
                    [sharedWindow attachToCurrentActiveScene];
                    [sharedWindow setNeedsLayout];
                }
                
                if (floatingWindows) {
                    for (CV3FloatingAppWindow *win in floatingWindows) {
                        if ([win isKindOfClass:[CV3FloatingAppWindow class]] && !win.isClosing) {
                            win.targetOrientation = currentOrientation; // 核心：同步目标方向
                            [win attachToCurrentActiveScene];
                            [win setNeedsLayout];
                        }
                    }
                }
            });
            isUpdating = NO;
        }
    }
}
%end



@interface SBWorkspaceEntity : NSObject
- (id)applicationSceneEntity;
@end

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
            @try {
                NSString *bid = nil;
                if ([entity respondsToSelector:@selector(applicationSceneEntity)]) {
                    id appEntity = [entity performSelector:@selector(applicationSceneEntity)];
                    if ([appEntity respondsToSelector:@selector(bundleIdentifier)]) {
                        bid = [appEntity performSelector:@selector(bundleIdentifier)];
                    }
                }

                if (bid) {
                    for (CV3FloatingAppWindow *win in floatingWindows) {
                        if ([bid isEqualToString:win.bundleID] && !win.isClosing) {
                            [mutableDeactivated removeObject:entity];
                            modified = YES;
                            CV3LogToFile(@"[Immortality] 成功从停用列表中剔除分屏应用: %@", bid);
                        }
                    }
                }
            } @catch (NSException *e) {}
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
            @try {
                NSString *bid = nil;
                if ([entity respondsToSelector:@selector(applicationSceneEntity)]) {
                    id appEntity = [entity performSelector:@selector(applicationSceneEntity)];
                    if ([appEntity respondsToSelector:@selector(bundleIdentifier)]) {
                        bid = [appEntity performSelector:@selector(bundleIdentifier)];
                    }
                }

                if (bid) {
                    for (CV3FloatingAppWindow *win in floatingWindows) {
                        if ([bid isEqualToString:win.bundleID] && !win.isClosing) {
                            [mutableResigning removeObject:entity];
                            modified = YES;
                            CV3LogToFile(@"[Immortality] 成功从辞职(Resign)列表中剔除分屏应用: %@", bid);
                        }
                    }
                }
            } @catch (NSException *e) {}
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
                            return kChevronLayoutConstants.cornerRadius;
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
                    id item = nil;
                    if ([NSClassFromString(@"SBDisplayItem") respondsToSelector:@selector(displayItemWithType:bundleIdentifier:)]) {
                        item = [NSClassFromString(@"SBDisplayItem") performSelector:@selector(displayItemWithType:bundleIdentifier:) withObject:@"main" withObject:win.bundleID];
                    }
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
    %orig(arg1);
}

- (void)workspace:(id)arg1 didExecuteTransitionRequest:(id)arg2 {
    %orig;
    CV3LogToFile(@"[Workspace] 转换请求已执行完毕，执行最终渲染对齐");
    if (floatingWindows) {
        for (CV3FloatingAppWindow *win in floatingWindows) {
            if ([win isKindOfClass:[CV3FloatingAppWindow class]] && !win.isClosing) {
                // 转换后稍微延迟执行，确保系统状态稳定
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.15 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                    [win attachToCurrentActiveScene];
                    [win refreshHostViewPresentation];
                    CV3LogToFile(@"[Workspace] 转换后延迟对齐完成: %@", win.bundleID);
                });
            }
        }
    }

    // 恢复对主窗口的场景同步及取色逻辑
    if (sharedWindow) {
        [sharedWindow attachToCurrentActiveScene];
        @try {
            id activeItem = nil;
            if ([self respondsToSelector:@selector(activeDisplayItem)]) {
                activeItem = [self performSelector:@selector(activeDisplayItem)];
            }
            if (activeItem && [activeItem respondsToSelector:@selector(bundleIdentifier)]) {
                NSString *bid = [activeItem performSelector:@selector(bundleIdentifier)];
                CV3UpdateAdaptiveTint(bid);
            }
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

%hook _UISceneLayerHostContainerView
- (void)layoutSubviews {
    %orig;
    for (UIView *subview in self.subviews) {
        if ([NSStringFromClass([subview class]) containsString:@"Keyboard"]) {
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
                cv3_keyboardWindow.windowLevel = kChevronWindowLevels.keyboard;
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
    %orig;
    // 核心：当 Switcher 窗口状态改变时，强制刷新所有分屏窗口的显示状态
    if (floatingWindows) {
        for (CV3FloatingAppWindow *win in floatingWindows) {
            if ([win isKindOfClass:[CV3FloatingAppWindow class]] && !win.isClosing) {
                [win setHidden:NO];
                [win makeKeyAndVisible];
                [win refreshHostViewPresentation];
            }
        }
    }
}

- (void)_setMainSwitcherVisible:(BOOL)arg1 {
    %orig;
    if (floatingWindows) {
        for (CV3FloatingAppWindow *win in floatingWindows) {
            if ([win isKindOfClass:[CV3FloatingAppWindow class]] && !win.isClosing) {
                [win setHidden:NO];
                [win refreshHostViewPresentation];
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

                CV3LogToFile(@"[FBScene] 捕捉到 Settings 更新请求: %@", win.bundleID);
                id mutableSettings = [arg1 mutableCopy];
                BOOL modified = NO;

                if ([mutableSettings respondsToSelector:@selector(setForeground:)]) {
                    [mutableSettings setForeground:YES];
                    modified = YES;
                }
                if ([mutableSettings respondsToSelector:@selector(setBackgrounded:)]) {
                    [mutableSettings setBackgrounded:NO];
                    modified = YES;
                }
                
                // [Foreground Sovereignty] Extra Hardening in global hook
                @try {
                    if ([mutableSettings respondsToSelector:@selector(setOccluded:)]) {
                        [mutableSettings setValue:@NO forKey:@"occluded"];
                        modified = YES;
                    }
                    if ([mutableSettings respondsToSelector:@selector(setVisibility:)]) {
                        [mutableSettings setValue:@2 forKey:@"visibility"];
                        modified = YES;
                    }
                    if ([mutableSettings respondsToSelector:@selector(setIdleTimerDisabled:)]) {
                        [mutableSettings setValue:@YES forKey:@"idleTimerDisabled"];
                        modified = YES;
                    }

                    // [Foreground Sovereignty] Force interruptionPolicy to 1 (Suppress)
                    if ([mutableSettings respondsToSelector:@selector(setInterruptionPolicy:)]) {
                        [mutableSettings setInterruptionPolicy:1];
                        modified = YES;
                    } else {
                        @try { 
                            [mutableSettings setValue:@1 forKey:@"interruptionPolicy"]; 
                            modified = YES;
                        } @catch (NSException *e) {}
                    }

                    // [Layout Sovereignty] 注入安全区域约束与方向硬化
                    // 抖音搜索冻屏通常是因为在转场瞬间 SceneSettings 丢失了关键布局元数据，导致渲染引擎 Fence 等待超时
                    if ([mutableSettings isKindOfClass:[%c(UIMutableApplicationSceneSettings) class]]) {
                        UIMutableApplicationSceneSettings *uim = (UIMutableApplicationSceneSettings *)mutableSettings;
                        UIEdgeInsets safeArea = UIEdgeInsetsZero; // 分屏模式下通常不使用系统级 Safe Area，由宿主控制
                        
                        if ([uim respondsToSelector:@selector(setSafeAreaInsetsPortrait:)]) uim.safeAreaInsetsPortrait = safeArea;
                        if ([uim respondsToSelector:@selector(setSafeAreaInsetsLandscapeLeft:)]) uim.safeAreaInsetsLandscapeLeft = safeArea;
                        if ([uim respondsToSelector:@selector(setSafeAreaInsetsLandscapeRight:)]) uim.safeAreaInsetsLandscapeRight = safeArea;
                        if ([uim respondsToSelector:@selector(setSafeAreaInsetsPortraitUpsideDown:)]) uim.safeAreaInsetsPortraitUpsideDown = safeArea;
                        
                        // 强制同步方向，防止在搜索弹出键盘时触发不必要的旋转计算导致的死锁
                        if ([uim respondsToSelector:@selector(setInterfaceOrientation:)]) {
                            [uim performSelector:@selector(setInterfaceOrientation:) withObject:@(win.targetOrientation)];
                        }
                        
                        // [Deactivation Immunity] 核心防御：清除系统手势导致的失活原因 (Deactivation Reasons)
                        // 当用户触发 Home 手势时，系统会为活跃场景附加 deactivationReasons 导致 App 进入 Inactive 状态，从而触发视频暂停。
                        if ([uim respondsToSelector:@selector(setDeactivationReasons:)]) {
                            uim.deactivationReasons = 0;
                        }
                        
                        modified = YES;
                    }
                } @catch (NSException *e) {}

                if (modified) {
                    %orig(mutableSettings, arg2);
                } else {
                    %orig(arg1, arg2);
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

                CV3LogToFile(@"[FBScene] 捕捉到 Settings 更新请求 (带 completion): %@", win.bundleID);
                id mutableSettings = [arg1 mutableCopy];
                BOOL modified = NO;

                if ([mutableSettings respondsToSelector:@selector(setForeground:)]) {
                    [mutableSettings setForeground:YES];
                    modified = YES;
                }
                if ([mutableSettings respondsToSelector:@selector(setBackgrounded:)]) {
                    [mutableSettings setBackgrounded:NO];
                    modified = YES;
                }
                
                @try {
                    if ([mutableSettings respondsToSelector:@selector(setOccluded:)]) {
                        [mutableSettings setValue:@NO forKey:@"occluded"];
                        modified = YES;
                    }
                    if ([mutableSettings respondsToSelector:@selector(setVisibility:)]) {
                        [mutableSettings setValue:@2 forKey:@"visibility"];
                        modified = YES;
                    }
                    if ([mutableSettings respondsToSelector:@selector(setIdleTimerDisabled:)]) {
                        [mutableSettings setValue:@YES forKey:@"idleTimerDisabled"];
                        modified = YES;
                    }

                    // [Foreground Sovereignty] Force interruptionPolicy to 1 (Suppress)
                    if ([mutableSettings respondsToSelector:@selector(setInterruptionPolicy:)]) {
                        [mutableSettings setInterruptionPolicy:1];
                        modified = YES;
                    } else {
                        @try { 
                            [mutableSettings setValue:@1 forKey:@"interruptionPolicy"]; 
                            modified = YES;
                        } @catch (NSException *e) {}
                    }

                    // [Layout Sovereignty] 注入安全区域约束与方向硬化
                    if ([mutableSettings isKindOfClass:[%c(UIMutableApplicationSceneSettings) class]]) {
                        UIMutableApplicationSceneSettings *uim = (UIMutableApplicationSceneSettings *)mutableSettings;
                        UIEdgeInsets safeArea = UIEdgeInsetsZero;
                        if ([uim respondsToSelector:@selector(setSafeAreaInsetsPortrait:)]) uim.safeAreaInsetsPortrait = safeArea;
                        if ([uim respondsToSelector:@selector(setSafeAreaInsetsLandscapeLeft:)]) uim.safeAreaInsetsLandscapeLeft = safeArea;
                        if ([uim respondsToSelector:@selector(setSafeAreaInsetsLandscapeRight:)]) uim.safeAreaInsetsLandscapeRight = safeArea;
                        if ([uim respondsToSelector:@selector(setSafeAreaInsetsPortraitUpsideDown:)]) uim.safeAreaInsetsPortraitUpsideDown = safeArea;
                        
                        if ([uim respondsToSelector:@selector(setInterfaceOrientation:)]) {
                            [uim performSelector:@selector(setInterfaceOrientation:) withObject:@(win.targetOrientation)];
                        }
                        
                        if ([uim respondsToSelector:@selector(setDeactivationReasons:)]) {
                            uim.deactivationReasons = 0;
                        }
                        
                        modified = YES;
                    }
                } @catch (NSException *e) {}

                if (modified) {
                    %orig(mutableSettings, arg2, arg3);
                } else {
                    %orig(arg1, arg2, arg3);
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
