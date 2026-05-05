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

@interface SpringBoard : UIApplication
- (BOOL)_accessibilityLaunchAppWithBundleID:(id)arg1;
@end

@interface SBMainWorkspace : NSObject
+ (id)sharedInstance;
- (UIInterfaceOrientation)activeInterfaceOrientation;
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

@interface UIImage (Private)
+ (UIImage *)_applicationIconImageForBundleIdentifier:(NSString *)bundleIdentifier format:(int)format scale:(CGFloat)scale;
@end

// --- Data Model ---
@interface CV3AppInfo : NSObject
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSString *bundleId;
@property (nonatomic, strong) UIImage *icon;
@property (nonatomic, strong) id sbIcon; 
@property (nonatomic, copy) NSString *pinyinInitial; // 存储名称的拼音首字母
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

// --- Custom Cell ---
@interface CV3AppCell : UICollectionViewCell
@property (nonatomic, strong) UIImageView *iconView;
@property (nonatomic, strong) UILabel *nameLabel;
- (void)configureWithInfo:(CV3AppInfo *)info searchText:(NSString *)searchText;
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
- (void)configureWithInfo:(CV3AppInfo *)info searchText:(NSString *)searchText {
    self.iconView.image = info.icon;
    
    if (searchText && searchText.length > 0) {
        NSMutableAttributedString *as = [[NSMutableAttributedString alloc] initWithString:info.name attributes:@{NSForegroundColorAttributeName: [[UIColor whiteColor] colorWithAlphaComponent:0.9]}];
        NSRange range = [info.name rangeOfString:searchText options:NSCaseInsensitiveSearch];
        if (range.location != NSNotFound) {
            // 高亮颜色：使用与绿色交通灯一致的绿色
            [as addAttribute:NSForegroundColorAttributeName value:[UIColor colorWithRed:0.15 green:0.79 blue:0.25 alpha:1.0] range:range];
            [as addAttribute:NSFontAttributeName value:[UIFont systemFontOfSize:10.0 weight:UIFontWeightBold] range:range];
        }
        self.nameLabel.attributedText = as;
    } else {
        self.nameLabel.attributedText = nil;
        self.nameLabel.text = info.name;
        self.nameLabel.textColor = [[UIColor whiteColor] colorWithAlphaComponent:0.9];
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
@interface CV3Window : UIWindow <UIGestureRecognizerDelegate, UICollectionViewDataSource, UICollectionViewDelegate, UITextFieldDelegate>
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
@property (nonatomic, assign) BOOL isProcessing; 
@property (nonatomic, assign) BOOL launchDebounce;
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
@property (nonatomic, strong) UITextField *searchField;
@property (nonatomic, strong) NSMutableArray<CV3AppInfo *> *filteredApps;
@property (nonatomic, strong) UILabel *noResultsLabel;
@property (nonatomic, assign) CGFloat lastHapticX;
@property (nonatomic, strong) UIScreenEdgePanGestureRecognizer *systemEdgePan;
@property (nonatomic, assign) UIInterfaceOrientation targetOrientation;
@property (nonatomic, assign) CGPoint lastTriggerPoint;

- (void)show;
- (void)loadAppsAsync;
- (NSString *)_role; 
@end

static NSCache *cv3IconCache = nil; 
static CV3Window *sharedWindow = nil;

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
        if (sharedWindow && sharedWindow.isPanelShowing) {
            [sharedWindow loadAppsAsync];
        }
    });
}

- (void)applicationsDidUninstall:(NSArray *)applications {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (sharedWindow && sharedWindow.isPanelShowing) {
            [sharedWindow loadAppsAsync];
        }
    });
}
@end

// --- Layout Constants ---
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
    .trafficDotSize = 8.0
};


// --- Quick Access View (Keyboard Accessory) ---
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

- (void)handleDoubleTap:(UITapGestureRecognizer *)gesture {
    [self.feedback impactOccurred];
    [self.searchField becomeFirstResponder];
}

- (void)handlePanelTap:(UITapGestureRecognizer *)gesture {
    // 单击暂不处理
}

// 统一 App 启动逻辑
- (void)launchApp:(CV3AppInfo *)info {
    if (self.launchDebounce) return;
    self.launchDebounce = YES;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.4 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        self.launchDebounce = NO;
    });

    [self.feedback impactOccurred];
    if (info.bundleId) {
        NSString *bid = [info.bundleId copy];
        
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
        [self animateSpotlight:NO fromPoint:self.panelContainer.center];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.05 * NSEC_PER_SEC)), dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
            [[NSClassFromString(@"LSApplicationWorkspace") defaultWorkspace] openApplicationWithBundleID:bid];
        });
    }
}

- (void)filterApps {
    NSString *text = [self.searchField.text lowercaseString];
    if (!text || text.length == 0) {
        self.filteredApps = [self.apps mutableCopy];
        
        // 智能辅助：输入为空时，在键盘上方显示 Top 5 常用应用
        if (!self.searchField.inputAccessoryView && self.apps.count > 0) {
            NSArray *topApps = [self.apps subarrayWithRange:NSMakeRange(0, MIN(5, self.apps.count))];
            __weak typeof(self) weakSelf = self;
            self.searchField.inputAccessoryView = [[CV3QuickAccessView alloc] initWithApps:topApps selectionHandler:^(CV3AppInfo *appInfo) {
                [weakSelf launchApp:appInfo];
            }];
            [self.searchField reloadInputViews];
        }
    } else {
        self.searchField.inputAccessoryView = nil;
        [self.searchField reloadInputViews];

        NSMutableArray *res = [NSMutableArray array];
        for (CV3AppInfo *info in self.apps) {
            if ([info.name rangeOfString:text options:NSCaseInsensitiveSearch].location != NSNotFound ||
                [info.bundleId rangeOfString:text options:NSCaseInsensitiveSearch].location != NSNotFound ||
                (info.pinyinInitial && [info.pinyinInitial rangeOfString:text].location != NSNotFound)) {
                [res addObject:info];
            }
        }
        self.filteredApps = res;
    }
    self.noResultsLabel.hidden = (self.filteredApps.count > 0);
    [self.collectionView reloadData];
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
        [UIView animateWithDuration:0.5 delay:0 options:UIViewAnimationOptionAutoreverse | UIViewAnimationOptionRepeat | UIViewAnimationOptionAllowUserInteraction animations:^{
            container.layer.shadowColor = [UIColor whiteColor].CGColor;
            container.layer.shadowOffset = CGSizeZero;
            container.layer.shadowOpacity = 0.4;
            container.layer.shadowRadius = 8.0;
            container.layer.borderColor = [[UIColor whiteColor] colorWithAlphaComponent:0.4].CGColor;
            container.transform = CGAffineTransformMakeScale(1.02, 1.02);
        } completion:nil];
    }
}

- (void)textFieldDidEndEditing:(UITextField *)textField {
    if (textField == self.searchField) {
        UIView *container = textField.superview;
        [container.layer removeAllAnimations];
        [UIView animateWithDuration:0.3 animations:^{
            container.layer.shadowOpacity = 0;
            container.layer.shadowRadius = 0;
            container.layer.borderColor = [[UIColor whiteColor] colorWithAlphaComponent:0.1].CGColor;
            container.transform = CGAffineTransformIdentity;
        }];
    }
}

- (void)collectionView:(UICollectionView *)cv didSelectItemAtIndexPath:(NSIndexPath *)indexPath {
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

- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)gesture {
    if (gesture == self.systemEdgePan) {
        UIInterfaceOrientation orientation = self.targetOrientation != UIInterfaceOrientationUnknown ? self.targetOrientation : UIInterfaceOrientationPortrait;
        CGFloat w = self.bounds.size.width;
        CGFloat h = self.bounds.size.height;
        UIEdgeInsets safe = self.safeAreaInsets;
        
        // 键盘可见时限制区域
        if (self.isKeyboardVisible) {
            CGPoint pInWindow = [gesture locationInView:nil];
            CGFloat yThreshold = h * 0.4;
            if (pInWindow.y > yThreshold) return NO;
        }
        
        // 限制在安全区域范围内触发
        CGPoint p = [gesture locationInView:self];
        if (orientation == UIInterfaceOrientationPortrait || orientation == UIInterfaceOrientationPortraitUpsideDown) {
            if (p.y < safe.top || p.y > (h - safe.bottom)) {
                CV3LogToFile(@"[Debug] Gesture 被拒绝: 竖屏安全区域限制 (y=%f)", p.y);
                return NO;
            }
        } else {
            if (p.x < safe.left || p.x > (w - safe.right)) {
                CV3LogToFile(@"[Debug] Gesture 被拒绝: 横屏安全区域限制 (x=%f)", p.x);
                return NO;
            }
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

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)otherGestureRecognizer {    // 禁止拖拽手势与调整大小手势同时发生
    if (([gestureRecognizer.view isKindOfClass:[NSClassFromString(@"UIPanGestureRecognizer") class]] && otherGestureRecognizer.view == self.resizingHandle) ||
        (gestureRecognizer.view == self.resizingHandle && [otherGestureRecognizer.view isKindOfClass:[NSClassFromString(@"UIPanGestureRecognizer") class]])) {
        return NO;
    }
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
    self.edgeTriggerView.backgroundColor = [[UIColor redColor] colorWithAlphaComponent:0.5]; // 调试可见
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
    self.bezierLayer.fillColor = [UIColor whiteColor].CGColor;
    self.bezierBlur.layer.mask = self.bezierLayer; 
    
    self.panelContainer = [[UIView alloc] initWithFrame:CGRectMake(0, 0, kChevronLayoutConstants.panelW, kChevronLayoutConstants.panelH)];
    self.panelContainer.backgroundColor = [[UIColor blueColor] colorWithAlphaComponent:0.0]; // 调试可见，现在设为透明
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

    // 单击手势：维持原有潜在功能（或留作扩展）
    UITapGestureRecognizer *panTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handlePanelTap:)];
    panTap.delegate = self;
    [self.panelContainer addGestureRecognizer:panTap];

    // 添加双击手势用于快速激活搜索
    UITapGestureRecognizer *doubleTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleDoubleTap:)];
    doubleTap.numberOfTapsRequired = 2;
    doubleTap.delegate = self;
    [self.panelContainer addGestureRecognizer:doubleTap];
    [panTap requireGestureRecognizerToFail:doubleTap]; // 确保单击与双击不冲突

    self.appPanel = [[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemUltraThinMaterial]];    self.appPanel.frame = self.panelContainer.bounds;
    self.appPanel.backgroundColor = [[UIColor clearColor] colorWithAlphaComponent:0.0]; // 移除黄色测试色
    self.appPanel.layer.cornerRadius = kChevronLayoutConstants.cornerRadius;
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
    dispersion.layer.cornerRadius = kChevronLayoutConstants.cornerRadius;
    dispersion.layer.masksToBounds = YES;
    dispersion.userInteractionEnabled = NO;
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
        [dotBtn addTarget:self action:@selector(handleTrafficLight:) forControlEvents:UIControlEventTouchUpInside];
        [self.trafficCapsule addSubview:dotBtn];
        [dots addObject:visualDot]; // 存储视觉圆点用于颜色更新
    }
    self.trafficDots = dots;

    // --- Search Bar Setup ---
    UIView *searchContainer = [[UIView alloc] initWithFrame:CGRectMake(15, 50, kChevronLayoutConstants.panelW - 30, 36)];
    searchContainer.backgroundColor = [[UIColor whiteColor] colorWithAlphaComponent:0.06];
    searchContainer.layer.cornerRadius = 10;
    searchContainer.layer.borderWidth = 0.4;
    searchContainer.layer.borderColor = [[UIColor whiteColor] colorWithAlphaComponent:0.1].CGColor;
    [self.appPanel.contentView addSubview:searchContainer];
    
    self.searchField = [[UITextField alloc] initWithFrame:CGRectInset(searchContainer.bounds, 10, 0)];
    self.searchField.placeholder = @"搜索应用...";
    self.searchField.textColor = [UIColor whiteColor];
    self.searchField.font = [UIFont systemFontOfSize:14];
    self.searchField.tintColor = [UIColor whiteColor];
    // 设置占位符颜色
    self.searchField.attributedPlaceholder = [[NSAttributedString alloc] initWithString:@"搜索应用..." attributes:@{NSForegroundColorAttributeName: [[UIColor whiteColor] colorWithAlphaComponent:0.4]}];
    [self.searchField addTarget:self action:@selector(searchTextChanged:) forControlEvents:UIControlEventEditingChanged];
    self.searchField.delegate = self;
    self.searchField.returnKeyType = UIReturnKeySearch;
    self.searchField.clearButtonMode = UITextFieldViewModeWhileEditing; // 启用清空按钮
    [searchContainer addSubview:self.searchField];

    // --- No Results Label Setup ---
    self.noResultsLabel = [[UILabel alloc] initWithFrame:CGRectMake(0, 150, kChevronLayoutConstants.panelW, 40)];
    self.noResultsLabel.text = @"未找到相关应用";
    self.noResultsLabel.textColor = [[UIColor whiteColor] colorWithAlphaComponent:0.4];
    self.noResultsLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightMedium];
    self.noResultsLabel.textAlignment = NSTextAlignmentCenter;
    self.noResultsLabel.hidden = YES;
    [self.appPanel.contentView addSubview:self.noResultsLabel];

    self.resizingHandle = [[UIView alloc] initWithFrame:CGRectMake(kChevronLayoutConstants.panelW - 40, kChevronLayoutConstants.panelH - 40, 40, 40)];
    self.resizingHandle.backgroundColor = [UIColor clearColor];
    [self.panelContainer addSubview:self.resizingHandle];
    
    CAShapeLayer *handleLayer = [CAShapeLayer layer];
    // 改为朝向右下角（面板圆角处），使用 0 到 M_PI_2 的圆弧
    handleLayer.path = [UIBezierPath bezierPathWithArcCenter:CGPointMake(0, 0) radius:18 startAngle:0 endAngle:M_PI_2 clockwise:YES].CGPath;
    handleLayer.fillColor = [UIColor clearColor].CGColor;
    handleLayer.strokeColor = [[UIColor whiteColor] colorWithAlphaComponent:0.3].CGColor;
    handleLayer.lineWidth = 2.0;
    [self.resizingHandle.layer addSublayer:handleLayer];
    
    UIPanGestureRecognizer *resizePan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handleResize:)];
    resizePan.delegate = self;
    [self.resizingHandle addGestureRecognizer:resizePan];

    UICollectionViewFlowLayout *layout = [[UICollectionViewFlowLayout alloc] init];
    layout.itemSize = CGSizeMake(80, 100);
    layout.minimumInteritemSpacing = 5.0;
    layout.minimumLineSpacing = 10.0;
    // 调整 CollectionView 的 y 起点以避开搜索框 (从 45 移至 96)
    self.collectionView = [[UICollectionView alloc] initWithFrame:CGRectMake(0, 96, kChevronLayoutConstants.panelW, kChevronLayoutConstants.panelH-96) collectionViewLayout:layout];
    self.collectionView.dataSource = self; self.collectionView.delegate = self;
    self.collectionView.backgroundColor = [UIColor clearColor];
    [self.collectionView registerClass:[CV3AppCell class] forCellWithReuseIdentifier:@"C"];
    [self.appPanel.contentView addSubview:self.collectionView];

}

- (void)handlePanelDrag:(UIPanGestureRecognizer *)gesture {
    CGPoint location = [gesture locationInView:self.panelContainer];
    if (gesture.state == UIGestureRecognizerStateBegan) {
        if (location.y > 45.0) { return; }
        self.hasBeenMoved = YES;
        [UIView animateWithDuration:0.3 delay:0 usingSpringWithDamping:0.5 initialSpringVelocity:1.0 options:0 animations:^{
            // 保留当前的旋转状态（transform）只进行缩放
            CGAffineTransform currentTransform = self.panelContainer.transform;
            self.panelContainer.transform = CGAffineTransformScale(currentTransform, 1.05, 1.05);
        } completion:nil];
    }
    
    // 使用 superview 坐标系以确保与父容器内的绝对位置一致
    CGPoint translation = [gesture translationInView:self.panelContainer.superview];
    CGPoint newCenter = CGPointMake(self.panelContainer.center.x + translation.x, self.panelContainer.center.y + translation.y);
    
    // 使用物理屏幕边界进行约束，允许超出安全区域
    CGRect bounds = self.bounds;
    
    // 获取面板在旋转变换前的 bounds
    CGRect panelBounds = self.panelContainer.bounds;
    CGFloat halfW = (panelBounds.size.width * 1.05) / 2.0;
    CGFloat halfH = (panelBounds.size.height * 1.05) / 2.0;
    
    // 物理屏幕边缘钳位：允许部分拖出，但必须保留面板的一定可视部分 (这里预留 halfW/halfH，即面板中心不会出屏幕)
    newCenter.x = MAX(halfW - panelBounds.size.width * 0.4, MIN(bounds.size.width - halfW + panelBounds.size.width * 0.4, newCenter.x));
    newCenter.y = MAX(halfH - panelBounds.size.height * 0.4, MIN(bounds.size.height - halfH + panelBounds.size.height * 0.4, newCenter.y));
    
    self.panelContainer.center = newCenter;
    [gesture setTranslation:CGPointZero inView:self.panelContainer.superview];
    
    if (gesture.state == UIGestureRecognizerStateEnded || gesture.state == UIGestureRecognizerStateCancelled) {
        // 恢复原始缩放，但不重置 transform（保留旋转）
        CGAffineTransform current = self.panelContainer.transform;
        [UIView animateWithDuration:0.4 delay:0 usingSpringWithDamping:0.5 initialSpringVelocity:1.0 options:0 animations:^{
            self.panelContainer.transform = CGAffineTransformScale(current, 1/1.05, 1/1.05);
            
            // 自动回弹检测
            CGRect b = self.bounds;
            CGRect pb = self.panelContainer.bounds;
            CGFloat hW = pb.size.width * 0.4;
            CGFloat hH = pb.size.height * 0.4;
            
            CGPoint currentCenter = self.panelContainer.center;
            CGPoint targetCenter = currentCenter;
            
            targetCenter.x = MAX(hW, MIN(b.size.width - hW, targetCenter.x));
            targetCenter.y = MAX(hH, MIN(b.size.height - hH, targetCenter.y));
            
            self.panelContainer.center = targetCenter;
        } completion:nil];
    }
}

- (void)handleDimmingTap:(UITapGestureRecognizer *)tap {
    [self animateSpotlight:NO fromPoint:self.panelContainer.center];
}

- (void)handleResize:(UIPanGestureRecognizer *)gesture {
    // 增加 resize 锁
    self.isProcessing = YES; 

    static CGRect lastValidBounds;
    if (gesture && gesture.state == UIGestureRecognizerStateBegan) {
        lastValidBounds = self.panelContainer.bounds;
    }

    CGRect f = self.panelContainer.bounds;

    if (gesture) {
        CGPoint translation = [gesture translationInView:self.panelContainer];
        CGFloat newWidth = MAX(280, f.size.width + translation.x);
        CGFloat newHeight = MAX(350, f.size.height + translation.y);

        // 计算新的边界框在根视图中的尺寸和位置
        CGRect newBounds = CGRectMake(0, 0, newWidth, newHeight);
        CGSize newSizeInRoot = CGRectApplyAffineTransform(newBounds, self.panelContainer.transform).size;
        CGRect newFrameInRoot = CGRectMake(self.panelContainer.center.x - newSizeInRoot.width / 2.0,
                                           self.panelContainer.center.y - newSizeInRoot.height / 2.0,
                                           newSizeInRoot.width,
                                           newSizeInRoot.height);

        CGFloat screenW = self.bounds.size.width;
        CGFloat screenH = self.bounds.size.height;

        // 检查是否越界
        if (CGRectGetMaxX(newFrameInRoot) > screenW || CGRectGetMaxY(newFrameInRoot) > screenH || CGRectGetMinX(newFrameInRoot) < 0 || CGRectGetMinY(newFrameInRoot) < 0) {
            // 若越界，强制回退至上一次合法尺寸
            newWidth = lastValidBounds.size.width;
            newHeight = lastValidBounds.size.height;
        } else {
            // 更新缓存
            lastValidBounds = CGRectMake(0, 0, newWidth, newHeight);
        }

        f.size.width = newWidth;
        f.size.height = newHeight;
        self.panelContainer.bounds = f;
        [gesture setTranslation:CGPointZero inView:self.panelContainer];
    }

    self.appPanel.frame = self.panelContainer.bounds;
    
    // 动态调整搜索框和 CollectionView
    UIView *searchContainer = self.searchField.superview;
    searchContainer.frame = CGRectMake(15, 50, f.size.width - 30, 36);
    self.searchField.frame = CGRectInset(searchContainer.bounds, 10, 0);
    self.collectionView.frame = CGRectMake(0, 96, f.size.width, f.size.height - 96);
    self.noResultsLabel.frame = CGRectMake(0, 150, f.size.width, 40);

    [self updateResizingHandleFrame];
    self.specularHighlight.frame = self.appPanel.bounds;
    self.cyanLayer.frame = CGRectInset(self.appPanel.bounds, -0.3, -0.3);
    self.magentaLayer.frame = CGRectInset(self.appPanel.bounds, 0.3, 0.3);
    [self.collectionView.collectionViewLayout invalidateLayout];

    if (gesture && (gesture.state == UIGestureRecognizerStateEnded || gesture.state == UIGestureRecognizerStateCancelled)) {
        self.isProcessing = NO;
    } else if (!gesture) {
        self.isProcessing = NO;
    }
}

- (void)handleTrafficLight:(UIButton *)sender {
    [self.feedback impactOccurred];
    if (sender.tag == 0 || sender.tag == 1) {
        [self animateSpotlight:NO fromPoint:self.panelContainer.center];
    } else if (sender.tag == 2) {
        [UIView animateWithDuration:0.6 delay:0 usingSpringWithDamping:0.7 initialSpringVelocity:1 options:0 animations:^{
            CGSize maxSize = [self calculateMaxPanelSize];
            CGFloat targetW = MIN(kChevronLayoutConstants.panelW, maxSize.width);
            CGFloat targetH = MIN(kChevronLayoutConstants.panelH, maxSize.height);
            
            self.panelContainer.bounds = CGRectMake(0, 0, targetW, targetH);
            self.panelContainer.center = CGPointMake(self.bounds.size.width/2, self.bounds.size.height/2);
            [self handleResize:nil];
        } completion:nil];
    }

}

- (void)updateResizingHandleFrame {
    // 确保把手始终在面板的右下角
    CGRect bounds = self.panelContainer.bounds;
    self.resizingHandle.frame = CGRectMake(bounds.size.width - 40, bounds.size.height - 40, 40, 40);
}

- (void)layoutSubviews {
    [super layoutSubviews];
    
    UIEdgeInsets safe = self.safeAreaInsets;
    CGRect bounds = self.bounds;
    CGFloat w = bounds.size.width;
    CGFloat h = bounds.size.height;

    // 计算安全区域内的有效绘图区
    CGRect safeBounds = CGRectMake(safe.left + kChevronLayoutConstants.safeAreaBreath, 
                                   safe.top + kChevronLayoutConstants.safeAreaBreath, 
                                   w - safe.left - safe.right - 2 * kChevronLayoutConstants.safeAreaBreath, 
                                   h - safe.top - safe.bottom - 2 * kChevronLayoutConstants.safeAreaBreath);

    // 1. 设置触发区域
    self.edgeTriggerView.backgroundColor = [[UIColor redColor] colorWithAlphaComponent:0.5]; // 调试可见
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
    
    static NSTimeInterval lastLayoutTime = 0;
    NSTimeInterval currentTime = [[NSDate date] timeIntervalSince1970];
    NSTimeInterval interval = (lastLayoutTime > 0) ? (currentTime - lastLayoutTime) : 0;
    lastLayoutTime = currentTime;

    CV3LogToFile(@"[Debug] Window: %.1fx%.1f, EdgeFrame: %@, Source: layoutSubviews, Interval: %.3fs", w, h, NSStringFromCGRect(self.edgeTriggerView.frame), interval);

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
    
    // 只有在未拖动过且非正在动画时，或者旋转方向改变时，才强制同步 bounds
    BOOL orientationChanged = !CGAffineTransformEqualToTransform(self.panelContainer.transform, targetRotation);
    BOOL shouldForceLayout = (!self.hasBeenMoved && !self.isAnimating) || orientationChanged;

    if (shouldForceLayout && (!CGRectEqualToRect(self.panelContainer.bounds, panelBounds) || orientationChanged)) {
        [UIView animateWithDuration:0.35 delay:0 usingSpringWithDamping:0.8 initialSpringVelocity:0.5 options:UIViewAnimationOptionCurveEaseInOut animations:^{
            self.panelContainer.transform = targetRotation;
            self.panelContainer.bounds = panelBounds;
            
            // 调整子组件大小以匹配容器
            self.appPanel.frame = self.panelContainer.bounds;
            
            UIView *searchContainer = self.searchField.superview;
            searchContainer.frame = CGRectMake(15, 50, targetW - 30, 36);
            self.searchField.frame = CGRectInset(searchContainer.bounds, 10, 0);
            self.collectionView.frame = CGRectMake(0, 96, targetW, targetH - 96);
            self.noResultsLabel.frame = CGRectMake(0, 150, targetW, 40);
            
            self.trafficCapsule.frame = CGRectMake(16, 14, kChevronLayoutConstants.trafficCapsuleW, kChevronLayoutConstants.trafficCapsuleH);
            [self updateResizingHandleFrame];
            self.specularHighlight.frame = self.appPanel.bounds;
            self.cyanLayer.frame = CGRectInset(self.appPanel.bounds, -0.3, -0.3);
            self.magentaLayer.frame = CGRectInset(self.appPanel.bounds, 0.3, 0.3);
            [self.collectionView.collectionViewLayout invalidateLayout];
            
            if (!self.hasBeenMoved) {
                self.panelContainer.center = CGPointMake(CGRectGetMidX(safeBounds), CGRectGetMidY(safeBounds));
            }
        } completion:nil];
    } else {
        // 如果已经拖动过，仅在旋转时更新 transform
        if (orientationChanged) {
             [UIView animateWithDuration:0.35 animations:^{
                self.panelContainer.transform = targetRotation;
             }];
        }
        
        if (!self.isAnimating && !self.hasBeenMoved) {
            self.panelContainer.center = CGPointMake(CGRectGetMidX(safeBounds), CGRectGetMidY(safeBounds));
        } else if (self.isPanelShowing && !self.isAnimating) {
            // 保持在屏幕内的钳位逻辑
            CGPoint currentCenter = self.panelContainer.center;
            CGRect currentBounds = self.panelContainer.bounds;
            
            // 考虑旋转后的实际尺寸
            CGSize sizeInRoot = CGRectApplyAffineTransform(currentBounds, self.panelContainer.transform).size;
            CGFloat rootHalfW = sizeInRoot.width / 2.0;
            CGFloat rootHalfH = sizeInRoot.height / 2.0;

            currentCenter.x = MAX(rootHalfW, MIN(w - rootHalfW, currentCenter.x));
            currentCenter.y = MAX(rootHalfH, MIN(h - rootHalfH, currentCenter.y));
            self.panelContainer.center = currentCenter;
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

    // --- 动态方向感知拉伸计算 ---
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
        if (!self.isPanelShowing) {
            [self.feedback impactOccurred];
            [self.selectionFeedback prepare];
            self.lastHapticX = 0;
            self.bezierContainer.alpha = 1.0;
            self.dimmingView.alpha = 0; 
            
            self.bezierLayer.shadowColor = [UIColor whiteColor].CGColor;
            self.bezierLayer.shadowOffset = CGSizeZero;
            self.bezierLayer.shadowRadius = 10.0;
            self.bezierLayer.shadowOpacity = 0.0;
        }
    } else if (gesture.state == UIGestureRecognizerStateChanged) {
        if (self.bezierContainer.alpha > 0) {
            self.bezierLayer.path = [self pathForStretch:MAX(0, stretch) atPoint:location velocity:velocity orientation:orientation].CGPath;

            CGFloat progress = MIN(stretch / 45.0, 1.0);
            self.dimmingView.alpha = progress;
            self.bezierLayer.shadowOpacity = progress * 0.6;

            CGFloat currentInterval = MAX(10.0, 18.0 - (stretch / 45.0) * 8.0);
            if (fabs(stretch - self.lastHapticX) > currentInterval) {
                if (fabs(vel) > 800) {
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
        if (self.bezierContainer.alpha > 0 && !self.isPanelShowing && vel > 300 && gesture.state != UIGestureRecognizerStateCancelled) {
            [self animateSpotlight:YES fromPoint:location];
        }
        [UIView animateWithDuration:0.4 animations:^{ 
            self.bezierContainer.alpha = 0; 
            if (!self.isPanelShowing) self.dimmingView.alpha = 0;
        }];
    }
}


- (UIBezierPath *)pathForStretch:(CGFloat)stretch atPoint:(CGPoint)point velocity:(CGPoint)velocity orientation:(UIInterfaceOrientation)orientation {
    CGFloat s = MIN(stretch * 0.7, 95); 
    
    UIBezierPath *path = [UIBezierPath bezierPath];

    CGRect b = self.bounds;

    if (orientation == UIInterfaceOrientationLandscapeLeft) {
        // 顶部拉伸 (LandscapeLeft, Home在右)
        CGFloat leftX = point.x - 130;
        CGFloat rightX = point.x + 130;
        CGFloat peakY = s;
        [path moveToPoint:CGPointMake(0, 0)]; // 从左上角开始
        [path addLineToPoint:CGPointMake(leftX, 0)]; // 直线到左边起点
        [path addCurveToPoint:CGPointMake(point.x, peakY) controlPoint1:CGPointMake(point.x - 65, 0) controlPoint2:CGPointMake(point.x - 45, peakY)];
        [path addCurveToPoint:CGPointMake(rightX, 0) controlPoint1:CGPointMake(point.x + 45, peakY) controlPoint2:CGPointMake(point.x + 65, 0)];
        [path addLineToPoint:CGPointMake(b.size.width, 0)]; // 直线到右上角
        [path addLineToPoint:CGPointMake(0, 0)]; // 闭合
    } else if (orientation == UIInterfaceOrientationLandscapeRight) {
        // 底部拉伸 (LandscapeRight, Home在左)
        CGFloat leftX = point.x - 130;
        CGFloat rightX = point.x + 130;
        CGFloat peakY = b.size.height - s;
        [path moveToPoint:CGPointMake(0, b.size.height)]; // 左下角
        [path addLineToPoint:CGPointMake(leftX, b.size.height)];
        [path addCurveToPoint:CGPointMake(point.x, peakY) controlPoint1:CGPointMake(point.x - 65, b.size.height) controlPoint2:CGPointMake(point.x - 45, peakY)];
        [path addCurveToPoint:CGPointMake(rightX, b.size.height) controlPoint1:CGPointMake(point.x + 45, peakY) controlPoint2:CGPointMake(point.x + 65, b.size.height)];
        [path addLineToPoint:CGPointMake(b.size.width, b.size.height)]; // 右下角
        [path addLineToPoint:CGPointMake(0, b.size.height)]; // 闭合
    } else if (orientation == UIInterfaceOrientationPortraitUpsideDown) {
        // 左边缘拉伸
        CGFloat topY = point.y - 130;
        CGFloat bottomY = point.y + 130;
        CGFloat peakX = s;
        [path moveToPoint:CGPointMake(0, 0)]; // 左上角
        [path addLineToPoint:CGPointMake(0, topY)];
        [path addCurveToPoint:CGPointMake(peakX, point.y) controlPoint1:CGPointMake(0, point.y - 65) controlPoint2:CGPointMake(peakX, point.y - 45)];
        [path addCurveToPoint:CGPointMake(0, bottomY) controlPoint1:CGPointMake(peakX, point.y + 45) controlPoint2:CGPointMake(0, point.y + 65)];
        [path addLineToPoint:CGPointMake(0, b.size.height)]; // 左下角
        [path addLineToPoint:CGPointMake(0, 0)]; // 闭合
    } else {
        // 右边缘拉伸 (Portrait)
        CGFloat topY = point.y - 130;
        CGFloat bottomY = point.y + 130;
        CGFloat peakX = b.size.width - s;
        [path moveToPoint:CGPointMake(b.size.width, 0)]; // 右上角
        [path addLineToPoint:CGPointMake(b.size.width, topY)];
        [path addCurveToPoint:CGPointMake(peakX, point.y) controlPoint1:CGPointMake(b.size.width, point.y - 65) controlPoint2:CGPointMake(peakX, point.y - 45)];
        [path addCurveToPoint:CGPointMake(b.size.width, bottomY) controlPoint1:CGPointMake(peakX, point.y + 45) controlPoint2:CGPointMake(b.size.width, point.y + 65)];
        [path addLineToPoint:CGPointMake(b.size.width, b.size.height)]; // 右下角
        [path addLineToPoint:CGPointMake(b.size.width, 0)]; // 闭合
    }

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
        self.lastTriggerPoint = point;
        [self loadAppsAsync];
        [self updateTrafficLightsFocus:YES];
        self.dimmingView.userInteractionEnabled = YES; // 显示时开启拦截
        self.panelContainer.hidden = NO; self.panelContainer.center = point;
        
        // 预先应用正确的旋转变换和尺寸
        CGAffineTransform initialRotation = CGAffineTransformIdentity;
        UIInterfaceOrientation orientation = self.targetOrientation != UIInterfaceOrientationUnknown ? self.targetOrientation : UIInterfaceOrientationPortrait;
        switch (orientation) {
            case UIInterfaceOrientationLandscapeLeft: initialRotation = CGAffineTransformMakeRotation(-M_PI_2); break;
            case UIInterfaceOrientationLandscapeRight: initialRotation = CGAffineTransformMakeRotation(M_PI_2); break;
            case UIInterfaceOrientationPortraitUpsideDown: initialRotation = CGAffineTransformMakeRotation(M_PI); break;
            default: initialRotation = CGAffineTransformIdentity; break;
        }

        // 计算当前环境下合法的尺寸 (同步 layoutSubviews 逻辑)
        CGSize maxSize = [self calculateMaxPanelSize];
        
        CGFloat targetW = MIN(kChevronLayoutConstants.panelW, maxSize.width);
        CGFloat targetH = MIN(kChevronLayoutConstants.panelH, maxSize.height);
        targetH = MAX(targetH, kChevronLayoutConstants.minHeight);
        
        // 设置初始 bounds 和子组件大小，防止在 layoutSubviews 锁定期间出现错位
        self.panelContainer.bounds = CGRectMake(0, 0, targetW, targetH);
        self.appPanel.frame = self.panelContainer.bounds;
        
        UIView *searchContainer = self.searchField.superview;
        searchContainer.frame = CGRectMake(15, 50, targetW - 30, 36);
        self.searchField.frame = CGRectInset(searchContainer.bounds, 10, 0);
        self.collectionView.frame = CGRectMake(0, 96, targetW, targetH - 96);
        self.noResultsLabel.frame = CGRectMake(0, 150, targetW, 40);
        
        self.trafficCapsule.frame = CGRectMake(16, 14, kChevronLayoutConstants.trafficCapsuleW, kChevronLayoutConstants.trafficCapsuleH);
        [self updateResizingHandleFrame];
        self.specularHighlight.frame = self.appPanel.bounds;
        self.cyanLayer.frame = CGRectInset(self.appPanel.bounds, -0.3, -0.3);
        self.magentaLayer.frame = CGRectInset(self.appPanel.bounds, 0.3, 0.3);
        [self.collectionView.collectionViewLayout invalidateLayout];

        self.panelContainer.transform = CGAffineTransformScale(initialRotation, 0.01, 0.01);
        self.panelContainer.alpha = 0;

        [UIView animateWithDuration:0.6 delay:0 usingSpringWithDamping:0.7 initialSpringVelocity:1 options:0 animations:^{
            self.dimmingView.alpha = 1.0;
            self.panelContainer.center = CGPointMake(self.bounds.size.width/2, self.bounds.size.height/2);
            self.panelContainer.transform = initialRotation;
            self.panelContainer.alpha = 1;
        } completion:^(BOOL f){ self.isAnimating = NO; [self startLiquidMotion]; }];
    } else {
        [self.searchField resignFirstResponder]; // 关闭时自动收起键盘
        [self updateTrafficLightsFocus:NO];
        [self stopLiquidMotion];
        self.dimmingView.userInteractionEnabled = NO; // 隐藏时关闭拦截
        
        // 获取当前的旋转状态
        CGAffineTransform currentRotation = self.panelContainer.transform;
        
        [UIView animateWithDuration:0.3 delay:0 options:UIViewAnimationOptionBeginFromCurrentState animations:^{ 
            self.dimmingView.alpha = 0;
            self.panelContainer.alpha = 0; 
            self.panelContainer.center = self.lastTriggerPoint; // 回退到存储的触发点
            self.panelContainer.transform = CGAffineTransformScale(currentRotation, 0.01, 0.01);
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
    [cv3IconCache removeAllObjects]; // 确保每次加载时图标缓存是空的，避免显示旧图标
    dispatch_async(dispatch_get_global_queue(0,0), ^{
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
            CV3LogToFile(@"[Debug] 成功获取 SBIconModel，leafIcons 数量: %lu", (unsigned long)[leafIcons count]);
            
            for (id icon in leafIcons) {
                // 过滤：必须是 ApplicationIcon
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
                    info.sbIcon = icon; // 存储 SBIcon 引用
                    [info generatePinyin]; // 预生成拼音首字母
                    
                    UIImage *cachedIcon = [cv3IconCache objectForKey:bundleId];
                    if (cachedIcon) {
                        info.icon = cachedIcon;
                    } else {
                        info.icon = [UIImage _applicationIconImageForBundleIdentifier:bundleId format:10 scale:[UIScreen mainScreen].scale];
                        if (info.icon) [cv3IconCache setObject:info.icon forKey:bundleId];
                    }

                    if (info.icon) {
                        [temp addObject:info];
                    }
                }
            }
        }
        
        // 如果上面获取失败，回退到原有的 Workspace 方法
        if (temp.count == 0) {
            CV3LogToFile(@"[Debug] 警告：无法获取 SBIconModel，回退至 LSApplicationWorkspace");
            id ws = [NSClassFromString(@"LSApplicationWorkspace") defaultWorkspace];
            for (id p in [ws performSelector:@selector(allInstalledApplications)]) {
                if (![self shouldIncludeApp:p]) continue;
                
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

                if (info.name && info.bundleId && info.icon) [temp addObject:info];
            }
        }
        
        // 获取使用频率数据 (时间衰减逻辑)
        NSDictionary *usageData = [[NSUserDefaults standardUserDefaults] dictionaryForKey:@"CV3AppUsageData"];
        NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
        NSTimeInterval sevenDaysInSeconds = 7 * 24 * 3600;
        
        // 排序逻辑：
        // 1. 仅统计最近 7 天内的点击次数作为活跃权重
        // 2. 权重相同则按字母排序
        [temp sortUsingComparator:^NSComparisonResult(CV3AppInfo *obj1, CV3AppInfo *obj2) {
            NSArray *ts1 = usageData[obj1.bundleId];
            NSArray *ts2 = usageData[obj2.bundleId];
            
            NSInteger count1 = 0;
            for (NSNumber *ts in ts1) {
                if (now - [ts doubleValue] < sevenDaysInSeconds) count1++;
            }
            
            NSInteger count2 = 0;
            for (NSNumber *ts in ts2) {
                if (now - [ts doubleValue] < sevenDaysInSeconds) count2++;
            }
            
            if (count1 != count2) {
                return count1 > count2 ? NSOrderedAscending : NSOrderedDescending;
            }
            return [obj1.name localizedCaseInsensitiveCompare:obj2.name];
        }];
        
        dispatch_async(dispatch_get_main_queue(), ^{ 
            self.apps = temp; 
            [self filterApps]; // 初始化过滤列表
            [self animateIconsStaggered]; 
        });
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
    // 异步确保不在敏感的系统转换周期内执行同步 UI 操作
    dispatch_async(dispatch_get_main_queue(), ^{
        // 增加内部保护，防止异步任务堆叠
        if (self.isProcessing) return;
        self.isProcessing = YES;

        @try {
            UIWindowScene *targetScene = nil;
            if ([NSClassFromString(@"SBWindowScene") respondsToSelector:@selector(mainDisplayWindowScene)]) {
                targetScene = [NSClassFromString(@"SBWindowScene") performSelector:@selector(mainDisplayWindowScene)];
            }
            
            if (!targetScene) {
                for (UIScene *scene in [[UIApplication sharedApplication].connectedScenes allObjects]) {
                    if ([scene isKindOfClass:[UIWindowScene class]]) {
                        NSString *role = scene.session.role;
                        
                        // 仅过滤掉明确的系统覆盖层
                        if ([role isEqualToString:@"SBWindowSceneSessionRoleSystemAperture"] ||
                            [role isEqualToString:@"SBWindowSceneSessionRoleSystemApertureCurtain"] ||
                            [role isEqualToString:@"UISceneSessionRolePlaceholder"]) continue;
                        
                        // 放宽：只要是前台活跃的 UIWindowScene 均可挂载
                        if (scene.activationState == UISceneActivationStateForegroundActive) {
                            targetScene = (UIWindowScene *)scene;
                            break; // 找到第一个活跃场景即可
                        }
                    }
                }
            }


            if (targetScene) {
                if (self.windowScene != targetScene) self.windowScene = targetScene;
                self.hidden = NO; 
                [self applyAdaptiveLevel];
                
                // 使用 targetScene 的 bounds 以保证在不同场景旋转下覆盖整个屏幕
                CGRect targetBounds = targetScene.coordinateSpace.bounds;
                self.frame = targetBounds;

                [self setNeedsLayout];
            }
        } @catch (NSException *e) {}
        self.isProcessing = NO;
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

- (NSInteger)collectionView:(id)c numberOfItemsInSection:(NSInteger)s { return self.filteredApps.count; }
- (id)collectionView:(id)c cellForItemAtIndexPath:(id)i {
    CV3AppCell *cell = [c dequeueReusableCellWithReuseIdentifier:@"C" forIndexPath:i];
    [cell configureWithInfo:self.filteredApps[[(NSIndexPath *)i item]] searchText:self.searchField.text];
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
        // 1. 优先检查搜索框及其容器（最高优先级，防止被拖拽拦截）
        UIView *searchContainer = self.searchField.superview;
        CGPoint pInSearch = [self convertPoint:point toView:searchContainer];
        if (CGRectContainsPoint(searchContainer.bounds, pInSearch)) {
            UIView *hit = [searchContainer hitTest:pInSearch withEvent:e];
            return hit ?: searchContainer;
        }

        // 2. 检查面板区域
        CGPoint p = [self convertPoint:point toView:self.panelContainer];
        if (CGRectContainsPoint(self.panelContainer.bounds, p)) {
            UIView *hit = [self.panelContainer hitTest:p withEvent:e];
            // 如果点中了面板但没有具体子视图响应，返回面板容器以便处理拖拽
            return hit ?: self.panelContainer;
        }
        
        // 检查遮罩层
        CGPoint pInDimming = [self convertPoint:point toView:self.dimmingView];
        if (CGRectContainsPoint(self.dimmingView.bounds, pInDimming)) {
            return self.dimmingView;
        }
        return nil;
    }

    // 终极绑定逻辑
    CGPoint pointInRoot = [self convertPoint:point toView:self.rootViewController.view];
    if (CGRectContainsPoint(self.edgeTriggerView.frame, pointInRoot)) {
        if (self.isKeyboardVisible) {
            CGPoint pInTrigger = [self.rootViewController.view convertPoint:pointInRoot toView:self.edgeTriggerView];
            if (pInTrigger.y > self.edgeTriggerView.bounds.size.height * 0.4) return nil;
        }
        return self;
    }

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
                    [sharedWindow layoutIfNeeded];
                }
            });
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
