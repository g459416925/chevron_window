#import <UIKit/UIKit.h>
#import <AVFAudio/AVFAudio.h>
#import <AVFoundation/AVFoundation.h>
#import <objc/message.h>
#import <objc/runtime.h>
#import <notify.h>
#import <substrate.h>

static const char *CV3VideoOrientationNotification = "com.xu.chevronv3.video-orientation";
static const char *CV3PlaybackTraceNotification = "com.xu.chevronv3.playback-trace";
static const char *CV3HostGenerationNotification = "com.xu.chevronv3.host-generation";
static int CV3VideoOrientationNotificationToken = -1;
static int CV3PlaybackTraceNotificationToken = -1;
static UIInterfaceOrientation CV3RequestedInterfaceOrientation = UIInterfaceOrientationUnknown;
static __weak UIViewController *CV3VideoOrientationOwner = nil;
static UIInterfaceOrientation CV3OrientationBeforeVideo = UIInterfaceOrientationUnknown;
static int CV3HostedStateNotificationToken = -1;
static int CV3HostGenerationNotificationToken = -1;
static BOOL CV3ApplicationIsChevronHosted = NO;
static BOOL CV3WorkspaceTransitionShieldActive = NO;
static NSTimeInterval CV3PlaybackTransitionGraceDeadline = 0;
static const uint64_t CV3ClientBridgeProtocolVersion = 0x2026090603ULL;
static const uint64_t CV3CanvasReadyFlag = (1ULL << 63);
static NSTimer *CV3CanvasTimer = nil;
static int CV3CanvasNotificationToken = -1;
static NSString *CV3CanvasNotificationName = nil;
static NSString *CV3LastClientDirectionSignature = nil;
static NSString *CV3LastClientReceptionSignature = nil;
static NSTimeInterval CV3LastClientReceptionHeartbeatTime = 0;
static BOOL CV3ShouldProtectHostedPlayback(void);
static volatile uint64_t CV3MetalDrawableRequestCount = 0;
static volatile uint64_t CV3VideoPixelBufferCopyCount = 0;
static volatile CFTimeInterval CV3LastMetalDrawableRequestTime = 0;
static volatile CFTimeInterval CV3LastVideoPixelBufferCopyTime = 0;
static CFTimeInterval CV3LandscapeReentrySuppressedUntil = 0;

static void CV3AppendCanvasTrace(NSString *line) {
    (void)line;
}

static NSString *CV3TraceLayerValue(id object, NSString *key) {
    @try {
        id value = [object valueForKey:key];
        return value ? [value description] : @"nil";
    } @catch (__unused NSException *exception) {
        return @"n/a";
    }
}

static NSString *CV3ClientDirectionTransform3D(CATransform3D t) {
    return [NSString stringWithFormat:
        @"[%.4f %.4f %.4f %.4f; %.4f %.4f %.4f %.4f; %.4f %.4f %.4f %.4f; %.4f %.4f %.4f %.4f]",
        t.m11, t.m12, t.m13, t.m14,
        t.m21, t.m22, t.m23, t.m24,
        t.m31, t.m32, t.m33, t.m34,
        t.m41, t.m42, t.m43, t.m44];
}

static NSString *CV3ClientDirectionLayer(CALayer *layer) {
    if (!layer) return @"nil";
    CALayer *presentation = layer.presentationLayer;
    return [NSString stringWithFormat:
        @"%@ frame=%@ bounds=%@ affine=%@ transform=%@ presentationFrame=%@ presentationBounds=%@ presentationTransform=%@",
        NSStringFromClass(layer.class), NSStringFromCGRect(layer.frame), NSStringFromCGRect(layer.bounds),
        NSStringFromCGAffineTransform(layer.affineTransform), CV3ClientDirectionTransform3D(layer.transform),
        presentation ? NSStringFromCGRect(presentation.frame) : @"nil",
        presentation ? NSStringFromCGRect(presentation.bounds) : @"nil",
        presentation ? CV3ClientDirectionTransform3D(presentation.transform) : @"nil"];
}

static AVPlayerLayer *CV3FirstPlayerLayer(CALayer *layer) {
    if (!layer) return nil;
    if ([layer isKindOfClass:AVPlayerLayer.class]) return (AVPlayerLayer *)layer;
    for (CALayer *child in layer.sublayers ?: @[]) {
        AVPlayerLayer *result = CV3FirstPlayerLayer(child);
        if (result) return result;
    }
    return nil;
}

static void CV3CollectClientReceptionLayers(CALayer *layer,
                                            NSString *path,
                                            NSUInteger depth,
                                            NSMutableArray<NSString *> *entries) {
    if (!layer || depth > 12 || entries.count >= 64) return;
    BOOL isPlayer = [layer isKindOfClass:AVPlayerLayer.class];
    BOOL isMetal = [NSStringFromClass(layer.class) containsString:@"Metal"];
    if (isPlayer || isMetal) {
        CALayer *presentation = layer.presentationLayer;
        NSMutableString *entry = [NSMutableString stringWithFormat:
            @"%@:%@ frame=%@ hidden=%d opacity=%.2f contents=%@ drawable=%@ pres=%@",
            path, NSStringFromClass(layer.class), NSStringFromCGRect(layer.frame), layer.hidden, layer.opacity,
            CV3TraceLayerValue(layer, @"contents"), CV3TraceLayerValue(layer, @"drawableSize"),
            presentation ? NSStringFromCGRect(presentation.frame) : @"nil"];
        if (isPlayer) {
            AVPlayer *player = ((AVPlayerLayer *)layer).player;
            AVPlayerItem *item = player.currentItem;
            [entry appendFormat:@" player=%p rate=%.3f timeControl=%ld reason=%@ item=%p itemStatus=%ld error=%@",
                player, player.rate, (long)player.timeControlStatus, player.reasonForWaitingToPlay,
                item, (long)item.status, item.error];
        }
        [entries addObject:entry];
    }
    NSUInteger index = 0;
    for (CALayer *child in layer.sublayers ?: @[]) {
        CV3CollectClientReceptionLayers(child, [path stringByAppendingFormat:@".%lu", (unsigned long)index++],
                                        depth + 1, entries);
    }
}

static void CV3RecordClientReceptionTrace(NSString *phase, BOOL force) {
    if (!CV3ApplicationIsChevronHosted && !force) return;
    NSMutableArray<NSString *> *windows = [NSMutableArray array];
    NSUInteger sceneIndex = 0;
    for (UIScene *sceneObject in UIApplication.sharedApplication.connectedScenes) {
        if (![sceneObject isKindOfClass:UIWindowScene.class]) continue;
        UIWindowScene *scene = (UIWindowScene *)sceneObject;
        NSUInteger windowIndex = 0;
        for (UIWindow *window in scene.windows) {
            NSMutableArray<NSString *> *layers = [NSMutableArray array];
            CV3CollectClientReceptionLayers(window.layer, @"L", 0, layers);
            [windows addObject:[NSString stringWithFormat:
                @"S%lu.W%lu sceneActivation=%ld sceneOrientation=%ld hidden=%d alpha=%.2f key=%d "
                 "frame=%@ bounds=%@ root=%@ layers=[%@]",
                (unsigned long)sceneIndex, (unsigned long)windowIndex++, (long)scene.activationState,
                (long)scene.interfaceOrientation, window.hidden, window.alpha, window.isKeyWindow,
                NSStringFromCGRect(window.frame), NSStringFromCGRect(window.bounds),
                NSStringFromClass(window.rootViewController.class), [layers componentsJoinedByString:@" | "]]];
        }
        sceneIndex++;
    }
    NSString *signature = [NSString stringWithFormat:
        @"hosted=%d shield=%d appState=%ld protected=%d metalDrawableRequests=%llu metalAge=%.3f "
         "videoPixelCopies=%llu videoAge=%.3f windows=%@",
        CV3ApplicationIsChevronHosted, CV3WorkspaceTransitionShieldActive,
        (long)UIApplication.sharedApplication.applicationState,
        CV3ShouldProtectHostedPlayback(), (unsigned long long)CV3MetalDrawableRequestCount,
        CV3LastMetalDrawableRequestTime > 0 ? CACurrentMediaTime() - CV3LastMetalDrawableRequestTime : -1.0,
        (unsigned long long)CV3VideoPixelBufferCopyCount,
        CV3LastVideoPixelBufferCopyTime > 0 ? CACurrentMediaTime() - CV3LastVideoPixelBufferCopyTime : -1.0,
        [windows componentsJoinedByString:@" || "]];
    NSTimeInterval now = CACurrentMediaTime();
    BOOL changed = ![signature isEqualToString:CV3LastClientReceptionSignature];
    BOOL heartbeatDue = now - CV3LastClientReceptionHeartbeatTime >= 2.0;
    if (!force && !changed && !heartbeatDue) return;
    CV3LastClientReceptionSignature = signature;
    CV3LastClientReceptionHeartbeatTime = now;
    CV3AppendCanvasTrace([NSString stringWithFormat:@"[ReceptionTrace][Client] event=%@ phase=%@ %@",
        changed ? @"change" : @"heartbeat", phase ?: @"unknown", signature]);
}

static void CV3RecordClientReceptionLifecycleEvent(NSNotificationName name) {
    if (!CV3ApplicationIsChevronHosted || name.length == 0) return;
    NSString *phase = [@"lifecycle.notification." stringByAppendingString:name];
    if ([NSThread isMainThread]) {
        CV3RecordClientReceptionTrace(phase, YES);
    } else {
        dispatch_async(dispatch_get_main_queue(), ^{
            CV3RecordClientReceptionTrace(phase, YES);
        });
    }
}

static void CV3RecordClientDirectionTrace(UIWindowScene *scene,
                                          UIWindow *window,
                                          BOOL repairedVideoLayer,
                                          uint64_t readyGeometry,
                                          BOOL force) {
    if (!scene || !window) return;
    UIView *rootView = window.rootViewController.viewIfLoaded;
    AVPlayerLayer *playerLayer = CV3FirstPlayerLayer(window.layer);
    NSString *signature = [NSString stringWithFormat:
        @"sceneOrientation=%ld deviceOrientation=%ld sceneBounds=%@ screenBounds=%@ "
         "windowFrame=%@ windowBounds=%@ windowTransform=%@ windowLayer={%@} "
         "rootFrame=%@ rootBounds=%@ rootTransform=%@ rootLayer={%@} player={%@} repaired=%d ready=0x%016llx",
        (long)scene.interfaceOrientation, (long)UIDevice.currentDevice.orientation,
        NSStringFromCGRect(scene.coordinateSpace.bounds), NSStringFromCGRect(scene.screen.bounds),
        NSStringFromCGRect(window.frame), NSStringFromCGRect(window.bounds), NSStringFromCGAffineTransform(window.transform),
        CV3ClientDirectionLayer(window.layer), NSStringFromCGRect(rootView.frame), NSStringFromCGRect(rootView.bounds),
        NSStringFromCGAffineTransform(rootView.transform), CV3ClientDirectionLayer(rootView.layer),
        CV3ClientDirectionLayer(playerLayer), repairedVideoLayer, (unsigned long long)readyGeometry];
    if (!force && [signature isEqualToString:CV3LastClientDirectionSignature]) return;
    CV3LastClientDirectionSignature = signature;
    CV3AppendCanvasTrace([NSString stringWithFormat:@"[DirectionTrace][Client] %@", signature]);
}

static BOOL CV3RepairHostedVideoLayerTreeRecursive(CALayer *root, CGSize canvasSize) {
    if (!root || canvasSize.width <= canvasSize.height) return NO;

    __block BOOL repaired = NO;
    for (CALayer *child in root.sublayers ?: @[]) {
        CGSize parentSize = child.superlayer.bounds.size;
        CGSize childSize = child.bounds.size;
        BOOL parentMatchesCanvas = fabs(parentSize.width - canvasSize.width) <= 1.0 &&
            fabs(parentSize.height - canvasSize.height) <= 1.0;
        BOOL childIsTransposedCanvas = fabs(childSize.width - canvasSize.height) <= 1.0 &&
            fabs(childSize.height - canvasSize.width) <= 1.0;
        if ([child isKindOfClass:AVPlayerLayer.class] && parentMatchesCanvas && childIsTransposedCanvas) {
            child.frame = child.superlayer.bounds;
            [child setNeedsLayout];
            [child layoutIfNeeded];
            CV3AppendCanvasTrace([NSString stringWithFormat:
                @"[DEBUG-canvas-repair] AVPlayerLayer %@ -> %@ parent=%@ videoGravity=%@",
                NSStringFromCGSize(childSize), NSStringFromCGSize(child.bounds.size),
                NSStringFromCGSize(parentSize), ((AVPlayerLayer *)child).videoGravity]);
            repaired = YES;
        }
        repaired |= CV3RepairHostedVideoLayerTreeRecursive(child, canvasSize);
    }
    return repaired;
}

static BOOL CV3RepairHostedVideoLayerTree(CALayer *root, CGSize canvasSize) {
    if (!root || canvasSize.width <= canvasSize.height) return NO;

    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    BOOL repaired = CV3RepairHostedVideoLayerTreeRecursive(root, canvasSize);
    if (repaired) {
        uint64_t committedGeometry = ((uint64_t)llround(canvasSize.width) << 16) |
            (uint64_t)llround(canvasSize.height) | CV3CanvasReadyFlag;
        [CATransaction setCompletionBlock:^{
            // Publish readiness only after the corrected AVPlayerLayer frame
            // has reached Core Animation. This lets the host reveal the first
            // real frame without an arbitrary safety delay.
            if (CV3ApplicationIsChevronHosted && CV3CanvasNotificationToken >= 0) {
                notify_set_state(CV3CanvasNotificationToken, committedGeometry);
                if (CV3CanvasNotificationName.length > 0) {
                    notify_post(CV3CanvasNotificationName.UTF8String);
                }
            }
        }];
    }
    [CATransaction commit];
    return repaired;
}

typedef struct CV3SBIconImageInfo {
    CGSize size;
    CGFloat scale;
    CGFloat continuousCornerRadius;
} CV3SBIconImageInfo;

@interface UIImage (CV3GlobalIconPrivate)
+ (UIImage *)_applicationIconImageForBundleIdentifier:(NSString *)bundleIdentifier
                                               format:(NSInteger)format
                                                scale:(CGFloat)scale;
+ (UIImage *)_iconForResourceProxy:(id)applicationProxy format:(NSInteger)format;
- (UIImage *)_applicationIconImageForFormat:(NSInteger)format
                                precomposed:(BOOL)precomposed
                                      scale:(CGFloat)scale;
@end

static const CGFloat CV3GlobalApplicationIconScale = 0.95;
static const void *CV3ScaledApplicationIconKey = &CV3ScaledApplicationIconKey;
static __thread NSUInteger CV3ApplicationIconScalingDepth = 0;

static UIImage *CV3ScaleApplicationIconImage(UIImage *image) {
    if (![image isKindOfClass:[UIImage class]] || CV3ApplicationIconScalingDepth > 0) return image;
    if (image.size.width <= 0.0 || image.size.height <= 0.0) return image;
    if ([objc_getAssociatedObject(image, CV3ScaledApplicationIconKey) boolValue]) return image;

    CGSize canvasSize = image.size;
    CGSize scaledSize = CGSizeMake(canvasSize.width * CV3GlobalApplicationIconScale,
                                   canvasSize.height * CV3GlobalApplicationIconScale);
    CGRect drawRect = CGRectMake((canvasSize.width - scaledSize.width) * 0.5,
                                 (canvasSize.height - scaledSize.height) * 0.5,
                                 scaledSize.width,
                                 scaledSize.height);

    __block UIImage *scaledImage = nil;
    __block BOOL contextStarted = NO;
    CV3ApplicationIconScalingDepth++;
    @try {
        UIGraphicsBeginImageContextWithOptions(canvasSize, NO, image.scale > 0.0 ? image.scale : 0.0);
        contextStarted = YES;
        [image drawInRect:drawRect];
        scaledImage = UIGraphicsGetImageFromCurrentImageContext();
        UIGraphicsEndImageContext();
        contextStarted = NO;
    } @catch (__unused NSException *exception) {
        if (contextStarted) UIGraphicsEndImageContext();
        scaledImage = nil;
    } @finally {
        CV3ApplicationIconScalingDepth--;
    }
    if (!scaledImage) return image;

    scaledImage = [scaledImage imageWithRenderingMode:image.renderingMode];
    objc_setAssociatedObject(scaledImage, CV3ScaledApplicationIconKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return scaledImage;
}

typedef NS_ENUM(uint8_t, CV3PlaybackTraceEvent) {
    CV3PlaybackTraceBridgeLoaded = 1,
    CV3PlaybackTraceHostedEnabled = 2,
    CV3PlaybackTraceHostedDisabled = 3,
    CV3PlaybackTraceShieldEnabled = 4,
    CV3PlaybackTraceShieldDisabled = 5,
    CV3PlaybackTraceApplicationWillResign = 10,
    CV3PlaybackTraceApplicationDidEnterBackground = 11,
    CV3PlaybackTraceSceneWillResign = 12,
    CV3PlaybackTraceSceneDidEnterBackground = 13,
    CV3PlaybackTraceLifecycleMultiplexer = 14,
    CV3PlaybackTraceLifecycleNotification = 15,
    CV3PlaybackTraceAudioSessionDeactivate = 20,
    CV3PlaybackTraceAudioSessionDeactivateWithOptions = 21,
    CV3PlaybackTraceAudioInterruption = 22,
    CV3PlaybackTraceAVPlayerPause = 30,
    CV3PlaybackTraceAVPlayerRateZero = 31,
    CV3PlaybackTraceAVPlayerTimedRateZero = 32,
    CV3PlaybackTraceAVAudioPlayerPause = 33,
    CV3PlaybackTraceAVAudioPlayerStop = 34,
};

static BOOL CV3ControllerLikelyOwnsFullscreenVideo(UIViewController *controller);
static void CV3InstallLifecycleDelegateHooks(void);
static void CV3InstallHostedAppHooksIfNeeded(void);

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

static void CV3PostPlaybackTrace(CV3PlaybackTraceEvent event) {
    NSString *bundleID = [NSBundle mainBundle].bundleIdentifier;
    if (bundleID.length == 0) return;
    if (CV3PlaybackTraceNotificationToken < 0 &&
        notify_register_check(CV3PlaybackTraceNotification,
                              &CV3PlaybackTraceNotificationToken) != NOTIFY_STATUS_OK) {
        CV3PlaybackTraceNotificationToken = -1;
        return;
    }
    uint64_t state = (((uint64_t)event) << 56) | CV3StableBundleHash(bundleID);
    notify_set_state(CV3PlaybackTraceNotificationToken, state);
    notify_post(CV3PlaybackTraceNotification);
}

static NSString *CV3BridgeReadyNotificationName(void) {
    NSString *bundleID = [NSBundle mainBundle].bundleIdentifier;
    if (bundleID.length == 0) return nil;
    return [NSString stringWithFormat:@"com.xu.chevronv3.bridge-ready.%014llx",
                                      CV3StableBundleHash(bundleID)];
}

static void CV3PublishBridgeReadyState(void) {
    NSString *name = CV3BridgeReadyNotificationName();
    if (name.length == 0) return;

    int token = -1;
    if (notify_register_check(name.UTF8String, &token) != NOTIFY_STATUS_OK) return;
    notify_set_state(token, CV3ClientBridgeProtocolVersion);
    notify_post(name.UTF8String);
    notify_cancel(token);
}

static void CV3RefreshHostedState(int token) {
    uint64_t state = 0;
    if (token >= 0 && notify_get_state(token, &state) == NOTIFY_STATUS_OK) {
        uint64_t hostGeneration = 0;
        int generationToken = -1;
        if (notify_register_check(CV3HostGenerationNotification, &generationToken) == NOTIFY_STATUS_OK) {
            notify_get_state(generationToken, &hostGeneration);
            notify_cancel(generationToken);
        }
        uint32_t stateGeneration = (uint32_t)(state >> 32);
        uint32_t currentGeneration = (uint32_t)hostGeneration;
        uint64_t flags = (stateGeneration != 0 && stateGeneration == currentGeneration)
            ? (state & 0xFFFFFFFFULL)
            : 0;
        BOOL previousShield = CV3WorkspaceTransitionShieldActive;
        BOOL previousHosted = CV3ApplicationIsChevronHosted;
        CV3ApplicationIsChevronHosted = (flags & 1) != 0;
        CV3WorkspaceTransitionShieldActive = (flags & 2) != 0;
        if (previousHosted != CV3ApplicationIsChevronHosted) {
            [CV3CanvasTimer invalidate];
            CV3CanvasTimer = nil;
            CV3LastClientDirectionSignature = nil;
            CV3LastClientReceptionSignature = nil;
            if (CV3ApplicationIsChevronHosted) {
                CV3MetalDrawableRequestCount = 0;
                CV3VideoPixelBufferCopyCount = 0;
                CV3LastMetalDrawableRequestTime = 0;
                CV3LastVideoPixelBufferCopyTime = 0;
            }
            CV3RecordClientReceptionTrace(CV3ApplicationIsChevronHosted ? @"hosted.begin" : @"hosted.end", YES);
            NSString *canvasName = [NSString stringWithFormat:@"com.xu.chevronv3.canvas.%@", NSBundle.mainBundle.bundleIdentifier];
            if (CV3CanvasNotificationToken < 0 || ![CV3CanvasNotificationName isEqualToString:canvasName]) {
                if (CV3CanvasNotificationToken >= 0) notify_cancel(CV3CanvasNotificationToken);
                CV3CanvasNotificationToken = -1;
                CV3CanvasNotificationName = [canvasName copy];
                notify_register_check(canvasName.UTF8String, &CV3CanvasNotificationToken);
            }
            if (CV3CanvasNotificationToken >= 0) {
                notify_set_state(CV3CanvasNotificationToken, 0);
            }
            if (CV3ApplicationIsChevronHosted) {
                CV3CanvasTimer = [NSTimer timerWithTimeInterval:0.15 repeats:YES block:^(NSTimer *timer) {
                    uint64_t geometry = 0;
                    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
                        if (![scene isKindOfClass:UIWindowScene.class]) continue;
                        for (UIWindow *window in ((UIWindowScene *)scene).windows) {
                            if (window.hidden || window.alpha < 0.01 || !window.rootViewController) continue;
                            if (window.windowLevel != UIWindowLevelNormal) continue;
                            CGSize size = window.bounds.size;
                            CGSize rootSize = window.rootViewController.viewIfLoaded.bounds.size;
                            BOOL repairedVideoLayer = CV3RepairHostedVideoLayerTree(window.layer, size);
                            uint64_t sampledGeometry = ((uint64_t)llround(size.width) << 16) |
                                (uint64_t)llround(size.height);
                            if (!repairedVideoLayer &&
                                fabs(size.width - rootSize.width) <= 1 &&
                                fabs(size.height - rootSize.height) <= 1) {
                                sampledGeometry |= CV3CanvasReadyFlag;
                            }
                            CV3RecordClientDirectionTrace((UIWindowScene *)scene, window,
                                                          repairedVideoLayer, sampledGeometry, NO);
                            if (fabs(size.width - rootSize.width) > 1 || fabs(size.height - rootSize.height) > 1) continue;
                            geometry = ((uint64_t)llround(size.width) << 16) | (uint64_t)llround(size.height);
                            // If no transposed video layer needed repair, the
                            // current layer tree is already safe to reveal. A
                            // repaired tree publishes the ready bit from the CA
                            // transaction completion block above instead.
                            if (!repairedVideoLayer) geometry |= CV3CanvasReadyFlag;
                            break;
                        }
                        if (geometry) break;
                    }
                    // Keep a registered token alive for the lifetime of the
                    // client. Darwin notification state is tied to registered
                    // names and can disappear when the last transient token is
                    // cancelled before SpringBoard reads it.
                    if (CV3CanvasNotificationToken >= 0) {
                        notify_set_state(CV3CanvasNotificationToken, geometry);
                    }
                    CV3RecordClientReceptionTrace(@"timer", NO);
                }];
                [[NSRunLoop mainRunLoop] addTimer:CV3CanvasTimer forMode:NSRunLoopCommonModes];
                // Unity-style game loops may never enter the default run-loop
                // mode during startup. Publish the first sample immediately so
                // the host does not remain stuck at a synthetic 0x0 canvas.
                [CV3CanvasTimer fire];
            }
            CV3PostPlaybackTrace(CV3ApplicationIsChevronHosted
                                 ? CV3PlaybackTraceHostedEnabled
                                 : CV3PlaybackTraceHostedDisabled);
        }
        if (previousShield != CV3WorkspaceTransitionShieldActive) {
            CV3PostPlaybackTrace(CV3WorkspaceTransitionShieldActive
                                 ? CV3PlaybackTraceShieldEnabled
                                 : CV3PlaybackTraceShieldDisabled);
        }
        NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
        if (!CV3ApplicationIsChevronHosted) {
            CV3PlaybackTransitionGraceDeadline = 0;
            CV3RequestedInterfaceOrientation = UIInterfaceOrientationUnknown;
            CV3VideoOrientationOwner = nil;
            CV3OrientationBeforeVideo = UIInterfaceOrientationUnknown;
        } else if (CV3WorkspaceTransitionShieldActive) {
            CV3PlaybackTransitionGraceDeadline = now + 60.0;
        } else if (previousShield) {
            // Some apps enqueue their player pause after the lifecycle callback
            // has returned. Cover that tail without affecting later user input.
            CV3PlaybackTransitionGraceDeadline = now + 0.85;
        }
        if (CV3ApplicationIsChevronHosted) {
            CV3InstallHostedAppHooksIfNeeded();
            dispatch_async(dispatch_get_main_queue(), ^{
                CV3InstallLifecycleDelegateHooks();
            });
        }
    }
}

static BOOL CV3ShouldProtectHostedPlayback(void) {
    // The hosted-state lease already excludes stashed and closing windows.
    // Keep lifecycle/playback protection active for that whole lease instead
    // of relying on transition callbacks, which miss some iOS 16 paths.
    return CV3ApplicationIsChevronHosted;
}

static BOOL CV3IsLifecycleDeactivationNotification(NSNotificationName name) {
    if (name.length == 0) return NO;
    return [name isEqualToString:UIApplicationWillResignActiveNotification] ||
           [name isEqualToString:UIApplicationDidEnterBackgroundNotification] ||
           [name isEqualToString:UISceneWillDeactivateNotification] ||
           [name isEqualToString:UISceneDidEnterBackgroundNotification];
}

static BOOL CV3IsLifecycleTraceNotification(NSNotificationName name) {
    if (CV3IsLifecycleDeactivationNotification(name)) return YES;
    return [name isEqualToString:UIApplicationDidBecomeActiveNotification] ||
           [name isEqualToString:UIApplicationWillEnterForegroundNotification] ||
           [name isEqualToString:UISceneDidActivateNotification] ||
           [name isEqualToString:UISceneWillEnterForegroundNotification];
}

static BOOL CV3IsAppSuspensionAudioInterruption(NSDictionary *userInfo) {
    // 使用运行时键名兼容 iOS 14.0；SDK 中对应常量从 14.5 才可用。
    NSNumber *reason = userInfo[@"AVAudioSessionInterruptionReasonKey"];
    NSNumber *wasSuspended = userInfo[@"AVAudioSessionInterruptionWasSuspendedKey"];
    return reason.unsignedIntegerValue == 1 || wasSuspended.boolValue;
}

static BOOL CV3ShouldSuppressHostedAudioInterruption(NSNotificationName name,
                                                       NSDictionary *userInfo) {
    if (!CV3ApplicationIsChevronHosted ||
        ![name isEqualToString:AVAudioSessionInterruptionNotification]) {
        return NO;
    }
    if (CV3IsAppSuspensionAudioInterruption(userInfo)) return YES;
    if (!CV3WorkspaceTransitionShieldActive) return NO;

    NSNumber *type = userInfo[AVAudioSessionInterruptionTypeKey];
    return !type || type.unsignedIntegerValue == AVAudioSessionInterruptionTypeBegan;
}

static NSMutableDictionary<NSString *, NSValue *> *CV3LifecycleOriginalIMPs = nil;
static NSMutableSet<NSString *> *CV3InstalledLifecycleHooks = nil;

static NSString *CV3LifecycleHookKey(Class cls, SEL selector) {
    return [NSString stringWithFormat:@"%@::%@", NSStringFromClass(cls), NSStringFromSelector(selector)];
}

static IMP CV3OriginalLifecycleIMPForObject(id object, SEL selector) {
    for (Class cls = object_getClass(object); cls; cls = class_getSuperclass(cls)) {
        NSValue *value = CV3LifecycleOriginalIMPs[CV3LifecycleHookKey(cls, selector)];
        if (value) return (IMP)value.pointerValue;
    }
    return NULL;
}

static void CV3LifecycleDelegateReplacement(id self, SEL selector, id context) {
    if (CV3ShouldProtectHostedPlayback()) {
        if (selector == @selector(applicationWillResignActive:)) {
            CV3PostPlaybackTrace(CV3PlaybackTraceApplicationWillResign);
        } else if (selector == @selector(applicationDidEnterBackground:)) {
            CV3PostPlaybackTrace(CV3PlaybackTraceApplicationDidEnterBackground);
        } else if (selector == @selector(sceneWillResignActive:)) {
            CV3PostPlaybackTrace(CV3PlaybackTraceSceneWillResign);
        } else if (selector == @selector(sceneDidEnterBackground:)) {
            CV3PostPlaybackTrace(CV3PlaybackTraceSceneDidEnterBackground);
        }
        return;
    }

    IMP original = CV3OriginalLifecycleIMPForObject(self, selector);
    if (original) ((void (*)(id, SEL, id))original)(self, selector, context);
}

static void CV3HookLifecycleDelegateObject(id delegate) {
    if (!delegate) return;
    if (!CV3LifecycleOriginalIMPs) CV3LifecycleOriginalIMPs = [NSMutableDictionary dictionary];
    if (!CV3InstalledLifecycleHooks) CV3InstalledLifecycleHooks = [NSMutableSet set];

    NSArray<NSString *> *selectorNames = @[
        @"applicationWillResignActive:",
        @"applicationDidEnterBackground:",
        @"sceneWillResignActive:",
        @"sceneDidEnterBackground:"
    ];
    Class cls = object_getClass(delegate);
    for (NSString *selectorName in selectorNames) {
        SEL selector = NSSelectorFromString(selectorName);
        if (![delegate respondsToSelector:selector]) continue;

        NSString *key = CV3LifecycleHookKey(cls, selector);
        if ([CV3InstalledLifecycleHooks containsObject:key]) continue;

        IMP original = NULL;
        MSHookMessageEx(cls, selector, (IMP)CV3LifecycleDelegateReplacement, &original);
        if (original) {
            CV3LifecycleOriginalIMPs[key] = [NSValue valueWithPointer:(const void *)original];
            [CV3InstalledLifecycleHooks addObject:key];
        }
    }
}

static void CV3InstallLifecycleDelegateHooks(void) {
    UIApplication *application = [UIApplication sharedApplication];
    CV3HookLifecycleDelegateObject(application.delegate);
    for (UIScene *scene in application.connectedScenes) {
        CV3HookLifecycleDelegateObject(scene.delegate);
    }
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

    CFTimeInterval now = CACurrentMediaTime();
    BOOL leavingLandscape = UIInterfaceOrientationIsLandscape(CV3RequestedInterfaceOrientation) &&
        UIInterfaceOrientationIsPortrait(orientation);
    if (leavingLandscape) {
        // Full-screen player dismissal commonly emits one stale landscape
        // geometry/controller callback immediately after its portrait restore.
        // Forwarding that callback makes the host reopen the just-dismissed
        // full-screen presentation and can form a portrait/landscape loop.
        CV3LandscapeReentrySuppressedUntil = now + 1.5;
    } else if (UIInterfaceOrientationIsLandscape(orientation) &&
               now < CV3LandscapeReentrySuppressedUntil) {
        return;
    }
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
    if (!CV3ApplicationIsChevronHosted || !controller) return;

    @try {
        if (!controller.viewIfLoaded.window) return;
    } @catch (__unused NSException *exception) {
        return;
    }

    UIInterfaceOrientation preferredOrientation = UIInterfaceOrientationUnknown;
    UIInterfaceOrientationMask supportedOrientations = UIInterfaceOrientationMaskPortrait;
    @try {
        preferredOrientation = controller.preferredInterfaceOrientationForPresentation;
        supportedOrientations = controller.supportedInterfaceOrientations;
    } @catch (__unused NSException *exception) {
        return;
    }

    UIInterfaceOrientation orientation = CV3InterfaceOrientationForMask(supportedOrientations,
                                                                         preferredOrientation);
    if (UIInterfaceOrientationIsLandscape(orientation) && CV3ControllerLikelyOwnsFullscreenVideo(controller)) {
        if (!CV3VideoOrientationOwner) {
            CV3OrientationBeforeVideo = controller.viewIfLoaded.window.windowScene.interfaceOrientation;
        }
        CV3VideoOrientationOwner = controller;
        CV3PostVideoOrientation(orientation);
    } else if (CV3VideoOrientationOwner == controller) {
        CV3VideoOrientationOwner = nil;
        CV3PostVideoOrientation(CV3OrientationBeforeVideo);
        CV3OrientationBeforeVideo = UIInterfaceOrientationUnknown;
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

%group CV3HostedAppHooks

%hook CAMetalLayer
- (id)nextDrawable {
    if (CV3ApplicationIsChevronHosted) {
        __sync_add_and_fetch(&CV3MetalDrawableRequestCount, 1);
        CV3LastMetalDrawableRequestTime = CACurrentMediaTime();
    }
    return %orig;
}
%end

%hook AVPlayerItemVideoOutput
- (CVPixelBufferRef)copyPixelBufferForItemTime:(CMTime)itemTime
                           itemTimeForDisplay:(CMTime *)outItemTimeForDisplay {
    CVPixelBufferRef buffer = %orig(itemTime, outItemTimeForDisplay);
    if (CV3ApplicationIsChevronHosted && buffer) {
        __sync_add_and_fetch(&CV3VideoPixelBufferCopyCount, 1);
        CV3LastVideoPixelBufferCopyTime = CACurrentMediaTime();
    }
    return buffer;
}
%end

%hook UIWindowScene
- (void)requestGeometryUpdateWithPreferences:(id)preferences errorHandler:(id)errorHandler {
    SEL selector = NSSelectorFromString(@"interfaceOrientations");
    if (CV3ApplicationIsChevronHosted && preferences && [preferences respondsToSelector:selector]) {
        UIInterfaceOrientationMask mask = ((UIInterfaceOrientationMask (*)(id, SEL))objc_msgSend)(preferences, selector);
        CV3PostVideoOrientation(CV3InterfaceOrientationForMask(mask, UIInterfaceOrientationUnknown));
    }
    %orig(preferences, errorHandler);
}
%end

%hook UIViewController
- (void)setNeedsUpdateOfSupportedInterfaceOrientations {
    %orig;
    if (!CV3ApplicationIsChevronHosted) return;
    __weak UIViewController *weakController = self;
    dispatch_async(dispatch_get_main_queue(), ^{
        UIViewController *controller = weakController;
        if (controller) CV3PostOrientationForController(controller);
    });
}

- (void)viewDidAppear:(BOOL)animated {
    %orig(animated);
    CV3PostOrientationForController(self);
}

- (void)viewDidDisappear:(BOOL)animated {
    %orig(animated);
    if (CV3VideoOrientationOwner == self) {
        CV3VideoOrientationOwner = nil;
        CV3PostVideoOrientation(CV3OrientationBeforeVideo);
        CV3OrientationBeforeVideo = UIInterfaceOrientationUnknown;
    }
}
%end

%hook UIDevice
- (void)setValue:(id)value forKey:(NSString *)key {
    if (CV3ApplicationIsChevronHosted &&
        [key isEqualToString:@"orientation"] &&
        [value respondsToSelector:@selector(integerValue)]) {
        CV3PostVideoOrientation(CV3InterfaceOrientationForDeviceOrientation((UIDeviceOrientation)[value integerValue]));
    }
    %orig(value, key);
}
%end

%hook AVAudioSession
- (BOOL)setActive:(BOOL)active error:(NSError **)outError {
    if (!active && CV3ShouldProtectHostedPlayback()) {
        CV3PostPlaybackTrace(CV3PlaybackTraceAudioSessionDeactivate);
        return YES;
    }
    return %orig(active, outError);
}

- (BOOL)setActive:(BOOL)active withOptions:(AVAudioSessionSetActiveOptions)options error:(NSError **)outError {
    if (!active && CV3ShouldProtectHostedPlayback()) {
        CV3PostPlaybackTrace(CV3PlaybackTraceAudioSessionDeactivateWithOptions);
        return YES;
    }
    return %orig(active, options, outError);
}
%end

%hook AVPlayer
- (void)pause {
    if (CV3ApplicationIsChevronHosted) CV3PostPlaybackTrace(CV3PlaybackTraceAVPlayerPause);
    if (CV3ApplicationIsChevronHosted) CV3RecordClientReceptionTrace(@"AVPlayer.pause.before", YES);
    if (CV3ShouldProtectHostedPlayback()) {
        return;
    }
    %orig;
    if (CV3ApplicationIsChevronHosted) {
        dispatch_async(dispatch_get_main_queue(), ^{ CV3RecordClientReceptionTrace(@"AVPlayer.pause.after", YES); });
    }
}

- (void)setRate:(float)rate {
    if (rate == 0.0f && CV3ApplicationIsChevronHosted) CV3PostPlaybackTrace(CV3PlaybackTraceAVPlayerRateZero);
    if (rate == 0.0f && CV3ApplicationIsChevronHosted) CV3RecordClientReceptionTrace(@"AVPlayer.setRateZero.before", YES);
    if (rate == 0.0f && CV3ShouldProtectHostedPlayback()) return;
    %orig(rate);
    if (rate == 0.0f && CV3ApplicationIsChevronHosted) {
        dispatch_async(dispatch_get_main_queue(), ^{ CV3RecordClientReceptionTrace(@"AVPlayer.setRateZero.after", YES); });
    }
}

- (void)setRate:(float)rate time:(CMTime)itemTime atHostTime:(CMTime)hostClockTime {
    if (rate == 0.0f && CV3ApplicationIsChevronHosted) CV3PostPlaybackTrace(CV3PlaybackTraceAVPlayerTimedRateZero);
    if (rate == 0.0f && CV3ApplicationIsChevronHosted) CV3RecordClientReceptionTrace(@"AVPlayer.setTimedRateZero.before", YES);
    if (rate == 0.0f && CV3ShouldProtectHostedPlayback()) return;
    %orig(rate, itemTime, hostClockTime);
    if (rate == 0.0f && CV3ApplicationIsChevronHosted) {
        dispatch_async(dispatch_get_main_queue(), ^{ CV3RecordClientReceptionTrace(@"AVPlayer.setTimedRateZero.after", YES); });
    }
}
%end

%hook AVAudioPlayer
- (void)pause {
    if (CV3ApplicationIsChevronHosted) CV3PostPlaybackTrace(CV3PlaybackTraceAVAudioPlayerPause);
    if (CV3ShouldProtectHostedPlayback()) return;
    %orig;
}

- (void)stop {
    if (CV3ApplicationIsChevronHosted) CV3PostPlaybackTrace(CV3PlaybackTraceAVAudioPlayerStop);
    if (CV3ShouldProtectHostedPlayback()) return;
    %orig;
}
%end

%hook UIApplication
- (void)setDelegate:(id)delegate {
    %orig(delegate);
    CV3HookLifecycleDelegateObject(delegate);
}

- (UIApplicationState)applicationState {
    if (CV3ShouldProtectHostedPlayback()) {
        return UIApplicationStateActive;
    }
    return %orig;
}
%end

%hook UIScene
- (void)setDelegate:(id)delegate {
    %orig(delegate);
    CV3HookLifecycleDelegateObject(delegate);
}

- (UISceneActivationState)activationState {
    if (CV3ShouldProtectHostedPlayback()) {
        return UISceneActivationStateForegroundActive;
    }
    return %orig;
}
%end

%hook _UISceneLifecycleMultiplexer
- (void)_performBlock:(id)block
withApplicationOfDeactivationReasons:(NSUInteger)reasons
          fromReasons:(NSUInteger)fromReasons {
    if (CV3ShouldProtectHostedPlayback() && reasons != 0) {
        CV3PostPlaybackTrace(CV3PlaybackTraceLifecycleMultiplexer);
        return;
    }
    %orig(block, reasons, fromReasons);
}
%end

%hook NSNotificationCenter
- (void)postNotification:(NSNotification *)notification {
    if (CV3IsLifecycleTraceNotification(notification.name)) {
        CV3RecordClientReceptionLifecycleEvent(notification.name);
    }
    if (CV3ShouldProtectHostedPlayback() &&
        CV3IsLifecycleDeactivationNotification(notification.name)) {
        CV3PostPlaybackTrace(CV3PlaybackTraceLifecycleNotification);
        return;
    }
    if (CV3ShouldSuppressHostedAudioInterruption(notification.name, notification.userInfo)) {
        CV3PostPlaybackTrace(CV3PlaybackTraceAudioInterruption);
        return;
    }
    %orig(notification);
}

- (void)postNotificationName:(NSNotificationName)name object:(id)object {
    if (CV3IsLifecycleTraceNotification(name)) {
        CV3RecordClientReceptionLifecycleEvent(name);
    }
    if (CV3ShouldProtectHostedPlayback() &&
        CV3IsLifecycleDeactivationNotification(name)) {
        CV3PostPlaybackTrace(CV3PlaybackTraceLifecycleNotification);
        return;
    }
    %orig(name, object);
}

- (void)postNotificationName:(NSNotificationName)name object:(id)object userInfo:(NSDictionary *)userInfo {
    if (CV3IsLifecycleTraceNotification(name)) {
        CV3RecordClientReceptionLifecycleEvent(name);
    }
    if (CV3ShouldProtectHostedPlayback() &&
        CV3IsLifecycleDeactivationNotification(name)) {
        CV3PostPlaybackTrace(CV3PlaybackTraceLifecycleNotification);
        return;
    }
    if (CV3ShouldSuppressHostedAudioInterruption(name, userInfo)) {
        CV3PostPlaybackTrace(CV3PlaybackTraceAudioInterruption);
        return;
    }
    %orig(name, object, userInfo);
}
%end

%end

static BOOL CV3HostedAppHooksInstalled = NO;

static void CV3InstallHostedAppHooksIfNeeded(void) {
    if (CV3HostedAppHooksInstalled) return;
    CV3HostedAppHooksInstalled = YES;
    %init(CV3HostedAppHooks);
    dispatch_async(dispatch_get_main_queue(), ^{
        CV3InstallLifecycleDelegateHooks();
    });
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.75 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        CV3InstallLifecycleDelegateHooks();
    });
}

%group CV3GlobalIconImageHooks
%hook UIImage
+ (UIImage *)_applicationIconImageForBundleIdentifier:(NSString *)bundleIdentifier
                                               format:(NSInteger)format
                                                scale:(CGFloat)scale {
    return CV3ScaleApplicationIconImage(%orig(bundleIdentifier, format, scale));
}

+ (UIImage *)_iconForResourceProxy:(id)applicationProxy format:(NSInteger)format {
    return CV3ScaleApplicationIconImage(%orig(applicationProxy, format));
}

- (UIImage *)_applicationIconImageForFormat:(NSInteger)format
                                precomposed:(BOOL)precomposed
                                      scale:(CGFloat)scale {
    return CV3ScaleApplicationIconImage(%orig(format, precomposed, scale));
}
%end

%end

%group CV3SpringBoardIconImageHooks
%hook SBIcon
- (UIImage *)generateIconImage:(NSInteger)type {
    return CV3ScaleApplicationIconImage(%orig(type));
}

- (UIImage *)generateIconImageWithInfo:(CV3SBIconImageInfo)imageInfo {
    return CV3ScaleApplicationIconImage(%orig(imageInfo));
}

- (UIImage *)getIconImage:(NSInteger)variant {
    return CV3ScaleApplicationIconImage(%orig(variant));
}

- (UIImage *)getUnmaskedIconImage:(NSInteger)variant {
    return CV3ScaleApplicationIconImage(%orig(variant));
}
%end
%end

%ctor {
    @autoreleasepool {
        %init(CV3GlobalIconImageHooks);

        NSString *processBundleID = [NSBundle mainBundle].bundleIdentifier.lowercaseString;
        if ([processBundleID isEqualToString:@"com.apple.springboard"]) {
            if (NSClassFromString(@"SBIcon")) %init(CV3SpringBoardIconImageHooks);
            return;
        }
        if (processBundleID.length == 0) {
            return;
        }
        CV3PostPlaybackTrace(CV3PlaybackTraceBridgeLoaded);
        CV3PublishBridgeReadyState();
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
        notify_register_dispatch(CV3HostGenerationNotification,
                                 &CV3HostGenerationNotificationToken,
                                 dispatch_get_main_queue(),
                                 ^(__unused int token) {
            CV3RefreshHostedState(CV3HostedStateNotificationToken);
        });
    }
}
