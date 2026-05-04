#import <UIKit/UIKit.h>
#import <CoreMotion/CoreMotion.h>
#import <QuartzCore/QuartzCore.h>
#import <AudioToolbox/AudioToolbox.h>

// --- Private API Declarations ---
@interface SBWindow : UIWindow
@end

@interface SBDeviceApplicationSceneWindow : SBWindow
@end

@interface SBSystemGestureManager : NSObject
+ (id)mainDisplayManager;
- (void)addGestureRecognizer:(id)arg1 withType:(unsigned long long)arg2;
@end

@interface SBMainWorkspace : NSObject
+ (id)sharedInstance;
- (UIInterfaceOrientation)activeInterfaceOrientation;
@end

@interface LSApplicationWorkspace : NSObject
+ (id)defaultWorkspace;
- (NSArray *)allInstalledApplications;
- (BOOL)openApplicationWithBundleID:(id)arg1;
@end

@interface UIImage (Private)
+ (UIImage *)_applicationIconImageForBundleIdentifier:(NSString *)bundleIdentifier format:(int)format scale:(CGFloat)scale;
@end

// --- Data Model ---
@interface CV3AppInfo : NSObject
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSString *bundleId;
@property (nonatomic, strong) UIImage *icon;
@end
@implementation CV3AppInfo
@end

// --- Custom Cell ---
@interface CV3AppCell : UICollectionViewCell
@property (nonatomic, strong) UIImageView *iconView;
@property (nonatomic, strong) UILabel *nameLabel;
- (void)configureWithInfo:(CV3AppInfo *)info;
- (void)startBreathing;
@end

@implementation CV3AppCell
- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        CGFloat iconSize = 54.0;
        UIView *ivBack = [[UIView alloc] initWithFrame:CGRectMake((frame.size.width - iconSize)/2, 8, iconSize, iconSize)];
        ivBack.backgroundColor = [[UIColor whiteColor] colorWithAlphaComponent:0.08];
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
        self.nameLabel = [[UILabel alloc] initWithFrame:CGRectMake(4, iconSize + 14, frame.size.width - 8, 28)];
        self.nameLabel.textColor = [[UIColor whiteColor] colorWithAlphaComponent:0.9];
        self.nameLabel.font = [UIFont systemFontOfSize:10.0 weight:UIFontWeightMedium];
        self.nameLabel.textAlignment = NSTextAlignmentCenter;
        self.nameLabel.numberOfLines = 2;
        [self.contentView addSubview:self.nameLabel];
    }
    return self;
}
- (void)configureWithInfo:(CV3AppInfo *)info {
    self.nameLabel.text = info.name;
    self.iconView.image = info.icon;
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
@end

// --- Root VC ---
#import <UIKit/UIKit.h> // Explicitly import UIKit to ensure visibility of UIWindowScene

@interface CV3RootViewController : UIViewController
@end
static void CV3LogToFile(NSString *format, ...) {
// --- Helper for File Logging (Asynchronous & Safe) ---
    va_list args;
    va_start(args, format);
    NSString *message = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);

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
            }
            
            NSFileHandle *handle = [NSFileHandle fileHandleForWritingAtPath:logPath];
            if (handle) {
                [handle seekToEndOfFile];
                NSString *timestamp = [NSDateFormatter localizedStringFromDate:[NSDate date] dateStyle:NSDateFormatterShortStyle timeStyle:NSDateFormatterMediumStyle];
                NSString *finalLog = [NSString stringWithFormat:@"[%@] %@\n", timestamp, message];
                // 确保使用 UTF-8 编码写入文件
                [handle writeData:[finalLog dataUsingEncoding:NSUTF8StringEncoding]];
                [handle closeFile];
            }
        } @catch (NSException *e) {}
    });
}

@implementation CV3RootViewController
@end

// --- Main Window ---
@interface CV3Window : UIWindow <UIGestureRecognizerDelegate, UICollectionViewDataSource, UICollectionViewDelegate>
@property (nonatomic, strong) UIView *panelContainer; 
@property (nonatomic, strong) UIVisualEffectView *appPanel; 
@property (nonatomic, strong) UICollectionView *collectionView;
@property (nonatomic, strong) UIView *edgeTriggerView; 
@property (nonatomic, strong) CAGradientLayer *specularHighlight;
@property (nonatomic, strong) CMMotionManager *motionManager;
@property (nonatomic, strong) UIView *bezierContainer;
@property (nonatomic, strong) CAShapeLayer *bezierLayer;
@property (nonatomic, strong) UIVisualEffectView *bezierBlur;
@property (nonatomic, strong) CALayer *cyanLayer;
@property (nonatomic, strong) CALayer *magentaLayer;
@property (nonatomic, assign) BOOL isPanelShowing;
@property (nonatomic, assign) BOOL isAnimating;
@property (nonatomic, strong) NSMutableArray<CV3AppInfo *> *apps;
@property (nonatomic, strong) UIImpactFeedbackGenerator *feedback;
@property (nonatomic, strong) UISelectionFeedbackGenerator *selectionFeedback;
@property (nonatomic, strong) NSTimer *heartbeatTimer;
@property (nonatomic, assign) BOOL isKeyboardVisible; 
@property (nonatomic, assign) BOOL hasBeenMoved;
@property (nonatomic, strong) UIView *dimmingView;
@property (nonatomic, strong) UIView *resizingHandle;
@property (nonatomic, strong) UIView *trafficCapsule;
@property (nonatomic, strong) NSArray<UIView *> *trafficDots;
@property (nonatomic, assign) CGFloat lastHapticX;
@property (nonatomic, strong) UIScreenEdgePanGestureRecognizer *systemEdgePan;
@property (nonatomic, assign) UIInterfaceOrientation targetOrientation;

- (void)show;
- (NSString *)_role; 
@end

static NSCache *cv3IconCache = nil; 
static CV3Window *sharedWindow = nil;
static const CGFloat kPanelW = 370.0;
static const CGFloat kPanelH = 520.0;
static const CGFloat kTriggerHotzoneWidth = 50.0;
static const CGFloat kTriggerVisualWidth = 20.0;
static const CGFloat kTriggerBottomOffset = 100.0;

@implementation CV3Window

- (NSString *)_role {
    return @"SBWindowRoleFloatingCanHostLaunchpad"; 
}

- (BOOL)_canAffectStatusBarAppearance { return NO; }

- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)gesture {
    if (gesture == self.systemEdgePan) {
        // 键盘可见时限制区域
        if (self.isKeyboardVisible) {
            CGPoint p = [gesture locationInView:nil];
            CGFloat yThreshold = self.bounds.size.height * 0.4;
            if (p.y > yThreshold) return NO;
        }
        
        // 限制在安全区域范围内触发
        UIEdgeInsets safe = self.safeAreaInsets;
        CGPoint p = [gesture locationInView:self];
        if (p.y < safe.top || p.y > (self.bounds.size.height - safe.bottom)) {
            return NO;
        }
    }
    return YES;
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldBeRequiredToFailByGestureRecognizer:(UIGestureRecognizer *)otherGestureRecognizer {
    if (gestureRecognizer == self.systemEdgePan && [otherGestureRecognizer isKindOfClass:[UIScreenEdgePanGestureRecognizer class]]) {
        return YES;
    }
    return NO;
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldRequireFailureOfGestureRecognizer:(UIGestureRecognizer *)otherGestureRecognizer {
    return NO;
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)otherGestureRecognizer {
    return YES; 
}

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        if (!cv3IconCache) cv3IconCache = [[NSCache alloc] init];
        [self applyAdaptiveLevel];
        self.backgroundColor = [UIColor clearColor];
        self.apps = [NSMutableArray array];
        self.feedback = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleHeavy];
        self.selectionFeedback = [[UISelectionFeedbackGenerator alloc] init];
        self.motionManager = [[CMMotionManager alloc] init];
        self.motionManager.deviceMotionUpdateInterval = 1.0 / 120.0;
        CV3RootViewController *rootVC = [[CV3RootViewController alloc] init];
        rootVC.view.backgroundColor = [UIColor clearColor];
        self.rootViewController = rootVC;
        [self setupUI];
    }
    return self;
}

- (void)setupUI {
    CGRect bounds = self.bounds;

    self.edgeTriggerView = [[UIView alloc] initWithFrame:CGRectZero];
    self.edgeTriggerView.backgroundColor = [[UIColor redColor] colorWithAlphaComponent:0.2]; // 调试可见
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
    
    self.bezierContainer = [[UIView alloc] initWithFrame:bounds];
    self.bezierContainer.backgroundColor = [[UIColor greenColor] colorWithAlphaComponent:0.1]; // 调试可见
    self.bezierContainer.alpha = 0;
    self.bezierContainer.userInteractionEnabled = NO;
    self.bezierContainer.autoresizingMask = UIViewAutoresizingNone;
    [self.rootViewController.view addSubview:self.bezierContainer];
    
    self.bezierBlur = [[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemUltraThinMaterial]];
    self.bezierBlur.frame = bounds;
    self.bezierBlur.autoresizingMask = UIViewAutoresizingNone;
    [self.bezierContainer addSubview:self.bezierBlur];
    self.bezierLayer = [CAShapeLayer layer];
    self.bezierLayer.fillColor = [UIColor whiteColor].CGColor;
    self.bezierBlur.layer.mask = self.bezierLayer; 
    
    self.panelContainer = [[UIView alloc] initWithFrame:CGRectMake(0, 0, kPanelW, kPanelH)];
    self.panelContainer.backgroundColor = [[UIColor blueColor] colorWithAlphaComponent:0.2]; // 调试可见
    self.panelContainer.hidden = YES;
    self.panelContainer.layer.shadowColor = [UIColor blackColor].CGColor;
    self.panelContainer.layer.shadowOffset = CGSizeMake(0, 20);
    self.panelContainer.layer.shadowOpacity = 0.45;
    self.panelContainer.layer.shadowRadius = 50;
    self.panelContainer.autoresizingMask = UIViewAutoresizingNone;
    [self.rootViewController.view addSubview:self.panelContainer];
    
    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handlePanelDrag:)];
    [self.panelContainer addGestureRecognizer:pan];
    
    self.appPanel = [[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemUltraThinMaterial]];
    self.appPanel.frame = self.panelContainer.bounds;
    self.appPanel.backgroundColor = [[UIColor yellowColor] colorWithAlphaComponent:0.3]; // 调试可见
    self.appPanel.layer.cornerRadius = 28;
    self.appPanel.layer.masksToBounds = YES;
    self.appPanel.layer.borderWidth = 0.4;
    self.appPanel.layer.borderColor = [[UIColor whiteColor] colorWithAlphaComponent:0.2].CGColor;
    
    UIView *whiteFilter = [[UIView alloc] initWithFrame:self.appPanel.bounds];
    whiteFilter.backgroundColor = [[UIColor whiteColor] colorWithAlphaComponent:0.04];
    whiteFilter.userInteractionEnabled = NO;
    [self.appPanel.contentView addSubview:whiteFilter];

    self.specularHighlight = [CAGradientLayer layer];
    self.specularHighlight.frame = self.appPanel.bounds;
    self.specularHighlight.colors = @[(id)[[UIColor whiteColor] colorWithAlphaComponent:0.0].CGColor, (id)[[UIColor whiteColor] colorWithAlphaComponent:0.12].CGColor, (id)[[UIColor whiteColor] colorWithAlphaComponent:0.0].CGColor];
    [self.appPanel.layer addSublayer:self.specularHighlight];

    UIView *dispersion = [[UIView alloc] initWithFrame:self.appPanel.bounds];
    dispersion.layer.cornerRadius = 28;
    dispersion.layer.masksToBounds = YES;
    [self.appPanel.contentView addSubview:dispersion];
    
    self.cyanLayer = [CALayer layer]; 
    self.cyanLayer.frame = CGRectInset(dispersion.bounds, -0.3, -0.3);
    self.cyanLayer.borderColor = [[UIColor cyanColor] colorWithAlphaComponent:0.12].CGColor; 
    self.cyanLayer.borderWidth = 0.3; 
    [dispersion.layer addSublayer:self.cyanLayer];
    
    self.magentaLayer = [CALayer layer]; 
    self.magentaLayer.frame = CGRectInset(dispersion.bounds, 0.3, 0.3); 
    self.magentaLayer.borderColor = [[UIColor magentaColor] colorWithAlphaComponent:0.12].CGColor; 
    self.magentaLayer.borderWidth = 0.3; 
    [dispersion.layer addSublayer:self.magentaLayer];

    [self.panelContainer addSubview:self.appPanel];

    self.trafficCapsule = [[UIView alloc] initWithFrame:CGRectMake(16, 14, 64, 24)];
    self.trafficCapsule.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.08];
    self.trafficCapsule.layer.cornerRadius = 12;
    [self.panelContainer addSubview:self.trafficCapsule];
    
    NSMutableArray *dots = [NSMutableArray array];
    NSArray *tc = @[[UIColor colorWithRed:1.00 green:0.37 blue:0.33 alpha:1.0], [UIColor colorWithRed:1.00 green:0.75 blue:0.18 alpha:1.0], [UIColor colorWithRed:0.15 green:0.79 blue:0.25 alpha:1.0]];
    for (int i = 0; i < 3; i++) {
        UIButton *dot = [UIButton buttonWithType:UIButtonTypeCustom];
        dot.frame = CGRectMake(10 + i * 16, 8, 8, 8);
        dot.backgroundColor = tc[i];
        dot.layer.cornerRadius = 4;
        dot.tag = i;
        [dot addTarget:self action:@selector(handleTrafficLight:) forControlEvents:UIControlEventTouchUpInside];
        [self.trafficCapsule addSubview:dot];
        [dots addObject:dot];
    }
    self.trafficDots = dots;

    self.resizingHandle = [[UIView alloc] initWithFrame:CGRectMake(kPanelW - 40, kPanelH - 40, 40, 40)];
    self.resizingHandle.backgroundColor = [UIColor clearColor];
    [self.panelContainer addSubview:self.resizingHandle];
    
    CAShapeLayer *handleLayer = [CAShapeLayer layer];
    handleLayer.path = [UIBezierPath bezierPathWithArcCenter:CGPointMake(40, 40) radius:18 startAngle:M_PI endAngle:1.5 * M_PI clockwise:YES].CGPath;
    handleLayer.fillColor = [UIColor clearColor].CGColor;
    handleLayer.strokeColor = [[UIColor whiteColor] colorWithAlphaComponent:0.3].CGColor;
    handleLayer.lineWidth = 2.0;
    [self.resizingHandle.layer addSublayer:handleLayer];
    
    UIPanGestureRecognizer *resizePan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handleResize:)];
    [self.resizingHandle addGestureRecognizer:resizePan];

    UICollectionViewFlowLayout *layout = [[UICollectionViewFlowLayout alloc] init];
    layout.itemSize = CGSizeMake(80, 100);
    self.collectionView = [[UICollectionView alloc] initWithFrame:CGRectMake(0, 45, kPanelW, kPanelH-45) collectionViewLayout:layout];
    self.collectionView.dataSource = self; self.collectionView.delegate = self;
    self.collectionView.backgroundColor = [UIColor clearColor];
    [self.collectionView registerClass:[CV3AppCell class] forCellWithReuseIdentifier:@"C"];
    [self.appPanel.contentView addSubview:self.collectionView];
}

- (void)handlePanelDrag:(UIPanGestureRecognizer *)gesture {
    CGPoint location = [gesture locationInView:self.panelContainer];
    if (gesture.state == UIGestureRecognizerStateBegan) {
        if (location.y > 45.0) { gesture.enabled = NO; gesture.enabled = YES; return; }
        self.hasBeenMoved = YES;
        [UIView animateWithDuration:0.3 delay:0 usingSpringWithDamping:0.5 initialSpringVelocity:1.0 options:0 animations:^{
            self.panelContainer.transform = CGAffineTransformMakeScale(1.05, 1.05);
        } completion:nil];
    }
    
    CGPoint translation = [gesture translationInView:self.rootViewController.view];
    CGPoint newCenter = CGPointMake(self.panelContainer.center.x + translation.x, self.panelContainer.center.y + translation.y);
    
    UIEdgeInsets safe = self.safeAreaInsets;
    CGFloat halfW = self.panelContainer.frame.size.width / 2.0;
    CGFloat halfH = self.panelContainer.frame.size.height / 2.0;
    
    CGFloat minX = safe.left + 10.0 + halfW;
    CGFloat maxX = self.bounds.size.width - safe.right - 10.0 - halfW;
    CGFloat minY = safe.top + 10.0 + halfH;
    CGFloat maxY = self.bounds.size.height - safe.bottom - 10.0 - halfH;
    
    newCenter.x = MAX(minX, MIN(maxX, newCenter.x));
    newCenter.y = MAX(minY, MIN(maxY, newCenter.y));
    
    self.panelContainer.center = newCenter;
    [gesture setTranslation:CGPointZero inView:self.rootViewController.view];
    
    if (gesture.state == UIGestureRecognizerStateEnded || gesture.state == UIGestureRecognizerStateCancelled) {
        [UIView animateWithDuration:0.4 delay:0 usingSpringWithDamping:0.5 initialSpringVelocity:1.0 options:0 animations:^{
            self.panelContainer.transform = CGAffineTransformIdentity;
        } completion:nil];
    }
}

- (void)handleResize:(UIPanGestureRecognizer *)gesture {
    CGPoint translation = [gesture translationInView:self.panelContainer];
    CGRect f = self.panelContainer.frame;
    
    CGFloat newWidth = MAX(280, f.size.width + translation.x);
    CGFloat newHeight = MAX(350, f.size.height + translation.y);
    
    UIEdgeInsets safe = self.safeAreaInsets;
    CGFloat maxX = self.bounds.size.width - safe.right - 10.0;
    CGFloat maxY = self.bounds.size.height - safe.bottom - 10.0;
    
    if (f.origin.x + newWidth > maxX) newWidth = maxX - f.origin.x;
    if (f.origin.y + newHeight > maxY) newHeight = maxY - f.origin.y;
    
    f.size.width = newWidth;
    f.size.height = newHeight;
    self.panelContainer.frame = f;
    [gesture setTranslation:CGPointZero inView:self.panelContainer];
    
    self.appPanel.frame = self.panelContainer.bounds;
    self.collectionView.frame = CGRectMake(0, 45, f.size.width, f.size.height - 45);
    self.resizingHandle.frame = CGRectMake(f.size.width - 40, f.size.height - 40, 40, 40);
    self.specularHighlight.frame = self.appPanel.bounds;
    self.cyanLayer.frame = CGRectInset(self.appPanel.bounds, -0.3, -0.3);
    self.magentaLayer.frame = CGRectInset(self.appPanel.bounds, 0.3, 0.3);
    
    [self.collectionView.collectionViewLayout invalidateLayout];
}

- (void)handleTrafficLight:(UIButton *)sender {
    [self.feedback impactOccurred];
    if (sender.tag == 0 || sender.tag == 1) {
        [self animateSpotlight:NO fromPoint:self.panelContainer.center];
    } else if (sender.tag == 2) {
        [UIView animateWithDuration:0.6 delay:0 usingSpringWithDamping:0.7 initialSpringVelocity:1 options:0 animations:^{
            self.panelContainer.frame = CGRectMake(0, 0, kPanelW, kPanelH);
            self.panelContainer.center = CGPointMake(self.bounds.size.width/2, self.bounds.size.height/2);
            [self handleResize:nil];
        } completion:nil];
    }
}

- (void)layoutSubviews {
    [super layoutSubviews];
    
    // 获取安全区域
    UIEdgeInsets safe = self.safeAreaInsets;
    CGRect bounds = self.bounds;
    CGFloat w = bounds.size.width;
    CGFloat h = bounds.size.height;

    // 计算安全区域内的有效绘图区
    CGRect safeBounds = CGRectMake(safe.left, safe.top, 
                                   w - safe.left - safe.right, 
                                   h - safe.top - safe.bottom);

    // 1. 设置触发区域：根据目标方向动态调整 (解决横屏观察不到旋转的问题)
    self.edgeTriggerView.backgroundColor = [[UIColor redColor] colorWithAlphaComponent:0.5];
    UIInterfaceOrientation orientation = self.targetOrientation != UIInterfaceOrientationUnknown ? self.targetOrientation : UIInterfaceOrientationPortrait;
    
    switch (orientation) {
        case UIInterfaceOrientationLandscapeLeft:
            self.systemEdgePan.edges = UIRectEdgeTop;
            self.edgeTriggerView.frame = CGRectMake(0, 0, w, kTriggerVisualWidth);
            break;
        case UIInterfaceOrientationLandscapeRight:
            self.systemEdgePan.edges = UIRectEdgeBottom;
            self.edgeTriggerView.frame = CGRectMake(0, h - kTriggerVisualWidth, w, kTriggerVisualWidth);
            break;
        case UIInterfaceOrientationPortraitUpsideDown:
            self.systemEdgePan.edges = UIRectEdgeLeft;
            self.edgeTriggerView.frame = CGRectMake(0, safe.top, kTriggerVisualWidth, h - safe.top - kTriggerBottomOffset);
            break;
        case UIInterfaceOrientationPortrait:
        default:
            self.systemEdgePan.edges = UIRectEdgeRight;
            self.edgeTriggerView.frame = CGRectMake(w - kTriggerVisualWidth, safe.top, kTriggerVisualWidth, h - safe.top - kTriggerBottomOffset);
            break;
    }
    [self.rootViewController.view bringSubviewToFront:self.edgeTriggerView];
    
    CV3LogToFile(@"[Layout] CV3Window 宽度: %.1f, 高度: %.1f, 方向: %ld", w, h, (long)orientation);

    // 2. 面板容器：蓝色 (主要操作区域)
    self.panelContainer.backgroundColor = [[UIColor blueColor] colorWithAlphaComponent:0.2];
    if (!self.isAnimating && !self.hasBeenMoved) {
        self.panelContainer.center = CGPointMake(CGRectGetMidX(safeBounds), CGRectGetMidY(safeBounds));
    }

    // 3. 特效层：绿色 (贝塞尔曲线拉伸背景区域)
    self.bezierContainer.frame = safeBounds;
    self.bezierBlur.frame = self.bezierContainer.bounds;
    self.bezierContainer.backgroundColor = [[UIColor greenColor] colorWithAlphaComponent:0.15];
    
    // 4. 面板主体：黄色 (UIVisualEffectView 容器)
    self.appPanel.backgroundColor = [[UIColor yellowColor] colorWithAlphaComponent:0.2];

    // 5. 辅助视图：紫色 (交通灯) 与 青色 (缩放手柄)
    self.trafficCapsule.backgroundColor = [[UIColor purpleColor] colorWithAlphaComponent:0.4];
    self.resizingHandle.backgroundColor = [[UIColor cyanColor] colorWithAlphaComponent:0.4];

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

    // 锁定为右侧拉伸计算
    CGFloat stretch = -translation.x;

    if (gesture.state == UIGestureRecognizerStateBegan) {
        if (!self.isPanelShowing) {
            [self.feedback impactOccurred];
            [self.selectionFeedback prepare];
            self.lastHapticX = 0;
            self.bezierContainer.alpha = 1.0;
            self.dimmingView.alpha = 0; // 初始透明
            
            // 为贝塞尔层增加发光效果 (Glow)
            self.bezierLayer.shadowColor = [UIColor whiteColor].CGColor;
            self.bezierLayer.shadowOffset = CGSizeZero;
            self.bezierLayer.shadowRadius = 10.0;
            self.bezierLayer.shadowOpacity = 0.0;
        }
    } else if (gesture.state == UIGestureRecognizerStateChanged) {
        if (self.bezierContainer.alpha > 0) {
            // 恢复使用屏幕物理边缘作为贝塞尔曲线起点
            CGFloat edgeX = self.bounds.size.width;
            
            self.bezierLayer.path = [self pathForStretch:MAX(0, stretch) atPoint:location velocity:velocity edgeX:edgeX].CGPath;

            // 动态调整背景变暗程度与发光强度 (Progress: 0.0 -> 1.0)
            CGFloat progress = MIN(stretch / 45.0, 1.0);
            self.dimmingView.alpha = progress;
            self.bezierLayer.shadowOpacity = progress * 0.6;

            CGFloat currentInterval = MAX(10.0, 18.0 - (stretch / 45.0) * 8.0);
            if (fabs(stretch - self.lastHapticX) > currentInterval) {
                // 根据滑动速率动态调整震动强度
                CGFloat v = fabs(velocity.x);
                if (v > 800) {
                    [self.feedback impactOccurredWithIntensity:0.85];
                } else {
                    [self.selectionFeedback selectionChanged];
                }
                
                AudioServicesPlaySystemSound(1104); 
                self.lastHapticX = stretch;
            }

            if (stretch > 45) { 
                [self animateSpotlight:YES fromPoint:location]; 
                gesture.enabled = NO; gesture.enabled = YES; 
            }
        }
    } else if (gesture.state == UIGestureRecognizerStateEnded || gesture.state == UIGestureRecognizerStateCancelled) {
        if (self.bezierContainer.alpha > 0 && !self.isPanelShowing && velocity.x < -300 && gesture.state != UIGestureRecognizerStateCancelled) {
            [self animateSpotlight:YES fromPoint:location];
        }
        [UIView animateWithDuration:0.4 animations:^{ 
            self.bezierContainer.alpha = 0; 
            if (!self.isPanelShowing) self.dimmingView.alpha = 0;
        }];
    }
}


- (UIBezierPath *)pathForStretch:(CGFloat)stretch atPoint:(CGPoint)point velocity:(CGPoint)velocity edgeX:(CGFloat)edgeX {
    CGFloat s = MIN(stretch * 0.7, 95); 
    
    // 引入惯性形变 (Inertial Deformation)
    CGFloat xInertia = MIN(fabs(velocity.x) / 1000.0 * 15.0, 30.0);
    CGFloat yInertia = velocity.y / 1000.0 * 25.0;
    
    UIBezierPath *path = [UIBezierPath bezierPath];
    
    CGFloat topY = point.y - 130 + yInertia;
    CGFloat bottomY = point.y + 130 + yInertia;
    CGFloat peakX = edgeX - s - xInertia;
    
    [path moveToPoint:CGPointMake(edgeX, topY)];
    [path addCurveToPoint:CGPointMake(peakX, point.y + yInertia) 
            controlPoint1:CGPointMake(edgeX, point.y - 65 + yInertia) 
            controlPoint2:CGPointMake(peakX, point.y - 45 + yInertia)];
    [path addCurveToPoint:CGPointMake(edgeX, bottomY) 
            controlPoint1:CGPointMake(peakX, point.y + 45 + yInertia) 
            controlPoint2:CGPointMake(edgeX, point.y + 65 + yInertia)];
    [path closePath];
    return path;
}

- (void)updateTrafficLightsFocus:(BOOL)active {
    NSArray *tc = @[[UIColor colorWithRed:1.00 green:0.37 blue:0.33 alpha:1.0], [UIColor colorWithRed:1.00 green:0.75 blue:0.18 alpha:1.0], [UIColor colorWithRed:0.15 green:0.79 blue:0.25 alpha:1.0]];
    UIColor *gray = [[UIColor whiteColor] colorWithAlphaComponent:0.2];
    
    [UIView animateWithDuration:0.3 animations:^{
        for (int i = 0; i < self.trafficDots.count; i++) {
            self.trafficDots[i].backgroundColor = active ? tc[i] : gray;
        }
    }];
}

- (void)animateSpotlight:(BOOL)visible fromPoint:(CGPoint)point {
    if (self.isAnimating) return;
    self.isPanelShowing = visible; self.isAnimating = YES;
    if (visible) {
        [self loadAppsAsync];
        [self updateTrafficLightsFocus:YES];
        self.panelContainer.hidden = NO; self.panelContainer.center = point;
        self.panelContainer.transform = CGAffineTransformScale(CGAffineTransformIdentity, 0.01, 0.01);
        [UIView animateWithDuration:0.6 delay:0 usingSpringWithDamping:0.7 initialSpringVelocity:1 options:0 animations:^{
            self.dimmingView.alpha = 1.0;
            self.panelContainer.center = CGPointMake(self.bounds.size.width/2, self.bounds.size.height/2);
            self.panelContainer.transform = CGAffineTransformIdentity;
            self.panelContainer.alpha = 1;
        } completion:^(BOOL f){ self.isAnimating = NO; [self startLiquidMotion]; }];
    } else {
        [self updateTrafficLightsFocus:NO];
        [self stopLiquidMotion];
        [UIView animateWithDuration:0.5 delay:0 usingSpringWithDamping:0.85 initialSpringVelocity:0.5 options:UIViewAnimationOptionCurveEaseInOut animations:^{ 
            self.dimmingView.alpha = 0;
            self.panelContainer.alpha = 0; 
            self.panelContainer.transform = CGAffineTransformScale(CGAffineTransformIdentity, 0.001, 0.001);
        } completion:^(BOOL f){ self.isAnimating = NO; self.panelContainer.hidden = YES; }];
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
    [self.motionManager startDeviceMotionUpdatesToQueue:[NSOperationQueue mainQueue] withHandler:^(CMDeviceMotion *m, NSError *e) {
        if (!m) return;
        [CATransaction begin]; [CATransaction setDisableActions:YES];
        
        self.specularHighlight.startPoint = CGPointMake(0.5 - m.attitude.roll*1.5, 0.5 - m.attitude.pitch*1.5);
        self.specularHighlight.endPoint = CGPointMake(1.5 - m.attitude.roll*1.5, 1.5 - m.attitude.pitch*1.5);
        
        CGFloat dx = m.attitude.roll * 1.2;
        CGFloat dy = m.attitude.pitch * 1.2;
        self.cyanLayer.transform = CATransform3DMakeTranslation(-dx, -dy, 0);
        self.magentaLayer.transform = CATransform3DMakeTranslation(dx, dy, 0);
        
        [CATransaction commit];
    }];
}
- (void)stopLiquidMotion { [self.motionManager stopDeviceMotionUpdates]; }

- (void)loadAppsAsync {
    dispatch_async(dispatch_get_global_queue(0,0), ^{
        NSMutableArray *temp = [NSMutableArray array];
        id ws = [NSClassFromString(@"LSApplicationWorkspace") defaultWorkspace];
        for (id p in [ws performSelector:@selector(allInstalledApplications)]) {
            NSString *bundleId = [p performSelector:@selector(bundleIdentifier)];
            NSString *name = [p performSelector:@selector(localizedName)];
            
            CV3AppInfo *info = [[CV3AppInfo alloc] init];
            info.name = name;
            info.bundleId = bundleId;
            
            UIImage *cachedIcon = [cv3IconCache objectForKey:bundleId];
            if (cachedIcon) {
                info.icon = cachedIcon;
            } else {
                info.icon = [UIImage _applicationIconImageForBundleIdentifier:bundleId format:10 scale:[UIScreen mainScreen].scale];
                if (info.icon) [cv3IconCache setObject:info.icon forKey:bundleId];
            }

            if (info.name && info.bundleId) [temp addObject:info];
        }
        dispatch_async(dispatch_get_main_queue(), ^{ self.apps = temp; [self.collectionView reloadData]; [self.collectionView layoutIfNeeded]; [self animateIconsStaggered]; });
    });
}

- (void)handleMemoryWarning {
    [cv3IconCache removeAllObjects];
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
}

- (void)keyboardWillHide:(NSNotification *)notification {
    self.isKeyboardVisible = NO;
}

- (void)monitorState {
    @try {
        [self attachToCurrentActiveScene];
        
        NSMutableString *winMap = [NSMutableString stringWithFormat:@"\n    [Hierarchy Map]"];
        
        NSArray *windows = nil;
        UIApplication *app = [UIApplication sharedApplication];
        if ([app respondsToSelector:@selector(allWindowsIncludingInternalWindows:)]) {
            windows = [app performSelector:@selector(allWindowsIncludingInternalWindows:) withObject:@YES];
        } else {
            windows = app.windows;
        }
        
        for (UIWindow *win in windows) {
            if (!win) continue;
            [winMap appendFormat:@"\n    - [%@]: Lvl=%.1f, Alpha=%.2f, Hidden=%d, Scene=%p", 
                NSStringFromClass([win class]), win.windowLevel, win.alpha, win.hidden, win.windowScene];
        }
    } @catch (NSException *e) {
    }
}

- (BOOL)_shouldAutorotateToInterfaceOrientation:(long long)orientation { return NO; }

- (void)attachToCurrentActiveScene {
    // 异步获取方向并分发，确保不在敏感的系统转换周期内执行同步 UI 操作
    dispatch_async(dispatch_get_main_queue(), ^{
        UIInterfaceOrientation orientation = UIInterfaceOrientationPortrait;
        Class workspaceClass = NSClassFromString(@"SBMainWorkspace");
        if (workspaceClass && [workspaceClass respondsToSelector:@selector(sharedInstance)]) {
            id workspace = [workspaceClass performSelector:@selector(sharedInstance)];
            if (workspace && [workspace respondsToSelector:@selector(activeInterfaceOrientation)]) {
                orientation = (UIInterfaceOrientation)[workspace activeInterfaceOrientation];
            }
        }
        [self attachToCurrentActiveSceneWithOrientation:orientation];
    });
}

- (void)attachToCurrentActiveSceneWithOrientation:(UIInterfaceOrientation)orientation {
    // 记录目标方向，供 layoutSubviews 使用
    self.targetOrientation = orientation;
    
    // 增加内部保护，防止异步任务堆叠
    static BOOL isProcessing = NO;
    if (isProcessing) return;
    isProcessing = YES;

    dispatch_async(dispatch_get_main_queue(), ^{
        @try {
            UIWindowScene *targetScene = nil;
            if ([NSClassFromString(@"SBWindowScene") respondsToSelector:@selector(mainDisplayWindowScene)]) {
                targetScene = [NSClassFromString(@"SBWindowScene") performSelector:@selector(mainDisplayWindowScene)];
            }
            
            if (!targetScene) {
                for (UIScene *scene in [[UIApplication sharedApplication].connectedScenes allObjects]) {
                    if ([scene isKindOfClass:[UIWindowScene class]]) {
                        NSString *role = scene.session.role;
                        if ([role isEqualToString:@"SBWindowSceneSessionRoleSystemAperture"] ||
                            [role isEqualToString:@"SBWindowSceneSessionRoleSystemApertureCurtain"] ||
                            [role isEqualToString:@"UISceneSessionRolePlaceholder"]) continue;
                        
                        if (scene.activationState == UISceneActivationStateForegroundActive || 
                            [role isEqualToString:@"SBWindowSceneSessionRoleHomeScreen"] ||
                            [role isEqualToString:@"UIWindowSceneSessionRoleApplication"]) {
                            targetScene = (UIWindowScene *)scene;
                        }
                    }
                }
            }

            if (targetScene) {
                if (self.windowScene != targetScene) self.windowScene = targetScene;
                self.hidden = NO; 
                [self applyAdaptiveLevel];
                
                // 使用 UIScreen 完整 bounds，并根据当前 Scene 自动同步旋转
                CGRect screenBounds = [UIScreen mainScreen].bounds;
                self.frame = screenBounds;

                [self setNeedsLayout];
            }
        } @catch (NSException *e) {}
        isProcessing = NO;
    });
}

- (void)applyAdaptiveLevel {
    // 锁定在控制中心下方，但在所有 App 之上
    // UIWindowLevelStatusBar 是 1000，2099 通常足以覆盖所有三方 App
    CGFloat targetLevel = 2099.0; 
    
    if (self.windowLevel != targetLevel) {
        self.windowLevel = targetLevel;
    }
}

- (NSInteger)collectionView:(id)c numberOfItemsInSection:(NSInteger)s { return self.apps.count; }
- (id)collectionView:(id)c cellForItemAtIndexPath:(id)i {
    CV3AppCell *cell = [c dequeueReusableCellWithReuseIdentifier:@"C" forIndexPath:i];
    [cell configureWithInfo:self.apps[[(NSIndexPath *)i item]]];
    return cell;
}

- (BOOL)_canBecomeKeyWindow { return NO; }
- (BOOL)_ignoresHitTest { return NO; }
- (BOOL)_shouldIsolate { return YES; }

// --- 尝试绕过 App 级触控黑洞的私有方法 ---
- (BOOL)_isSecure { return YES; }
- (BOOL)_isWindowServerHostingManaged { return YES; }
- (BOOL)_wantsSceneAssociation { return YES; }

- (UIView *)hitTest:(CGPoint)point withEvent:(id)e {
    if (self.isPanelShowing) {
        CGPoint p = [self convertPoint:point toView:self.panelContainer];
        if (CGRectContainsPoint(self.panelContainer.bounds, p)) {
            return [self.panelContainer hitTest:p withEvent:e];
        }
        return nil;
    }
    
    // 拦截热区：根据当前方向动态判断边缘
    UIInterfaceOrientation orientation = self.targetOrientation != UIInterfaceOrientationUnknown ? self.targetOrientation : UIInterfaceOrientationPortrait;
    BOOL inHotzone = NO;
    
    CGFloat w = self.bounds.size.width;
    CGFloat h = self.bounds.size.height;
    UIEdgeInsets safe = self.safeAreaInsets;

    switch (orientation) {
        case UIInterfaceOrientationLandscapeLeft:
            if (point.y <= kTriggerHotzoneWidth) inHotzone = YES;
            break;
        case UIInterfaceOrientationLandscapeRight:
            if (point.y >= h - kTriggerHotzoneWidth) inHotzone = YES;
            break;
        case UIInterfaceOrientationPortraitUpsideDown:
            if (point.x <= kTriggerHotzoneWidth) inHotzone = YES;
            break;
        case UIInterfaceOrientationPortrait:
        default:
            if (point.x >= w - kTriggerHotzoneWidth) inHotzone = YES;
            break;
    }

    if (inHotzone) {
        // 复用键盘避让逻辑 (仅在竖屏或有意义时)
        if (self.isKeyboardVisible) {
            CGFloat yThreshold = h * 0.4;
            if (point.y > yThreshold) return nil;
        }
        
        // 避开安全区域触发 (对于左右边缘，检查 Y 轴；对于上下边缘，检查 X 轴)
        if (orientation == UIInterfaceOrientationPortrait || orientation == UIInterfaceOrientationPortraitUpsideDown) {
            if (point.y < safe.top || point.y > (h - safe.bottom)) return nil;
        } else {
            if (point.x < safe.left || point.x > (w - safe.right)) return nil;
        }

        return self;
    }
    
    return nil;
}
@end

%hook UIWindow
- (void)layoutSubviews {
    %orig;

    // 增加递归保护：如果是 CV3Window 自身的 layoutSubviews，或者已经在处理中，则跳过
    static BOOL isUpdating = NO;
    if (isUpdating || (sharedWindow && self == sharedWindow)) return;

    // 仅监控处于前台且已激活的窗口场景
    if (self.windowScene && self.windowScene.activationState == UISceneActivationStateForegroundActive) {
        static UIInterfaceOrientation globalLastConfirmedOrientation = UIInterfaceOrientationUnknown;
        static NSTimeInterval lastLogTime = 0;
        
        UIInterfaceOrientation currentOrientation = self.windowScene.interfaceOrientation;
        NSTimeInterval currentTime = [[NSDate date] timeIntervalSince1970];

        if (currentOrientation != globalLastConfirmedOrientation && 
            currentOrientation != UIInterfaceOrientationUnknown &&
            (currentTime - lastLogTime > 0.5)) { // 缩短防抖到 0.5s 提高响应速度
            
            globalLastConfirmedOrientation = currentOrientation;
            lastLogTime = currentTime;
            
            isUpdating = YES;
            switch (currentOrientation) {
                case UIInterfaceOrientationPortrait:
                    CV3LogToFile(@"界面直立");
                    if (sharedWindow) [sharedWindow attachToCurrentActiveSceneWithOrientation:currentOrientation];
                    break;
                case UIInterfaceOrientationPortraitUpsideDown:
                    CV3LogToFile(@"界面直立，上下颠倒");
                    if (sharedWindow) [sharedWindow attachToCurrentActiveSceneWithOrientation:currentOrientation];
                    break;
                case UIInterfaceOrientationLandscapeLeft:
                    CV3LogToFile(@"界面朝左");
                    if (sharedWindow) [sharedWindow attachToCurrentActiveSceneWithOrientation:currentOrientation];
                    break;
                case UIInterfaceOrientationLandscapeRight:
                    CV3LogToFile(@"界面朝右");
                    if (sharedWindow) [sharedWindow attachToCurrentActiveSceneWithOrientation:currentOrientation];
                    break;
                default:
                    break;
            }
            isUpdating = NO;
        }
    }
}
%end

%hook SBMainWorkspace
- (void)workspace:(id)arg1 didExecuteTransitionRequest:(id)arg2 {
    %orig;
    if (sharedWindow) [sharedWindow attachToCurrentActiveScene];
}
%end

%hook SBLockScreenManager
- (void)lockScreenViewControllerDidPresent {
    %orig;
    if (sharedWindow) sharedWindow.hidden = YES;
}
- (void)lockScreenViewControllerDidDismiss {
    %orig;
    if (sharedWindow) sharedWindow.hidden = NO;
}
%end

%hook SpringBoard
- (void)applicationDidFinishLaunching:(id)application {
    %orig;


    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (sharedWindow) return;
        sharedWindow = [[CV3Window alloc] initWithFrame:[UIScreen mainScreen].bounds];
        sharedWindow.hidden = NO;
        sharedWindow.alpha = 1.0;
        [sharedWindow show];
    });
}
%end
