#import <UIKit/UIKit.h>
#import <AVFAudio/AVFAudio.h>
#import <objc/message.h>
#import <notify.h>

static const char *CV3VideoOrientationNotification = "com.xu.chevronv3.video-orientation";
static int CV3VideoOrientationNotificationToken = -1;
static UIInterfaceOrientation CV3RequestedInterfaceOrientation = UIInterfaceOrientationUnknown;
static int CV3HostedStateNotificationToken = -1;
static BOOL CV3ApplicationIsChevronHosted = NO;
static BOOL CV3WorkspaceTransitionShieldActive = NO;

static BOOL CV3ControllerLikelyOwnsFullscreenVideo(UIViewController *controller);

static uint64_t CV3StableBundleHash(NSString *bundleID) {
    const unsigned char *bytes = (const unsigned char *)[bundleID UTF8String];
    uint64_t hash = 1469598103934665603ULL;
    if (!bytes) return hash;
    while (*bytes) {
        hash ^= (uint64_t)*bytes++;
        hash *= 1099511628211ULL;
    }
    return hash & 0x00FFFFFFFFFFFFFFULL;
}

static NSString *CV3HostedStateNotificationName(void) {
    NSString *bundleID = [NSBundle mainBundle].bundleIdentifier;
    if (bundleID.length == 0) return nil;
    return [NSString stringWithFormat:@"com.xu.chevronv3.hosted.%014llx", CV3StableBundleHash(bundleID)];
}

static void CV3RefreshHostedState(int token) {
    uint64_t state = 0;
    if (token >= 0 && notify_get_state(token, &state) == NOTIFY_STATUS_OK) {
        CV3ApplicationIsChevronHosted = (state & 1) != 0;
        CV3WorkspaceTransitionShieldActive = (state & 2) != 0;
    }
}

static BOOL CV3IsLifecycleDeactivationNotification(NSNotificationName name) {
    if (name.length == 0) return NO;
    return [name isEqualToString:UIApplicationWillResignActiveNotification] ||
           [name isEqualToString:UIApplicationDidEnterBackgroundNotification] ||
           [name isEqualToString:UISceneWillDeactivateNotification] ||
           [name isEqualToString:UISceneDidEnterBackgroundNotification];
}

static BOOL CV3IsAppSuspensionAudioInterruption(NSDictionary *userInfo) {
    // 使用运行时键名兼容 iOS 14.0；SDK 中对应常量从 14.5 才可用。
    NSNumber *reason = userInfo[@"AVAudioSessionInterruptionReasonKey"];
    NSNumber *wasSuspended = userInfo[@"AVAudioSessionInterruptionWasSuspendedKey"];
    return reason.unsignedIntegerValue == 1 || wasSuspended.boolValue;
}

static UIInterfaceOrientation CV3InterfaceOrientationForDeviceOrientation(UIDeviceOrientation orientation) {
    switch (orientation) {
        case UIDeviceOrientationLandscapeLeft:
            return UIInterfaceOrientationLandscapeRight;
        case UIDeviceOrientationLandscapeRight:
            return UIInterfaceOrientationLandscapeLeft;
        case UIDeviceOrientationPortraitUpsideDown:
            return UIInterfaceOrientationPortraitUpsideDown;
        case UIDeviceOrientationPortrait:
            return UIInterfaceOrientationPortrait;
        default:
            return UIInterfaceOrientationUnknown;
    }
}

static UIInterfaceOrientation CV3InterfaceOrientationForMask(UIInterfaceOrientationMask mask,
                                                              UIInterfaceOrientation preferredOrientation) {
    BOOL supportsPortrait = (mask & (UIInterfaceOrientationMaskPortrait | UIInterfaceOrientationMaskPortraitUpsideDown)) != 0;
    BOOL supportsLandscape = (mask & UIInterfaceOrientationMaskLandscape) != 0;

    if (supportsLandscape && !supportsPortrait) {
        UIInterfaceOrientation deviceOrientation = CV3InterfaceOrientationForDeviceOrientation([UIDevice currentDevice].orientation);
        if (UIInterfaceOrientationIsLandscape(deviceOrientation) && (mask & (1UL << deviceOrientation))) {
            return deviceOrientation;
        }
        if (UIInterfaceOrientationIsLandscape(preferredOrientation) && (mask & (1UL << preferredOrientation))) {
            return preferredOrientation;
        }
        return (mask & UIInterfaceOrientationMaskLandscapeRight)
            ? UIInterfaceOrientationLandscapeRight
            : UIInterfaceOrientationLandscapeLeft;
    }

    if (supportsPortrait && !supportsLandscape) {
        return (mask & UIInterfaceOrientationMaskPortrait)
            ? UIInterfaceOrientationPortrait
            : UIInterfaceOrientationPortraitUpsideDown;
    }

    if (UIInterfaceOrientationIsLandscape(preferredOrientation)) return preferredOrientation;
    return UIInterfaceOrientationUnknown;
}

static void CV3PostVideoOrientation(UIInterfaceOrientation orientation) {
    if (orientation == UIInterfaceOrientationUnknown) return;

    NSString *bundleID = [NSBundle mainBundle].bundleIdentifier;
    if (bundleID.length == 0 || [bundleID isEqualToString:@"com.apple.springboard"]) return;
    CV3RequestedInterfaceOrientation = orientation;

    if (CV3VideoOrientationNotificationToken < 0) {
        if (notify_register_check(CV3VideoOrientationNotification, &CV3VideoOrientationNotificationToken) != NOTIFY_STATUS_OK) {
            CV3VideoOrientationNotificationToken = -1;
            return;
        }
    }

    uint64_t state = CV3StableBundleHash(bundleID) | (((uint64_t)orientation & 0xFFULL) << 56);
    notify_set_state(CV3VideoOrientationNotificationToken, state);
    notify_post(CV3VideoOrientationNotification);
}

static void CV3PostOrientationForController(UIViewController *controller) {
    if (!controller || !controller.viewIfLoaded.window) return;

    UIInterfaceOrientation preferredOrientation = UIInterfaceOrientationUnknown;
    @try {
        preferredOrientation = controller.preferredInterfaceOrientationForPresentation;
    } @catch (NSException *exception) {}

    UIInterfaceOrientation orientation = CV3InterfaceOrientationForMask(controller.supportedInterfaceOrientations,
                                                                         preferredOrientation);
    if (UIInterfaceOrientationIsLandscape(orientation) && CV3ControllerLikelyOwnsFullscreenVideo(controller)) {
        CV3PostVideoOrientation(orientation);
    } else if (CV3RequestedInterfaceOrientation != UIInterfaceOrientationUnknown) {
        CV3PostVideoOrientation(UIInterfaceOrientationPortrait);
    }
}

static BOOL CV3ControllerLikelyOwnsFullscreenVideo(UIViewController *controller) {
    if (!controller) return NO;
    if (controller.presentingViewController || controller.presentedViewController) return YES;
    if (controller.modalPresentationStyle == UIModalPresentationFullScreen ||
        controller.modalPresentationStyle == UIModalPresentationOverFullScreen) return YES;

    NSString *className = NSStringFromClass(controller.class);
    return [className rangeOfString:@"Player" options:NSCaseInsensitiveSearch].location != NSNotFound ||
           [className rangeOfString:@"Video" options:NSCaseInsensitiveSearch].location != NSNotFound ||
           [className rangeOfString:@"FullScreen" options:NSCaseInsensitiveSearch].location != NSNotFound;
}

%hook UIWindowScene
- (void)requestGeometryUpdateWithPreferences:(id)preferences errorHandler:(id)errorHandler {
    SEL selector = NSSelectorFromString(@"interfaceOrientations");
    if (preferences && [preferences respondsToSelector:selector]) {
        UIInterfaceOrientationMask mask = ((UIInterfaceOrientationMask (*)(id, SEL))objc_msgSend)(preferences, selector);
        CV3PostVideoOrientation(CV3InterfaceOrientationForMask(mask, UIInterfaceOrientationUnknown));
    }
    %orig(preferences, errorHandler);
}
%end

%hook UIViewController
- (void)setNeedsUpdateOfSupportedInterfaceOrientations {
    %orig;
    dispatch_async(dispatch_get_main_queue(), ^{
        CV3PostOrientationForController(self);
    });
}

- (void)viewDidAppear:(BOOL)animated {
    %orig(animated);
    CV3PostOrientationForController(self);
}

- (void)viewDidDisappear:(BOOL)animated {
    %orig(animated);
    if (CV3RequestedInterfaceOrientation != UIInterfaceOrientationUnknown &&
        CV3ControllerLikelyOwnsFullscreenVideo(self)) {
        CV3PostVideoOrientation(UIInterfaceOrientationPortrait);
    }
}
%end

%hook UIDevice
- (void)setValue:(id)value forKey:(NSString *)key {
    if ([key isEqualToString:@"orientation"] && [value respondsToSelector:@selector(integerValue)]) {
        CV3PostVideoOrientation(CV3InterfaceOrientationForDeviceOrientation((UIDeviceOrientation)[value integerValue]));
    }
    %orig(value, key);
}
%end

%hook AVAudioSession
- (BOOL)setActive:(BOOL)active error:(NSError **)outError {
    if (!active && CV3ApplicationIsChevronHosted) return YES;
    return %orig(active, outError);
}

- (BOOL)setActive:(BOOL)active withOptions:(AVAudioSessionSetActiveOptions)options error:(NSError **)outError {
    if (!active && CV3ApplicationIsChevronHosted) return YES;
    return %orig(active, options, outError);
}
%end

%hook UIApplication
- (UIApplicationState)applicationState {
    if (CV3ApplicationIsChevronHosted) {
        return UIApplicationStateActive;
    }
    return %orig;
}
%end

%hook UIScene
- (UISceneActivationState)activationState {
    if (CV3ApplicationIsChevronHosted) {
        return UISceneActivationStateForegroundActive;
    }
    return %orig;
}
%end

%hook _UISceneLifecycleMultiplexer
- (void)_performBlock:(id)block
withApplicationOfDeactivationReasons:(NSUInteger)reasons
          fromReasons:(NSUInteger)fromReasons {
    // UIKit 会绕过 NSNotificationCenter，直接在此处向 App/Scene delegate
    // 分发 willResignActive / didEnterBackground。整个托管生命周期内跳过整段
    // lifecycle block，同时避免 UIApplication 内部的 deactivation mask 被更改。
    if (CV3ApplicationIsChevronHosted && reasons != 0) {
        NSLog(@"[ChevronV3VideoBridge] Suppressed lifecycle deactivation reasons=%lu from=%lu",
              (unsigned long)reasons,
              (unsigned long)fromReasons);
        return;
    }
    %orig(block, reasons, fromReasons);
}
%end

%hook NSNotificationCenter
- (void)postNotification:(NSNotification *)notification {
    if (CV3ApplicationIsChevronHosted &&
        CV3IsLifecycleDeactivationNotification(notification.name)) {
        return;
    }
    if (CV3ApplicationIsChevronHosted &&
        [notification.name isEqualToString:AVAudioSessionInterruptionNotification] &&
        CV3IsAppSuspensionAudioInterruption(notification.userInfo)) {
        return;
    }
    %orig(notification);
}

- (void)postNotificationName:(NSNotificationName)name object:(id)object {
    if (CV3ApplicationIsChevronHosted &&
        CV3IsLifecycleDeactivationNotification(name)) return;
    %orig(name, object);
}

- (void)postNotificationName:(NSNotificationName)name object:(id)object userInfo:(NSDictionary *)userInfo {
    if (CV3ApplicationIsChevronHosted &&
        CV3IsLifecycleDeactivationNotification(name)) return;
    if (CV3ApplicationIsChevronHosted &&
        [name isEqualToString:AVAudioSessionInterruptionNotification] &&
        CV3IsAppSuspensionAudioInterruption(userInfo)) return;
    %orig(name, object, userInfo);
}
%end

%ctor {
    @autoreleasepool {
        if ([[NSBundle mainBundle].bundleIdentifier lowercaseString].length == 0 ||
            [[[NSBundle mainBundle].bundleIdentifier lowercaseString] isEqualToString:@"com.apple.springboard"]) {
            return;
        }
        NSString *hostedStateName = CV3HostedStateNotificationName();
        if (hostedStateName.length > 0 &&
            notify_register_dispatch(hostedStateName.UTF8String,
                                     &CV3HostedStateNotificationToken,
                                     dispatch_get_main_queue(),
                                     ^(int token) {
                CV3RefreshHostedState(token);
            }) == NOTIFY_STATUS_OK) {
            CV3RefreshHostedState(CV3HostedStateNotificationToken);
        }
        %init;
    }
}
