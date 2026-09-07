static void CV3CascadeUpdateSovereigntyAssertions(void) {
    if (!floatingWindows || floatingWindows.count == 0) return;
    NSArray *windowsSnapshot = [floatingWindows copy];
    for (id win in windowsSnapshot) {
        if ([win isKindOfClass:[CV3FloatingAppWindow class]] && ![win isClosing]) {
            [win updateSovereigntyAssertion];
        }
    }
}

// A host UIView can survive after FrontBoard drops the Scene's real content
// layer. Match PullOver-X's stronger readiness check instead of treating any
// sublayer as proof that the client is still drawable.
static NSString *CV3DirectionTraceView(UIView *view);

static BOOL CV3SceneHasRenderableMainLayer(FBScene *scene) {
    if (!scene) return NO;

    id layerManager = nil;
    @try {
        if ([scene respondsToSelector:@selector(layerManager)]) {
            layerManager = ((id (*)(id, SEL))objc_msgSend)(scene, @selector(layerManager));
        } else {
            layerManager = [scene valueForKey:@"_layerManager"];
        }
    } @catch (__unused NSException *exception) {
        return NO;
    }
    if (!layerManager) return NO;

    id rawLayers = nil;
    @try {
        if ([layerManager respondsToSelector:@selector(layers)]) {
            rawLayers = ((id (*)(id, SEL))objc_msgSend)(layerManager, @selector(layers));
        }
    } @catch (__unused NSException *exception) {
        return NO;
    }

    NSArray *layers = [rawLayers isKindOfClass:[NSArray class]]
        ? rawLayers
        : ([rawLayers respondsToSelector:@selector(array)] ? [rawLayers array] : nil);
    if (![layers isKindOfClass:[NSArray class]]) return NO;

    for (id layer in layers) {
        @try {
            BOOL keyboardLayer = [layer respondsToSelector:@selector(isKeyboardLayer)] &&
                ((BOOL (*)(id, SEL))objc_msgSend)(layer, @selector(isKeyboardLayer));
            id externalSceneID = [layer respondsToSelector:@selector(externalSceneID)]
                ? ((id (*)(id, SEL))objc_msgSend)(layer, @selector(externalSceneID))
                : nil;
            if (!keyboardLayer && !externalSceneID) return YES;
        } @catch (__unused NSException *exception) {}
    }
    return NO;
}

// Return the first live remote CA context carried by a host hierarchy.  The
// value is intentionally read from the layer tree instead of the presentation
// context object: the latter can exist before FrontBoard has published a new
// CALayerHost and was the source of the false-positive readiness in v70.
static NSString *CV3HostedLayerContextID(CALayer *layer) {
    if (!layer) return nil;
    for (NSString *key in @[@"contextId", @"_contextId"]) {
        @try {
            id value = [layer valueForKey:key];
            if ([value respondsToSelector:@selector(unsignedLongLongValue)] &&
                [value unsignedLongLongValue] != 0) {
                return [value description];
            }
        } @catch (__unused NSException *exception) {}
    }
    for (CALayer *child in layer.sublayers) {
        NSString *value = CV3HostedLayerContextID(child);
        if (value.length > 0) return value;
    }
    return nil;
}

static void CV3StashPeerWindowsForFullscreen(CV3FloatingAppWindow *activeWindow) {
    if (!activeWindow || !floatingWindows || floatingWindows.count <= 1) return;

    NSArray *windowsSnapshot = [floatingWindows copy];
    for (id obj in windowsSnapshot) {
        if (![obj isKindOfClass:[CV3FloatingAppWindow class]]) continue;
        CV3FloatingAppWindow *win = (CV3FloatingAppWindow *)obj;
        if (win == activeWindow || win.isClosing || win.isStashed) continue;
        [win handleHideAction];
    }

    [activeWindow promoteFloatingWindowInZOrder];
    [activeWindow makeKeyAndVisible];
    activeWindow.windowLevel = CV3Style.floatingApp;
    [activeWindow setWindowFocused:YES];
}
static const CGFloat kCV3RotationCascadeStep = 20.0;
static const CGFloat kCV3StashIconSize = 54.0;
static const CGFloat kCV3StashIconInset = 7.0;
static const NSInteger kCV3ExposeColumnCount = 2;
static const CGFloat kCV3ExposeOuterPadding = 20.0;
static const CGFloat kCV3ExposeInterItemSpacing = 14.0;
static const CGFloat kCV3ExposeMaxCellWidthRatio = 0.40;
static const CGFloat kCV3ExposeMaxCellHeightRatio = 0.42;
static const CGFloat kCV3ExposeCardCornerRadius = 22.0;
static const CGFloat kCV3ExposeCardShadowOpacity = 0.22;
static const CGFloat kCV3ExposeCardShadowRadius = 20.0;
static const CGFloat kCV3ExposeCardSelectedScale = 1.03;
static const CGFloat kCV3FloatingDefaultWidthRatio = 0.45;

static CGRect CV3DisplayBoundsForWindow(UIWindow *window) {
    if (window.windowScene) {
        CGRect sceneBounds = window.windowScene.coordinateSpace.bounds;
        if (!CGRectIsEmpty(sceneBounds)) {
            return sceneBounds;
        }
    }
    if (window.screen) {
        CGRect screenBounds = window.screen.bounds;
        if (!CGRectIsEmpty(screenBounds)) {
            return screenBounds;
        }
    }
    return [UIScreen mainScreen].bounds;
}

// SpringBoard can keep a portrait UIWindowScene coordinate space while the
// physical display is already landscape. In that state CoreAnimation maps the
// Scene to the display by swapping its axes. A landscape floating shell must
// therefore be portrait-shaped in Scene coordinates, then rotate its logical
// content into that shell exactly once.
static BOOL CV3SceneAndDisplayAxesDifferForScene(UIWindowScene *scene) {
    if (!scene || !scene.screen) return NO;
    CGSize sceneSize = scene.coordinateSpace.bounds.size;
    CGSize screenSize = scene.screen.bounds.size;
    if (sceneSize.width <= 0.0 || sceneSize.height <= 0.0 ||
        screenSize.width <= 0.0 || screenSize.height <= 0.0) return NO;
    BOOL sceneLandscape = sceneSize.width > sceneSize.height;
    BOOL screenLandscape = screenSize.width > screenSize.height;
    return sceneLandscape != screenLandscape;
}

static BOOL CV3SceneAndDisplayAxesDiffer(UIWindow *window) {
    return window ? CV3SceneAndDisplayAxesDifferForScene(window.windowScene) : NO;
}

static BOOL CV3ShellShouldBeLandscape(CV3FloatingAppWindow *window,
                                      UIInterfaceOrientation presentationOrientation) {
    BOOL presentationLandscape = UIInterfaceOrientationIsLandscape(presentationOrientation);
    BOOL landscapeClientNeedsSceneAxisCompensation = window.prefersLandscapePresentation &&
        window.requiresLandscapeContent && CV3SceneAndDisplayAxesDiffer(window);
    return landscapeClientNeedsSceneAxisCompensation ? !presentationLandscape : presentationLandscape;
}

static UIInterfaceOrientation CV3HostedClientOrientation(CV3FloatingAppWindow *window) {
    if (!window.targetScene) return UIInterfaceOrientationUnknown;
    id clientSettings = CV3InvokeObject(window.targetScene,
                                        NSSelectorFromString(@"clientSettings"));
    return (UIInterfaceOrientation)CV3InvokeInteger(clientSettings,
                                                     @selector(interfaceOrientation),
                                                     UIInterfaceOrientationUnknown);
}

static CGSize CV3SceneSettingsBounds(id settings) {
    SEL boundsSelector = NSSelectorFromString(@"bounds");
    if (!settings || ![settings respondsToSelector:boundsSelector]) return CGSizeZero;
    @try {
        CGRect bounds = ((CGRect (*)(id, SEL))objc_msgSend)(settings, boundsSelector);
        return bounds.size;
    } @catch (__unused NSException *exception) {
        return CGSizeZero;
    }
}

static BOOL CV3SceneSettingsBoundsMatchOrientation(id settings,
                                                    UIInterfaceOrientation orientation) {
    if (!CV3IsValidInterfaceOrientation(orientation)) return NO;
    CGSize bounds = CV3SceneSettingsBounds(settings);
    if (bounds.width <= 0.0 || bounds.height <= 0.0 ||
        fabs(bounds.width - bounds.height) <= 0.5) return NO;
    return (bounds.width > bounds.height) == UIInterfaceOrientationIsLandscape(orientation);
}

static CGAffineTransform CV3HostedContentRotationInScene(CV3FloatingAppWindow *window) {
    if (!window.prefersLandscapePresentation ||
        !UIInterfaceOrientationIsLandscape(window.hostedContentOrientation)) {
        return CGAffineTransformIdentity;
    }

    // clientSettings is the producer-side acknowledgement. Once it reaches the
    // requested orientation, UIKit has already oriented the remote Surface.
    // Rotating rootTransformContainer as well applies the presentation a second
    // time and leaves the translated client content in only half of the shell.
    UIInterfaceOrientation clientOrientation = CV3HostedClientOrientation(window);
    if (CV3IsValidInterfaceOrientation(clientOrientation)) {
        if (clientOrientation == window.hostedContentOrientation) {
            window.clientAcknowledgedOrientation = clientOrientation;
        } else if (window.clientAcknowledgedOrientation == window.hostedContentOrientation) {
            UIInterfaceOrientation staleAcknowledgement = window.clientAcknowledgedOrientation;
            window.clientAcknowledgedOrientation = UIInterfaceOrientationUnknown;
            CV3LogToFile(@"[OrientationRepair] phase=clientAckInvalidated bundle=%@ liveClient=%ld cachedAck=%ld requested=%ld",
                         window.bundleID ?: @"nil", (long)clientOrientation,
                         (long)staleAcknowledgement, (long)window.hostedContentOrientation);
        }
    }
    if (window.clientAcknowledgedOrientation == window.hostedContentOrientation) {
        return CGAffineTransformIdentity;
    }

    // The server frame remains in portrait reference coordinates, but the
    // effective Scene bounds are orientation-aware. When those bounds already
    // match the requested hosted axis, the remote surface is already laid out
    // in landscape and rotating the root again clips it to a square slice.
    id settings = window.targetScene
        ? CV3InvokeObject(window.targetScene, @selector(settings))
        : nil;
    if (CV3SceneSettingsBoundsMatchOrientation(settings, window.hostedContentOrientation)) {
        return CGAffineTransformIdentity;
    }

    UIInterfaceOrientation sceneOrientation = window.windowScene.interfaceOrientation;
    if (!CV3IsValidInterfaceOrientation(sceneOrientation)) {
        sceneOrientation = UIInterfaceOrientationPortrait;
    }
    if (sceneOrientation == window.hostedContentOrientation) {
        return CGAffineTransformIdentity;
    }
    CGAffineTransform hosted = CV3RotationTransformForInterfaceOrientation(window.hostedContentOrientation);
    CGAffineTransform scene = CV3RotationTransformForInterfaceOrientation(sceneOrientation);
    return CGAffineTransformConcat(hosted, CGAffineTransformInvert(scene));
}

static UIEdgeInsets CV3InitialFloatingSafeAreaInsets(UIWindowScene *scene) {
    UIWindow *keyWindow = nil;
    if (@available(iOS 15.0, *)) {
        keyWindow = scene.keyWindow;
    }
    UIEdgeInsets safeArea = keyWindow.safeAreaInsets;
    if (safeArea.top == 0.0 && safeArea.bottom == 0.0 &&
        safeArea.left == 0.0 && safeArea.right == 0.0) {
        safeArea = UIEdgeInsetsMake(47.0, 0.0, 34.0, 0.0);
    }
    return safeArea;
}

static CGRect CV3ClampInitialFloatingFrame(CGRect frame, CGRect bounds, UIEdgeInsets safeArea) {
    CGFloat breath = CV3Style.safeAreaBreath;
    CGFloat minX = CGRectGetMinX(bounds) + safeArea.left + breath;
    CGFloat minY = CGRectGetMinY(bounds) + safeArea.top + breath;
    CGFloat maxX = CGRectGetMaxX(bounds) - safeArea.right - breath - frame.size.width;
    CGFloat maxY = CGRectGetMaxY(bounds) - safeArea.bottom - breath - frame.size.height;
    if (maxX < minX) maxX = minX;
    if (maxY < minY) maxY = minY;
    frame.origin.x = MIN(MAX(frame.origin.x, minX), maxX);
    frame.origin.y = MIN(MAX(frame.origin.y, minY), maxY);
    return frame;
}

static NSString *CV3WindowLayoutKey(NSString *bundleID) {
    if (bundleID.length == 0) return nil;
    return [NSString stringWithFormat:@"CV3WindowLayout.%@", bundleID];
}

static NSDictionary *CV3SavedWindowLayout(NSString *bundleID) {
    NSString *key = CV3WindowLayoutKey(bundleID);
    if (!key) return nil;
    NSDictionary *layout = [[[NSUserDefaults alloc] initWithSuiteName:@"com.xu.chevronv3"] dictionaryForKey:key];
    return [layout isKindOfClass:[NSDictionary class]] ? layout : nil;
}

static void CV3SaveWindowLayout(CV3FloatingAppWindow *window) {
    if (!window || window.bundleID.length == 0 || window.isClosing || window.isStashed) return;
    NSString *key = CV3WindowLayoutKey(window.bundleID);
    if (!key) return;

    NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:@"com.xu.chevronv3"];
    NSDictionary *layout = @{
        @"frame": NSStringFromCGRect(window.frame),
        @"orientation": @(window.targetOrientation),
        @"updatedAt": @([[NSDate date] timeIntervalSince1970])
    };
    [defaults setObject:layout forKey:key];
    [defaults synchronize];
    CV3LogToFile(@"[LayoutStore] 保存 %@ frame=%@ orientation=%ld",
                 window.bundleID, NSStringFromCGRect(window.frame), (long)window.targetOrientation);
}

static CGRect CV3CanonicalApplicationSceneFrame(id settings) {
    id displayConfiguration = nil;
    SEL displaySelector = NSSelectorFromString(@"displayConfiguration");
    if (settings && [settings respondsToSelector:displaySelector]) {
        @try {
            displayConfiguration = ((id (*)(id, SEL))objc_msgSend)(settings, displaySelector);
        } @catch (NSException *e) {}
    }
    if (!displayConfiguration && [[UIScreen mainScreen] respondsToSelector:displaySelector]) {
        @try {
            displayConfiguration = ((id (*)(id, SEL))objc_msgSend)([UIScreen mainScreen], displaySelector);
        } @catch (NSException *e) {}
    }

    SEL boundsSelector = NSSelectorFromString(@"bounds");
    if (displayConfiguration && [displayConfiguration respondsToSelector:boundsSelector]) {
        @try {
            CGRect bounds = ((CGRect (*)(id, SEL))objc_msgSend)(displayConfiguration, boundsSelector);
            if (CGRectGetWidth(bounds) > 0.0 && CGRectGetHeight(bounds) > 0.0) {
                return CGRectMake(0, 0, CGRectGetWidth(bounds), CGRectGetHeight(bounds));
            }
        } @catch (NSException *e) {}
    }

    CGSize screenSize = [UIScreen mainScreen].bounds.size;
    return CGRectMake(0, 0,
                      MIN(screenSize.width, screenSize.height),
                      MAX(screenSize.width, screenSize.height));
}

static CGSize CV3HostedCanvasSizeForOrientation(UIInterfaceOrientation orientation, id settings) {
    CGRect canonicalFrame = CV3CanonicalApplicationSceneFrame(settings);
    CGFloat shortSide = MIN(CGRectGetWidth(canonicalFrame), CGRectGetHeight(canonicalFrame));
    CGFloat longSide = MAX(CGRectGetWidth(canonicalFrame), CGRectGetHeight(canonicalFrame));
    if (shortSide <= 0.0 || longSide <= 0.0) {
        CGSize screenSize = [UIScreen mainScreen].bounds.size;
        shortSide = MIN(screenSize.width, screenSize.height);
        longSide = MAX(screenSize.width, screenSize.height);
    }
    return UIInterfaceOrientationIsLandscape(orientation)
        ? CGSizeMake(longSide, shortSide)
        : CGSizeMake(shortSide, longSide);
}

static UIInterfaceOrientation CV3HostedPresentationOrientation(CV3FloatingAppWindow *window) {
    if (!window) return UIInterfaceOrientationUnknown;
    // The destination is SpringBoard's display scene, not the hosted app.
    // Use this window's live Scene orientation even when its private session
    // role is not _UIScreenBasedSceneSession. Falling through the global
    // trusted-orientation cache can return the hosted app's landscape request
    // while SpringBoard is still portrait, causing the required cross-axis map
    // to be restored incorrectly.
    UIInterfaceOrientation sceneOrientation = window.windowScene.interfaceOrientation;
    if (CV3IsValidInterfaceOrientation(sceneOrientation)) {
        return sceneOrientation;
    }
    return CV3TrustedInterfaceOrientation(window.windowScene);
}

// PullOver chooses the initial hosted orientation from the client's declared
// orientations instead of assuming portrait. This matters before the first
// Scene transaction, when the device Scene still reports its own orientation.
static BOOL CV3BundleDeclaresLandscapeOnly(NSString *bundleID) {
    if (bundleID.length == 0) return NO;

    @try {
        Class proxyClass = CV3ClassNamed(@"LSApplicationProxy");
        SEL selector = NSSelectorFromString(@"applicationProxyForIdentifier:");
        id proxy = proxyClass && [proxyClass respondsToSelector:selector]
            ? ((id (*)(id, SEL, id))objc_msgSend)(proxyClass, selector, bundleID)
            : nil;
        NSURL *bundleURL = proxy && [proxy respondsToSelector:@selector(bundleURL)]
            ? ((id (*)(id, SEL))objc_msgSend)(proxy, @selector(bundleURL))
            : nil;
        NSDictionary *info = bundleURL ? [NSDictionary dictionaryWithContentsOfFile:[[bundleURL path] stringByAppendingPathComponent:@"Info.plist"]] : nil;
        id runtimeApp = nil;
        if (!info) {
            Class appController = CV3ClassNamed(@"SBApplicationController");
            id app = appController && [appController respondsToSelector:@selector(sharedInstance)]
                ? ((id (*)(id, SEL))objc_msgSend)(appController, @selector(sharedInstance))
                : nil;
            app = app && [app respondsToSelector:@selector(applicationWithBundleIdentifier:)]
                ? ((id (*)(id, SEL, id))objc_msgSend)(app, @selector(applicationWithBundleIdentifier:), bundleID)
                : nil;
            runtimeApp = app;
            NSURL *fallbackURL = app && [app respondsToSelector:@selector(bundleURL)]
                ? ((id (*)(id, SEL))objc_msgSend)(app, @selector(bundleURL))
                : nil;
            if (fallbackURL) {
                info = [NSDictionary dictionaryWithContentsOfFile:[[fallbackURL path] stringByAppendingPathComponent:@"Info.plist"]];
            }
        }
        if (!runtimeApp) {
            Class appController = CV3ClassNamed(@"SBApplicationController");
            id controller = appController && [appController respondsToSelector:@selector(sharedInstance)]
                ? ((id (*)(id, SEL))objc_msgSend)(appController, @selector(sharedInstance))
                : nil;
            runtimeApp = controller && [controller respondsToSelector:@selector(applicationWithBundleIdentifier:)]
                ? ((id (*)(id, SEL, id))objc_msgSend)(controller, @selector(applicationWithBundleIdentifier:), bundleID)
                : nil;
        }
        if (runtimeApp) {
            @try {
                id maskValue = [runtimeApp valueForKey:@"supportedInterfaceOrientations"];
                UIInterfaceOrientationMask mask = [maskValue unsignedIntegerValue];
                BOOL hasLandscape = (mask & UIInterfaceOrientationMaskLandscape) != 0;
                BOOL hasPortrait = (mask & (UIInterfaceOrientationMaskPortrait | UIInterfaceOrientationMaskPortraitUpsideDown)) != 0;
                if (hasLandscape && !hasPortrait) return YES;
            } @catch (__unused NSException *exception) {}
        }
        NSString *declaredDefault = [info[@"UIInterfaceOrientation"] isKindOfClass:[NSString class]]
            ? info[@"UIInterfaceOrientation"]
            : nil;
        if (declaredDefault.length && [declaredDefault rangeOfString:@"Landscape" options:NSCaseInsensitiveSearch].location != NSNotFound) {
            return YES;
        }
        NSArray *orientations = info[@"UISupportedInterfaceOrientations"];
        if (![orientations isKindOfClass:[NSArray class]]) {
            orientations = info[@"UISupportedInterfaceOrientations~ipad"];
        }
        if (![orientations isKindOfClass:[NSArray class]] || orientations.count == 0) return NO;

        BOOL hasLandscape = NO;
        BOOL hasPortrait = NO;
        for (NSString *value in orientations) {
            NSString *name = [value isKindOfClass:[NSString class]] ? value : @"";
            hasLandscape |= [name rangeOfString:@"Landscape" options:NSCaseInsensitiveSearch].location != NSNotFound;
            hasPortrait |= [name rangeOfString:@"Portrait" options:NSCaseInsensitiveSearch].location != NSNotFound;
        }
        return hasLandscape && !hasPortrait;
    } @catch (__unused NSException *exception) {
        return NO;
    }
}

static UIInterfaceOrientation CV3InitialHostedOrientationForBundleID(NSString *bundleID,
                                                                       UIInterfaceOrientation fallback) {
    if (!CV3BundleDeclaresLandscapeOnly(bundleID)) return fallback;
    if (fallback == UIInterfaceOrientationLandscapeLeft || fallback == UIInterfaceOrientationLandscapeRight) {
        return fallback;
    }
    return UIInterfaceOrientationLandscapeRight;
}

static BOOL isGlobalExposeActive = NO;
static UIWindow *globalExposeBackdrop = nil;
static UIView *globalExposeContentView = nil;
static NSArray<CV3FloatingAppWindow *> *globalExposeWindows = nil;
static CGFloat globalExposeScrollOffset = 0.0;
static NSInteger globalExposeSelectedIndex = 0;
static BOOL globalExposeIsLandscape = NO;
static void CV3ExitExposeModeSelectingWindow(CV3FloatingAppWindow *selectedWindow, BOOL focusSelected);

static BOOL CV3WindowIsExpandedForExpose(id object) {
    if (![object isKindOfClass:[CV3FloatingAppWindow class]]) return NO;
    CV3FloatingAppWindow *window = (CV3FloatingAppWindow *)object;
    if (window.isClosing || window.isStashed) return NO;

    // During the genie transition restoreFromStash clears isStashed before the
    // full window is visible. Treat that interval as icon state so Expose only
    // contains windows whose expanded content is actually on screen.
    UIView *content = window.appContentWrapper;
    UIView *chrome = window.clippingContainer;
    return content && chrome && content.alpha > 0.01 && chrome.alpha > 0.01;
}

static NSArray<CV3FloatingAppWindow *> *CV3ExpandedWindowsForExpose(void) {
    NSMutableArray<CV3FloatingAppWindow *> *expandedWindows = [NSMutableArray array];
    for (id object in [floatingWindows copy]) {
        if (CV3WindowIsExpandedForExpose(object)) {
            [expandedWindows addObject:(CV3FloatingAppWindow *)object];
        }
    }
    return [expandedWindows copy];
}

static CGFloat CV3ClampCGFloat(CGFloat value, CGFloat minValue, CGFloat maxValue) {
    if (maxValue < minValue) return minValue;
    return MAX(minValue, MIN(maxValue, value));
}

static CGRect CV3ExposeLayoutBounds(CGRect bounds) {
    UIEdgeInsets safeArea = UIEdgeInsetsZero;
    if (globalExposeBackdrop && !globalExposeContentView) {
        safeArea = globalExposeBackdrop.safeAreaInsets;
    }
    CGRect layoutBounds = CGRectMake(bounds.origin.x + safeArea.left + kCV3ExposeOuterPadding,
                                     bounds.origin.y + safeArea.top + kCV3ExposeOuterPadding,
                                     bounds.size.width - safeArea.left - safeArea.right - kCV3ExposeOuterPadding * 2.0,
                                     bounds.size.height - safeArea.top - safeArea.bottom - kCV3ExposeOuterPadding * 2.0);
    if (layoutBounds.size.width < 1.0) layoutBounds.size.width = 1.0;
    if (layoutBounds.size.height < 1.0) layoutBounds.size.height = 1.0;
    return layoutBounds;
}

static CGFloat CV3ExposePortraitAspectRatio(CGRect bounds) {
    CGFloat shortSide = MIN(bounds.size.width, bounds.size.height);
    CGFloat longSide = MAX(bounds.size.width, bounds.size.height);
    return longSide / MAX(shortSide, 1.0);
}

static NSInteger CV3ExposeColumnCountForWindows(NSInteger count, BOOL landscape) {
    if (count <= 0) return 0;
    return landscape ? MAX(1, count) : MIN(kCV3ExposeColumnCount, count);
}

static NSInteger CV3ExposeRowCountForWindows(NSInteger count, BOOL landscape) {
    if (count <= 0) return 0;
    if (landscape) return 1;
    NSInteger cols = CV3ExposeColumnCountForWindows(count, NO);
    return MAX(1, (NSInteger)ceil((double)count / (double)MAX(1, cols)));
}

static CGSize CV3ExposeCellSize(CGRect bounds, NSInteger count, BOOL landscape) {
    if (count <= 0 || CGRectIsEmpty(bounds)) return CGSizeZero;

    CGRect layoutBounds = CV3ExposeLayoutBounds(bounds);
    NSInteger visibleCols = landscape ? MIN(MAX(1, count), 4) : MIN(kCV3ExposeColumnCount, MAX(1, count));
    NSInteger visibleRows = landscape ? 1 : MIN(MAX(1, CV3ExposeRowCountForWindows(count, NO)), 2);
    CGFloat totalSpacingX = kCV3ExposeInterItemSpacing * MAX(0, visibleCols - 1);
    CGFloat totalSpacingY = kCV3ExposeInterItemSpacing * MAX(0, visibleRows - 1);
    CGFloat maxCellWidth = MAX(1.0, (layoutBounds.size.width - totalSpacingX) / (CGFloat)visibleCols);
    CGFloat maxCellHeight = MAX(1.0, (layoutBounds.size.height - totalSpacingY) / (CGFloat)visibleRows);
    CGFloat aspectRatio = CV3ExposePortraitAspectRatio(bounds);
    CGFloat viewportWidthCap = layoutBounds.size.width * (landscape ? 0.25 : kCV3ExposeMaxCellWidthRatio);
    CGFloat viewportHeightCap = layoutBounds.size.height * (landscape ? 0.96 : 0.52);

    maxCellWidth = MIN(maxCellWidth, MAX(1.0, viewportWidthCap));
    maxCellHeight = MIN(maxCellHeight, MAX(1.0, viewportHeightCap));

    CGFloat cellWidth = MIN(maxCellWidth, maxCellHeight / MAX(aspectRatio, 1.0));
    CGFloat cellHeight = cellWidth * aspectRatio;
    if (cellHeight > maxCellHeight) {
        cellHeight = maxCellHeight;
        cellWidth = cellHeight / MAX(aspectRatio, 1.0);
    }

    return CGSizeMake(MAX(1.0, cellWidth), MAX(1.0, cellHeight));
}

static CGFloat CV3ExposeMaxScrollForWindows(NSArray<CV3FloatingAppWindow *> *windows, CGRect bounds, BOOL landscape) {
    NSInteger count = windows.count;
    if (count <= 0 || CGRectIsEmpty(bounds)) return 0.0;

    CGRect layoutBounds = CV3ExposeLayoutBounds(bounds);
    NSInteger cols = CV3ExposeColumnCountForWindows(count, landscape);
    NSInteger rows = CV3ExposeRowCountForWindows(count, landscape);
    CGSize cellSize = CV3ExposeCellSize(bounds, count, landscape);
    CGFloat contentWidth = cellSize.width * cols + kCV3ExposeInterItemSpacing * MAX(0, cols - 1);
    CGFloat contentHeight = cellSize.height * rows + kCV3ExposeInterItemSpacing * MAX(0, rows - 1);
    return landscape ? MAX(0.0, contentWidth - layoutBounds.size.width) : MAX(0.0, contentHeight - layoutBounds.size.height);
}

static CGRect CV3ExposeCellFrameForIndex(NSInteger index, NSInteger count, CGRect bounds, BOOL landscape) {
    if (count <= 0 || CGRectIsEmpty(bounds)) return CGRectZero;

    NSInteger cols = CV3ExposeColumnCountForWindows(count, landscape);
    NSInteger rows = CV3ExposeRowCountForWindows(count, landscape);
    NSInteger row = index / cols;
    NSInteger col = index % cols;

    CGRect layoutBounds = CV3ExposeLayoutBounds(bounds);
    CGSize cellSize = CV3ExposeCellSize(bounds, count, landscape);
    CGFloat cellW = cellSize.width;
    CGFloat cellH = cellSize.height;
    CGFloat gridWidth = cellW * cols + kCV3ExposeInterItemSpacing * MAX(0, cols - 1);
    CGFloat gridHeight = cellH * rows + kCV3ExposeInterItemSpacing * MAX(0, rows - 1);
    CGFloat centeredOffsetX = MAX(0.0, (layoutBounds.size.width - gridWidth) * 0.5);
    CGFloat startX = layoutBounds.origin.x + centeredOffsetX - (landscape ? globalExposeScrollOffset : 0.0);
    CGFloat centeredOffsetY = MAX(0.0, (layoutBounds.size.height - gridHeight) * 0.5);
    CGFloat startY = layoutBounds.origin.y + centeredOffsetY - (landscape ? 0.0 : globalExposeScrollOffset);

    NSInteger itemsInRow = cols;
    if (row == rows - 1) {
        NSInteger remaining = count - row * cols;
        if (remaining > 0) itemsInRow = MIN(cols, remaining);
    }
    CGFloat rowWidth = cellW * itemsInRow + kCV3ExposeInterItemSpacing * MAX(0, itemsInRow - 1);
    CGFloat rowStartX = startX + MAX(0.0, (gridWidth - rowWidth) * 0.5);

    CGFloat x = landscape ? startX + col * (cellW + kCV3ExposeInterItemSpacing) : rowStartX + col * (cellW + kCV3ExposeInterItemSpacing);
    return CGRectMake(x,
                      startY + row * (cellH + kCV3ExposeInterItemSpacing),
                      cellW,
                      cellH);
}

static void CV3UpdateExposeSelection(NSInteger selectedIndex) {
    if (!globalExposeWindows || globalExposeWindows.count == 0) return;
    globalExposeSelectedIndex = MAX(0, MIN(selectedIndex, (NSInteger)globalExposeWindows.count - 1));

    for (NSInteger i = 0; i < (NSInteger)globalExposeWindows.count; i++) {
        CV3FloatingAppWindow *win = globalExposeWindows[i];
        UIView *overlay = win.exposeOverlayView;
        if (!overlay) continue;

        BOOL selected = (i == globalExposeSelectedIndex);
        UIColor *focusColor = [UIColor colorWithRed:0.18 green:0.82 blue:1.0 alpha:1.0];
        overlay.layer.borderWidth = selected ? 3.0 : 1.0;
        overlay.layer.borderColor = (selected
                                     ? focusColor
                                     : [[UIColor whiteColor] colorWithAlphaComponent:0.20]).CGColor;
        overlay.layer.cornerRadius = kCV3ExposeCardCornerRadius;
        overlay.backgroundColor = selected ? [focusColor colorWithAlphaComponent:0.10] : [[UIColor blackColor] colorWithAlphaComponent:0.14];
        overlay.layer.shadowColor = [UIColor blackColor].CGColor;
        overlay.layer.shadowOpacity = selected ? (float)(kCV3ExposeCardShadowOpacity + 0.08) : (float)kCV3ExposeCardShadowOpacity;
        overlay.layer.shadowRadius = selected ? kCV3ExposeCardShadowRadius + 6.0 : kCV3ExposeCardShadowRadius;
        overlay.layer.shadowOffset = CGSizeMake(0, selected ? 18.0 : 12.0);
        overlay.transform = selected ? CGAffineTransformMakeScale(kCV3ExposeCardSelectedScale, kCV3ExposeCardSelectedScale) : CGAffineTransformIdentity;
    }
}

static void CV3UpdateExposeSelectionForViewportCenter(void) {
    if (!globalExposeWindows || globalExposeWindows.count == 0 || !globalExposeBackdrop) return;

    CGRect bounds = globalExposeContentView ? globalExposeContentView.bounds : globalExposeBackdrop.bounds;
    CGPoint viewportCenter = CGPointMake(CGRectGetMidX(bounds), CGRectGetMidY(bounds));
    CGFloat bestDistance = CGFLOAT_MAX;
    NSInteger bestIndex = globalExposeSelectedIndex;

    for (NSInteger i = 0; i < (NSInteger)globalExposeWindows.count; i++) {
        CGRect cellFrame = CV3ExposeCellFrameForIndex(i, globalExposeWindows.count, bounds, globalExposeIsLandscape);
        CGPoint center = CGPointMake(CGRectGetMidX(cellFrame), CGRectGetMidY(cellFrame));
        CGFloat dx = center.x - viewportCenter.x;
        CGFloat dy = center.y - viewportCenter.y;
        CGFloat distance = dx * dx + dy * dy;
        if (distance < bestDistance) {
            bestDistance = distance;
            bestIndex = i;
        }
    }

    CV3UpdateExposeSelection(bestIndex);
}

static void CV3LayoutExposeLiveContent(CV3FloatingAppWindow *win) {
    UIView *cardView = win.exposeOverlayView;
    UIView *contentContainer = win.exposeLiveContentContainer;
    UIView *liveContent = win.appContentWrapper;
    if (!cardView || !contentContainer || !liveContent) return;

    contentContainer.frame = cardView.bounds;
    contentContainer.layer.cornerRadius = kCV3ExposeCardCornerRadius;

    CGRect sourceBounds = win.exposeContentOriginalBounds;
    if (CGRectIsEmpty(sourceBounds)) sourceBounds = liveContent.bounds;
    if (CGRectIsEmpty(sourceBounds)) return;

    CGFloat scaleX = CGRectGetWidth(contentContainer.bounds) / MAX(CGRectGetWidth(sourceBounds), 1.0);
    CGFloat scaleY = CGRectGetHeight(contentContainer.bounds) / MAX(CGRectGetHeight(sourceBounds), 1.0);
    CGFloat scale = MIN(scaleX, scaleY);

    liveContent.bounds = sourceBounds;
    liveContent.center = CGPointMake(CGRectGetMidX(contentContainer.bounds), CGRectGetMidY(contentContainer.bounds));
    liveContent.transform = CGAffineTransformMakeScale(scale, scale);
}

static void CV3RestoreExposeLiveContent(CV3FloatingAppWindow *win, BOOL preserveCardImage) {
    UIView *cardView = win.exposeOverlayView;
    UIView *contentContainer = win.exposeLiveContentContainer;
    UIView *liveContent = win.appContentWrapper;
    if (!contentContainer || !liveContent || liveContent.superview != contentContainer) return;

    if (preserveCardImage && cardView && !CGRectIsEmpty(contentContainer.bounds)) {
        UIView *transitionSnapshot = [contentContainer snapshotViewAfterScreenUpdates:NO];
        if (transitionSnapshot) {
            transitionSnapshot.frame = contentContainer.frame;
            transitionSnapshot.userInteractionEnabled = NO;
            transitionSnapshot.layer.cornerRadius = kCV3ExposeCardCornerRadius;
            transitionSnapshot.layer.masksToBounds = YES;
            [cardView insertSubview:transitionSnapshot atIndex:0];
        }
    }

    UIView *originalSuperview = win.exposeContentOriginalSuperview ?: win.rootTransformContainer;
    if (originalSuperview) {
        NSInteger insertionIndex = MAX(0, win.exposeContentOriginalIndex);
        insertionIndex = MIN(insertionIndex, (NSInteger)originalSuperview.subviews.count);
        [originalSuperview insertSubview:liveContent atIndex:(NSUInteger)insertionIndex];
    }

    liveContent.bounds = win.exposeContentOriginalBounds;
    liveContent.center = win.exposeContentOriginalCenter;
    liveContent.transform = win.exposeContentOriginalTransform;
    liveContent.autoresizingMask = win.exposeContentOriginalAutoresizingMask;
    liveContent.userInteractionEnabled = win.exposeContentOriginalUserInteractionEnabled;

    [contentContainer removeFromSuperview];
    win.exposeLiveContentContainer = nil;
    win.exposeContentOriginalSuperview = nil;
    [win setNeedsLayout];
    [win layoutIfNeeded];
}

static void CV3LayoutExposeWindowsAnimated(BOOL animated) {
    if (!globalExposeWindows || globalExposeWindows.count == 0 || !globalExposeBackdrop) return;

    CGRect bounds = globalExposeContentView ? globalExposeContentView.bounds : globalExposeBackdrop.bounds;
    globalExposeScrollOffset = CV3ClampCGFloat(globalExposeScrollOffset,
                                               0.0,
                                               CV3ExposeMaxScrollForWindows(globalExposeWindows, bounds, globalExposeIsLandscape));

    void (^layoutBlock)(void) = ^{
        for (NSInteger i = 0; i < (NSInteger)globalExposeWindows.count; i++) {
            CV3FloatingAppWindow *win = globalExposeWindows[i];
            if (win.isClosing) continue;

            CGRect cellFrame = CV3ExposeCellFrameForIndex(i, globalExposeWindows.count, bounds, globalExposeIsLandscape);
            UIView *cardView = win.exposeOverlayView;
            if (!cardView) continue;
            cardView.frame = cellFrame;
            cardView.layer.shadowPath = [UIBezierPath bezierPathWithRoundedRect:cardView.bounds cornerRadius:kCV3ExposeCardCornerRadius].CGPath;
            CV3LayoutExposeLiveContent(win);
        }
    };

    if (animated) {
        [UIView animateWithDuration:0.28 delay:0 usingSpringWithDamping:0.82 initialSpringVelocity:0.0 options:UIViewAnimationOptionCurveEaseInOut | UIViewAnimationOptionAllowUserInteraction animations:layoutBlock completion:nil];
    } else {
        [CATransaction begin];
        [CATransaction setDisableActions:YES];
        layoutBlock();
        [CATransaction commit];
    }

    CV3UpdateExposeSelection(globalExposeSelectedIndex);
}

@implementation CV3HostedSceneSession

- (instancetype)initWithWindow:(CV3FloatingAppWindow *)window {
    self = [super init];
    if (self) self.window = window;
    return self;
}

- (void)setActive:(BOOL)active {
    if (_active == active) return;
    _active = active;

    [self.continuityTimer invalidate];
    self.continuityTimer = nil;
    CV3PostHostedState(self.window.bundleID, active);

    if (active) {
        [self validateNow:@"HostedSessionActivated"];
        // Scene updates are expensive for clients with complex accessibility
        // trees. A slower lease heartbeat avoids feeding the scene-update
        // watchdog while still recovering a genuinely lost host layer.
        self.continuityTimer = [NSTimer scheduledTimerWithTimeInterval:3.0
                                                               target:self
                                                             selector:@selector(continuityTimerFired:)
                                                             userInfo:nil
                                                              repeats:YES];
    }
}

- (void)continuityTimerFired:(NSTimer *)timer {
    [self validateNow:@"HostedSessionHeartbeat"];
}

- (void)validateNow:(NSString *)reason {
    CV3FloatingAppWindow *window = self.window;
    if (!self.active || !window || window.isClosing || window.isStashed) return;
    NSUInteger generationBeforeRecovery = window.sceneHostGeneration;
    [window recoverHostedPresentationIfNeeded:reason];
    // A recovery invalidates the old host generation. Do not mutate the
    // detached Scene again in the same heartbeat.
    if (window.sceneHostGeneration != generationBeforeRecovery ||
        window.hostLifecycleState != CV3HostLifecycleStateLive) return;
    [window stabilizeForegroundForWorkspaceTransition:reason];
}

- (void)invalidate {
    [self setActive:NO];
    self.window = nil;
}

- (void)dealloc {
    [self.continuityTimer invalidate];
}

@end

static void CV3UpdateExposeForSceneRotation(CV3SceneRotationContext context, BOOL animated) {
    if (!isGlobalExposeActive || !globalExposeBackdrop || !globalExposeContentView) return;

    CV3FloatingAppWindow *selectedWindow = nil;
    if (globalExposeSelectedIndex >= 0 && globalExposeSelectedIndex < (NSInteger)globalExposeWindows.count) {
        selectedWindow = globalExposeWindows[globalExposeSelectedIndex];
    }

    NSMutableArray<CV3FloatingAppWindow *> *expandedSnapshot = [NSMutableArray array];
    for (CV3FloatingAppWindow *window in globalExposeWindows) {
        if (CV3WindowIsExpandedForExpose(window)) {
            [expandedSnapshot addObject:window];
        } else {
            CV3RestoreExposeLiveContent(window, NO);
            [window.exposeOverlayView removeFromSuperview];
            window.exposeOverlayView = nil;
        }
    }
    if (expandedSnapshot.count != globalExposeWindows.count) {
        globalExposeWindows = [expandedSnapshot copy];
        NSInteger preservedIndex = selectedWindow ? [globalExposeWindows indexOfObject:selectedWindow] : NSNotFound;
        globalExposeSelectedIndex = preservedIndex == NSNotFound
            ? MIN(globalExposeSelectedIndex, MAX(0, (NSInteger)globalExposeWindows.count - 1))
            : preservedIndex;
        globalExposeScrollOffset = 0.0;
    }
    if (globalExposeWindows.count < 2) {
        CV3ExitExposeModeSelectingWindow(globalExposeWindows.firstObject, globalExposeWindows.count == 1);
        return;
    }

    CGRect sceneBounds = context.sceneBounds;
    if (CGRectIsEmpty(sceneBounds)) sceneBounds = [UIScreen mainScreen].bounds;

    CGFloat shortSide = MIN(sceneBounds.size.width, sceneBounds.size.height);
    CGFloat longSide = MAX(sceneBounds.size.width, sceneBounds.size.height);
    CGSize layoutSize = context.isLandscape
        ? CGSizeMake(longSide, shortSide)
        : CGSizeMake(shortSide, longSide);

    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    globalExposeBackdrop.frame = sceneBounds;
    for (UIView *subview in globalExposeBackdrop.subviews) {
        if (subview != globalExposeContentView) subview.frame = globalExposeBackdrop.bounds;
    }
    globalExposeContentView.bounds = CGRectMake(0, 0, layoutSize.width, layoutSize.height);
    globalExposeContentView.center = CGPointMake(CGRectGetMidX(globalExposeBackdrop.bounds),
                                                 CGRectGetMidY(globalExposeBackdrop.bounds));
    BOOL backingBoundsLandscape = CGRectGetWidth(globalExposeBackdrop.bounds) > CGRectGetHeight(globalExposeBackdrop.bounds);
    globalExposeContentView.transform = (backingBoundsLandscape == context.isLandscape)
        ? CGAffineTransformIdentity
        : context.transform;
    [CATransaction commit];

    BOOL layoutAxisChanged = (globalExposeIsLandscape != context.isLandscape);
    globalExposeIsLandscape = context.isLandscape;
    if (layoutAxisChanged) globalExposeScrollOffset = 0.0;
    CV3LayoutExposeWindowsAnimated(animated);
    CV3UpdateExposeSelectionForViewportCenter();
}

static void CV3ExitExposeModeSelectingWindow(CV3FloatingAppWindow *selectedWindow, BOOL focusSelected) {
    if (!isGlobalExposeActive) {
        if (focusSelected && selectedWindow && !selectedWindow.isClosing) {
            [selectedWindow setWindowFocused:YES];
        }
        return;
    }

    isGlobalExposeActive = NO;
    NSArray *windowsSnapshot = [globalExposeWindows copy] ?: @[];
    UIWindow *backdrop = globalExposeBackdrop;
    globalExposeWindows = nil;
    globalExposeScrollOffset = 0.0;
    globalExposeSelectedIndex = 0;

    for (id obj in windowsSnapshot) {
        if (![obj isKindOfClass:[CV3FloatingAppWindow class]]) continue;
        CV3FloatingAppWindow *win = (CV3FloatingAppWindow *)obj;
        CV3RestoreExposeLiveContent(win, YES);
    }

    if (focusSelected && selectedWindow && !selectedWindow.isClosing) {
        [selectedWindow promoteFloatingWindowInZOrder];
    }

    [UIView animateWithDuration:0.35 delay:0 usingSpringWithDamping:0.86 initialSpringVelocity:0.0 options:UIViewAnimationOptionCurveEaseInOut | UIViewAnimationOptionAllowUserInteraction animations:^{
        for (id obj in windowsSnapshot) {
            if (![obj isKindOfClass:[CV3FloatingAppWindow class]]) continue;
            CV3FloatingAppWindow *win = (CV3FloatingAppWindow *)obj;
            win.alpha = 1.0;
            win.exposeOverlayView.alpha = 0.0;
        }
        if (backdrop) backdrop.alpha = 0.0;
    } completion:^(BOOL finished) {
        for (id obj in windowsSnapshot) {
            if (![obj isKindOfClass:[CV3FloatingAppWindow class]]) continue;
            CV3FloatingAppWindow *win = (CV3FloatingAppWindow *)obj;
            [win.exposeOverlayView removeFromSuperview];
            win.exposeOverlayView = nil;
        }

        if (backdrop) {
            backdrop.hidden = YES;
            if (globalExposeBackdrop == backdrop) globalExposeBackdrop = nil;
        }
        if (globalExposeContentView) {
            [globalExposeContentView removeFromSuperview];
            globalExposeContentView = nil;
        }

        if (focusSelected && selectedWindow && !selectedWindow.isClosing) {
            [selectedWindow setWindowFocused:YES];
        }
    }];
}

static BOOL CV3ExitExposeModeIfNeeded(CV3FloatingAppWindow *selectedWindow, BOOL focusSelected) {
    if (!isGlobalExposeActive) return NO;
    CV3ExitExposeModeSelectingWindow(selectedWindow, focusSelected);
    return YES;
}

void CV3ToggleExposeMode(void) {
    if (isGlobalExposeActive) {
        CV3ExitExposeModeSelectingWindow(nil, NO);
    } else {
        if (!floatingWindows || floatingWindows.count == 0) return;

        NSMutableArray<CV3FloatingAppWindow *> *activeWindows = [CV3ExpandedWindowsForExpose() mutableCopy];
        if (activeWindows.count < 2) {
            CV3FloatingAppWindow *onlyWindow = activeWindows.firstObject;
            if (onlyWindow) [onlyWindow setWindowFocused:YES];
            return;
        }

        CV3FloatingAppWindow *preferredFirstWindow = nil;
        for (CV3FloatingAppWindow *win in activeWindows) {
            if (win.isFocused && CV3WindowIsExpandedForExpose(win)) {
                preferredFirstWindow = win;
                break;
            }
        }
        if (!preferredFirstWindow) {
            for (NSInteger i = (NSInteger)floatingWindows.count - 1; i >= 0; i--) {
                id obj = floatingWindows[i];
                if (![obj isKindOfClass:[CV3FloatingAppWindow class]]) continue;
                CV3FloatingAppWindow *win = (CV3FloatingAppWindow *)obj;
                if (CV3WindowIsExpandedForExpose(win) && [activeWindows containsObject:win]) {
                    preferredFirstWindow = win;
                    break;
                }
            }
        }
        if (preferredFirstWindow && activeWindows.firstObject != preferredFirstWindow) {
            [activeWindows removeObject:preferredFirstWindow];
            [activeWindows insertObject:preferredFirstWindow atIndex:0];
        }

        // Enter Exposé
        isGlobalExposeActive = YES;
        
        UIWindowScene *scene = nil;
        for (CV3FloatingAppWindow *win in activeWindows) {
            scene = win.windowScene;
            if (scene) break;
        }
        
        if (!globalExposeBackdrop) {
            if (scene) {
                globalExposeBackdrop = [[UIWindow alloc] initWithWindowScene:scene];
            } else {
                globalExposeBackdrop = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
            }
            globalExposeBackdrop.windowLevel = CV3Style.floatingApp + 5;
            
            UIBlurEffect *blur = [UIBlurEffect effectWithStyle:UIBlurEffectStyleDark];
            UIVisualEffectView *bg = [[UIVisualEffectView alloc] initWithEffect:blur];
            bg.frame = globalExposeBackdrop.bounds;
            bg.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
            [globalExposeBackdrop addSubview:bg];
            
            UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:[CV3FloatingAppWindow class] action:@selector(handleExposeBackdropTap:)];
            [globalExposeBackdrop addGestureRecognizer:tap];
            UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:[CV3FloatingAppWindow class] action:@selector(handleExposeBackdropPan:)];
            [globalExposeBackdrop addGestureRecognizer:pan];
        }

        UIInterfaceOrientation exposeOrientation = CV3TrustedInterfaceOrientation(scene);
        BOOL exposeLandscape = UIInterfaceOrientationIsLandscape(exposeOrientation);
        CGRect rawBackdropBounds = CGRectZero;
        if (scene && !CGRectIsEmpty(scene.coordinateSpace.bounds)) {
            rawBackdropBounds = scene.coordinateSpace.bounds;
        }
        if (CGRectIsEmpty(rawBackdropBounds)) {
            rawBackdropBounds = [UIScreen mainScreen].bounds;
        }

        CGFloat shortSide = MIN(rawBackdropBounds.size.width, rawBackdropBounds.size.height);
        CGFloat longSide = MAX(rawBackdropBounds.size.width, rawBackdropBounds.size.height);
        CGRect backdropFrame = exposeLandscape
            ? CGRectMake(0, 0, longSide, shortSide)
            : CGRectMake(0, 0, shortSide, longSide);
        CGRect windowFrame = rawBackdropBounds;
        globalExposeBackdrop.frame = windowFrame;
        for (UIView *subview in globalExposeBackdrop.subviews) {
            subview.frame = globalExposeBackdrop.bounds;
        }

        if (!globalExposeContentView) {
            globalExposeContentView = [[UIView alloc] initWithFrame:CGRectZero];
            globalExposeContentView.backgroundColor = [UIColor clearColor];
            globalExposeContentView.clipsToBounds = NO;
            [globalExposeBackdrop addSubview:globalExposeContentView];
        }

        globalExposeContentView.bounds = CGRectMake(0, 0, backdropFrame.size.width, backdropFrame.size.height);
        globalExposeContentView.center = CGPointMake(CGRectGetMidX(globalExposeBackdrop.bounds),
                                                     CGRectGetMidY(globalExposeBackdrop.bounds));
        BOOL backingBoundsLandscape = CGRectGetWidth(globalExposeBackdrop.bounds) > CGRectGetHeight(globalExposeBackdrop.bounds);
        globalExposeContentView.transform = (backingBoundsLandscape == exposeLandscape)
            ? CGAffineTransformIdentity
            : CV3RotationTransformForInterfaceOrientation(exposeOrientation);
        
        globalExposeBackdrop.alpha = 0.0;
        globalExposeBackdrop.hidden = NO;

        globalExposeWindows = [activeWindows copy];
        globalExposeScrollOffset = 0.0;
        globalExposeSelectedIndex = 0;
        globalExposeIsLandscape = exposeLandscape;
        
        [UIView animateWithDuration:0.45 delay:0 usingSpringWithDamping:0.75 initialSpringVelocity:0.0 options:UIViewAnimationOptionCurveEaseInOut | UIViewAnimationOptionAllowUserInteraction animations:^{
            globalExposeBackdrop.alpha = 1.0;
            
            for (NSInteger i=0; i<(NSInteger)activeWindows.count; i++) {
                CV3FloatingAppWindow *win = activeWindows[i];
                
                // 折叠浮窗的控制菜单（如果有展开的话）
                [win dismissMultitaskingMenu];
                
                win.preExposeFrame = win.frame;
                win.preExposeTransform = win.transform;
                win.alpha = 0.22;
                
                // Add Overlay
                if (!win.exposeOverlayView) {
                    UIView *cardView = [[UIView alloc] initWithFrame:CGRectZero];
                    cardView.layer.cornerRadius = kCV3ExposeCardCornerRadius;
                    cardView.layer.masksToBounds = NO;
                    cardView.clipsToBounds = NO;

                    UIView *liveContent = win.appContentWrapper;
                    if (liveContent && liveContent.superview) {
                        UIView *originalSuperview = liveContent.superview;
                        win.exposeContentOriginalSuperview = originalSuperview;
                        win.exposeContentOriginalIndex = (NSInteger)[originalSuperview.subviews indexOfObject:liveContent];
                        win.exposeContentOriginalBounds = liveContent.bounds;
                        win.exposeContentOriginalCenter = liveContent.center;
                        win.exposeContentOriginalTransform = liveContent.transform;
                        win.exposeContentOriginalAutoresizingMask = liveContent.autoresizingMask;
                        win.exposeContentOriginalUserInteractionEnabled = liveContent.userInteractionEnabled;

                        UIView *contentContainer = [[UIView alloc] initWithFrame:cardView.bounds];
                        contentContainer.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
                        contentContainer.backgroundColor = [UIColor clearColor];
                        contentContainer.userInteractionEnabled = NO;
                        contentContainer.clipsToBounds = YES;
                        contentContainer.layer.cornerRadius = kCV3ExposeCardCornerRadius;
                        [cardView addSubview:contentContainer];
                        [contentContainer addSubview:liveContent];
                        liveContent.autoresizingMask = UIViewAutoresizingNone;
                        liveContent.userInteractionEnabled = NO;
                        win.exposeLiveContentContainer = contentContainer;
                    } else {
                        UIView *snapshotSourceView = win.rootTransformContainer ?: win;
                        UIView *snapshotView = [snapshotSourceView snapshotViewAfterScreenUpdates:NO];
                        if (snapshotView) {
                            snapshotView.frame = cardView.bounds;
                            snapshotView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
                            snapshotView.layer.cornerRadius = kCV3ExposeCardCornerRadius;
                            snapshotView.layer.masksToBounds = YES;
                            [cardView addSubview:snapshotView];
                        }
                    }

                    UIView *scrim = [[UIView alloc] initWithFrame:cardView.bounds];
                    scrim.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
                    scrim.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.06];
                    scrim.userInteractionEnabled = NO;
                    scrim.layer.cornerRadius = kCV3ExposeCardCornerRadius;
                    [cardView addSubview:scrim];

                    win.exposeOverlayView = cardView;
                    UITapGestureRecognizer *winTap = [[UITapGestureRecognizer alloc] initWithTarget:win action:@selector(handleExposeSelectionTap:)];
                    [cardView addGestureRecognizer:winTap];
                    UIPanGestureRecognizer *winPan = [[UIPanGestureRecognizer alloc] initWithTarget:win action:@selector(handleExposeCardPan:)];
                    [cardView addGestureRecognizer:winPan];
                    [globalExposeContentView addSubview:cardView];
                }
            }
            CV3LayoutExposeWindowsAnimated(NO);
        } completion:nil];
    }
}

@implementation CV3FloatingAppWindow
- (CGFloat)angleForInterfaceOrientation:(UIInterfaceOrientation)orientation {
    switch (orientation) {
        case UIInterfaceOrientationLandscapeLeft:
            return (CGFloat)(-M_PI_2);
        case UIInterfaceOrientationLandscapeRight:
            return (CGFloat)(M_PI_2);
        case UIInterfaceOrientationPortraitUpsideDown:
            return (CGFloat)M_PI;
        case UIInterfaceOrientationPortrait:
        default:
            return 0.0;
    }
}

- (UIImage *)imageByRotatingImage:(UIImage *)image fromOrientation:(UIInterfaceOrientation)fromOrientation toOrientation:(UIInterfaceOrientation)toOrientation {
    if (!image || fromOrientation == toOrientation) return image;

    CGFloat delta = [self angleForInterfaceOrientation:toOrientation] - [self angleForInterfaceOrientation:fromOrientation];
    while (delta > M_PI) delta -= (CGFloat)(M_PI * 2.0);
    while (delta < -M_PI) delta += (CGFloat)(M_PI * 2.0);
    if (fabs(delta) < 0.001) return image;

    CGSize sourceSize = image.size;
    CGRect sourceRect = CGRectMake(0, 0, sourceSize.width, sourceSize.height);
    CGRect rotatedRect = CGRectApplyAffineTransform(sourceRect, CGAffineTransformMakeRotation(delta));
    CGSize rotatedSize = CGSizeMake(fabs(rotatedRect.size.width), fabs(rotatedRect.size.height));

    UIGraphicsBeginImageContextWithOptions(rotatedSize, NO, image.scale);
    CGContextRef context = UIGraphicsGetCurrentContext();
    if (!context) {
        UIGraphicsEndImageContext();
        return image;
    }

    CGContextTranslateCTM(context, rotatedSize.width * 0.5, rotatedSize.height * 0.5);
    CGContextRotateCTM(context, delta);
    [image drawInRect:CGRectMake(-sourceSize.width * 0.5, -sourceSize.height * 0.5, sourceSize.width, sourceSize.height)];
    UIImage *rotatedImage = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return rotatedImage ?: image;
}

- (UIImage *)snapshotImageForRestoreAnimation {
    UIView *view = self.hostContainerProxy ?: self.clippingContainer ?: self.appContentWrapper;
    if (!view || CGRectIsEmpty(view.bounds)) return nil;

    UIGraphicsBeginImageContextWithOptions(view.bounds.size, NO, [UIScreen mainScreen].scale);
    BOOL didDraw = [view drawViewHierarchyInRect:view.bounds afterScreenUpdates:NO];
    if (!didDraw) {
        CGContextRef context = UIGraphicsGetCurrentContext();
        if (context) [view.layer renderInContext:context];
    }
    UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();

    UIInterfaceOrientation orientation = CV3IsValidInterfaceOrientation(self.targetOrientation)
        ? self.targetOrientation
        : CV3TrustedInterfaceOrientation(self.windowScene);
    return [self imageByRotatingImage:image
                      fromOrientation:UIInterfaceOrientationPortrait
                        toOrientation:orientation];
}

- (void)updateStashedRestoreSnapshotForOrientation:(UIInterfaceOrientation)orientation {
    if (!CV3IsValidInterfaceOrientation(orientation)) return;
    if (!self.stashedRestoreSnapshotImage) {
        self.stashedRestoreSnapshotOrientation = orientation;
        return;
    }
    UIInterfaceOrientation previousOrientation = CV3IsValidInterfaceOrientation(self.stashedRestoreSnapshotOrientation) ? self.stashedRestoreSnapshotOrientation : orientation;
    self.stashedRestoreSnapshotImage = [self imageByRotatingImage:self.stashedRestoreSnapshotImage fromOrientation:previousOrientation toOrientation:orientation];
    self.stashedRestoreSnapshotOrientation = orientation;
}

- (CGRect)interpolatedRectFrom:(CGRect)fromRect to:(CGRect)toRect progress:(CGFloat)progress {
    CGFloat p = MIN(1.0, MAX(0.0, progress));
    return CGRectMake(fromRect.origin.x + (toRect.origin.x - fromRect.origin.x) * p,
                      fromRect.origin.y + (toRect.origin.y - fromRect.origin.y) * p,
                      fromRect.size.width + (toRect.size.width - fromRect.size.width) * p,
                      fromRect.size.height + (toRect.size.height - fromRect.size.height) * p);
}

- (CATransform3D)genieTransformWithProgress:(CGFloat)progress towardLeft:(BOOL)towardLeft presenting:(BOOL)presenting {
    CGFloat p = MIN(1.0, MAX(0.0, progress));
    CGFloat wave = sin((CGFloat)M_PI * p);
    CGFloat direction = towardLeft ? -1.0 : 1.0;
    CGFloat xScale = 1.0 - 0.10 * wave;
    CGFloat yScale = 1.0 + 0.035 * wave;
    CGFloat rotationY = direction * 0.10 * wave * (presenting ? -1.0 : 1.0);
    CATransform3D transform = CATransform3DIdentity;
    transform.m34 = -1.0 / 900.0;
    transform = CATransform3DScale(transform, xScale, yScale, 1.0);
    transform = CATransform3DRotate(transform, rotationY, 0, 1, 0);
    return transform;
}

- (void)animateGenieSurfaceImage:(UIImage *)image
                     sourceFrame:(CGRect)sourceFrame
                       iconFrame:(CGRect)iconFrame
                      presenting:(BOOL)presenting
                      completion:(void (^)(void))completion {
    if (!image || CGRectIsEmpty(sourceFrame) || CGRectIsEmpty(iconFrame)) {
        if (completion) completion();
        return;
    }

    NSString *direction = presenting ? @"restore" : @"minimize";
    NSString *traceID = self.stashAnimationTraceID ?: @"unknown";
    CFTimeInterval surfaceStartTime = CACurrentMediaTime();
    CV3LogStashAnimation(@"[StashAnimation] id=%@ direction=%@ phase=surface.begin source=%@ icon=%@ duration_ms=340",
                 traceID,
                 direction,
                 NSStringFromCGRect(sourceFrame),
                 NSStringFromCGRect(iconFrame));

    BOOL towardLeft = CGRectGetMidX(iconFrame) < CGRectGetMidX(sourceFrame);
    CGRect stageFrame = [self interpolatedRectFrom:sourceFrame to:iconFrame progress:0.64];
    CGFloat stageInset = MAX(0.0, MIN(stageFrame.size.width * 0.16, fabs(sourceFrame.size.width - iconFrame.size.width) * 0.18));
    stageFrame = CGRectInset(stageFrame, stageInset, -8.0);
    stageFrame.size.width = MAX(iconFrame.size.width * 1.25, stageFrame.size.width);
    stageFrame.size.height = MAX(iconFrame.size.height * 1.4, stageFrame.size.height * 0.62);

    UIView *shadowSurface = [[UIView alloc] initWithFrame:presenting ? iconFrame : sourceFrame];
    shadowSurface.backgroundColor = [UIColor clearColor];
    shadowSurface.userInteractionEnabled = NO;
    shadowSurface.layer.shadowColor = [UIColor blackColor].CGColor;
    shadowSurface.layer.shadowOffset = presenting ? CGSizeMake(0, 2) : [self visualShadowLayer].shadowOffset;
    shadowSurface.layer.shadowOpacity = presenting ? 0.0 : MIN(0.14, MAX(0.08, [self visualShadowLayer].shadowOpacity));
    shadowSurface.layer.shadowRadius = presenting ? 3.0 : MIN(18.0, MAX(10.0, [self visualShadowLayer].shadowRadius * 0.65));
    shadowSurface.layer.shadowPath = [UIBezierPath bezierPathWithRoundedRect:shadowSurface.bounds cornerRadius:(presenting ? CV3Style.iconCornerRadius : self.clippingContainer.layer.cornerRadius)].CGPath;
    shadowSurface.layer.allowsEdgeAntialiasing = YES;

    UIImageView *imageView = [[UIImageView alloc] initWithFrame:shadowSurface.bounds];
    imageView.image = image;
    imageView.contentMode = UIViewContentModeScaleToFill;
    imageView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    imageView.clipsToBounds = YES;
    imageView.layer.cornerRadius = presenting ? CV3Style.iconCornerRadius : self.clippingContainer.layer.cornerRadius;
    imageView.layer.magnificationFilter = kCAFilterTrilinear;
    imageView.layer.minificationFilter = kCAFilterTrilinear;
    imageView.layer.allowsEdgeAntialiasing = YES;
    [shadowSurface addSubview:imageView];
    shadowSurface.alpha = presenting ? 0.0 : 1.0;
    [self addSubview:shadowSurface];

    NSTimeInterval duration = 0.34;
    [UIView animateKeyframesWithDuration:duration
                                   delay:0
                                 options:UIViewKeyframeAnimationOptionCalculationModeCubic | UIViewAnimationOptionBeginFromCurrentState
                              animations:^{
        if (presenting) {
            [UIView addKeyframeWithRelativeStartTime:0.0 relativeDuration:0.54 animations:^{
                shadowSurface.frame = stageFrame;
                shadowSurface.alpha = 0.92;
                shadowSurface.layer.transform = [self genieTransformWithProgress:0.58 towardLeft:towardLeft presenting:YES];
                shadowSurface.layer.shadowOpacity = 0.08;
                shadowSurface.layer.shadowRadius = 10.0;
                shadowSurface.layer.shadowPath = [UIBezierPath bezierPathWithRoundedRect:shadowSurface.bounds cornerRadius:self.clippingContainer.layer.cornerRadius * 1.8].CGPath;
                imageView.layer.cornerRadius = self.clippingContainer.layer.cornerRadius * 1.8;
            }];
            [UIView addKeyframeWithRelativeStartTime:0.34 relativeDuration:0.66 animations:^{
                shadowSurface.frame = sourceFrame;
                shadowSurface.alpha = 1.0;
                shadowSurface.layer.transform = CATransform3DIdentity;
                shadowSurface.layer.shadowOpacity = MIN(0.14, MAX(0.08, [self visualShadowLayer].shadowOpacity));
                shadowSurface.layer.shadowRadius = MIN(18.0, MAX(10.0, [self visualShadowLayer].shadowRadius * 0.65));
                shadowSurface.layer.shadowPath = [UIBezierPath bezierPathWithRoundedRect:shadowSurface.bounds cornerRadius:self.clippingContainer.layer.cornerRadius].CGPath;
                imageView.layer.cornerRadius = self.clippingContainer.layer.cornerRadius;
            }];
        } else {
            [UIView addKeyframeWithRelativeStartTime:0.0 relativeDuration:0.52 animations:^{
                shadowSurface.frame = stageFrame;
                shadowSurface.alpha = 0.96;
                shadowSurface.layer.transform = [self genieTransformWithProgress:0.58 towardLeft:towardLeft presenting:NO];
                shadowSurface.layer.shadowOpacity = 0.08;
                shadowSurface.layer.shadowRadius = 10.0;
                shadowSurface.layer.shadowPath = [UIBezierPath bezierPathWithRoundedRect:shadowSurface.bounds cornerRadius:self.clippingContainer.layer.cornerRadius * 1.8].CGPath;
                imageView.layer.cornerRadius = self.clippingContainer.layer.cornerRadius * 1.8;
            }];
            [UIView addKeyframeWithRelativeStartTime:0.34 relativeDuration:0.54 animations:^{
                shadowSurface.frame = iconFrame;
                shadowSurface.alpha = 0.0;
                shadowSurface.layer.transform = CATransform3DIdentity;
                shadowSurface.layer.shadowOpacity = 0.0;
                shadowSurface.layer.shadowRadius = 2.0;
                shadowSurface.layer.shadowPath = [UIBezierPath bezierPathWithRoundedRect:shadowSurface.bounds cornerRadius:CV3Style.iconCornerRadius].CGPath;
                imageView.layer.cornerRadius = CV3Style.iconCornerRadius;
            }];
        }
    } completion:^(BOOL finished) {
        [shadowSurface removeFromSuperview];
        CV3LogStashAnimation(@"[StashAnimation] id=%@ direction=%@ phase=surface.completion finished=%d elapsed_ms=%.1f",
                     traceID,
                     direction,
                     finished,
                     (CACurrentMediaTime() - surfaceStartTime) * 1000.0);
        if (completion) completion();
    }];
}

- (UIEdgeInsets)currentSafeAreaInsets {
    UIEdgeInsets safeArea = self.safeAreaInsets;
    if (safeArea.top == 0 && safeArea.bottom == 0 && safeArea.left == 0 && safeArea.right == 0) {
        UIWindow *keyWindow = nil;
        if (@available(iOS 15.0, *)) {
            keyWindow = self.windowScene.keyWindow;
        } else {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
            keyWindow = [UIApplication sharedApplication].keyWindow;
#pragma clang diagnostic pop
        }
        safeArea = keyWindow ? keyWindow.safeAreaInsets : UIEdgeInsetsMake(47, 0, 34, 0);
    }
    return safeArea;
}
+ (void)handleExposeBackdropTap:(UITapGestureRecognizer *)sender {
    CV3ExitExposeModeSelectingWindow(nil, NO);
}

+ (void)handleExposeBackdropPan:(UIPanGestureRecognizer *)sender {
    if (!isGlobalExposeActive || !globalExposeBackdrop) return;

    UIView *gestureView = globalExposeContentView ?: globalExposeBackdrop;
    CGPoint translation = [sender translationInView:gestureView];
    if (sender.state == UIGestureRecognizerStateChanged) {
        globalExposeScrollOffset -= globalExposeIsLandscape ? translation.x : translation.y;
        [sender setTranslation:CGPointZero inView:gestureView];
        CV3LayoutExposeWindowsAnimated(NO);
        CV3UpdateExposeSelectionForViewportCenter();
    } else if (sender.state == UIGestureRecognizerStateEnded ||
               sender.state == UIGestureRecognizerStateCancelled ||
               sender.state == UIGestureRecognizerStateFailed) {
        CGRect layoutBounds = globalExposeContentView ? globalExposeContentView.bounds : globalExposeBackdrop.bounds;
        globalExposeScrollOffset = CV3ClampCGFloat(globalExposeScrollOffset,
                                                   0.0,
                                                   CV3ExposeMaxScrollForWindows(globalExposeWindows, layoutBounds, globalExposeIsLandscape));
        CV3LayoutExposeWindowsAnimated(YES);
        CV3UpdateExposeSelectionForViewportCenter();
    }
}

- (void)handleExposeSelectionTap:(UITapGestureRecognizer *)sender {
    if (!globalExposeWindows || sender.state != UIGestureRecognizerStateEnded) return;

    NSInteger index = [globalExposeWindows indexOfObject:self];
    if (index == NSNotFound) return;

    if (index != globalExposeSelectedIndex) {
        CV3UpdateExposeSelection(index);
        return;
    }

    CV3ExitExposeModeSelectingWindow(self, YES);
}

- (void)handleExposeCardPan:(UIPanGestureRecognizer *)sender {
    [CV3FloatingAppWindow handleExposeBackdropPan:sender];
}

- (void)enforcePortraitWindowGeometry {
    if (self.isStashed || self.isClosing) return;

    self.transform = CGAffineTransformIdentity;
    CV3SceneRotationContext context = CV3MakeSceneRotationContext(self.windowScene);
    UIInterfaceOrientation effectiveOrientation =
        self.prefersLandscapePresentation && UIInterfaceOrientationIsLandscape(self.hostedContentOrientation)
            ? self.hostedContentOrientation
            : context.orientation;
    if (!CV3IsValidInterfaceOrientation(effectiveOrientation)) {
        effectiveOrientation = UIInterfaceOrientationPortrait;
    }

    BOOL wantsLandscape = CV3ShellShouldBeLandscape(self, effectiveOrientation);
    BOOL shellIsLandscape = self.bounds.size.width > self.bounds.size.height;
    if (wantsLandscape != shellIsLandscape && self.bounds.size.width > 0.0 && self.bounds.size.height > 0.0) {
        CGSize size = self.bounds.size;
        self.bounds = CGRectMake(0, 0, size.height, size.width);
    }

    self.targetOrientation = effectiveOrientation;
    self.baseRotationTransform = CV3RotationTransformForInterfaceOrientation(effectiveOrientation);
    // A landscape-only client is simulated inside a portrait SpringBoard
    // Scene. Its outer chrome already has landscape bounds, so rotating the
    // root again would mix portrait chrome with a landscape hosted canvas.
    self.rootTransformContainer.transform = self.prefersLandscapePresentation
        ? CV3HostedContentRotationInScene(self)
        : self.baseRotationTransform;
}

- (CGSize)portraitLogicalSizeForDisplayBounds:(CGRect)displayBounds widthRatio:(CGFloat)widthRatio {
    if (CGRectIsEmpty(displayBounds)) {
        displayBounds = CV3DisplayBoundsForWindow(self);
    }

    CGFloat shortSide = MIN(displayBounds.size.width, displayBounds.size.height);
    CGFloat longSide = MAX(displayBounds.size.width, displayBounds.size.height);
    CGFloat aspect = longSide / MAX(shortSide, 1.0);
    CGFloat logicalW = shortSide * widthRatio;
    return CGSizeMake(MAX(1.0, logicalW), MAX(1.0, logicalW * aspect));
}

- (CGSize)physicalFloatingSizeForLogicalWidth:(CGFloat)logicalWidth displayBounds:(CGRect)displayBounds orientation:(UIInterfaceOrientation)orientation {
    if (CGRectIsEmpty(displayBounds)) {
        displayBounds = CV3DisplayBoundsForWindow(self);
    }

    CGFloat shortSide = MIN(displayBounds.size.width, displayBounds.size.height);
    CGFloat longSide = MAX(displayBounds.size.width, displayBounds.size.height);
    CGFloat aspect = longSide / MAX(shortSide, 1.0);
    CGSize logicalSize = CGSizeMake(MAX(1.0, logicalWidth), MAX(1.0, logicalWidth * aspect));
    CGSize physicalSize = UIInterfaceOrientationIsLandscape(orientation)
        ? CGSizeMake(logicalSize.height, logicalSize.width)
        : logicalSize;

    UIEdgeInsets safeArea = [self currentSafeAreaInsets];
    CGFloat breath = CV3Style.safeAreaBreath;
    CGFloat visibleW = MAX(1.0, displayBounds.size.width - safeArea.left - safeArea.right - breath * 2.0);
    CGFloat visibleH = MAX(1.0, displayBounds.size.height - safeArea.top - safeArea.bottom - breath * 2.0);
    CGFloat fitScale = MIN(1.0, MIN(visibleW / MAX(physicalSize.width, 1.0),
                                   visibleH / MAX(physicalSize.height, 1.0)));
    if (fitScale < 1.0) {
        physicalSize.width *= fitScale;
        physicalSize.height *= fitScale;
    }

    return CGSizeMake(MAX(1.0, physicalSize.width), MAX(1.0, physicalSize.height));
}

- (CGSize)defaultPhysicalFloatingSizeForOrientation:(UIInterfaceOrientation)orientation displayBounds:(CGRect)displayBounds {
    CGSize logicalSize = [self portraitLogicalSizeForDisplayBounds:displayBounds widthRatio:kCV3FloatingDefaultWidthRatio];
    return [self physicalFloatingSizeForLogicalWidth:logicalSize.width displayBounds:displayBounds orientation:orientation];
}

- (void)applyInterfaceOrientation:(UIInterfaceOrientation)orientation force:(BOOL)force {
    if (!CV3IsValidInterfaceOrientation(orientation)) return;

    CV3SceneRotationContext context = CV3MakeSceneRotationContext(self.windowScene);
    context.orientation = orientation;
    context.isLandscape = UIInterfaceOrientationIsLandscape(orientation);
    context.transform = CV3RotationTransformForInterfaceOrientation(orientation);
    [self applySceneRotationContext:context force:force];
}

- (void)applySceneRotationContext:(CV3SceneRotationContext)context force:(BOOL)force {
    if (!CV3IsValidInterfaceOrientation(context.orientation) || self.isClosing) return;
    [self recordOrientationTrace:@"applySceneRotationContext.begin" force:YES];

    // A landscape-only client owns the initial presentation orientation. The
    // display Scene may still report portrait while the app is being hosted;
    // letting that value overwrite the window produces a portrait shell with
    // a partially rotated landscape client.
    if (!self.isStashed && self.prefersLandscapePresentation &&
        UIInterfaceOrientationIsLandscape(self.hostedContentOrientation) &&
        !UIInterfaceOrientationIsLandscape(context.orientation)) {
        context.orientation = self.hostedContentOrientation;
        context.isLandscape = YES;
        context.transform = CV3RotationTransformForInterfaceOrientation(context.orientation);
    }

    BOOL orientationChanged = (self.lastLayoutOrientation != context.orientation);
    BOOL rotationChanged = !CGAffineTransformEqualToTransform(self.baseRotationTransform, context.transform);

    CV3LastTrustedInterfaceOrientation = context.orientation;
    self.targetOrientation = context.orientation;

    if (self.isStashed) {
        CGPoint preferredCenter = CGRectIsEmpty(self.preStashFrame) ? self.center : CGPointMake(CGRectGetMidX(self.preStashFrame), CGRectGetMidY(self.preStashFrame));
        if (CGRectIsEmpty(self.preStashFrame)) {
            self.preStashFrame = [self restorableFrameForOrientation:context.orientation preferredCenter:preferredCenter];
        } else {
            self.preStashFrame = [self safeAreaClampedFrame:self.preStashFrame preferredCenter:preferredCenter preserveSize:YES];
        }
        if (orientationChanged || !CV3IsValidInterfaceOrientation(self.stashedRestoreSnapshotOrientation)) {
            [self updateStashedRestoreSnapshotForOrientation:context.orientation];
        }
        self.baseRotationTransform = context.transform;
        self.lastLayoutOrientation = context.orientation;
        self.rootTransformContainer.transform = CGAffineTransformIdentity;
        [self normalizeStashedGrabberLayout];
        [self recordOrientationTrace:@"applySceneRotationContext.stashed" force:YES];
        return;
    }

    if (!force && !orientationChanged && !rotationChanged) {
        [self recordOrientationTrace:@"applySceneRotationContext.noChange" force:NO];
        return;
    }

    CGPoint oldCenter = self.center;
    CGRect screenBounds = CGRectIsEmpty(context.sceneBounds) ? CV3DisplayBoundsForWindow(self) : context.sceneBounds;
    CGSize currentSize = self.bounds.size;
    BOOL currentLandscape = currentSize.width > currentSize.height;
    BOOL targetLandscape = CV3ShellShouldBeLandscape(self, context.orientation);
    CGSize newSize = currentSize;
    // Preserve the user's current logical window size. A physical rotation
    // swaps the shell axes; recomputing the default size here loses custom
    // sizing and can leave a portrait-shaped window in landscape.
    if (currentSize.width <= 1.0 || currentSize.height <= 1.0) {
        newSize = [self defaultPhysicalFloatingSizeForOrientation:context.orientation displayBounds:screenBounds];
    } else if (currentLandscape != targetLandscape) {
        newSize = CGSizeMake(currentSize.height, currentSize.width);
    }

    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    self.transform = CGAffineTransformIdentity;
    self.bounds = CGRectMake(0, 0, MAX(1.0, newSize.width), MAX(1.0, newSize.height));
    
    self.center = oldCenter;

    self.baseRotationTransform = context.transform;
    self.rootTransformContainer.transform = self.prefersLandscapePresentation
        ? CV3HostedContentRotationInScene(self)
        : context.transform;
    
    [CATransaction commit];

    // 转屏时将窗口像果冻一样平滑弹跳居中，加入级联偏移防止多窗口重叠，并保证安全区域避让
    if (orientationChanged) {
        NSInteger index = 0;
        if (floatingWindows) {
            index = [floatingWindows indexOfObject:self];
            if (index == NSNotFound) index = 0;
        }
        CGFloat cascade = index * kCV3RotationCascadeStep;
        CGRect displayBounds = CGRectIsEmpty(context.sceneBounds) ? CV3DisplayBoundsForWindow(self) : context.sceneBounds;
        [UIView animateWithDuration:0.55
                              delay:0
             usingSpringWithDamping:0.48 // 果冻物理阻尼系数
              initialSpringVelocity:0.6
                            options:UIViewAnimationOptionCurveEaseInOut | UIViewAnimationOptionBeginFromCurrentState
                         animations:^{
            self.center = CGPointMake(CGRectGetMidX(displayBounds) + cascade, CGRectGetMidY(displayBounds) + cascade);
            [self clampToScreenBounds];
        } completion:nil];
    }

    self.lastLayoutOrientation = context.orientation;
    [self syncHostedSceneLayoutForce:YES];
    [self setNeedsLayout];
    [self layoutIfNeeded];
    [self clampToScreenBounds];
    [self syncWindowBoundsToClient];
    [self recordOrientationTrace:@"applySceneRotationContext.end" force:YES];
}

- (void)applyTrustedOrientationNow {
    [self applyInterfaceOrientation:CV3TrustedInterfaceOrientation(self.windowScene) force:NO];
}

- (CGRect)restorableFrameForOrientation:(UIInterfaceOrientation)orientation preferredCenter:(CGPoint)preferredCenter {
    CGRect screenBounds = CV3DisplayBoundsForWindow(self);
    CGSize targetSize = [self defaultPhysicalFloatingSizeForOrientation:orientation displayBounds:screenBounds];

    CGRect targetFrame = CGRectMake(preferredCenter.x - targetSize.width * 0.5,
                                    preferredCenter.y - targetSize.height * 0.5,
                                    targetSize.width,
                                    targetSize.height);
    return [self safeAreaClampedFrame:targetFrame preferredCenter:preferredCenter preserveSize:YES];
}

- (CGRect)safeAreaClampedFrame:(CGRect)frame preferredCenter:(CGPoint)preferredCenter preserveSize:(BOOL)preserveSize {
    CGRect screenBounds = CV3DisplayBoundsForWindow(self);
    UIEdgeInsets safeArea = [self currentSafeAreaInsets];
    CGFloat breath = CV3Style.safeAreaBreath;
    CGFloat maxWidth = screenBounds.size.width - safeArea.left - safeArea.right - breath * 2.0;
    CGFloat maxHeight = screenBounds.size.height - safeArea.top - safeArea.bottom - breath * 2.0;
    CGSize targetSize = frame.size;

    if (!preserveSize && targetSize.width > 0.0 && targetSize.height > 0.0) {
        CGFloat widthScale = maxWidth / targetSize.width;
        CGFloat heightScale = maxHeight / targetSize.height;
        CGFloat scale = MIN(1.0, MIN(widthScale, heightScale));
        if (scale > 0.0 && scale < 1.0) {
            targetSize = CGSizeMake(targetSize.width * scale, targetSize.height * scale);
        }
    }

    targetSize.width = MAX(1.0, targetSize.width);
    targetSize.height = MAX(1.0, targetSize.height);
    CGRect targetFrame = CGRectMake(preferredCenter.x - targetSize.width * 0.5,
                                    preferredCenter.y - targetSize.height * 0.5,
                                    targetSize.width,
                                    targetSize.height);
    CGFloat minX = safeArea.left + breath;
    CGFloat minY = safeArea.top + breath;
    CGFloat maxX = screenBounds.size.width - safeArea.right - breath - targetFrame.size.width;
    CGFloat maxY = screenBounds.size.height - safeArea.bottom - breath - targetFrame.size.height;
    if (maxX < minX) maxX = minX;
    if (maxY < minY) maxY = minY;
    targetFrame.origin.x = MIN(MAX(targetFrame.origin.x, minX), maxX);
    targetFrame.origin.y = MIN(MAX(targetFrame.origin.y, minY), maxY);
    return targetFrame;
}

- (CGRect)restorableFramePreservingStashedSizeForOrientation:(UIInterfaceOrientation)orientation preferredCenter:(CGPoint)preferredCenter {
    if (CGRectIsEmpty(self.preStashFrame)) {
        return [self restorableFrameForOrientation:orientation preferredCenter:preferredCenter];
    }
    return [self safeAreaClampedFrame:self.preStashFrame preferredCenter:preferredCenter preserveSize:NO];
}

- (CGRect)visiblePortraitContentFrame {
    if (self.rootTransformContainer && !CGRectIsEmpty(self.rootTransformContainer.bounds)) {
        return self.rootTransformContainer.bounds;
    }
    return self.bounds;
}

- (CGRect)currentHostedSceneBounds {
    // This proxy lives inside rootTransformContainer's upright logical coordinate
    // space. The root container applies the physical device rotation, while the
    // hosted Scene settings below describe the app's own content orientation.
    id sceneSettings = self.targetScene
        ? CV3InvokeObject(self.targetScene, @selector(settings))
        : nil;
    UIInterfaceOrientation hostedOrientation = CV3IsValidInterfaceOrientation(self.hostedContentOrientation)
        ? self.hostedContentOrientation
        : UIInterfaceOrientationPortrait;
    CGAffineTransform localRotation = CV3HostedContentRotationInScene(self);
    BOOL localRotationSwapsAxes = fabs(localRotation.b) > 0.5 || fabs(localRotation.c) > 0.5;
    // When SpringBoard remains portrait but the hosted App requests landscape,
    // FrontBoard still publishes the remote Scene in portrait reference
    // coordinates. Preserve that complete 430x932 canvas and rotate it once in
    // rootTransformContainer. Asking the host for 932x430 at the same time
    // stretches only the container; the producer's valid 430-wide Surface then
    // occupies the left half and leaves the remainder transparent.
    CGSize canvasSize = localRotationSwapsAxes
        ? CV3CanonicalApplicationSceneFrame(sceneSettings).size
        : CV3HostedCanvasSizeForOrientation(hostedOrientation, sceneSettings);
    return CGRectMake(0, 0, canvasSize.width, canvasSize.height);
}

- (BOOL)applyHostedSceneLayoutToSettings:(id)settings force:(BOOL)force {
    if (!settings) return NO;

    BOOL modified = NO;
    UIInterfaceOrientation targetOrientation = CV3IsValidInterfaceOrientation(self.hostedContentOrientation)
        ? self.hostedContentOrientation
        : UIInterfaceOrientationPortrait;
    // FBS scene frames use the display's portrait reference coordinates. The
    // host presentation rotates this canonical canvas when the hosted App and
    // SpringBoard Scene differ; swapping this frame itself leaves only the
    // producer's original 430-wide content visible in a 932-wide container.
    CGRect targetFrame = CV3CanonicalApplicationSceneFrame(settings);
    CV3LogToFile(@"[Strict] trace=%@ phase=settingsLayout.begin force=%d targetOrientation=%ld targetFrame=%@ before={%@} resolver={%@}",
                 self.coldLaunchTraceID, force, (long)targetOrientation,
                 NSStringFromCGRect(targetFrame), CV3SceneSettingsFingerprint(settings),
                 CV3OrientationResolverTrace(settings));

    @try {
        if (force ||
            fabs(((FBSMutableSceneSettings *)settings).frame.size.width - targetFrame.size.width) > 0.1 ||
            fabs(((FBSMutableSceneSettings *)settings).frame.size.height - targetFrame.size.height) > 0.1) {
            if ([settings respondsToSelector:@selector(setFrame:)]) {
                [(FBSMutableSceneSettings *)settings setFrame:targetFrame];
                modified = YES;
                CV3LogToFile(@"[Strict] trace=%@ phase=settingsLayout.frame.written value=%@ now={%@}",
                             self.coldLaunchTraceID, NSStringFromCGRect(targetFrame),
                             CV3SceneSettingsFingerprint(settings));
            }
        }
    } @catch (NSException *e) {
        CV3LogToFile(@"[Strict] trace=%@ phase=settingsLayout.frame.exception exception=%@",
                     self.coldLaunchTraceID, e);
    }

    NSInteger orientationValue = (NSInteger)targetOrientation;
    modified |= CV3SetIntegerSetting(settings,
                                     @selector(interfaceOrientation),
                                     @selector(setInterfaceOrientation:),
                                     @"interfaceOrientation",
                                     orientationValue,
                                     force);
    CV3LogToFile(@"[Strict] trace=%@ phase=settingsLayout.interfaceOrientation.applied requested=%ld modified=%d now={%@}",
                 self.coldLaunchTraceID, (long)orientationValue, modified,
                 CV3SceneSettingsFingerprint(settings));

    UIDeviceOrientation deviceOrientation = CV3DeviceOrientationFromInterface(targetOrientation);
    if (deviceOrientation != UIDeviceOrientationUnknown) {
        modified |= CV3SetIntegerSetting(settings,
                                         @selector(deviceOrientation),
                                         @selector(setDeviceOrientation:),
                                         @"deviceOrientation",
                                         (NSInteger)deviceOrientation,
                                         force);
        CV3LogToFile(@"[Strict] trace=%@ phase=settingsLayout.deviceOrientation.applied requested=%ld modified=%d now={%@}",
                     self.coldLaunchTraceID, (long)deviceOrientation, modified,
                     CV3SceneSettingsFingerprint(settings));
    }

    modified |= CV3ApplyLockedOrientationTraitsToSettings(settings, targetOrientation, force);
    CV3LogToFile(@"[Strict] trace=%@ phase=settingsLayout.traits.applied target=%ld modified=%d traits=%@ clientTraits=%@ preferredTraits=%@ effectiveTraits=%@",
                 self.coldLaunchTraceID, (long)targetOrientation, modified,
                 CV3SafeSettingValue(settings, @"traitCollection"),
                 CV3SafeSettingValue(settings, @"clientTraitCollection"),
                 CV3SafeSettingValue(settings, @"preferredTraitCollection"),
                 CV3SafeSettingValue(settings, @"effectiveTraitCollection"));

    UIInterfaceOrientation presentationOrientation = CV3HostedPresentationOrientation(self);
    BOOL sceneBoundsMatchTarget =
        CV3SceneSettingsBoundsMatchOrientation(settings, targetOrientation);
    BOOL needsCrossOrientationMap =
        CV3IsValidInterfaceOrientation(presentationOrientation) &&
        UIInterfaceOrientationIsLandscape(presentationOrientation) !=
            UIInterfaceOrientationIsLandscape(targetOrientation) &&
        !sceneBoundsMatchTarget;
    id currentOrientationResolver = CV3OrientationMapResolverFromSettings(settings);
    if (needsCrossOrientationMap) {
        if (!self.hasCapturedOrientationMapBaseline) {
            self.originalOrientationMapResolver = CV3OrientationMapResolverFromSettings(settings);
            SEL modeGetter = NSSelectorFromString(@"interfaceOrientationMode");
            if ([settings respondsToSelector:modeGetter]) {
                @try {
                    self.originalInterfaceOrientationMode =
                        ((NSInteger (*)(id, SEL))objc_msgSend)(settings, modeGetter);
                    self.hasOriginalInterfaceOrientationMode = YES;
                } @catch (__unused NSException *exception) {}
            }
            self.hasCapturedOrientationMapBaseline = YES;
        }

        BOOL mappingChanged =
            self.mappedPresentationOrientation != presentationOrientation ||
            self.mappedHostedOrientation != targetOrientation;
        BOOL resolverDrifted = !CV3OrientationMapResolverMatches(
            currentOrientationResolver, presentationOrientation, targetOrientation);
        BOOL mappingStateChanged = !self.crossOrientationMapApplied || mappingChanged || resolverDrifted;
        BOOL mapModified = CV3ApplyCrossOrientationMapToSettings(
            settings, presentationOrientation, targetOrientation,
            force || !self.crossOrientationMapApplied || mappingChanged || resolverDrifted);
        modified |= mapModified;
        if (mapModified || CV3OrientationMapResolverFromSettings(settings)) {
            self.crossOrientationMapApplied = YES;
            self.activeOrientationMapResolver = CV3OrientationMapResolverFromSettings(settings);
            self.mappedPresentationOrientation = presentationOrientation;
            self.mappedHostedOrientation = targetOrientation;
        }
        if (mapModified && mappingStateChanged && self.hostView) {
            self.hostPresentationRepublishPending = YES;
            CV3LogToFile(@"[HostRepublish] trace=%@ phase=marked reason=orientationMapChanged host=%p contextId=%@ presentation=%ld hosted=%ld",
                         self.coldLaunchTraceID, self.hostView,
                         CV3HostedLayerContextID(self.hostView.layer) ?: @"nil",
                         (long)presentationOrientation, (long)targetOrientation);
        }
        CV3LogToFile(@"[Strict] trace=%@ phase=settingsLayout.orientationMap needs=1 presentation=%ld hosted=%ld modified=%d resolver={%@}",
                     self.coldLaunchTraceID, (long)presentationOrientation,
                     (long)targetOrientation, mapModified,
                     CV3OrientationResolverTrace(settings));
    } else if (self.hasCapturedOrientationMapBaseline ||
               CV3OrientationMapResolverMatches(currentOrientationResolver,
                                                presentationOrientation,
                                                targetOrientation)) {
        // Effective Scene bounds already own the requested orientation. A
        // canonical cross-axis resolver rotates those pixels a second time.
        modified |= CV3RestoreCrossOrientationMapOnSettings(settings, nil, 0, YES);
        self.originalOrientationMapResolver = nil;
        self.activeOrientationMapResolver = nil;
        self.hasOriginalInterfaceOrientationMode = NO;
        self.hasCapturedOrientationMapBaseline = NO;
        self.crossOrientationMapApplied = NO;
        self.mappedPresentationOrientation = UIInterfaceOrientationUnknown;
        self.mappedHostedOrientation = UIInterfaceOrientationUnknown;
        self.hostPresentationRepublishPending = NO;
        CV3LogToFile(@"[Strict] trace=%@ phase=settingsLayout.orientationMap cleared presentation=%ld hosted=%ld boundsMatch=%d resolver={%@}",
                     self.coldLaunchTraceID, (long)presentationOrientation,
                     (long)targetOrientation, sceneBoundsMatchTarget,
                     CV3OrientationResolverTrace(settings));
    }

    CV3LogToFile(@"[Strict] trace=%@ phase=settingsLayout.end modified=%d after={%@} resolver={%@}",
                 self.coldLaunchTraceID, modified, CV3SceneSettingsFingerprint(settings),
                 CV3OrientationResolverTrace(settings));

    return modified;
}

static NSString *CV3VideoLayerValue(id object, NSString *key) {
    if (!object || key.length == 0) return @"nil";
    @try {
        id value = [object valueForKey:key];
        return value ? [value description] : @"nil";
    } @catch (__unused NSException *exception) {
        return @"n/a";
    }
}

static void CV3CollectVideoFullscreenLayers(CALayer *layer,
                                            NSString *path,
                                            NSUInteger depth,
                                            NSMutableArray<NSString *> *entries) {
    if (!layer || depth > 12 || entries.count >= 64) return;

    CALayer *presentation = layer.presentationLayer;
    id contents = nil;
    @try { contents = layer.contents; } @catch (__unused NSException *exception) {}
    [entries addObject:[NSString stringWithFormat:
        @"%@:%@ frame=%@ bounds=%@ position=%@ anchor=%@ presFrame=%@ presBounds=%@ affine=%@ hidden=%d opacity=%.2f masks=%d gravity=%@ contentsRect=%@ contentsScale=%.3f context=%@ contextAlt=%@ hostedLayer=%@ remoteLayer=%@ contents=%@:%p children=%lu",
        path,
        NSStringFromClass(layer.class),
        NSStringFromCGRect(layer.frame),
        NSStringFromCGRect(layer.bounds),
        NSStringFromCGPoint(layer.position),
        NSStringFromCGPoint(layer.anchorPoint),
        presentation ? NSStringFromCGRect(presentation.frame) : @"nil",
        presentation ? NSStringFromCGRect(presentation.bounds) : @"nil",
        NSStringFromCGAffineTransform(layer.affineTransform),
        layer.hidden,
        layer.opacity,
        layer.masksToBounds,
        layer.contentsGravity ?: @"nil",
        NSStringFromCGRect(layer.contentsRect),
        layer.contentsScale,
        CV3VideoLayerValue(layer, @"contextId"),
        CV3VideoLayerValue(layer, @"_contextId"),
        CV3VideoLayerValue(layer, @"hostedLayer"),
        CV3VideoLayerValue(layer, @"remoteLayer"),
        contents ? NSStringFromClass([contents class]) : @"nil",
        contents,
        (unsigned long)layer.sublayers.count]];

    NSUInteger index = 0;
    for (CALayer *child in layer.sublayers ?: @[]) {
        CV3CollectVideoFullscreenLayers(child,
                                        [path stringByAppendingFormat:@".%lu", (unsigned long)index++],
                                        depth + 1,
                                        entries);
    }
}

static NSString *CV3SceneLayerManagerAudit(FBScene *scene) {
    if (!scene) return @"scene=nil";
    id manager = CV3InvokeObject(scene, @selector(layerManager));
    if (!manager) manager = CV3SafeSettingValue(scene, @"_layerManager");
    id rawLayers = CV3InvokeObject(manager, @selector(layers));
    NSArray *layers = [rawLayers isKindOfClass:NSArray.class]
        ? rawLayers
        : ([rawLayers respondsToSelector:@selector(array)] ? [rawLayers array] : nil);
    NSMutableArray<NSString *> *entries = [NSMutableArray array];
    NSUInteger index = 0;
    for (id layer in layers ?: @[]) {
        NSMutableArray<NSString *> *values = [NSMutableArray array];
        for (NSString *key in @[@"identifier", @"level", @"role", @"contextID", @"contextId",
                                @"interfaceOrientation", @"orientation", @"frame", @"bounds",
                                @"externalSceneID", @"keyboardLayer", @"isKeyboardLayer"]) {
            [values addObject:[NSString stringWithFormat:@"%@=%@", key,
                               CV3VideoLayerValue(layer, key)]];
        }
        [entries addObject:[NSString stringWithFormat:@"%lu:%@{%@}",
                            (unsigned long)index++, NSStringFromClass([layer class]),
                            [values componentsJoinedByString:@";"]]];
    }
    return [NSString stringWithFormat:@"manager=%@:%p layers=%lu [%@]",
            manager ? NSStringFromClass([manager class]) : @"nil", manager,
            (unsigned long)layers.count, [entries componentsJoinedByString:@" | "]];
}

static NSUInteger CV3SynchronizeHostedContextLayerGeometry(CALayer *layer,
                                                            NSUInteger depth) {
    if (!layer || depth > 12) return 0;

    NSUInteger updated = 0;
    for (CALayer *child in layer.sublayers ?: @[]) {
        if ([NSStringFromClass(child.class) isEqualToString:@"CALayerHost"]) {
            CGRect expectedFrame = child.superlayer.bounds;
            if (!CGRectEqualToRect(child.frame, expectedFrame) ||
                !CGSizeEqualToSize(child.bounds.size, expectedFrame.size)) {
                child.frame = expectedFrame;
                child.bounds = CGRectMake(0, 0,
                                          CGRectGetWidth(expectedFrame),
                                          CGRectGetHeight(expectedFrame));
                updated++;
            }
        }
        updated += CV3SynchronizeHostedContextLayerGeometry(child, depth + 1);
    }
    return updated;
}

- (void)synchronizeHostedContextLayerGeometry {
    [self recordStrictSplitTrace:@"layerGeometrySync.entry" details:nil];
    if (!self.hostView || self.isClosing || self.isStashed) {
        [self recordStrictSplitTrace:@"layerGeometrySync.rejected" details:nil];
        return;
    }

    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    NSUInteger updated = CV3SynchronizeHostedContextLayerGeometry(self.hostView.layer, 0);
    [CATransaction commit];
    if (updated > 0) {
        [self.hostView.layer setNeedsLayout];
    }
    [self recordStrictSplitTrace:@"layerGeometrySync.exit"
                         details:[NSString stringWithFormat:@"updatedLayerHosts=%lu", (unsigned long)updated]];
}

- (void)recordVideoFullscreenTrace:(NSString *)phase requestedOrientation:(UIInterfaceOrientation)orientation {
    id settings = self.targetScene ? CV3InvokeObject(self.targetScene, @selector(settings)) : nil;
    CGRect settingsFrame = CGRectZero;
    @try {
        if ([settings respondsToSelector:@selector(frame)]) {
            settingsFrame = ((FBSMutableSceneSettings *)settings).frame;
        }
    } @catch (__unused NSException *exception) {}
    NSInteger settingsOrientation = CV3InvokeInteger(settings,
                                                      @selector(interfaceOrientation),
                                                      NSIntegerMin);
    NSInteger contentState = CV3InvokeInteger(self.targetScene,
                                              @selector(contentState),
                                              NSIntegerMin);
    CALayer *hostLayer = self.hostView.layer;
    CALayer *presentation = hostLayer.presentationLayer;
    NSMutableArray<NSString *> *hostLayers = [NSMutableArray array];
    CV3CollectVideoFullscreenLayers(hostLayer, @"host", 0, hostLayers);
    CV3LogVideoFullscreen(@"[DEBUG-VIDEOFULLSCREEN] phase=%@ bundle=%@ requested=%ld target=%ld hosted=%ld display=%ld prefersLandscape=%d requiresLandscape=%d stashed=%d windowFrame=%@ windowBounds=%@ rootBounds=%@ rootTransform=%@ wrapper=%@ clip=%@ proxy=%@ hostFrame=%@ hostBounds=%@ hostAttached=%d hostChildren=%lu layerFrame=%@ layerBounds=%@ presentationFrame=%@ settingsFrame=%@ settingsOrientation=%ld contentState=%ld hostLayers=[%@]",
                          phase ?: @"unknown",
                          self.bundleID ?: @"unknown",
                          (long)orientation,
                          (long)self.targetOrientation,
                          (long)self.hostedContentOrientation,
                          (long)CV3TrustedInterfaceOrientation(self.windowScene),
                          self.prefersLandscapePresentation,
                          self.requiresLandscapeContent,
                          self.isStashed,
                          NSStringFromCGRect(self.frame),
                          NSStringFromCGRect(self.bounds),
                          NSStringFromCGRect(self.rootTransformContainer.bounds),
                          NSStringFromCGAffineTransform(self.rootTransformContainer.transform),
                          NSStringFromCGRect(self.appContentWrapper.frame),
                          NSStringFromCGRect(self.clippingContainer.frame),
                          NSStringFromCGRect(self.hostContainerProxy.frame),
                          NSStringFromCGRect(self.hostView.frame),
                          NSStringFromCGRect(self.hostView.bounds),
                          self.hostView.superview == self.hostContainerProxy,
                          (unsigned long)(self.hostView.subviews.count + self.hostView.layer.sublayers.count),
                          NSStringFromCGRect(hostLayer.frame),
                          NSStringFromCGRect(hostLayer.bounds),
                          presentation ? NSStringFromCGRect(presentation.frame) : @"nil",
                          NSStringFromCGRect(settingsFrame),
                          (long)settingsOrientation,
                          (long)contentState,
                          [hostLayers componentsJoinedByString:@" | "]);
}

static NSString *CV3OrientationAxisNameForValue(UIInterfaceOrientation orientation) {
    if (UIInterfaceOrientationIsLandscape(orientation)) return @"landscape";
    if (UIInterfaceOrientationIsPortrait(orientation)) return @"portrait";
    return @"unknown";
}

static NSString *CV3OrientationAxisNameForSize(CGSize size) {
    if (size.width > size.height + 0.5) return @"landscape";
    if (size.height > size.width + 0.5) return @"portrait";
    return @"square";
}

static NSString *CV3OrientationResolverTrace(id settings) {
    if (!settings) return @"settings=nil";

    id resolver = nil;
    NSInteger mode = NSIntegerMin;
    @try {
        SEL resolverGetter = NSSelectorFromString(@"interfaceOrientationMapResolver");
        if ([settings respondsToSelector:resolverGetter]) {
            resolver = ((id (*)(id, SEL))objc_msgSend)(settings, resolverGetter);
        }
        SEL modeGetter = NSSelectorFromString(@"interfaceOrientationMode");
        if ([settings respondsToSelector:modeGetter]) {
            mode = ((NSInteger (*)(id, SEL))objc_msgSend)(settings, modeGetter);
        }
    } @catch (__unused NSException *exception) {}

    NSMutableArray<NSString *> *values = [NSMutableArray arrayWithObjects:
        [NSString stringWithFormat:@"mode=%ld", (long)mode],
        [NSString stringWithFormat:@"resolverClass=%@", resolver ? NSStringFromClass([resolver class]) : @"nil"],
        nil];
    for (NSString *key in @[@"targetOrientation", @"currentOrientation",
                             @"sourceOrientation", @"interfaceOrientation"]) {
        @try {
            id value = [resolver valueForKey:key];
            if (value) [values addObject:[NSString stringWithFormat:@"%@=%@", key, value]];
        } @catch (__unused NSException *exception) {}
    }
    if (resolver) {
        @try {
            [values addObject:[NSString stringWithFormat:@"resolver=%@", resolver]];
        } @catch (__unused NSException *exception) {}
    }
    return [values componentsJoinedByString:@" "];
}

- (void)recordSplitWindowOrientationTrace:(NSString *)phase
                     requestedOrientation:(UIInterfaceOrientation)orientation
                                   source:(NSString *)source {
    id settings = self.targetScene ? CV3InvokeObject(self.targetScene, @selector(settings)) : nil;
    UIInterfaceOrientation settingsOrientation = (UIInterfaceOrientation)CV3InvokeInteger(
        settings, @selector(interfaceOrientation), UIInterfaceOrientationUnknown);
    UIInterfaceOrientation sceneOrientation = self.windowScene
        ? CV3TrustedInterfaceOrientation(self.windowScene)
        : UIInterfaceOrientationUnknown;
    NSString *requestedAxis = CV3OrientationAxisNameForValue(orientation);
    NSString *windowAxis = CV3OrientationAxisNameForSize(self.bounds.size);
    NSString *wrapperAxis = CV3OrientationAxisNameForSize(self.appContentWrapper.bounds.size);
    NSString *hostAxis = CV3OrientationAxisNameForSize(self.hostView.bounds.size);
    BOOL requestedWindowMismatch = ![requestedAxis isEqualToString:@"unknown"] &&
        ![windowAxis isEqualToString:@"square"] &&
        ![requestedAxis isEqualToString:windowAxis];
    BOOL hostedWindowMismatch = CV3IsValidInterfaceOrientation(self.hostedContentOrientation) &&
        ![CV3OrientationAxisNameForValue(self.hostedContentOrientation) isEqualToString:windowAxis];
    BOOL settingsWindowMismatch = CV3IsValidInterfaceOrientation(settingsOrientation) &&
        ![CV3OrientationAxisNameForValue(settingsOrientation) isEqualToString:windowAxis];
    NSUInteger layerHostCount = 0;
    NSMutableArray<CALayer *> *pending = [NSMutableArray array];
    if (self.hostView.layer) [pending addObject:self.hostView.layer];
    while (pending.count > 0) {
        CALayer *layer = pending.lastObject;
        [pending removeLastObject];
        if ([NSStringFromClass(layer.class) isEqualToString:@"CALayerHost"]) layerHostCount++;
        if (layer.sublayers.count > 0) [pending addObjectsFromArray:layer.sublayers];
    }
    CV3LogWindowOrientation(@"[WindowOrientationTrace] phase=%@ bundle=%@ source=%@ requested=%ld requestedAxis=%@ target=%ld hosted=%ld settings=%ld scene=%ld windowAxis=%@ wrapperAxis=%@ hostAxis=%@ window=%@ wrapper=%@ host=%@ mismatch.requestedWindow=%d mismatch.hostedWindow=%d mismatch.settingsWindow=%d layerHosts=%lu stashed=%d closing=%d orientationResolver={%@}",
                            phase ?: @"unknown", self.bundleID ?: @"unknown", source ?: @"unknown",
                            (long)orientation, requestedAxis, (long)self.targetOrientation,
                            (long)self.hostedContentOrientation, (long)settingsOrientation,
                            (long)sceneOrientation, windowAxis, wrapperAxis, hostAxis,
                            NSStringFromCGSize(self.bounds.size),
                            NSStringFromCGSize(self.appContentWrapper.bounds.size),
                            NSStringFromCGSize(self.hostView.bounds.size),
                            requestedWindowMismatch, hostedWindowMismatch, settingsWindowMismatch,
                            (unsigned long)layerHostCount, self.isStashed, self.isClosing,
                            CV3OrientationResolverTrace(settings));
}

- (void)recordStrictSplitTrace:(NSString *)phase details:(NSString *)details {
    id settings = self.targetScene ? CV3InvokeObject(self.targetScene, @selector(settings)) : nil;
    id clientSettings = self.targetScene
        ? CV3InvokeObject(self.targetScene, NSSelectorFromString(@"clientSettings"))
        : nil;
    NSMutableArray<NSString *> *layers = [NSMutableArray array];
    CV3CollectVideoFullscreenLayers(self.hostView.layer, @"host", 0, layers);
    CGRect sceneBounds = self.windowScene ? self.windowScene.coordinateSpace.bounds : CGRectZero;
    CGRect screenBounds = self.windowScene.screen ? self.windowScene.screen.bounds : UIScreen.mainScreen.bounds;
    UIInterfaceOrientation sceneOrientation = self.windowScene
        ? self.windowScene.interfaceOrientation
        : UIInterfaceOrientationUnknown;
    CGAffineTransform calculatedRotation = CV3HostedContentRotationInScene(self);
    CGRect calculatedCanvas = [self currentHostedSceneBounds];
    BOOL presentationContext = self.hostView &&
        CV3InvokeObject(self.hostView, NSSelectorFromString(@"presentationContext")) != nil;
    CV3LogToFile(@"[Strict] trace=%@ phase=%@ details={%@} bundle=%@ generation=%lu lifecycle=%@ "
                 "flags={closing=%d stashed=%d moving=%d liveResize=%d awaitingFirst=%d focused=%d "
                 "prefersLandscape=%d requiresLandscape=%d} orientations={scene=%ld target=%ld hosted=%ld "
                 "lastLayout=%ld device=%ld} spaces={scene=%@ screen=%@ calculatedCanvas=%@ calculatedRotation=%@} "
                 "settings={%@ resolver={%@}} clientSettings={%@} contentState=%ld sceneValid=%d "
                 "views={window:%@ root:%@ wrapper:%@ clip:%@ proxy:%@ host:%@} "
                 "hosting={attached=%d presentationContext=%d requester=%@ childViews=%lu childLayers=%lu} layers=[%@]",
                 self.coldLaunchTraceID ?: @"unassigned", phase ?: @"unknown", details ?: @"none",
                 self.bundleID ?: @"nil", (unsigned long)self.sceneHostGeneration,
                 CV3HostLifecycleStateName(self.hostLifecycleState), self.isClosing, self.isStashed,
                 self.isMovingWindow, self.isLiveResizing, self.awaitingInitialRenderableContent,
                 self.isFocused, self.prefersLandscapePresentation, self.requiresLandscapeContent,
                 (long)sceneOrientation, (long)self.targetOrientation,
                 (long)self.hostedContentOrientation, (long)self.lastLayoutOrientation,
                 (long)UIDevice.currentDevice.orientation, NSStringFromCGRect(sceneBounds),
                 NSStringFromCGRect(screenBounds), NSStringFromCGRect(calculatedCanvas),
                 NSStringFromCGAffineTransform(calculatedRotation), CV3SceneSettingsFingerprint(settings),
                 CV3OrientationResolverTrace(settings), CV3SceneSettingsFingerprint(clientSettings),
                 (long)CV3InvokeInteger(self.targetScene, @selector(contentState), NSIntegerMin),
                 self.targetScene ? CV3InvokeBool(self.targetScene, @selector(isValid), YES) : NO,
                 CV3DirectionTraceView(self), CV3DirectionTraceView(self.rootTransformContainer),
                 CV3DirectionTraceView(self.appContentWrapper), CV3DirectionTraceView(self.clippingContainer),
                 CV3DirectionTraceView(self.hostContainerProxy), CV3DirectionTraceView(self.hostView),
                 self.hostView.superview == self.hostContainerProxy, presentationContext,
                 self.sceneHostingRequester ?: @"nil", (unsigned long)self.hostView.subviews.count,
                 (unsigned long)self.hostView.layer.sublayers.count,
                 [layers componentsJoinedByString:@" | "]);
}

- (void)recordProducerGeometryTrace:(NSString *)phase {
    id settings = self.targetScene ? CV3InvokeObject(self.targetScene, @selector(settings)) : nil;
    id clientSettings = self.targetScene
        ? CV3InvokeObject(self.targetScene, NSSelectorFromString(@"clientSettings"))
        : nil;
    NSMutableArray<NSString *> *layers = [NSMutableArray array];
    CV3CollectVideoFullscreenLayers(self.hostView.layer, @"host", 0, layers);
    CV3LogToFile(@"[ProducerGeometry] trace=%@ phase=%@ generation=%lu target=%@ "
                 "sceneOrientation=%ld targetOrientation=%ld hostedOrientation=%ld clientAck=%ld "
                 "sceneBounds=%@ screenBounds=%@ settings={%@} clientSettings={%@} "
                 "window={%@} root={%@} wrapper={%@} clip={%@} proxy={%@} host={%@} layers=[%@]",
                 self.coldLaunchTraceID ?: @"unassigned", phase ?: @"unknown",
                 (unsigned long)self.sceneHostGeneration,
                 CV3DiagnosticObjectFingerprint(self.targetScene),
                 (long)(self.windowScene ? self.windowScene.interfaceOrientation : UIInterfaceOrientationUnknown),
                 (long)self.targetOrientation, (long)self.hostedContentOrientation,
                 (long)self.clientAcknowledgedOrientation,
                 NSStringFromCGRect(self.windowScene ? self.windowScene.coordinateSpace.bounds : CGRectZero),
                 NSStringFromCGRect(self.windowScene.screen ? self.windowScene.screen.bounds : UIScreen.mainScreen.bounds),
                 CV3DiagnosticObjectFingerprint(settings),
                 CV3DiagnosticObjectFingerprint(clientSettings),
                 CV3DirectionTraceView(self), CV3DirectionTraceView(self.rootTransformContainer),
                 CV3DirectionTraceView(self.appContentWrapper), CV3DirectionTraceView(self.clippingContainer),
                 CV3DirectionTraceView(self.hostContainerProxy), CV3DirectionTraceView(self.hostView),
                 [layers componentsJoinedByString:@" | "]);
}

- (void)recordSurfaceOrientationAudit:(NSString *)phase force:(BOOL)force {
    if (self.isClosing) return;
    id settings = CV3InvokeObject(self.targetScene, @selector(settings));
    id clientSettings = CV3InvokeObject(self.targetScene, NSSelectorFromString(@"clientSettings"));
    UIInterfaceOrientation sceneOrientation = self.windowScene
        ? self.windowScene.interfaceOrientation : UIInterfaceOrientationUnknown;
    UIInterfaceOrientation settingsOrientation = (UIInterfaceOrientation)CV3InvokeInteger(
        settings, @selector(interfaceOrientation), UIInterfaceOrientationUnknown);
    UIInterfaceOrientation clientOrientation = (UIInterfaceOrientation)CV3InvokeInteger(
        clientSettings, @selector(interfaceOrientation), UIInterfaceOrientationUnknown);
    CGAffineTransform decision = CV3HostedContentRotationInScene(self);
    NSString *sceneAxis = CV3OrientationAxisNameForValue(sceneOrientation);
    NSString *settingsAxis = CV3OrientationAxisNameForValue(settingsOrientation);
    NSString *clientAxis = CV3OrientationAxisNameForValue(clientOrientation);
    NSString *shellAxis = CV3OrientationAxisNameForSize(self.bounds.size);
    NSString *hostAxis = CV3OrientationAxisNameForSize(self.hostView.bounds.size);
    CALayer *hostLayer = self.hostView.layer;
    CALayer *hostPresentation = hostLayer.presentationLayer;
    NSString *modelAxis = CV3OrientationAxisNameForSize(hostLayer.bounds.size);
    NSString *presentationAxis = CV3OrientationAxisNameForSize(
        hostPresentation ? hostPresentation.bounds.size : CGSizeZero);
    NSString *contextID = CV3HostedLayerContextID(hostLayer) ?: @"nil";
    id hostManagerPublic = CV3InvokeObject(self.targetScene, @selector(hostManager));
    id hostManagerPrivate = CV3SafeSettingValue(self.targetScene, @"_hostManager");
    BOOL crossAxis = ![sceneAxis isEqualToString:@"unknown"] &&
        ![clientAxis isEqualToString:@"unknown"] && ![sceneAxis isEqualToString:clientAxis];
    BOOL identityDecision = CGAffineTransformIsIdentity(decision);
    BOOL pixelOrientationUnverified = crossAxis && identityDecision;

    NSString *signature = [NSString stringWithFormat:
        @"bundle=%@ orientations={scene=%ld settings=%ld client=%ld target=%ld hosted=%ld ack=%ld mappedPresentation=%ld mappedHosted=%ld} "
         "axes={scene=%@ settings=%@ client=%@ shell=%@ host=%@ model=%@ presentation=%@} "
         "rotation={decision=%@ root=%@ proxy=%@ host=%@} "
         "surface={contextId=%@ host=%p hostClass=%@ hostSubviews=%lu hostSublayers=%lu modelBounds=%@ presentationBounds=%@} "
         "mapping={applied=%d resolver={%@}} manager={public=%@:%p private=%@:%p requester=%@ pendingRequester=%@} "
         "verdict={crossAxis=%d identityDecision=%d pixelOrientationUnverified=%d} sceneLayers={%@}",
        self.bundleID ?: @"nil", (long)sceneOrientation, (long)settingsOrientation,
        (long)clientOrientation, (long)self.targetOrientation,
        (long)self.hostedContentOrientation, (long)self.clientAcknowledgedOrientation,
        (long)self.mappedPresentationOrientation, (long)self.mappedHostedOrientation,
        sceneAxis, settingsAxis, clientAxis, shellAxis, hostAxis, modelAxis,
        presentationAxis, NSStringFromCGAffineTransform(decision),
        NSStringFromCGAffineTransform(self.rootTransformContainer.transform),
        NSStringFromCGAffineTransform(self.hostContainerProxy.transform),
        NSStringFromCGAffineTransform(self.hostView.transform), contextID, self.hostView,
        self.hostView ? NSStringFromClass(self.hostView.class) : @"nil",
        (unsigned long)self.hostView.subviews.count,
        (unsigned long)self.hostView.layer.sublayers.count,
        NSStringFromCGRect(hostLayer.bounds),
        hostPresentation ? NSStringFromCGRect(hostPresentation.bounds) : @"nil",
        self.crossOrientationMapApplied, CV3OrientationResolverTrace(settings),
        hostManagerPublic ? NSStringFromClass([hostManagerPublic class]) : @"nil", hostManagerPublic,
        hostManagerPrivate ? NSStringFromClass([hostManagerPrivate class]) : @"nil", hostManagerPrivate,
        self.sceneHostingRequester ?: @"nil", self.pendingRepublishedRequester ?: @"nil",
        crossAxis, identityDecision, pixelOrientationUnverified,
        CV3SceneLayerManagerAudit(self.targetScene)];

    CFTimeInterval now = CACurrentMediaTime();
    BOOL changed = ![signature isEqualToString:self.lastSurfaceOrientationAuditSignature];
    BOOL heartbeatDue = now - self.lastSurfaceOrientationAuditTime >= 1.0;
    if (!force && !changed && !heartbeatDue) return;
    self.lastSurfaceOrientationAuditSignature = signature;
    self.lastSurfaceOrientationAuditTime = now;
    CV3LogToFile(@"[SurfaceOrientationAudit] event=%@ phase=%@ %@",
                 changed ? @"change" : @"heartbeat", phase ?: @"unknown", signature);
}

- (void)applyHostedContentOrientation:(UIInterfaceOrientation)orientation {
    CFTimeInterval orientationStart = CACurrentMediaTime();
    [self recordSurfaceOrientationAudit:@"orientation.request.before" force:YES];
    [self recordStrictSplitTrace:@"orientation.request.received"
                         details:[NSString stringWithFormat:@"requested=%ld", (long)orientation]];
    [self recordVideoFullscreenTrace:@"applyHosted.entry" requestedOrientation:orientation];
    if (!CV3IsValidInterfaceOrientation(orientation) || self.isClosing) {
        [self recordStrictSplitTrace:@"orientation.request.rejected.invalidOrClosing"
                             details:[NSString stringWithFormat:@"requested=%ld", (long)orientation]];
        [self recordVideoFullscreenTrace:@"applyHosted.rejected.invalidOrClosing" requestedOrientation:orientation];
        return;
    }
    if (self.requiresLandscapeContent && !UIInterfaceOrientationIsLandscape(orientation)) {
        [self recordStrictSplitTrace:@"orientation.request.rejected.landscapeOnly"
                             details:[NSString stringWithFormat:@"requested=%ld", (long)orientation]];
        [self recordVideoFullscreenTrace:@"applyHosted.rejected.landscapeOnly" requestedOrientation:orientation];
        return;
    }
    UIInterfaceOrientation liveClientOrientation = CV3HostedClientOrientation(self);
    BOOL liveClientMatchesRequest =
        CV3IsValidInterfaceOrientation(liveClientOrientation) &&
        liveClientOrientation == orientation;
    if (self.hostedContentOrientation == orientation && liveClientMatchesRequest) {
        [self recordStrictSplitTrace:@"orientation.request.shortCircuit.sameOrientation"
                             details:[NSString stringWithFormat:@"requested=%ld", (long)orientation]];
        [self recordVideoFullscreenTrace:@"applyHosted.shortCircuit.sameOrientation" requestedOrientation:orientation];
        return;
    }

    BOOL repairingClientDrift = self.hostedContentOrientation == orientation &&
        CV3IsValidInterfaceOrientation(liveClientOrientation) &&
        !liveClientMatchesRequest;
    if (repairingClientDrift) {
        [self recordStrictSplitTrace:@"orientation.request.repair.clientDrift"
                             details:[NSString stringWithFormat:@"requested=%ld liveClient=%ld cachedAck=%ld",
                                      (long)orientation, (long)liveClientOrientation,
                                      (long)self.clientAcknowledgedOrientation]];
        CV3LogToFile(@"[OrientationRepair] phase=requestRepair bundle=%@ requested=%ld liveClient=%ld cachedAck=%ld",
                     self.bundleID ?: @"nil", (long)orientation,
                     (long)liveClientOrientation, (long)self.clientAcknowledgedOrientation);
    }

    [self recordStrictSplitTrace:@"orientation.state.beforeMutation"
                         details:[NSString stringWithFormat:@"requested=%ld", (long)orientation]];
    [self recordProducerGeometryTrace:@"orientation.beforeMutation"];
    self.clientAcknowledgedOrientation = UIInterfaceOrientationUnknown;
    self.hostedContentOrientation = orientation;
    self.prefersLandscapePresentation = UIInterfaceOrientationIsLandscape(orientation);
    self.targetOrientation = orientation;
    self.lastLayoutOrientation = orientation;
    [self recordStrictSplitTrace:@"orientation.state.afterMutation"
                         details:[NSString stringWithFormat:@"requested=%ld", (long)orientation]];
    [self recordProducerGeometryTrace:@"orientation.afterMutation"];
    [self syncHostedSceneLayoutForce:YES];
    [self recordStrictSplitTrace:@"orientation.afterSceneSync" details:[NSString stringWithFormat:@"elapsedMs=%.3f", (CACurrentMediaTime() - orientationStart) * 1000.0]];
    [self recordProducerGeometryTrace:@"orientation.afterSceneSync"];
    [self refreshHostViewPresentation];
    [self recordStrictSplitTrace:@"orientation.afterPresentationRefresh" details:[NSString stringWithFormat:@"elapsedMs=%.3f", (CACurrentMediaTime() - orientationStart) * 1000.0]];
    [self recordProducerGeometryTrace:@"orientation.afterPresentationRefresh"];
    [self setNeedsLayout];
    [self recordStrictSplitTrace:@"orientation.afterSetNeedsLayout" details:nil];
    [self layoutIfNeeded];
    [self recordStrictSplitTrace:@"orientation.afterLayoutIfNeeded" details:[NSString stringWithFormat:@"elapsedMs=%.3f", (CACurrentMediaTime() - orientationStart) * 1000.0]];
    [self recordProducerGeometryTrace:@"orientation.afterLayoutIfNeeded"];
    [self synchronizeHostedContextLayerGeometry];
    [self recordStrictSplitTrace:@"orientation.afterLayerGeometrySync" details:nil];
    for (NSNumber *delay in @[@0.05, @0.15]) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,
                                     (int64_t)(delay.doubleValue * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            if (self.isClosing || self.isStashed ||
                self.hostedContentOrientation != orientation) {
                [self recordStrictSplitTrace:@"orientation.delayedSync.cancelled"
                                     details:[NSString stringWithFormat:@"delay=%.3f requested=%ld", delay.doubleValue, (long)orientation]];
                return;
            }
            [self recordStrictSplitTrace:@"orientation.delayedSync.before"
                                     details:[NSString stringWithFormat:@"delay=%.3f sinceRequestMs=%.3f", delay.doubleValue, (CACurrentMediaTime() - orientationStart) * 1000.0]];
            [self synchronizeHostedContextLayerGeometry];
            [self recordStrictSplitTrace:@"orientation.delayedSync.after"
                                 details:[NSString stringWithFormat:@"delay=%.3f", delay.doubleValue]];
            [self recordProducerGeometryTrace:[NSString stringWithFormat:@"orientation.delayed.%.0fms",
                                               delay.doubleValue * 1000.0]];
        });
    }
    // Home bar placement belongs to the logical content container. Re-run it
    // after the scene orientation transaction, otherwise the bar keeps the
    // pre-hosting portrait edge while the shell is already landscape.
    [self layoutFloatingHomeBarForBounds:self.appContentWrapper.bounds];
    [self recordStrictSplitTrace:@"orientation.request.completed"
                         details:[NSString stringWithFormat:@"requested=%ld", (long)orientation]];
    [self recordSurfaceOrientationAudit:@"orientation.request.completed" force:YES];
    [self recordVideoFullscreenTrace:@"applyHosted.completed" requestedOrientation:orientation];
    CV3LogToFile(@"[VideoBridge] 已更新托管内容方向=%ld: %@", (long)orientation, self.bundleID);
}

- (BOOL)syncHostedSceneLayoutForce:(BOOL)force {
    [self recordStrictSplitTrace:@"sceneSync.entry"
                         details:[NSString stringWithFormat:@"force=%d", force]];
    if (!self.targetScene || self.isClosing || self.isStashed) {
        [self recordStrictSplitTrace:@"sceneSync.rejected.lifecycle"
                             details:[NSString stringWithFormat:@"force=%d", force]];
        return NO;
    }
    if (!force && (self.isMovingWindow || CACurrentMediaTime() < self.moveSceneSyncSuppressedUntil)) {
        [self recordStrictSplitTrace:@"sceneSync.rejected.movementGate" details:nil];
        return NO;
    }

    BOOL didUpdate = NO;
    @try {
        FBSMutableSceneSettings *settings = [[self.targetScene settings] mutableCopy];
        CV3LogToFile(@"[Strict] trace=%@ phase=sceneSync.mutable.before force=%d fingerprint={%@}",
                     self.coldLaunchTraceID, force, CV3SceneSettingsFingerprint(settings));
        didUpdate = [self applyForegroundSovereigntyToSettings:settings clearDeactivation:YES forceLayout:force];
        CV3LogToFile(@"[Strict] trace=%@ phase=sceneSync.mutable.afterApply didUpdate=%d fingerprint={%@}",
                     self.coldLaunchTraceID, didUpdate, CV3SceneSettingsFingerprint(settings));
        if (didUpdate) {
            [self recordStrictSplitTrace:@"sceneSync.commit.begin"
                                 details:[NSString stringWithFormat:@"force=%d outgoing={%@}", force, CV3SceneSettingsFingerprint(settings)]];
            [CATransaction begin];
            [CATransaction setDisableActions:YES];
            [self.targetScene updateSettings:settings withTransitionContext:nil];
            [CATransaction commit];
            [self recordStrictSplitTrace:@"sceneSync.commit.returned" details:nil];
            [self beginHostPresentationRepublishIfNeeded:@"sceneSync.commit"];
            CV3LogToFile(@"[Layout] 已同步托管 Scene 方向=%ld frame=%@", (long)self.targetOrientation, NSStringFromCGRect(((FBSMutableSceneSettings *)settings).frame));
        }
    } @catch (NSException *e) {
        [self recordStrictSplitTrace:@"sceneSync.exception" details:e.description];
        CV3LogToFile(@"[Error] syncHostedSceneLayoutForce 异常: %@", e);
    }

    [self recordStrictSplitTrace:@"sceneSync.exit"
                         details:[NSString stringWithFormat:@"didUpdate=%d", didUpdate]];
    return didUpdate;
}

- (BOOL)applyForegroundSovereigntyToSettings:(id)settings clearDeactivation:(BOOL)clearDeactivation forceLayout:(BOOL)forceLayout {
    if (!settings) return NO;

    BOOL modified = NO;
    modified |= CV3SetBoolSettingIfNeeded(settings, @selector(setForeground:), @"foreground", YES);
    modified |= CV3SetBoolSettingIfNeeded(settings, @selector(setBackgrounded:), @"backgrounded", NO);
    modified |= CV3SetBoolSettingIfNeeded(settings, NSSelectorFromString(@"setOccluded:"), @"occluded", NO);
    modified |= CV3SetIntegerSettingIfNeeded(settings, NSSelectorFromString(@"setVisibility:"), @"visibility", 2);
    // Preserve the hosted app's idle-timer policy. Forcing this scene setting to
    // YES can outlive the floating window and prevent system events that wait
    // for a normal backlight-dim transition, including automatic appearance.
    modified |= CV3SetIntegerSettingIfNeeded(settings,
                                             @selector(setInterruptionPolicy:),
                                             @"interruptionPolicy",
                                             1);

    if (clearDeactivation) {
        modified |= CV3SetIntegerSettingIfNeeded(settings,
                                                 @selector(setDeactivationReasons:),
                                                 @"deactivationReasons",
                                                 0);
    }

    modified |= [self applyHostedSceneLayoutToSettings:settings force:forceLayout];
    return modified;
}

- (void)stabilizeForegroundForWorkspaceTransition:(NSString *)reason {
    if (!self.targetScene || self.isClosing || self.isStashed) return;

    NSTimeInterval now = CACurrentMediaTime();
    if (now - self.lastForegroundSceneRepairAt < 2.5) {
        return;
    }
    self.lastForegroundSceneRepairAt = now;

    @try {
        FBSMutableSceneSettings *settings = [[self.targetScene settings] mutableCopy];
        BOOL modified = [self applyForegroundSovereigntyToSettings:settings clearDeactivation:YES forceLayout:NO];
        if (modified) {
            [self.targetScene updateSettings:settings withTransitionContext:nil];
            CV3LogToFile(@"[Continuity] 已稳定分屏前台状态(%@): %@", reason ?: @"Unknown", self.bundleID);
            CV3LogToFile(@"[Warning][PlaybackTrace] source=SpringBoard event=SceneForegroundRepaired bundle=%@ reason=%@",
                         self.bundleID, reason ?: @"Unknown");
        }

        if ([self.targetScene respondsToSelector:@selector(_setContentState:)]) {
            [self.targetScene _setContentState:2];
        }

        if (self.sceneHostingRequester.length > 0) {
            id hostManager = CV3InvokeObject(self.targetScene, @selector(hostManager));
            SEL orderFrontSelector = @selector(enableHostingForRequester:orderFront:);
            if (CV3TargetRespondsToSelector(hostManager, orderFrontSelector)) {
                ((void (*)(id, SEL, id, BOOL))objc_msgSend)(hostManager,
                                                            orderFrontSelector,
                                                            self.sceneHostingRequester,
                                                            YES);
            }
        }

        self.hostView.hidden = NO;
        self.hostView.alpha = 1.0;
        if (!self.rbsAssertion) {
            [self updateSovereigntyAssertion];
        }
    } @catch (NSException *e) {
        CV3LogToFile(@"[Error] stabilizeForegroundForWorkspaceTransition 异常: %@", e);
    }
}

- (UIButton *)chromeButtonWithTitle:(NSString *)title action:(SEL)action {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
    (void)title;
    button.tintColor = [UIColor clearColor];
    [button setTitle:nil forState:UIControlStateNormal];
    [button setImage:nil forState:UIControlStateNormal];
    button.clipsToBounds = NO;
    
    // 视觉圆点作为子视图居中
    UIView *visualDot = [[UIView alloc] initWithFrame:CGRectZero];
    visualDot.tag = 999;
    visualDot.backgroundColor = [UIColor secondaryLabelColor];
    visualDot.layer.cornerRadius = CV3Style.floatingChromeControlSize / 2.0;
    visualDot.layer.masksToBounds = YES;
    visualDot.layer.borderWidth = 0.5 / [UIScreen mainScreen].scale;
    visualDot.layer.borderColor = [[UIColor blackColor] colorWithAlphaComponent:0.18].CGColor;
    visualDot.userInteractionEnabled = NO;
    [button addSubview:visualDot];
    
    // macOS 交通灯内部图标符号
    NSString *symbolName = nil;
    if (action == @selector(handleChromeCloseAction:)) {
        symbolName = @"xmark";
    } else if (action == @selector(handleChromeMinimizeAction:)) {
        symbolName = @"minus";
    } else if (action == @selector(handleChromeModeAction:)) {
        symbolName = @"plus";
    }
    
    if (symbolName) {
        UIImageView *symbolView = [[UIImageView alloc] initWithFrame:CGRectZero];
        symbolView.tag = 998;
        if (@available(iOS 13.0, *)) {
            UIImageSymbolConfiguration *config = [UIImageSymbolConfiguration configurationWithPointSize:6.0 weight:UIImageSymbolWeightBold scale:UIImageSymbolScaleSmall];
            symbolView.image = [[UIImage systemImageNamed:symbolName withConfiguration:config] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
        }
        symbolView.tintColor = [[UIColor blackColor] colorWithAlphaComponent:0.55];
        symbolView.contentMode = UIViewContentModeScaleAspectFit;
        symbolView.userInteractionEnabled = NO;
        symbolView.alpha = 0.0; // 默认隐藏，在 touch down 或悬停时显现
        [visualDot addSubview:symbolView];
    }
    
    [button addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    return button;
}

- (void)updateFloatingChromeAppearance {
    self.windowChromeView.backgroundColor = [UIColor clearColor];
    self.windowChromeView.layer.cornerRadius = 0;
    self.chromeModeButton.hidden = NO;
    self.chromeMinimizeButton.hidden = NO;
    self.chromeCloseButton.hidden = NO;

    // 去掉药丸把手的视觉背景和描边（使其透明，仅保留手势物理拦截区）
    self.chromeDragHandle.backgroundColor = [UIColor clearColor];
    self.chromeDragHandle.layer.borderColor = [UIColor clearColor].CGColor;
    self.chromeDragHandle.layer.borderWidth = 0.0;
    self.chromeDragHandle.layer.cornerRadius = self.chromeDragHandle.bounds.size.height / 2.0;
    self.chromeDragHandle.clipsToBounds = NO; // 不裁切子圆点的物理缩放交互边界
    
    // 取消生硬投影
    self.chromeDragHandle.layer.shadowColor = [UIColor clearColor].CGColor;
    self.chromeDragHandle.layer.shadowOpacity = 0.0;

    // 默认常态显示经典的交通灯配色 (若窗口失焦则显示置灰颜色)
    NSArray<UIButton *> *buttons = @[self.chromeCloseButton, self.chromeMinimizeButton, self.chromeModeButton];
    for (UIButton *btn in buttons) {
        btn.backgroundColor = [UIColor clearColor]; // 物理按钮自身透明
        btn.layer.borderWidth = 0;
        btn.alpha = 1.0;
        
        UIView *vDot = [btn viewWithTag:999];
        if (vDot) {
            vDot.transform = CGAffineTransformIdentity;
            vDot.layer.borderWidth = 0.5 / [UIScreen mainScreen].scale;
            vDot.layer.borderColor = [[UIColor blackColor] colorWithAlphaComponent:0.12].CGColor;
            
            if (self.isFocused) {
                // 经典交通灯配色
                if (btn == self.chromeCloseButton) {
                    vDot.backgroundColor = [UIColor colorWithRed:1.00 green:0.37 blue:0.33 alpha:1.0]; // macOS 红
                } else if (btn == self.chromeMinimizeButton) {
                    vDot.backgroundColor = [UIColor colorWithRed:1.00 green:0.75 blue:0.18 alpha:1.0]; // macOS 黄
                } else if (btn == self.chromeModeButton) {
                    vDot.backgroundColor = [UIColor colorWithRed:0.15 green:0.79 blue:0.25 alpha:1.0]; // macOS 绿
                }
            } else {
                // 失焦时使用全局样式中定义的灰色
                vDot.backgroundColor = [UIColor colorWithWhite:CV3Style.trafficLightInactiveGray alpha:CV3Style.trafficLightInactiveAlpha];
            }
        }
    }

    [self.windowChromeView sendSubviewToBack:self.chromeDragHandle];
    [self.windowChromeView bringSubviewToFront:self.chromeCloseButton];
    [self.windowChromeView bringSubviewToFront:self.chromeMinimizeButton];
    [self.windowChromeView bringSubviewToFront:self.chromeModeButton];
}

- (void)layoutFloatingChromeForSize:(CGSize)size {
    CGFloat chromeScale = MIN(1.25, MAX(0.72, MIN(size.width, size.height) / 390.0));
    CGFloat chromeH = MIN(44.0 * chromeScale, MAX(0.0, size.height));
    self.windowChromeView.frame = CGRectMake(0, 0, size.width, chromeH);

    // 恒定使用完美的展开比例，取消折叠尺寸
    CGFloat capsuleX = 9.0 * chromeScale;
    CGFloat capsuleY = 6.0 * chromeScale;
    CGFloat capsuleW = CV3Style.windowHandleW * chromeScale;
    CGFloat capsuleH = CV3Style.windowHandleH * chromeScale;
    CGFloat dot = CV3Style.floatingChromeControlSize * chromeScale;

    self.chromeDragHandle.frame = CGRectMake(capsuleX, capsuleY, capsuleW, capsuleH);
    
    // 物理热区进一步放大：按钮高度提升到 54pt，宽度平分胶囊宽度 (capsuleW / 3)
    CGFloat btnW = capsuleW / 3.0;
    CGFloat btnH = 54.0;
    CGFloat btnY = capsuleY + (capsuleH - btnH) / 2.0;
    
    self.chromeCloseButton.frame = CGRectMake(capsuleX + 0 * btnW, btnY, btnW, btnH);
    self.chromeMinimizeButton.frame = CGRectMake(capsuleX + 1 * btnW, btnY, btnW, btnH);
    self.chromeModeButton.frame = CGRectMake(capsuleX + 2 * btnW, btnY, btnW, btnH);
    
    // 重新排列内部的视觉圆点
    NSArray<UIButton *> *buttons = @[self.chromeCloseButton, self.chromeMinimizeButton, self.chromeModeButton];
    for (UIButton *btn in buttons) {
        UIView *vDot = [btn viewWithTag:999];
        if (vDot) {
            // 采用 bounds 和 center 安全定位，规避 transform 状态下赋值 frame 的未定义错乱
            vDot.bounds = CGRectMake(0, 0, dot, dot);
            vDot.center = CGPointMake(btnW / 2.0, btnH / 2.0);
            vDot.layer.cornerRadius = dot / 2.0;
            
            UIView *symbolView = [vDot viewWithTag:998];
            if (symbolView) {
                CGFloat symbolSize = dot * 0.55;
                symbolView.bounds = CGRectMake(0, 0, symbolSize, symbolSize);
                symbolView.center = CGPointMake(dot / 2.0, dot / 2.0);
            }
        }
    }
    
    [self updateFloatingChromeAppearance];
}

- (void)setChromeControlsExpanded:(BOOL)expanded animated:(BOOL)animated {
    self.chromeControlsExpanded = expanded;
    void (^changes)(void) = ^{
        [self layoutFloatingChromeForSize:self.bounds.size];
        [self updateFloatingChromeAppearance];
    };
    if (animated) {
        [UIView animateWithDuration:0.18 delay:0 options:UIViewAnimationOptionCurveEaseOut animations:changes completion:nil];
    } else {
        changes();
    }
}

- (void)scheduleChromeControlsCollapse {
    // 长驻无需折叠
}

- (void)collapseChromeControlsTimerFired:(NSTimer *)timer {
    // 长驻无需折叠
}

- (void)handleChromeControlTouchDown:(id)sender {
    // 长驻无需折叠
}

- (void)handleChromeControlTap:(id)sender {
    // 恒定展开，无需操作
}

- (void)attachMoveLongPressToChromeButton:(UIButton *)button {
    if (!button) return;

    UILongPressGestureRecognizer *moveLongPress = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(handleMoveLongPress:)];
    moveLongPress.minimumPressDuration = 0.22;
    moveLongPress.delegate = self;
    [button addGestureRecognizer:moveLongPress];
}

- (void)handleChromeCloseAction:(id)sender {
    CV3ExitExposeModeIfNeeded(self, NO);
    // 隐藏窗口：触发中等关闭震动
    [[[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium] impactOccurred];
    [self closeWindow];
}

- (void)handleChromeMinimizeAction:(id)sender {
    CV3ExitExposeModeIfNeeded(self, NO);
    // 隐藏窗口：触发中等关闭震动
    [[[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium] impactOccurred];
    [self handleHideAction];
}

- (void)handleChromeModeAction:(id)sender {
    CV3ExitExposeModeIfNeeded(self, YES);
    // 绿色按钮点击时弹出多任务菜单（全屏/所有浮窗/关闭）
    CV3LogToFile(@"[MultitaskingMenu] handleChromeModeAction clicked!");
    [[[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight] impactOccurred];
    [self toggleMultitaskingMenu];
}

- (void)chromeBtnTouchDown:(UIButton *)sender {
    // 触发微弱选择震动
    [[[UISelectionFeedbackGenerator alloc] init] selectionChanged];
    [UIView animateWithDuration:0.2 delay:0 options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction animations:^{
        UIView *dot = [sender viewWithTag:999];
        if (dot) {
            dot.transform = CGAffineTransformMakeScale(0.82, 0.82);
        }
        
        NSArray<UIButton *> *buttons = @[self.chromeCloseButton, self.chromeMinimizeButton, self.chromeModeButton];
        for (UIButton *btn in buttons) {
            UIView *vDot = [btn viewWithTag:999];
            if (vDot) {
                UIView *sym = [vDot viewWithTag:998];
                if (sym) sym.alpha = 1.0;
            }
        }
    } completion:nil];
}

- (void)chromeBtnTouchUp:(UIButton *)sender {
    [UIView animateWithDuration:0.35 delay:0 usingSpringWithDamping:0.6 initialSpringVelocity:0.5 options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction animations:^{
        UIView *dot = [sender viewWithTag:999];
        if (dot) {
            dot.transform = CGAffineTransformIdentity;
        }
        
        NSArray<UIButton *> *buttons = @[self.chromeCloseButton, self.chromeMinimizeButton, self.chromeModeButton];
        for (UIButton *btn in buttons) {
            UIView *vDot = [btn viewWithTag:999];
            if (vDot) {
                UIView *sym = [vDot viewWithTag:998];
                if (sym) sym.alpha = 0.0;
            }
        }
    } completion:nil];
}

- (void)menuBtnTouchDown:(UIButton *)sender {
    [[[UISelectionFeedbackGenerator alloc] init] selectionChanged];
    [UIView animateWithDuration:CV3Style.durationShort delay:0 options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction animations:^{
        sender.transform = CGAffineTransformMakeScale(CV3Style.menuBtnScale, CV3Style.menuBtnScale);
        sender.alpha = 0.85;
        
        UIView *hoverBg = [sender viewWithTag:990];
        if (hoverBg) {
            hoverBg.alpha = 1.0;
            
            CAGradientLayer *specular = nil;
            if (hoverBg.layer.sublayers) {
                for (CALayer *sub in hoverBg.layer.sublayers) {
                    if ([[sub valueForKey:@"name"] isEqualToString:@"specular"]) {
                        specular = (CAGradientLayer *)sub;
                        break;
                    }
                }
            }
            if (specular) {
                [specular removeAnimationForKey:@"flow"];
                
                CABasicAnimation *startAnim = [CABasicAnimation animationWithKeyPath:@"startPoint"];
                startAnim.fromValue = [NSValue valueWithCGPoint:CGPointMake(-0.5, -0.5)];
                startAnim.toValue = [NSValue valueWithCGPoint:CGPointMake(1.0, 1.0)];
                
                CABasicAnimation *endAnim = [CABasicAnimation animationWithKeyPath:@"endPoint"];
                endAnim.fromValue = [NSValue valueWithCGPoint:CGPointMake(0.0, 0.0)];
                endAnim.toValue = [NSValue valueWithCGPoint:CGPointMake(1.5, 1.5)];
                
                CAAnimationGroup *group = [CAAnimationGroup animation];
                group.animations = @[startAnim, endAnim];
                group.duration = CV3Style.menuAnimDuration;
                group.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
                group.fillMode = kCAFillModeForwards;
                group.removedOnCompletion = NO;
                [specular addAnimation:group forKey:@"flow"];
            }
        }
    } completion:nil];
}

- (void)menuBtnTouchUp:(UIButton *)sender {
    [UIView animateWithDuration:CV3Style.durationMedium delay:0 usingSpringWithDamping:CV3Style.springDamping initialSpringVelocity:CV3Style.springVelocity options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction animations:^{
        sender.transform = CGAffineTransformIdentity;
        sender.alpha = 1.0;
        
        UIView *hoverBg = [sender viewWithTag:990];
        if (hoverBg) {
            hoverBg.alpha = 0.0;
            
            if (hoverBg.layer.sublayers) {
                for (CALayer *sub in hoverBg.layer.sublayers) {
                    if ([[sub valueForKey:@"name"] isEqualToString:@"specular"]) {
                        [sub removeAnimationForKey:@"flow"];
                        break;
                    }
                }
            }
        }
    } completion:nil];
}

- (void)createFloatingHomeBarIfNeeded {
    if (self.homeBarView) return;

    UIView *bar = [[UIView alloc] initWithFrame:CGRectZero];
    bar.userInteractionEnabled = YES;
    bar.backgroundColor = [UIColor clearColor];
    bar.layer.shadowColor = [UIColor blackColor].CGColor;
    bar.layer.shadowOffset = CGSizeMake(0, 6);
    bar.layer.shadowOpacity = 0.16;
    bar.layer.shadowRadius = 14.0;

    UIVisualEffectView *blurView = [[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemChromeMaterial]];
    blurView.userInteractionEnabled = NO;
    blurView.clipsToBounds = YES;
    if (@available(iOS 13.0, *)) {
        blurView.layer.cornerCurve = kCACornerCurveContinuous;
    }
    [bar addSubview:blurView];

    // Apple Design: 经典 iOS 内嵌指示胶囊条 (Home Capsule Pill)
    UIView *pill = [[UIView alloc] initWithFrame:CGRectZero];
    pill.backgroundColor = [[UIColor labelColor] colorWithAlphaComponent:0.65];
    pill.userInteractionEnabled = NO;
    pill.layer.cornerRadius = 2.25;
    if (@available(iOS 13.0, *)) {
        pill.layer.cornerCurve = kCACornerCurveContinuous;
    }
    [blurView.contentView addSubview:pill];

    CAGradientLayer *glow = [CAGradientLayer layer];
    glow.startPoint = CGPointMake(0.0, 0.5);
    glow.endPoint = CGPointMake(1.0, 0.5);
    if (@available(iOS 13.0, *)) {
        glow.cornerCurve = kCACornerCurveContinuous;
    }
    [bar.layer insertSublayer:glow atIndex:0];

    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleHomeBarTap:)];
    UILongPressGestureRecognizer *move = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(handleMoveLongPress:)];
    move.minimumPressDuration = 0.22;
    move.allowableMovement = 24.0;
    move.delegate = self;
    UIPanGestureRecognizer *resizePan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handleHomeBarResizePan:)];
    resizePan.delegate = self;

    [tap requireGestureRecognizerToFail:move];
    [tap requireGestureRecognizerToFail:resizePan];
    [bar addGestureRecognizer:tap];
    [bar addGestureRecognizer:move];
    [bar addGestureRecognizer:resizePan];

    self.homeBarView = bar;
    self.homeBarBlurView = blurView;
    self.homeBarGlowLayer = glow;
    self.homeBarPillIndicator = pill;
    self.homeBarPlacement = 0;
    UIView *homeBarContainer = self.appContentWrapper ?: self;
    [homeBarContainer addSubview:self.homeBarView];
    [self updateFloatingHomeBarAppearance];
    CV3LogHomeBarVisibility(@"[HomeBarTrace] phase=created bundle=%@ alpha=%.3f focused=%d stashed=%d frame=%@",
                            self.bundleID, self.homeBarView.alpha, self.isFocused,
                            self.isStashed, NSStringFromCGRect(self.homeBarView.frame));
    [self scheduleFloatingHomeBarAutoHide];
}

- (NSInteger)preferredHomeBarPlacementForScreenFrame:(CGRect)frame {
    UIEdgeInsets safeArea = [self currentSafeAreaInsets];
    CGRect screenBounds = CV3DisplayBoundsForWindow(self);

    // Once the floating window becomes key, its safeAreaInsets describe the
    // small hosted window rather than the display. Use the largest peer window
    // in the same scene as the display-level safe-area reference.
    UIWindow *displayWindow = nil;
    CGFloat largestWindowArea = 0.0;
    for (UIWindow *candidate in self.windowScene.windows) {
        if (candidate == self || candidate.hidden) continue;
        CGFloat area = CGRectGetWidth(candidate.bounds) * CGRectGetHeight(candidate.bounds);
        if (area > largestWindowArea) {
            largestWindowArea = area;
            displayWindow = candidate;
        }
    }
    if (displayWindow) {
        UIEdgeInsets displayInsets = displayWindow.safeAreaInsets;
        if (displayInsets.top > 0.0 || displayInsets.bottom > 0.0 ||
            displayInsets.left > 0.0 || displayInsets.right > 0.0) {
            safeArea = displayInsets;
        }
    }

    NSInteger bestScreenPlacement = 0;
    CGFloat clearances[4] = {
        MAX(0.0, screenBounds.size.height - safeArea.bottom - CGRectGetMaxY(frame)),
        MAX(0.0, CGRectGetMinY(frame) - safeArea.top),
        MAX(0.0, screenBounds.size.width - safeArea.right - CGRectGetMaxX(frame)),
        MAX(0.0, CGRectGetMinX(frame) - safeArea.left)
    };
    CGFloat largestClearance = clearances[0];
    for (NSInteger i = 1; i < 4; i++) {
        if (clearances[i] > largestClearance) {
            largestClearance = clearances[i];
            bestScreenPlacement = i;
        }
    }

    // Map the selected display edge through the actual view transform. An
    // independently landscape app does not imply that its chrome is rotated.
    UIView *container = self.appContentWrapper ?: self;
    CGRect localBounds = container.bounds;
    CGPoint localCenter = CGPointMake(CGRectGetMidX(localBounds), CGRectGetMidY(localBounds));
    CGPoint centerInWindow = [container convertPoint:localCenter toView:self];
    CGPoint edges[4] = {
        CGPointMake(localCenter.x, CGRectGetMaxY(localBounds)),
        CGPointMake(localCenter.x, CGRectGetMinY(localBounds)),
        CGPointMake(CGRectGetMaxX(localBounds), localCenter.y),
        CGPointMake(CGRectGetMinX(localBounds), localCenter.y)
    };
    CGPoint directions[4] = {CGPointMake(0, 1), CGPointMake(0, -1), CGPointMake(1, 0), CGPointMake(-1, 0)};
    CGFloat bestScore = -CGFLOAT_MAX;
    NSInteger localPlacement = bestScreenPlacement;
    for (NSInteger i = 0; i < 4; i++) {
        CGPoint edge = [container convertPoint:edges[i] toView:self];
        CGFloat dx = edge.x - centerInWindow.x;
        CGFloat dy = edge.y - centerInWindow.y;
        CGFloat length = hypot(dx, dy);
        if (length < 0.01) continue;
        CGFloat score = (dx * directions[bestScreenPlacement].x + dy * directions[bestScreenPlacement].y) / length;
        if (score > bestScore) {
            bestScore = score;
            localPlacement = i;
        }
    }
    return localPlacement;
}

- (CGRect)orientedDisplayBoundsForCurrentOrientation {
    CGRect screenBounds = CV3DisplayBoundsForWindow(self);
    CGFloat shortSide = MIN(screenBounds.size.width, screenBounds.size.height);
    CGFloat longSide = MAX(screenBounds.size.width, screenBounds.size.height);
    UIInterfaceOrientation orientation = self.targetOrientation;
    if (!CV3IsValidInterfaceOrientation(orientation)) {
        orientation = CV3TrustedInterfaceOrientation(self.windowScene);
    }

    CGSize orientedSize = UIInterfaceOrientationIsLandscape(orientation)
        ? CGSizeMake(longSide, shortSide)
        : CGSizeMake(shortSide, longSide);
    return CGRectMake(0, 0, orientedSize.width, orientedSize.height);
}

- (void)homeBarResizeLimitsForAspect:(CGFloat)aspect minWidth:(CGFloat *)minWidth maxWidth:(CGFloat *)maxWidth {
    CGRect screenBounds = [self orientedDisplayBoundsForCurrentOrientation];
    UIEdgeInsets safeArea = [self currentSafeAreaInsets];
    CGFloat breath = CV3Style.safeAreaBreath;
    CGFloat shortSide = MIN(screenBounds.size.width, screenBounds.size.height);
    CGFloat visibleWidth = MAX(1.0, screenBounds.size.width - safeArea.left - safeArea.right - breath * 2.0);
    CGFloat visibleHeight = MAX(1.0, screenBounds.size.height - safeArea.top - safeArea.bottom - breath * 2.0);
    CGFloat minW = shortSide * 0.4;
    CGFloat maxW = shortSide * 0.75;

    maxW = MIN(maxW, visibleWidth);
    maxW = MIN(maxW, visibleHeight / MAX(aspect, 1.0));
    if (maxW < minW) minW = maxW;

    if (minWidth) *minWidth = MAX(1.0, minW);
    if (maxWidth) *maxWidth = MAX(1.0, maxW);
}

- (CGRect)constrainedFloatingFrameForSize:(CGSize)size preferredCenter:(CGPoint)center {
    CGRect screenBounds = [self orientedDisplayBoundsForCurrentOrientation];
    UIEdgeInsets safeArea = [self currentSafeAreaInsets];
    CGFloat breath = CV3Style.safeAreaBreath;
    CGRect frame = CGRectMake(center.x - size.width * 0.5,
                              center.y - size.height * 0.5,
                              size.width,
                              size.height);
    CGFloat minX = safeArea.left + breath;
    CGFloat minY = safeArea.top + breath;
    CGFloat maxX = screenBounds.size.width - safeArea.right - breath - size.width;
    CGFloat maxY = screenBounds.size.height - safeArea.bottom - breath - size.height;

    if (maxX < minX) maxX = minX;
    if (maxY < minY) maxY = minY;
    frame.origin.x = MIN(MAX(frame.origin.x, minX), maxX);
    frame.origin.y = MIN(MAX(frame.origin.y, minY), maxY);
    return frame;
}

- (void)startHomeBarResizeSessionIfNeeded {
    if (self.isLiveResizing) return;

    UIImpactFeedbackGenerator *gen = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight];
    [gen impactOccurred];

    self.isLiveResizing = YES;
    [self visualShadowLayer].shadowPath = nil;
    [self startLiquidMotion];
    [UIView animateWithDuration:0.2 animations:^{
        [self visualShadowLayer].shadowOpacity = CV3Style.shadowOpacityUnfocused * 0.5;
        self.glassBackdrop.effect = nil;
        self.glassBackdrop.backgroundColor = [UIColor clearColor];
    }];

    if (self.hostView) {
        self.liveResizeSnapshotView = [self.hostView snapshotViewAfterScreenUpdates:NO];
        if (self.liveResizeSnapshotView) {
            self.liveResizeSnapshotView.frame = self.hostContainerProxy.bounds;
            self.liveResizeSnapshotView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
            [self.hostContainerProxy addSubview:self.liveResizeSnapshotView];
            self.hostView.alpha = 0;
        }
    }

    if (self.targetScene) {
        @try {
            FBSMutableSceneSettings *settings = [[self.targetScene settings] mutableCopy];
            if ([settings respondsToSelector:@selector(setInLiveResize:)]) {
                [(UIMutableApplicationSceneSettings *)settings setInLiveResize:YES];
                [self.targetScene updateSettings:settings withTransitionContext:nil];
            }
        } @catch (NSException *e) {
            CV3LogToFile(@"[Critical] Failed to set home bar live resize state: %@", e);
        }
    }
}

- (void)updateFloatingHomeBarAppearance {
    if (!self.homeBarView || !self.homeBarBlurView) return;

    CGFloat alpha = self.isFocused ? 1.0 : 0.84;
    self.homeBarView.alpha = (self.isStashed || self.isClosing || self.homeBarAutoHidden) ? 0.0 : alpha;

    self.homeBarView.layer.shadowOpacity = self.isFocused ? 0.18 : 0.10;
    self.homeBarView.layer.shadowRadius = self.isFocused ? 16.0 : 10.0;
    CV3ApplyGlassAccentStyle(self.homeBarBlurView,
                             self.homeBarBlurView.contentView,
                             self.homeBarGlowLayer,
                             nil,
                             CGRectGetHeight(self.homeBarBlurView.bounds) / 2.0,
                             self.isFocused ? 0.74 : 0.44,
                             self.isFocused);
}

- (void)setFloatingHomeBarAutoHidden:(BOOL)hidden animated:(BOOL)animated {
    if (!self.homeBarView) return;

    BOOL previousHidden = self.homeBarAutoHidden;
    CGFloat previousAlpha = self.homeBarView.alpha;
    self.homeBarAutoHidden = hidden;
    CGFloat targetAlpha = (hidden || self.isStashed || self.isClosing)
        ? 0.0
        : (self.isFocused ? 1.0 : 0.84);
    BOOL shouldTraceVisibilityChange = previousHidden != hidden ||
        fabs(previousAlpha - targetAlpha) >= 0.01;
    if (shouldTraceVisibilityChange) {
        CV3LogHomeBarVisibility(@"[HomeBarTrace] phase=visibility.request bundle=%@ hidden=%d previousHidden=%d animated=%d alpha=%.3f target=%.3f focused=%d stashed=%d closing=%d",
                                self.bundleID, hidden, previousHidden, animated,
                                previousAlpha, targetAlpha, self.isFocused,
                                self.isStashed, self.isClosing);
    }

    if (previousHidden == hidden && self.homeBarVisibilityAnimator) {
        return;
    }

    if (self.homeBarVisibilityAnimator) {
        [self.homeBarVisibilityAnimator stopAnimation:NO];
        [self.homeBarVisibilityAnimator finishAnimationAtPosition:UIViewAnimatingPositionCurrent];
        self.homeBarVisibilityAnimator = nil;
    }

    if (!animated || fabs(self.homeBarView.alpha - targetAlpha) < 0.01) {
        self.homeBarView.alpha = targetAlpha;
        if (shouldTraceVisibilityChange) {
            CV3LogHomeBarVisibility(@"[HomeBarTrace] phase=visibility.immediate bundle=%@ hidden=%d alpha=%.3f",
                                    self.bundleID, hidden, self.homeBarView.alpha);
        }
        return;
    }

    NSTimeInterval duration = hidden ? 0.20 : 0.16;
    UIViewPropertyAnimator *animator = [[UIViewPropertyAnimator alloc]
        initWithDuration:duration
        controlPoint1:CGPointMake(0.23, 1.0)
        controlPoint2:CGPointMake(0.32, 1.0)
        animations:^{
            self.homeBarView.alpha = targetAlpha;
        }];
    self.homeBarVisibilityAnimator = animator;
    __weak typeof(self) weakSelf = self;
    __weak UIViewPropertyAnimator *weakAnimator = animator;
    [animator addCompletion:^(__unused UIViewAnimatingPosition finalPosition) {
        __strong typeof(weakSelf) self = weakSelf;
        CV3LogHomeBarVisibility(@"[HomeBarTrace] phase=visibility.completed bundle=%@ hidden=%d alpha=%.3f position=%ld",
                                self.bundleID, self.homeBarAutoHidden,
                                self.homeBarView.alpha, (long)finalPosition);
        if (self.homeBarVisibilityAnimator == weakAnimator) {
            self.homeBarVisibilityAnimator = nil;
        }
    }];
    [animator startAnimation];
}

- (void)scheduleFloatingHomeBarAutoHide {
    BOOL replacingActiveTimer = self.homeBarAutoHideTimer.isValid;
    [self.homeBarAutoHideTimer invalidate];
    self.homeBarAutoHideTimer = nil;
    if (!self.homeBarView || self.isStashed || self.isClosing) return;

    NSTimer *timer = [NSTimer timerWithTimeInterval:3.0
                                             target:self
                                           selector:@selector(homeBarAutoHideTimerFired:)
                                           userInfo:nil
                                            repeats:NO];
    self.homeBarAutoHideTimer = timer;
    [[NSRunLoop mainRunLoop] addTimer:timer forMode:NSRunLoopCommonModes];
    if (!replacingActiveTimer) {
        CV3LogHomeBarVisibility(@"[HomeBarTrace] phase=timer.scheduled bundle=%@ idle=3.0 alpha=%.3f hidden=%d",
                                self.bundleID, self.homeBarView.alpha, self.homeBarAutoHidden);
    }
}

- (void)noteFloatingHomeBarInteraction {
    if (!self.homeBarView || self.isStashed || self.isClosing) return;
    CFTimeInterval now = CACurrentMediaTime();
    if (self.homeBarAutoHidden || now - self.lastHomeBarInteractionTraceTime >= 0.5) {
        CV3LogHomeBarVisibility(@"[HomeBarTrace] phase=interaction.received bundle=%@ alpha=%.3f hidden=%d timer=%d",
                                self.bundleID, self.homeBarView.alpha,
                                self.homeBarAutoHidden, self.homeBarAutoHideTimer.isValid);
        self.lastHomeBarInteractionTraceTime = now;
    }
    [self setFloatingHomeBarAutoHidden:NO animated:YES];
    [self scheduleFloatingHomeBarAutoHide];
}

- (void)homeBarAutoHideTimerFired:(NSTimer *)timer {
    if (timer != self.homeBarAutoHideTimer) return;
    self.homeBarAutoHideTimer = nil;
    if (self.isStashed || self.isClosing) return;
    CV3LogHomeBarVisibility(@"[HomeBarTrace] phase=timer.fired bundle=%@ alpha=%.3f hidden=%d",
                            self.bundleID, self.homeBarView.alpha, self.homeBarAutoHidden);
    [self setFloatingHomeBarAutoHidden:YES animated:YES];
}

- (void)layoutFloatingHomeBarForBounds:(CGRect)bounds {
    [self createFloatingHomeBarIfNeeded];
    if (!self.homeBarView) return;

    CGFloat minEdge = MIN(bounds.size.width, bounds.size.height);
    CGFloat scale = MIN(1.18, MAX(0.82, minEdge / 390.0));
    CGFloat barLength = 56.0 * scale;
    CGFloat barThickness = 18.0 * scale;
    CGFloat protrusion = MAX(4.0, barThickness * 0.42);

    self.homeBarPlacement = [self preferredHomeBarPlacementForScreenFrame:self.frame];
    self.homeBarView.bounds = CGRectMake(0, 0, barLength, barThickness);
    self.homeBarBlurView.frame = self.homeBarView.bounds;
    self.homeBarBlurView.layer.cornerRadius = barThickness / 2.0;
    self.homeBarGlowLayer.frame = self.homeBarView.bounds;
    self.homeBarGlowLayer.cornerRadius = barThickness / 2.0;

    if (self.homeBarPillIndicator) {
        CGFloat pillW = 36.0 * scale;
        CGFloat pillH = 4.5 * scale;
        self.homeBarPillIndicator.bounds = CGRectMake(0, 0, pillW, pillH);
        self.homeBarPillIndicator.center = CGPointMake(barLength * 0.5, barThickness * 0.5);
        self.homeBarPillIndicator.layer.cornerRadius = pillH * 0.5;
    }

    CGPoint center = CGPointMake(CGRectGetMidX(bounds), CGRectGetMaxY(bounds) - barThickness * 0.5 + protrusion);
    CGAffineTransform orientationTransform = CGAffineTransformIdentity;
    if (self.homeBarPlacement == 1) {
        center = CGPointMake(CGRectGetMidX(bounds), barThickness * 0.5 - protrusion);
    } else if (self.homeBarPlacement == 2) {
        center = CGPointMake(CGRectGetMaxX(bounds) - barThickness * 0.5 + protrusion, CGRectGetMidY(bounds));
        orientationTransform = CGAffineTransformMakeRotation((CGFloat)(M_PI_2));
    } else if (self.homeBarPlacement == 3) {
        center = CGPointMake(barThickness * 0.5 - protrusion, CGRectGetMidY(bounds));
        orientationTransform = CGAffineTransformMakeRotation((CGFloat)(M_PI_2));
    }

    self.homeBarView.center = center;
    self.homeBarView.transform = orientationTransform;
    [self updateFloatingHomeBarAppearance];
    [self.homeBarView.superview bringSubviewToFront:self.homeBarView];
}

- (void)handleHomeBarTap:(UITapGestureRecognizer *)gesture {
    if (gesture.state != UIGestureRecognizerStateEnded || self.isClosing || self.isStashed) return;
    CV3ExitExposeModeIfNeeded(self, NO);
    [[[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight] impactOccurred];
    [self handleHideAction];
}

- (void)handleHomeBarResizePan:(UIPanGestureRecognizer *)gesture {
    static CGFloat lastHapticOvershoot = 0;
    static BOOL hasTriggeredTopHaptic = NO;
    static BOOL hasTriggeredBottomHaptic = NO;
    static BOOL hasTriggeredSideHaptic = NO;

    if (self.isClosing || self.isStashed) return;

    if (gesture.state == UIGestureRecognizerStateBegan) {
        CV3ExitExposeModeIfNeeded(self, YES);
        self.isFullscreenMode = NO;
        self.isCompactMode = NO;
        self.initialResizeFrame = self.frame;
        self.homeBarResizeStartPlacement = self.homeBarPlacement;
        CGPoint axis = CGPointMake(1.0, 0.0);
        if (self.homeBarView) {
            CGRect barBounds = self.homeBarView.bounds;
            CGPoint left = [self.homeBarView convertPoint:CGPointMake(CGRectGetMinX(barBounds), CGRectGetMidY(barBounds)) toView:nil];
            CGPoint right = [self.homeBarView convertPoint:CGPointMake(CGRectGetMaxX(barBounds), CGRectGetMidY(barBounds)) toView:nil];
            axis = CGPointMake(right.x - left.x, right.y - left.y);
            CGFloat length = sqrt(axis.x * axis.x + axis.y * axis.y);
            if (length > 0.1) {
                axis.x /= length;
                axis.y /= length;
            } else {
                axis = CGPointMake(1.0, 0.0);
            }
        }
        if (self.homeBarResizeStartPlacement == 2 || self.homeBarResizeStartPlacement == 3) {
            axis.x = -axis.x;
            axis.y = -axis.y;
        }
        self.homeBarResizeAxis = axis;
        CGPoint commandAxis = CGPointMake(-axis.y, axis.x);
        if (self.homeBarView) {
            UIView *container = self.homeBarView.superview ?: self.appContentWrapper ?: self;
            CGPoint contentCenter = [container convertPoint:CGPointMake(CGRectGetMidX(container.bounds), CGRectGetMidY(container.bounds)) toView:nil];
            CGPoint barCenter = [self.homeBarView convertPoint:CGPointMake(CGRectGetMidX(self.homeBarView.bounds), CGRectGetMidY(self.homeBarView.bounds)) toView:nil];
            commandAxis = CGPointMake(barCenter.x - contentCenter.x, barCenter.y - contentCenter.y);
            CGFloat commandLength = sqrt(commandAxis.x * commandAxis.x + commandAxis.y * commandAxis.y);
            if (commandLength > 0.1) {
                commandAxis.x /= commandLength;
                commandAxis.y /= commandLength;
            } else {
                commandAxis = CGPointMake(-axis.y, axis.x);
            }
        }
        CGFloat dot = commandAxis.x * axis.x + commandAxis.y * axis.y;
        commandAxis = CGPointMake(commandAxis.x - axis.x * dot, commandAxis.y - axis.y * dot);
        CGFloat commandAxisLength = sqrt(commandAxis.x * commandAxis.x + commandAxis.y * commandAxis.y);
        if (commandAxisLength > 0.1) {
            commandAxis.x /= commandAxisLength;
            commandAxis.y /= commandAxisLength;
        } else {
            commandAxis = CGPointMake(-axis.y, axis.x);
        }
        self.homeBarCommandAxis = commandAxis;
        [gesture setTranslation:CGPointZero inView:nil];
        lastHapticOvershoot = 0;
        hasTriggeredTopHaptic = NO;
        hasTriggeredBottomHaptic = NO;
        hasTriggeredSideHaptic = NO;
        self.homeBarPanMode = 0;
        self.homeBarCommandProjection = 0.0;
    }

    CGPoint translation = [gesture translationInView:nil];

    if (gesture.state == UIGestureRecognizerStateChanged) {
        CGRect screenBounds = [self orientedDisplayBoundsForCurrentOrientation];
        CGFloat shortSide = MIN(screenBounds.size.width, screenBounds.size.height);
        CGFloat longSide = MAX(screenBounds.size.width, screenBounds.size.height);
        CGFloat aspect = longSide / MAX(shortSide, 1.0);
        CGFloat minAllowedWidth = 1.0;
        CGFloat maxAllowedWidth = 1.0;
        [self homeBarResizeLimitsForAspect:aspect minWidth:&minAllowedWidth maxWidth:&maxAllowedWidth];

        CGPoint axis = self.homeBarResizeAxis;
        CGFloat axisLength = sqrt(axis.x * axis.x + axis.y * axis.y);
        if (axisLength < 0.1) {
            axis = CGPointMake(1.0, 0.0);
        }
        CGFloat dominantTranslation = translation.x * axis.x + translation.y * axis.y;
        CGPoint commandAxis = self.homeBarCommandAxis;
        CGFloat commandAxisLength = sqrt(commandAxis.x * commandAxis.x + commandAxis.y * commandAxis.y);
        if (commandAxisLength < 0.1) {
            commandAxis = CGPointMake(-axis.y, axis.x);
        }
        CGFloat commandTranslation = translation.x * commandAxis.x + translation.y * commandAxis.y;

        if (self.homeBarPanMode == 0) {
            CGFloat movement = sqrt(translation.x * translation.x + translation.y * translation.y);
            if (movement < 8.0) return;

            if (fabs(commandTranslation) > fabs(dominantTranslation) * 1.15) {
                self.homeBarPanMode = 2;
                self.homeBarCommandProjection = commandTranslation;
                UIImpactFeedbackGenerator *gen = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight];
                [gen impactOccurred];
                return;
            }

            self.homeBarPanMode = 1;
            [self startHomeBarResizeSessionIfNeeded];
        }

        if (self.homeBarPanMode == 2) {
            self.homeBarCommandProjection = commandTranslation;
            return;
        }

        CGFloat initialLogicalWidth = MIN(self.initialResizeFrame.size.width, self.initialResizeFrame.size.height);
        CGFloat targetWidth = initialLogicalWidth + dominantTranslation * 0.9;

        CGFloat overshoot = 0;
        if (targetWidth < minAllowedWidth) overshoot = (minAllowedWidth - targetWidth) / (minAllowedWidth * 0.2);
        else if (targetWidth > maxAllowedWidth) overshoot = (targetWidth - maxAllowedWidth) / (maxAllowedWidth * 0.2);

        if (overshoot > 0.05 && fabs(overshoot - lastHapticOvershoot) > 0.1) {
            UIImpactFeedbackGenerator *gradientGen = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight];
            [gradientGen impactOccurredWithIntensity:MIN(1.0, overshoot)];
            lastHapticOvershoot = overshoot;
        } else if (overshoot <= 0.05) {
            lastHapticOvershoot = 0;
        }

        NSArray *windowsSnapshot = [floatingWindows copy];
        for (CV3FloatingAppWindow *other in windowsSnapshot) {
            if (other == self || other.isStashed || ![other isKindOfClass:[CV3FloatingAppWindow class]]) continue;

            CGFloat distance = sqrt(pow(self.center.x - other.center.x, 2) + pow(self.center.y - other.center.y, 2));
            CGFloat minGap = (self.bounds.size.width + other.bounds.size.width) / 2.0 + 20.0;
            if (distance < minGap) {
                targetWidth *= (0.8 + 0.2 * (distance / minGap));
            }
        }

        CGFloat finalWidth = MIN(MAX(targetWidth, minAllowedWidth), maxAllowedWidth);

        CGPoint preferredCenter = CGPointMake(CGRectGetMidX(self.initialResizeFrame), CGRectGetMidY(self.initialResizeFrame));
        CGSize physicalSize = [self physicalFloatingSizeForLogicalWidth:finalWidth
                                                           displayBounds:screenBounds
                                                            orientation:self.targetOrientation];
        CGRect newFrame = [self constrainedFloatingFrameForSize:physicalSize preferredCenter:preferredCenter];

        UIEdgeInsets safeArea = [self currentSafeAreaInsets];
        if (newFrame.origin.y < safeArea.top && !hasTriggeredTopHaptic) {
            [[[UISelectionFeedbackGenerator alloc] init] selectionChanged];
            hasTriggeredTopHaptic = YES;
        } else if (newFrame.origin.y >= safeArea.top) {
            hasTriggeredTopHaptic = NO;
        }

        if (CGRectGetMaxY(newFrame) > screenBounds.size.height - safeArea.bottom && !hasTriggeredBottomHaptic) {
            [[[UISelectionFeedbackGenerator alloc] init] selectionChanged];
            hasTriggeredBottomHaptic = YES;
        } else if (CGRectGetMaxY(newFrame) <= screenBounds.size.height - safeArea.bottom) {
            hasTriggeredBottomHaptic = NO;
        }

        BOOL hitSide = (newFrame.origin.x < safeArea.left || CGRectGetMaxX(newFrame) > screenBounds.size.width - safeArea.right);
        if (hitSide && !hasTriggeredSideHaptic) {
            [[[UISelectionFeedbackGenerator alloc] init] selectionChanged];
            hasTriggeredSideHaptic = YES;
        } else if (!hitSide) {
            hasTriggeredSideHaptic = NO;
        }

        [CATransaction begin];
        [CATransaction setDisableActions:YES];
        self.bounds = CGRectMake(0, 0, newFrame.size.width, newFrame.size.height);
        self.center = CGPointMake(CGRectGetMidX(newFrame), CGRectGetMidY(newFrame));
        [self layoutFloatingHomeBarForBounds:self.appContentWrapper.bounds];
        
        // Apple Design Rule 8: 拖拽动态 Morphing 形变暗示
        if (self.homeBarPillIndicator) {
            CGFloat scale = MIN(1.18, MAX(0.82, finalWidth / 390.0));
            CGFloat pillStretch = MIN(14.0, fabs(dominantTranslation) * 0.15);
            CGFloat pillW = 36.0 * scale + pillStretch;
            CGFloat pillH = 4.5 * scale;
            self.homeBarPillIndicator.bounds = CGRectMake(0, 0, pillW, pillH);
            self.homeBarPillIndicator.layer.cornerRadius = pillH * 0.5;
            self.homeBarPillIndicator.backgroundColor = [[UIColor labelColor] colorWithAlphaComponent:0.95];
        }
        [CATransaction commit];
        [self syncWindowBoundsToClientAndNotify:NO];
    }

    if (gesture.state == UIGestureRecognizerStateEnded ||
        gesture.state == UIGestureRecognizerStateCancelled ||
        gesture.state == UIGestureRecognizerStateFailed) {
        if (self.homeBarPanMode == 2) {
            CGPoint velocity = [gesture velocityInView:nil];
            CGPoint commandAxis = self.homeBarCommandAxis;
            CGFloat commandAxisLength = sqrt(commandAxis.x * commandAxis.x + commandAxis.y * commandAxis.y);
            if (commandAxisLength < 0.1) {
                CGPoint axis = self.homeBarResizeAxis;
                CGFloat axisLength = sqrt(axis.x * axis.x + axis.y * axis.y);
                if (axisLength < 0.1) axis = CGPointMake(1.0, 0.0);
                commandAxis = CGPointMake(-axis.y, axis.x);
            }
            CGFloat commandVelocity = velocity.x * commandAxis.x + velocity.y * commandAxis.y;
            CGFloat commandProjection = self.homeBarCommandProjection;
            self.homeBarPanMode = 0;
            self.homeBarCommandProjection = 0.0;

            if (gesture.state == UIGestureRecognizerStateEnded &&
                (fabs(commandProjection) > 42.0 || fabs(commandVelocity) > 520.0)) {
                CGFloat commandSignal = fabs(commandVelocity) > 520.0 ? commandVelocity : commandProjection;
                [[[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium] impactOccurred];
                if (commandSignal > 0.0) {
                    CV3ExitExposeModeIfNeeded(nil, NO);
                    [self activateHostedAppFullscreenAndClose];
                } else {
                    CV3ToggleExposeMode();
                }
            }
            return;
        }

        if (self.homeBarPanMode == 0 || !self.isLiveResizing) {
            self.homeBarPanMode = 0;
            self.homeBarCommandProjection = 0.0;
            return;
        }

        self.homeBarPanMode = 0;
        self.homeBarCommandProjection = 0.0;
        [self stopLiquidMotion];

        if (gesture.state != UIGestureRecognizerStateEnded) {
            self.isLiveResizing = NO;
            CGFloat minEdge = MIN(self.bounds.size.width, self.bounds.size.height);
            CGFloat finalRadius = MAX(CV3Style.adaptiveCornerRadiusMin, MIN(CV3Style.adaptiveCornerRadiusMax, minEdge * CV3Style.adaptiveCornerRadiusRatio));
            [self visualShadowLayer].shadowPath = [UIBezierPath bezierPathWithRoundedRect:[self currentVisualShadowFrame] cornerRadius:finalRadius].CGPath;
            [self animateFocusShadow:self.isFocused];
            [UIView animateWithDuration:0.35 delay:0 usingSpringWithDamping:0.80 initialSpringVelocity:0.5 options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction animations:^{
                self.glassBackdrop.effect = nil;
                self.glassBackdrop.backgroundColor = [UIColor clearColor];
                if (self.homeBarPillIndicator) {
                    CGFloat minEdge = MIN(self.bounds.size.width, self.bounds.size.height);
                    CGFloat scale = MIN(1.18, MAX(0.82, minEdge / 390.0));
                    CGFloat pillW = 36.0 * scale;
                    CGFloat pillH = 4.5 * scale;
                    self.homeBarPillIndicator.bounds = CGRectMake(0, 0, pillW, pillH);
                    self.homeBarPillIndicator.backgroundColor = [[UIColor labelColor] colorWithAlphaComponent:0.65];
                }
            } completion:nil];
        }

        CGRect screenBounds = [self orientedDisplayBoundsForCurrentOrientation];
        CGFloat shortSide = MIN(screenBounds.size.width, screenBounds.size.height);
        CGFloat longSide = MAX(screenBounds.size.width, screenBounds.size.height);
        CGFloat aspect = longSide / MAX(shortSide, 1.0);
        CGPoint initialCenter = CGPointMake(CGRectGetMidX(self.frame), CGRectGetMidY(self.frame));
        UIEdgeInsets safeArea = [self currentSafeAreaInsets];

        if (self.targetScene) {
            @try {
                FBSMutableSceneSettings *settings = [[self.targetScene settings] mutableCopy];
                if ([settings respondsToSelector:@selector(setInLiveResize:)]) {
                    [(UIMutableApplicationSceneSettings *)settings setInLiveResize:NO];
                    [self.targetScene updateSettings:settings withTransitionContext:nil];
                }
                [self setNeedsLayout];
                [self layoutIfNeeded];
            } @catch (NSException *e) {}
        }

        UIView *snapshot = self.liveResizeSnapshotView;
        self.liveResizeSnapshotView = nil;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.12 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [UIView animateWithDuration:0.25 delay:0 options:UIViewAnimationOptionCurveEaseOut | UIViewAnimationOptionBeginFromCurrentState animations:^{
                self.hostView.alpha = 1.0;
                if (snapshot) snapshot.alpha = 0;
            } completion:^(BOOL finished) {
                [snapshot removeFromSuperview];
            }];
        });

        if (gesture.state == UIGestureRecognizerStateEnded) {
            CGFloat finalWidth = MIN(self.bounds.size.width, self.bounds.size.height);
            CGPoint velocity = [gesture velocityInView:nil];
            CGPoint axis = self.homeBarResizeAxis;
            CGFloat axisLength = sqrt(axis.x * axis.x + axis.y * axis.y);
            if (axisLength < 0.1) axis = CGPointMake(1.0, 0.0);
            CGFloat axisVelocity = velocity.x * axis.x + velocity.y * axis.y;
            if (fabs(axisVelocity) > 300.0) {
                finalWidth += axisVelocity * 0.015;
            }

            CGFloat minAllowedWidth = 1.0;
            CGFloat maxAllowedWidth = 1.0;
            [self homeBarResizeLimitsForAspect:aspect minWidth:&minAllowedWidth maxWidth:&maxAllowedWidth];
            finalWidth = MAX(minAllowedWidth, MIN(maxAllowedWidth, finalWidth));

            CGFloat previousLogicalWidth = finalWidth;
            CGRect snapFrame = self.frame;
            CGFloat snapThreshold = 25.0;
            if (fabs(snapFrame.origin.y - safeArea.top) < snapThreshold) {
                snapFrame.origin.y = safeArea.top;
                [[[UISelectionFeedbackGenerator alloc] init] selectionChanged];
            }

            CGFloat currentRatio = finalWidth / shortSide;
            if (fabs(currentRatio - 0.5) < 0.03) finalWidth = shortSide * 0.5;
            else if (fabs(currentRatio - 0.75) < 0.03) finalWidth = shortSide * 0.75;
            finalWidth = MAX(minAllowedWidth, MIN(maxAllowedWidth, finalWidth));

            CGSize finalSize = [self physicalFloatingSizeForLogicalWidth:finalWidth
                                                            displayBounds:screenBounds
                                                             orientation:self.targetOrientation];
            snapFrame.size = finalSize;

            if (fabs(finalWidth - previousLogicalWidth) > 0.1) {
                snapFrame.origin.x = initialCenter.x - finalSize.width / 2.0;
                snapFrame.origin.y = initialCenter.y - finalSize.height / 2.0;
                [[[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium] impactOccurred];
            }

            snapFrame = [self constrainedFloatingFrameForSize:finalSize preferredCenter:CGPointMake(CGRectGetMidX(snapFrame), CGRectGetMidY(snapFrame))];

            CGFloat springVelocity = MIN(3.5, MAX(0.6, fabs(axisVelocity) / 750.0));
            // Stage Manager 级流体 Spring 阻尼与动量过渡
            [UIView animateWithDuration:0.45 delay:0 usingSpringWithDamping:0.82 initialSpringVelocity:springVelocity options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction animations:^{
                self.bounds = CGRectMake(0, 0, snapFrame.size.width, snapFrame.size.height);
                self.center = CGPointMake(CGRectGetMidX(snapFrame), CGRectGetMidY(snapFrame));
                [self setNeedsLayout];
                [self layoutIfNeeded];
                [self layoutFloatingHomeBarForBounds:self.appContentWrapper.bounds];
            } completion:^(BOOL finished) {
                self.isLiveResizing = NO;
                CGFloat minEdge = MIN(self.bounds.size.width, self.bounds.size.height);
                CGFloat finalRadius = MAX(CV3Style.adaptiveCornerRadiusMin, MIN(CV3Style.adaptiveCornerRadiusMax, minEdge * CV3Style.adaptiveCornerRadiusRatio));
                [self visualShadowLayer].shadowPath = [UIBezierPath bezierPathWithRoundedRect:[self currentVisualShadowFrame] cornerRadius:finalRadius].CGPath;
                [UIView animateWithDuration:0.4 delay:0 options:UIViewAnimationOptionCurveEaseInOut animations:^{
                    self.glassBackdrop.effect = nil;
                    self.glassBackdrop.backgroundColor = [UIColor clearColor];
                } completion:nil];
                [self syncWindowBoundsToClientAndNotify:YES];
                [self syncWindowShadowForCurrentState];
                CV3SaveWindowLayout(self);
            }];

            [self animateFocusShadow:self.isFocused];
        }
    }
}

- (void)activateHostedAppFullscreenAndClose {
    if (self.isClosing || self.bundleID.length == 0) return;

    CV3ExitExposeModeIfNeeded(nil, NO);
    CV3StashPeerWindowsForFullscreen(self);

    NSString *bundleID = [self.bundleID copy];
    [self closeWindow];

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
        @try {
            [[CV3ClassNamed(@"LSApplicationWorkspace") defaultWorkspace] openApplicationWithBundleID:bundleID];
        } @catch (NSException *e) {
            CV3LogToFile(@"[HomeBar] 打开全屏应用失败 %@: %@", bundleID, e);
        }
    });
}

- (UIButton *)multitaskingMenuButtonWithTitle:(NSString *)title symbol:(NSString *)symbol action:(SEL)action {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    button.tintColor = [UIColor labelColor];
    button.titleLabel.font = [UIFont systemFontOfSize:CV3Style.multitaskingMenuFontSize weight:UIFontWeightSemibold];
    button.titleLabel.numberOfLines = 1;
    button.backgroundColor = [UIColor clearColor];
    button.layer.cornerRadius = 10.0;
    
    // 增加精致的半透明圆角选项背景层（Hover/Touch 高亮跟随）
    UIView *hoverBg = [[UIView alloc] initWithFrame:CGRectZero];
    hoverBg.tag = 990;
    hoverBg.backgroundColor = [[UIColor labelColor] colorWithAlphaComponent:0.07];
    hoverBg.layer.cornerRadius = 8.0;
    if (@available(iOS 13.0, *)) {
        hoverBg.layer.cornerCurve = kCACornerCurveContinuous;
    }
    hoverBg.userInteractionEnabled = NO;
    hoverBg.alpha = 0.0;
    [button addSubview:hoverBg];
    
    // 增加金属反射流光层 (Metallic Specular Flow)
    CAGradientLayer *specular = [CAGradientLayer layer];
    [specular setValue:@"specular" forKey:@"name"];
    specular.colors = @[(id)[UIColor clearColor].CGColor,
                        (id)[[UIColor whiteColor] colorWithAlphaComponent:CV3Style.menuSpecularAlpha].CGColor,
                        (id)[UIColor clearColor].CGColor];
    specular.startPoint = CGPointMake(-0.5, -0.5);
    specular.endPoint = CGPointMake(0.0, 0.0);
    specular.locations = @[@0.0, @0.5, @1.0];
    [hoverBg.layer addSublayer:specular];
    
    if (@available(iOS 13.0, *)) {
        // 使用配置好的 icon 尺寸，防止大尺寸 SF Symbol 挤占或遮挡文字
        UIImageSymbolConfiguration *config = [UIImageSymbolConfiguration configurationWithPointSize:CV3Style.multitaskingMenuIconSize weight:UIImageSymbolWeightMedium scale:UIImageSymbolScaleSmall];
        UIImage *image = [UIImage systemImageNamed:symbol withConfiguration:config];
        [button setImage:image forState:UIControlStateNormal];
    }
    [button setTitle:[NSString stringWithFormat:@" %@", title] forState:UIControlStateNormal];
    [button setTitleColor:[UIColor labelColor] forState:UIControlStateNormal];
    [button addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    
    // 连接触控物理收缩反馈
    [button addTarget:self action:@selector(menuBtnTouchDown:) forControlEvents:UIControlEventTouchDown | UIControlEventTouchDragEnter];
    [button addTarget:self action:@selector(menuBtnTouchUp:) forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside | UIControlEventTouchCancel | UIControlEventTouchDragExit];
    
    return button;
}

- (void)toggleMultitaskingMenu {
    CV3LogToFile(@"[MultitaskingMenu] toggleMultitaskingMenu entered. menuView = %@, hidden = %d", self.multitaskingMenuView, self.multitaskingMenuView ? self.multitaskingMenuView.hidden : -1);
    if (self.multitaskingMenuView && !self.multitaskingMenuView.hidden) {
        CV3LogToFile(@"[MultitaskingMenu] menuView already visible, dismissing");
        [self dismissMultitaskingMenu];
        return;
    }

    if (!self.multitaskingMenuView) {
        CV3LogToFile(@"[MultitaskingMenu] Creating multitaskingMenuView...");
        UIBlurEffect *effect = [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemMaterial];
        self.multitaskingMenuView = [[UIVisualEffectView alloc] initWithEffect:effect];
        self.multitaskingMenuView.clipsToBounds = YES;
        self.multitaskingMenuView.layer.cornerRadius = 16.0;
        if (@available(iOS 13.0, *)) {
            self.multitaskingMenuView.layer.cornerCurve = kCACornerCurveContinuous;
        }
        self.multitaskingMenuView.layer.shadowColor = [UIColor blackColor].CGColor;
        self.multitaskingMenuView.layer.shadowOffset = CGSizeMake(0, 8);
        self.multitaskingMenuView.layer.shadowOpacity = 0.18;
        self.multitaskingMenuView.layer.shadowRadius = 18.0;

        // 冰川蓝注入层 (Ice Tint) 增强毛玻璃通透感与极致美学
        UIView *tintView = [[UIView alloc] initWithFrame:self.multitaskingMenuView.bounds];
        tintView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        tintView.backgroundColor = [UIColor colorWithRed:CV3Style.menuTintR green:CV3Style.menuTintG blue:CV3Style.menuTintB alpha:CV3Style.menuTintA];
        tintView.userInteractionEnabled = NO;
        [self.multitaskingMenuView.contentView addSubview:tintView];

        // 多任务菜单三棱镜色散层 (Prism Dispersion for Menu)
        CALayer *menuCyan = [CALayer layer];
        [menuCyan setValue:@"menuCyan" forKey:@"name"];
        menuCyan.borderColor = [[UIColor cyanColor] colorWithAlphaComponent:0.12].CGColor;
        menuCyan.borderWidth = 0.3;
        menuCyan.cornerRadius = 16.0;
        if (@available(iOS 13.0, *)) {
            menuCyan.cornerCurve = kCACornerCurveContinuous;
        }
        [self.multitaskingMenuView.layer addSublayer:menuCyan];
        
        CALayer *menuMagenta = [CALayer layer];
        [menuMagenta setValue:@"menuMagenta" forKey:@"name"];
        menuMagenta.borderColor = [[UIColor magentaColor] colorWithAlphaComponent:0.12].CGColor;
        menuMagenta.borderWidth = 0.3;
        menuMagenta.cornerRadius = 16.0;
        if (@available(iOS 13.0, *)) {
            menuMagenta.cornerCurve = kCACornerCurveContinuous;
        }
        [self.multitaskingMenuView.layer addSublayer:menuMagenta];

        UIButton *fullscreen = [self multitaskingMenuButtonWithTitle:@"全屏" symbol:@"rectangle.fill" action:@selector(handleFullscreenMenuAction:)];
        UIButton *expose = [self multitaskingMenuButtonWithTitle:@"所有浮窗" symbol:@"square.grid.2x2" action:@selector(handleExposeMenuAction:)];
        UIButton *copy = [self multitaskingMenuButtonWithTitle:@"复制" symbol:@"doc.on.doc" action:@selector(handleCopyHostedContentAction:)];
        UIButton *close = [self multitaskingMenuButtonWithTitle:@"关闭" symbol:@"xmark" action:@selector(handleCloseMenuAction:)];
        fullscreen.tag = 101;
        expose.tag = 102;
        copy.tag = 103;
        close.tag = 104;
        [self.multitaskingMenuView.contentView addSubview:fullscreen];
        [self.multitaskingMenuView.contentView addSubview:expose];
        [self.multitaskingMenuView.contentView addSubview:copy];
        [self.multitaskingMenuView.contentView addSubview:close];
        [self.rootTransformContainer addSubview:self.multitaskingMenuView];
    }

    CGFloat logicalW = self.rootTransformContainer.bounds.size.width;
    CGFloat menuW = MIN(320.0, MAX(280.0, logicalW - 24.0));
    CGFloat menuH = 54.0;
    self.multitaskingMenuView.frame = CGRectMake((logicalW - menuW) / 2.0, 24.0, menuW, menuH);
    CV3LogToFile(@"[MultitaskingMenu] menuView frame = %@", NSStringFromCGRect(self.multitaskingMenuView.frame));
    
    // 动态调整多任务菜单的色散边缘图层
    CGRect menuBounds = self.multitaskingMenuView.bounds;
    if (self.multitaskingMenuView.layer.sublayers) {
        for (CALayer *sub in self.multitaskingMenuView.layer.sublayers) {
            if ([[sub valueForKey:@"name"] isEqualToString:@"menuCyan"]) {
                sub.frame = CGRectInset(menuBounds, -0.3, -0.3);
            } else if ([[sub valueForKey:@"name"] isEqualToString:@"menuMagenta"]) {
                sub.frame = CGRectInset(menuBounds, 0.3, 0.3);
            }
        }
    }
    
    CGFloat itemW = menuW / 4.0;
    for (UIButton *button in self.multitaskingMenuView.contentView.subviews) {
        if (![button isKindOfClass:[UIButton class]]) continue;
        NSInteger idx = button.tag - 101;
        button.frame = CGRectMake(itemW * idx, 0, itemW, menuH);
        
        UIView *hoverBg = [button viewWithTag:990];
        if (hoverBg) {
            hoverBg.frame = CGRectInset(button.bounds, 4, 4); // 四周内缩，呈现精致悬浮边框
            
            // 同步调整金属反射流光层的尺寸
            if (hoverBg.layer.sublayers) {
                for (CALayer *sub in hoverBg.layer.sublayers) {
                    if ([[sub valueForKey:@"name"] isEqualToString:@"specular"]) {
                        sub.frame = hoverBg.bounds;
                        break;
                    }
                }
            }
        }
    }

    // 级联水滴滑入动效 (Cascade Slide Animation) - 从绿色的多任务按钮正下方喷射展开
    CGPoint startCenter = [self.windowChromeView convertPoint:self.chromeModeButton.center toView:self.rootTransformContainer];
    CGPoint targetCenter = CGPointMake(logicalW / 2.0, 24.0 + menuH / 2.0);
    
    self.multitaskingMenuView.center = startCenter;
    self.multitaskingMenuView.transform = CGAffineTransformMakeScale(CV3Style.menuStartScale, CV3Style.menuStartScale);
    self.multitaskingMenuView.alpha = 0.0;
    self.multitaskingMenuView.hidden = NO;
    [self.rootTransformContainer bringSubviewToFront:self.multitaskingMenuView];
    
    // 水滴抛物线飞行动画 (Parabolic Flight trajectory)
    CGMutablePathRef curvedPath = CGPathCreateMutable();
    CGPathMoveToPoint(curvedPath, NULL, startCenter.x, startCenter.y);
    CGFloat cx = startCenter.x + (targetCenter.x - startCenter.x) * 0.4;
    CGFloat cy = startCenter.y + CV3Style.menuParabolicOffset;
    CGPathAddQuadCurveToPoint(curvedPath, NULL, cx, cy, targetCenter.x, targetCenter.y);
    
    CAKeyframeAnimation *pathAnimation = [CAKeyframeAnimation animationWithKeyPath:@"position"];
    pathAnimation.duration = CV3Style.menuAnimDuration;
    pathAnimation.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
    pathAnimation.path = curvedPath;
    CGPathRelease(curvedPath);
    
    [self.multitaskingMenuView.layer addAnimation:pathAnimation forKey:@"position"];
    
    CV3LogToFile(@"[MultitaskingMenu] Performing cascade spring animation...");
    [UIView animateWithDuration:CV3Style.menuAnimDuration
                          delay:0
         usingSpringWithDamping:CV3Style.menuAnimDamping
          initialSpringVelocity:0.2
                        options:UIViewAnimationOptionCurveEaseInOut | UIViewAnimationOptionAllowUserInteraction
                     animations:^{
        self.multitaskingMenuView.center = targetCenter;
        self.multitaskingMenuView.transform = CGAffineTransformIdentity;
        self.multitaskingMenuView.alpha = 1.0;
    } completion:nil];
}

- (void)dismissMultitaskingMenu {
    CV3LogToFile(@"[MultitaskingMenu] dismissMultitaskingMenu called.");
    if (!self.multitaskingMenuView || self.multitaskingMenuView.hidden) return;
    
    CGPoint startCenter = [self.windowChromeView convertPoint:self.chromeModeButton.center toView:self.rootTransformContainer];
    CGPoint currentCenter = self.multitaskingMenuView.center;
    
    // 原路收缩，吸回绿色的多任务按钮中
    CGMutablePathRef curvedPath = CGPathCreateMutable();
    CGPathMoveToPoint(curvedPath, NULL, currentCenter.x, currentCenter.y);
    CGFloat cx = startCenter.x + (currentCenter.x - startCenter.x) * 0.4;
    CGFloat cy = currentCenter.y + CV3Style.menuParabolicOffset;
    CGPathAddQuadCurveToPoint(curvedPath, NULL, cx, cy, startCenter.x, startCenter.y);
    
    CAKeyframeAnimation *pathAnimation = [CAKeyframeAnimation animationWithKeyPath:@"position"];
    pathAnimation.duration = CV3Style.durationMedium;
    pathAnimation.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
    pathAnimation.path = curvedPath;
    CGPathRelease(curvedPath);
    
    [self.multitaskingMenuView.layer addAnimation:pathAnimation forKey:@"position"];
    
    [UIView animateWithDuration:CV3Style.durationMedium
                          delay:0
                        options:UIViewAnimationOptionCurveEaseIn | UIViewAnimationOptionAllowUserInteraction
                     animations:^{
        self.multitaskingMenuView.alpha = 0;
        self.multitaskingMenuView.center = startCenter;
        self.multitaskingMenuView.transform = CGAffineTransformMakeScale(CV3Style.menuStartScale, CV3Style.menuStartScale);
    } completion:^(BOOL finished) {
        self.multitaskingMenuView.hidden = YES;
        self.multitaskingMenuView.transform = CGAffineTransformIdentity;
        CV3LogToFile(@"[MultitaskingMenu] dismiss completed.");
    }];
}

- (void)handleFullscreenMenuAction:(id)sender {
    [self dismissMultitaskingMenu];
    CV3ExitExposeModeIfNeeded(self, YES);

    if (self.isFullscreenMode && !CGRectIsEmpty(self.preFullscreenFrame)) {
        CGRect restoreFrame = self.preFullscreenFrame;
        self.isFullscreenMode = NO;
        self.isCompactMode = NO;
        
        // 视窗变小，初态注入扩张视差 1.05x
        self.appContentWrapper.transform = CGAffineTransformMakeScale(CV3Style.transitionParallaxShrink, CV3Style.transitionParallaxShrink);
        
        [UIView animateWithDuration:0.35 delay:0 usingSpringWithDamping:0.86 initialSpringVelocity:0.0 options:UIViewAnimationOptionCurveEaseInOut animations:^{
            self.frame = restoreFrame;
            [self setNeedsLayout];
            [self layoutIfNeeded];
            
            // 视差过渡至标准物理尺寸
            self.appContentWrapper.transform = CGAffineTransformIdentity;
        } completion:^(BOOL finished) {
            [self syncHostedSceneLayoutForce:YES];
            [self syncWindowBoundsToClient];
        }];
        return;
    }

    if (!self.isFullscreenMode) {
        CV3StashPeerWindowsForFullscreen(self);
        self.preFullscreenFrame = self.frame;
        self.isFullscreenMode = YES;
        self.isCompactMode = NO;
    }

    CGRect targetFrame = self.windowScene ? self.windowScene.coordinateSpace.bounds : [UIScreen mainScreen].bounds;
    
    // 视窗变大，初态注入收缩视差 0.93x
    self.appContentWrapper.transform = CGAffineTransformMakeScale(CV3Style.transitionParallaxExpand, CV3Style.transitionParallaxExpand);
    
    [UIView animateWithDuration:0.35 delay:0 usingSpringWithDamping:0.86 initialSpringVelocity:0.0 options:UIViewAnimationOptionCurveEaseInOut animations:^{
        self.transform = CGAffineTransformIdentity;
        self.frame = targetFrame;
        [self setNeedsLayout];
        [self layoutIfNeeded];
        
        // 视差过渡至标准物理尺寸
        self.appContentWrapper.transform = CGAffineTransformIdentity;
    } completion:^(BOOL finished) {
        [self syncHostedSceneLayoutForce:YES];
        [self syncWindowBoundsToClient];
    }];
}

- (void)handleCloseMenuAction:(id)sender {
    [self dismissMultitaskingMenu];
    CV3ExitExposeModeIfNeeded(self, NO);
    [self closeWindow];
}

- (void)handleCopyHostedContentAction:(id)sender {
    [self dismissMultitaskingMenu];
    if (self.isClosing || !self.hostView) return;

    UIImage *image = nil;
    @autoreleasepool {
        CGSize size = self.hostView.bounds.size;
        if (size.width > 1.0 && size.height > 1.0) {
            UIGraphicsImageRendererFormat *format = [UIGraphicsImageRendererFormat preferredFormat];
            format.scale = [UIScreen mainScreen].scale;
            UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:size format:format];
            image = [renderer imageWithActions:^(UIGraphicsImageRendererContext *context) {
                if (![self.hostView drawViewHierarchyInRect:self.hostView.bounds afterScreenUpdates:NO]) {
                    [self.hostView.layer renderInContext:context.CGContext];
                }
            }];
        }
    }

    if (!image) {
        CV3LogToFile(@"[Clipboard] 无法生成托管内容快照: %@", self.bundleID);
        return;
    }

    UIPasteboard *pasteboard = [UIPasteboard generalPasteboard];
    pasteboard.items = @[@{
        @"public.png": UIImagePNGRepresentation(image)
    }];
    CV3LogToFile(@"[Clipboard] 已复制分屏画面 %@ size=%@", self.bundleID, NSStringFromCGSize(image.size));
    [self triggerCollisionImpulse];
}

- (void)handleExposeMenuAction:(id)sender {
    [self dismissMultitaskingMenu];
    CV3ToggleExposeMode();
}

static NSString *CV3DirectionTraceTransform3D(CATransform3D t) {
    return [NSString stringWithFormat:
        @"[%.4f %.4f %.4f %.4f; %.4f %.4f %.4f %.4f; %.4f %.4f %.4f %.4f; %.4f %.4f %.4f %.4f]",
        t.m11, t.m12, t.m13, t.m14,
        t.m21, t.m22, t.m23, t.m24,
        t.m31, t.m32, t.m33, t.m34,
        t.m41, t.m42, t.m43, t.m44];
}

static NSString *CV3DirectionTraceView(UIView *view) {
    if (!view) return @"nil";
    CALayer *layer = view.layer;
    CALayer *presentation = layer.presentationLayer;
    return [NSString stringWithFormat:
        @"%@ frame=%@ bounds=%@ center=%@ viewT=%@ hidden=%d alpha=%.3f "
         "layerFrame=%@ layerBounds=%@ layerT=%@ presentationFrame=%@ presentationBounds=%@ presentationT=%@",
        NSStringFromClass(view.class), NSStringFromCGRect(view.frame), NSStringFromCGRect(view.bounds),
        NSStringFromCGPoint(view.center), NSStringFromCGAffineTransform(view.transform), view.hidden, view.alpha,
        NSStringFromCGRect(layer.frame), NSStringFromCGRect(layer.bounds), CV3DirectionTraceTransform3D(layer.transform),
        presentation ? NSStringFromCGRect(presentation.frame) : @"nil",
        presentation ? NSStringFromCGRect(presentation.bounds) : @"nil",
        presentation ? CV3DirectionTraceTransform3D(presentation.transform) : @"nil"];
}

static NSString *CV3ReceptionKVCValue(id object, NSString *key) {
    if (!object || key.length == 0) return @"nil";
    @try {
        id value = [object valueForKey:key];
        return value ? [value description] : @"nil";
    } @catch (__unused NSException *exception) {
        return @"n/a";
    }
}

static void CV3CollectReceptionLayers(CALayer *layer,
                                      NSString *path,
                                      NSUInteger depth,
                                      NSMutableArray<NSString *> *entries) {
    if (!layer || depth > 10 || entries.count >= 48) return;
    CALayer *presentation = layer.presentationLayer;
    id contents = nil;
    @try { contents = layer.contents; } @catch (__unused NSException *exception) {}
    NSString *contextID = CV3ReceptionKVCValue(layer, @"contextId");
    BOOL interesting = depth == 0 || contents != nil ||
        (![contextID isEqualToString:@"nil"] && ![contextID isEqualToString:@"n/a"] && ![contextID isEqualToString:@"0"]);
    if (interesting) {
        [entries addObject:[NSString stringWithFormat:
            @"%@:%@ frame=%@ hidden=%d opacity=%.2f context=%@ contents=%@:%p pres=%@",
            path, NSStringFromClass(layer.class), NSStringFromCGRect(layer.frame), layer.hidden,
            layer.opacity, contextID, contents ? NSStringFromClass([contents class]) : @"nil", contents,
            presentation ? NSStringFromCGRect(presentation.frame) : @"nil"]];
    }
    NSUInteger index = 0;
    for (CALayer *child in layer.sublayers ?: @[]) {
        CV3CollectReceptionLayers(child, [path stringByAppendingFormat:@".%lu", (unsigned long)index++],
                                  depth + 1, entries);
    }
}

- (void)recordReceptionTrace:(NSString *)phase force:(BOOL)force {
    if (self.isClosing) return;
    NSMutableArray<NSString *> *layers = [NSMutableArray array];
    CV3CollectReceptionLayers(self.hostView.layer, @"host", 0, layers);
    id settings = CV3InvokeObject(self.targetScene, @selector(settings));
    NSInteger contentState = CV3InvokeInteger(self.targetScene, NSSelectorFromString(@"contentState"), NSIntegerMin);
    if (contentState == NSIntegerMin) {
        contentState = CV3InvokeInteger(self.targetScene, NSSelectorFromString(@"_contentState"), NSIntegerMin);
    }
    BOOL sceneValid = self.targetScene ? CV3InvokeBool(self.targetScene, @selector(isValid), YES) : NO;
    BOOL hostAttached = self.hostView && self.hostView.superview == self.hostContainerProxy;
    BOOL hostHasTree = self.hostView && (self.hostView.subviews.count > 0 || self.hostView.layer.sublayers.count > 0);
    NSString *signature = [NSString stringWithFormat:
        @"bundle=%@ appState=%ld workspace=%d switcher=%d/%d lifecycle=%@ generation=%lu "
         "stashed=%d focused=%d windowHidden=%d windowAlpha=%.2f sceneValid=%d contentState=%ld "
         "foreground=%@ backgrounded=%@ deactivation=%@ hostAttached=%d hostWindow=%d hostHidden=%d "
         "hostAlpha=%.2f hostTree=%d hostFrame=%@ proxyBounds=%@ presentationContext=%d rbs=%d layers=%@",
        self.bundleID ?: @"nil", (long)UIApplication.sharedApplication.applicationState,
        CV3WorkspaceTransitionActive, CV3SwitcherWindowVisible, CV3MainSwitcherVisible,
        CV3HostLifecycleStateName(self.hostLifecycleState), (unsigned long)self.sceneHostGeneration,
        self.isStashed, self.isFocused, self.hidden, self.alpha, sceneValid, (long)contentState,
        CV3ReceptionKVCValue(settings, @"foreground"), CV3ReceptionKVCValue(settings, @"backgrounded"),
        CV3ReceptionKVCValue(settings, @"deactivationReasons"), hostAttached, self.hostView.window != nil,
        self.hostView.hidden, self.hostView.alpha, hostHasTree, NSStringFromCGRect(self.hostView.frame),
        NSStringFromCGRect(self.hostContainerProxy.bounds),
        CV3InvokeObject(self.hostView, @selector(presentationContext)) != nil, self.rbsAssertion != nil,
        [layers componentsJoinedByString:@" | "]];
    NSTimeInterval now = CACurrentMediaTime();
    BOOL changed = ![signature isEqualToString:self.lastReceptionTraceSignature];
    BOOL heartbeatDue = now - self.lastReceptionTraceHeartbeatTime >= 2.0;
    if (!force && !changed && !heartbeatDue) return;
    self.lastReceptionTraceSignature = signature;
    self.lastReceptionTraceHeartbeatTime = now;
    CV3LogToFile(@"[ReceptionTrace][Host] event=%@ phase=%@ %@",
                 changed ? @"change" : @"heartbeat", phase ?: @"unknown", signature);
}

- (void)schedulePendingPortraitConfirmation {
    if (!CV3IsValidInterfaceOrientation(self.pendingPortraitOrientation) ||
        self.pendingPortraitStableSince <= 0) return;
    CFTimeInterval stableSince = self.pendingPortraitStableSince;
    CFTimeInterval deadline = self.pendingPortraitDeadline;
    UIInterfaceOrientation orientation = self.pendingPortraitOrientation;
    // Check just after the threshold instead of waiting for a 250 ms timer tick.
    NSTimeInterval delay = MAX(0.001, stableSince + 0.501 - CACurrentMediaTime());
    __weak CV3FloatingAppWindow *weakWindow = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        CV3FloatingAppWindow *window = weakWindow;
        if (!window || window.isClosing || window.isStashed ||
            window.pendingPortraitOrientation != orientation ||
            window.pendingPortraitDeadline != deadline ||
            window.pendingPortraitStableSince != stableSince) return;
        CV3LogToFile(@"[PortraitRestore] phase=deadlineCheck bundle=%@ stableMs=%.3f",
                     window.bundleID, (CACurrentMediaTime() - stableSince) * 1000.0);
        [window receptionTraceTimerFired:nil];
    });
}

- (void)receptionTraceTimerFired:(NSTimer *)timer {
    (void)timer;
    [self recordReceptionTrace:@"timer" force:NO];
    [self recordSurfaceOrientationAudit:@"timer" force:NO];

    // Scene updates may replace the orientation resolver after the hosted
    // Surface has already settled. Layer bounds still look full-size in that
    // failure mode, while the producer renders into only the portrait-width
    // portion of the landscape Surface. Audit the resolver's semantic pair and
    // repair the Scene transaction with a bounded cadence.
    if (!self.isClosing && !self.isStashed && self.targetScene) {
        UIInterfaceOrientation presentationOrientation =
            CV3HostedPresentationOrientation(self);
        UIInterfaceOrientation requestedOrientation = self.hostedContentOrientation;
        id liveSettings = CV3InvokeObject(self.targetScene, @selector(settings));
        BOOL sceneBoundsMatchRequest =
            CV3SceneSettingsBoundsMatchOrientation(liveSettings, requestedOrientation);
        BOOL needsCrossOrientationMap =
            CV3IsValidInterfaceOrientation(presentationOrientation) &&
            CV3IsValidInterfaceOrientation(requestedOrientation) &&
            UIInterfaceOrientationIsLandscape(presentationOrientation) !=
                UIInterfaceOrientationIsLandscape(requestedOrientation) &&
            !sceneBoundsMatchRequest;
        id liveResolver = CV3OrientationMapResolverFromSettings(liveSettings);
        BOOL resolverMatches = CV3OrientationMapResolverMatches(
            liveResolver, presentationOrientation, requestedOrientation);
        BOOL cachedPairMatches = self.crossOrientationMapApplied &&
            self.mappedPresentationOrientation == presentationOrientation &&
            self.mappedHostedOrientation == requestedOrientation;
        if (needsCrossOrientationMap && (!resolverMatches || !cachedPairMatches)) {
            CFTimeInterval mapNow = CACurrentMediaTime();
            if (mapNow - self.lastOrientationMapRepairAt >= 1.0) {
                self.lastOrientationMapRepairAt = mapNow;
                CV3LogToFile(@"[OrientationMapRepair] phase=detected bundle=%@ presentation=%ld hosted=%ld cachedApplied=%d cachedPair=%ld->%ld resolverMatches=%d resolver={%@}",
                             self.bundleID ?: @"nil", (long)presentationOrientation,
                             (long)requestedOrientation, self.crossOrientationMapApplied,
                             (long)self.mappedPresentationOrientation,
                             (long)self.mappedHostedOrientation, resolverMatches,
                             CV3OrientationResolverTrace(liveSettings));
                BOOL repaired = [self syncHostedSceneLayoutForce:YES];
                CV3LogToFile(@"[OrientationMapRepair] phase=committed bundle=%@ repaired=%d resolver={%@}",
                             self.bundleID ?: @"nil", repaired,
                             CV3OrientationResolverTrace(CV3InvokeObject(self.targetScene,
                                                                         @selector(settings))));
                [self setNeedsLayout];
                [self layoutIfNeeded];
            }
        }
    }

    UIInterfaceOrientation hostedOrientation = self.hostedContentOrientation;
    UIInterfaceOrientation liveClientOrientation = CV3HostedClientOrientation(self);
    if (CV3IsValidInterfaceOrientation(self.pendingPortraitOrientation)) {
        CFTimeInterval sampleTime = CACurrentMediaTime();
        CV3LogToFile(@"[PortraitRestore] phase=sample bundle=%@ requested=%ld client=%ld elapsedMs=%.3f stableMs=%.3f remainingMs=%.3f",
                     self.bundleID, (long)self.pendingPortraitOrientation, (long)liveClientOrientation,
                     (sampleTime - (self.pendingPortraitDeadline - 1.5)) * 1000.0,
                     self.pendingPortraitStableSince > 0 ? (sampleTime - self.pendingPortraitStableSince) * 1000.0 : 0.0,
                     (self.pendingPortraitDeadline - sampleTime) * 1000.0);
        if (self.isClosing || self.isStashed || self.requiresLandscapeContent ||
            sampleTime >= self.pendingPortraitDeadline) {
            CV3LogToFile(@"[PortraitRestore] phase=cancelled bundle=%@ client=%ld closing=%d stashed=%d",
                         self.bundleID, (long)liveClientOrientation, self.isClosing, self.isStashed);
            self.pendingPortraitOrientation = UIInterfaceOrientationUnknown;
            self.pendingPortraitStableSince = 0;
        } else {
            if (liveClientOrientation != self.pendingPortraitOrientation) {
                self.pendingPortraitStableSince = 0;
            } else if (self.pendingPortraitStableSince == 0) {
                self.pendingPortraitStableSince = sampleTime;
                [self schedulePendingPortraitConfirmation];
            } else if (sampleTime - self.pendingPortraitStableSince >= 0.5) {
                UIInterfaceOrientation confirmed = self.pendingPortraitOrientation;
                self.pendingPortraitOrientation = UIInterfaceOrientationUnknown;
                self.pendingPortraitStableSince = 0;
                self.hostedOrientationDriftFirstSeenAt = 0;
                self.hostedOrientationDriftRepairApplied = NO;
                CV3LogToFile(@"[PortraitRestore] phase=confirmed bundle=%@ requested=%ld client=%ld",
                             self.bundleID, (long)confirmed, (long)liveClientOrientation);
                CFTimeInterval applyStart = CACurrentMediaTime();
                [self applyHostedContentOrientation:confirmed];
                CV3LogToFile(@"[PortraitRestore] phase=applyReturned bundle=%@ elapsedMs=%.3f",
                             self.bundleID, (CACurrentMediaTime() - applyStart) * 1000.0);
            }
            // Do not reassert the old landscape request while checking an exit.
            return;
        }
    }
    BOOL hasClientDrift = !self.isClosing && !self.isStashed &&
        CV3IsValidInterfaceOrientation(hostedOrientation) &&
        CV3IsValidInterfaceOrientation(liveClientOrientation) &&
        hostedOrientation != liveClientOrientation;
    if (!hasClientDrift) {
        BOOL driftWasActive = self.hostedOrientationDriftFirstSeenAt > 0.0;
        if (driftWasActive) {
            CV3LogToFile(@"[OrientationRepair] phase=driftCleared bundle=%@ hosted=%ld liveClient=%ld repairApplied=%d",
                         self.bundleID ?: @"nil", (long)hostedOrientation,
                         (long)liveClientOrientation, self.hostedOrientationDriftRepairApplied);
        }
        self.hostedOrientationDriftFirstSeenAt = 0.0;
        self.hostedOrientationDriftClientOrientation = UIInterfaceOrientationUnknown;
        self.hostedOrientationDriftRepairApplied = NO;

        // The producer can recover from portrait back to the requested
        // landscape orientation without changing hostedContentOrientation.
        // In that transition the expected local transform becomes identity,
        // but an ordinary same-orientation request is intentionally
        // short-circuited. Re-layout exactly once when the observed drift
        // clears so the stale 90-degree compensation is removed.
        if (driftWasActive && !self.isClosing && !self.isStashed &&
            CV3IsValidInterfaceOrientation(liveClientOrientation) &&
            liveClientOrientation == hostedOrientation) {
            CGAffineTransform expectedRotation = CV3HostedContentRotationInScene(self);
            if (!CGAffineTransformEqualToTransform(self.rootTransformContainer.transform,
                                                    expectedRotation)) {
                CV3LogToFile(@"[OrientationRepair] phase=recoveryTransformSync bundle=%@ hosted=%ld liveClient=%ld rootBefore=%@ expected=%@",
                             self.bundleID ?: @"nil", (long)hostedOrientation,
                             (long)liveClientOrientation,
                             NSStringFromCGAffineTransform(self.rootTransformContainer.transform),
                             NSStringFromCGAffineTransform(expectedRotation));
                [self setNeedsLayout];
                [self layoutIfNeeded];
                CV3LogToFile(@"[OrientationRepair] phase=recoveryTransformSynced bundle=%@ rootAfter=%@",
                             self.bundleID ?: @"nil",
                             NSStringFromCGAffineTransform(self.rootTransformContainer.transform));
            }
        }
        return;
    }

    CFTimeInterval now = CACurrentMediaTime();
    if (self.hostedOrientationDriftFirstSeenAt <= 0.0 ||
        self.hostedOrientationDriftClientOrientation != liveClientOrientation) {
        self.hostedOrientationDriftFirstSeenAt = now;
        self.hostedOrientationDriftClientOrientation = liveClientOrientation;
        self.hostedOrientationDriftRepairApplied = NO;
        CV3LogToFile(@"[OrientationRepair] phase=driftObserved bundle=%@ hosted=%ld liveClient=%ld cachedAck=%ld",
                     self.bundleID ?: @"nil", (long)hostedOrientation,
                     (long)liveClientOrientation, (long)self.clientAcknowledgedOrientation);
        return;
    }

    if (!self.hostedOrientationDriftRepairApplied &&
        now - self.hostedOrientationDriftFirstSeenAt >= 0.5) {
        self.hostedOrientationDriftRepairApplied = YES;
        self.clientAcknowledgedOrientation = UIInterfaceOrientationUnknown;
        CV3LogToFile(@"[OrientationRepair] phase=driftRepairTriggered bundle=%@ duration=%.3f hosted=%ld liveClient=%ld",
                     self.bundleID ?: @"nil", now - self.hostedOrientationDriftFirstSeenAt,
                     (long)hostedOrientation, (long)liveClientOrientation);
        [self applyHostedContentOrientation:hostedOrientation];
    }
}

+ (CGRect)initialFrameForBundleID:(NSString *)bundleID
                           center:(CGPoint)center
                      windowScene:(UIWindowScene *)windowScene {
    CGRect sceneBounds = windowScene.coordinateSpace.bounds;
    if (CGRectIsEmpty(sceneBounds)) sceneBounds = windowScene.screen.bounds;
    if (CGRectIsEmpty(sceneBounds)) sceneBounds = UIScreen.mainScreen.bounds;

    UIInterfaceOrientation displayOrientation = CV3TrustedInterfaceOrientation(windowScene);
    UIInterfaceOrientation hostedOrientation =
        CV3InitialHostedOrientationForBundleID(bundleID, displayOrientation);
    CGFloat shortSide = MIN(sceneBounds.size.width, sceneBounds.size.height);
    CGFloat longSide = MAX(sceneBounds.size.width, sceneBounds.size.height);
    CGFloat logicalWidth = shortSide * kCV3FloatingDefaultWidthRatio;
    CGSize size = CGSizeMake(logicalWidth, logicalWidth * (longSide / MAX(shortSide, 1.0)));
    if (UIInterfaceOrientationIsLandscape(hostedOrientation)) {
        size = CGSizeMake(size.height, size.width);
    }

    UIEdgeInsets safeArea = CV3InitialFloatingSafeAreaInsets(windowScene);
    CGFloat breath = CV3Style.safeAreaBreath;
    CGFloat visibleWidth = MAX(1.0, sceneBounds.size.width - safeArea.left - safeArea.right - breath * 2.0);
    CGFloat visibleHeight = MAX(1.0, sceneBounds.size.height - safeArea.top - safeArea.bottom - breath * 2.0);
    CGFloat fitScale = MIN(1.0, MIN(visibleWidth / MAX(size.width, 1.0),
                                   visibleHeight / MAX(size.height, 1.0)));
    if (fitScale < 1.0) {
        size.width *= fitScale;
        size.height *= fitScale;
    }

    BOOL shellLandscape = UIInterfaceOrientationIsLandscape(hostedOrientation);
    BOOL requiresLandscapeContent = CV3BundleDeclaresLandscapeOnly(bundleID);
    if (requiresLandscapeContent && CV3SceneAndDisplayAxesDifferForScene(windowScene)) {
        shellLandscape = !shellLandscape;
    }
    if ((size.width > size.height) != shellLandscape) {
        size = CGSizeMake(size.height, size.width);
    }

    CGPoint targetCenter = center;
    NSDictionary *savedLayout = CV3SavedWindowLayout(bundleID);
    NSNumber *savedOrientationNumber = savedLayout[@"orientation"];
    NSString *savedFrameString = savedLayout[@"frame"];
    if ([savedOrientationNumber isKindOfClass:NSNumber.class] &&
        [savedFrameString isKindOfClass:NSString.class]) {
        UIInterfaceOrientation savedOrientation =
            (UIInterfaceOrientation)savedOrientationNumber.integerValue;
        CGRect savedFrame = CGRectFromString(savedFrameString);
        if (CV3IsValidInterfaceOrientation(savedOrientation) &&
            UIInterfaceOrientationIsLandscape(savedOrientation) == UIInterfaceOrientationIsLandscape(hostedOrientation) &&
            !CGRectIsNull(savedFrame) && !CGRectIsEmpty(savedFrame) &&
            savedFrame.size.width >= 1.0 && savedFrame.size.height >= 1.0) {
            size = savedFrame.size;
            if ((size.width > size.height) != shellLandscape) {
                size = CGSizeMake(size.height, size.width);
            }
            targetCenter = CGPointMake(CGRectGetMidX(savedFrame), CGRectGetMidY(savedFrame));
        }
    }

    CGRect frame = CGRectMake(targetCenter.x - size.width * 0.5,
                              targetCenter.y - size.height * 0.5,
                              size.width, size.height);
    return CV3ClampInitialFloatingFrame(frame, sceneBounds, safeArea);
}

- (void)recordOrientationTrace:(NSString *)phase force:(BOOL)force {
    UIWindowScene *scene = self.windowScene;
    CGRect sceneBounds = scene ? scene.coordinateSpace.bounds : CGRectZero;
    UIInterfaceOrientation sceneOrientation = scene ? scene.interfaceOrientation : UIInterfaceOrientationUnknown;
    CGRect screenBounds = scene.screen ? scene.screen.bounds : UIScreen.mainScreen.bounds;
    UIInterfaceOrientation presentationOrientation = CV3HostedPresentationOrientation(self);
    NSString *signature = [NSString stringWithFormat:
        @"scene=%ld/%@ screen=%@ target=%ld hosted=%ld presentation=%ld landscape=%d/%d "
         "window={%@} root={%@} wrapper={%@} clip={%@} proxy={%@} host={%@}",
        (long)sceneOrientation, NSStringFromCGRect(sceneBounds), NSStringFromCGRect(screenBounds),
        (long)self.targetOrientation, (long)self.hostedContentOrientation, (long)presentationOrientation,
        self.prefersLandscapePresentation, self.requiresLandscapeContent,
        CV3DirectionTraceView(self), CV3DirectionTraceView(self.rootTransformContainer),
        CV3DirectionTraceView(self.appContentWrapper), CV3DirectionTraceView(self.clippingContainer),
        CV3DirectionTraceView(self.hostContainerProxy), CV3DirectionTraceView(self.hostView)];
    if (!force && [signature isEqualToString:self.lastOrientationTraceSignature]) return;
    self.lastOrientationTraceSignature = signature;
    CV3LogToFile(@"[DirectionTrace][Host] phase=%@ bundle=%@ %@",
                 phase ?: @"unknown", self.bundleID ?: @"nil", signature);
}

- (instancetype)initWithBundleID:(NSString *)bundleID center:(CGPoint)center windowScene:(UIWindowScene *)windowScene {
    if (windowScene) {
        self = [super initWithWindowScene:windowScene];
    } else {
        self = [super initWithFrame:CGRectMake(0, 0, 300, 500)];
    }
    
    if (self) {
        self.bundleID = bundleID;
        self.coldLaunchStartTime = CACurrentMediaTime();
        self.coldLaunchTraceID = [NSString stringWithFormat:@"%@-%.0f",
                                  bundleID ?: @"unknown",
                                  [[NSDate date] timeIntervalSince1970] * 1000.0];
        [self recordColdLaunchMilestone:@"WINDOW_INIT_BEGIN" details:nil];

        UIInterfaceOrientation currentOrientation = CV3TrustedInterfaceOrientation(windowScene);
        UIInterfaceOrientation initialOrientation = CV3InitialHostedOrientationForBundleID(bundleID, currentOrientation);
        self.frame = [[self class] initialFrameForBundleID:bundleID center:center windowScene:windowScene];
        self.lastLayoutOrientation = initialOrientation;
        self.targetOrientation = initialOrientation;
        
        self.hostedSession = [[CV3HostedSceneSession alloc] initWithWindow:self];
        self.requiresLandscapeContent = CV3BundleDeclaresLandscapeOnly(bundleID);
        self.prefersLandscapePresentation = UIInterfaceOrientationIsLandscape(initialOrientation) &&
            self.requiresLandscapeContent;
        self.hostedContentOrientation = self.prefersLandscapePresentation
            ? initialOrientation
            : UIInterfaceOrientationPortrait;
        self.allowProcessTerminationOnClose = NO;
        [self enforcePortraitWindowGeometry];
        self.windowLevel = CV3Style.floatingApp; // 高于普通 App，但低于通知栏/控制中心
        self.backgroundColor = [UIColor clearColor];
        self.alpha = 1.0;
        
        [self visualShadowLayer].shadowColor = [UIColor blackColor].CGColor;
        [self visualShadowLayer].shadowOffset = CGSizeMake(0, 10);
        [self visualShadowLayer].shadowOpacity = 0.16;
        [self visualShadowLayer].shadowRadius = 24.0;
        self.layer.cornerRadius = CV3Style.floatingChromeCornerRadius;
        if (@available(iOS 13.0, *)) {
            self.layer.cornerCurve = kCACornerCurveContinuous;
        }
        
        // 核心修复：引入旋转根容器 (Root Transform Container)
        // 该容器用于隔离系统 UIWindow 的 Transform 问题，承载全方位的视觉旋转
        self.rootTransformContainer = [[UIView alloc] initWithFrame:self.bounds];
        self.rootTransformContainer.backgroundColor = [UIColor clearColor];
        // Do not expose an empty floating shell while FrontBoard is still
        // attaching the remote canvas. The container is revealed atomically
        // by finishHostingWhenRenderableWithRetries: once the real first frame
        // and its final geometry are both available.
        self.rootTransformContainer.hidden = YES;
        [self addSubview:self.rootTransformContainer];

        // 核心修复：引入内容包装层 (App Content Wrapper)
        // 该层用于统一缩放动画，确保主内容与把手 (Home Bar) 同步缩放至图标
        self.appContentWrapper = [[UIView alloc] initWithFrame:self.rootTransformContainer.bounds];
        self.appContentWrapper.backgroundColor = [UIColor clearColor];
        [self.rootTransformContainer addSubview:self.appContentWrapper];
        // Keep polling the client's first landscape canvas so layout is
        // refreshed as soon as its Scene transaction lands. The container must
        // remain visible because some clients publish no canvas notification.
        self.awaitingInitialRenderableContent = YES;
        [self clearOuterWindowShadow];
        [self syncWindowShadowForCurrentState];

        [self createFloatingHomeBarIfNeeded];

        // 核心修复：引入非缩放裁剪层 (Clipping Container)
        // 该层的大小始终等于窗口大小，负责强制执行圆角裁剪，不受内部缩放影响
        self.clippingContainer = [[UIView alloc] initWithFrame:self.bounds];
        self.clippingContainer.layer.cornerRadius = CV3Style.floatingChromeCornerRadius;
        if (@available(iOS 13.0, *)) {
            self.clippingContainer.layer.cornerCurve = kCACornerCurveContinuous;
        }
        self.clippingContainer.layer.masksToBounds = YES;
        self.clippingContainer.layer.borderWidth = 1.0 / [UIScreen mainScreen].scale;
        self.clippingContainer.backgroundColor = [UIColor clearColor];
        [self.appContentWrapper addSubview:self.clippingContainer];

        // The hosted scene must be the first visible content. A material effect
        // here becomes a bright veil while the remote canvas is still making
        // its first commit, so keep the fallback completely transparent.
        self.glassBackdrop = [[UIVisualEffectView alloc] initWithEffect:nil];
        self.glassBackdrop.backgroundColor = [UIColor clearColor];
        self.glassBackdrop.frame = self.clippingContainer.bounds;
        self.glassBackdrop.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        [self.clippingContainer insertSubview:self.glassBackdrop atIndex:0];

        CGFloat initialRadius = CV3Style.floatingChromeCornerRadius;
        
        self.cyanLayer = [CALayer layer];
        self.cyanLayer.frame = self.clippingContainer.bounds;
        self.cyanLayer.borderColor = [[UIColor cyanColor] colorWithAlphaComponent:0.12].CGColor;
        self.cyanLayer.borderWidth = 0.3;
        self.cyanLayer.cornerRadius = initialRadius;
        [self.clippingContainer.layer addSublayer:self.cyanLayer];

        self.magentaLayer = [CALayer layer];
        self.magentaLayer.frame = self.clippingContainer.bounds;
        self.magentaLayer.borderColor = [[UIColor magentaColor] colorWithAlphaComponent:0.12].CGColor;
        self.magentaLayer.borderWidth = 0.3;
        self.magentaLayer.cornerRadius = initialRadius;
        [self.clippingContainer.layer addSublayer:self.magentaLayer];

        self.innerGlowLayer = [CALayer layer];
        self.innerGlowLayer.frame = self.clippingContainer.bounds;
        self.innerGlowLayer.borderColor = [[UIColor labelColor] colorWithAlphaComponent:0.45].CGColor;
        self.innerGlowLayer.borderWidth = 0.3;
        self.innerGlowLayer.cornerRadius = initialRadius;
        [self.clippingContainer.layer addSublayer:self.innerGlowLayer];

        self.specularHighlight = [CAGradientLayer layer];
        self.specularHighlight.frame = self.clippingContainer.bounds;
        self.specularHighlight.colors = @[
            (id)[[UIColor whiteColor] colorWithAlphaComponent:0.0].CGColor,
            (id)[[UIColor whiteColor] colorWithAlphaComponent:0.15].CGColor,
            (id)[[UIColor whiteColor] colorWithAlphaComponent:0.0].CGColor
        ];
        self.specularHighlight.startPoint = CGPointMake(0.0, 0.0);
        self.specularHighlight.endPoint = CGPointMake(1.0, 1.0);
        self.specularHighlight.cornerRadius = initialRadius;
        [self.clippingContainer.layer addSublayer:self.specularHighlight];

        // 代理容器：用来隔离系统的布局覆盖，承载真实的缩放和裁剪
        self.hostContainerProxy = [[UIView alloc] initWithFrame:self.bounds];
        self.hostContainerProxy.backgroundColor = [UIColor clearColor];
        // 核心修复：应用三线性过滤 (Trilinear Filtering)
        // 在非整数缩放比下，三线性过滤能显著减少文本和细线的锯齿，提升渲染清晰度
        self.hostContainerProxy.layer.magnificationFilter = kCAFilterTrilinear;
        self.hostContainerProxy.layer.minificationFilter = kCAFilterTrilinear;
        
        [self.clippingContainer addSubview:self.hostContainerProxy];
        [self ensureLaunchSplashVisible];
        
        // 侧边隐藏拉手 (Grabber -> Prism Switcher)
        self.stashGrabber = [[CV3StashGrabberView alloc] initWithFrame:CGRectMake(0, 0, kCV3StashIconSize, kCV3StashIconSize)];
        self.stashGrabber.backgroundColor = [UIColor clearColor];
        self.stashGrabber.layer.cornerRadius = 0;
        self.stashGrabber.layer.borderWidth = 0;
        self.stashGrabber.layer.shadowColor = [UIColor blackColor].CGColor;
        self.stashGrabber.layer.shadowOffset = CGSizeMake(0, 10);
        self.stashGrabber.layer.shadowOpacity = 0.26;
        self.stashGrabber.layer.shadowRadius = 18.0;
        self.stashGrabber.alpha = 0; // 初始隐藏
        [self addSubview:self.stashGrabber];

        self.stashIconBackdropView = [[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemChromeMaterial]];
        self.stashIconBackdropView.userInteractionEnabled = NO;
        self.stashIconBackdropView.clipsToBounds = YES;
        [self.stashGrabber addSubview:self.stashIconBackdropView];

        self.stashIconHighlightLayer = [CAGradientLayer layer];
        self.stashIconHighlightLayer.startPoint = CGPointMake(0.0, 0.0);
        self.stashIconHighlightLayer.endPoint = CGPointMake(1.0, 1.0);
        [self.stashIconBackdropView.contentView.layer addSublayer:self.stashIconHighlightLayer];

        self.appIconMiniView = [[UIImageView alloc] initWithFrame:CGRectMake(kCV3StashIconInset, kCV3StashIconInset, kCV3StashIconSize - kCV3StashIconInset * 2.0, kCV3StashIconSize - kCV3StashIconInset * 2.0)];
        self.appIconMiniView.layer.cornerRadius = 10;
        self.appIconMiniView.clipsToBounds = YES;
        self.appIconMiniView.contentMode = UIViewContentModeScaleAspectFill;
        self.appIconMiniView.layer.borderColor = [[UIColor whiteColor] colorWithAlphaComponent:0.30].CGColor;
        self.appIconMiniView.layer.borderWidth = 1.0 / [UIScreen mainScreen].scale;
        [self.stashGrabber addSubview:self.appIconMiniView];
        [self updateStashIconAppearance];

        UITapGestureRecognizer *restoreTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleRestoreTap:)];
        [self.stashGrabber addGestureRecognizer:restoreTap];

        UIPanGestureRecognizer *restorePan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handleStashPan:)];
        [self.stashGrabber addGestureRecognizer:restorePan];

        // 核心功能：长按结束分屏
        UILongPressGestureRecognizer *stashClose = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(handleStashLongPress:)];
        stashClose.minimumPressDuration = 0.8; 
        [self.stashGrabber addGestureRecognizer:stashClose];

        self.stashGrabber.userInteractionEnabled = YES;

        [self clampToScreenBounds];
        [self layoutFloatingHomeBarForBounds:self.appContentWrapper.bounds];
        [self updateAdaptiveColor];

        [self loadAppScene];
        
        // Auto-focus on creation
        [self setWindowFocused:YES];

        // 核心修复：监听 Scene 变更与系统通知，确保窗口持久存在
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(attachToCurrentActiveScene) name:UISceneDidActivateNotification object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(enforceSceneForegroundState) name:UISceneDidEnterBackgroundNotification object:nil];
        [[UIDevice currentDevice] beginGeneratingDeviceOrientationNotifications];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(physicalDeviceOrientationDidChange:)
                                                     name:UIDeviceOrientationDidChangeNotification
                                                   object:[UIDevice currentDevice]];

        // Assertions are refreshed by state changes; this slower watchdog only retries failures.
        self.assertionWatchdogTimer = [NSTimer scheduledTimerWithTimeInterval:15.0 target:self selector:@selector(assertionWatchdogTick:) userInfo:nil repeats:YES];
        
        // [SHM Lazy Unmapping] 持有共享内存引用计数
        CV3RetainSharedGeometry(self.bundleID);
        [self.hostedSession setActive:YES];
        self.receptionTraceTimer = [NSTimer timerWithTimeInterval:0.25
                                                           target:self
                                                         selector:@selector(receptionTraceTimerFired:)
                                                         userInfo:nil
                                                          repeats:YES];
        [[NSRunLoop mainRunLoop] addTimer:self.receptionTraceTimer forMode:NSRunLoopCommonModes];
        [self recordReceptionTrace:@"window.init" force:YES];
        [self recordOrientationTrace:@"init.complete" force:YES];
    }
    return self;
}

- (void)setHidden:(BOOL)hidden {
    if (self.isSuppressedByLockScreen) {
        [super setHidden:YES];
        return;
    }

    // Keep a visible hosted window attached during ordinary workspace transitions.
    if (hidden && !self.isStashed && !self.isClosing) {
        CV3LogToFile(@"[Visibility] 拦截系统隐藏请求: %@", self.bundleID);
        [super setHidden:NO];
        [self attachToCurrentActiveScene];
        return;
    }
    CV3LogToFile(@"[Visibility] 窗口 Hidden 状态变更 -> %d: %@", hidden, self.bundleID);
    [super setHidden:hidden];
    [self recordReceptionTrace:hidden ? @"window.hidden" : @"window.visible" force:YES];
}

- (void)attachToCurrentActiveScene {
    CV3LogToFile(@"[Scene] 开始尝试同步挂载场景: %@", self.bundleID);
    @try {
        UIWindowScene *targetScene = nil;
        
        // 1. 终极优先：获取 SpringBoard 核心主场景 (SBWindowSceneSessionRoleMain)
        targetScene = CV3InvokeObject(CV3ClassNamed(@"SBWindowScene"), @selector(mainDisplayWindowScene));
        
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
            CV3SceneRotationContext context = CV3MakeSceneRotationContext(targetScene);
            [self applySceneRotationContext:context force:NO];
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
        // _setPresentationContext: is not an ordinary property setter. Each new
        // context asks FrontBoard to publish another set of CALayerHost surfaces.
        // Rebinding it during every portrait/landscape video transition leaves
        // the previous surface alive, so a stale portrait layer can cover the
        // correctly resized landscape host. Treat an existing context as the
        // live hosting session and only restore the view's visibility here.
        id existingContext = CV3TargetRespondsToSelector(self.hostView, @selector(presentationContext))
            ? CV3InvokeObject(self.hostView, @selector(presentationContext))
            : nil;
        if (existingContext) {
            self.hostView.alpha = 1.0;
            self.hostView.hidden = NO;
            return;
        }

        // [Safety Restore] 恢复至 7 (1|2|4)，确保键盘可弹出。
        // 由于已解决布局死锁，恢复 2(Keyboard) 和 4(KeyboardBg) 是安全的。
        UIScenePresentationContext *context = [[CV3ClassNamed(@"UIScenePresentationContext") alloc] _initWithDefaultValues];
        if ([context respondsToSelector:@selector(setPresentedLayerTypes:)]) {
            [context setPresentedLayerTypes:7];
        }
        if ([context respondsToSelector:@selector(setAppearanceStyle:)]) {
            BOOL previousSuppress = CV3SuppressPresentationContextFanout;
            CV3SuppressPresentationContextFanout = YES;
            @try {
                [context setAppearanceStyle:2];
            } @finally {
                CV3SuppressPresentationContextFanout = previousSuppress;
            }
        }
        if ([context respondsToSelector:@selector(setClipsToBounds:)]) {
            [context setClipsToBounds:YES];
        }
        
        CV3InvokeObject1(self.hostView, @selector(_setPresentationContext:), context);
        
        self.hostView.alpha = 1.0;
        self.hostView.hidden = NO;
        
    } @catch (NSException *e) {
        CV3LogToFile(@"[Error] 热刷新渲染失败: %@", e);
    }
}

- (void)beginHostPresentationRepublishIfNeeded:(NSString *)reason {
    if (!self.hostPresentationRepublishPending || self.pendingRepublishedHostView ||
        !self.targetScene || !self.hostView || self.isClosing || self.isStashed) return;

    self.hostPresentationRepublishPending = NO;
    UIView *oldHost = self.hostView;
    NSString *oldContextID = CV3HostedLayerContextID(oldHost.layer);
    NSUInteger generation = ++self.hostPresentationRepublishGeneration;

    @try {
        id hostManager = CV3InvokeObject(self.targetScene, @selector(hostManager));
        NSString *requester = [NSString stringWithFormat:@"com.xu.chevronv3.host.%@.orientation.%lu",
                               self.bundleID, (unsigned long)generation];
        SEL enableSelector = @selector(enableHostingForRequester:orderFront:);
        if (!hostManager || !CV3TargetRespondsToSelector(hostManager, enableSelector)) {
            CV3LogToFile(@"[HostRepublish] trace=%@ phase=manager.unavailable generation=%lu manager=%@ requester=%@",
                         self.coldLaunchTraceID, (unsigned long)generation, hostManager, requester);
            return;
        }
        ((void (*)(id, SEL, id, BOOL))objc_msgSend)(hostManager, enableSelector, requester, YES);
        self.pendingRepublishedRequester = requester;
        self.pendingRepublishedContextID = nil;
        self.pendingRepublishedStableCount = 0;
        CV3LogToFile(@"[HostRepublish] trace=%@ phase=manager.enabled generation=%lu reason=%@ requester=%@ oldHost=%p oldContextId=%@ resolver={%@}",
                     self.coldLaunchTraceID, (unsigned long)generation, reason ?: @"unknown",
                     requester, oldHost, oldContextID ?: @"nil",
                     CV3OrientationResolverTrace(CV3InvokeObject(self.targetScene, @selector(settings))));
        [self acquireRepublishedHostViewForGeneration:generation oldHost:oldHost
                                         oldContextID:oldContextID retries:40];
    } @catch (NSException *exception) {
        CV3LogToFile(@"[HostRepublish] trace=%@ phase=manager.exception generation=%lu exception=%@",
                     self.coldLaunchTraceID, (unsigned long)generation, exception);
    }
}

- (void)acquireRepublishedHostViewForGeneration:(NSUInteger)generation
                                        oldHost:(UIView *)oldHost
                                   oldContextID:(NSString *)oldContextID
                                        retries:(NSInteger)retries {
    if (generation != self.hostPresentationRepublishGeneration || self.isClosing ||
        self.pendingRepublishedRequester.length == 0) return;

    UIView *newHost = nil;
    id hostManager = CV3InvokeObject(self.targetScene, @selector(hostManager));
    SEL selector = @selector(hostViewForRequester:enableAndOrderFront:);
    @try {
        if (CV3TargetRespondsToSelector(hostManager, selector)) {
            newHost = ((id (*)(id, SEL, id, BOOL))objc_msgSend)(
                hostManager, selector, self.pendingRepublishedRequester, YES);
        }
    } @catch (NSException *exception) {
        CV3LogToFile(@"[HostRepublish] trace=%@ phase=manager.acquire.exception generation=%lu requester=%@ exception=%@",
                     self.coldLaunchTraceID, (unsigned long)generation,
                     self.pendingRepublishedRequester, exception);
    }

    if (newHost && newHost != oldHost) {
        newHost.backgroundColor = UIColor.clearColor;
        newHost.layer.cornerRadius = 0;
        newHost.layer.masksToBounds = YES;
        newHost.transform = CGAffineTransformIdentity;
        newHost.frame = [self currentHostedSceneBounds];
        newHost.accessibilityIdentifier = @"ChevronV3PendingHost";
        [self.hostContainerProxy insertSubview:newHost belowSubview:oldHost];
        [newHost setNeedsLayout];
        [newHost layoutIfNeeded];
        self.pendingRepublishedHostView = newHost;
        CV3LogToFile(@"[HostRepublish] trace=%@ phase=manager.acquired generation=%lu requester=%@ oldHost=%p newHost=%p oldContextId=%@ newContextId=%@ frame=%@",
                     self.coldLaunchTraceID, (unsigned long)generation,
                     self.pendingRepublishedRequester, oldHost, newHost,
                     oldContextID ?: @"nil", CV3HostedLayerContextID(newHost.layer) ?: @"nil",
                     NSStringFromCGRect(newHost.frame));
        [self pollRepublishedHostViewForGeneration:generation oldHost:oldHost
                                      oldContextID:oldContextID retries:80];
        return;
    }

    CV3LogToFile(@"[HostRepublish] trace=%@ phase=manager.acquire.wait generation=%lu requester=%@ retries=%ld result=%p sameAsOld=%d",
                 self.coldLaunchTraceID, (unsigned long)generation,
                 self.pendingRepublishedRequester, (long)retries, newHost, newHost == oldHost);
    if (retries <= 0) {
        SEL disableSelector = @selector(disableHostingForRequester:);
        if (CV3TargetRespondsToSelector(hostManager, disableSelector)) {
            ((void (*)(id, SEL, id))objc_msgSend)(hostManager, disableSelector,
                                                  self.pendingRepublishedRequester);
        }
        self.pendingRepublishedRequester = nil;
        CV3LogToFile(@"[HostRepublish] trace=%@ phase=manager.acquire.timeout generation=%lu keptOldHost=%p oldContextId=%@",
                     self.coldLaunchTraceID, (unsigned long)generation, oldHost,
                     oldContextID ?: @"nil");
        return;
    }
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.05 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        [self acquireRepublishedHostViewForGeneration:generation oldHost:oldHost
                                         oldContextID:oldContextID retries:retries - 1];
    });
}

- (void)pollRepublishedHostViewForGeneration:(NSUInteger)generation
                                     oldHost:(UIView *)oldHost
                                oldContextID:(NSString *)oldContextID
                                     retries:(NSInteger)retries {
    UIView *newHost = self.pendingRepublishedHostView;
    if (!newHost || generation != self.hostPresentationRepublishGeneration || self.isClosing) return;

    NSString *newContextID = CV3HostedLayerContextID(newHost.layer);
    BOOL hasRemoteContext = newContextID.length > 0;
    BOOL sameProducerContext = oldContextID.length > 0 &&
        [newContextID isEqualToString:oldContextID];
    BOOL hasTree = newHost.layer.sublayers.count > 0 || newHost.subviews.count > 0;
    BOOL mainLayer = CV3SceneHasRenderableMainLayer(self.targetScene);
    CGRect expectedBounds = [self currentHostedSceneBounds];
    CGRect presentedBounds = newHost.layer.presentationLayer
        ? newHost.layer.presentationLayer.bounds : CGRectZero;
    BOOL geometryReady = fabs(CGRectGetWidth(newHost.bounds) - CGRectGetWidth(expectedBounds)) <= 1.0 &&
        fabs(CGRectGetHeight(newHost.bounds) - CGRectGetHeight(expectedBounds)) <= 1.0 &&
        fabs(CGRectGetWidth(presentedBounds) - CGRectGetWidth(expectedBounds)) <= 1.0 &&
        fabs(CGRectGetHeight(presentedBounds) - CGRectGetHeight(expectedBounds)) <= 1.0;

    if (hasRemoteContext && hasTree && mainLayer && geometryReady) {
        if ([self.pendingRepublishedContextID isEqualToString:newContextID]) {
            self.pendingRepublishedStableCount += 1;
        } else {
            self.pendingRepublishedContextID = newContextID;
            self.pendingRepublishedStableCount = 1;
        }
    } else {
        self.pendingRepublishedStableCount = 0;
    }

    CV3LogToFile(@"[HostRepublish] trace=%@ phase=poll generation=%lu requester=%@ retries=%ld oldContextId=%@ newContextId=%@ sameProducerContext=%d tree=%d mainLayer=%d geometryReady=%d bounds=%@ presentedBounds=%@ expected=%@ stable=%lu",
                 self.coldLaunchTraceID, (unsigned long)generation,
                 self.pendingRepublishedRequester, (long)retries, oldContextID ?: @"nil",
                 newContextID ?: @"nil", sameProducerContext, hasTree, mainLayer,
                 geometryReady, NSStringFromCGRect(newHost.bounds),
                 NSStringFromCGRect(presentedBounds), NSStringFromCGRect(expectedBounds),
                 (unsigned long)self.pendingRepublishedStableCount);

    if (self.pendingRepublishedStableCount >= 2) {
        [UIView performWithoutAnimation:^{
            newHost.accessibilityIdentifier = @"ChevronV3Host";
            [self.hostContainerProxy bringSubviewToFront:newHost];
            self.hostView = newHost;
            self.pendingRepublishedHostView = nil;
            [self setNeedsLayout];
            [self layoutIfNeeded];
            [oldHost removeFromSuperview];
            if ([oldHost respondsToSelector:@selector(invalidate)]) {
                CV3InvokeObject(oldHost, @selector(invalidate));
            }
        }];
        NSString *oldRequester = self.sceneHostingRequester;
        self.sceneHostingRequester = self.pendingRepublishedRequester;
        self.pendingRepublishedRequester = nil;
        if (oldRequester.length > 0 && ![oldRequester isEqualToString:self.sceneHostingRequester]) {
            id hostManager = CV3InvokeObject(self.targetScene, @selector(hostManager));
            SEL disableSelector = @selector(disableHostingForRequester:);
            if (CV3TargetRespondsToSelector(hostManager, disableSelector)) {
                ((void (*)(id, SEL, id))objc_msgSend)(hostManager, disableSelector, oldRequester);
            }
        }
        CV3LogToFile(@"[HostRepublish] trace=%@ phase=swapped generation=%lu requester=%@ oldHost=%p newHost=%p oldContextId=%@ newContextId=%@ sameProducerContext=%d",
                     self.coldLaunchTraceID, (unsigned long)generation,
                     self.sceneHostingRequester, oldHost, newHost, oldContextID ?: @"nil",
                     newContextID ?: @"nil", sameProducerContext);
        [self recordStrictSplitTrace:@"hostRepublish.swapped"
                             details:[NSString stringWithFormat:@"generation=%lu old=%@ new=%@",
                                      (unsigned long)generation, oldContextID ?: @"nil",
                                      newContextID ?: @"nil"]];
        return;
    }

    if (retries <= 0) {
        [newHost removeFromSuperview];
        if ([newHost respondsToSelector:@selector(invalidate)]) CV3InvokeObject(newHost, @selector(invalidate));
        self.pendingRepublishedHostView = nil;
        self.pendingRepublishedContextID = nil;
        self.pendingRepublishedStableCount = 0;
        id hostManager = CV3InvokeObject(self.targetScene, @selector(hostManager));
        SEL disableSelector = @selector(disableHostingForRequester:);
        if (self.pendingRepublishedRequester.length > 0 &&
            CV3TargetRespondsToSelector(hostManager, disableSelector)) {
            ((void (*)(id, SEL, id))objc_msgSend)(hostManager, disableSelector,
                                                  self.pendingRepublishedRequester);
        }
        self.pendingRepublishedRequester = nil;
        CV3LogToFile(@"[HostRepublish] trace=%@ phase=timeout generation=%lu keptOldHost=%p oldContextId=%@",
                     self.coldLaunchTraceID, (unsigned long)generation,
                     oldHost, oldContextID ?: @"nil");
        return;
    }

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.05 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        [self pollRepublishedHostViewForGeneration:generation oldHost:oldHost
                                      oldContextID:oldContextID retries:retries - 1];
    });
}

- (UIView *)hostViewForScene:(FBScene *)scene {
    if (!scene) return nil;

    @try {
        id hostManager = CV3InvokeObject(scene, @selector(hostManager));
        if (!hostManager) return nil;

        NSString *requester = [NSString stringWithFormat:@"com.xu.chevronv3.host.%@", self.bundleID];
        SEL hostViewSelector = @selector(hostViewForRequester:enableAndOrderFront:);
        if (CV3TargetRespondsToSelector(hostManager, hostViewSelector)) {
            UIView *hostView = ((id (*)(id, SEL, id, BOOL))objc_msgSend)(hostManager,
                                                                        hostViewSelector,
                                                                        requester,
                                                                        YES);
            if (hostView) {
                self.sceneHostingRequester = requester;
                CV3LogToFile(@"[SceneHost] 已通过 FrontBoard 获取渲染视图: %@", self.bundleID);
                return hostView;
            }
        }

        SEL enableSelector = @selector(enableHostingForRequester:orderFront:);
        if (CV3TargetRespondsToSelector(hostManager, enableSelector)) {
            ((void (*)(id, SEL, id, BOOL))objc_msgSend)(hostManager, enableSelector, requester, YES);
            self.sceneHostingRequester = requester;
            CV3LogToFile(@"[SceneHost] 已启用 FrontBoard 托管，使用容器回退: %@", self.bundleID);
        }
    } @catch (NSException *exception) {
        CV3LogToFile(@"[Error] 启用 Scene 托管失败 %@: %@", self.bundleID, exception);
    }
    return nil;
}

- (void)disableHostingForCurrentScene {
    NSString *requester = self.sceneHostingRequester;
    if (!requester) return;

    FBScene *scene = self.targetScene;
    if (scene) {
        @try {
            id hostManager = CV3InvokeObject(scene, @selector(hostManager));
            SEL selector = @selector(disableHostingForRequester:);
            if (CV3TargetRespondsToSelector(hostManager, selector)) {
                ((void (*)(id, SEL, id))objc_msgSend)(hostManager, selector, requester);
            }
        } @catch (NSException *exception) {
            CV3LogToFile(@"[Error] 关闭 Scene 托管失败 %@: %@", self.bundleID, exception);
        }
    }
    self.sceneHostingRequester = nil;
}

- (void)setHostLifecycleState:(CV3HostLifecycleState)state reason:(NSString *)reason {
    if (self.hostLifecycleState == state) return;
    CV3HostLifecycleState previous = self.hostLifecycleState;
    self.hostLifecycleState = state;
    CV3LogToFile(@"[HostState] %@ %@ -> %@ generation=%lu reason=%@",
                 self.bundleID,
                 CV3HostLifecycleStateName(previous),
                 CV3HostLifecycleStateName(state),
                 (unsigned long)self.sceneHostGeneration,
                 reason ?: @"Unknown");
}

- (void)detachHostedSceneForReason:(NSString *)reason clearScene:(BOOL)clearScene {
    [self setHostLifecycleState:CV3HostLifecycleStateReleasing reason:reason];
    CV3ReleaseKeyboardHostingForWindow(self);
    [self disableHostingForCurrentScene];
    UIView *hostView = self.hostView;
    self.hostView = nil;
    if ([hostView respondsToSelector:@selector(invalidate)]) {
        @try {
            CV3InvokeObject(hostView, @selector(invalidate));
        } @catch (NSException *exception) {
            CV3LogToFile(@"[Error] HostView invalidate 失败 %@ reason=%@: %@", self.bundleID, reason, exception);
        }
    }
    [hostView removeFromSuperview];
    if (clearScene) self.targetScene = nil;
    [self setHostLifecycleState:clearScene ? CV3HostLifecycleStateIdle : CV3HostLifecycleStateWaitingForScene
                         reason:clearScene ? @"Detached" : @"DetachedForRetry"];
    CV3LogToFile(@"[SceneHost] 已同步解绑托管场景 %@ reason=%@ clearScene=%d",
                 self.bundleID, reason ?: @"Unknown", clearScene);
}

- (BOOL)hostViewHasRenderableContent {
    if (!self.hostView || !self.hostView.superview || self.hostView.hidden || self.hostView.alpha < 0.01) return NO;

    id presentationContext = CV3InvokeObject(self.hostView, @selector(presentationContext));
    if (CV3TargetRespondsToSelector(self.hostView, @selector(presentationContext)) && !presentationContext) return NO;
    if (!CV3SceneHasRenderableMainLayer(self.targetScene)) return NO;
    if (self.awaitingInitialRenderableContent && self.requiresLandscapeContent) {
        NSString *name = [NSString stringWithFormat:@"com.xu.chevronv3.canvas.%@", self.bundleID];
        int token = -1;
        uint64_t geometry = 0;
        if (notify_register_check(name.UTF8String, &token) == NOTIFY_STATUS_OK) {
            notify_get_state(token, &geometry);
            notify_cancel(token);
        }
        CGSize expected = [self currentHostedSceneBounds].size;
        CGFloat width = (geometry >> 16) & 0xFFFF;
        CGFloat height = geometry & 0xFFFF;
        BOOL canvasLandscape = fabs(width - expected.width) <= 1.0 &&
            fabs(height - expected.height) <= 1.0;
        BOOL canvasLayerCommitReady = (geometry & CV3CanvasReadyFlag) != 0;
        if (!canvasLandscape || !canvasLayerCommitReady) {
            NSTimeInterval now = CACurrentMediaTime();
            if (now - self.lastCanvasMismatchLoggedAt > 1.0) {
                self.lastCanvasMismatchLoggedAt = now;
                CV3LogToFile(@"[CanvasGate] %@ client=%.0fx%.0f expected=%.0fx%.0f layerCommitReady=%d proxy=%@ host=%@ children=%@ settings=%@ initial=1 waiting…",
                             self.bundleID, width, height, expected.width, expected.height,
                             canvasLayerCommitReady,
                             NSStringFromCGRect(self.hostContainerProxy.bounds),
                             NSStringFromCGRect(self.hostView.frame), self.hostView.subviews,
                             CV3InvokeObject(self.targetScene, @selector(settings)));
            }
            return NO;
        }
        if (!self.coldLaunchCanvasMatchedRecorded) {
            self.coldLaunchCanvasMatchedRecorded = YES;
            [self recordColdLaunchMilestone:@"CANVAS_GEOMETRY_AND_LAYER_COMMIT_READY"
                                    details:[NSString stringWithFormat:@"client=%.0fx%.0f expected=%.0fx%.0f",
                                             width, height, expected.width, expected.height]];
        }
        // The client reports this flag only after its Core Animation repair
        // transaction has committed, so no fixed post-geometry delay is needed.
        CV3LogToFile(@"[CanvasGate] %@ client=%.0fx%.0f geometry and layer commit ready",
                     self.bundleID, width, height);
    }
    return self.hostView.layer.sublayers.count > 0 || self.hostView.subviews.count > 0;
}

- (void)recoverHostedPresentationIfNeeded:(NSString *)reason {
    if (self.isClosing || self.isStashed || self.isMovingWindow || !self.targetScene ||
        self.hostLifecycleState != CV3HostLifecycleStateLive) return;

    NSTimeInterval now = CACurrentMediaTime();
    if (self.hostContentRecoveryInFlight && now - self.lastHostContentRecoveryAt < 3.0) return;
    self.hostContentRecoveryInFlight = NO;

    BOOL hostAttached = self.hostView && self.hostView.superview &&
        !self.hostView.hidden && self.hostView.alpha > 0.01;
    BOOL hasPresentationContext = !CV3TargetRespondsToSelector(self.hostView, @selector(presentationContext)) ||
        CV3InvokeObject(self.hostView, @selector(presentationContext)) != nil;
    BOOL hasMainLayer = CV3SceneHasRenderableMainLayer(self.targetScene);

    if (hostAttached && hasPresentationContext && hasMainLayer) {
        self.hostContentFailureCount = 0;
        return;
    }

    self.hostContentFailureCount += 1;
    if (self.hostContentFailureCount < 2) return;

    if (now - self.lastHostContentRecoveryAt < 3.0) return;
    self.lastHostContentRecoveryAt = now;
    self.hostContentRecoveryInFlight = YES;

    CV3LogToFile(@"[Recovery] 托管内容层丢失，保留音频与浮窗几何并重建显示层: %@ reason=%@ host=%d context=%d mainLayer=%d",
                 self.bundleID, reason ?: @"Heartbeat", hostAttached, hasPresentationContext, hasMainLayer);
    [self ensureLaunchSplashVisible];
    // Invalidate all delayed attach/retry callbacks from the old host before
    // detaching. Reusing the same generation allows stale callbacks to race
    // the recovery mount and create duplicate host views.
    self.sceneHostGeneration += 1;
    [self detachHostedSceneForReason:@"HostedContentUnavailable" clearScene:NO];
    [self attemptToHostSceneWithRetries:6 delay:0.05 generation:self.sceneHostGeneration];
}

- (void)finishHostingWhenRenderableWithRetries:(NSInteger)retries {
    [self finishHostingWhenRenderableWithRetries:retries generation:self.sceneHostGeneration];
}

- (void)finishHostingWhenRenderableWithRetries:(NSInteger)retries generation:(NSUInteger)generation {
    if (self.isClosing || !self.hostView || generation != self.sceneHostGeneration) return;
    // Remote content children can arrive after the host wrapper is attached.
    // Give them the final canvas before declaring the loading surface ready.
    [self setNeedsLayout];
    [self layoutIfNeeded];
    if ([self hostViewHasRenderableContent]) {
        [self recordColdLaunchMilestone:@"RENDERABLE_CONFIRMED"
                                details:[NSString stringWithFormat:@"host=%@ canvas=%@",
                                         NSStringFromCGRect(self.hostView.frame),
                                         NSStringFromCGRect(self.hostContainerProxy.bounds)]];
        self.hostContentFailureCount = 0;
        self.hostContentRecoveryInFlight = NO;
        [self setHostLifecycleState:CV3HostLifecycleStateLive reason:@"Renderable"];
        [self syncWindowBoundsToClient];
        [self dismissLaunchSplashAnimated];
        if (self.awaitingInitialRenderableContent) {
            self.awaitingInitialRenderableContent = NO;
            [self recordReceptionTrace:@"firstFrame.beforeReveal" force:YES];
            [self recordOrientationTrace:@"firstFrame.beforeReveal" force:YES];
            [UIView performWithoutAnimation:^{
                [CATransaction begin];
                [CATransaction setDisableActions:YES];
                [CATransaction setCompletionBlock:^{
                    [self recordReceptionTrace:@"firstFrame.transactionCommitted" force:YES];
                    [self recordOrientationTrace:@"firstFrame.transactionCommitted" force:YES];
                    if (!self.coldLaunchCompletedRecorded) {
                        self.coldLaunchCompletedRecorded = YES;
                        [self recordColdLaunchMilestone:@"FIRST_FRAME_COMMITTED" details:nil];
                    }
                }];
                self.rootTransformContainer.hidden = NO;
                [self setNeedsLayout];
                [self layoutIfNeeded];
                [CATransaction commit];
            }];
            [self recordOrientationTrace:@"firstFrame.afterRevealRequest" force:YES];
            [self recordColdLaunchMilestone:@"FIRST_FRAME_REVEAL_REQUESTED" details:nil];
        }
        CV3LogToFile(@"[SceneHost] 渲染层已就绪: %@", self.bundleID);
        CV3LogToFile(@"[HostGeometry] bundle=%@ shell=%@ canvas=%@ host=%@ children=%@ displayOrientation=%ld contentOrientation=%ld mapped=%d",
                     self.bundleID, NSStringFromCGRect(self.bounds),
                     NSStringFromCGRect(self.hostContainerProxy.bounds), self.hostView,
                     self.hostView.subviews, (long)CV3HostedPresentationOrientation(self),
                     (long)self.hostedContentOrientation, self.crossOrientationMapApplied);
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            if (self.isClosing || generation != self.sceneHostGeneration) return;
            CV3LogToFile(@"[HostGeometryDetail] bundle=%@ settings=%@ client=%@ hierarchy=%@",
                         self.bundleID, CV3InvokeObject(self.targetScene, @selector(settings)),
                         CV3InvokeObject(self.targetScene, NSSelectorFromString(@"clientSettings")),
                         CV3InvokeObject(self.hostView, NSSelectorFromString(@"recursiveDescription")));
        });
        return;
    }

    if (retries <= 0) {
        if (self.awaitingInitialRenderableContent && self.requiresLandscapeContent && !self.isClosing &&
            self.hostLifecycleState != CV3HostLifecycleStateReleasing) {
            // The hosted game may take several seconds to publish and commit a
            // landscape canvas. Keep polling and relayouting without hiding the
            // actual hosted surface or placing a launch overlay above it.
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.25 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                if (self.isClosing || self.hostLifecycleState == CV3HostLifecycleStateReleasing ||
                    generation != self.sceneHostGeneration) return;
                [self finishHostingWhenRenderableWithRetries:1 generation:generation];
            });
            return;
        }
        self.hostContentRecoveryInFlight = NO;
        CV3LogToFile(@"[Error] Scene 容器存在但渲染层未就绪，保留加载界面: %@", self.bundleID);
        return;
    }

    CFTimeInterval now = CACurrentMediaTime();
    if (!self.awaitingInitialRenderableContent ||
        now - self.lastInitialHostPresentationRefreshTime >= 0.15) {
        self.lastInitialHostPresentationRefreshTime = now;
        [self refreshHostViewPresentation];
    }
    // While waiting for the first frame, check the client's transaction-ready
    // flag once per display frame. Presentation-context refresh remains
    // throttled above so this faster readiness polling does not churn hosting.
    NSTimeInterval nextCheckDelay = self.awaitingInitialRenderableContent ? (1.0 / 60.0) : 0.15;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(nextCheckDelay * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (self.isClosing || self.hostLifecycleState == CV3HostLifecycleStateReleasing ||
            generation != self.sceneHostGeneration) return;
        [self finishHostingWhenRenderableWithRetries:retries - 1 generation:generation];
    });
}

- (void)ensureLaunchSplashVisible {
    // Never obscure the hosted app with a synthetic blur/tint launch layer.
    // Initial presentation is gated separately until the complete remote canvas
    // has committed its final geometry.
    [self.splashView removeFromSuperview];
    self.splashView = nil;
    self.largeSplashIcon = nil;
}

- (void)recordColdLaunchMilestone:(NSString *)milestone details:(NSString *)details {
    [self recordStrictSplitTrace:[@"coldLaunch." stringByAppendingString:milestone ?: @"unknown"]
                         details:[NSString stringWithFormat:@"elapsedMs=%.1f %@",
                                  (CACurrentMediaTime() - self.coldLaunchStartTime) * 1000.0,
                                  details ?: @""]];
}

- (void)dismissLaunchSplashAnimated {
    UIView *splash = self.splashView;
    self.splashView = nil;
    self.largeSplashIcon = nil;
    [splash removeFromSuperview];
}

- (void)enforceSceneForegroundState {
    if (self.isMovingWindow || CACurrentMediaTime() < self.moveSceneSyncSuppressedUntil) return;

    if (!self.targetScene) {
        CV3LogToFile(@"[Recovery] enforceSceneForegroundState 缺失 targetScene，触发冷启动: %@", self.bundleID);
        [self ensureLaunchSplashVisible];
        [self loadAppScene];
        return;
    }
    
    @try {
        // 核心增强：除了检查 isValid，还检查是否还在连接状态
        BOOL sceneValid = CV3InvokeBool(self.targetScene, @selector(isValid), YES);
        
        if (!sceneValid) {
            CV3LogToFile(@"[Recovery] 场景失效，停止自动重连并关闭分屏: %@", self.bundleID);
            [self closeWindow];
            return;
        }

        // 预防性重置：如果检测到 HostView 存在但可能已“冻结”，强制触发层级重新同步
        if (self.hostView && self.hostView.superview) {
            // 通过检查渲染层级是否还具备 Presentation Context 来判断冻结
            if (CV3TargetRespondsToSelector(self.hostView, @selector(presentationContext)) &&
                !CV3InvokeObject(self.hostView, @selector(presentationContext))) {
                CV3LogToFile(@"[Recovery] 检测到 HostView 渲染层断连，强制修复: %@", self.bundleID);
                [self ensureLaunchSplashVisible];
                [self detachHostedSceneForReason:@"PresentationContextDisconnected" clearScene:NO];
                [self attemptToHostSceneWithRetries:1 delay:0]; // 快速尝试重建
                return;
            }
        }

        FBSMutableSceneSettings *settings = [[self.targetScene settings] mutableCopy];
        BOOL needsUpdate = [self applyForegroundSovereigntyToSettings:settings clearDeactivation:YES forceLayout:NO];
        
        if (needsUpdate) {
            [self.targetScene updateSettings:settings withTransitionContext:nil];
            [self beginHostPresentationRepublishIfNeeded:@"foreground.commit"];
            
            // 确保内容状态强制为前台
            if ([self.targetScene respondsToSelector:@selector(_setContentState:)]) {
                [self.targetScene _setContentState:2]; 
            }
            
            // 立即实施层级重刷，而非等待主循环
            [self refreshHostViewPresentation];
            CV3LogToFile(@"[Lifecycle] 已强制更新 %@ 场景设置与渲染上下文", self.bundleID);
        }
    } @catch (NSException *e) {
        CV3LogToFile(@"[Error] enforceSceneForegroundState 异常: %@", e);
    }
}

- (void)updateSovereigntyAssertion {
    if (!self.bundleID || self.isClosing || self.rbsAssertionUnsupported) return;

    // AssertionServices exposes this public private-header contract on iOS 16:
    // BackgroundUI reason=7, flags PreventSuspend=1,
    // PreventThrottleDownCPU=2, AllowIdleSleep=4 and
    // WantsForegroundResourcePriority=8.
    NSUInteger assertionFlags = self.isStashed ? (1 | 4) : (1 | 2 | 8);
    NSUInteger assertionReason = 7;
    NSString *attributeName = self.isStashed ? @"BKS.BackgroundUI.Stashed" : @"BKS.BackgroundUI.Foreground";
    if (self.rbsAssertion && [self.rbsAssertionAttributeName isEqualToString:attributeName]) return;

    if (![self.rbsAssertionLastAttemptedAttributeName isEqualToString:attributeName]) {
        self.rbsAssertionLastAttemptedAttributeName = attributeName;
        self.rbsAssertionFailureCount = 0;
        self.rbsAssertionRetryAfter = 0;
    }
    if (self.rbsAssertionFailureCount >= 5) return;

    NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
    if (now < self.rbsAssertionRetryAfter) return;

    @try {
        Class assertionClass = CV3ClassNamed(@"BKSProcessAssertion");
        if (!assertionClass) {
            @throw [NSException exceptionWithName:@"CV3RBSConfigurationException"
                                           reason:@"BKSProcessAssertion is unavailable"
                                         userInfo:nil];
        }

        BKSProcessAssertion *replacement = [[assertionClass alloc]
            initWithBundleIdentifier:self.bundleID
            flags:assertionFlags
            reason:assertionReason
            name:[NSString stringWithFormat:@"ChevronV3 hosted scene (%@)", self.bundleID]
            withHandler:nil];
        if (!replacement || !replacement.valid) {
            [replacement invalidate];
            @throw [NSException exceptionWithName:@"CV3RBSConfigurationException"
                                           reason:[NSString stringWithFormat:@"BKS BackgroundUI assertion is invalid flags=%lu",
                                                   (unsigned long)assertionFlags]
                                         userInfo:nil];
        }

        id previous = self.rbsAssertion;
        self.rbsAssertion = replacement;
        self.rbsAssertionAttributeName = attributeName;
        self.rbsAssertionFailureCount = 0;
        self.rbsAssertionRetryAfter = 0;
        [previous invalidate];
        CV3LogToFile(@"[Immortality] 已更新 %@ 后台 UI 断言 -> %@ flags=%lu",
                     self.bundleID, attributeName, (unsigned long)assertionFlags);
        CV3LogToFile(@"[Warning][PlaybackTrace] source=SpringBoard event=BKSAssertionAcquired bundle=%@ attribute=%@ flags=%lu",
                     self.bundleID, attributeName, (unsigned long)assertionFlags);
    } @catch (NSException *e) {
        self.rbsAssertionFailureCount++;
        NSUInteger exponent = MIN(self.rbsAssertionFailureCount, (NSUInteger)5);
        self.rbsAssertionRetryAfter = self.rbsAssertionFailureCount >= 5
            ? DBL_MAX
            : now + MIN(60.0, (NSTimeInterval)(1ULL << exponent));
        CV3LogToFile(@"[Error] BKS BackgroundUI assertion 异常: %@", e);
        if (self.rbsAssertionFailureCount >= 5) {
            self.rbsAssertionUnsupported = YES;
            CV3LogToFile(@"[Warning] BKS assertion (%@) 连续异常，已停止定时重试: %@", attributeName, self.bundleID);
        }
    }
}

- (void)animateFocusShadow:(BOOL)focused {
    if (self.isStashed) {
        [self syncWindowShadowForCurrentState];
        return;
    }

    CALayer *shadowLayer = [self visualShadowLayer];
    [self clearOuterWindowShadow];
    shadowLayer.shadowColor = [UIColor blackColor].CGColor;
    [shadowLayer removeAnimationForKey:@"shadowRadius"];
    [shadowLayer removeAnimationForKey:@"shadowOpacity"];
    [shadowLayer removeAnimationForKey:@"shadowOffset"];
    
    CGFloat startRadius = focused ? CV3Style.shadowRadiusUnfocused : CV3Style.shadowRadiusFocused;
    CGFloat peakRadius = focused ? CV3Style.shadowRadiusPeak : (CV3Style.shadowRadiusUnfocused - 4.0);
    CGFloat endRadius = focused ? CV3Style.shadowRadiusFocused : CV3Style.shadowRadiusUnfocused;
    
    CGFloat startOpacity = focused ? CV3Style.shadowOpacityUnfocused : CV3Style.shadowOpacityFocused;
    CGFloat peakOpacity = focused ? CV3Style.shadowOpacityPeak : (CV3Style.shadowOpacityUnfocused - 0.04);
    CGFloat endOpacity = focused ? CV3Style.shadowOpacityFocused : CV3Style.shadowOpacityUnfocused;
    
    CGFloat startOffsetY = focused ? CV3Style.shadowOffsetUnfocusedY : CV3Style.shadowOffsetFocusedY;
    CGFloat peakOffsetY = focused ? CV3Style.shadowOffsetPeakY : (CV3Style.shadowOffsetUnfocusedY - 2.0);
    CGFloat endOffsetY = focused ? CV3Style.shadowOffsetFocusedY : CV3Style.shadowOffsetUnfocusedY;
    
    CAKeyframeAnimation *radiusAnim = [CAKeyframeAnimation animationWithKeyPath:@"shadowRadius"];
    radiusAnim.values = @[@(startRadius), @(peakRadius), @(endRadius)];
    radiusAnim.keyTimes = @[@0.0, @0.4, @1.0];
    radiusAnim.duration = CV3Style.durationMedium;
    radiusAnim.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
    [shadowLayer addAnimation:radiusAnim forKey:@"shadowRadius"];
    shadowLayer.shadowRadius = endRadius;
    
    CAKeyframeAnimation *opacityAnim = [CAKeyframeAnimation animationWithKeyPath:@"shadowOpacity"];
    opacityAnim.values = @[@(startOpacity), @(peakOpacity), @(endOpacity)];
    opacityAnim.keyTimes = @[@0.0, @0.4, @1.0];
    opacityAnim.duration = CV3Style.durationMedium;
    opacityAnim.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
    [shadowLayer addAnimation:opacityAnim forKey:@"shadowOpacity"];
    shadowLayer.shadowOpacity = endOpacity;
    
    CAKeyframeAnimation *offsetAnim = [CAKeyframeAnimation animationWithKeyPath:@"shadowOffset"];
    offsetAnim.values = @[
        [NSValue valueWithCGSize:CGSizeMake(0, startOffsetY)],
        [NSValue valueWithCGSize:CGSizeMake(0, peakOffsetY)],
        [NSValue valueWithCGSize:CGSizeMake(0, endOffsetY)]
    ];
    offsetAnim.keyTimes = @[@0.0, @0.4, @1.0];
    offsetAnim.duration = CV3Style.durationMedium;
    offsetAnim.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
    [shadowLayer addAnimation:offsetAnim forKey:@"shadowOffset"];
    shadowLayer.shadowOffset = CGSizeMake(0, endOffsetY);
}

- (void)setWindowFocused:(BOOL)focused {
    [self recordOrientationTrace:focused ? @"setWindowFocused.begin.focus" : @"setWindowFocused.begin.blur" force:YES];
    BOOL focusChanged = (self.isFocused != focused);
    if (!focusChanged && !focused) return;
    self.isFocused = focused;
    
    [self updateSovereigntyAssertion]; // 同步更新优先级
    [self applyCurrentTransformWithScale:1.0];
    
    [self animateFocusShadow:focused]; // 触发三维物理回弹阴影
    
    self.hostContainerProxy.alpha = 1.0;
    
    [self updateFloatingHomeBarAppearance];
    
    if (focused) {
        [self promoteFloatingWindowInZOrder];
        
        // Dim other windows
        for (CV3FloatingAppWindow *win in floatingWindows) {
            if (win != self && [win isKindOfClass:[CV3FloatingAppWindow class]]) [win setWindowFocused:NO];
        }

        // Z-Order 发生变化，级联刷新所有窗口前台优先级断言
        CV3CascadeUpdateSovereigntyAssertions();
    }
    [self recordOrientationTrace:focused ? @"setWindowFocused.end.focus" : @"setWindowFocused.end.blur" force:YES];
}

- (void)promoteFloatingWindowInZOrder {
    if (self.isClosing) return;

    [self makeKeyAndVisible];
    self.windowLevel = CV3Style.floatingApp;

    // Z-order 层级重排：将当前窗口移至 floatingWindows 数组末尾，使命中测试优先处理它。
    if (floatingWindows && [floatingWindows containsObject:self]) {
        [floatingWindows removeObject:self];
        [floatingWindows addObject:self];
    }
}

- (void)updateResizeHandleAppearance {
    BOOL darkStyle = NO;
    if (@available(iOS 12.0, *)) {
        darkStyle = self.traitCollection.userInterfaceStyle == UIUserInterfaceStyleDark;
    }
    
    UIColor *borderColor = darkStyle ? [[UIColor whiteColor] colorWithAlphaComponent:0.18] : [[UIColor blackColor] colorWithAlphaComponent:0.16];
    
    UIColor *baseColor = self.adaptiveAppColor ?: (darkStyle ? [UIColor systemGrayColor] : [UIColor whiteColor]);
    CGFloat hue = 0, saturation = 0, brightness = 0, alpha = 0;
    if ([baseColor getHue:&hue saturation:&saturation brightness:&brightness alpha:&alpha]) {
        saturation = MIN(0.55, MAX(0.18, saturation));
        brightness = darkStyle ? MIN(0.82, MAX(0.36, brightness)) : MIN(0.98, MAX(0.72, brightness));
        baseColor = [UIColor colorWithHue:hue saturation:saturation brightness:brightness alpha:1.0];
    }

    self.resizeHandle.backgroundColor = [UIColor clearColor];
    self.resizeHandle.layer.borderWidth = 0;
    self.resizeHandle.layer.shadowOpacity = 0;

    CGSize visualSize = self.resizeHandleVisualSize;
    if (visualSize.width <= 0 || visualSize.height <= 0) {
        visualSize = CGSizeMake(MIN(26.0, CGRectGetWidth(self.resizeHandle.bounds)),
                                MIN(26.0, CGRectGetHeight(self.resizeHandle.bounds)));
    }
    CGRect b = CGRectMake(CGRectGetWidth(self.resizeHandle.bounds) - visualSize.width,
                          CGRectGetHeight(self.resizeHandle.bounds) - visualSize.height,
                          visualSize.width,
                          visualSize.height);
    if (!CGRectIsEmpty(b)) {
        self.resizeHandleLayer.frame = b;
        UIBezierPath *path = [UIBezierPath bezierPath];

        CGRect localBounds = self.resizeHandleLayer.bounds;
        CGPoint cornerCenter = CGPointMake(CGRectGetMinX(localBounds), CGRectGetMinY(localBounds));
        CGFloat windowScale = MIN(1.35, MAX(0.78, MIN(self.bounds.size.width, self.bounds.size.height) / 390.0));
        CGFloat arcRadius = MAX(10.0, MIN(localBounds.size.width - 4.0, (CV3Style.floatingChromeCornerRadius + 4.0) * windowScale));
        CGFloat startAngle = (CGFloat)(M_PI_4 * 0.18);
        CGFloat endAngle = (CGFloat)(M_PI_4 * 1.52);
        [path addArcWithCenter:cornerCenter radius:arcRadius startAngle:startAngle endAngle:endAngle clockwise:YES];

        UIColor *strokeColor = baseColor;
        CGFloat strokeHue = 0, strokeSaturation = 0, strokeBrightness = 0, strokeAlpha = 0;
        if ([strokeColor getHue:&strokeHue saturation:&strokeSaturation brightness:&strokeBrightness alpha:&strokeAlpha]) {
            BOOL sourceIsBright = strokeBrightness > 0.62;
            strokeSaturation = sourceIsBright ? MIN(0.42, MAX(0.10, strokeSaturation * 0.65)) : MIN(0.62, MAX(0.20, strokeSaturation + 0.10));
            strokeBrightness = darkStyle ? MIN(0.92, MAX(0.68, strokeBrightness + 0.22)) : (sourceIsBright ? 0.30 : 0.78);
            strokeColor = [UIColor colorWithHue:strokeHue saturation:strokeSaturation brightness:strokeBrightness alpha:1.0];
        }
        self.resizeHandleLayer.path = path.CGPath;
        self.resizeHandleLayer.strokeColor = [strokeColor colorWithAlphaComponent:(darkStyle ? 0.72 : 0.58)].CGColor;
        self.resizeHandleLayer.fillColor = [UIColor clearColor].CGColor;
        self.resizeHandleLayer.lineWidth = MAX(2.0, MIN(3.0, 2.35 * windowScale));
        self.resizeHandleLayer.lineCap = kCALineCapRound;
    }

    self.clippingContainer.layer.borderColor = borderColor.CGColor;
}

- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection {
    [super traitCollectionDidChange:previousTraitCollection];
    [self updateResizeHandleAppearance];
}

- (void)handleGrabberLongPress:(UILongPressGestureRecognizer *)gesture {
    if (gesture.state == UIGestureRecognizerStateBegan) {
        UIImpactFeedbackGenerator *gen = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleHeavy];
        [gen impactOccurred];
    }
}

- (void)handleHideAction {
    [self dismissMultitaskingMenu];
    CV3ExitExposeModeIfNeeded(self, NO);
    UIImpactFeedbackGenerator *gen = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight];
    [gen impactOccurred];

    CGRect screen = CV3DisplayBoundsForWindow(self);
    BOOL isNearLeft = (self.center.x < screen.size.width / 2.0);
    CGRect initialFrame = self.frame;
    UIEdgeInsets safeArea = [self currentSafeAreaInsets];
    CGFloat breath = CV3Style.safeAreaBreath;
    CGFloat stashHalf = kCV3StashIconSize * 0.5;
    CGPoint stashCenter = CGPointMake(CGRectGetMidX(initialFrame), CGRectGetMidY(initialFrame));
    CGFloat minCenterX = safeArea.left + breath + stashHalf;
    CGFloat maxCenterX = screen.size.width - safeArea.right - breath - stashHalf;
    CGFloat minCenterY = safeArea.top + breath + stashHalf;
    CGFloat maxCenterY = screen.size.height - safeArea.bottom - breath - stashHalf;
    if (maxCenterX < minCenterX) maxCenterX = minCenterX;
    if (maxCenterY < minCenterY) maxCenterY = minCenterY;
    stashCenter.x = MIN(MAX(stashCenter.x, minCenterX), maxCenterX);
    stashCenter.y = MIN(MAX(stashCenter.y, minCenterY), maxCenterY);
    CGRect targetFrame = CGRectMake(stashCenter.x - stashHalf, stashCenter.y - stashHalf, kCV3StashIconSize, kCV3StashIconSize);
    CGRect targetFrameInWindow = CGRectOffset(targetFrame, -initialFrame.origin.x, -initialFrame.origin.y);
    UIView *snapshotSourceView = self.hostContainerProxy ?: self.clippingContainer ?: self.appContentWrapper;
    CGRect snapshotStartFrame = [self convertRect:snapshotSourceView.bounds fromView:snapshotSourceView];
    self.stashedRestoreSnapshotImage = [self snapshotImageForRestoreAnimation];
    self.stashedRestoreSnapshotOrientation = self.targetOrientation;
    UIImage *genieImage = self.stashedRestoreSnapshotImage;

    self.stashAnimationTraceID = NSUUID.UUID.UUIDString;
    self.stashAnimationTraceStartTime = CACurrentMediaTime();
    CV3LogStashAnimation(@"[StashAnimation] id=%@ direction=minimize phase=begin bundle=%@ source=%@ target=%@ device_orientation=%ld content_orientation=%ld snapshot=%d",
                 self.stashAnimationTraceID,
                 self.bundleID ?: @"unknown",
                 NSStringFromCGRect(initialFrame),
                 NSStringFromCGRect(targetFrame),
                 (long)CV3TrustedInterfaceOrientation(self.windowScene),
                 (long)self.targetOrientation,
                 genieImage != nil);

    self.preStashFrame = self.frame;
    self.isStashed = YES;
    [self.hostedSession setActive:NO];
    CV3ReleaseKeyboardHostingForWindow(self);
    self.stashedSide = isNearLeft ? 1 : 2;
    [self promoteFloatingWindowInZOrder];
    CV3CascadeUpdateSovereigntyAssertions(); // 级联刷新所有窗口前台优先级断言

    if (!genieImage) {
        self.frame = targetFrame;
        self.appContentWrapper.alpha = 0.0;
        self.resizeHandle.alpha = 0.0;
        self.homeBarView.alpha = 0.0;
        [self normalizeStashedGrabberLayout];
        CV3UpdateFloatingBackdrop(self.windowScene);
        for (CV3FloatingAppWindow *win in [floatingWindows copy]) {
            if ([win isKindOfClass:[CV3FloatingAppWindow class]] && win.isStashed) [win updateGrabberStack];
        }
        CV3LogStashAnimation(@"[StashAnimation] id=%@ direction=minimize phase=completion mode=fallback final=%@ elapsed_ms=%.1f",
                     self.stashAnimationTraceID,
                     NSStringFromCGRect(self.frame),
                     (CACurrentMediaTime() - self.stashAnimationTraceStartTime) * 1000.0);
        self.stashAnimationTraceID = nil;
        self.stashAnimationTraceStartTime = 0;
        return;
    }

    self.stashGrabber.alpha = 0.0;
    self.stashGrabber.bounds = CGRectMake(0, 0, kCV3StashIconSize, kCV3StashIconSize);
    self.stashGrabber.center = CGPointMake(CGRectGetMidX(targetFrameInWindow), CGRectGetMidY(targetFrameInWindow));
    [self updateStashIconAppearance];
    [self applyStashedGrabberOrientation];
    self.appIconMiniView.transform = CGAffineTransformScale(self.appIconMiniView.transform, 0.82, 0.82);
    self.appContentWrapper.alpha = 0.0;
    self.resizeHandle.alpha = 0.0;
    self.homeBarView.alpha = 0.0;
    [self syncWindowShadowForCurrentState];

    CGRect targetIconFrameInWindow = CGRectInset(targetFrameInWindow, kCV3StashIconInset, kCV3StashIconInset);
    [self animateGenieSurfaceImage:genieImage sourceFrame:snapshotStartFrame iconFrame:targetIconFrameInWindow presenting:NO completion:^{
        // The icon fade used to outlive the genie animation by about 120 ms.
        // At this point the UIWindow changes from its full frame to 54x54, so an
        // outstanding center animation would continue in the old coordinate
        // space and visibly push the icon downward before the stack pass fixed it.
        [self.stashGrabber.layer removeAllAnimations];
        [self.appIconMiniView.layer removeAllAnimations];
        self.frame = targetFrame;
        [self visualShadowLayer].shadowOpacity = 0.0;
        [self visualShadowLayer].shadowRadius = 0.0;
        [self visualShadowLayer].shadowOffset = CGSizeZero;
        [self visualShadowLayer].shadowPath = nil;
        self.appContentWrapper.transform = CGAffineTransformIdentity;
        self.appContentWrapper.alpha = 0.0;
        [self.hostView removeFromSuperview];
        [self normalizeStashedGrabberLayout];
        CV3UpdateFloatingBackdrop(self.windowScene);
        for (CV3FloatingAppWindow *win in [floatingWindows copy]) {
            if ([win isKindOfClass:[CV3FloatingAppWindow class]] && win.isStashed) [win updateGrabberStack];
        }
        CV3LogStashAnimation(@"[StashAnimation] id=%@ direction=minimize phase=completion mode=genie final=%@ icon_alpha=%.2f elapsed_ms=%.1f",
                     self.stashAnimationTraceID,
                     NSStringFromCGRect(self.frame),
                     self.stashGrabber.alpha,
                     (CACurrentMediaTime() - self.stashAnimationTraceStartTime) * 1000.0);
        self.stashAnimationTraceID = nil;
        self.stashAnimationTraceStartTime = 0;
    }];

    // Keep this animation inside the genie's 0.34 s lifetime and animate only
    // visual properties. Geometry was established above and must not continue
    // animating after the window switches coordinate spaces in the completion.
    [UIView animateWithDuration:0.16
                          delay:0.18
                        options:UIViewAnimationOptionCurveEaseOut | UIViewAnimationOptionBeginFromCurrentState
                     animations:^{
        self.stashGrabber.alpha = 1.0;
        [self applyStashedGrabberOrientation];
    } completion:nil];
}

- (void)applyStashedGrabberOrientation {
    // A minimized icon is device UI, not hosted-app content. Its only rotation
    // input is the physical device orientation relative to the SpringBoard
    // Scene that contains this window.
    self.stashGrabber.transform = CGAffineTransformIdentity;

    UIInterfaceOrientation deviceOrientation = CV3InterfaceOrientationFromDevice();
    CGSize screenSize = self.windowScene.screen.bounds.size;
    BOOL screenLandscape = screenSize.width > screenSize.height;
    if (CV3IsValidInterfaceOrientation(deviceOrientation) &&
        UIInterfaceOrientationIsLandscape(deviceOrientation) == screenLandscape) {
        CV3LastPhysicalDeviceInterfaceOrientation = deviceOrientation;
    } else if (CV3IsValidInterfaceOrientation(CV3LastPhysicalDeviceInterfaceOrientation) &&
               UIInterfaceOrientationIsLandscape(CV3LastPhysicalDeviceInterfaceOrientation) == screenLandscape) {
        deviceOrientation = CV3LastPhysicalDeviceInterfaceOrientation;
    } else {
        UIInterfaceOrientation sceneCandidate = self.windowScene.interfaceOrientation;
        if (CV3IsValidInterfaceOrientation(sceneCandidate) &&
            UIInterfaceOrientationIsLandscape(sceneCandidate) == screenLandscape) {
            deviceOrientation = sceneCandidate;
        } else {
            deviceOrientation = screenLandscape
                ? UIInterfaceOrientationLandscapeRight
                : UIInterfaceOrientationPortrait;
        }
        CV3LastPhysicalDeviceInterfaceOrientation = deviceOrientation;
    }

    UIInterfaceOrientation sceneOrientation = self.windowScene.interfaceOrientation;
    if (!CV3IsValidInterfaceOrientation(sceneOrientation)) {
        sceneOrientation = deviceOrientation;
    }
    CGAffineTransform deviceTransform = CV3RotationTransformForInterfaceOrientation(deviceOrientation);
    CGAffineTransform sceneTransform = CV3RotationTransformForInterfaceOrientation(sceneOrientation);
    self.appIconMiniView.transform = CGAffineTransformConcat(deviceTransform,
                                                              CGAffineTransformInvert(sceneTransform));
}

- (void)physicalDeviceOrientationDidChange:(NSNotification *)notification {
    (void)notification;
    UIInterfaceOrientation current = CV3InterfaceOrientationFromDevice();
    if (CV3IsValidInterfaceOrientation(current)) {
        CV3LastPhysicalDeviceInterfaceOrientation = current;
    }
    if (self.isClosing || !CV3IsValidInterfaceOrientation(current)) return;

    if (self.isStashed) {
        [UIView performWithoutAnimation:^{
            [self updateStashIconAppearance];
            [self applyStashedGrabberOrientation];
        }];
        return;
    }

    // A landscape-only game's target/content orientation is already landscape
    // while the device is portrait. Comparing orientation values alone therefore
    // reports "no change" when the display later rotates to landscape, even
    // though the SpringBoard Scene/display axes have changed and the shell must
    // be transposed. Force a geometry re-evaluation for this one presentation
    // mode; ordinary floating apps continue through the shared Scene path.
    if (self.prefersLandscapePresentation && self.requiresLandscapeContent) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (self.isClosing || self.isStashed) return;
            [self applyInterfaceOrientation:current force:YES];
        });

        // UIKit can publish the physical orientation before the display Scene's
        // coordinate space settles. Re-evaluate once after that transaction so
        // hosted content and chrome use the same final axes.
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.12 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            if (self.isClosing || self.isStashed) return;
            [self applyInterfaceOrientation:current force:YES];
        });
    }
}

- (void)normalizeStashedGrabberLayout {
    if (!self.isStashed) return;
    self.rootTransformContainer.transform = CGAffineTransformIdentity;
    self.rootTransformContainer.frame = self.bounds;
    self.stashGrabber.bounds = CGRectMake(0, 0, kCV3StashIconSize, kCV3StashIconSize);
    self.stashGrabber.center = CGPointMake(CGRectGetMidX(self.bounds), CGRectGetMidY(self.bounds));
    self.stashGrabber.alpha = 1.0;
    self.stashGrabber.userInteractionEnabled = YES;
    [self updateStashIconAppearance];
    [self applyStashedGrabberOrientation];
    [self bringSubviewToFront:self.stashGrabber];
    [self syncWindowShadowForCurrentState];
}

- (void)updateStashIconAppearance {
    if (!self.stashGrabber || !self.stashIconBackdropView || !self.appIconMiniView) return;

    CGRect bounds = self.stashGrabber.bounds;
    if (CGRectIsEmpty(bounds)) {
        bounds = CGRectMake(0, 0, kCV3StashIconSize, kCV3StashIconSize);
    }

    CGRect backdropFrame = CGRectInset(bounds, 1.0, 1.0);
    CGFloat cornerRadius = 16.0;
    self.stashIconBackdropView.frame = backdropFrame;
    self.stashIconBackdropView.layer.cornerRadius = cornerRadius;
    if (@available(iOS 13.0, *)) {
        self.stashIconBackdropView.layer.cornerCurve = kCACornerCurveContinuous;
    }
    CV3ApplyGlassAccentStyle(self.stashIconBackdropView,
                             self.stashIconBackdropView.contentView,
                             self.stashIconHighlightLayer,
                             nil,
                             cornerRadius,
                             0.88,
                             YES);

    CGRect iconFrame = CGRectInset(bounds, kCV3StashIconInset, kCV3StashIconInset);
    self.appIconMiniView.bounds = CGRectMake(0, 0, iconFrame.size.width, iconFrame.size.height);
    self.appIconMiniView.center = CGPointMake(CGRectGetMidX(iconFrame), CGRectGetMidY(iconFrame));
    self.appIconMiniView.layer.cornerRadius = 10.0;
    self.appIconMiniView.layer.borderColor = [[UIColor whiteColor] colorWithAlphaComponent:0.30].CGColor;
    self.appIconMiniView.layer.borderWidth = 1.0 / [UIScreen mainScreen].scale;

    self.stashGrabber.layer.shadowPath = [UIBezierPath bezierPathWithRoundedRect:backdropFrame cornerRadius:cornerRadius].CGPath;
    [self.stashGrabber bringSubviewToFront:self.appIconMiniView];
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
            }
            [self updateStashIconAppearance];
            [self updateResizeHandleAppearance];
            [self updateFloatingHomeBarAppearance];
        });
    });
}
- (void)triggerCollisionImpulseAtPoint:(CGPoint)point {
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
    [self recordOrientationTrace:@"applyCurrentTransform.begin" force:YES];
    // A landscape-only app already owns a landscape shell and landscape
    // canvas. Reapplying the display's ±90° transform during focus changes
    // recreates the legacy portrait-card presentation with sideways content.
    BOOL hostedLandscapeOwnsPresentation = self.prefersLandscapePresentation &&
        UIInterfaceOrientationIsLandscape(self.hostedContentOrientation);
    CGAffineTransform transform = hostedLandscapeOwnsPresentation
        ? CV3HostedContentRotationInScene(self)
        : self.baseRotationTransform;
    if (scale != 1.0) {
        transform = CGAffineTransformScale(transform, scale, scale);
    }
    self.transform = CGAffineTransformIdentity; // Keep physical upright
    self.rootTransformContainer.transform = transform;
    [self recordOrientationTrace:@"applyCurrentTransform.end" force:YES];
}

- (CALayer *)visualShadowLayer {
    return self.appContentWrapper ? self.appContentWrapper.layer : self.layer;
}

- (void)clearOuterWindowShadow {
    self.layer.shadowPath = nil;
    self.layer.shadowOpacity = 0.0;
    self.layer.shadowRadius = 0.0;
    self.layer.shadowOffset = CGSizeZero;
}

- (CGRect)currentVisualShadowFrame {
    return self.appContentWrapper ? self.appContentWrapper.bounds : self.bounds;
}

- (void)syncWindowShadowForCurrentState {
    CALayer *shadowLayer = [self visualShadowLayer];
    [self clearOuterWindowShadow];
    [shadowLayer removeAnimationForKey:@"shadowRadius"];
    [shadowLayer removeAnimationForKey:@"shadowOpacity"];
    [shadowLayer removeAnimationForKey:@"shadowOffset"];
    shadowLayer.shadowColor = [UIColor blackColor].CGColor;

    if (self.isStashed) {
        shadowLayer.shadowPath = nil;
        shadowLayer.shadowOpacity = 0.0;
        shadowLayer.shadowRadius = 0.0;
        shadowLayer.shadowOffset = CGSizeZero;
        return;
    }

    CGFloat minEdge = MIN(self.bounds.size.width, self.bounds.size.height);
    CGFloat adaptiveRadius = MAX(CV3Style.adaptiveCornerRadiusMin, MIN(CV3Style.adaptiveCornerRadiusMax, minEdge * CV3Style.adaptiveCornerRadiusRatio));
    shadowLayer.shadowPath = [UIBezierPath bezierPathWithRoundedRect:[self currentVisualShadowFrame] cornerRadius:adaptiveRadius].CGPath;
    shadowLayer.shadowOpacity = self.isFocused ? CV3Style.shadowOpacityFocused : CV3Style.shadowOpacityUnfocused;
    shadowLayer.shadowRadius = self.isFocused ? CV3Style.shadowRadiusFocused : CV3Style.shadowRadiusUnfocused;
    shadowLayer.shadowOffset = CGSizeMake(0, self.isFocused ? CV3Style.shadowOffsetFocusedY : CV3Style.shadowOffsetUnfocusedY);
}

- (void)layoutSubviews {
    [self recordStrictSplitTrace:@"layout.entry" details:nil];
    if (self.isStashed || self.isInLayout) {
        [self recordStrictSplitTrace:@"layout.rejected"
                             details:[NSString stringWithFormat:@"stashed=%d reentrant=%d", self.isStashed, self.isInLayout]];
        return;
    }
    self.isInLayout = YES;

    // Scene settings are asynchronous acknowledgements. They must not replace
    // the requested orientation while a previous transaction is still settling.

    UIInterfaceOrientation activeOrientation = self.prefersLandscapePresentation &&
        UIInterfaceOrientationIsLandscape(self.hostedContentOrientation)
        ? self.hostedContentOrientation
        : CV3TrustedInterfaceOrientation(self.windowScene);
    if (self.prefersLandscapePresentation &&
        UIInterfaceOrientationIsLandscape(self.hostedContentOrientation) &&
        (!CV3IsValidInterfaceOrientation(activeOrientation) ||
         !UIInterfaceOrientationIsLandscape(activeOrientation))) {
        activeOrientation = self.hostedContentOrientation;
    }
    if (!CV3IsValidInterfaceOrientation(activeOrientation)) {
        activeOrientation = UIInterfaceOrientationPortrait;
    }
    self.targetOrientation = activeOrientation;

    // Keep the UIWindow shell in the coordinate system supplied by the active
    // display scene. Hosted content is rotated below, inside the logical root.
    // Swapping bounds here is safe because the window transform itself remains
    // identity, so frame/center calculations continue to use physical points.
    BOOL wantsLandscape = CV3ShellShouldBeLandscape(self, activeOrientation);
    BOOL shellIsLandscape = self.bounds.size.width > self.bounds.size.height;
    if (wantsLandscape != shellIsLandscape && self.bounds.size.width > 0.0 && self.bounds.size.height > 0.0) {
        CGSize shellSize = self.bounds.size;
        self.bounds = CGRectMake(0, 0, shellSize.height, shellSize.width);
    }

    UIInterfaceOrientation sceneOrientation = self.windowScene
        ? self.windowScene.interfaceOrientation
        : UIInterfaceOrientationUnknown;
    BOOL sceneOrientationValid = CV3IsValidInterfaceOrientation(sceneOrientation);
    CGAffineTransform contentRotation = self.prefersLandscapePresentation
        ? CV3HostedContentRotationInScene(self)
        : CGAffineTransformIdentity;
    if (!self.prefersLandscapePresentation &&
        (!sceneOrientationValid || sceneOrientation != activeOrientation)) {
        contentRotation = CV3RotationTransformForInterfaceOrientation(activeOrientation);
    }
    // baseRotationTransform is the device orientation state consumed by the
    // global dispatcher. Keep it canonical even when the Scene already owns
    // the physical rotation; contentRotation is the local compensation below.
    self.baseRotationTransform = CV3RotationTransformForInterfaceOrientation(activeOrientation);
    self.transform = CGAffineTransformIdentity;
    [self recordStrictSplitTrace:@"layout.orientationDecision"
                         details:[NSString stringWithFormat:@"active=%ld scene=%ld client=%ld acknowledged=%ld wantsLandscape=%d shellWasLandscape=%d rotation=%@",
                                  (long)activeOrientation, (long)sceneOrientation,
                                  (long)CV3HostedClientOrientation(self),
                                  (long)self.clientAcknowledgedOrientation,
                                  wantsLandscape, shellIsLandscape,
                                  NSStringFromCGAffineTransform(contentRotation)]];
    
    [super layoutSubviews];
    
    CGRect physicalFrame = self.bounds;
    CGFloat fullW = physicalFrame.size.width;
    CGFloat fullH = physicalFrame.size.height;
    
    CGFloat logicalW, logicalH;
    BOOL needsManualRotation = !CGAffineTransformIsIdentity(contentRotation);
    BOOL rotationSwapsAxes = fabs(contentRotation.b) > 0.5 || fabs(contentRotation.c) > 0.5;
    if (needsManualRotation && rotationSwapsAxes) {
        logicalW = fullH;
        logicalH = fullW;
    } else {
        logicalW = fullW;
        logicalH = fullH;
    }

    self.rootTransformContainer.bounds = CGRectMake(0, 0, logicalW, logicalH);
    self.rootTransformContainer.center = CGPointMake(fullW / 2.0, fullH / 2.0);
    self.rootTransformContainer.transform = contentRotation;
    [self recordStrictSplitTrace:@"layout.rootGeometryApplied"
                         details:[NSString stringWithFormat:@"logical=%.2fx%.2f physical=%.2fx%.2f swapsAxes=%d",
                                  logicalW, logicalH, fullW, fullH, rotationSwapsAxes]];

    self.appContentWrapper.bounds = CGRectMake(0, 0, logicalW, logicalH);
    self.appContentWrapper.center = CGPointMake(logicalW / 2.0, logicalH / 2.0);

    [self layoutFloatingHomeBarForBounds:self.appContentWrapper.bounds];

    CGAffineTransform jellyTransform = CGAffineTransformIdentity;
    CGFloat pushFactor = 0;
    NSInteger pushAxis = 0; // 1: X, 2: Y
    if (floatingWindows && floatingWindows.count > 1) {
        for (CV3FloatingAppWindow *other in floatingWindows) {
            if (other == self || other.isStashed || ![other isKindOfClass:[CV3FloatingAppWindow class]]) continue;
            
            CGFloat dx = self.center.x - other.center.x;
            CGFloat dy = self.center.y - other.center.y;
            CGFloat distance = sqrt(dx * dx + dy * dy);
            
            CGFloat threshold = (self.bounds.size.width + other.bounds.size.width) / 2.0 + 15.0;
            if (distance < threshold && distance > 0.1) {
                CGFloat overlap = threshold - distance;
                pushFactor = MIN(0.07, (overlap / threshold) * 0.25);
                pushAxis = (fabs(dx) > fabs(dy)) ? 1 : 2;
                break; // 每次只对最贴近的一个进行判定
            }
        }
    }
    
    if (pushFactor > 0.001) {
        self.collisionReleaseValue = pushFactor;
        self.collisionReleaseAxis = pushAxis;
        self.collisionReleaseTime = 0;
        
        CGFloat scaleX = (pushAxis == 1) ? (1.0 - pushFactor) : 1.0;
        CGFloat scaleY = (pushAxis == 2) ? (1.0 - pushFactor) : 1.0;
        jellyTransform = CGAffineTransformMakeScale(scaleX, scaleY);
    } else {
        if (self.collisionReleaseValue > 0.001) {
            self.collisionReleaseValue = 0;
            self.collisionReleaseTime = 0;
            CGAffineTransform releaseTransform = self.rootTransformContainer.transform;
            // 优化：解耦 layoutSubviews 递归 pass，改用平滑 Spring 过渡复位
            [UIView animateWithDuration:0.35 delay:0 usingSpringWithDamping:0.75 initialSpringVelocity:0.5 options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction animations:^{
                self.rootTransformContainer.transform = releaseTransform;
            } completion:nil];
        }
    }
    self.rootTransformContainer.transform = CGAffineTransformConcat(self.rootTransformContainer.transform, jellyTransform);

    // 4. 更新子组件布局 (基于直立的逻辑坐标系)
    self.clippingContainer.bounds = CGRectMake(0, 0, logicalW, logicalH);
    self.clippingContainer.center = CGPointMake(logicalW / 2.0, logicalH / 2.0);
    // Do not rely solely on autoresizing here: the outer blur is the visible
    // shell of the split window and must track the same logical bounds as the
    // clipping container after an orientation change.
    self.glassBackdrop.bounds = self.clippingContainer.bounds;
    self.glassBackdrop.center = CGPointMake(logicalW / 2.0, logicalH / 2.0);
    
    CGFloat minEdge = MIN(logicalW, logicalH);
    CGFloat adaptiveRadius = MAX(CV3Style.adaptiveCornerRadiusMin, MIN(CV3Style.adaptiveCornerRadiusMax, minEdge * CV3Style.adaptiveCornerRadiusRatio));
    self.layer.cornerRadius = adaptiveRadius;
    self.clippingContainer.layer.cornerRadius = adaptiveRadius;
    if (@available(iOS 13.0, *)) {
        self.layer.cornerCurve = kCACornerCurveContinuous;
        self.clippingContainer.layer.cornerCurve = kCACornerCurveContinuous;
    }
    self.clippingContainer.layer.borderWidth = 1.0 / [UIScreen mainScreen].scale;

    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    self.cyanLayer.frame = self.clippingContainer.bounds;
    self.cyanLayer.cornerRadius = adaptiveRadius;
    
    self.magentaLayer.frame = self.clippingContainer.bounds;
    self.magentaLayer.cornerRadius = adaptiveRadius;
    
    self.innerGlowLayer.frame = self.clippingContainer.bounds;
    self.innerGlowLayer.cornerRadius = adaptiveRadius;
    
    self.specularHighlight.frame = self.clippingContainer.bounds;
    self.specularHighlight.cornerRadius = adaptiveRadius;
    if (@available(iOS 13.0, *)) {
        self.cyanLayer.cornerCurve = kCACornerCurveContinuous;
        self.magentaLayer.cornerCurve = kCACornerCurveContinuous;
        self.innerGlowLayer.cornerCurve = kCACornerCurveContinuous;
        self.specularHighlight.cornerCurve = kCACornerCurveContinuous;
    }
    [CATransaction commit];

    // 5. 更新内部 App 场景 (等比铺满算法：基于直立窗口比例动态映射虚拟画布)
    if (self.hostContainerProxy) {
        CGRect virtualBounds = [self currentHostedSceneBounds];
        // Use exactly the same canvas as applyHostedSceneLayoutToSettings:.
        CGFloat virtualW = MAX(CGRectGetWidth(virtualBounds), 1.0);
        CGFloat virtualH = MAX(CGRectGetHeight(virtualBounds), 1.0);
        // Preserve the Scene canvas. Enlarging only the host's bounds creates
        // empty space: the remote application still renders its original size.
        CGFloat uniformScale = MIN(logicalW / virtualW, logicalH / virtualH);
        [self recordStrictSplitTrace:@"layout.hostDecision"
                             details:[NSString stringWithFormat:@"virtual=%@ logical=%.2fx%.2f scale=%.6f",
                                      NSStringFromCGRect(virtualBounds), logicalW, logicalH, uniformScale]];
        
        if (!self.liveResizeSnapshotView && !self.isMovingWindow) {
            [self recordStrictSplitTrace:@"layout.sceneSync.begin" details:nil];
            [self syncHostedSceneLayoutForce:NO];
            [self recordStrictSplitTrace:@"layout.sceneSync.end" details:nil];
        }

        self.hostContainerProxy.transform = CGAffineTransformIdentity;
        self.hostContainerProxy.bounds = virtualBounds;
        if (self.hostView) {
            self.hostView.transform = CGAffineTransformIdentity;
            self.hostView.frame = virtualBounds;
            [self.hostView layoutIfNeeded];
            // FrontBoard can return a wrapper around the actual scene host.
            // Match PullOver-X layoutContextView: resize the direct hosted
            // children as well; changing just the wrapper leaves stale frames.
            for (UIView *content in [self.hostView.subviews copy]) {
                if (!CGRectEqualToRect(content.frame, self.hostView.bounds)) {
                    CV3LogToFile(@"[HostGeometry] %@ child=%@ old=%@ canvas=%@",
                                 self.bundleID, NSStringFromClass(content.class),
                                 NSStringFromCGRect(content.frame), NSStringFromCGRect(self.hostView.bounds));
                    content.frame = self.hostView.bounds;
                }
                content.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
                [content layoutIfNeeded];
            }
            [self synchronizeHostedContextLayerGeometry];
            [self recordStrictSplitTrace:@"layout.hostGeometryApplied" details:nil];
        }
        self.hostContainerProxy.layer.anchorPoint = CGPointMake(0.5, 0.5);
        self.hostContainerProxy.center = CGPointMake(logicalW / 2.0, logicalH / 2.0);
        self.hostContainerProxy.transform = CGAffineTransformMakeScale(uniformScale, uniformScale);
    }
    if (self.homeBarView && self.homeBarView.superview) {
        [self.homeBarView.superview bringSubviewToFront:self.homeBarView];
    }
    
    if (!self.isLiveResizing) {
        [self visualShadowLayer].shadowPath = [UIBezierPath bezierPathWithRoundedRect:[self currentVisualShadowFrame] cornerRadius:adaptiveRadius].CGPath;
    }
    
    self.isInLayout = NO;
    [self recordStrictSplitTrace:@"layout.exit" details:nil];
    [self recordOrientationTrace:@"layoutSubviews.end" force:NO];
}

- (void)clampToScreenBounds {
    if (self.isStashed) return; // 隐藏状态下跳过钳位，允许 origin.x 超出屏幕
    
    UIEdgeInsets safeArea = [self currentSafeAreaInsets];
    CGRect screenBounds = CV3DisplayBoundsForWindow(self);
    
    CGRect frame = self.frame;
    CGFloat breath = CV3Style.safeAreaBreath;
    if (frame.origin.x < safeArea.left + breath) frame.origin.x = safeArea.left + breath;
    if (frame.origin.y < safeArea.top + breath) frame.origin.y = safeArea.top + breath;
    if (CGRectGetMaxX(frame) > screenBounds.size.width - safeArea.right - breath) frame.origin.x = screenBounds.size.width - safeArea.right - breath - frame.size.width;
    if (CGRectGetMaxY(frame) > screenBounds.size.height - safeArea.bottom - breath) frame.origin.y = screenBounds.size.height - safeArea.bottom - breath - frame.size.height;
    
    // 核心修复：严禁在有 Transform (如缩放/旋转) 的情况下直接设置 frame。
    // 使用 center 进行平移钳位，确保不会触发无限抖动。
    self.center = CGPointMake(CGRectGetMidX(frame), CGRectGetMidY(frame));
}

- (FBScene *)getSceneForBundleID:(NSString *)bundleID {
    @try {
        SBApplication *app = [[CV3ClassNamed(@"SBApplicationController") sharedInstance] applicationWithBundleIdentifier:bundleID];
        if ([app respondsToSelector:@selector(mainScene)]) {
            FBScene *scene = [app mainScene];
            // 核心修复：严禁返回已失效或正在销毁的场景，强制触发重试逻辑等待新场景创建
            if (scene && !CV3InvokeBool(scene, @selector(isValid), YES)) {
                CV3LogToFile(@"[Debug] 忽略无效的旧场景: %@", bundleID);
            } else if (scene) {
                return scene;
            }
        }
        
        FBSceneManager *manager = [CV3ClassNamed(@"FBSceneManager") sharedInstance];
        
        // iOS 16 fallback: check if 'scenes' property exists (returns NSSet)
        if ([manager respondsToSelector:@selector(scenes)]) {
            id scenesSet = [manager valueForKey:@"scenes"];
            if ([scenesSet isKindOfClass:[NSSet class]]) {
                for (FBScene *scene in scenesSet) {
                    if (CV3IdentifierContainsExactBundleID(scene.identifier, bundleID)) {
                        if (!CV3InvokeBool(scene, @selector(isValid), YES)) continue;
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
            if (CV3IdentifierContainsExactBundleID(key, bundleID)) {
                FBScene *scene = scenes[key];
                if (!CV3InvokeBool(scene, @selector(isValid), YES)) continue;
                return scene;
            }
        }
    } @catch (NSException *e) {
        CV3LogToFile(@"[Error] getSceneForBundleID failed: %@", e);
    }
    return nil;
}

- (void)attemptToHostSceneWithRetries:(int)retries delay:(double)delay {
    [self attemptToHostSceneWithRetries:retries delay:delay generation:self.sceneHostGeneration];
}

- (void)attemptToHostSceneWithRetries:(int)retries delay:(double)delay generation:(NSUInteger)generation {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (self.isClosing || generation != self.sceneHostGeneration) {
            CV3LogToFile(@"[SceneHost] 忽略过期挂载任务 %@ generation=%lu current=%lu closing=%d",
                         self.bundleID, (unsigned long)generation,
                         (unsigned long)self.sceneHostGeneration, self.isClosing);
            return;
        }
        [self setHostLifecycleState:CV3HostLifecycleStateWaitingForScene reason:@"RetryAttempt"];
        @try {
            FBScene *targetScene = [self getSceneForBundleID:self.bundleID];
            
            if (targetScene) {
                self.targetScene = targetScene;
                if (!self.coldLaunchSceneFoundRecorded) {
                    self.coldLaunchSceneFoundRecorded = YES;
                    [self recordColdLaunchMilestone:@"SCENE_FOUND" details:nil];
                }
                [self setHostLifecycleState:CV3HostLifecycleStatePrepared reason:@"SceneFound"];
                CV3LogToFile(@"[Debug] 找到场景: %@ (retries left: %d)", self.bundleID, retries);

                // The initial hosted-state post can precede a cold-launched
                // client's Darwin registration. Re-post after its Scene exists
                // so the client bridge starts orientation and canvas reporting
                // before the first hosted surface settles.
                CV3PostHostedState(self.bundleID, YES);
                
                // Step 1: 确保 Scene 已准备好被托管
                FBSMutableSceneSettings *settings = [[targetScene settings] mutableCopy];
                [self applyForegroundSovereigntyToSettings:settings clearDeactivation:YES forceLayout:YES];

                [targetScene updateSettings:settings withTransitionContext:nil];
                
                if ([targetScene respondsToSelector:@selector(_setContentState:)]) {
                    [targetScene _setContentState:2]; // Ready
                }
                
                // Step 2: 优先重用已有的渲染视图，避免在 Scene 尚未完全就绪前重建引发死视图黑屏
                @try {
                    UIView *hostedView = self.hostView;
                    BOOL isReused = (hostedView != nil);
                    if (!hostedView) {
                        hostedView = [self hostViewForScene:targetScene];
                    }

                    if (!hostedView) {
                        hostedView = [[CV3ClassNamed(@"_UISceneLayerHostContainerView") alloc]
                                      initWithScene:targetScene
                                      debugDescription:@"ChevronV3Host"];
                        UIScenePresentationContext *context = [[CV3ClassNamed(@"UIScenePresentationContext") alloc] _initWithDefaultValues];
                        if ([context respondsToSelector:@selector(setPresentedLayerTypes:)]) [context setPresentedLayerTypes:7];
                        if ([context respondsToSelector:@selector(setAppearanceStyle:)]) [context setAppearanceStyle:2];
                        if ([context respondsToSelector:@selector(setClipsToBounds:)]) [context setClipsToBounds:YES];
                        CV3InvokeObject1(hostedView, @selector(_setPresentationContext:), context);
                    }
                    
                    if (hostedView) {
                        hostedView.layer.cornerRadius = 0;
                        hostedView.layer.masksToBounds = YES;
                        
                        self.hostView = hostedView;
                        self.hostView.accessibilityIdentifier = @"ChevronV3Host";
                        
                        // 核心：将真实画面插入 Splash 之下，确保过渡动画淡出时能自然显露内容
                        if (!hostedView.superview) {
                            if (self.splashView) {
                                [self.hostContainerProxy insertSubview:hostedView belowSubview:self.splashView];
                            } else {
                                [self.hostContainerProxy addSubview:hostedView];
                            }
                        }
                        [self recordOrientationTrace:@"hostView.attached" force:YES];
                        [self recordReceptionTrace:@"hostView.attached" force:YES];
                        if (!self.coldLaunchHostAttachedRecorded) {
                            self.coldLaunchHostAttachedRecorded = YES;
                            [self recordColdLaunchMilestone:@"HOST_VIEW_ATTACHED"
                                                    details:NSStringFromClass([hostedView class])];
                        }
                        
                        CV3LogToFile(isReused ? @"[Debug] 成功重用已有的 _UISceneLayerHostContainerView" : @"[Debug] 成功通过 _UISceneLayerHostContainerView 创建渲染视图");
                        
                        [self finishHostingWhenRenderableWithRetries:200 generation:generation];
                    } else {
                        CV3LogToFile(@"[Error] _UISceneLayerHostContainerView 创建/重用失败");
                    }
                } @catch (NSException *e) {
                    CV3LogToFile(@"[Error] 获取 SceneContainerView 失败: %@", e);
                }
            } else {
                [self setHostLifecycleState:CV3HostLifecycleStateWaitingForScene reason:@"SceneUnavailable"];
                CV3LogToFile(@"[Debug] 未找到场景: %@", self.bundleID);
                if (retries > 0) {
                    // The first lookup is immediate. Back off gently after a
                    // miss so cold-launched apps are discovered quickly without
                    // exhausting all retries in the same run-loop turn.
                    double nextDelay = MIN(MAX(delay * 1.25, 0.025), 0.15);
                    [self attemptToHostSceneWithRetries:retries - 1 delay:nextDelay generation:generation];
                } else {
                    CV3LogToFile(@"[Error] targetScene not found after launch for %@", self.bundleID);
                }
            }
        } @catch (NSException *e) {
            CV3LogToFile(@"[Error] Floating window load scene failed: %@", e);
        }
    });
}

- (void)loadAppScene {
    NSUInteger generation = ++self.sceneHostGeneration;
    [self setHostLifecycleState:CV3HostLifecycleStatePreparing reason:@"LoadAppScene"];
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self.isClosing || generation != self.sceneHostGeneration) return;
        @try {
            [self ensureLaunchSplashVisible];
            [self recordColdLaunchMilestone:@"LAUNCH_APPLICATION_BEGIN" details:nil];
            [[UIApplication sharedApplication] launchApplicationWithIdentifier:self.bundleID suspended:YES];
            [self recordColdLaunchMilestone:@"LAUNCH_APPLICATION_RETURNED" details:nil];
            
            [self updateSovereigntyAssertion];

            // Probe immediately, then use short bounded backoff for cold starts.
            // This removes the unconditional 300 ms before Scene acquisition.
            [self attemptToHostSceneWithRetries:40 delay:0.0 generation:generation];
            
            // Keep the loading surface visible until the hosted Scene supplies a render layer.
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(12.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                if (!self.isClosing && generation == self.sceneHostGeneration && self.splashView) {
                    CV3LogToFile(@"[Recovery] 启动超时，重新请求 Scene 渲染层: %@", self.bundleID);
                    [self attemptToHostSceneWithRetries:3 delay:0.0 generation:generation];
                }
            });
        } @catch (NSException *e) {
            CV3LogToFile(@"[Error] Floating window launch failed: %@", e);
        }
    });
}

- (void)handleMoveLongPress:(UIGestureRecognizer *)gesture {
    static CGPoint initialTouchOffset;
    static CGPoint lastVelocity;
    static NSTimeInterval lastTime;
    
    CGPoint currentPoint = [gesture locationInView:nil];
    CGRect screen = CV3DisplayBoundsForWindow(self);
    
    if (gesture.state == UIGestureRecognizerStateBegan) {
        CV3LogToFile(@"[MoveGesture] handleMoveLongPress state began. Dismissing multitaskingMenu");
        self.isMovingWindow = YES;
        self.moveSceneSyncSuppressedUntil = DBL_MAX;
        [self dismissMultitaskingMenu];
        CV3ExitExposeModeIfNeeded(self, YES);
        if (!self.isStashed) {
            self.stashGrabber.alpha = 0;
            self.clippingContainer.alpha = 1.0;
            self.appContentWrapper.alpha = 1.0;
            self.appContentWrapper.transform = CGAffineTransformIdentity;
            self.resizeHandle.alpha = 1.0;
            self.homeBarView.alpha = 1.0;
        }
        self.isFullscreenMode = NO;
        self.isCompactMode = NO;
        [self setWindowFocused:YES];
        CGPoint centerInWindow = self.center;
        initialTouchOffset = CGPointMake(currentPoint.x - centerInWindow.x, currentPoint.y - centerInWindow.y);
        
        [self startLiquidMotion];
        
        CGFloat minEdge = MIN(self.bounds.size.width, self.bounds.size.height);
        CGFloat adaptiveRadius = MAX(CV3Style.adaptiveCornerRadiusMin, MIN(CV3Style.adaptiveCornerRadiusMax, minEdge * CV3Style.adaptiveCornerRadiusRatio));
        [self visualShadowLayer].shadowPath = [UIBezierPath bezierPathWithRoundedRect:[self currentVisualShadowFrame] cornerRadius:adaptiveRadius].CGPath;
        [UIView animateWithDuration:0.3 animations:^{
            [self visualShadowLayer].shadowOpacity = CV3Style.shadowOpacityPeak;
            [self visualShadowLayer].shadowRadius = CV3Style.shadowRadiusPeak;
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
        
        // 2. 更新惯性拉伸阴影与高度抬起
        CGFloat speed = sqrt(lastVelocity.x * lastVelocity.x + lastVelocity.y * lastVelocity.y);
        CGFloat elevationBoost = MIN(CV3Style.dragLagShadowElevationMax, speed * CV3Style.dragLagShadowElevationFactor);
        
        CGFloat dx = -lastVelocity.x * CV3Style.dragLagShadowFactor;
        CGFloat dy = -lastVelocity.y * CV3Style.dragLagShadowFactor + CV3Style.shadowOffsetPeakY + elevationBoost;
        CGFloat maxOffset = CV3Style.dragLagShadowMaxOffset;
        dx = MAX(-maxOffset, MIN(maxOffset, dx));
        dy = MAX(-maxOffset + CV3Style.shadowOffsetPeakY + elevationBoost, MIN(maxOffset + CV3Style.shadowOffsetPeakY + elevationBoost, dy));
        
        [CATransaction begin];
        [CATransaction setDisableActions:YES];
        [self visualShadowLayer].shadowRadius = CV3Style.shadowRadiusPeak + elevationBoost;
        [self visualShadowLayer].shadowOpacity = CV3Style.shadowOpacityPeak - elevationBoost * 0.005;
        [self visualShadowLayer].shadowOffset = CGSizeMake(dx, dy);
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

        [self layoutFloatingHomeBarForBounds:self.appContentWrapper.bounds];
    }
    
    if (gesture.state == UIGestureRecognizerStateEnded ||
        gesture.state == UIGestureRecognizerStateCancelled ||
        gesture.state == UIGestureRecognizerStateFailed) {
        [self stopLiquidMotion];
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
            self.isStashed = NO;
            self.stashedSide = 0;
            self.stashGrabber.alpha = 0;
            self.clippingContainer.alpha = 1.0;
            self.appContentWrapper.alpha = 1.0;
            self.appContentWrapper.transform = CGAffineTransformIdentity;
            self.resizeHandle.alpha = 1.0;

            CGRect targetFrame = self.frame;
            UIEdgeInsets safeArea = [self currentSafeAreaInsets];
            CGFloat breath = CV3Style.safeAreaBreath;
            CGFloat minX = safeArea.left + breath;
            CGFloat minY = safeArea.top + breath;
            CGFloat maxX = screen.size.width - safeArea.right - breath - targetFrame.size.width;
            CGFloat maxY = screen.size.height - safeArea.bottom - breath - targetFrame.size.height;

            if (maxX < minX) maxX = minX;
            if (maxY < minY) maxY = minY;

            targetFrame.origin.x = MIN(MAX(targetFrame.origin.x, minX), maxX);
            targetFrame.origin.y = MIN(MAX(targetFrame.origin.y, minY), maxY);
            
            if (!CGRectEqualToRect(targetFrame, self.frame)) {
                self.center = CGPointMake(CGRectGetMidX(targetFrame), CGRectGetMidY(targetFrame));
            }
        } completion:^(BOOL finished) {
            self.moveSceneSyncSuppressedUntil = CACurrentMediaTime() + 0.8;
            self.isMovingWindow = NO;
            [self layoutFloatingHomeBarForBounds:self.appContentWrapper.bounds];
            // The drag phase applies a velocity-dependent peak shadow. UIKit's
            // position spring can interrupt the separate shadow animation, so
            // normalize the model layer only after movement has fully settled.
            [self syncWindowShadowForCurrentState];
            CV3SaveWindowLayout(self);
        }];
        
        // Settle directly from the velocity-dependent drag shadow to the
        // steady focus shadow. animateFocusShadow: deliberately contains a
        // dark peak keyframe, which reads as a black flash when the user lets
        // go after moving the window.
        CALayer *shadowLayer = [self visualShadowLayer];
        [self clearOuterWindowShadow];
        [shadowLayer removeAnimationForKey:@"shadowRadius"];
        [shadowLayer removeAnimationForKey:@"shadowOpacity"];
        [shadowLayer removeAnimationForKey:@"shadowOffset"];
        CGFloat settledRadius = self.isFocused ? CV3Style.shadowRadiusFocused : CV3Style.shadowRadiusUnfocused;
        CGFloat settledOpacity = self.isFocused ? CV3Style.shadowOpacityFocused : CV3Style.shadowOpacityUnfocused;
        CGFloat settledOffsetY = self.isFocused ? CV3Style.shadowOffsetFocusedY : CV3Style.shadowOffsetUnfocusedY;
        [UIView animateWithDuration:0.24
                              delay:0
                            options:UIViewAnimationOptionBeginFromCurrentState |
                                    UIViewAnimationOptionCurveEaseOut |
                                    UIViewAnimationOptionAllowUserInteraction
                         animations:^{
            shadowLayer.shadowRadius = settledRadius;
            shadowLayer.shadowOpacity = settledOpacity;
            shadowLayer.shadowOffset = CGSizeMake(0, settledOffsetY);
        } completion:nil];
    }
}

- (void)updateGrabberStack {
    // 移除旧的堆叠视觉
    for (UIView *sub in self.stashGrabber.subviews) {
        if (sub.tag == 99) [sub removeFromSuperview];
    }
    
    NSMutableArray *sameSideStashedWindows = [NSMutableArray array];
    for (CV3FloatingAppWindow *win in floatingWindows) {
        if ([win isKindOfClass:[CV3FloatingAppWindow class]] && win.isStashed && win.stashedSide == self.stashedSide) {
            [sameSideStashedWindows addObject:win];
        }
    }

    NSInteger stackIndex = [sameSideStashedWindows indexOfObject:self];
    if (stackIndex == NSNotFound) stackIndex = 0;
    
    if (sameSideStashedWindows.count > 1) {
        // 建议：Prism Stacking (棱镜堆叠视觉)
        // ... (保持原有的图标堆叠视觉逻辑) ...
    }

    CGRect screen = CV3DisplayBoundsForWindow(self);
    UIEdgeInsets safeArea = [self currentSafeAreaInsets];
    CGFloat minY = safeArea.top;
    CGFloat maxY = screen.size.height - safeArea.bottom - kCV3StashIconSize;
    if (maxY < minY) maxY = minY;

    [sameSideStashedWindows sortUsingComparator:^NSComparisonResult(CV3FloatingAppWindow *a, CV3FloatingAppWindow *b) {
        CGFloat aCenterY = CGRectIsEmpty(a.preStashFrame) ? CGRectGetMidY(a.frame) : CGRectGetMidY(a.preStashFrame);
        CGFloat bCenterY = CGRectIsEmpty(b.preStashFrame) ? CGRectGetMidY(b.frame) : CGRectGetMidY(b.preStashFrame);
        if (aCenterY < bCenterY) return NSOrderedAscending;
        if (aCenterY > bCenterY) return NSOrderedDescending;
        return NSOrderedSame;
    }];

    stackIndex = [sameSideStashedWindows indexOfObject:self];
    if (stackIndex == NSNotFound) stackIndex = 0;

    // A single icon has no stacking conflict. Its frame was already clamped
    // using the same safe area when the hide transition began; recalculating it
    // after an App Switcher -> Home transition can observe a different transient
    // safe-area value and produces a second, visible position correction.
    if (sameSideStashedWindows.count <= 1) {
        [self normalizeStashedGrabberLayout];
        return;
    }

    CGFloat desiredTop = CGFLOAT_MAX;
    for (CV3FloatingAppWindow *win in sameSideStashedWindows) {
        CGFloat centerY = CGRectIsEmpty(win.preStashFrame) ? CGRectGetMidY(win.frame) : CGRectGetMidY(win.preStashFrame);
        desiredTop = MIN(desiredTop, centerY - kCV3StashIconSize * 0.5);
    }
    if (desiredTop == CGFLOAT_MAX) desiredTop = self.frame.origin.y;

    CGFloat defaultStackOffset = kCV3StashIconSize + 8.0;
    CGFloat availableHeight = MAX(0.0, maxY - minY);
    CGFloat stackOffset = defaultStackOffset;
    if (sameSideStashedWindows.count > 1) {
        CGFloat maxFittingOffset = availableHeight / (CGFloat)(sameSideStashedWindows.count - 1);
        stackOffset = MIN(defaultStackOffset, MAX(kCV3StashIconSize * 0.72, maxFittingOffset));
    }

    CGFloat stackHeight = kCV3StashIconSize + stackOffset * MAX(0, (NSInteger)sameSideStashedWindows.count - 1);
    CGFloat maxTop = screen.size.height - safeArea.bottom - stackHeight;
    if (maxTop < minY) maxTop = minY;
    CGFloat anchoredTop = MIN(MAX(desiredTop, minY), maxTop);

    CGRect currentFrame = self.frame;
    currentFrame.size = CGSizeMake(kCV3StashIconSize, kCV3StashIconSize);
    currentFrame.origin.y = MIN(MAX(anchoredTop + stackIndex * stackOffset, minY), maxY);

    [UIView animateWithDuration:0.4 delay:0 usingSpringWithDamping:0.8 initialSpringVelocity:0 options:0 animations:^{
        self.frame = currentFrame;
        [self normalizeStashedGrabberLayout];
    } completion:nil];
}
- (void)handleRestoreTap:(UITapGestureRecognizer *)gesture {
    if (gesture.state != UIGestureRecognizerStateEnded) return;
    CV3ExitExposeModeIfNeeded(self, YES);
    [self restoreFromStash];
}

- (void)restoreFromStash {
    [self dismissMultitaskingMenu];
    CV3ExitExposeModeIfNeeded(self, YES);
    // 恢复为普通 App 之上的浮窗层级，保留系统通知栏/控制中心在上方
    self.windowLevel = CV3Style.floatingApp; 
    [self makeKeyAndVisible];
    self.windowLevel = CV3Style.floatingApp;
    [self setWindowFocused:YES];

    if (self.isStashed) {
        UIImpactFeedbackGenerator *gen = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight];
        [gen impactOccurred];

        CGRect iconFrame = self.frame;
        UIView *iconProxy = [self.stashGrabber snapshotViewAfterScreenUpdates:NO];
        CGPoint preferredCenter = CGRectIsEmpty(self.preStashFrame) ? self.center : CGPointMake(CGRectGetMidX(self.preStashFrame), CGRectGetMidY(self.preStashFrame));
        CGRect targetFrame = [self restorableFramePreservingStashedSizeForOrientation:self.targetOrientation preferredCenter:preferredCenter];
        self.stashAnimationTraceID = NSUUID.UUID.UUIDString;
        self.stashAnimationTraceStartTime = CACurrentMediaTime();
        CV3LogStashAnimation(@"[StashAnimation] id=%@ direction=restore phase=begin bundle=%@ source=%@ target=%@ device_orientation=%ld content_orientation=%ld cached_snapshot=%d icon_proxy=%d",
                     self.stashAnimationTraceID,
                     self.bundleID ?: @"unknown",
                     NSStringFromCGRect(iconFrame),
                     NSStringFromCGRect(targetFrame),
                     (long)CV3TrustedInterfaceOrientation(self.windowScene),
                     (long)self.targetOrientation,
                     self.stashedRestoreSnapshotImage != nil,
                     iconProxy != nil);
        self.stashGrabber.alpha = 0.0;

        self.isStashed = NO; // 先解除 Stash 标志，以便下面 updateSettings 时能被识别为前台
        [self.hostedSession setActive:YES];
        CV3CascadeUpdateSovereigntyAssertions(); // 级联刷新所有窗口前台优先级断言

        // 核心修复：如果已有的 hostView 存在，立即加回层级中并设为可见，避免黑屏/渲染延迟
        if (self.hostView && !self.hostView.superview) {
            if (self.splashView) {
                [self.hostContainerProxy insertSubview:self.hostView belowSubview:self.splashView];
            } else {
                [self.hostContainerProxy addSubview:self.hostView];
            }
            self.hostView.hidden = NO;
            self.hostView.alpha = 1.0;
        }

        self.frame = targetFrame;
        [self enforcePortraitWindowGeometry];
        self.stashedSide = 0;
        [self syncHostedSceneLayoutForce:YES];
        [self setNeedsLayout];
        [self layoutIfNeeded];

        [self enforceSceneForegroundState]; // 立即通知 SpringBoard 将 FBScene 拉回前台
        [self attemptToHostSceneWithRetries:10 delay:0.05]; // 异步拉回渲染视图，50ms 延迟足够让 Scene 状态生效并挂载

        self.stashGrabber.alpha = 0.0;
        self.appContentWrapper.transform = CGAffineTransformIdentity;
        self.appContentWrapper.alpha = 1.0;
        self.clippingContainer.alpha = 1.0;
        self.clippingContainer.transform = CGAffineTransformIdentity;
        self.resizeHandle.alpha = 1.0;
        self.homeBarView.alpha = 1.0;

        UIView *snapshotSourceView = self.hostContainerProxy ?: self.clippingContainer ?: self.appContentWrapper;
        CGRect endFrameInWindow = [self convertRect:snapshotSourceView.bounds fromView:snapshotSourceView];
        CGRect startFrameInWindow = CGRectOffset(iconFrame, -targetFrame.origin.x, -targetFrame.origin.y);
        UIImage *genieImage = self.stashedRestoreSnapshotImage ?: [self snapshotImageForRestoreAnimation];

        self.appContentWrapper.alpha = 0.0;
        self.resizeHandle.alpha = 0.0;
        self.homeBarView.alpha = 0.0;
        [self syncWindowShadowForCurrentState];
        [self visualShadowLayer].shadowOpacity = 0.0;
        [self visualShadowLayer].shadowRadius = 0.0;
        [self visualShadowLayer].shadowOffset = CGSizeZero;
        [self visualShadowLayer].shadowPath = nil;

        if (!genieImage) {
            self.appContentWrapper.alpha = 1.0;
            self.resizeHandle.alpha = 1.0;
            self.homeBarView.alpha = 1.0;
            [self syncWindowShadowForCurrentState];
            [self animateFocusShadow:self.isFocused];
            CV3UpdateFloatingBackdrop(self.windowScene);
            for (CV3FloatingAppWindow *win in floatingWindows) {
                if (win.isStashed) [win updateGrabberStack];
            }
            CV3LogStashAnimation(@"[StashAnimation] id=%@ direction=restore phase=completion mode=fallback final=%@ elapsed_ms=%.1f",
                         self.stashAnimationTraceID,
                         NSStringFromCGRect(self.frame),
                         (CACurrentMediaTime() - self.stashAnimationTraceStartTime) * 1000.0);
            self.stashAnimationTraceID = nil;
            self.stashAnimationTraceStartTime = 0;
            return;
        }

        if (!iconProxy) {
            UIImageView *fallbackIconProxy = [[UIImageView alloc] initWithFrame:CGRectInset(startFrameInWindow, 4, 4)];
            fallbackIconProxy.image = self.appIconMiniView.image;
            fallbackIconProxy.layer.cornerRadius = CV3Style.iconCornerRadius;
            fallbackIconProxy.layer.masksToBounds = YES;
            fallbackIconProxy.contentMode = UIViewContentModeScaleAspectFill;
            fallbackIconProxy.transform = self.baseRotationTransform;
            iconProxy = fallbackIconProxy;
        } else {
            iconProxy.frame = startFrameInWindow;
            iconProxy.transform = self.baseRotationTransform;
        }
        [self addSubview:iconProxy];
        CGAffineTransform iconBaseTransform = self.baseRotationTransform;

        CGRect startIconFrameInWindow = CGRectInset(startFrameInWindow, kCV3StashIconInset, kCV3StashIconInset);
        [self animateGenieSurfaceImage:genieImage sourceFrame:endFrameInWindow iconFrame:startIconFrameInWindow presenting:YES completion:^{
            [iconProxy removeFromSuperview];
            self.appContentWrapper.alpha = 1.0;
            self.resizeHandle.alpha = 1.0;
            self.homeBarView.alpha = 1.0;
            [self syncWindowShadowForCurrentState];
            [self animateFocusShadow:self.isFocused];
            CV3UpdateFloatingBackdrop(self.windowScene);
            // 通知其他窗口更新堆叠状态
            for (CV3FloatingAppWindow *win in floatingWindows) {
                if (win.isStashed) [win updateGrabberStack];
            }
            CV3LogStashAnimation(@"[StashAnimation] id=%@ direction=restore phase=completion mode=genie final=%@ content_alpha=%.2f host_attached=%d elapsed_ms=%.1f",
                         self.stashAnimationTraceID,
                         NSStringFromCGRect(self.frame),
                         self.appContentWrapper.alpha,
                         self.hostView.superview != nil,
                         (CACurrentMediaTime() - self.stashAnimationTraceStartTime) * 1000.0);
            self.stashAnimationTraceID = nil;
            self.stashAnimationTraceStartTime = 0;
        }];

        [UIView animateKeyframesWithDuration:0.18 delay:0 options:UIViewKeyframeAnimationOptionCalculationModeCubic | UIViewAnimationOptionBeginFromCurrentState animations:^{
            [UIView addKeyframeWithRelativeStartTime:0.0 relativeDuration:0.22 animations:^{
                iconProxy.alpha = 0.0;
                iconProxy.transform = CGAffineTransformScale(iconBaseTransform, 0.86, 0.86);
            }];
        } completion:nil];
    } else {
        // 如果没有被隐藏，则执行轻微的脉冲动画提醒用户它已置顶
        [self triggerCollisionImpulse];
    }
}

- (void)handleStashLongPress:(UILongPressGestureRecognizer *)gesture {
    if (!self.isStashed) return;
    if (gesture.state == UIGestureRecognizerStateBegan) {
        CV3ExitExposeModeIfNeeded(self, NO);
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
    CGRect screen = CV3DisplayBoundsForWindow(self);
    
    if (gesture.state == UIGestureRecognizerStateBegan) {
        CV3ExitExposeModeIfNeeded(self, YES);
        [UIView animateWithDuration:0.2 animations:^{
            [self applyCurrentTransformWithScale:1.0];
            [self visualShadowLayer].shadowOpacity = 0;
            [self visualShadowLayer].shadowRadius = 0;
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
            [self visualShadowLayer].shadowOpacity = 0;
            [self visualShadowLayer].shadowRadius = 0;
            
            // 自由拖动位置：保持在安全区域内，但不强制吸附至侧边
            UIEdgeInsets safeArea = [self currentSafeAreaInsets];
            
            CGRect frame = self.frame;
            if (frame.origin.x < safeArea.left) frame.origin.x = safeArea.left;
            if (frame.origin.y < safeArea.top) frame.origin.y = safeArea.top;
            if (CGRectGetMaxX(frame) > screen.size.width - safeArea.right) frame.origin.x = screen.size.width - safeArea.right - frame.size.width;
            if (CGRectGetMaxY(frame) > screen.size.height - safeArea.bottom) frame.origin.y = screen.size.height - safeArea.bottom - frame.size.height;
            self.frame = frame;
            
            // 重要：更新 preStashFrame，确保从当前图标位置还原
            CGRect psf = self.preStashFrame;
            psf.origin.x = self.frame.origin.x + (kCV3StashIconSize * 0.5) - psf.size.width / 2.0;
            psf.origin.y = self.frame.origin.y + (kCV3StashIconSize * 0.5) - psf.size.height / 2.0;
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
    [self syncWindowBoundsToClientAndNotify:YES];
}

- (void)syncWindowBoundsToClientAndNotify:(BOOL)notify {
    if (self.bundleID) {
        CGRect contentFrame = [self visiblePortraitContentFrame];
        
        CV3WriteSharedGeometryForBundleID(self.bundleID,
                                          (float)contentFrame.size.width,
                                          (float)contentFrame.size.height,
                                          self.hidden ? 0 : 1);
        
        // 2. 仅在需要通知的静态时刻，才落盘 Plist 提供持久化记录和兼容性
        if (notify) {
            NSString *path = @"/var/mobile/Library/Preferences/com.xu.chevronv3.plist";
            NSMutableDictionary *dict = [NSMutableDictionary dictionaryWithContentsOfFile:path] ?: [NSMutableDictionary dictionary];
            
            dict[[NSString stringWithFormat:@"isHosted_%@", self.bundleID]] = @(!self.hidden);
            dict[[NSString stringWithFormat:@"currentWidth_%@", self.bundleID]] = @(contentFrame.size.width);
            dict[[NSString stringWithFormat:@"currentHeight_%@", self.bundleID]] = @(contentFrame.size.height);
            
            [dict writeToFile:path atomically:YES];
            chmod([path UTF8String], 0644);
            
            CV3LogToFile(@"宿主窗口 (%@) 最终尺寸已同步并发送 Darwin 通知: 宽度=%.1f, 高度=%.1f", self.bundleID, contentFrame.size.width, contentFrame.size.height);
            CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), (CFStringRef)@"com.xu.chevronv3/SizeChanged", NULL, NULL, YES);
        } else {
            // 节流状态下，由于共享内存已更新，在此处我们完全省去 Plist 磁盘操作
            CV3LogToFile(@"[Throttled] 仅共享内存同步（零磁盘 IO）: %@ -> 宽度=%.1f, 高度=%.1f", self.bundleID, contentFrame.size.width, contentFrame.size.height);
        }
    }
}

- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    if (self.isClosing) return nil;

    if (self.isStashed) {
        CGPoint pInGrabber = [self convertPoint:point toView:self.stashGrabber];
        if ([self.stashGrabber pointInside:pInGrabber withEvent:event]) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [self promoteFloatingWindowInZOrder];
            });
            UIView *grabberHit = [self.stashGrabber hitTest:pInGrabber withEvent:event];
            return grabberHit ?: self.stashGrabber;
        }
        return nil;
    }

    if (self.homeBarView && !self.homeBarView.hidden && self.homeBarView.alpha > 0.01) {
        CGRect homeBarFrame = CGRectInset([self convertRect:self.homeBarView.bounds fromView:self.homeBarView], -18.0, -18.0);
        if (CGRectContainsPoint(homeBarFrame, point)) {
            if (!self.isFocused) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    [self setWindowFocused:YES];
                });
            }
            CGPoint pInHomeBar = [self convertPoint:point toView:self.homeBarView];
            UIView *homeBarHit = [self.homeBarView hitTest:pInHomeBar withEvent:event];
            return homeBarHit ?: self.homeBarView;
        }
    }

    // 2. 检查侧边 Stash 区域 (仅在 Stashed 时，但此处主要处理 Active 状态)
    if (self.stashGrabber.alpha > 0.5) {
        CGPoint pInGrabber = [self convertPoint:point toView:self.stashGrabber];
        if ([self.stashGrabber pointInside:pInGrabber withEvent:event]) {
            if (!self.isFocused) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    [self setWindowFocused:YES];
                });
            }
            return self.stashGrabber;
        }
    }

    CGPoint pInRoot = [self convertPoint:point toView:self.rootTransformContainer];
    UIView *rootHit = [self.rootTransformContainer hitTest:pInRoot withEvent:event];
    if (!rootHit && ![self.rootTransformContainer pointInside:pInRoot withEvent:event]) return nil;

    if (event.type == UIEventTypeTouches) {
        // A hosted scene may consume the touch through its remote context
        // without forwarding a stable Began phase to this UIWindow. The
        // successful content hit itself is the reliable interaction signal.
        CV3LogHomeBarVisibility(@"[HomeBarTrace] phase=hitTest.content bundle=%@ hit=%@ point=%@ alpha=%.3f hidden=%d",
                                self.bundleID, NSStringFromClass(rootHit.class),
                                NSStringFromCGPoint(point), self.homeBarView.alpha,
                                self.homeBarAutoHidden);
        [self noteFloatingHomeBarInteraction];
    }

    if (!self.isFocused) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self setWindowFocused:YES];
        });
    }
    if (rootHit) return rootHit;

    UIView *hit = [super hitTest:point withEvent:event];
    return hit ?: (self.clippingContainer ?: self.rootTransformContainer ?: self);
}

- (void)sendEvent:(UIEvent *)event {
    if (event.type == UIEventTypeTouches && !self.isStashed && !self.isClosing) {
        for (UITouch *touch in event.allTouches) {
            if (touch.phase == UITouchPhaseBegan ||
                touch.phase == UITouchPhaseMoved ||
                touch.phase == UITouchPhaseStationary) {
                if (touch.phase == UITouchPhaseBegan) {
                    CV3LogHomeBarVisibility(@"[HomeBarTrace] phase=sendEvent.touchBegan bundle=%@ alpha=%.3f hidden=%d timer=%d",
                                            self.bundleID, self.homeBarView.alpha,
                                            self.homeBarAutoHidden,
                                            self.homeBarAutoHideTimer.isValid);
                }
                [self noteFloatingHomeBarInteraction];
                break;
            }
        }
    }
    [super sendEvent:event];
}

- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)gesture {
    return YES;
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldReceiveTouch:(UITouch *)touch {
    return YES;
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldBeRequiredToFailByGestureRecognizer:(UIGestureRecognizer *)otherGestureRecognizer {
    // 强制要求其他手势（即来自宿主 App 内部的手势）在我们自己的控制手势面前失败
    // 这可以防止拖拽或缩放/位移窗口时，底下的 App 还在疯狂滚动
    if (gestureRecognizer.view == self.homeBarView) {
        return NO;
    }
    return NO;
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldRequireFailureOfGestureRecognizer:(UIGestureRecognizer *)otherGestureRecognizer {
    return NO;
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)otherGestureRecognizer {
    return NO;
}

- (void)handleResizePan:(UIPanGestureRecognizer *)gesture {
    static BOOL hasTriggeredTopHaptic = NO;
    static BOOL hasTriggeredBottomHaptic = NO;
    static BOOL hasTriggeredSideHaptic = NO;

    if (gesture.state == UIGestureRecognizerStateBegan) {
        [self dismissMultitaskingMenu];
        CV3ExitExposeModeIfNeeded(self, YES);
        self.isFullscreenMode = NO;
        self.isCompactMode = NO;
        self.initialResizeFrame = self.frame;
        [gesture setTranslation:CGPointZero inView:nil];
        hasTriggeredTopHaptic = NO;
        hasTriggeredBottomHaptic = NO;
        hasTriggeredSideHaptic = NO;
        
        UIImpactFeedbackGenerator *gen = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight];
        [gen impactOccurred];

        self.isLiveResizing = YES;
        CALayer *shadowLayer = [self visualShadowLayer];
        shadowLayer.shadowPath = nil;
        shadowLayer.shouldRasterize = YES;
        shadowLayer.rasterizationScale = [UIScreen mainScreen].scale;
        [self startLiquidMotion];
        [UIView animateWithDuration:0.2 animations:^{
            shadowLayer.shadowOpacity = CV3Style.shadowOpacityUnfocused * 0.5;
            self.glassBackdrop.effect = nil;
            self.glassBackdrop.backgroundColor = [UIColor clearColor];
        }];

        if (self.hostView) {
            self.liveResizeSnapshotView = [self.hostView snapshotViewAfterScreenUpdates:NO];
            if (self.liveResizeSnapshotView) {
                self.liveResizeSnapshotView.frame = self.hostContainerProxy.bounds;
                self.liveResizeSnapshotView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
                [self.hostContainerProxy addSubview:self.liveResizeSnapshotView];
                self.hostView.alpha = 0;
            }
        }

        if (self.targetScene) {
            @try {
                FBSMutableSceneSettings *settings = [[self.targetScene settings] mutableCopy];
                if ([settings respondsToSelector:@selector(setInLiveResize:)]) {
                    [(UIMutableApplicationSceneSettings *)settings setInLiveResize:YES];
                    [self.targetScene updateSettings:settings withTransitionContext:nil];
                }
            } @catch (NSException *e) {
                CV3LogToFile(@"[Critical] Failed to set live resize state: %@", e);
            }
        }

    }
    
    CGPoint translation = [gesture translationInView:nil];
    
    if (gesture.state == UIGestureRecognizerStateChanged) {
        CGRect screenBounds = CV3DisplayBoundsForWindow(self);
        CGFloat shortSide = MIN(screenBounds.size.width, screenBounds.size.height);
        CGFloat longSide = MAX(screenBounds.size.width, screenBounds.size.height);
        CGFloat aspect = longSide / MAX(shortSide, 1.0);
        
        CGFloat minAllowedWidth = shortSide * 0.4;
        CGFloat maxAllowedWidth = shortSide * 0.75;
        
        CGPoint initialCenter = CGPointMake(CGRectGetMidX(self.initialResizeFrame), CGRectGetMidY(self.initialResizeFrame));
        CGPoint initialHandlePos = CGPointMake(CGRectGetMaxX(self.initialResizeFrame), CGRectGetMaxY(self.initialResizeFrame));
        CGPoint currentHandlePos = CGPointMake(initialHandlePos.x + translation.x, initialHandlePos.y + translation.y);
        
        CGFloat initialDist = sqrt(pow(initialHandlePos.x - initialCenter.x, 2) + pow(initialHandlePos.y - initialCenter.y, 2));
        CGFloat currentDist = sqrt(pow(currentHandlePos.x - initialCenter.x, 2) + pow(currentHandlePos.y - initialCenter.y, 2));
        
        CGFloat rawScaleFactor = initialDist > 0 ? (currentDist / initialDist) : 1.0;
        CGFloat scaleFactor = 1.0 + (rawScaleFactor - 1.0) * 1.25; 
        
        CGFloat initialLogicalWidth = self.initialResizeFrame.size.width;
        CGFloat targetWidth = initialLogicalWidth * scaleFactor;
        
        // --- [Geek Advice] Haptic Gradient Implementation ---
        static CGFloat lastHapticOvershoot = 0;
        CGFloat overshoot = 0;
        if (targetWidth < minAllowedWidth) overshoot = (minAllowedWidth - targetWidth) / (minAllowedWidth * 0.2);
        else if (targetWidth > maxAllowedWidth) overshoot = (targetWidth - maxAllowedWidth) / (maxAllowedWidth * 0.2);
        
        if (overshoot > 0.05 && fabs(overshoot - lastHapticOvershoot) > 0.1) {
            UIImpactFeedbackGenerator *gradientGen = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight];
            [gradientGen impactOccurredWithIntensity:MIN(1.0, overshoot)];
            lastHapticOvershoot = overshoot;
        } else if (overshoot <= 0.05) {
            lastHapticOvershoot = 0;
        }

        // Use copy to avoid mutation during enumeration
        NSArray *windowsSnapshot = [floatingWindows copy];
        for (CV3FloatingAppWindow *other in windowsSnapshot) {
            if (other == self || other.isStashed || ![other isKindOfClass:[CV3FloatingAppWindow class]]) continue;
            
            CGFloat distance = sqrt(pow(self.center.x - other.center.x, 2) + pow(self.center.y - other.center.y, 2));
            CGFloat minGap = (self.bounds.size.width + other.bounds.size.width) / 2.0 + 20.0;
            
            if (distance < minGap) {
                targetWidth *= (0.8 + 0.2 * (distance / minGap));
            }
        }

        CGFloat finalWidth = targetWidth;
        if (targetWidth < minAllowedWidth) {
            finalWidth = minAllowedWidth - (minAllowedWidth - targetWidth) * 0.3;
        } else if (targetWidth > maxAllowedWidth) {
            finalWidth = maxAllowedWidth + (targetWidth - maxAllowedWidth) * 0.3;
        }
        
        CGFloat finalHeight = finalWidth * aspect;
        CGFloat outerWidth = finalWidth;
        CGFloat outerHeight = finalHeight;
        
        CGRect newFrame;
        newFrame.size = CGSizeMake(outerWidth, outerHeight);
        newFrame.origin.x = initialCenter.x - outerWidth / 2.0;
        newFrame.origin.y = initialCenter.y - outerHeight / 2.0;
        
        UIEdgeInsets safeArea = [self currentSafeAreaInsets];
        
        if (newFrame.origin.y < safeArea.top && !hasTriggeredTopHaptic) {
            [[[UISelectionFeedbackGenerator alloc] init] selectionChanged];
            hasTriggeredTopHaptic = YES;
        } else if (newFrame.origin.y >= safeArea.top) {
            hasTriggeredTopHaptic = NO;
        }

        if (CGRectGetMaxY(newFrame) > screenBounds.size.height - safeArea.bottom && !hasTriggeredBottomHaptic) {
            [[[UISelectionFeedbackGenerator alloc] init] selectionChanged];
            hasTriggeredBottomHaptic = YES;
        } else if (CGRectGetMaxY(newFrame) <= screenBounds.size.height - safeArea.bottom) {
            hasTriggeredBottomHaptic = NO;
        }

        BOOL hitSide = (newFrame.origin.x < safeArea.left || CGRectGetMaxX(newFrame) > screenBounds.size.width - safeArea.right);
        if (hitSide && !hasTriggeredSideHaptic) {
            [[[UISelectionFeedbackGenerator alloc] init] selectionChanged];
            hasTriggeredSideHaptic = YES;
        } else if (!hitSide) {
            hasTriggeredSideHaptic = NO;
        }
            
        [CATransaction begin];
        [CATransaction setDisableActions:YES];
        
        self.bounds = CGRectMake(0, 0, outerWidth, outerHeight);
        self.center = CGPointMake(CGRectGetMidX(newFrame), CGRectGetMidY(newFrame));
        [CATransaction commit];
        
        // 拖动期间：仅同步 Plist 数据，节流静默 Darwin 广播通知
        [self syncWindowBoundsToClientAndNotify:NO];
    }
    
    if (gesture.state == UIGestureRecognizerStateEnded || 
        gesture.state == UIGestureRecognizerStateCancelled || 
        gesture.state == UIGestureRecognizerStateFailed) {
        
        [self stopLiquidMotion];
        
        [self visualShadowLayer].shouldRasterize = NO;
        
        if (gesture.state != UIGestureRecognizerStateEnded) {
            self.isLiveResizing = NO;
            CGFloat minEdge = MIN(self.bounds.size.width, self.bounds.size.height);
            CGFloat finalRadius = MAX(CV3Style.adaptiveCornerRadiusMin, MIN(CV3Style.adaptiveCornerRadiusMax, minEdge * CV3Style.adaptiveCornerRadiusRatio));
            [self visualShadowLayer].shadowPath = [UIBezierPath bezierPathWithRoundedRect:[self currentVisualShadowFrame] cornerRadius:finalRadius].CGPath;
            [self animateFocusShadow:self.isFocused];
            
            [UIView animateWithDuration:0.4 delay:0 options:UIViewAnimationOptionCurveEaseInOut animations:^{
                self.glassBackdrop.effect = nil;
                self.glassBackdrop.backgroundColor = [UIColor clearColor];
            } completion:nil];
        }
        
        CGRect screenBounds = CV3DisplayBoundsForWindow(self);
        CGFloat shortSide = MIN(screenBounds.size.width, screenBounds.size.height);
        CGFloat longSide = MAX(screenBounds.size.width, screenBounds.size.height);
        CGFloat aspect = longSide / MAX(shortSide, 1.0);
        CGPoint initialCenter = CGPointMake(CGRectGetMidX(self.frame), CGRectGetMidY(self.frame));

        UIEdgeInsets safeArea = [self currentSafeAreaInsets];

        // --- [Geek Advice] Asynchronous Frame Pipelining ---
        // Step 1: Immediately update scene settings to final frame and release live resize lock
        if (self.targetScene) {
            @try {
                FBSMutableSceneSettings *settings = [[self.targetScene settings] mutableCopy];
                if ([settings respondsToSelector:@selector(setInLiveResize:)]) {
                    [(UIMutableApplicationSceneSettings *)settings setInLiveResize:NO];
                    [self.targetScene updateSettings:settings withTransitionContext:nil];
                }
                
                // Force an immediate layout update for the new size
                [self setNeedsLayout];
                [self layoutIfNeeded]; 
                
                CV3LogToFile(@"[Pipelining] 已提交最终场景布局请求: %@", self.bundleID);
            } @catch (NSException *e) {}
        }

        // Cleanup visuals with staged fade
        UIView *snapshot = self.liveResizeSnapshotView;
        self.liveResizeSnapshotView = nil; // Clear state immediately to allow layoutSubviews to update the final scene frame

        // Step 2: Delay the transition slightly to give the remote process time to render its first frame at the new size
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.15 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [UIView animateWithDuration:0.4 delay:0 options:UIViewAnimationOptionCurveEaseInOut animations:^{
                self.hostView.alpha = 1.0;
                if (snapshot) snapshot.alpha = 0;
            } completion:^(BOOL finished) {
                [snapshot removeFromSuperview];
            }];
        });

        // Snapping and constraints for Ended state
        if (gesture.state == UIGestureRecognizerStateEnded) {
            CGFloat finalWidth = self.bounds.size.width;
            
            // 惯性滑行动量优化
            CGPoint gestureVel = [gesture velocityInView:nil];
            CGFloat speed = sqrt(gestureVel.x * gestureVel.x + gestureVel.y * gestureVel.y);
            CGFloat widthMomentum = 0;
            if (speed > 300.0) {
                // 计算对角线上的滑动速度分量
                CGFloat diagVelocity = (gestureVel.x + gestureVel.y) / sqrt(2.0);
                // 3000px/s 的速度映射为 45pt 的尺寸滑行动量
                widthMomentum = diagVelocity * 0.015;
            }
            finalWidth += widthMomentum;

            // 限制惯性后的宽度范围，避免拉伸越界
            CGFloat minAllowedWidth = shortSide * 0.4;
            CGFloat maxAllowedWidth = shortSide * 0.75;
            if (finalWidth < minAllowedWidth) finalWidth = minAllowedWidth;
            if (finalWidth > maxAllowedWidth) finalWidth = maxAllowedWidth;

            CGFloat previousLogicalWidth = finalWidth;
            
            // Island Snapping
            CGRect snapFrame = self.frame;
            CGFloat snapThreshold = 25.0;
            if (fabs(snapFrame.origin.y - safeArea.top) < snapThreshold) {
                snapFrame.origin.y = safeArea.top;
                [[[UISelectionFeedbackGenerator alloc] init] selectionChanged];
            }

            // Ratio Snapping
            CGFloat currentRatio = finalWidth / shortSide;
            if (fabs(currentRatio - 0.5) < 0.03) finalWidth = shortSide * 0.5;
            else if (fabs(currentRatio - 0.75) < 0.03) finalWidth = shortSide * 0.75;

            CGFloat finalHeight = finalWidth * aspect;
            CGFloat outerWidth = finalWidth;
            CGFloat outerHeight = finalHeight;
            snapFrame.size = CGSizeMake(outerWidth, outerHeight);
            
            // Re-center if ratio snapped
            if (fabs(finalWidth - previousLogicalWidth) > 0.1) {
                snapFrame.origin.x = initialCenter.x - outerWidth / 2.0;
                snapFrame.origin.y = initialCenter.y - outerHeight / 2.0;
                [[[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium] impactOccurred];
            }

            // Safety clamp with breath padding to enforce Safe Area Constraint
            CGFloat breath = CV3Style.safeAreaBreath;
            if (snapFrame.origin.x < safeArea.left + breath) snapFrame.origin.x = safeArea.left + breath;
            if (snapFrame.origin.y < safeArea.top + breath) snapFrame.origin.y = safeArea.top + breath;
            if (CGRectGetMaxX(snapFrame) > screenBounds.size.width - safeArea.right - breath) 
                snapFrame.origin.x = screenBounds.size.width - safeArea.right - breath - outerWidth;
            if (CGRectGetMaxY(snapFrame) > screenBounds.size.height - safeArea.bottom - breath) 
                snapFrame.origin.y = screenBounds.size.height - safeArea.bottom - breath - outerHeight;

            // Final bounce animation with dynamic spring velocity matching gesture release speed
            CGFloat springVelocity = MIN(4.0, MAX(0.5, speed / 800.0));
            [UIView animateWithDuration:0.5 delay:0 usingSpringWithDamping:0.75 initialSpringVelocity:springVelocity options:0 animations:^{
                self.bounds = CGRectMake(0, 0, snapFrame.size.width, snapFrame.size.height);
                self.center = CGPointMake(CGRectGetMidX(snapFrame), CGRectGetMidY(snapFrame));
            } completion:^(BOOL finished) {
                self.isLiveResizing = NO;
                CGFloat minEdge = MIN(self.bounds.size.width, self.bounds.size.height);
                CGFloat finalRadius = MAX(CV3Style.adaptiveCornerRadiusMin, MIN(CV3Style.adaptiveCornerRadiusMax, minEdge * CV3Style.adaptiveCornerRadiusRatio));
                [self visualShadowLayer].shadowPath = [UIBezierPath bezierPathWithRoundedRect:[self currentVisualShadowFrame] cornerRadius:finalRadius].CGPath;
                
                [UIView animateWithDuration:0.4 delay:0 options:UIViewAnimationOptionCurveEaseInOut animations:^{
                    self.glassBackdrop.effect = nil;
                    self.glassBackdrop.backgroundColor = [UIColor clearColor];
                } completion:nil];

                // 动画静止后，发出一次最终的 Darwin 通知，通知客户端刷新其 UI
                [self syncWindowBoundsToClientAndNotify:YES];
                CV3SaveWindowLayout(self);
            }];
            
            [self animateFocusShadow:self.isFocused];
        }
    }
}

- (void)handleTransitionGhosting {
    if (self.isClosing || !self.hostView) return;
    
    UIView *ghostShield = [self.hostView snapshotViewAfterScreenUpdates:NO];
    if (ghostShield) {
        ghostShield.frame = self.hostContainerProxy.bounds;
        [self.hostContainerProxy addSubview:ghostShield];
        
        self.hostView.alpha = 0;
        [self refreshHostViewPresentation];
        
        [UIView animateWithDuration:0.25 delay:0.05 options:UIViewAnimationOptionCurveEaseOut animations:^{
            ghostShield.alpha = 0;
            self.hostView.alpha = 1.0;
        } completion:^(BOOL finished) {
            [ghostShield removeFromSuperview];
        }];
    }
}

- (void)closeWindow {
    if (self.isClosing) return;
    CV3ExitExposeModeIfNeeded(self, NO);
    self.isClosing = YES;
    self.sceneHostGeneration += 1;
    [self setHostLifecycleState:CV3HostLifecycleStateReleasing reason:@"WindowClosing"];
    [self.hostedSession invalidate];
    
    if (self.assertionWatchdogTimer) {
        [self.assertionWatchdogTimer invalidate];
        self.assertionWatchdogTimer = nil;
    }
    [self.receptionTraceTimer invalidate];
    self.receptionTraceTimer = nil;
    [self.homeBarAutoHideTimer invalidate];
    self.homeBarAutoHideTimer = nil;
    [self.homeBarVisibilityAnimator stopAnimation:YES];
    self.homeBarVisibilityAnimator = nil;
    
    CV3LogToFile(@"[Lifecycle] 正在关闭窗口(默认仅分离宿主，不强杀应用): %@", self.bundleID);
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    self.hidden = YES;
    [self syncWindowBoundsToClient];
    if (self.rbsAssertion) {
        [self.rbsAssertion invalidate];
        self.rbsAssertion = nil;
        CV3LogToFile(@"[Immortality] 已释放 %@ 的前台优先级断连", self.bundleID);
    }

    if (self.hostView || self.crossOrientationMapApplied) {
        // [New] Reset Scene Settings to Background before destroying
        BOOL sceneValid = self.targetScene && CV3InvokeBool(self.targetScene, @selector(isValid), YES);
        if (sceneValid) {
            @try {
                FBSMutableSceneSettings *settings = [[self.targetScene settings] mutableCopy];
                if ([settings respondsToSelector:@selector(setForeground:)]) [settings setForeground:NO];
                if ([settings respondsToSelector:@selector(setBackgrounded:)]) [settings setBackgrounded:YES];
                if (self.crossOrientationMapApplied) {
                    CV3RestoreCrossOrientationMapOnSettings(settings,
                                                            self.originalOrientationMapResolver,
                                                            self.originalInterfaceOrientationMode,
                                                            self.hasOriginalInterfaceOrientationMode);
                    self.originalOrientationMapResolver = nil;
                    self.activeOrientationMapResolver = nil;
                    self.hasOriginalInterfaceOrientationMode = NO;
                    self.hasCapturedOrientationMapBaseline = NO;
                    self.crossOrientationMapApplied = NO;
                }
                [self.targetScene updateSettings:settings withTransitionContext:nil];
                CV3LogToFile(@"[Aggressive] 已将 Scene 设置为后台状态: %@", self.bundleID);
            } @catch (NSException *e) {
                CV3LogToFile(@"[Error] Reset scene settings failed: %@", e);
            }
        } else if (self.targetScene) {
            CV3LogToFile(@"[Lifecycle] 跳过失效 Scene 的后台设置更新: %@", self.bundleID);
        }
    }
    [self detachHostedSceneForReason:@"WindowClosing" clearScene:YES];
    if (self.allowProcessTerminationOnClose) {
        CV3LogToFile(@"[Warning] allowProcessTerminationOnClose 已启用，但当前默认关闭路径不执行 kill: %@", self.bundleID);
    }
    
    self.windowScene = nil; // Clear scene attachment
    [floatingWindows removeObject:self];
    [[NSNotificationCenter defaultCenter] postNotificationName:CV3FloatingWindowsDidChangeNotification object:nil];

    // 如果没有剩下活跃的分屏窗口，且 Expose 模式处于开启状态，自动退出 Expose 模式
    if (isGlobalExposeActive) {
        if (CV3ExpandedWindowsForExpose().count < 2) {
            CV3ToggleExposeMode();
        }
    }

    CV3CascadeUpdateSovereigntyAssertions(); // 级联刷新剩下的窗口前台优先级断言
    CV3UpdateFloatingBackdrop(nil);
    
    // [SHM Lazy Unmapping] 释放当前窗口对 SHM 的引用计数，若归零则60秒后回收
    CV3ReleaseSharedGeometry(self.bundleID);
}

- (void)assertionWatchdogTick:(NSTimer *)timer {
    if (self.isClosing) return;
    
    // 低电量模式：放宽保活强度，节省后台唤醒开销
    BOOL isLowPower = [NSProcessInfo processInfo].isLowPowerModeEnabled;

    if (self.isStashed) {
        // Stash + 低电量 -> 允许完全挂起，无需断言刷新
        if (isLowPower) return;
    }
    if (self.hidden) return;
    
    // State changes perform immediate updates. Matching assertions return immediately;
    // this call only fills a missing assertion or retries a failed priority change.
    @try {
        [self updateSovereigntyAssertion];
    } @catch (NSException *e) {}

    NSTimeInterval targetInterval = isLowPower ? 30.0 : 15.0;
    if (fabs(timer.timeInterval - targetInterval) > 0.1) {
        [self.assertionWatchdogTimer invalidate];
        self.assertionWatchdogTimer = [NSTimer scheduledTimerWithTimeInterval:targetInterval
                                                                       target:self
                                                                     selector:@selector(assertionWatchdogTick:)
                                                                     userInfo:nil
                                                                      repeats:YES];
    }
}

- (void)dealloc {
    CV3LogToFile(@"[Lifecycle] CV3FloatingAppWindow Dealloc: %@", self.bundleID);
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [[UIDevice currentDevice] endGeneratingDeviceOrientationNotifications];
    [self.receptionTraceTimer invalidate];
    self.receptionTraceTimer = nil;
    [self.homeBarAutoHideTimer invalidate];
    self.homeBarAutoHideTimer = nil;
    [self.homeBarVisibilityAnimator stopAnimation:YES];
    self.homeBarVisibilityAnimator = nil;
    
    [self stopLiquidMotion];
    
    if (self.assertionWatchdogTimer) {
        [self.assertionWatchdogTimer invalidate];
        self.assertionWatchdogTimer = nil;
    }
    
    if (self.rbsAssertion) {
        [self.rbsAssertion invalidate];
        self.rbsAssertion = nil;
    }
    if ([self.hostView respondsToSelector:@selector(invalidate)]) {
        CV3InvokeObject(self.hostView, @selector(invalidate));
    }
}

+ (CMMotionManager *)sharedMotionManager {
    static CMMotionManager *sharedMotionManager = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedMotionManager = [[CMMotionManager alloc] init];
        sharedMotionManager.deviceMotionUpdateInterval = 1.0 / 120.0;
    });
    return sharedMotionManager;
}

- (void)startLiquidMotion {
    CMMotionManager *mgr = [[self class] sharedMotionManager];
    if (!mgr.isDeviceMotionAvailable) return;
    
    self.hasCapturedBaseline = NO;
    [mgr startDeviceMotionUpdates];
    if (self.liquidDisplayLink) {
        [self.liquidDisplayLink invalidate];
    }
    self.liquidDisplayLink = [CADisplayLink displayLinkWithTarget:self selector:@selector(updateLiquidMotion:)];
    [self.liquidDisplayLink addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
}

- (void)updateLiquidMotion:(CADisplayLink *)sender {
    CMMotionManager *mgr = [[self class] sharedMotionManager];
    CMDeviceMotion *m = mgr.deviceMotion;
    if (!m) return;
    
    if (!self.hasCapturedBaseline) {
        self.baseRoll = m.attitude.roll;
        self.basePitch = m.attitude.pitch;
        self.hasCapturedBaseline = YES;
    }
    
    CGFloat deltaRoll = m.attitude.roll - self.baseRoll;
    CGFloat deltaPitch = m.attitude.pitch - self.basePitch;
    
    CGFloat tilt = sqrt(deltaRoll * deltaRoll + deltaPitch * deltaPitch);
    CGFloat dynamicBorderWidth = MIN(0.8, 0.3 + tilt * 0.5);
    
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    // 1. 镜面高光流动
    self.specularHighlight.startPoint = CGPointMake(0.0 - deltaRoll * 1.5, 0.0 - deltaPitch * 1.5);
    self.specularHighlight.endPoint = CGPointMake(1.0 - deltaRoll * 1.5, 1.0 - deltaPitch * 1.5);
    
    // 2. 青红分光折射与厚度动态色散
    CGFloat dx = deltaRoll * 1.2;
    CGFloat dy = deltaPitch * 1.2;
    self.cyanLayer.transform = CATransform3DMakeTranslation(-dx, -dy, 0);
    self.magentaLayer.transform = CATransform3DMakeTranslation(dx, dy, 0);
    
    self.cyanLayer.borderWidth = dynamicBorderWidth;
    self.magentaLayer.borderWidth = dynamicBorderWidth;
    [CATransaction commit];
}

- (void)stopLiquidMotion {
    if (self.liquidDisplayLink) {
        [self.liquidDisplayLink invalidate];
        self.liquidDisplayLink = nil;
    }
    
    BOOL anyActive = NO;
    if (floatingWindows) {
        for (CV3FloatingAppWindow *win in floatingWindows) {
            if (win != self && [win isKindOfClass:[CV3FloatingAppWindow class]] && win.liquidDisplayLink) {
                anyActive = YES;
                break;
            }
        }
    }
    if (!anyActive) {
        [[[self class] sharedMotionManager] stopDeviceMotionUpdates];
    }
}

@end
