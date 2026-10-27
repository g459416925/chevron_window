static NSInteger CV3GetTimePriorityForCategory(NSString *cat);

static NSString *CV3CurrentWorkspaceBundleID(void) {
    @try {
        id workspace = [CV3ClassNamed(@"SBMainWorkspace") sharedInstance];
        id activeItem = CV3InvokeObject(workspace, @selector(activeDisplayItem));
        NSString *bundleID = CV3BundleIdentifierFromWorkspaceObject(activeItem);
        if (bundleID.length > 0) return bundleID;
    } @catch (NSException *e) {}
    return nil;
}

static BOOL CV3WorkspaceObjectMatchesBundleID(id object, NSString *bundleID) {
    if (!object || bundleID.length == 0) return NO;

    NSString *activeBundleID = CV3BundleIdentifierFromWorkspaceObject(object);
    if ([activeBundleID isEqualToString:bundleID]) return YES;
    if (CV3IdentifierContainsExactBundleID(activeBundleID, bundleID)) return YES;

    @try {
        NSString *description = [object description];
        if (CV3IdentifierContainsExactBundleID(description, bundleID)) return YES;
    } @catch (NSException *e) {}

    return NO;
}

static NSString *CV3BundleIDFromCandidateObject(id object) {
    if (!object) return nil;

    if ([object isKindOfClass:[NSString class]]) {
        NSString *string = (NSString *)object;
        return [string containsString:@"."] ? string : nil;
    }

    if ([object isKindOfClass:[NSArray class]] || [object isKindOfClass:[NSSet class]]) {
        for (id child in object) {
            NSString *bundleID = CV3BundleIDFromCandidateObject(child);
            if (bundleID.length > 0) return bundleID;
        }
        return nil;
    }

    NSString *bundleID = CV3BundleIdentifierFromWorkspaceObject(object);
    if (bundleID.length > 0) return bundleID;

    NSArray<NSString *> *extraSelectors = @[
        @"leafIdentifier",
        @"applicationIdentifier",
        @"applicationBundleID",
        @"displayIdentifier",
        @"bundleIdentifierForDisplay"
    ];

    for (NSString *selectorName in extraSelectors) {
        NSString *value = CV3InvokeObject(object, NSSelectorFromString(selectorName));
        if ([value isKindOfClass:[NSString class]] && value.length > 0) return value;
    }

    return nil;
}

static BOOL CV3SceneSettingsLookForeground(id settings) {
    if (!settings) return NO;

    if (CV3InvokeBool(settings, @selector(foreground), NO)) return YES;
    return !CV3InvokeBool(settings, @selector(backgrounded), YES);
}

static NSMutableSet<NSString *> *CV3ObservedForegroundSceneIdentifiers = nil;
static NSMutableSet<NSString *> *CV3ObservedForegroundBundleIDs = nil;
static NSString *CV3LastObservedForegroundSceneIdentifier = nil;
static NSString *CV3LastObservedForegroundBundleID = nil;
static NSString *CV3LastObservedActiveSceneIdentifier = nil;
static NSString *CV3LastDynamicFrontmostBundleID = nil;
static NSString *CV3LastDynamicFrontmostSource = nil;
static NSMutableDictionary<NSString *, NSNumber *> *CV3PanelStateLastDebugLogTimes = nil;

static NSString *CV3ShortDebugString(id object, NSUInteger maxLength) {
    NSString *string = nil;
    @try {
        string = [object description];
    } @catch (NSException *e) {}

    if (string.length == 0) return @"nil";
    if (string.length <= maxLength) return string;
    return [[string substringToIndex:maxLength] stringByAppendingString:@"…"];
}

static NSString *CV3TryFrontmostSelector(id target, NSString *selectorName, NSString *sourcePrefix) {
    if (!target || selectorName.length == 0) return nil;

    SEL selector = NSSelectorFromString(selectorName);
    if (![target respondsToSelector:selector]) return nil;

    id value = CV3InvokeObject(target, selector);
    NSString *bundleID = CV3BundleIDFromCandidateObject(value);
    if (bundleID.length > 0) {
        CV3LastDynamicFrontmostBundleID = bundleID;
        CV3LastDynamicFrontmostSource = [NSString stringWithFormat:@"%@.%@", sourcePrefix ?: NSStringFromClass([target class]), selectorName];
        return bundleID;
    }

    return nil;
}

static NSString *CV3DynamicFrontmostBundleID(void) {
    NSArray<NSString *> *selectors = @[
        @"frontmostApplication",
        @"foregroundApplication",
        @"activeApplication",
        @"displayedApplication",
        @"applicationCurrentlyDisplayed",
        @"_accessibilityFrontMostApplication",
        @"frontMostApp",
        @"topApplication",
        @"activeDisplayItem",
        @"activeDisplayItems"
    ];

    NSArray<NSDictionary *> *targets = @[
        @{@"class": @"SBMainWorkspace", @"shared": @"sharedInstance"},
        @{@"class": @"SBApplicationController", @"shared": @"sharedInstance"},
        @{@"class": @"SBUIController", @"shared": @"sharedInstance"},
        @{@"class": @"SBWorkspaceController", @"shared": @"sharedInstance"}
    ];

    for (NSDictionary *targetInfo in targets) {
        id target = CV3InvokeObject(CV3ClassNamed(targetInfo[@"class"]), NSSelectorFromString(targetInfo[@"shared"]));
        for (NSString *selectorName in selectors) {
            NSString *bundleID = CV3TryFrontmostSelector(target, selectorName, targetInfo[@"class"]);
            if (bundleID.length > 0) return bundleID;
        }
    }

    id springBoard = [UIApplication sharedApplication];
    for (NSString *selectorName in selectors) {
        NSString *bundleID = CV3TryFrontmostSelector(springBoard, selectorName, @"SpringBoard");
        if (bundleID.length > 0) return bundleID;
    }

    CV3LastDynamicFrontmostBundleID = nil;
    CV3LastDynamicFrontmostSource = nil;
    return nil;
}

static void CV3RecordApplicationForegroundState(NSString *bundleID, BOOL foreground) {
    if (bundleID.length == 0) return;

    if (!CV3ObservedForegroundBundleIDs) {
        CV3ObservedForegroundBundleIDs = [NSMutableSet set];
    }

    if (foreground) {
        [CV3ObservedForegroundBundleIDs addObject:bundleID];
        CV3LastObservedForegroundBundleID = bundleID;
        if (sharedWindow && sharedWindow.isPanelShowing) {
            CV3LogToFile(@"[Warning][PanelStateRecord] SBApplication foreground bundle=%@", bundleID);
        }
    } else {
        [CV3ObservedForegroundBundleIDs removeObject:bundleID];
        if ([CV3LastObservedForegroundBundleID isEqualToString:bundleID]) {
            CV3LastObservedForegroundBundleID = nil;
        }
    }
}

static void CV3RecordSceneForegroundState(FBScene *scene, id settings, NSString *reason) {
    if (!scene || !settings) return;

    NSString *identifier = nil;
    @try {
        identifier = scene.identifier;
    } @catch (NSException *e) {}
    if (identifier.length == 0) return;

    if (!CV3ObservedForegroundSceneIdentifiers) {
        CV3ObservedForegroundSceneIdentifiers = [NSMutableSet set];
    }

    if (CV3SceneSettingsLookForeground(settings)) {
        [CV3ObservedForegroundSceneIdentifiers addObject:identifier];
        CV3LastObservedForegroundSceneIdentifier = identifier;
        if (sharedWindow && sharedWindow.isPanelShowing) {
            CV3LogToFile(@"[Warning][PanelStateRecord] FBScene foreground id=%@ reason=%@", identifier, reason ?: @"Unknown");
        }
    } else {
        [CV3ObservedForegroundSceneIdentifiers removeObject:identifier];
        if ([CV3LastObservedForegroundSceneIdentifier isEqualToString:identifier]) {
            CV3LastObservedForegroundSceneIdentifier = nil;
        }
    }
}

static BOOL CV3SceneIdentifierBelongsToFloatingWindow(NSString *identifier) {
    if (identifier.length == 0 || !floatingWindows) return NO;

    for (CV3FloatingAppWindow *win in [floatingWindows copy]) {
        if (![win isKindOfClass:[CV3FloatingAppWindow class]] || win.isClosing) continue;
        if (CV3IdentifierContainsExactBundleID(identifier, win.bundleID)) return YES;
    }

    return NO;
}

static void CV3RecordSceneContentState(FBScene *scene, NSInteger contentState, NSString *reason) {
    NSString *identifier = nil;
    @try {
        identifier = scene.identifier;
    } @catch (NSException *e) {}
    if (identifier.length == 0) return;

    if (CV3SceneIdentifierBelongsToFloatingWindow(identifier)) return;

    // contentState 2 is the stable Ready/active state on the versions this tweak targets.
    if (contentState == 2) {
        CV3LastObservedActiveSceneIdentifier = identifier;
        if (sharedWindow && sharedWindow.isPanelShowing) {
            CV3LogToFile(@"[Warning][PanelStateRecord] FBScene activeContent id=%@ reason=%@", identifier, reason ?: @"Unknown");
        }
    }
}

static BOOL CV3ObservedForegroundMatchesBundleID(NSString *bundleID) {
    if (bundleID.length == 0) return NO;

    if (CV3IdentifierContainsExactBundleID(CV3LastObservedActiveSceneIdentifier, bundleID)) return YES;

    if ([CV3LastObservedForegroundBundleID isEqualToString:bundleID]) return YES;
    if ([CV3ObservedForegroundBundleIDs containsObject:bundleID]) return YES;

    if (CV3IdentifierContainsExactBundleID(CV3LastObservedForegroundSceneIdentifier, bundleID)) return YES;

    for (NSString *identifier in [CV3ObservedForegroundSceneIdentifiers copy]) {
        if (CV3IdentifierContainsExactBundleID(identifier, bundleID)) return YES;
    }

    return NO;
}

static BOOL CV3ApplicationHasLiveScene(NSString *bundleID) {
    if (bundleID.length == 0) return NO;
    if (!CV3IdentifierContainsExactBundleID(CV3LastObservedActiveSceneIdentifier, bundleID)) return NO;

    @try {
        SBApplication *app = [[CV3ClassNamed(@"SBApplicationController") sharedInstance] applicationWithBundleIdentifier:bundleID];
        if (app && [app respondsToSelector:@selector(mainScene)]) {
            FBScene *scene = [app mainScene];
            if (scene && CV3IdentifierContainsExactBundleID(scene.identifier, bundleID)) return YES;
        }
    } @catch (NSException *e) {}

    @try {
        id manager = [CV3ClassNamed(@"FBSceneManager") sharedInstance];
        id workspace = [manager valueForKey:@"_workspace"];
        NSDictionary *scenes = [workspace valueForKey:@"_allScenesByID"];

        for (id key in scenes) {
            FBScene *scene = scenes[key];
            NSString *keyString = [key isKindOfClass:[NSString class]] ? key : [key description];
            NSString *sceneID = nil;
            @try {
                sceneID = scene.identifier;
            } @catch (NSException *e) {}

            if (CV3IdentifierContainsExactBundleID(keyString, bundleID) || CV3IdentifierContainsExactBundleID(sceneID, bundleID)) {
                return YES;
            }
        }
    } @catch (NSException *e) {}

    return NO;
}

static void CV3LogPanelStateDebugForBundleID(NSString *bundleID, CV3AppPanelProtectionState resolvedState, NSString *source) {
    if (bundleID.length == 0 || !sharedWindow || !sharedWindow.isPanelShowing) return;
    // 纯诊断：日志关着时不要白算工作区枚举（本函数每秒会被可见 Cell 各调一次）。
    if (!CV3DiagnosticLoggingEnabled()) return;

    NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
    if (!CV3PanelStateLastDebugLogTimes) {
        CV3PanelStateLastDebugLogTimes = [NSMutableDictionary dictionary];
    }

    NSString *logKey = [NSString stringWithFormat:@"%@:%@", source ?: @"Unknown", bundleID];
    NSTimeInterval last = [CV3PanelStateLastDebugLogTimes[logKey] doubleValue];
    if (now - last < 2.0) return;
    CV3PanelStateLastDebugLogTimes[logKey] = @(now);

    NSString *currentActive = CV3CurrentWorkspaceBundleID();
    NSString *activeItemClass = @"nil";
    NSString *activeItemParsed = @"nil";
    NSString *activeItemDesc = @"nil";
    NSUInteger activeItemsCount = 0;
    BOOL activeItemsMatched = NO;

    @try {
        id workspace = [CV3ClassNamed(@"SBMainWorkspace") sharedInstance];
        id activeItem = CV3InvokeObject(workspace, @selector(activeDisplayItem));
        activeItemClass = activeItem ? NSStringFromClass([activeItem class]) : @"nil";
        activeItemParsed = CV3BundleIdentifierFromWorkspaceObject(activeItem) ?: @"nil";
        activeItemDesc = CV3ShortDebugString(activeItem, 220);

        NSSet *activeItems = CV3InvokeObject(workspace, @selector(activeDisplayItems));
        activeItemsCount = activeItems.count;
        for (id item in activeItems) {
            if (CV3WorkspaceObjectMatchesBundleID(item, bundleID)) {
                activeItemsMatched = YES;
                break;
            }
        }
    } @catch (NSException *e) {}

    BOOL observedBundleExact = [CV3ObservedForegroundBundleIDs containsObject:bundleID];
    BOOL observedSceneMatch = CV3ObservedForegroundMatchesBundleID(bundleID);
    NSString *lastObservedBundle = CV3LastObservedForegroundBundleID ?: @"nil";
    NSString *lastObservedScene = CV3LastObservedForegroundSceneIdentifier ?: @"nil";
    NSString *lastActiveScene = CV3LastObservedActiveSceneIdentifier ?: @"nil";
    NSString *dynamicFrontmost = CV3DynamicFrontmostBundleID() ?: @"nil";
    NSString *dynamicFrontmostSource = CV3LastDynamicFrontmostSource ?: @"nil";

    BOOL appExists = NO;
    BOOL appBackgrounded = YES;
    BOOL appSuspended = NO;
    NSString *mainSceneID = @"nil";
    BOOL mainSceneForeground = NO;
    BOOL mainSceneSettingsForeground = NO;
    BOOL mainSceneSettingsBackgrounded = YES;

    @try {
        SBApplication *app = [[CV3ClassNamed(@"SBApplicationController") sharedInstance] applicationWithBundleIdentifier:bundleID];
        appExists = (app != nil);
        if (app) {
            appBackgrounded = CV3InvokeBool(app, @selector(isBackgrounded), YES);
            appSuspended = CV3InvokeBool(app, @selector(isSuspended), NO);
            FBScene *scene = nil;
            if ([app respondsToSelector:@selector(mainScene)]) {
                scene = [app mainScene];
            }
            if (scene) {
                mainSceneID = scene.identifier ?: @"nil";
                mainSceneSettingsForeground = CV3InvokeBool(scene.settings, @selector(foreground), NO);
                mainSceneSettingsBackgrounded = CV3InvokeBool(scene.settings, @selector(backgrounded), YES);
                mainSceneForeground = CV3SceneSettingsLookForeground(scene.settings);
            }
        }
    } @catch (NSException *e) {}

    NSUInteger fbSceneCount = 0;
    BOOL fbSceneMatched = NO;
    NSString *matchedFBSceneID = @"nil";
    BOOL matchedFBSceneForeground = NO;
    BOOL matchedFBSceneSettingsForeground = NO;
    BOOL matchedFBSceneSettingsBackgrounded = YES;

    @try {
        id manager = [CV3ClassNamed(@"FBSceneManager") sharedInstance];
        id workspace = [manager valueForKey:@"_workspace"];
        NSDictionary *scenes = [workspace valueForKey:@"_allScenesByID"];
        fbSceneCount = scenes.count;

        for (id key in scenes) {
            FBScene *scene = scenes[key];
            NSString *keyString = [key isKindOfClass:[NSString class]] ? key : [key description];
            NSString *sceneID = nil;
            @try {
                sceneID = scene.identifier;
            } @catch (NSException *e) {}

            if (CV3IdentifierContainsExactBundleID(keyString, bundleID) || CV3IdentifierContainsExactBundleID(sceneID, bundleID)) {
                fbSceneMatched = YES;
                matchedFBSceneID = sceneID ?: keyString ?: @"nil";
                matchedFBSceneSettingsForeground = CV3InvokeBool(scene.settings, @selector(foreground), NO);
                matchedFBSceneSettingsBackgrounded = CV3InvokeBool(scene.settings, @selector(backgrounded), YES);
                matchedFBSceneForeground = CV3SceneSettingsLookForeground(scene.settings);
                break;
            }
        }
    } @catch (NSException *e) {}

    CV3LogToFile(@"[Warning][PanelState] source=%@ target=%@ resolved=%ld currentActive=%@ dynamicFrontmost=%@ dynamicFrontmostSource=%@ activeItemClass=%@ activeItemParsed=%@ activeItemDesc=%@ activeItemsCount=%lu activeItemsMatched=%d observedBundleExact=%d observedSceneMatch=%d lastObservedBundle=%@ lastObservedScene=%@ lastActiveScene=%@ appExists=%d appBackgrounded=%d appSuspended=%d mainSceneID=%@ mainSceneForeground=%d mainSceneSettingsForeground=%d mainSceneSettingsBackgrounded=%d fbSceneCount=%lu fbSceneMatched=%d matchedFBSceneID=%@ matchedFBSceneForeground=%d matchedFBSceneSettingsForeground=%d matchedFBSceneSettingsBackgrounded=%d",
                 source ?: @"Unknown",
                 bundleID,
                 (long)resolvedState,
                 currentActive ?: @"nil",
                 dynamicFrontmost,
                 dynamicFrontmostSource,
                 activeItemClass,
                 activeItemParsed,
                 activeItemDesc,
                 (unsigned long)activeItemsCount,
                 activeItemsMatched,
                 observedBundleExact,
                 observedSceneMatch,
                 lastObservedBundle,
                 lastObservedScene,
                 lastActiveScene,
                 appExists,
                 appBackgrounded,
                 appSuspended,
                 mainSceneID,
                 mainSceneForeground,
                 mainSceneSettingsForeground,
                 mainSceneSettingsBackgrounded,
                 (unsigned long)fbSceneCount,
                 fbSceneMatched,
                 matchedFBSceneID,
                 matchedFBSceneForeground,
                 matchedFBSceneSettingsForeground,
                 matchedFBSceneSettingsBackgrounded);
}

static BOOL CV3ApplicationLooksForeground(NSString *bundleID) {
    if (bundleID.length == 0) return NO;

    if (CV3ObservedForegroundMatchesBundleID(bundleID)) return YES;

    @try {
        SBApplication *app = [[CV3ClassNamed(@"SBApplicationController") sharedInstance] applicationWithBundleIdentifier:bundleID];
        if (app) {
            BOOL backgrounded = CV3InvokeBool(app, @selector(isBackgrounded), YES);
            BOOL suspended = CV3InvokeBool(app, @selector(isSuspended), NO);
            if (!backgrounded && !suspended) return YES;

            FBScene *scene = nil;
            if ([app respondsToSelector:@selector(mainScene)]) {
                scene = [app mainScene];
            }
            if (scene && CV3IdentifierContainsExactBundleID(scene.identifier, bundleID) && CV3SceneSettingsLookForeground(scene.settings)) {
                return YES;
            }
        }
    } @catch (NSException *e) {}

    @try {
        id manager = [CV3ClassNamed(@"FBSceneManager") sharedInstance];
        id workspace = [manager valueForKey:@"_workspace"];
        NSDictionary *scenes = [workspace valueForKey:@"_allScenesByID"];

        for (id key in scenes) {
            FBScene *scene = scenes[key];
            NSString *keyString = [key isKindOfClass:[NSString class]] ? key : [key description];
            NSString *sceneID = nil;
            @try {
                sceneID = scene.identifier;
            } @catch (NSException *e) {}

            if ((CV3IdentifierContainsExactBundleID(keyString, bundleID) || CV3IdentifierContainsExactBundleID(sceneID, bundleID)) &&
                CV3SceneSettingsLookForeground(scene.settings)) {
                return YES;
            }
        }
    } @catch (NSException *e) {}

    @try {
        for (UIScene *scene in [[UIApplication sharedApplication].connectedScenes allObjects]) {
            if (scene.activationState != UISceneActivationStateForegroundActive) continue;
            NSString *sceneDescription = [scene description];
            NSString *sessionDescription = [scene.session description];
            NSString *persistentIdentifier = CV3InvokeObject(scene.session, @selector(persistentIdentifier));
            if (CV3IdentifierContainsExactBundleID(sceneDescription, bundleID) ||
                CV3IdentifierContainsExactBundleID(sessionDescription, bundleID) ||
                CV3IdentifierContainsExactBundleID(persistentIdentifier, bundleID)) {
                return YES;
            }
        }
    } @catch (NSException *e) {}

    return NO;
}

static BOOL CV3WorkspaceHasActiveBundleID(NSString *bundleID) {
    if (bundleID.length == 0) return NO;

    NSString *currentActive = CV3CurrentWorkspaceBundleID();
    if ([currentActive isEqualToString:bundleID]) return YES;

    @try {
        id workspace = [CV3ClassNamed(@"SBMainWorkspace") sharedInstance];
        id activeItem = CV3InvokeObject(workspace, @selector(activeDisplayItem));
        if (CV3WorkspaceObjectMatchesBundleID(activeItem, bundleID)) return YES;

        NSSet *activeItems = CV3InvokeObject(workspace, @selector(activeDisplayItems));
        for (id item in activeItems) {
            if (CV3WorkspaceObjectMatchesBundleID(item, bundleID)) return YES;
        }
    } @catch (NSException *e) {}

    return NO;
}

static BOOL CV3BounceItCarrierIsReadyComparedToSnapshot(UIView *view,
                                                         NSValue *identity,
                                                         NSDictionary<NSValue *, NSString *> *prelaunchSnapshot,
                                                         BOOL *hostContextChanged) {
    if (!prelaunchSnapshot) return YES;
    NSString *previousContextID = prelaunchSnapshot[identity];
    if (!previousContextID) return YES; // A genuinely new carrier object.

    NSString *currentContextID = CV3HostedLayerContextID(view.layer) ?: @"";
    BOOL changed = currentContextID.length > 0 &&
                   ![currentContextID isEqualToString:previousContextID];
    if (changed && hostContextChanged) *hostContextChanged = YES;
    return changed;
}

static UIView *CV3BounceItAppTransitionViewComparedToSnapshot(
    NSDictionary<NSValue *, NSString *> *prelaunchSnapshot,
    NSMutableDictionary<NSValue *, NSString *> *observedSnapshot,
    BOOL *hostContextChanged) {
    UIView *bestView = nil;
    BOOL bestHostContextChanged = NO;
    NSInteger bestScore = NSIntegerMin;
    CGRect screenBounds = UIScreen.mainScreen.bounds;
    CGFloat screenArea = MAX(1.0, CGRectGetWidth(screenBounds) * CGRectGetHeight(screenBounds));

    for (UIWindow *window in UIApplication.sharedApplication.windows) {
        if (!window || window == sharedWindow || [window isKindOfClass:[CV3Window class]] ||
            window.hidden || window.alpha <= 0.01) {
            continue;
        }

        NSMutableArray<UIView *> *pending = [NSMutableArray arrayWithObject:window];
        while (pending.count > 0) {
            UIView *view = pending.lastObject;
            [pending removeLastObject];
            if (!view || view.hidden || view.alpha <= 0.01) continue;

            NSString *className = NSStringFromClass(view.class);
            NSInteger score = NSIntegerMin;
            if ([className containsString:@"AppContainer"]) {
                score = 5000;
            } else if ([className containsString:@"ApplicationScene"] ||
                       [className containsString:@"DeviceApplicationScene"]) {
                score = 4500;
            } else if ([className containsString:@"SceneLayout"]) {
                score = 4000;
            } else if ([className containsString:@"SceneHost"] ||
                       [className containsString:@"LayerHostContainer"]) {
                score = 3500;
            }

            if (score != NSIntegerMin) {
                CGRect frameInScreen = [view convertRect:view.bounds toView:nil];
                CGFloat area = MAX(0.0, CGRectGetWidth(frameInScreen)) *
                               MAX(0.0, CGRectGetHeight(frameInScreen));
                CGFloat coverage = MIN(1.0, area / screenArea);
                if (coverage >= 0.72 && CGRectIntersectsRect(frameInScreen, screenBounds)) {
                    NSValue *identity = [NSValue valueWithPointer:(void *)view];
                    NSString *contextID = CV3HostedLayerContextID(view.layer) ?: @"";
                    if (observedSnapshot) observedSnapshot[identity] = contextID;
                    score += (NSInteger)lrint(coverage * 1000.0);
                    // Prefer the deepest concrete app container over a broad parent.
                    score += MIN((NSInteger)view.superview.subviews.count, 20);
                    BOOL candidateContextChanged = NO;
                    BOOL ready = CV3BounceItCarrierIsReadyComparedToSnapshot(
                        view, identity, prelaunchSnapshot, &candidateContextChanged);
                    if (ready && score > bestScore) {
                        bestScore = score;
                        bestView = view;
                        bestHostContextChanged = candidateContextChanged;
                    }
                }
            }

            [pending addObjectsFromArray:view.subviews];
        }

    }

    if (bestView && hostContextChanged) *hostContextChanged = bestHostContextChanged;
    return bestView;
}

// Capture every full-screen SpringBoard app-scene carrier before launch. App-to-app
// transitions either mount a new carrier or reuse one with a new CALayerHost context.
// Snapshot both identities so the bridge cannot animate the outgoing app.
static NSDictionary<NSValue *, NSString *> *CV3BounceItAppTransitionSnapshot(void) {
    NSMutableDictionary<NSValue *, NSString *> *snapshot = [NSMutableDictionary dictionary];
    CV3BounceItAppTransitionViewComparedToSnapshot(nil, snapshot, nil);
    return [NSDictionary dictionaryWithDictionary:snapshot];
}

static BOOL CV3BounceItAnimationParameters(CGFloat *mass,
                                            CGFloat *stiffness,
                                            CGFloat *damping,
                                            NSString **ownerPath) {
    Class settingsClass = CV3ClassNamed(@"SBFAnimationSettings");
    SEL dampingSelector = NSSelectorFromString(@"damping");
    Method dampingMethod = settingsClass ? class_getInstanceMethod(settingsClass, dampingSelector) : NULL;
    if (!dampingMethod) return NO;

    IMP rawImplementation = method_getImplementation(dampingMethod);
    void *implementation = (void *)rawImplementation;
#if __has_feature(ptrauth_calls)
    implementation = ptrauth_strip(implementation, ptrauth_key_function_pointer);
#endif
    Dl_info info = {0};
    if (!dladdr(implementation, &info) || !info.dli_fname) return NO;

    NSString *imagePath = [NSString stringWithUTF8String:info.dli_fname] ?: @"";
    if (ownerPath) *ownerPath = imagePath;
    if ([imagePath rangeOfString:@"BounceIt16" options:NSCaseInsensitiveSearch].location == NSNotFound) {
        return NO;
    }

    id settings = [settingsClass alloc];
    SEL massSelector = NSSelectorFromString(@"mass");
    SEL stiffnessSelector = NSSelectorFromString(@"stiffness");
    if (![settings respondsToSelector:massSelector] ||
        ![settings respondsToSelector:stiffnessSelector] ||
        ![settings respondsToSelector:dampingSelector]) {
        return NO;
    }

    double resolvedMass = ((double (*)(id, SEL))objc_msgSend)(settings, massSelector);
    double resolvedStiffness = ((double (*)(id, SEL))objc_msgSend)(settings, stiffnessSelector);
    double resolvedDamping = ((double (*)(id, SEL))objc_msgSend)(settings, dampingSelector);
    if (!isfinite(resolvedMass) || !isfinite(resolvedStiffness) || !isfinite(resolvedDamping) ||
        resolvedMass <= 0.0 || resolvedStiffness <= 0.0 || resolvedDamping < 0.0) {
        return NO;
    }

    if (mass) *mass = (CGFloat)resolvedMass;
    if (stiffness) *stiffness = (CGFloat)resolvedStiffness;
    if (damping) *damping = (CGFloat)resolvedDamping;
    return YES;
}

static NSUInteger CV3BounceItLaunchGeneration = 0;

static void CV3ApplyBounceItAppLaunchWhenReady(NSString *bundleID,
                                                NSString *sourceBundleID,
                                                NSUInteger generation,
                                                NSInteger attemptsRemaining,
                                                NSDictionary<NSValue *, NSString *> *prelaunchSnapshot) {
    if (generation != CV3BounceItLaunchGeneration || bundleID.length == 0) return;

    // CV3CurrentWorkspaceBundleID/activeDisplayItem are observably nil while the
    // launcher UIWindow is active, so workspace foreground state cannot gate this
    // bridge. Readiness is either a newly mounted carrier or a new CALayerHost
    // context inside a reused carrier (Apple News follows the latter path).
    BOOL hostContextChanged = NO;
    UIView *targetView = CV3BounceItAppTransitionViewComparedToSnapshot(
        prelaunchSnapshot, nil, &hostContextChanged);

    if (!targetView) {
        if (attemptsRemaining <= 0) {
            CV3LogToFile(@"[Launcher] phase=bounceitBridge bundle=%@ source=%@ applied=0 error=appSceneNotReady baselineCount=%lu",
                         bundleID, sourceBundleID ?: @"nil",
                         (unsigned long)prelaunchSnapshot.count);
            return;
        }
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.025 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            CV3ApplyBounceItAppLaunchWhenReady(bundleID, sourceBundleID,
                                                generation, attemptsRemaining - 1,
                                                prelaunchSnapshot);
        });
        return;
    }

    dispatch_async(dispatch_get_main_queue(), ^{
        if (generation != CV3BounceItLaunchGeneration) return;

        CGFloat mass = 0.0;
        CGFloat stiffness = 0.0;
        CGFloat damping = 0.0;
        NSString *ownerPath = nil;
        if (!CV3BounceItAnimationParameters(&mass, &stiffness, &damping, &ownerPath)) {
            CV3LogToFile(@"[Launcher] phase=bounceitBridge bundle=%@ source=%@ applied=0 error=pluginHookUnavailable owner=%@",
                         bundleID, sourceBundleID ?: @"nil", ownerPath ?: @"nil");
            return;
        }

        CASpringAnimation *bounce = [CASpringAnimation animationWithKeyPath:@"transform.scale"];
        bounce.mass = mass;
        bounce.stiffness = stiffness;
        bounce.damping = damping;
        bounce.initialVelocity = 0.0;
        // BounceIt supplies the spring physics, while the bridge must supply a
        // meaningful launch displacement. 0.92 only moves eight percent, making
        // the plugin's under-damped rebound nearly invisible on a full-screen app.
        // 0.82 preserves BounceIt's live mass/stiffness/damping while giving that
        // rebound enough travel to read like the native icon-launch animation.
        static const CGFloat kCV3BounceItLaunchFromScale = 0.82;
        bounce.fromValue = @(kCV3BounceItLaunchFromScale);
        bounce.toValue = @1.0;
        bounce.duration = bounce.settlingDuration;
        bounce.removedOnCompletion = YES;
        [targetView.layer addAnimation:bounce forKey:@"com.xu.chevronv3.bounceit-app-launch"];

        CGFloat dampingRatio = damping / (2.0 * sqrt(MAX(0.001, stiffness * mass)));
        NSInteger readyDelayMs = MAX(0, 80 - attemptsRemaining) * 25;
        CV3LogToFile(@"[Launcher] phase=bounceitBridge bundle=%@ source=%@ applied=1 sceneReady=1 reusedCarrier=%d hostContextChanged=%d readyDelayMs=%ld baselineCount=%lu view=%@ frame=%@ owner=%@ fromScale=%.2f mass=%.2f stiffness=%.1f damping=%.1f dampingRatio=%.3f duration=%.3f",
                     bundleID, sourceBundleID ?: @"nil", hostContextChanged,
                     hostContextChanged, (long)readyDelayMs,
                     (unsigned long)prelaunchSnapshot.count, NSStringFromClass(targetView.class),
                     NSStringFromCGRect([targetView convertRect:targetView.bounds toView:nil]),
                     ownerPath.lastPathComponent ?: ownerPath,
                     kCV3BounceItLaunchFromScale, mass, stiffness, damping,
                     dampingRatio, bounce.duration);
    });
}

// 主面板统一启动入口：始终在 SpringBoard 主线程发起同一种系统启动事务。
// Home→App 会原生消费 BounceIt Hook 的 SBFAnimationSettings；App→App 不会，
// 因此后一种路径在目标 Scene 提交后显式读取 BounceIt 的实时参数并补到 App 容器。
// 不回主屏、不复刻图标、不走 LSApplicationWorkspace，也不使用硬编码插件参数。
static void CV3LaunchApplicationThroughSpringBoard(NSString *bundleID, NSString *reason) {
    if (bundleID.length == 0) return;

    void (^launchBlock)(void) = ^{
        @try {
            id springBoard = [UIApplication sharedApplication];
            SEL launchSelector = @selector(launchApplicationWithIdentifier:suspended:);
            if (![springBoard respondsToSelector:launchSelector]) {
                CV3LogToFile(@"[Launcher] phase=bounceitSystemLaunch bundle=%@ reason=%@ invoked=0 error=selectorUnavailable",
                             bundleID, reason ?: @"Unknown");
                return;
            }

            NSString *sourceBundleID = CV3CurrentWorkspaceBundleID();
            BOOL appToApp = sourceBundleID.length > 0 &&
                            ![sourceBundleID isEqualToString:bundleID] &&
                            ![sourceBundleID isEqualToString:@"com.apple.springboard"];
            NSUInteger bounceGeneration = ++CV3BounceItLaunchGeneration;
            NSDictionary<NSValue *, NSString *> *prelaunchSnapshot = CV3BounceItAppTransitionSnapshot();
            CV3LogToFile(@"[Launcher] phase=bounceitSystemLaunch bundle=%@ source=%@ reason=%@ willInvoke=1 appToApp=%d mainThread=%d",
                         bundleID, sourceBundleID ?: @"nil", reason ?: @"Unknown",
                         appToApp, NSThread.isMainThread);

            ((void (*)(id, SEL, id, BOOL))objc_msgSend)(springBoard,
                                                        launchSelector,
                                                        bundleID,
                                                        NO);
            CV3LogToFile(@"[Launcher] phase=bounceitSystemLaunch bundle=%@ reason=%@ invoked=1 mainThread=%d",
                         bundleID, reason ?: @"Unknown", [NSThread isMainThread]);

            // Poll only after the launch transaction begins. A new carrier identity
            // or a changed CALayerHost context is the readiness gate; workspace bundle
            // APIs are nil while our panel owns the key window.
            CV3ApplyBounceItAppLaunchWhenReady(bundleID, sourceBundleID,
                                                bounceGeneration, 80,
                                                prelaunchSnapshot);
        } @catch (NSException *exception) {
            CV3LogToFile(@"[Launcher] phase=bounceitSystemLaunch bundle=%@ reason=%@ invoked=0 exception=%@",
                         bundleID, reason ?: @"Unknown", exception);
        }
    };

    if ([NSThread isMainThread]) {
        launchBlock();
    } else {
        dispatch_async(dispatch_get_main_queue(), launchBlock);
    }
}

static CV3FloatingAppWindow *CV3FloatingWindowForBundleID(NSString *bundleID) {
    if (bundleID.length == 0 || !floatingWindows) return nil;

    for (CV3FloatingAppWindow *win in [floatingWindows copy]) {
        if (![win isKindOfClass:[CV3FloatingAppWindow class]] || win.isClosing) continue;
        if ([win.bundleID isEqualToString:bundleID]) return win;
    }

    return nil;
}

static void CV3RefreshFloatingHomeBarAfterPresentation(CV3FloatingAppWindow *window) {
    if (!window || window.isClosing || window.isStashed) return;

    void (^refresh)(void) = ^{
        if (!window || window.isClosing || window.isStashed) return;
        [window setNeedsLayout];
        [window layoutIfNeeded];
        [window layoutFloatingHomeBarForBounds:window.appContentWrapper.bounds];
    };

    refresh();
    dispatch_async(dispatch_get_main_queue(), refresh);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.12 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), refresh);
}

// Entry point shared by the launcher and notification delivery callbacks.
static BOOL CV3OpenBundleInFloatingWindow(NSString *bundleID, NSString *reason) {
    if (bundleID.length == 0) return NO;

    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            CV3OpenBundleInFloatingWindow(bundleID, reason);
        });
        return YES;
    }

    // Screen Time 限额闸门（通知点开/其他回调开分屏的统一入口）
    if (!CV3ScreenTimeGateBundleID(bundleID,
                                   [NSString stringWithFormat:@"FloatingWindowOpen:%@", reason ?: @"Unknown"],
                                   YES,
                                   sharedWindow.windowScene)) {
        return YES;   // 已呈现拦截页，视为已处理
    }

    if (CV3EnsureFreshClientBridgeBeforeHosting(bundleID, ^{
        CV3OpenBundleInFloatingWindow(bundleID, reason);
    })) {
        return YES;
    }

    CV3FloatingAppWindow *existingWindow = CV3FloatingWindowForBundleID(bundleID);
    if (existingWindow) {
        if (CV3LockScreenPresented) {
            existingWindow.isSuppressedByLockScreen = YES;
            [existingWindow setHidden:YES];
            CV3LogToFile(@"[NotificationSplit] 锁屏期间保持已有分屏隐藏: %@ (%@)", bundleID, reason ?: @"Unknown");
            return YES;
        }
        [existingWindow restoreFromStash];
        [existingWindow setWindowFocused:YES];
        CV3RefreshFloatingHomeBarAfterPresentation(existingWindow);
        CV3LogToFile(@"[NotificationSplit] 聚焦已有分屏: %@ (%@)", bundleID, reason ?: @"Unknown");
        return YES;
    }

    if (!floatingWindows) floatingWindows = [NSMutableArray array];

    UIWindowScene *scene = sharedWindow.windowScene;
    if (!scene) {
        for (UIScene *candidate in [[UIApplication sharedApplication].connectedScenes allObjects]) {
            if ([candidate isKindOfClass:[UIWindowScene class]] &&
                candidate.activationState != UISceneActivationStateUnattached) {
                scene = (UIWindowScene *)candidate;
                break;
            }
        }
    }

    if (!scene) {
        CV3LogToFile(@"[NotificationSplit] 找不到可用 UIWindowScene: %@", bundleID);
        return NO;
    }

    CGPoint center = CGPointMake(CGRectGetMidX(scene.coordinateSpace.bounds),
                                 CGRectGetMidY(scene.coordinateSpace.bounds));
    CV3FloatingAppWindow *floatingWindow = [[CV3FloatingAppWindow alloc] initWithBundleID:bundleID
                                                                                        center:center
                                                                                   windowScene:scene];
    if (!floatingWindow) return NO;

    // initWithBundleID: already resolves the presentation orientation from the
    // app's declared capabilities. Do not overwrite a landscape-only game's
    // orientation with the portrait orientation of SpringBoard's display Scene.
    floatingWindow.isSuppressedByLockScreen = CV3LockScreenPresented;
    [floatingWindows addObject:floatingWindow];
    if (CV3LockScreenPresented) {
        [floatingWindow setHidden:YES];
    } else {
        [floatingWindow setWindowFocused:YES];
    }
    if (!CV3LockScreenPresented) CV3RefreshFloatingHomeBarAfterPresentation(floatingWindow);
    [[NSNotificationCenter defaultCenter] postNotificationName:CV3FloatingWindowsDidChangeNotification object:nil];
    CV3LogToFile(@"[NotificationSplit] 开启分屏: %@ (%@) locked=%d",
                 bundleID, reason ?: @"Unknown", CV3LockScreenPresented);
    return YES;
}

static CV3AppPanelProtectionState CV3AppPanelProtectionStateForBundleID(NSString *bundleID) {
    if (bundleID.length == 0) return CV3AppPanelProtectionStateNone;

    CV3AppPanelProtectionState state = CV3AppPanelProtectionStateNone;

    if (CV3FloatingWindowForBundleID(bundleID) != nil) {
        state = CV3AppPanelProtectionStateSplit;
        CV3LogPanelStateDebugForBundleID(bundleID, state, @"ProtectionState");
        return state;
    }

    NSString *dynamicFrontmost = CV3DynamicFrontmostBundleID();
    if ([dynamicFrontmost isEqualToString:bundleID]) {
        state = CV3AppPanelProtectionStateForeground;
        CV3LogPanelStateDebugForBundleID(bundleID, state, @"ProtectionState");
        return state;
    }

    if (CV3WorkspaceHasActiveBundleID(bundleID)) {
        state = CV3AppPanelProtectionStateForeground;
        CV3LogPanelStateDebugForBundleID(bundleID, state, @"ProtectionState");
        return state;
    }

    if (CV3ApplicationLooksForeground(bundleID)) {
        state = CV3AppPanelProtectionStateForeground;
        CV3LogPanelStateDebugForBundleID(bundleID, state, @"ProtectionState");
        return state;
    }

    if (CV3ApplicationHasLiveScene(bundleID)) {
        state = CV3AppPanelProtectionStateForeground;
        CV3LogPanelStateDebugForBundleID(bundleID, state, @"ProtectionState");
        return state;
    }

    CV3LogPanelStateDebugForBundleID(bundleID, state, @"ProtectionState");
    return state;
}

static NSString *CV3AppPanelProtectionReason(CV3AppPanelProtectionState state) {
    switch (state) {
        case CV3AppPanelProtectionStateForeground:
            return @"当前已在前台运行";
        case CV3AppPanelProtectionStateSplit:
            return @"当前已处于分屏状态";
        default:
            return nil;
    }
}

static void CV3RemoveViewAnimationsRecursively(UIView *view) {
    if (!view) return;
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            CV3RemoveViewAnimationsRecursively(view);
        });
        return;
    }
    [view.layer removeAllAnimations];
    for (UIView *subview in view.subviews) {
        CV3RemoveViewAnimationsRecursively(subview);
    }
}

static void CV3FinalizePanelHiddenState(CV3Window *launcherWindow) {
    if (!launcherWindow) return;
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            CV3FinalizePanelHiddenState(launcherWindow);
        });
        return;
    }

    launcherWindow.interactionCount++;
    launcherWindow.panelVisibilityAnimator = nil;
    CV3RemoveViewAnimationsRecursively(launcherWindow.panelContainer);
    [launcherWindow.bezierContainer.layer removeAllAnimations];
    [launcherWindow.bezierLayer removeAllAnimations];

    [UIView performWithoutAnimation:^{
        [CATransaction begin];
        [CATransaction setDisableActions:YES];
        launcherWindow.backgroundColor = [UIColor clearColor];
        launcherWindow.panelContainer.alpha = 0.0;
        launcherWindow.panelContainer.hidden = YES;
        launcherWindow.panelContainer.layer.shadowOpacity = 0.0;
        launcherWindow.panelContainer.layer.shadowPath = nil;
        launcherWindow.panelContainer.layer.shouldRasterize = NO;
        launcherWindow.panelContainer.userInteractionEnabled = YES;
        // Keep descendants in their canonical visible state. The parent owns
        // visibility so interactive edge peeking fades all chrome together.
        launcherWindow.appPanel.alpha = 1.0;
        launcherWindow.collectionView.alpha = 1.0;
        launcherWindow.contrastBackdrop.hidden = YES;
        launcherWindow.bezierContainer.alpha = 0.0;
        launcherWindow.bezierLayer.opacity = 0.0;
        launcherWindow.bezierLayer.shadowOpacity = 0.0;
        launcherWindow.bezierLayer.path = nil;
        [CATransaction commit];
    }];
    [CATransaction flush];

    // 面板收起的唯一收口：连图标呼吸一起停，隐藏期间不再空转。
    [launcherWindow syncAppCellBreathing];
}

static void CV3HidePanelImmediately(CV3Window *launcherWindow) {
    if (!launcherWindow) return;
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            CV3HidePanelImmediately(launcherWindow);
        });
        return;
    }

    CV3SetKeyboardSuppressedByPanel(NO);
    CV3SetHomeScreenPullDownSuppressed(NO);
    UIViewPropertyAnimator *visibilityAnimator = launcherWindow.panelVisibilityAnimator;
    launcherWindow.panelDismissCompletion = nil;
    launcherWindow.panelVisibilityAnimator = nil;
    [visibilityAnimator stopAnimation:YES];
    launcherWindow.isPanelShowing = NO;
    launcherWindow.isAnimating = NO;
    CV3FinalizePanelHiddenState(launcherWindow);
    [launcherWindow.searchField resignFirstResponder];
}

static void CV3LogPanelCollectionState(CV3Window *window, NSString *phase) {
    if (!window || !window.collectionView) return;

    UICollectionView *collectionView = window.collectionView;
    UIEdgeInsets inset;
    if (@available(iOS 11.0, *)) {
        inset = collectionView.adjustedContentInset;
    } else {
        inset = collectionView.contentInset;
    }

    NSArray<NSIndexPath *> *visible = [collectionView.indexPathsForVisibleItems
        sortedArrayUsingSelector:@selector(compare:)];
    NSIndexPath *first = visible.firstObject;
    NSIndexPath *last = visible.lastObject;
    UIPanGestureRecognizer *pan = collectionView.panGestureRecognizer;
    CGPoint translation = [pan translationInView:collectionView];
    CGPoint velocity = [pan velocityInView:collectionView];

    CV3LogToFile(@"[PanelScrollTrace] phase=%@ offset=%@ contentSize=%@ bounds=%@ frame=%@ inset=%@ "
                 "state={tracking=%d dragging=%d decelerating=%d pan=%ld enabled=%d} "
                 "gesture={translation=%@ velocity=%@} data={apps=%lu filtered=%lu category=%@ visible=%lu first=%@ last=%@} "
                 "panel={showing=%d animating=%d hidden=%d alpha=%.3f}",
                 phase ?: @"unknown",
                 NSStringFromCGPoint(collectionView.contentOffset),
                 NSStringFromCGSize(collectionView.contentSize),
                 NSStringFromCGRect(collectionView.bounds),
                 NSStringFromCGRect(collectionView.frame),
                 NSStringFromUIEdgeInsets(inset),
                 collectionView.tracking, collectionView.dragging, collectionView.decelerating,
                 (long)pan.state, collectionView.scrollEnabled,
                 NSStringFromCGPoint(translation), NSStringFromCGPoint(velocity),
                 (unsigned long)window.apps.count, (unsigned long)window.filteredApps.count,
                 window.selectedCategory ?: @"nil", (unsigned long)visible.count,
                 first ?: @"nil", last ?: @"nil",
                 window.isPanelShowing, window.isAnimating,
                 window.panelContainer.hidden, window.panelContainer.alpha);
}

@implementation CV3Window

- (void)applyBackgroundTint:(UIColor *)color {
    (void)color;
    [UIView animateWithDuration:0.8 animations:^{
        self.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:CV3Style.maskAlpha];
        [self refreshGlassAccentSurfaces];
    }];
}

// 224：按“面板背后壁纸的亮度”覆盖窗口外观解析——文字颜色（labelColor 等动态色）自动适配，
// 玻璃与排版完全不动。深壁纸 → Dark 外观 → 白字；浅壁纸 → Light → 黑字。
static UIView *CV3FindWallpaperViewInView(UIView *view, NSInteger depth) {
    if (!view || depth > 20) return nil;
    NSString *cls = NSStringFromClass(view.class);
    if ([cls containsString:@"Wallpaper"]) return view;
    for (UIView *sub in view.subviews) {
        UIView *found = CV3FindWallpaperViewInView(sub, depth + 1);
        if (found) return found;
    }
    return nil;
}

// 226/227：从前台环境的状态栏样式解析明暗——App 设白字=深色界面（dark），黑字=浅色界面（light）。
// 返回 YES 表示已解析（outDark 有效）；Default/未知返回 NO（交给壁纸采样兜底）。
- (BOOL)cv3_styleFromStatusBar:(BOOL *)outDark {
    if (outDark) *outDark = NO;
    if (@available(iOS 13.0, *)) {
        UIWindowScene *activeScene = nil;
        for (UIScene *s in UIApplication.sharedApplication.connectedScenes) {
            if ([s isKindOfClass:UIWindowScene.class] && s.activationState == UISceneActivationStateForegroundActive) {
                activeScene = (UIWindowScene *)s;
                break;
            }
        }
        UIStatusBarManager *manager = (activeScene ?: self.windowScene).statusBarManager;
        if (manager) {
            UIStatusBarStyle style = manager.statusBarStyle;
            if (style == UIStatusBarStyleLightContent) {
                if (outDark) *outDark = YES;
                return YES;
            }
            if (style == UIStatusBarStyleDarkContent) {
                if (outDark) *outDark = NO;
                return YES;
            }
        }
    }
    return NO;
}

- (BOOL)cv3_backdropIsDark {
    NSMutableArray<NSString *> *diagnostics = [NSMutableArray array];
    NSArray<UIScene *> *scenes = UIApplication.sharedApplication.connectedScenes.allObjects;
    for (UIScene *scene in scenes) {
        if (![scene isKindOfClass:UIWindowScene.class]) continue;
        for (UIWindow *w in ((UIWindowScene *)scene).windows) {
            if (w == self) continue;
            if (diagnostics.count < 12) {
                [diagnostics addObject:[NSString stringWithFormat:@"%@(L%.0f,h%d,sub%lu)",
                                        NSStringFromClass(w.class), w.windowLevel, w.hidden,
                                        (unsigned long)w.subviews.count]];
            }
            if (w.hidden) continue;
            UIView *wallpaper = CV3FindWallpaperViewInView(w, 0);
            if (!wallpaper) continue;

            UIGraphicsImageRendererFormat *fmt = [UIGraphicsImageRendererFormat defaultFormat];
            fmt.scale = 1.0;
            UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(8.0, 8.0) format:fmt];
            UIImage *thumb = [renderer imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
                [wallpaper drawViewHierarchyInRect:CGRectMake(0, 0, 8.0, 8.0) afterScreenUpdates:NO];
            }];
            CGImageRef cg = thumb.CGImage;
            if (!cg) break;

            CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
            uint8_t pixels[8 * 8 * 4] = {0};
            CGContextRef bctx = CGBitmapContextCreate(pixels, 8, 8, 8, 32, space, kCGImageAlphaPremultipliedLast);
            CGColorSpaceRelease(space);
            if (!bctx) break;
            CGContextDrawImage(bctx, CGRectMake(0, 0, 8, 8), cg);
            CGContextRelease(bctx);

            double sum = 0.0;
            for (NSInteger i = 0; i < 8 * 8; i++) {
                CGFloat r = pixels[i * 4 + 0] / 255.0;
                CGFloat g = pixels[i * 4 + 1] / 255.0;
                CGFloat b = pixels[i * 4 + 2] / 255.0;
                sum += 0.2126 * r + 0.7152 * g + 0.0722 * b;
            }
            double luminance = sum / 64.0;
            CV3LogToFile(@"[PanelAppearance] sample=%@ luminance=%.3f -> %@",
                         NSStringFromClass(wallpaper.class), luminance, luminance < 0.5 ? @"dark" : @"light");
            return luminance < 0.5;
        }
    }
    // 兜底：找不到壁纸视图 → 按系统外观
    CV3LogToFile(@"[PanelAppearance] no-wallpaper windows=[%@] scenes=%lu",
                 [diagnostics componentsJoinedByString:@","], (unsigned long)scenes.count);
    if (@available(iOS 13.0, *)) {
        return self.traitCollection.userInterfaceStyle == UIUserInterfaceStyleDark;
    }
    return NO;
}

// 227：快路径（状态栏样式）每次 refresh 都解析——廉价且能即时跟随“你刚切到的 App”；
// 慢路径（壁纸采样，含 drawViewHierarchy）保留 5 秒节流，仅在状态栏为 Default 时使用。
- (void)cv3_updateAppearanceForBackdrop {
    if (@available(iOS 13.0, *)) {
        BOOL dark = NO;
        if ([self cv3_styleFromStatusBar:&dark]) {
            UIUserInterfaceStyle target = dark ? UIUserInterfaceStyleDark : UIUserInterfaceStyleLight;
            if (self.overrideUserInterfaceStyle != target) {
                self.overrideUserInterfaceStyle = target;
                CV3LogToFile(@"[PanelAppearance] overrideUserInterfaceStyle=%ld source=statusBar", (long)target);
            }
            return;
        }
        static CFTimeInterval lastSampleAt = 0;
        CFTimeInterval now = CACurrentMediaTime();
        if (now - lastSampleAt < 5.0) return;
        lastSampleAt = now;
        UIUserInterfaceStyle target = [self cv3_backdropIsDark] ? UIUserInterfaceStyleDark : UIUserInterfaceStyleLight;
        if (self.overrideUserInterfaceStyle != target) {
            self.overrideUserInterfaceStyle = target;
            CV3LogToFile(@"[PanelAppearance] overrideUserInterfaceStyle=%ld source=wallpaper", (long)target);
        }
    }
}

- (void)refreshGlassAccentSurfaces {
    if (self.appPanel) {
        self.appPanel.contentView.backgroundColor = [UIColor clearColor];
        self.appPanel.layer.borderColor = [[UIColor whiteColor] colorWithAlphaComponent:self.isPanelShowing ? 0.07 : 0.04].CGColor;
        self.appPanel.layer.borderWidth = 0.5 / [UIScreen mainScreen].scale;
    }

    // 224：文字颜色随“面板背后壁纸亮度”自适应（窗口外观覆盖；玻璃/排版不动）
    [self cv3_updateAppearanceForBackdrop];

    for (UIView *sub in self.categoryBar.subviews) {
        if (![sub isKindOfClass:[UIButton class]]) continue;
        UIButton *btn = (UIButton *)sub;
        NSString *fullTitle = btn.titleLabel.text ?: @"";
        NSString *catName = fullTitle;
        if ([fullTitle containsString:@" ("]) {
            catName = [fullTitle componentsSeparatedByString:@" ("][0];
        }
        BOOL isSelected = [catName isEqualToString:self.selectedCategory];
        BOOL isSuggested = CV3GetTimePriorityForCategory(catName) > 0;
        [self applyGlassAccentToCategoryButton:btn selected:isSelected suggested:isSuggested];
    }
}

#pragma mark - Liquid Glass（主面板）
// 参考 byg.iosios.net.liquidas 的实现路线：它的“液态玻璃”并非 Metal，
// 而是 CABackdropLayer + CAFilter 滤镜链（gaussianBlur 玻璃底 + colorSaturate
// vibrance）再叠加高光/边缘层。这里把同一配方只应用到主面板（appPanel）。
// 仅主面板，其余 surface 不动（2026-10-16 许总要求先看效果）。

- (void)installMainPanelLiquidGlass {
    if (!self.appPanel || self.liquidGlassHost) return;

    UIView *contentView = self.appPanel.contentView;

    // 1) 玻璃底：公用 backdrop（CV3LiquidGlassSupport.h，主面板配方），略放大做出透镜边缘感
    UIView *host = [[UIView alloc] initWithFrame:contentView.bounds];
    host.userInteractionEnabled = NO;
    host.backgroundColor = [UIColor clearColor];
    host.alpha = 0.88; // 轻微透出下方内容 = 半透明玻璃而非磨砂板
    host.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;

    BOOL created = NO;
    CALayer *backdrop = CV3LiquidGlassEnsureBackdrop(host,
                                                     @"CV3MainPanelLiquidGlassBackdrop",
                                                     CV3LiquidGlassRecipePanel(),
                                                     0.0,
                                                     &created);
    if (!backdrop) {
        CV3LogToFile(@"[LiquidGlass] install aborted reason=backdrop-unavailable");
        return;
    }

    // 系统乳白材质的色调层退场，否则会盖在自建玻璃上发白
    self.appPanel.effect = nil;
    [contentView insertSubview:host atIndex:0];

    // 2) 顶部菲涅尔光泽：玻璃内部的柔和高光
    UIView *glossView = [[UIView alloc] initWithFrame:contentView.bounds];
    glossView.userInteractionEnabled = NO;
    glossView.backgroundColor = [UIColor clearColor];
    glossView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    CAGradientLayer *gloss = [CAGradientLayer layer];
    gloss.colors = @[
        (id)[UIColor colorWithWhite:1.0 alpha:0.08].CGColor,
        (id)[UIColor colorWithWhite:1.0 alpha:0.025].CGColor,
        (id)[UIColor colorWithWhite:1.0 alpha:0.0].CGColor
    ];
    gloss.locations = @[@0.0, @0.40, @1.0];
    gloss.startPoint = CGPointMake(0.5, 0.0);
    gloss.endPoint = CGPointMake(0.5, 1.0);
    [glossView.layer addSublayer:gloss];
    [contentView insertSubview:glossView atIndex:1];

    // 3) 边缘镜面高光（rim）：顶部最亮、底部带反光，模拟玻璃边缘的折射亮线
    CAGradientLayer *rim = [CAGradientLayer layer];
    rim.colors = @[
        (id)[UIColor colorWithWhite:1.0 alpha:0.45].CGColor,
        (id)[UIColor colorWithWhite:1.0 alpha:0.06].CGColor,
        (id)[UIColor colorWithWhite:1.0 alpha:0.02].CGColor,
        (id)[UIColor colorWithWhite:1.0 alpha:0.02].CGColor,
        (id)[UIColor colorWithWhite:1.0 alpha:0.15].CGColor
    ];
    rim.locations = @[@0.0, @0.12, @0.35, @0.85, @1.0];
    rim.startPoint = CGPointMake(0.5, 0.0);
    rim.endPoint = CGPointMake(0.5, 1.0);
    CAShapeLayer *rimMask = [CAShapeLayer layer];
    rimMask.fillColor = [UIColor clearColor].CGColor;
    rimMask.strokeColor = [UIColor blackColor].CGColor;
    rimMask.lineWidth = 1.0;
    rim.mask = rimMask;
    [self.appPanel.layer addSublayer:rim];

    self.liquidGlassHost = host;
    self.liquidGlassBackdrop = backdrop;
    self.liquidGlassGlossView = glossView;
    self.liquidGlassGlossLayer = gloss;
    self.liquidGlassRim = rim;

    [self syncMainPanelLiquidGlassGeometry];

    CV3LogToFile(@"[LiquidGlass] installed surface=main-panel created=%d size=%.0fx%.0f",
                 created, host.bounds.size.width, host.bounds.size.height);
}

- (void)syncMainPanelLiquidGlassGeometry {
    if (!self.liquidGlassHost || !self.liquidGlassBackdrop) return;
    CGRect bounds = self.appPanel.bounds;
    if (CGRectIsEmpty(bounds)) return;

    [CATransaction begin];
    [CATransaction setDisableActions:YES];

    self.liquidGlassHost.frame = bounds;
    self.liquidGlassBackdrop.bounds = self.liquidGlassHost.bounds;
    self.liquidGlassBackdrop.position = CGPointMake(CGRectGetMidX(self.liquidGlassHost.bounds),
                                                    CGRectGetMidY(self.liquidGlassHost.bounds));

    self.liquidGlassGlossView.frame = bounds;
    self.liquidGlassGlossLayer.frame = self.liquidGlassGlossView.bounds;

    CGFloat inset = 0.7;
    self.liquidGlassRim.frame = bounds;
    CAShapeLayer *rimMask = [self.liquidGlassRim.mask isKindOfClass:[CAShapeLayer class]]
        ? (CAShapeLayer *)self.liquidGlassRim.mask : nil;
    if (rimMask) {
        CGFloat baseRadius = self.appPanel.layer.cornerRadius;
        if (baseRadius <= 0.0) baseRadius = CV3Style.cornerRadius;
        CGFloat radius = MAX(0.0, baseRadius - inset);
        rimMask.path = [UIBezierPath bezierPathWithRoundedRect:CGRectInset(bounds, inset, inset)
                                                  cornerRadius:radius].CGPath;
    }

    [CATransaction commit];

    // 证据链：记录同步次数与尺寸（前 8 次 + 每 200 次限流，避免拖拽帧刷盘）
    static NSUInteger syncSeq = 0;
    syncSeq += 1;
    if (syncSeq <= 8 || syncSeq % 200 == 0) {
        CV3LogToFile(@"[LiquidGlass] sync seq=%lu bounds=%.0fx%.0f",
                     (unsigned long)syncSeq, bounds.size.width, bounds.size.height);
    }
}

- (void)applyGlassAccentToCategoryButton:(UIButton *)button selected:(BOOL)selected suggested:(BOOL)suggested {
    if (!button) return;

    CGFloat intensity = selected ? 0.78 : (suggested ? 0.52 : 0.34);
    button.clipsToBounds = YES;
    button.layer.cornerRadius = CGRectGetHeight(button.bounds) * 0.5;
    CV3ApplyGlassAccentStyle(button,
                             button,
                             CV3EnsureGlassAccentLayer(button),
                             nil,
                             CGRectGetHeight(button.bounds) * 0.5,
                             intensity,
                             selected);
    // Liquid Glass：分类胶囊补真玻璃底（主面板同配方，模糊半径按小控件缩放）
    [self installLiquidGlassOnCategoryButton:button];
    [button setTitleColor:[UIColor labelColor] forState:UIControlStateNormal];
}

// Liquid Glass 分类胶囊：确保按钮拥有 CABackdropLayer 玻璃底（幂等；重复调用仅同步几何）
- (void)installLiquidGlassOnCategoryButton:(UIButton *)button {
    if (!button) return;

    BOOL created = NO;
    CALayer *backdrop = CV3LiquidGlassEnsureBackdrop(button,
                                                     @"CV3CategoryLiquidGlassBackdrop",
                                                     CV3LiquidGlassRecipeControl(),
                                                     CGRectGetHeight(button.bounds) * 0.5,
                                                     &created);
    if (backdrop && created) {
        CV3LogToFile(@"[LiquidGlass] installed surface=category-pill size=%.0fx%.0f",
                     button.bounds.size.width, button.bounds.size.height);
    }
}

- (void)handleDoubleTap:(UITapGestureRecognizer *)gesture {
    CV3ExitExposeModeIfNeeded(nil, NO);
    // 建议 5：搜索极速启动
    // 如果搜索框有内容且有结果，双击面板直接启动第一个
    if (self.searchField.text.length > 0 && self.filteredApps.count > 0) {
        [self launchApp:self.filteredApps[0]];
        return;
    }
    
    BOOL became = [self.searchField becomeFirstResponder];
    UIInterfaceOrientation orientation = self.targetOrientation != UIInterfaceOrientationUnknown ? self.targetOrientation : UIInterfaceOrientationPortrait;
    CV3LogToFile(@"[Warning][KeyboardDebug] doubleTap becomeFirstResponder=%d isFirstResponder=%d orientation=%ld window=%@ windowScene=%@ accessory=%@",
                 became,
                 self.searchField.isFirstResponder,
                 (long)orientation,
                 self.searchField.window,
                 self.windowScene,
                 self.searchField.inputAccessoryView);
}

// 统一 App 启动逻辑
- (void)launchApp:(CV3AppInfo *)info {
    if (!info || !info.bundleId) return;
    NSString *bid = [info.bundleId copy];
    CV3AppPanelProtectionState protectionState = CV3AppPanelProtectionStateForBundleID(bid);
    if (protectionState != CV3AppPanelProtectionStateNone) {
        CV3LogToFile(@"[Launcher] 已阻止主App面板操作: 目标=%@, 原因=%@",
                     bid,
                     CV3AppPanelProtectionReason(protectionState) ?: @"Unknown");
        [self.collectionView reloadData];
        return;
    }

    // Screen Time 限额闸门：命中则呈现系统拦截页（含 STL16 的 Face ID 增强），不发起启动
    if (!CV3ScreenTimeGateBundleID(bid, @"PanelLaunch", YES, self.windowScene)) {
        [self.collectionView reloadData];
        return;
    }

    if (self.launchDebounce) return;
    CV3ExitExposeModeIfNeeded(nil, NO);
    self.launchDebounce = YES;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.25 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        self.launchDebounce = NO;
    });


    NSString *currentActive = CV3CurrentWorkspaceBundleID();
    CV3LogToFile(@"[Launcher] 主App面板应用点击: 目标=%@, 当前前台App=%@", bid, currentActive);

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

    NSString *launchBundleID = [bid copy];

    // 启动代际：面板收起完成后，仅允许最新一次点击发起启动事务。
    self.launchRequestGeneration++;
    NSUInteger requestGeneration = self.launchRequestGeneration;

    // 面板完全收起后，只发起一次 SpringBoard 系统启动事务。无论面板来自主屏还是
    // 其他 App，路径都相同；BounceIt 会在系统动画设置层统一接管弹跳参数。
    __weak typeof(self) weakSelf = self;
    self.panelDismissCompletion = ^{
        CV3Window *strongSelf = weakSelf;
        if (!strongSelf) return;
        if (requestGeneration != strongSelf.launchRequestGeneration) return;

        CV3LaunchApplicationThroughSpringBoard(
            launchBundleID,
            [NSString stringWithFormat:@"LauncherPanel:%@", launchBundleID]);
    };
    [self animateSpotlight:NO fromPoint:self.panelContainer.center velocity:0.0];
}

- (void)searchTextChanged:(UITextField *)textField {
    CV3ExitExposeModeIfNeeded(nil, NO);
    [self filterApps];
}



// 建议 2：应用“衰老”效果 (Entropy Archive)
- (void)applyAgingEffectToCell:(CV3AppCell *)cell withInfo:(CV3AppInfo *)info {
    cell.alpha = 1.0;
}

- (void)filterApps {
    self.interactionCount++;
    CV3LogPanelCollectionState(self, @"filter.before");
    
    NSString *text = [self.searchField.text lowercaseString];
    
    BOOL hasSearch = (text && text.length > 0);
    BOOL isRecentlyUsed = [self.selectedCategory isEqualToString:@"最近使用"];
    BOOL isPinnedView = [self.selectedCategory isEqualToString:@"置顶"];
    BOOL hasCategory = (self.selectedCategory && ![self.selectedCategory isEqualToString:@"全部"] && !isRecentlyUsed && !isPinnedView);

    NSMutableArray *res = [NSMutableArray array];
    
    // 搜索始终覆盖当前分类；清空后仍按保留的 selectedCategory 恢复列表。
    if (hasSearch) {
        for (CV3AppInfo *info in self.apps) {
            BOOL matchSearch = ([info.name rangeOfString:text options:NSCaseInsensitiveSearch].location != NSNotFound ||
                                [info.bundleId rangeOfString:text options:NSCaseInsensitiveSearch].location != NSNotFound ||
                                (info.pinyinInitial && [info.pinyinInitial rangeOfString:text].location != NSNotFound));
            if (matchSearch) {
                [self applyAgingEffectToCell:nil withInfo:info];
                [res addObject:info];
            }
        }
    } else if (isRecentlyUsed) {
        for (CV3AppInfo *info in self.recentlyUsedApps) {
            [res addObject:info];
        }
    } else if (isPinnedView) {
        for (CV3AppInfo *info in self.apps) {
            if (info.isPinned) {
                [res addObject:info];
            }
        }
    } else {
        for (CV3AppInfo *info in self.apps) {
            BOOL matchCategory = YES;
            if (hasCategory) {
                matchCategory = [info.category isEqualToString:self.selectedCategory];
            }
            
            if (matchCategory) {
                // 应用衰老效果
                [self applyAgingEffectToCell:nil withInfo:info];
                [res addObject:info];
            }
        }
    }

    self.filteredApps = res;

    BOOL isUserScrolling = CV3ScrollViewIsActivelyControlled(self.collectionView);
    CGPoint preservedOffset = self.collectionView.contentOffset;

    if (isUserScrolling) {
        [UIView performWithoutAnimation:^{
            [self.collectionView reloadData];
            [self.collectionView layoutIfNeeded];
            [self.collectionView setContentOffset:CV3ClampedContentOffsetForScrollView(self.collectionView, preservedOffset) animated:NO];
        }];
    } else {
        [self.collectionView reloadData];
    }
    CV3LogPanelCollectionState(self, isUserScrolling ? @"filter.afterReload.preserved" : @"filter.afterReload.unpreserved");
    dispatch_async(dispatch_get_main_queue(), ^{
        CV3LogPanelCollectionState(self, @"filter.nextRunLoop");
    });

    // 列表刷新后只保留轻量入场动画，避免旧的磁吸/波纹 transform 干扰图标漂浮。
    NSInteger filterGeneration = self.interactionCount;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.01 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (filterGeneration != self.interactionCount) return;
        if (!CV3ScrollViewIsActivelyControlled(self.collectionView)) {
            [self animateIconsStaggered];
        }
    });

    UIInterfaceOrientation accessoryOrientation = self.targetOrientation != UIInterfaceOrientationUnknown ? self.targetOrientation : UIInterfaceOrientationPortrait;
    BOOL accessoryAllowed = !UIInterfaceOrientationIsLandscape(accessoryOrientation);

    // 键盘候选 App 快捷栏 (inputAccessoryView)：未搜索时展示常驻/最近 App，搜索时动态展示匹配候选 App
    if (accessoryAllowed) {
        NSArray<CV3AppInfo *> *candidateSource = hasSearch ? self.filteredApps : (self.recentlyUsedApps.count > 0 ? self.recentlyUsedApps : self.apps);
        if (candidateSource.count > 0) {
            NSArray *topCandidates = [candidateSource subarrayWithRange:NSMakeRange(0, MIN(6, candidateSource.count))];
            __weak typeof(self) weakSelf = self;
            self.searchField.inputAccessoryView = [[CV3QuickAccessView alloc] initWithApps:topCandidates selectionHandler:^(CV3AppInfo *appInfo) {
                [weakSelf launchApp:appInfo];
            }];
            if (self.searchField.isFirstResponder) {
                [self.searchField reloadInputViews];
            }
        } else if (self.searchField.inputAccessoryView) {
            self.searchField.inputAccessoryView = nil;
            if (self.searchField.isFirstResponder) {
                [self.searchField reloadInputViews];
            }
        }
    } else {
        if (self.searchField.inputAccessoryView) {
            self.searchField.inputAccessoryView = nil;
            if (self.searchField.isFirstResponder) {
                [self.searchField reloadInputViews];
            }
        }
    }
    self.noResultsLabel.hidden = (self.filteredApps.count > 0);
}

- (BOOL)textFieldShouldBeginEditing:(UITextField *)textField {
    if (textField == self.searchField) {
        UIInterfaceOrientation orientation = self.targetOrientation != UIInterfaceOrientationUnknown ? self.targetOrientation : UIInterfaceOrientationPortrait;
        CGRect searchFrameInWindow = [textField.superview convertRect:textField.frame toView:self];
        CV3LogToFile(@"[Warning][KeyboardDebug] shouldBegin searchField orientation=%ld isLandscape=%d window=%@ keyWindow=%d hidden=%d alpha=%.2f fieldWindow=%@ frameInWindow=%@ accessory=%@ inputView=%@",
                     (long)orientation,
                     UIInterfaceOrientationIsLandscape(orientation),
                     self,
                     self.isKeyWindow,
                     self.hidden,
                     self.alpha,
                     textField.window,
                     NSStringFromCGRect(searchFrameInWindow),
                     textField.inputAccessoryView,
                     textField.inputView);
    }
    return YES;
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
        CV3SetKeyboardSuppressedByPanel(self.isPanelShowing);
        CV3ExitExposeModeIfNeeded(nil, NO);
        [self filterApps];
        UIInterfaceOrientation orientation = self.targetOrientation != UIInterfaceOrientationUnknown ? self.targetOrientation : UIInterfaceOrientationPortrait;
        CV3LogToFile(@"[Warning][KeyboardDebug] didBegin searchField orientation=%ld isFirstResponder=%d window=%@ keyWindow=%d accessory=%@ inputView=%@",
                     (long)orientation,
                     textField.isFirstResponder,
                     textField.window,
                     self.isKeyWindow,
                     textField.inputAccessoryView,
                     textField.inputView);
        UIView *container = textField.superview;
        
        // 搜索框焦点态：单次平滑 Spring 响应 (根据 emil-design-eng & fixing-motion-performance 规范，避免无限循环 CPU/GPU 重绘)
        CGFloat concentricRadius = CV3ConcentricCornerRadius(CV3Style.cornerRadius, 15.0);
        [UIView animateWithDuration:0.25 delay:0 usingSpringWithDamping:0.85 initialSpringVelocity:0.3 options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction animations:^{
            container.transform = CGAffineTransformMakeScale(1.015, 1.015);
            self.searchBackground.shadowColor = [UIColor labelColor].CGColor;
            self.searchBackground.shadowOffset = CGSizeZero;
            self.searchBackground.shadowOpacity = 0.25;
            self.searchBackground.shadowRadius = 6.0;
            self.searchBackground.strokeColor = [[UIColor cyanColor] colorWithAlphaComponent:0.5].CGColor;
            self.searchBackground.path = [UIBezierPath bezierPathWithRoundedRect:self.searchBackground.bounds cornerRadius:concentricRadius].CGPath;
            CV3LiquidGlassEnsureBackdrop(container, @"CV3SearchFieldLiquidGlassBackdrop", CV3LiquidGlassRecipeControl(), concentricRadius, NULL);
        } completion:nil];
    }
}

- (void)textFieldDidEndEditing:(UITextField *)textField {
    if (textField == self.searchField) {
        CV3SetKeyboardSuppressedByPanel(self.isPanelShowing);
        UIInterfaceOrientation orientation = self.targetOrientation != UIInterfaceOrientationUnknown ? self.targetOrientation : UIInterfaceOrientationPortrait;
        CV3LogToFile(@"[Warning][KeyboardDebug] didEnd searchField orientation=%ld isFirstResponder=%d window=%@ keyWindow=%d",
                     (long)orientation,
                     textField.isFirstResponder,
                     textField.window,
                     self.isKeyWindow);
        UIView *container = textField.superview;
        [container.layer removeAllAnimations];
        [self.searchBackground removeAllAnimations];

        CGFloat concentricRadius = CV3ConcentricCornerRadius(CV3Style.cornerRadius, 15.0);
        void (^resetSearchVisuals)(void) = ^{
            container.transform = CGAffineTransformIdentity;
            self.searchBackground.shadowOpacity = 0;
            self.searchBackground.shadowRadius = 0;
            self.searchBackground.path = [UIBezierPath bezierPathWithRoundedRect:self.searchBackground.bounds cornerRadius:concentricRadius].CGPath;
            self.searchBackground.strokeColor = [[UIColor whiteColor] colorWithAlphaComponent:0.1].CGColor;
            CV3LiquidGlassEnsureBackdrop(container, @"CV3SearchFieldLiquidGlassBackdrop", CV3LiquidGlassRecipeControl(), concentricRadius, NULL);
        };
        if (self.isPanelShowing) {
            [UIView animateWithDuration:0.25 delay:0 options:UIViewAnimationOptionCurveEaseOut | UIViewAnimationOptionBeginFromCurrentState animations:resetSearchVisuals completion:nil];
        } else {
            [UIView performWithoutAnimation:resetSearchVisuals];
        }
    }
}

- (void)collectionView:(UICollectionView *)cv didSelectItemAtIndexPath:(NSIndexPath *)indexPath {
    [cv deselectItemAtIndexPath:indexPath animated:NO];

    if (indexPath.item < self.filteredApps.count) {
        CV3AppInfo *info = self.filteredApps[indexPath.item];
        CV3LogToFile(@"[LauncherTouch] phase=collectionSelection bundle=%@ index=%ld",
                     info.bundleId ?: @"nil", (long)indexPath.item);
        [self launchApp:info];
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
        maxW = h - (safe.top + safe.bottom + CV3Style.safeAreaBreath * 2);
        maxH = w - (safe.left + safe.right + CV3Style.safeAreaBreath * 2);
    } else {
        maxW = w - (safe.left + safe.right + CV3Style.safeAreaBreath * 2);
        maxH = h - (safe.top + safe.bottom + CV3Style.safeAreaBreath * 2);
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

    // UIWindow 上的全屏 tap 只负责面板外部收起。面板正在做弹簧变换时，
    // locationInView: 可能落在模型层 bounds 之外；以 UIKit 已经解析出的真实命中
    // view 祖先链为权威，避免把 App Cell 的单击误判为背景点击并穿透到底层。
    if (gestureRecognizer.view == self) {
        UIView *touchedView = touch.view;
        if (touchedView == self.panelContainer ||
            [touchedView isDescendantOfView:self.panelContainer]) {
            CV3LogToFile(@"[LauncherTouch] phase=dimming.reject reason=panelDescendant hit=%@",
                         NSStringFromClass(touchedView.class));
            return NO;
        }

        CGPoint location = [touch locationInView:self.panelContainer];
        if (CGRectContainsPoint(self.panelContainer.bounds, location)) {
            CV3LogToFile(@"[LauncherTouch] phase=dimming.reject reason=panelBounds hit=%@ point=%@",
                         NSStringFromClass(touchedView.class), NSStringFromCGPoint(location));
            return NO;
        }
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
    return CV3CurrentWorkspaceBundleID();
}

- (NSString *)edgeEnvironmentBlockReason {
    if (CV3LockScreenPresented) return @"reject.lockScreen";
    @try {
        id lock = CV3InvokeObject(CV3ClassNamed(@"SBLockScreenManager"), @selector(sharedInstance));
        if (CV3InvokeBool(lock, NSSelectorFromString(@"isUILocked"), NO) ||
            CV3InvokeBool(lock, NSSelectorFromString(@"isLocked"), NO)) return @"reject.lockScreen";
        id cc = CV3InvokeObject(CV3ClassNamed(@"SBControlCenterController"), @selector(sharedInstance));
        if (CV3InvokeBool(cc, @selector(isPresented), NO)) return @"reject.controlCenter";
        UIView *coverView = CV3GestureCoverSheetController.viewIfLoaded;
        if (CV3GestureCoverSheetPresented || (coverView.window && !coverView.hidden)) return @"reject.coverSheet";
    } @catch (__unused NSException *e) {
        return @"reject.environmentUnavailable";
    }
    if (self.isSuppressedBySystem) return @"reject.systemSuppressed";
    return nil;
}

- (void)cancelEdgeEnvironmentInteraction {
    self.edgeEnvironmentCancelled = YES;
    CV3PanelWakeGestureActive = NO;
    CV3SetHomeScreenPullDownSuppressed(NO);
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    self.triggerPreviewLayer.opacity = 0;
    self.bezierContainer.alpha = 0;
    if (!self.isPanelShowing) {
        self.panelContainer.hidden = YES;
        self.panelContainer.alpha = 0;
    }
    [CATransaction commit];
}

- (void)recordEdgeEnvironment:(NSString *)phase gesture:(UIGestureRecognizer *)gesture decision:(NSString *)decision {
    // Unknown private selectors must not be reported as a false/hidden state.
    NSInteger (^readFlag)(id, NSString *) = ^NSInteger(id object, NSString *name) {
        @try {
            SEL selector = NSSelectorFromString(name);
            if (!CV3TargetRespondsToSelector(object, selector)) return -1;
            return CV3InvokeBool(object, selector, NO) ? 1 : 0;
        } @catch (__unused NSException *e) { return -1; }
    };
    id lock = nil, cc = nil, cover = nil;
    @try {
        lock = CV3InvokeObject(CV3ClassNamed(@"SBLockScreenManager"), @selector(sharedInstance));
        cc = CV3InvokeObject(CV3ClassNamed(@"SBControlCenterController"), @selector(sharedInstance));
        cover = CV3InvokeObject(CV3ClassNamed(@"SBCoverSheetPresentationManager"), @selector(sharedInstance));
    } @catch (__unused NSException *e) {}
    CGPoint location = [gesture locationInView:self];
    CV3LogToFile(@"[EdgeSystemEnvironment] trace=%lu phase=%@ coverSheetCached=%d coverSheetViewAttached=%d blockReason=%@",
        (unsigned long)self.edgeEnvironmentSequence, phase, CV3GestureCoverSheetPresented,
        CV3GestureCoverSheetController.viewIfLoaded.window != nil, [self edgeEnvironmentBlockReason] ?: @"none");
    CGPoint translation = CGPointZero, velocity = CGPointZero;
    if ([gesture isKindOfClass:UIPanGestureRecognizer.class]) {
        translation = [(UIPanGestureRecognizer *)gesture translationInView:self];
        velocity = [(UIPanGestureRecognizer *)gesture velocityInView:self];
    }
    CV3LogToFile(@"[EdgeGestureEnvironment] trace=%lu phase=%@ decision=%@ state=%ld enabled=%d edge=%lu lockCached=%d uiLocked=%ld locked=%ld controlCenterPresented=%ld coverSheetVisible=%ld suppressedBySystem=%d windowHidden=%d windowAlpha=%.3f panelShowing=%d animating=%d sceneActivation=%ld orientation=%ld bounds=%@ safeArea=%@ location=%@ translation=%@ velocity=%@ workspace=%@ recognizerView=%@ unknown=-1",
        (unsigned long)self.edgeEnvironmentSequence, phase, decision, (long)gesture.state, gesture.enabled,
        (unsigned long)self.systemEdgePan.edges, CV3LockScreenPresented,
        (long)readFlag(lock, @"isUILocked"), (long)readFlag(lock, @"isLocked"),
        (long)readFlag(cc, @"isPresented"), (long)readFlag(cover, @"isAnyCoverSheetVisible"),
        self.isSuppressedBySystem, self.hidden, self.alpha, self.isPanelShowing, self.isAnimating,
        self.windowScene ? (long)self.windowScene.activationState : -1L, (long)self.targetOrientation,
        NSStringFromCGRect(self.bounds), NSStringFromUIEdgeInsets(self.safeAreaInsets),
        NSStringFromCGPoint(location), NSStringFromCGPoint(translation), NSStringFromCGPoint(velocity),
        [self currentActiveBundleID] ?: @"unknown", NSStringFromClass(gesture.view.class));
}

- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)gesture {
    if (gesture == self.systemEdgePan) {
        self.edgeEnvironmentSequence += 1;
        self.edgeEnvironmentCancelled = NO;
        NSString *blocked = [self edgeEnvironmentBlockReason];
        if (blocked) {
            [self recordEdgeEnvironment:@"shouldBegin" gesture:gesture decision:blocked];
            return NO;
        }
        if (self.isPanelShowing) {
            [self recordEdgeEnvironment:@"shouldBegin" gesture:gesture decision:@"reject.panelShowing"];
            return NO;
        }

        // Keep hit filtering in the launcher's Scene coordinate space. Global
        // screen coordinates can retain portrait dimensions while the active
        // application is already landscape, rejecting a valid right-edge pan.
        CGPoint location = [gesture locationInView:self];
        UIEdgeInsets safeArea = self.safeAreaInsets;

        CGSize screenSize = self.bounds.size;
        
        // 根据当前的 edges 动态拦截
        if (self.systemEdgePan.edges == UIRectEdgeLeft || self.systemEdgePan.edges == UIRectEdgeRight) {
            // 垂直方向边缘（Portrait）: 限制 Y 轴
            if (location.y < safeArea.top + 10 || location.y > screenSize.height - safeArea.bottom - 10) {
                [self recordEdgeEnvironment:@"shouldBegin" gesture:gesture decision:@"reject.verticalRange"];
                return NO;
            }
        } else if (self.systemEdgePan.edges == UIRectEdgeTop || self.systemEdgePan.edges == UIRectEdgeBottom) {
            // 水平方向边缘（Landscape）: 限制 X 轴
            if (location.x < safeArea.left + 10 || location.x > screenSize.width - safeArea.right - 10) {
                [self recordEdgeEnvironment:@"shouldBegin" gesture:gesture decision:@"reject.horizontalRange"];
                return NO;
            }
        }
        
        [self recordEdgeEnvironment:@"shouldBegin" gesture:gesture decision:@"allow"];
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
        return NO;
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
        
        // 初始化边缘预警层
        self.triggerPreviewLayer = [CAGradientLayer layer];
        self.triggerPreviewLayer.type = kCAGradientLayerRadial;
        self.triggerPreviewLayer.colors = @[(id)[UIColor clearColor].CGColor, (id)[UIColor clearColor].CGColor];
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
        id ws = [CV3ClassNamed(@"LSApplicationWorkspace") defaultWorkspace];
        CV3InvokeObject1(ws, @selector(addObserver:), [CV3AppObserver sharedObserver]);
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
        SBSystemGestureManager *manager = [CV3ClassNamed(@"SBSystemGestureManager") mainDisplayManager];
        [manager addGestureRecognizer:self.systemEdgePan withType:112];
    } @catch (NSException *e) {}
    
    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleDimmingTap:)];
    tap.delegate = self;
    [self addGestureRecognizer:tap];
    
    self.bezierContainer = [[UIView alloc] initWithFrame:bounds];
    self.bezierContainer.alpha = 0;
    self.bezierContainer.userInteractionEnabled = NO;
    self.bezierContainer.autoresizingMask = UIViewAutoresizingNone;
    [self.rootViewController.view addSubview:self.bezierContainer];
    
    self.bezierBlur = [[UIVisualEffectView alloc] initWithEffect:nil];
    self.bezierBlur.frame = bounds;
    self.bezierBlur.autoresizingMask = UIViewAutoresizingNone;
    [self.bezierContainer addSubview:self.bezierBlur];
    self.bezierLayer = [CAShapeLayer layer];
    // 贝塞尔层只负责承载手势形变，不显示额外的色块。
    self.bezierLayer.fillColor = [UIColor clearColor].CGColor;
    self.bezierBlur.layer.mask = self.bezierLayer; 
    
    self.panelContainer = [[UIView alloc] initWithFrame:CGRectMake(0, 0, CV3Style.panelW, CV3Style.panelH)];
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
    self.appPanel.layer.cornerRadius = CV3Style.cornerRadius;
    if (@available(iOS 13.0, *)) {
        self.appPanel.layer.cornerCurve = kCACornerCurveContinuous;
    }
    self.appPanel.layer.masksToBounds = YES;
    self.appPanel.layer.borderWidth = 0.5; // 建议：微增描边宽度以强化边缘抗锯齿
    self.appPanel.layer.borderColor = [[UIColor labelColor] colorWithAlphaComponent:0.2].CGColor;
    
    // 建议：注入三线性过滤 (Trilinear Filtering) 消除次像素位移锯齿
    self.appPanel.layer.magnificationFilter = kCAFilterTrilinear;
    self.appPanel.layer.minificationFilter = kCAFilterTrilinear;
    
    // 1. 对比度增强层 (Contrast Booster): 极淡的黑色，用于压住背景杂色，让 App 图标更浮出
    self.contrastBackdrop = [[UIView alloc] initWithFrame:self.appPanel.bounds];
    self.contrastBackdrop.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.025];
    self.contrastBackdrop.userInteractionEnabled = NO;
    [self.appPanel.contentView addSubview:self.contrastBackdrop];



    [self.panelContainer addSubview:self.appPanel];
    [self refreshGlassAccentSurfaces];
    [self installMainPanelLiquidGlass];



#pragma mark - Search Bar Setup
    UIView *searchContainer = [[UIView alloc] initWithFrame:CGRectMake(15, 14, CV3Style.panelW - 30, 36)];
    searchContainer.backgroundColor = [UIColor clearColor];
    [self.appPanel.contentView addSubview:searchContainer];

    // 液态背景层
    self.searchBackground = [CAShapeLayer layer];
    self.searchBackground.frame = searchContainer.bounds;
    self.searchBackground.path = [UIBezierPath bezierPathWithRoundedRect:searchContainer.bounds cornerRadius:10].CGPath;
    // Liquid Glass：搜索框玻璃底（公用配方，圆角随搜索框）
    CV3LiquidGlassEnsureBackdrop(searchContainer, @"CV3SearchFieldLiquidGlassBackdrop", CV3LiquidGlassRecipeControl(), 10.0, NULL);
    self.searchBackground.fillColor = [[UIColor labelColor] colorWithAlphaComponent:0.06].CGColor;
    self.searchBackground.strokeColor = [[UIColor labelColor] colorWithAlphaComponent:0.1].CGColor;
    self.searchBackground.lineWidth = 0.4;
    [searchContainer.layer addSublayer:self.searchBackground];
    
    self.searchField = [[UITextField alloc] initWithFrame:CGRectInset(searchContainer.bounds, 10, 0)];
    self.searchField.placeholder = @"搜索应用...";
    self.searchField.textColor = [UIColor labelColor];
    self.searchField.font = [UIFont systemFontOfSize:14];
    self.searchField.tintColor = [UIColor labelColor];
    // Apple Design Rule 15: 小字号 +0.15pt Tracking 提升精致可读性
    self.searchField.attributedPlaceholder = [[NSAttributedString alloc] initWithString:@"搜索应用..." attributes:@{
        NSForegroundColorAttributeName: [UIColor secondaryLabelColor],
        NSKernAttributeName: @(0.15)
    }];
    [self.searchField addTarget:self action:@selector(searchTextChanged:) forControlEvents:UIControlEventEditingChanged];
    self.searchField.delegate = self;
    self.searchField.returnKeyType = UIReturnKeySearch;
    self.searchField.clearButtonMode = UITextFieldViewModeWhileEditing; // 启用清空按钮
    [searchContainer addSubview:self.searchField];

#pragma mark - No Results Label Setup
    self.noResultsLabel = [[UILabel alloc] initWithFrame:CGRectMake(0, 114, CV3Style.panelW, 40)];
    self.noResultsLabel.attributedText = [[NSAttributedString alloc] initWithString:@"未找到相关应用" attributes:@{
        NSForegroundColorAttributeName: [UIColor secondaryLabelColor],
        NSFontAttributeName: [UIFont systemFontOfSize:14 weight:UIFontWeightMedium],
        NSKernAttributeName: @(0.15)
    }];
    self.noResultsLabel.textAlignment = NSTextAlignmentCenter;
    self.noResultsLabel.hidden = YES;
    [self.appPanel.contentView addSubview:self.noResultsLabel];

    self.selectedCategory = @"全部";
    self.categoryBar = [[UIScrollView alloc] initWithFrame:CGRectMake(15, 60, CV3Style.panelW - 30, 40)];
    self.categoryBar.showsHorizontalScrollIndicator = NO;
    self.categoryBar.backgroundColor = [UIColor clearColor];
    self.categoryBar.delegate = self;
    [self.appPanel.contentView addSubview:self.categoryBar];

    self.resizingHandle = [[CV3ResizeHandleView alloc] initWithFrame:CGRectMake(CV3Style.panelW - 40, CV3Style.panelH - 40, 40, 40)];
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
    self.collectionView = [[UICollectionView alloc] initWithFrame:CGRectMake(0, 104, CV3Style.panelW, CV3Style.panelH-104) collectionViewLayout:layout];
    self.collectionView.dataSource = self; self.collectionView.delegate = self;
    self.collectionView.backgroundColor = [UIColor clearColor];
    self.collectionView.delaysContentTouches = NO; // 关键：禁用触碰延迟实现即时反馈
    self.collectionView.showsVerticalScrollIndicator = NO;   // 隐藏纵向滚动条
    self.collectionView.showsHorizontalScrollIndicator = NO; // 隐藏横向滚动条
    self.collectionView.keyboardDismissMode = UIScrollViewKeyboardDismissModeOnDrag; // 滚动时自动收起键盘
    [self.collectionView registerClass:[CV3AppCell class] forCellWithReuseIdentifier:@"C"];
    [self.appPanel.contentView addSubview:self.collectionView];

    // 长按后可将应用拖出面板创建分屏。
    UILongPressGestureRecognizer *pinLongPress = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(handleAppLongPress:)];
    pinLongPress.minimumPressDuration = 0.6;
    pinLongPress.allowableMovement = kCV3AppDragLongPressAllowableMovement;
    pinLongPress.delegate = self;
    [self.collectionView addGestureRecognizer:pinLongPress];

}


- (CGRect)splitDropPreviewFrameForCenter:(CGPoint)center {
    CGRect frame = [CV3FloatingAppWindow initialFrameForBundleID:self.draggedAppInfo.bundleId
                                                         center:center
                                                    windowScene:self.windowScene];
    // The drop preview is the user's only prediction of the window they are
    // about to create, so it asks the same presentation decision that creation
    // asks. Deriving the axis here from the display orientation instead is what
    // let a portrait App promise a landscape frame and then open portrait.
    UIInterfaceOrientation displayOrientation = CV3TrustedInterfaceOrientation(self.windowScene);
    CV3InitialPresentation presentation =
        CV3ResolveInitialPresentation(self.draggedAppInfo.bundleId, displayOrientation);
    CV3LogToFile(@"[SplitPreviewTrace] phase=frame bundle=%@ center=%@ frame=%@ axis=%dx%d displayOrientation=%ld contentOrientation=%ld prefersLandscape=%d requiresLandscape=%d",
                 self.draggedAppInfo.bundleId ?: @"nil",
                 NSStringFromCGPoint(center),
                 NSStringFromCGRect(frame),
                 (int)(frame.size.width + 0.5), (int)(frame.size.height + 0.5),
                 (long)displayOrientation,
                 (long)presentation.contentOrientation,
                 presentation.prefersLandscape,
                 presentation.requiresLandscape);
    return frame;
}

- (void)layoutSplitDropPreviewLayer {
    if (!self.splitDropPreviewView || !self.splitDropPreviewLayer) return;

    CGRect bounds = self.splitDropPreviewView.bounds;
    CGRect pathBounds = CGRectMake(0, 0, bounds.size.width, bounds.size.height);
    CGFloat cornerRadius = MIN(CV3Style.floatingChromeCornerRadius, MIN(bounds.size.width, bounds.size.height) * 0.5);
    UIBezierPath *path = [UIBezierPath bezierPathWithRoundedRect:CGRectInset(pathBounds, 2.0, 2.0)
                                                    cornerRadius:cornerRadius];
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    self.splitDropPreviewLayer.bounds = pathBounds;
    self.splitDropPreviewLayer.position = CGPointMake(CGRectGetMidX(bounds), CGRectGetMidY(bounds));
    self.splitDropPreviewLayer.path = path.CGPath;
    self.splitDropPreviewLayer.cornerRadius = cornerRadius;
    [self.splitDropPreviewLayer setAffineTransform:CGAffineTransformIdentity];
    [CATransaction commit];
}

- (void)showSplitDropPreviewAtCenter:(CGPoint)center {
    CGRect targetFrame = [self splitDropPreviewFrameForCenter:center];
    if (!self.splitDropPreviewView) {
        self.splitDropPreviewView = [[UIView alloc] initWithFrame:targetFrame];
        self.splitDropPreviewView.userInteractionEnabled = NO;
        self.splitDropPreviewView.backgroundColor = [[UIColor colorWithRed:0.0 green:0.62 blue:1.0 alpha:1.0] colorWithAlphaComponent:0.08];
        self.splitDropPreviewView.alpha = 0.0;
        self.splitDropPreviewView.layer.shadowColor = [UIColor cyanColor].CGColor;
        self.splitDropPreviewView.layer.shadowOpacity = 0.22;
        self.splitDropPreviewView.layer.shadowRadius = 18.0;
        self.splitDropPreviewView.layer.shadowOffset = CGSizeMake(0, 12);
        if (@available(iOS 13.0, *)) {
            self.splitDropPreviewView.layer.cornerCurve = kCACornerCurveContinuous;
        }

        self.splitDropPreviewLayer = [CAShapeLayer layer];
        self.splitDropPreviewLayer.fillColor = [UIColor clearColor].CGColor;
        self.splitDropPreviewLayer.strokeColor = [[UIColor colorWithRed:0.0 green:0.75 blue:1.0 alpha:1.0] colorWithAlphaComponent:0.92].CGColor;
        self.splitDropPreviewLayer.lineWidth = 2.0;
        self.splitDropPreviewLayer.lineDashPattern = @[@10, @7];
        self.splitDropPreviewLayer.lineCap = kCALineCapRound;
        self.splitDropPreviewLayer.lineJoin = kCALineJoinRound;
        [self.splitDropPreviewView.layer addSublayer:self.splitDropPreviewLayer];

        CABasicAnimation *dashPhase = [CABasicAnimation animationWithKeyPath:@"lineDashPhase"];
        dashPhase.fromValue = @0.0;
        dashPhase.toValue = @34.0;
        dashPhase.duration = 1.15;
        dashPhase.repeatCount = HUGE_VALF;
        dashPhase.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionLinear];
        [self.splitDropPreviewLayer addAnimation:dashPhase forKey:@"dashPhase"];

        [self insertSubview:self.splitDropPreviewView belowSubview:self.panelContainer];
        [self layoutSplitDropPreviewLayer];

        self.splitDropPreviewView.transform = CGAffineTransformMakeScale(0.94, 0.94);
        [UIView animateWithDuration:0.18
                              delay:0
                            options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction
                         animations:^{
            self.splitDropPreviewView.alpha = 1.0;
            self.splitDropPreviewView.transform = CGAffineTransformIdentity;
        } completion:nil];
    } else {
        if (self.draggedIconView.superview) {
            [self.draggedIconView.superview bringSubviewToFront:self.draggedIconView];
        }
        [UIView animateWithDuration:0.12
                              delay:0
                            options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction
                         animations:^{
            self.splitDropPreviewView.frame = targetFrame;
        } completion:nil];
        [self layoutSplitDropPreviewLayer];
    }
}

- (void)hideSplitDropPreviewAnimated:(BOOL)animated {
    UIView *preview = self.splitDropPreviewView;
    if (!preview) return;
    self.splitDropPreviewView = nil;
    self.splitDropPreviewLayer = nil;

    void (^removeBlock)(void) = ^{
        [preview removeFromSuperview];
    };
    if (!animated) {
        removeBlock();
        return;
    }

    [UIView animateWithDuration:0.16
                          delay:0
                        options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction
                     animations:^{
        preview.alpha = 0.0;
        preview.transform = CGAffineTransformMakeScale(0.96, 0.96);
    } completion:^(BOOL finished) {
        removeBlock();
    }];
}

// 分屏预热：后台预启动（suspended）目标 App，幂等且低代价——用户拖拽开始即调用。
// 背景（2026-10-16 实测）：分屏耗时 80%+ 是"等 App 进程启动+场景建立"（王者 ~840ms / 抖音 ~1620ms），
// 提前启动后松手时只剩挂载(≈10ms)+渲染——分屏因此接近"秒开"。
static void CV3PreWarmAppForSplit(NSString *bundleID) {
    if (bundleID.length == 0) return;
    // Screen Time 限额中：不预热（分屏闸门会拦截，预热只会白启动进程）
    if (!CV3ScreenTimeGateBundleID(bundleID, @"PreWarm", NO, nil)) {
        CV3LogToFile(@"[PreWarm] ScreenTime 限额中，跳过分屏预热: %@", bundleID);
        return;
    }
    dispatch_async(dispatch_get_main_queue(), ^{
        @try {
            [[UIApplication sharedApplication] launchApplicationWithIdentifier:bundleID suspended:YES];
            CV3LogToFile(@"[PreWarm] phase=splitPreLaunch bundle=%@", bundleID);
        } @catch (NSException *e) {
            CV3LogToFile(@"[PreWarm] phase=splitPreLaunch.failed bundle=%@ error=%@", bundleID, e);
        }
    });
}

- (void)handleAppLongPress:(UILongPressGestureRecognizer *)gesture {
    CGPoint pointInCollection = [gesture locationInView:self.collectionView];
    CGPoint pointInPanel = [gesture locationInView:self.panelContainer];
    
    if (gesture.state == UIGestureRecognizerStateBegan) {
        CGPoint scrollVelocity = [self.collectionView.panGestureRecognizer velocityInView:self.collectionView];
        BOOL isScrollingApps = self.collectionView.dragging ||
                               self.collectionView.decelerating ||
                               fabs(scrollVelocity.y) > kCV3AppDragScrollVelocityGate;
        if (isScrollingApps) {
            self.draggedIconView = nil;
            self.draggedAppInfo = nil;
            return;
        }

        [self hideSplitDropPreviewAnimated:NO];
        NSIndexPath *indexPath = [self.collectionView indexPathForItemAtPoint:pointInCollection];
        if (indexPath && indexPath.item < self.filteredApps.count) {
            CV3AppCell *cell = (CV3AppCell *)[self.collectionView cellForItemAtIndexPath:indexPath];
            self.draggedAppInfo = self.filteredApps[indexPath.item];
            CV3AppPanelProtectionState protectionState = CV3AppPanelProtectionStateForBundleID(self.draggedAppInfo.bundleId);
            if (protectionState != CV3AppPanelProtectionStateNone) {
                CV3LogToFile(@"[Launcher] 已阻止主App面板长按操作: 目标=%@, 原因=%@",
                             self.draggedAppInfo.bundleId,
                             CV3AppPanelProtectionReason(protectionState) ?: @"Unknown");
                self.draggedAppInfo = nil;
                [self.collectionView reloadData];
                return;
            }

            CV3ExitExposeModeIfNeeded(nil, NO);

            // 分屏预热（2026-10-16）：拖拽一开始就在后台预启动目标 App。用户从长按激活到松手
            // 通常还需 0.5~2s——足够 App 完成“进程启动+场景建立”（实测占分屏总耗时 80%+），
            // 松手后只剩挂载(≈10ms)+渲染——实现“分屏接近秒开”。幂等：已启动的 App 无副作用。
            CV3PreWarmAppForSplit(self.draggedAppInfo.bundleId);

            // 锁定 CollectionView 滚动，防止拖拽时面板跟着滑动
            self.collectionView.scrollEnabled = NO;
            
            // 创建拖拽的浮动图标
            if (cell.iconView.image) {
                self.draggedIconView = [[UIImageView alloc] initWithImage:cell.iconView.image];
                CGRect iconFrameInPanel = [self.panelContainer convertRect:cell.iconView.bounds fromView:cell.iconView];
                self.draggedIconView.frame = iconFrameInPanel;
                self.dragStartCenter = self.draggedIconView.center;
                
                // 在 panelContainer 坐标系内拖拽，让图标继承横屏旋转并保持与视觉位置一致。
                self.dragTouchOffset = CGPointMake(pointInPanel.x - self.dragStartCenter.x, pointInPanel.y - self.dragStartCenter.y);
                
                [self.panelContainer addSubview:self.draggedIconView];
                
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
            self.draggedIconView.center = CGPointMake(pointInPanel.x - self.dragTouchOffset.x, pointInPanel.y - self.dragTouchOffset.y);

            BOOL isOutside = !CGRectContainsPoint(self.panelContainer.bounds, pointInPanel);
            if (isOutside) {
                CGPoint previewCenter = [self.panelContainer convertPoint:self.draggedIconView.center toView:self];
                [self showSplitDropPreviewAtCenter:previewCenter];
            } else {
                [self hideSplitDropPreviewAnimated:YES];
            }
        }
    } else if (gesture.state == UIGestureRecognizerStateEnded || gesture.state == UIGestureRecognizerStateCancelled) {
        // 恢复 CollectionView 滚动
        self.collectionView.scrollEnabled = YES;
        [self hideSplitDropPreviewAnimated:YES];
        
        if (self.draggedIconView && self.draggedAppInfo) {
            CV3AppPanelProtectionState protectionState = CV3AppPanelProtectionStateForBundleID(self.draggedAppInfo.bundleId);
            if (protectionState != CV3AppPanelProtectionStateNone) {
                CV3LogToFile(@"[Launcher] 已阻止主App面板拖拽完成操作: 目标=%@, 原因=%@",
                             self.draggedAppInfo.bundleId,
                             CV3AppPanelProtectionReason(protectionState) ?: @"Unknown");
                [UIView animateWithDuration:0.25 animations:^{
                    self.draggedIconView.alpha = 0.0;
                    self.draggedIconView.transform = CGAffineTransformMakeScale(0.1, 0.1);
                } completion:^(BOOL finished) {
                    [self hideSplitDropPreviewAnimated:NO];
                    [self.draggedIconView removeFromSuperview];
                    self.draggedIconView = nil;
                    self.draggedAppInfo = nil;
                    [self.collectionView reloadData];
                }];
                return;
            }

            // 判断是否拖出面板边界。这里直接使用 panelContainer 坐标，避免横屏 transform 下的换算误差。
            BOOL isOutside = !CGRectContainsPoint(self.panelContainer.bounds, pointInPanel);
            
            if (isOutside && gesture.state == UIGestureRecognizerStateEnded) {
                CV3LogToFile(@"[Info] 拖拽出面板，使用自带 App Hosting 开启: %@", self.draggedAppInfo.bundleId);
                
                NSString *bundleID = [self.draggedAppInfo.bundleId copy];
                CGPoint spawnPoint = [self.draggedIconView.superview convertPoint:self.draggedIconView.center toView:nil];
                dispatch_async(dispatch_get_main_queue(), ^{
                    CV3AppPanelProtectionState asyncProtectionState = CV3AppPanelProtectionStateForBundleID(bundleID);
                    if (asyncProtectionState != CV3AppPanelProtectionStateNone) {
                        CV3LogToFile(@"[Launcher] 已阻止主App面板异步分屏创建: 目标=%@, 原因=%@",
                                     bundleID,
                                     CV3AppPanelProtectionReason(asyncProtectionState) ?: @"Unknown");
                        [self.collectionView reloadData];
                        return;
                    }

                    // Screen Time 限额闸门：命中则呈现系统拦截页，不再创建分屏
                    if (!CV3ScreenTimeGateBundleID(bundleID, @"SplitDrop", YES, self.windowScene)) {
                        [self.collectionView reloadData];
                        return;
                    }

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
                        // 使用实际拖拽图标的屏幕位置创建分屏，横屏下不会退回竖屏坐标。
                        CV3FloatingAppWindow *floatingWindow = [[CV3FloatingAppWindow alloc] initWithBundleID:bundleID center:spawnPoint windowScene:self.windowScene];
                        // Preserve the orientation selected by the hosted app.
                        // The phone may remain portrait while a landscape-only
                        // game owns a landscape floating canvas.
                        [floatingWindows addObject:floatingWindow];
                        [floatingWindow setWindowFocused:YES];
                        CV3RefreshFloatingHomeBarAfterPresentation(floatingWindow);
                        [[NSNotificationCenter defaultCenter] postNotificationName:CV3FloatingWindowsDidChangeNotification object:nil];
                    }
                });
                
                // 移除浮动视图并隐藏面板
                [UIView animateWithDuration:0.3 animations:^{
                    self.draggedIconView.alpha = 0;
                    self.draggedIconView.transform = CGAffineTransformMakeScale(0.1, 0.1);
                } completion:^(BOOL finished) {
                    [self hideSplitDropPreviewAnimated:NO];
                    [self.draggedIconView removeFromSuperview];
                    self.draggedIconView = nil;
                    self.draggedAppInfo = nil;
                    [self loadAppsAsync];
                }];
                
                [self animateSpotlight:NO fromPoint:self.panelContainer.center velocity:0.0];
                
            } else {
                // 拖回面板或手势取消时只回弹，不修改应用状态。
                [UIView animateWithDuration:0.3 delay:0 usingSpringWithDamping:0.7 initialSpringVelocity:0.5 options:0 animations:^{
                    self.draggedIconView.center = self.dragStartCenter;
                    self.draggedIconView.transform = CGAffineTransformIdentity;
                } completion:^(BOOL finished) {
                    [self hideSplitDropPreviewAnimated:NO];
                    [self.draggedIconView removeFromSuperview];
                    self.draggedIconView = nil;
                    self.draggedAppInfo = nil;
                    [self.collectionView reloadData];
                }];
            }
        }
    }
}

- (void)handleCategoryTap:(UIButton *)sender {
    CV3ExitExposeModeIfNeeded(nil, NO);
    [self.searchField resignFirstResponder];
    
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
            BOOL isSuggested = CV3GetTimePriorityForCategory(btnCatName) > 0;
            [self applyGlassAccentToCategoryButton:btn selected:isSelected suggested:isSuggested];
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
        [self applyGlassAccentToCategoryButton:btn selected:isSelected suggested:isSuggested];
        
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
        CV3ExitExposeModeIfNeeded(nil, NO);
        [self.searchField resignFirstResponder];
        if (location.y > 45.0) { return; }
        self.hasBeenMoved = YES;
        [UIView animateWithDuration:kCV3PanelDragLiftDuration
                              delay:0
             usingSpringWithDamping:kCV3PanelDragLiftDamping
              initialSpringVelocity:kCV3PanelDragLiftVelocity
                            options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction | UIViewAnimationOptionCurveEaseInOut
                         animations:^{
            CGAffineTransform currentTransform = self.panelContainer.transform;
            self.panelContainer.transform = CGAffineTransformScale(currentTransform, kCV3PanelDragLiftScale, kCV3PanelDragLiftScale);
        } completion:nil];
    }

    if (gesture.state == UIGestureRecognizerStateChanged) {
        CGPoint translation = [gesture translationInView:self.panelContainer.superview];
        CGPoint newCenter = CGPointMake(self.panelContainer.center.x + translation.x, self.panelContainer.center.y + translation.y);
        
        CGRect bounds = self.bounds;
        CGRect panelBounds = self.panelContainer.bounds;
        CGFloat halfW = (panelBounds.size.width * kCV3PanelDragLiftScale) / 2.0;
        CGFloat halfH = (panelBounds.size.height * kCV3PanelDragLiftScale) / 2.0;
        
        newCenter.x = MAX(halfW - panelBounds.size.width * 0.4, MIN(bounds.size.width - halfW + panelBounds.size.width * 0.4, newCenter.x));
        newCenter.y = MAX(halfH - panelBounds.size.height * 0.4, MIN(bounds.size.height - halfH + panelBounds.size.height * 0.4, newCenter.y));
        
        self.panelContainer.center = newCenter;
        [gesture setTranslation:CGPointZero inView:self.panelContainer.superview];
    }
    if (gesture.state == UIGestureRecognizerStateEnded || gesture.state == UIGestureRecognizerStateCancelled) {
        CALayer *presentationLayer = self.panelContainer.layer.presentationLayer;
        if (presentationLayer) {
            self.panelContainer.center = presentationLayer.position;
            self.panelContainer.transform = CATransform3DGetAffineTransform(presentationLayer.transform);
        }

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

        CGPoint releaseVelocity = [gesture velocityInView:self.panelContainer.superview];
        CGFloat springVelocity = CV3ClampedSpringVelocity(hypot(releaseVelocity.x, releaseVelocity.y),
                                                          kCV3PanelDragReleaseVelocityDivisor,
                                                          kCV3PanelDragReleaseMinVelocity,
                                                          kCV3PanelDragReleaseMaxVelocity);

        [UIView animateWithDuration:kCV3PanelDragReleaseDuration
                              delay:0
             usingSpringWithDamping:kCV3PanelDragReleaseDamping
              initialSpringVelocity:springVelocity
                            options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction | UIViewAnimationOptionCurveEaseInOut
                         animations:^{
            self.panelContainer.transform = CGAffineTransformScale(current, 1.0 / kCV3PanelDragLiftScale, 1.0 / kCV3PanelDragLiftScale);
            self.appPanel.alpha = 1.0; // 恢复全透明度
            self.panelContainer.center = targetCenter;
        } completion:nil];
    }
}

- (void)handleDimmingTap:(UITapGestureRecognizer *)tap {
    // Defensive second gate for recognizers admitted while the panel was moving.
    CGPoint point = [tap locationInView:self];
    CGPoint pointInPanel = [self convertPoint:point toView:self.panelContainer];
    CALayer *presentation = self.panelContainer.layer.presentationLayer;
    BOOL insideModel = CGRectContainsPoint(self.panelContainer.bounds, pointInPanel);
    BOOL insidePresentation = presentation && CGRectContainsPoint(presentation.frame, point);
    if (insideModel || insidePresentation) {
        CV3LogToFile(@"[LauncherTouch] phase=dimming.ignore point=%@ insideModel=%d insidePresentation=%d",
                     NSStringFromCGPoint(point), insideModel, insidePresentation);
        return;
    }
    CV3ExitExposeModeIfNeeded(nil, NO);
    // Forensics: observed 7/7 dismissals carried point={0,0} — a location a
    // real finger tap never produces. Record the fingerprint so a ghost tap
    // (no touches / degenerate location) can be told apart from a real one.
    BOOL degenerate = CGPointEqualToPoint(point, CGPointZero);
    CV3LogToFile(@"[LauncherTouch] phase=dimming.dismiss point=%@ degenerate=%d touches=%lu state=%ld",
                 NSStringFromCGPoint(point), degenerate, (unsigned long)tap.numberOfTouches, (long)tap.state);
    [self animateSpotlight:NO fromPoint:self.panelContainer.center velocity:0.0];
}

- (void)handleResize:(UIPanGestureRecognizer *)gesture {
    if (!gesture || gesture.state == UIGestureRecognizerStateBegan) {
        CV3ExitExposeModeIfNeeded(nil, NO);
        [self.searchField resignFirstResponder];
    }
    // 增加 resize 锁
    self.isProcessing = YES; 

    // 建议：把手动态激活 (Handle Flare)
    // 根据手势状态切换把手视觉样式
    if (gesture.state == UIGestureRecognizerStateBegan) {
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
        CGFloat breath = CV3Style.safeAreaBreath;
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
                maxH = rootAllowedHalfH * 2.0;
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

        // 拖动到尺寸极限时使用颜色提示。
        BOOL atLimit = (rawW < minW || rawH < minH || rawW > maxW || rawH > maxH);
        if (atLimit && gesture.state == UIGestureRecognizerStateChanged) {
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
    CGFloat collectionViewY = hideCategories ? 60.0 : 104.0;

    // 动态调整搜索框和 CollectionView
    UIView *searchContainer = self.searchField.superview;
    searchContainer.frame = CGRectMake(15, 14, updatedBounds.size.width - 30, 36);
    self.searchField.frame = CGRectInset(searchContainer.bounds, 10, 0);
    self.searchBackground.frame = searchContainer.bounds;
    self.searchBackground.path = [UIBezierPath bezierPathWithRoundedRect:searchContainer.bounds cornerRadius:10].CGPath;
    CV3LiquidGlassEnsureBackdrop(searchContainer, @"CV3SearchFieldLiquidGlassBackdrop", CV3LiquidGlassRecipeControl(), 10.0, NULL);

    self.categoryBar.frame = CGRectMake(15, 60, updatedBounds.size.width - 30, 40);
    self.collectionView.frame = CGRectMake(0, collectionViewY, updatedBounds.size.width, updatedBounds.size.height - collectionViewY);
    self.noResultsLabel.frame = CGRectMake(0, 114, updatedBounds.size.width, 40);

    [self updateResizingHandleFrame];

    // 关键修复：同步更新所有装饰层并禁用隐式动画，消除“追赶感”和“固定宽高”问题
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    
    self.contrastBackdrop.frame = self.appPanel.bounds;
    [self syncMainPanelLiquidGlassGeometry];
    
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

- (CGPoint)calculateTargetCenter {
    UIEdgeInsets safe = self.safeAreaInsets;
    CGRect bounds = self.bounds;
    CGFloat w = bounds.size.width;
    CGFloat h = bounds.size.height;
    
    // 计算安全区域内的有效绘图区
    CGRect safeBounds = CGRectMake(safe.left + CV3Style.safeAreaBreath, 
                                   safe.top + CV3Style.safeAreaBreath, 
                                   w - safe.left - safe.right - 2 * CV3Style.safeAreaBreath, 
                                   h - safe.top - safe.bottom - 2 * CV3Style.safeAreaBreath);
                                   
    return CGPointMake(CGRectGetMidX(safeBounds), CGRectGetMidY(safeBounds));
}

- (CGPoint)clampedPanelCenterForCenter:(CGPoint)center {
    CGRect bounds = self.bounds;
    UIEdgeInsets safe = self.safeAreaInsets;
    CGFloat breath = CV3Style.safeAreaBreath;
    CGRect safeFrame = CGRectMake(safe.left + breath,
                                  safe.top + breath,
                                  bounds.size.width - safe.left - safe.right - 2.0 * breath,
                                  bounds.size.height - safe.top - safe.bottom - 2.0 * breath);

    CGRect panelBounds = self.panelContainer.bounds;
    CGSize sizeInRoot = CGRectApplyAffineTransform(panelBounds, self.panelContainer.transform).size;
    CGFloat rootHalfW = fabs(sizeInRoot.width) / 2.0;
    CGFloat rootHalfH = fabs(sizeInRoot.height) / 2.0;

    if (CGRectGetWidth(safeFrame) < rootHalfW * 2.0) {
        center.x = CGRectGetMidX(safeFrame);
    } else {
        center.x = MAX(CGRectGetMinX(safeFrame) + rootHalfW,
                       MIN(CGRectGetMaxX(safeFrame) - rootHalfW, center.x));
    }

    if (CGRectGetHeight(safeFrame) < rootHalfH * 2.0) {
        center.y = CGRectGetMidY(safeFrame);
    } else {
        center.y = MAX(CGRectGetMinY(safeFrame) + rootHalfH,
                       MIN(CGRectGetMaxY(safeFrame) - rootHalfH, center.y));
    }

    return center;
}

- (void)updateResizingHandleFrame {
    // 确保把手始终在面板的右下角
    CGRect bounds = self.panelContainer.bounds;
    self.resizingHandle.bounds = CGRectMake(0, 0, 40, 40);
    self.resizingHandle.center = CGPointMake(bounds.size.width - 20, bounds.size.height - 20);
}

- (void)applySceneRotationContext:(CV3SceneRotationContext)context force:(BOOL)force {
    if (!CV3IsValidInterfaceOrientation(context.orientation)) return;

    BOOL currentIsLandscape = self.bounds.size.width > self.bounds.size.height;
    BOOL needsApply = CV3SceneRotationContextNeedsApply(self.targetOrientation,
                                                       self.baseRotationTransform,
                                                       context,
                                                       force) ||
                      currentIsLandscape != context.isLandscape;
    if (!needsApply && !CGRectIsEmpty(context.sceneBounds) && !CGRectEqualToRect(self.frame, context.sceneBounds)) {
        needsApply = YES;
    }
    if (!needsApply) return;

    BOOL orientationChanged = self.targetOrientation != context.orientation;
    if (orientationChanged) {
        if (self.searchField.inputAccessoryView) {
            self.searchField.inputAccessoryView = nil;
            [self.searchField reloadInputViews];
        }
        if (self.searchField.isFirstResponder) {
            [self.searchField resignFirstResponder];
        }
    }

    self.targetOrientation = context.orientation;
    self.baseRotationTransform = context.transform;

    if (context.scene && self.windowScene != context.scene) {
        self.windowScene = context.scene;
    }
    if (!CGRectIsEmpty(context.sceneBounds) && !CGRectEqualToRect(self.frame, context.sceneBounds)) {
        self.frame = context.sceneBounds;
    }

    [self attachToCurrentActiveScene];
    [self setNeedsLayout];
    if (force) [self layoutIfNeeded];
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
    CV3SceneRotationContext rotationContext = CV3MakeSceneRotationContext(self.windowScene);
    rotationContext.orientation = orientation;
    rotationContext.isLandscape = UIInterfaceOrientationIsLandscape(orientation);
    rotationContext.transform = CV3RotationTransformForInterfaceOrientation(orientation);

    UIRectEdge desiredSystemEdge = UIRectEdgeRight;
    switch (orientation) {
        case UIInterfaceOrientationLandscapeLeft:
            desiredSystemEdge = UIRectEdgeTop;
            self.edgeTriggerView.frame = CGRectMake(0, 0, w, CV3Style.triggerHotzoneWidth);
            break;
        case UIInterfaceOrientationLandscapeRight:
            desiredSystemEdge = UIRectEdgeBottom;
            self.edgeTriggerView.frame = CGRectMake(0, h - CV3Style.triggerHotzoneWidth, w, CV3Style.triggerHotzoneWidth);
            break;
        case UIInterfaceOrientationPortraitUpsideDown:
            desiredSystemEdge = UIRectEdgeLeft;
            self.edgeTriggerView.frame = CGRectMake(0, safe.top, CV3Style.triggerHotzoneWidth, h - safe.top - CV3Style.triggerBottomOffset);
            break;
        case UIInterfaceOrientationPortrait:
        default:
            desiredSystemEdge = UIRectEdgeRight;
            self.edgeTriggerView.frame = CGRectMake(w - CV3Style.triggerHotzoneWidth, safe.top, CV3Style.triggerHotzoneWidth, h - safe.top - CV3Style.triggerBottomOffset);
            break;
    }

    if (self.systemEdgePan.edges != desiredSystemEdge) {
        self.systemEdgePan.enabled = NO;
        self.systemEdgePan.edges = desiredSystemEdge;
        self.systemEdgePan.enabled = YES;

        // SBSystemGestureManager caches edge routing at registration time.
        // Re-register after rotation so type 112 follows the new physical
        // right edge instead of remaining attached to the previous axis.
        UIScreenEdgePanGestureRecognizer *edgePan = self.systemEdgePan;
        dispatch_async(dispatch_get_main_queue(), ^{
            if (self.systemEdgePan != edgePan || edgePan.edges != desiredSystemEdge) return;
            @try {
                SBSystemGestureManager *manager = [CV3ClassNamed(@"SBSystemGestureManager") mainDisplayManager];
                [manager removeGestureRecognizer:edgePan];
                [manager addGestureRecognizer:edgePan withType:112];
            } @catch (__unused NSException *exception) {}
        });
    }

    [self.rootViewController.view bringSubviewToFront:self.edgeTriggerView];

    // 2. 面板容器
    self.panelContainer.backgroundColor = [UIColor clearColor];

    // 动态计算面板尺寸 (使用常量并确保不超出安全区域)
    CGSize maxSize = [self calculateMaxPanelSize];

    CGFloat targetW = MIN(CV3Style.panelW, maxSize.width);
    CGFloat targetH = MIN(CV3Style.panelH, maxSize.height);
    targetH = MAX(targetH, CV3Style.minHeight);

    CGRect panelBounds = CGRectMake(0, 0, targetW, targetH);    
    // 计算目标旋转
    CGAffineTransform targetRotation = rotationContext.transform;

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
            self.resizingHandle.transform = CGAffineTransformIdentity;

            // 调整子组件大小以匹配容器
            self.appPanel.frame = self.panelContainer.bounds;
            
            UIView *searchContainer = self.searchField.superview;
            searchContainer.frame = CGRectMake(15, 14, targetW - 30, 36);
            self.searchField.frame = CGRectInset(searchContainer.bounds, 10, 0);
            self.searchBackground.frame = searchContainer.bounds;
            self.searchBackground.path = [UIBezierPath bezierPathWithRoundedRect:searchContainer.bounds cornerRadius:10].CGPath;
            CV3LiquidGlassEnsureBackdrop(searchContainer, @"CV3SearchFieldLiquidGlassBackdrop", CV3LiquidGlassRecipeControl(), 10.0, NULL);

            self.categoryBar.frame = CGRectMake(15, 60, targetW - 30, 40);
            self.collectionView.frame = CGRectMake(0, 104, targetW, targetH - 104);
            self.noResultsLabel.frame = CGRectMake(0, 114, targetW, 40);
            
            [self updateResizingHandleFrame];
            
            [CATransaction begin];
            [CATransaction setDisableActions:YES];
            self.contrastBackdrop.frame = self.appPanel.bounds;
            [self syncMainPanelLiquidGlassGeometry];
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

    // Liquid Glass：手势预览玻璃底（幂等；宿主即 bezierBlur，backdrop 受其贝塞尔 mask 约束）
    BOOL bezierGlassCreated = NO;
    CV3LiquidGlassEnsureBackdrop(self.bezierBlur,
                                 @"CV3BezierPreviewLiquidGlassBackdrop",
                                 CV3LiquidGlassRecipePanel(),
                                 0.0,
                                 &bezierGlassCreated);
    if (bezierGlassCreated) {
        CV3LogToFile(@"[LiquidGlass] installed surface=bezier-preview size=%.0fx%.0f",
                     self.bezierBlur.bounds.size.width, self.bezierBlur.bounds.size.height);
    }
    
    // 4. 面板主体
    self.appPanel.backgroundColor = [UIColor clearColor];

    // 5. 辅助视图
    self.resizingHandle.backgroundColor = [UIColor clearColor];
    
    for (UIView *subview in self.appPanel.subviews) {
        if ([NSStringFromClass([subview class]) containsString:@"Backdrop"]) {
            subview.transform = CGAffineTransformMakeScale(1.15, 1.15);
        }
    }

    // Liquid Glass（主面板）：layoutSubviews 是几何同步的唯一裁决点
    [self syncMainPanelLiquidGlassGeometry];
    
    // 在 layoutSubviews 结尾更新 shadowPath，保证在拖动或 resize 时阴影能同步 bounds 并采用硬件加速
    if (self.isPanelShowing) {
        self.panelContainer.layer.shadowPath = [UIBezierPath bezierPathWithRoundedRect:self.panelContainer.bounds cornerRadius:CV3Style.cornerRadius].CGPath;
    }
}



- (void)handleEdgeInteraction:(UIPanGestureRecognizer *)gesture {
    NSString *blocked = [self edgeEnvironmentBlockReason];
    if (blocked || self.edgeEnvironmentCancelled) {
        if (!self.edgeEnvironmentCancelled) {
            [self recordEdgeEnvironment:@"action.blocked" gesture:gesture decision:blocked];
            [self cancelEdgeEnvironmentInteraction];
        }
        return;
    }
    if (gesture.state != UIGestureRecognizerStateChanged) {
        [self recordEdgeEnvironment:@"action" gesture:gesture decision:@"received"];
    }
    CGPoint location = [gesture locationInView:self];
    CGPoint translation = [gesture translationInView:self];
    CGPoint velocity = [gesture velocityInView:self];

#pragma mark - 动态方向感知拉伸计算
    UIInterfaceOrientation orientation = self.targetOrientation != UIInterfaceOrientationUnknown ? self.targetOrientation : UIInterfaceOrientationPortrait;
    CGFloat stretch = 0;
    CGFloat vel = 0;
    CGFloat triggerDistance = kCV3PanelTriggerDistance;

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
        // Claim the touch sequence before SpringBoard can turn the same edge
        // movement into Home Screen Spotlight/pull-down.
        CV3SetHomeScreenPullDownSuppressed(YES);
        CV3PanelWakeGestureActive = YES;
        CV3SystemHomeSearchTriggered = NO;
        // 1. 手势预警效果 (Trigger Preview Flare)
        [CATransaction begin];
        [CATransaction setAnimationDuration:0.2];
        self.triggerPreviewLayer.frame = CGRectMake(location.x - 75, location.y - 75, 150, 150);
        self.triggerPreviewLayer.opacity = 1.0;
        [CATransaction commit];

        // 建议3：布局预热 (Layout Pre-warming)
        self.cachedTargetCenter = [self calculateTargetCenter];

        if (!self.isPanelShowing) {
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

            // Apple Design Rule 2: 1:1 动态面板 Peeking 随动预览
            CGFloat triggerProgress = MIN(1.0, MAX(0.0, stretch / MAX(triggerDistance, 1.0)));
            if (!self.isPanelShowing) {
                self.panelContainer.hidden = NO;
                self.panelContainer.alpha = triggerProgress * 0.45;
                CGAffineTransform peekTransform = CGAffineTransformScale(self.baseRotationTransform, 0.91 + triggerProgress * 0.09, 0.91 + triggerProgress * 0.09);
                self.panelContainer.transform = peekTransform;
            }

            if (stretch > triggerDistance) {
                [self recordEdgeEnvironment:@"panel.request" gesture:gesture decision:@"distanceThreshold"];
                [self requestPanelPresentationFromPoint:location velocity:vel];
                gesture.enabled = NO; gesture.enabled = YES; 
            }
        }
    } else if (gesture.state == UIGestureRecognizerStateEnded ||
               gesture.state == UIGestureRecognizerStateCancelled ||
               gesture.state == UIGestureRecognizerStateFailed) {
        CV3PanelWakeGestureActive = NO;
        // 移除预警效果
        [CATransaction begin];
        [CATransaction setAnimationDuration:0.3];
        self.triggerPreviewLayer.opacity = 0;
        [CATransaction commit];

        // Apple Design Rule 6: 滑行动量投射 Endpoint 预测 (Deceleration Projection)
        CGFloat projectedStretch = stretch + (vel / 1000.0) * 0.998 / (1.0 - 0.998);
        BOOL shouldActivate = (stretch > triggerDistance || projectedStretch > triggerDistance || vel > 320.0);

        if (self.bezierContainer.alpha > 0 && !self.isPanelShowing && shouldActivate && gesture.state == UIGestureRecognizerStateEnded) {
            [self recordEdgeEnvironment:@"panel.request" gesture:gesture decision:@"releaseProjectionOrVelocity"];
            [self requestPanelPresentationFromPoint:location velocity:vel];
        } else if (!self.isPanelShowing) {
            // 修复：确保中断时重置所有状态
            [UIView animateWithDuration:0.4 animations:^{
                self.panelContainer.hidden = YES;
                self.panelContainer.alpha = 0;
                self.backgroundColor = [UIColor clearColor];
                self.isAnimating = NO;
                CV3SetKeyboardSuppressedByPanel(NO);
            }];
            CV3SetHomeScreenPullDownSuppressed(NO);
            
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
            if (!self.isPanelShowing) self.backgroundColor = [UIColor clearColor];
        } completion:nil];
    }
}

- (void)requestPanelPresentationFromPoint:(CGPoint)point velocity:(CGFloat)velocity {
    NSString *blocked = [self edgeEnvironmentBlockReason];
    if (blocked || self.edgeEnvironmentCancelled) {
        [self recordEdgeEnvironment:@"panel.blocked" gesture:self.systemEdgePan decision:blocked ?: @"reject.cancelled"];
        [self cancelEdgeEnvironmentInteraction];
        return;
    }
    if (self.isPanelShowing || self.isAnimating || CV3PendingPanelPresentation) return;

    __weak CV3Window *weakSelf = self;
    CV3QueuePanelPresentationAfterSystemGesture(^{
        CV3Window *strongSelf = weakSelf;
        if (!strongSelf || strongSelf.isPanelShowing || strongSelf.isAnimating) return;
        NSString *blocked = [strongSelf edgeEnvironmentBlockReason];
        if (blocked || strongSelf.edgeEnvironmentCancelled) {
            [strongSelf recordEdgeEnvironment:@"panel.deferredBlocked" gesture:strongSelf.systemEdgePan decision:blocked ?: @"reject.cancelled"];
            [strongSelf cancelEdgeEnvironmentInteraction];
            return;
        }
        [strongSelf animateSpotlight:YES fromPoint:point velocity:velocity];
    });
}


static inline CGFloat CV3AppleRubberband(CGFloat x, CGFloat dimension) {
    CGFloat c = 0.55;
    return (x * dimension * c) / (dimension + c * fabs(x));
}

- (UIBezierPath *)pathForStretch:(CGFloat)stretch atPoint:(CGPoint)point velocity:(CGPoint)velocity orientation:(UIInterfaceOrientation)orientation {
    // Apple Design Rule 9: 苹果官方对数 Rubber-Banding 连续抗力函数 (替代硬性 95pt 线性钳位)
    CGFloat s = CV3AppleRubberband(MAX(0, stretch), 110.0); 
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

- (void)animateSpotlight:(BOOL)visible fromPoint:(CGPoint)point velocity:(CGFloat)velocity {
    NSString *dismissSourceBundleID = visible ? nil :
        [self.panelPresentationSourceBundleID copy] ?: [CV3CurrentWorkspaceBundleID() copy];
    if (!visible) {
        NSArray<NSString *> *stack = [NSThread callStackSymbols];
        NSInteger stackLimit = MIN((NSInteger)stack.count, 10);
        CV3LogToFile(@"[LauncherTouch] phase=panelDismiss.begin source=%@ point=%@ completionPending=%d",
                     dismissSourceBundleID ?: @"nil", NSStringFromCGPoint(point),
                     self.panelDismissCompletion != nil);
        for (NSInteger i = 0; i < stackLimit; i++) {
            CV3LogToFile(@"[LauncherTouch] phase=panelDismiss.stack frame#%ld %@",
                         (long)i, stack[(NSUInteger)i]);
        }
    }
    // Apple Design Rule 3: 绝对中断性支持 — 移除硬卡顿阻断，支持动效中途反向实时接管
    self.isPanelShowing = visible;
    self.isAnimating = YES;
    if (visible) {
        CV3LogPanelCollectionState(self, @"panelShow.entry");

        // A newly presented panel must start a fresh scroll-touch sequence.
        // The collection is hidden between presentations, so no legitimate
        // drag can span this boundary. Resetting the recognizer also repairs
        // stale tracking left by older builds that consumed touch-ended events.
        UIPanGestureRecognizer *collectionPan = self.collectionView.panGestureRecognizer;
        if (self.collectionView.tracking || self.collectionView.dragging ||
            self.collectionView.decelerating ||
            collectionPan.state != UIGestureRecognizerStatePossible) {
            collectionPan.enabled = NO;
            collectionPan.enabled = YES;
            CV3LogPanelCollectionState(self, @"panelShow.afterPanReset");
        }
        self.panelPresentationSourceBundleID = [CV3CurrentWorkspaceBundleID() copy];
        CV3SetHomeScreenPullDownSuppressed(YES);
        CV3ExitExposeModeIfNeeded(nil, NO);
        UIViewPropertyAnimator *visibilityAnimator = self.panelVisibilityAnimator;
        self.panelDismissCompletion = nil;
        self.panelVisibilityAnimator = nil;
        [visibilityAnimator stopAnimation:YES];
        self.panelContainer.userInteractionEnabled = YES;
        self.panelContainer.layer.shouldRasterize = NO;

        CV3SetKeyboardSuppressedByPanel(YES);
        [self startPanelStateRefreshTimer];
        self.searchField.text = @"";
        self.selectedCategory = @"全部";
        [self filterApps];
        self.backgroundColor = [UIColor clearColor];
        self.lastTriggerPoint = point;
        [self loadAppsAsync];
        self.appPanel.alpha = 1.0;
        self.collectionView.alpha = 1.0;
        self.bezierLayer.opacity = 1.0;
        self.panelContainer.hidden = NO;
        
        self.contrastBackdrop.hidden = NO;

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
        CGFloat targetW = MIN(CV3Style.panelW, maxSize.width);
        CGFloat targetH = MIN(CV3Style.panelH, maxSize.height);
        targetH = MAX(targetH, CV3Style.minHeight);
        
        // 重置视差形变，防止修改 frame 时发生坐标跳变 (Geometry Jump)
        self.appPanel.transform = CGAffineTransformIdentity;
        self.resizingHandle.transform = CGAffineTransformIdentity;

        // 设置初始 bounds 和子组件大小
        self.panelContainer.bounds = CGRectMake(0, 0, targetW, targetH);
        self.appPanel.frame = self.panelContainer.bounds;
        
        UIView *searchContainer = self.searchField.superview;
        searchContainer.frame = CGRectMake(15, 14, targetW - 30, 36);
        self.searchField.frame = CGRectInset(searchContainer.bounds, 10, 0);
        self.searchBackground.frame = searchContainer.bounds;
        CGFloat concentricRadius = CV3ConcentricCornerRadius(CV3Style.cornerRadius, 15.0);
        self.searchBackground.path = [UIBezierPath bezierPathWithRoundedRect:searchContainer.bounds cornerRadius:concentricRadius].CGPath;
        CV3LiquidGlassEnsureBackdrop(searchContainer, @"CV3SearchFieldLiquidGlassBackdrop", CV3LiquidGlassRecipeControl(), concentricRadius, NULL);

        self.categoryBar.frame = CGRectMake(15, 60, targetW - 30, 40);
        self.collectionView.frame = CGRectMake(0, 104, targetW, targetH - 104);
        self.noResultsLabel.frame = CGRectMake(0, 114, targetW, 40);
        
        [self updateResizingHandleFrame];
        self.contrastBackdrop.frame = self.appPanel.bounds;
        [self syncMainPanelLiquidGlassGeometry];
        [self refreshGlassAccentSurfaces];
        [self.collectionView.collectionViewLayout invalidateLayout];
        // 打开面板时列表归位到顶部：避免滚动残留在“分类栏与首行图标”之间留出裸露玻璃缝（透出背后桌面内容）
        [self.collectionView setContentOffset:CGPointZero animated:NO];
        CV3LogPanelCollectionState(self, @"panelShow.afterGeometry");

        // 阴影硬件加速与大阴影配置
        self.panelContainer.layer.shadowColor = [UIColor blackColor].CGColor;
        self.panelContainer.layer.shadowOffset = CGSizeZero;
        self.panelContainer.layer.shadowOpacity = 0.0;
        self.panelContainer.layer.shadowRadius = CV3Style.shadowRadiusMask;
        self.panelContainer.layer.shadowPath = [UIBezierPath bezierPathWithRoundedRect:self.panelContainer.bounds cornerRadius:CV3Style.cornerRadius].CGPath;

        // Apple Design Rule 7: 来源锚定 (Anchor to Source)
        // 计算手势触发点与居中目标的向量差，在初始帧赋予微小来源偏移与位移拉伸
        CGPoint targetCenter = (self.cachedTargetCenter.x > 0) ? self.cachedTargetCenter : [self calculateTargetCenter];
        CGFloat offsetX = (point.x > 0 && point.x < self.bounds.size.width) ? (point.x - targetCenter.x) * 0.12 : 0;
        CGFloat offsetY = (point.y > 0 && point.y < self.bounds.size.height) ? (point.y - targetCenter.y) * 0.12 : 0;
        
        CGFloat jellyStrength = kCV3PanelJellyStrength;
        CGFloat velocityStretch = MIN(fabs(velocity) / 7500.0, 0.09) * jellyStrength;
        CGFloat initialScaleX = 0.91 - jellyStrength * 0.35 - velocityStretch;
        CGFloat initialScaleY = 0.91 - jellyStrength * 0.15 + velocityStretch * 0.20;
        
        // Apple Design Rule 5 & 6: 速度手接 handoff 与 Spring 速度换算
        CGFloat springVelocity = MIN(3.2, MAX(1.10, fabs(velocity) / 1200.0));
        // BounceIt 风格果冻弹跳：面板从 (0.56, 0.76) 的拉伸初态弹回时带过冲，
        // 原 0.82 接近临界阻尼、看不到回弹，故切到 kCV3BounceDamping。
        CGFloat springDamping = kCV3BounceDamping;
        
        CGAffineTransform sourceTransform = CGAffineTransformTranslate(initialRotation, offsetX, offsetY);
        self.panelPresentationStartTransform = CGAffineTransformScale(sourceTransform, initialScaleX, initialScaleY);
        CV3RemoveViewAnimationsRecursively(self.panelContainer);
        self.panelContainer.transform = self.panelPresentationStartTransform;
        self.panelContainer.alpha = 0;
        self.appPanelPresentationStartTransform = CGAffineTransformIdentity;
        self.appPanel.transform = CGAffineTransformIdentity;

        self.panelContainer.center = targetCenter;

        void (^presentationAnimations)(void) = ^{
            self.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:CV3Style.maskAlpha];
            self.panelContainer.transform = initialRotation;
            self.panelContainer.alpha = 1;
            self.panelContainer.layer.shadowOpacity = CV3Style.shadowOpacityMask;

            // 实时汲取当前活跃 App 的色调注入遮罩
            CV3UpdateAdaptiveTint([self currentActiveBundleID]);
        };
        void (^presentationCompletion)(BOOL) = ^(BOOL finished) {
            if (finished && self.isPanelShowing) self.isAnimating = NO;
            // 呈现前调用的 CV3RemoveViewAnimationsRecursively 会连带摘掉
            // Cell 上的呼吸动画；布局落定后按面板状态统一重挂。
            [self syncAppCellBreathing];
        };

        [UIView animateWithDuration:kCV3PanelPresentDuration
                              delay:0
             usingSpringWithDamping:springDamping
              initialSpringVelocity:springVelocity
                            options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction
                         animations:presentationAnimations
                         completion:presentationCompletion];
    } else {
        [self stopPanelStateRefreshTimer];

        CALayer *presentationLayer = self.panelContainer.layer.presentationLayer;
        CGPoint currentCenter = presentationLayer ? presentationLayer.position : self.panelContainer.center;
        CGAffineTransform currentTransform = presentationLayer
            ? CATransform3DGetAffineTransform(presentationLayer.transform)
            : self.panelContainer.transform;
        CGFloat currentAlpha = presentationLayer ? presentationLayer.opacity : self.panelContainer.alpha;
        CGFloat currentShadowOpacity = presentationLayer
            ? presentationLayer.shadowOpacity
            : self.panelContainer.layer.shadowOpacity;
        CALayer *windowPresentationLayer = self.layer.presentationLayer;
        UIColor *currentBackgroundColor = windowPresentationLayer.backgroundColor
            ? [UIColor colorWithCGColor:windowPresentationLayer.backgroundColor]
            : self.backgroundColor;

        // Continue from the exact visible frame before removing any stale layer
        // animation. This prevents a one-frame snap when dismissal interrupts a
        // presentation or an orientation update.
        [CATransaction begin];
        [CATransaction setDisableActions:YES];
        self.panelContainer.layer.position = currentCenter;
        self.panelContainer.layer.affineTransform = currentTransform;
        self.panelContainer.layer.opacity = currentAlpha;
        self.panelContainer.layer.shadowOpacity = currentShadowOpacity;
        [self.panelContainer.layer removeAllAnimations];
        self.layer.backgroundColor = currentBackgroundColor.CGColor;
        [self.layer removeAnimationForKey:@"backgroundColor"];
        [CATransaction commit];

        BOOL reduceMotion = UIAccessibilityIsReduceMotionEnabled();
        CGAffineTransform dismissTransform = reduceMotion
            ? currentTransform
            : CGAffineTransformScale(currentTransform, 0.965, 0.965);
        CGPoint dismissCenter = currentCenter;
        CGPoint edgePoint = self.lastTriggerPoint;
        CGFloat dx = edgePoint.x - dismissCenter.x;
        CGFloat dy = edgePoint.y - dismissCenter.y;
        CGFloat distance = sqrt(dx * dx + dy * dy);
        if (!reduceMotion && distance > 1.0) {
            dismissCenter.x += (dx / distance) * 10.0;
            dismissCenter.y += (dy / distance) * 10.0;
        }

        // 收起动画 = 快通道（透明度）+ 弹簧通道（几何）：
        // - 透明度类属性（遮罩 / 面板 alpha / 大面积阴影 / 光束）用 0.20s ease-out
        //   先行归零。大阴影与遮罩若跟着弹簧缓收，尾段会拖出肉眼可见的"拖尾阴影"
        //   与滞后感（2026-10-12 复测反馈："面板收起有拖尾阴影，看起来滞后"）。
        // - 几何（center / transform）保留 kCV3BounceDamping 弹簧的轻弹收尾。
        // reduceMotion 无障碍路径保持原 cubic 全属性动画，不引入回弹。
        NSTimeInterval duration = reduceMotion ? 0.18 : kCV3PanelDismissDuration;
        UIViewPropertyAnimator *animator;
        if (reduceMotion) {
            UICubicTimingParameters *timing = [[UICubicTimingParameters alloc]
                initWithControlPoint1:CGPointMake(0.20, 0.0)
                controlPoint2:CGPointMake(0.0, 1.0)];
            animator = [[UIViewPropertyAnimator alloc]
                initWithDuration:duration
                timingParameters:timing];
        } else {
            [UIView animateWithDuration:0.20
                                  delay:0
                                options:UIViewAnimationOptionCurveEaseOut | UIViewAnimationOptionBeginFromCurrentState
                             animations:^{
                self.backgroundColor = [UIColor clearColor];
                self.panelContainer.alpha = 0.0;
                self.panelContainer.layer.shadowOpacity = 0.0;
                self.bezierContainer.alpha = 0.0;
                self.bezierLayer.opacity = 0.0;
            } completion:nil];
            UISpringTimingParameters *timing = [[UISpringTimingParameters alloc]
                initWithDampingRatio:kCV3BounceDamping];
            animator = [[UIViewPropertyAnimator alloc]
                initWithDuration:duration
                timingParameters:timing];
        }
        self.panelContainer.userInteractionEnabled = NO;
        self.panelVisibilityAnimator = animator;

        if (reduceMotion) {
            [animator addAnimations:^{
                self.backgroundColor = [UIColor clearColor];
                self.panelContainer.center = dismissCenter;
                self.panelContainer.alpha = 0.0;
                self.panelContainer.transform = dismissTransform;
                self.panelContainer.layer.shadowOpacity = 0.0;
                self.bezierContainer.alpha = 0.0;
                self.bezierLayer.opacity = 0.0;
            }];
        } else {
            [animator addAnimations:^{
                self.panelContainer.center = dismissCenter;
                self.panelContainer.transform = dismissTransform;
            }];
        }

        __weak CV3Window *weakSelf = self;
        __weak UIViewPropertyAnimator *weakAnimator = animator;
        [animator addCompletion:^(__unused UIViewAnimatingPosition finalPosition) {
            CV3Window *strongSelf = weakSelf;
            UIViewPropertyAnimator *completedAnimator = weakAnimator;
            if (!strongSelf || strongSelf.panelVisibilityAnimator != completedAnimator) return;

            dispatch_block_t completion = strongSelf.panelDismissCompletion;
            strongSelf.panelDismissCompletion = nil;
            strongSelf.panelVisibilityAnimator = nil;
            strongSelf.isAnimating = NO;
            CV3FinalizePanelHiddenState(strongSelf);
            CV3SetKeyboardSuppressedByPanel(NO);
            CV3SetHomeScreenPullDownSuppressed(NO);
            if (completion) completion();
        }];

        [animator startAnimation];

        // Keyboard teardown can synchronously traverse its visual-effect tree.
        // Start the panel animation first so that work cannot delay its first frame.
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.searchField resignFirstResponder];
        });
    }
}

- (void)animateIconsStaggered {
    if (CV3ScrollViewIsActivelyControlled(self.collectionView)) return;

    NSArray *items = [self.collectionView visibleCells];
    NSArray *sorted = [items sortedArrayUsingComparator:^NSComparisonResult(UICollectionViewCell *a, UICollectionViewCell *b) {
        return [[self.collectionView indexPathForCell:a] compare:[self.collectionView indexPathForCell:b]];
    }];
    for (int i = 0; i < sorted.count; i++) {
        UIView *v = sorted[i]; v.transform = CGAffineTransformMakeScale(0.2, 0.2); v.alpha = 0;
        [UIView animateWithDuration:0.6 delay:i*0.015 usingSpringWithDamping:0.45 initialSpringVelocity:1.5 options:0 animations:^{ v.transform = CGAffineTransformIdentity; v.alpha = 1; } completion:nil];
    }
}







- (void)scrollViewWillBeginDragging:(UIScrollView *)scrollView {
    if (scrollView == self.collectionView) {
        CV3LogPanelCollectionState(self, @"scroll.willBeginDragging");
    }
    [self.searchField resignFirstResponder];
}

- (void)scrollViewDidScroll:(UIScrollView *)scrollView {
    if (scrollView != self.collectionView) return;

    static CFTimeInterval lastTraceTime = 0.0;
    static CGPoint lastTraceOffset = {CGFLOAT_MAX, CGFLOAT_MAX};
    CFTimeInterval now = CACurrentMediaTime();
    CGPoint offset = scrollView.contentOffset;
    CGFloat delta = hypot(offset.x - lastTraceOffset.x, offset.y - lastTraceOffset.y);
    if (delta >= 18.0 || now - lastTraceTime >= 0.06) {
        lastTraceTime = now;
        lastTraceOffset = offset;
        CV3LogPanelCollectionState(self, @"scroll.didScroll");
    }
}

- (void)scrollViewDidEndDecelerating:(UIScrollView *)scrollView {
    if (scrollView == self.collectionView) {
        CV3LogPanelCollectionState(self, @"scroll.didEndDecelerating");
    }
    // 减速自然归位：保持主线程零干预，使原生 120Hz ProMotion 减速平滑衰减至静止
}

- (void)scrollViewDidEndDragging:(UIScrollView *)scrollView willDecelerate:(BOOL)decelerate {
    if (scrollView == self.collectionView) {
        CV3LogPanelCollectionState(self, decelerate ? @"scroll.didEndDragging.decelerate" : @"scroll.didEndDragging.stop");
    }
}

static NSInteger CV3UnreadCountFromIconObject(id icon) {
    for (NSString *key in @[@"badgeValue", @"badgeNumber", @"displayedBadgeValue", @"badgeString"]) {
        id value = nil;
        @try {
            value = [icon valueForKey:key];
        } @catch (__unused NSException *exception) {
            value = nil;
        }
        if (!value || value == [NSNull null]) continue;

        if ([value isKindOfClass:[NSString class]]) {
            NSString *badgeText = [(NSString *)value stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
            if (badgeText.length == 0 || [badgeText isEqualToString:@"0"]) continue;
            NSInteger count = badgeText.integerValue;
            return count > 0 ? count : 1;
        }
        if ([value respondsToSelector:@selector(integerValue)]) {
            NSInteger count = [value integerValue];
            if (count > 0) return count;
        }
    }
    return 0;
}

static NSMutableDictionary<NSString *, NSNumber *> *CV3NotificationPermissionCache(void) {
    static NSMutableDictionary<NSString *, NSNumber *> *cache = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        cache = [NSMutableDictionary dictionary];
    });
    return cache;
}

static NSMutableDictionary<NSString *, NSNumber *> *CV3NotificationPermissionRequestDates(void) {
    static NSMutableDictionary<NSString *, NSNumber *> *dates = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        dates = [NSMutableDictionary dictionary];
    });
    return dates;
}

static id CV3NotificationSettingsGateway(void) {
    static id gateway = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        Class gatewayClass = CV3ClassNamed(@"BBSettingsGateway");
        if (gatewayClass) gateway = [[gatewayClass alloc] init];
    });
    return gateway;
}

static void CV3RequestNotificationPermissionForBundleID(NSString *bundleID) {
    if (![NSThread isMainThread] || bundleID.length == 0) return;

    NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
    NSMutableDictionary<NSString *, NSNumber *> *requestDates = CV3NotificationPermissionRequestDates();
    NSTimeInterval previousRequest = [requestDates[bundleID] doubleValue];
    if (previousRequest > 0.0 && now - previousRequest < 5.0) return;

    id gateway = CV3NotificationSettingsGateway();
    SEL selector = NSSelectorFromString(@"getSectionInfoForSectionID:withCompletion:");
    if (!gateway || ![gateway respondsToSelector:selector]) {
        CV3NotificationPermissionCache()[bundleID] = @NO;
        return;
    }

    requestDates[bundleID] = @(now);
    void (^completion)(id) = ^(id sectionInfo) {
        BOOL allowsNotifications = CV3InvokeBool(sectionInfo, NSSelectorFromString(@"allowsNotifications"), NO);
        dispatch_async(dispatch_get_main_queue(), ^{
            CV3NotificationPermissionCache()[bundleID] = @(allowsNotifications);
        });
    };

    @try {
        ((void (*)(id, SEL, NSString *, id))objc_msgSend)(gateway, selector, bundleID, completion);
    } @catch (__unused NSException *exception) {
        CV3NotificationPermissionCache()[bundleID] = @NO;
    }
}

static BOOL CV3AppHasNotificationPermission(NSString *bundleID) {
    if (bundleID.length == 0) return NO;
    CV3RequestNotificationPermissionForBundleID(bundleID);
    return [CV3NotificationPermissionCache()[bundleID] boolValue];
}

static NSDictionary<NSString *, NSNumber *> *CV3SpringBoardIconBadgeSnapshot(void) {
    if (![NSThread isMainThread]) return nil;

    id iconController = [CV3ClassNamed(@"SBIconController") sharedInstance];
    id iconManager = CV3InvokeObject(iconController, @selector(iconManager));
    id iconModel = CV3InvokeObject(iconManager, @selector(model));
    if (!iconModel) iconModel = CV3InvokeObject(iconController, @selector(model));

    id leafIcons = CV3InvokeObject(iconModel, @selector(leafIcons));
    if (![leafIcons conformsToProtocol:@protocol(NSFastEnumeration)]) return nil;

    NSMutableDictionary<NSString *, NSNumber *> *snapshot = [NSMutableDictionary dictionary];
    if ([leafIcons conformsToProtocol:@protocol(NSFastEnumeration)]) {
        for (id icon in leafIcons) {
            NSString *bundleID = CV3BundleIdentifierFromIconObject(icon);
            if (bundleID.length == 0) continue;

            NSInteger unreadCount = CV3UnreadCountFromIconObject(icon);
            if (unreadCount > 0 && !CV3AppHasNotificationPermission(bundleID)) unreadCount = 0;
            snapshot[bundleID] = @(unreadCount);
        }
    }
    return [snapshot copy];
}

- (BOOL)shouldIncludeApp:(id)appProxy launchableBundleIDs:(NSSet<NSString *> *)launchableBundleIDs {
    // 必须有有效 Bundle ID。
    NSString *bundleId = CV3InvokeObject(appProxy, @selector(bundleIdentifier));
    if (bundleId.length == 0) return NO;

    if (!CV3InvokeBool(appProxy, @selector(isInstalled), YES) ||
        CV3InvokeBool(appProxy, @selector(isPlaceholder), NO) ||
        CV3InvokeBool(appProxy, NSSelectorFromString(@"isLaunchProhibited"), NO)) {
        return NO;
    }

    if (launchableBundleIDs.count == 0 || ![launchableBundleIDs containsObject:bundleId]) {
        return NO;
    }

    NSArray *appTags = CV3InvokeObject(appProxy, @selector(appTags));
    for (id tag in appTags) {
        if (![tag isKindOfClass:[NSString class]]) continue;
        NSString *normalizedTag = [tag lowercaseString];
        if ([normalizedTag isEqualToString:@"hidden"] ||
            [normalizedTag isEqualToString:@"internal"] ||
            [normalizedTag containsString:@"plugin"]) {
            return NO;
        }
    }

    // 排除特定系统组件（通过 Bundle ID 前缀）。
    static NSArray *excludedPrefixes = nil;
    if (!excludedPrefixes) {
        excludedPrefixes = @[
            @"com.apple.webapp", @"com.apple.tips", @"com.apple.stocks",
            @"com.apple.coverage-details", @"com.apple.tvprovider", @"com.apple.lookup"
        ];
    }
    NSString *normalizedBundleID = [bundleId lowercaseString];
    for (NSString *prefix in excludedPrefixes) {
        if ([normalizedBundleID hasPrefix:[prefix lowercaseString]]) return NO;
    }

    NSString *localizedName = CV3InvokeObject(appProxy, @selector(localizedName));
    if (localizedName.length == 0) localizedName = CV3InvokeObject(appProxy, @selector(itemName));
    static NSSet<NSString *> *excludedNames = nil;
    static dispatch_once_t excludedNamesOnceToken;
    dispatch_once(&excludedNamesOnceToken, ^{
        excludedNames = [NSSet setWithArray:@[
            @"查询 App", @"保修范围详情信息", @"电视提供商",
            @"Lookup", @"Coverage Details", @"TV Provider"
        ]];
    });
    if ([excludedNames containsObject:localizedName]) return NO;

    return YES;
}

- (NSArray<CV3AppInfo *> *)buildAppSnapshotOnAppLoadQueueWithLaunchableBundleIDs:(NSSet<NSString *> *)launchableBundleIDs {
    NSMutableArray<CV3AppInfo *> *snapshot = [NSMutableArray array];

    id workspace = [CV3ClassNamed(@"LSApplicationWorkspace") defaultWorkspace];
    for (id proxy in CV3InvokeObject(workspace, @selector(allInstalledApplications))) {
        if (![self shouldIncludeApp:proxy launchableBundleIDs:launchableBundleIDs]) continue;

        NSString *bundleID = CV3InvokeObject(proxy, @selector(bundleIdentifier));
        NSString *name = CV3InvokeObject(proxy, @selector(localizedName));
        if (name.length == 0) name = CV3InvokeObject(proxy, @selector(itemName));
        if (name.length == 0) name = bundleID;
        if (bundleID.length == 0 || name.length == 0) continue;

        CV3AppInfo *info = [[CV3AppInfo alloc] init];
        info.name = name;
        info.bundleId = bundleID;
        info.icon = [cv3IconCache objectForKey:bundleID];
        info.category = CV3InvokeObject(proxy, @selector(genre)) ?: @"其他";
        [snapshot addObject:info];
    }
    return [snapshot copy];
}

static NSUInteger CV3IconCacheCost(UIImage *image) {
    if (!image) return 0;
    CGSize size = image.size;
    CGFloat scale = image.scale > 0 ? image.scale : [UIScreen mainScreen].scale;
    return (NSUInteger)MAX(1.0, size.width * scale * size.height * scale * 4.0);
}

- (void)loadIconForAppInfo:(CV3AppInfo *)info cell:(CV3AppCell *)cell {
    NSString *bundleID = [info.bundleId copy];
    if (bundleID.length == 0) return;

    UIImage *cachedImage = info.icon ?: [cv3IconCache objectForKey:bundleID];
    if (cachedImage) {
        info.icon = cachedImage;
        [cell setIconImage:cachedImage forBundleId:bundleID];
        return;
    }

    static NSMutableSet<NSString *> *inFlightBundleIDs = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        inFlightBundleIDs = [NSMutableSet set];
    });

    if ([inFlightBundleIDs containsObject:bundleID]) return;
    [inFlightBundleIDs addObject:bundleID];

    CGFloat scale = [UIScreen mainScreen].scale;
    __weak typeof(self) weakSelf = self;
    __weak CV3AppCell *weakCell = cell;
    dispatch_async(CV3AppLoadQueue(), ^{
        @autoreleasepool {
            UIImage *image = [cv3IconCache objectForKey:bundleID];
            if (!image) {
                image = [UIImage _applicationIconImageForBundleIdentifier:bundleID format:10 scale:scale];
                if (image) {
                    [cv3IconCache setObject:image forKey:bundleID cost:CV3IconCacheCost(image)];
                }
            }

            dispatch_async(dispatch_get_main_queue(), ^{
                [inFlightBundleIDs removeObject:bundleID];
                if (!image) return;

                CV3Window *strongSelf = weakSelf;
                if (!strongSelf) return;
                for (CV3AppInfo *candidate in strongSelf.apps) {
                    if ([candidate.bundleId isEqualToString:bundleID]) {
                        candidate.icon = image;
                        break;
                    }
                }
                [weakCell setIconImage:image forBundleId:bundleID];
                for (CV3AppCell *visibleCell in strongSelf.collectionView.visibleCells) {
                    [visibleCell setIconImage:image forBundleId:bundleID];
                }
            });
        }
    });
}

- (void)loadAppsAsync {
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self loadAppsAsync];
        });
        return;
    }

    NSUInteger requestedGeneration = ++self.appLoadGeneration;
    BOOL needsFullReload = self.needsFullReload || self.apps.count == 0;
    NSArray<CV3AppInfo *> *appsSnapshot = [self.apps copy] ?: @[];
    NSSet *pinnedSnapshot = [self.pinnedBundleIDs copy] ?: [NSSet set];
    NSDictionary<NSString *, NSNumber *> *badgeSnapshot = CV3SpringBoardIconBadgeSnapshot();
    NSSet<NSString *> *launchableBundleIDs = badgeSnapshot ? [NSSet setWithArray:badgeSnapshot.allKeys] : [NSSet set];

    dispatch_async(CV3AppLoadQueue(), ^{
        @autoreleasepool {
            NSMutableArray<CV3AppInfo *> *workingApps = [NSMutableArray arrayWithCapacity:appsSnapshot.count];
            for (CV3AppInfo *source in appsSnapshot) {
                CV3AppInfo *copiedInfo = CV3CopyAppInfo(source);
                if (copiedInfo) [workingApps addObject:copiedInfo];
            }

            if (!needsFullReload && workingApps.count > 0) {
                CV3LogToFile(@"[Debug] 命中增量更新，仅刷新置顶与排序状态 (generation=%lu)", (unsigned long)requestedGeneration);
            } else {
                CV3LogToFile(@"[Debug] 执行全量应用资源同步 (needsFullReload=%d, generation=%lu)", needsFullReload, (unsigned long)requestedGeneration);
                NSArray<CV3AppInfo *> *fullReloadSnapshot =
                    [self buildAppSnapshotOnAppLoadQueueWithLaunchableBundleIDs:launchableBundleIDs];
                workingApps = [NSMutableArray arrayWithCapacity:fullReloadSnapshot.count];
                for (CV3AppInfo *source in fullReloadSnapshot) {
                    CV3AppInfo *copiedInfo = CV3CopyAppInfo(source);
                    if (!copiedInfo) continue;
                    [copiedInfo generatePinyin];
                    [workingApps addObject:copiedInfo];
                }
            }

            NSDictionary *usageData = [[NSUserDefaults standardUserDefaults] dictionaryForKey:@"CV3AppUsageData"];
            NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
            NSTimeInterval sevenDaysInSeconds = 7 * 24 * 3600;

            for (CV3AppInfo *info in workingApps) {
                info.isPinned = [pinnedSnapshot containsObject:info.bundleId];
                info.unreadCount = [badgeSnapshot[info.bundleId] integerValue];
                NSArray *ts = usageData[info.bundleId];
                if (ts && ts.count > 0) {
                    info.lastUsedDate = [[ts lastObject] doubleValue];
                } else {
                    info.lastUsedDate = 0;
                }
            }

            [workingApps sortUsingComparator:^NSComparisonResult(CV3AppInfo *obj1, CV3AppInfo *obj2) {
                if (obj1.isPinned != obj2.isPinned) return obj1.isPinned ? NSOrderedAscending : NSOrderedDescending;

                NSArray *ts1 = usageData[obj1.bundleId];
                NSArray *ts2 = usageData[obj2.bundleId];

                double score1 = 0;
                for (NSNumber *ts in ts1) {
                    double diff = now - [ts doubleValue];
                    if (diff < sevenDaysInSeconds) score1 += (1.0 / (diff / 3600.0 + 1.0));
                }

                double score2 = 0;
                for (NSNumber *ts in ts2) {
                    double diff = now - [ts doubleValue];
                    if (diff < sevenDaysInSeconds) score2 += (1.0 / (diff / 3600.0 + 1.0));
                }

                if (score1 != score2) return score1 > score2 ? NSOrderedAscending : NSOrderedDescending;
                if (obj1.lastUsedDate != obj2.lastUsedDate) return obj1.lastUsedDate > obj2.lastUsedDate ? NSOrderedAscending : NSOrderedDescending;
                return [obj1.name localizedCaseInsensitiveCompare:obj2.name];
            }];

            NSArray<CV3AppInfo *> *sortedApps = [workingApps copy];

            dispatch_async(dispatch_get_main_queue(), ^{
                if (requestedGeneration != self.appLoadGeneration) {
                    CV3LogToFile(@"[Debug] 丢弃过期应用列表结果 (generation=%lu, latest=%lu)",
                                 (unsigned long)requestedGeneration,
                                 (unsigned long)self.appLoadGeneration);
                    return;
                }

                CV3LogPanelCollectionState(self, @"loadApps.apply.before");
                self.apps = [sortedApps mutableCopy];
                if (needsFullReload) self.needsFullReload = NO;
                self.recentlyUsedApps = [self.apps subarrayWithRange:NSMakeRange(0, MIN(12, self.apps.count))];
                [self updateCategoryBar];
                [self filterApps];
                CV3LogPanelCollectionState(self, @"loadApps.apply.after");
            });
        }
    });
}

- (void)handleMemoryWarning {
    CV3LogToFile(@"[Warning] Received Memory Warning, clearing icon cache and pausing tasks...");
    [cv3IconCache removeAllObjects];
    self.needsFullReload = YES; 
}

- (void)handleFloatingWindowsDidChange {
    CGPoint preservedOffset = self.collectionView.contentOffset;
    [UIView performWithoutAnimation:^{
        [self.collectionView reloadData];
        [self.collectionView layoutIfNeeded];
        [self.collectionView setContentOffset:CV3ClampedContentOffsetForScrollView(self.collectionView, preservedOffset) animated:NO];
    }];
}

- (void)refreshProtectedAppMarkers {
    if (!self.isPanelShowing || self.collectionView.hidden) return;
    if (CV3ScrollViewIsActivelyControlled(self.collectionView)) return;

    CFTimeInterval passStart = CACurrentMediaTime();

    BOOL badgeChanged = NO;
    NSDictionary<NSString *, NSNumber *> *badgeSnapshot = CV3SpringBoardIconBadgeSnapshot();
    if (badgeSnapshot) {
        for (CV3AppInfo *info in self.apps) {
            NSInteger unread = [badgeSnapshot[info.bundleId] integerValue];
            if (info.unreadCount != unread) badgeChanged = YES;
            info.unreadCount = unread;
        }
    }

    NSArray<UICollectionViewCell *> *visibleCells = self.collectionView.visibleCells;
    if (visibleCells.count == 0) return;

    // 就地刷新可见 Cell 的外观。绝不能再用 reloadItemsAtIndexPaths: —— 它会重建 Cell，
    // 把挂在 contentView.layer 上的图标呼吸动画每 1 秒打断重掷一次；而滚动期间本方法被
    // 上面的 guard 跳过，所以症状正是「停止滚动后才一卡一卡」。
    NSString *searchText = self.searchField.text;
    NSUInteger updated = 0;
    NSUInteger readded = 0;
    for (UICollectionViewCell *cell in visibleCells) {
        if (![cell isKindOfClass:[CV3AppCell class]]) continue;
        CV3AppCell *appCell = (CV3AppCell *)cell;

        NSIndexPath *indexPath = [self.collectionView indexPathForCell:appCell];
        if (!indexPath || indexPath.item >= (NSInteger)self.filteredApps.count) continue;

        CV3AppInfo *info = self.filteredApps[indexPath.item];
        // Cell 可能正在复用中（数据源已换成别的 App 但 configure 未跑完），交给后续 configure。
        if (![appCell.representedBundleId isEqualToString:info.bundleId]) continue;

        BOOL isFirst = (indexPath.item == 0 && searchText.length > 0);
        BOOL hadBreathing = [appCell hasBreathingAnimation];
        [appCell applyDynamicAppearanceWithInfo:info
                                     searchText:searchText
                                        isFirst:isFirst
                               protectionState:CV3AppPanelProtectionStateForBundleID(info.bundleId)];
        // readded 是「呼吸动画被谁拆掉了」的探测器：稳定状态下必须恒为 0。
        if (!hadBreathing && [appCell hasBreathingAnimation]) readded++;
        updated++;
    }

    CGFloat elapsedMs = (CACurrentMediaTime() - passStart) * 1000.0;
    if (badgeChanged || readded > 0 || elapsedMs > 8.0) {
        CV3LogToFile(@"[BreathingTrace] phase=markerRefresh badgeChanged=%d updated=%lu readded=%lu visible=%lu elapsedMs=%.2f",
                     badgeChanged, (unsigned long)updated, (unsigned long)readded,
                     (unsigned long)visibleCells.count, elapsedMs);
    }
}

- (void)startPanelStateRefreshTimer {
    if (self.panelStateRefreshTimer) return;

    self.panelStateRefreshTimer = [NSTimer scheduledTimerWithTimeInterval:1.0
                                                                   target:self
                                                                 selector:@selector(refreshProtectedAppMarkers)
                                                                 userInfo:nil
                                                                  repeats:YES];
    [[NSRunLoop mainRunLoop] addTimer:self.panelStateRefreshTimer forMode:NSRunLoopCommonModes];
}

- (void)stopPanelStateRefreshTimer {
    if (!self.panelStateRefreshTimer) return;

    [self.panelStateRefreshTimer invalidate];
    self.panelStateRefreshTimer = nil;
}

- (void)show {
    CV3ExitExposeModeIfNeeded(nil, NO);
    [self attachToCurrentActiveScene];
    self.hidden = NO;

    if (!self.observersRegistered) {
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(attachToCurrentActiveScene)
                                                     name:UISceneDidActivateNotification
                                                   object:nil];

        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(handleMemoryWarning)
                                                     name:UIApplicationDidReceiveMemoryWarningNotification
                                                   object:nil];

        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(keyboardWillShow:) name:UIKeyboardWillShowNotification object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(keyboardWillHide:) name:UIKeyboardWillHideNotification object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(handleFloatingWindowsDidChange) name:CV3FloatingWindowsDidChangeNotification object:nil];
        self.observersRegistered = YES;
    }
                                               
    if (!self.heartbeatTimer) {
        self.heartbeatTimer = [NSTimer scheduledTimerWithTimeInterval:15.0 target:self selector:@selector(monitorState) userInfo:nil repeats:YES];
        [[NSRunLoop mainRunLoop] addTimer:self.heartbeatTimer forMode:NSRunLoopCommonModes];
    }
}

- (void)cleanupRuntimeResources {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    self.observersRegistered = NO;

    if (self.heartbeatTimer) {
        [self.heartbeatTimer invalidate];
        self.heartbeatTimer = nil;
    }

    [self stopPanelStateRefreshTimer];
    CV3SetKeyboardSuppressedByPanel(NO);
}

- (void)dealloc {
    [self cleanupRuntimeResources];
}



- (void)keyboardWillShow:(NSNotification *)notification {
    self.isKeyboardVisible = YES;
    
    NSDictionary *userInfo = notification.userInfo;
    CGRect keyboardFrame = [userInfo[UIKeyboardFrameEndUserInfoKey] CGRectValue];
    double duration = [userInfo[UIKeyboardAnimationDurationUserInfoKey] doubleValue];
    UIViewAnimationOptions options = [userInfo[UIKeyboardAnimationCurveUserInfoKey] unsignedIntegerValue] << 16;
    UIInterfaceOrientation debugOrientation = self.targetOrientation != UIInterfaceOrientationUnknown ? self.targetOrientation : UIInterfaceOrientationPortrait;
    CV3LogToFile(@"[Warning][KeyboardDebug] keyboardWillShow orientation=%ld isLandscape=%d frameEnd=%@ duration=%.3f searchFirstResponder=%d windowScene=%@ accessory=%@",
                 (long)debugOrientation,
                 UIInterfaceOrientationIsLandscape(debugOrientation),
                 NSStringFromCGRect(keyboardFrame),
                 duration,
                 self.searchField.isFirstResponder,
                 self.windowScene,
                 self.searchField.inputAccessoryView);

    // 键盘现场取证：两拍快照（诊断专用，零行为改动）。
    // 0.55s 捕捉键盘动画完成态，1.35s 捕捉延迟布局后的最终态。
    static NSUInteger cv3KeyboardShowForensicsGeneration = 0;
    NSUInteger showForensicsGeneration = ++cv3KeyboardShowForensicsGeneration;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.55 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (showForensicsGeneration != cv3KeyboardShowForensicsGeneration) return;
        CV3DumpKeyboardForensics(@"willShow+0.55s");
    });
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.35 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (showForensicsGeneration != cv3KeyboardShowForensicsGeneration) return;
        CV3DumpKeyboardForensics(@"willShow+1.35s");
    });

    if (self.isPanelShowing && !self.searchField.isFirstResponder) {
        self.isKeyboardVisible = NO;
        CV3SetKeyboardSuppressedByPanel(YES);
        CV3LogToFile(@"[Warning][KeyboardDebug] suppressed background keyboard while panel is showing");
        return;
    }

    UIView *searchContainer = self.searchField.superview;
    if (!searchContainer || !searchContainer.superview) return;

    CGRect keyboardFrameInWindow = [self convertRect:keyboardFrame fromView:nil];
    keyboardFrameInWindow = CGRectIntersection(keyboardFrameInWindow, self.bounds);
    if (CGRectIsNull(keyboardFrameInWindow) || CGRectIsEmpty(keyboardFrameInWindow)) {
        CV3LogToFile(@"[Warning][KeyboardDebug] keyboard avoidance skipped empty intersection frame=%@ bounds=%@",
                     NSStringFromCGRect(keyboardFrame),
                     NSStringFromCGRect(self.bounds));
        return;
    }

    CGRect searchFrameInWindow = [searchContainer.superview convertRect:searchContainer.frame toView:self];
    CGRect criticalFrame = CGRectInset(searchFrameInWindow, 0.0, -kCV3KeyboardCriticalResultsReserve * 0.5);

    CGFloat overlap = 0.0;
    CGPoint moveVector = CGPointZero;
    switch (debugOrientation) {
        case UIInterfaceOrientationLandscapeLeft:
            overlap = CGRectGetMaxX(keyboardFrameInWindow) - CGRectGetMinX(criticalFrame);
            moveVector = CGPointMake(1.0, 0.0);
            break;
        case UIInterfaceOrientationLandscapeRight:
            overlap = CGRectGetMaxX(criticalFrame) - CGRectGetMinX(keyboardFrameInWindow);
            moveVector = CGPointMake(-1.0, 0.0);
            break;
        case UIInterfaceOrientationPortraitUpsideDown:
            overlap = CGRectGetMaxY(keyboardFrameInWindow) - CGRectGetMinY(criticalFrame);
            moveVector = CGPointMake(0.0, 1.0);
            break;
        case UIInterfaceOrientationPortrait:
        default:
            overlap = CGRectGetMaxY(criticalFrame) - CGRectGetMinY(keyboardFrameInWindow);
            moveVector = CGPointMake(0.0, -1.0);
            break;
    }

    CV3LogToFile(@"[Warning][KeyboardDebug] avoidance orientation=%ld keyboardInWindow=%@ critical=%@ overlap=%.2f center=%@",
                 (long)debugOrientation,
                 NSStringFromCGRect(keyboardFrameInWindow),
                 NSStringFromCGRect(criticalFrame),
                 overlap,
                 NSStringFromCGPoint(self.panelContainer.center));

    if (overlap > 0.0) {
        CGFloat offset = overlap + kCV3KeyboardAvoidanceBreath;

        [UIView animateWithDuration:duration delay:0 options:options animations:^{
            CGPoint center = self.panelContainer.center;
            center.x += moveVector.x * offset;
            center.y += moveVector.y * offset;
            self.panelContainer.center = [self clampedPanelCenterForCenter:center];
        } completion:nil];
    }
}

- (void)keyboardWillHide:(NSNotification *)notification {
    self.isKeyboardVisible = NO;
    
    NSDictionary *userInfo = notification.userInfo;
    double duration = [userInfo[UIKeyboardAnimationDurationUserInfoKey] doubleValue];
    UIViewAnimationOptions options = [userInfo[UIKeyboardAnimationCurveUserInfoKey] unsignedIntegerValue] << 16;
    CGRect keyboardFrame = [userInfo[UIKeyboardFrameEndUserInfoKey] CGRectValue];
    UIInterfaceOrientation debugOrientation = self.targetOrientation != UIInterfaceOrientationUnknown ? self.targetOrientation : UIInterfaceOrientationPortrait;
    CV3LogToFile(@"[Warning][KeyboardDebug] keyboardWillHide orientation=%ld frameEnd=%@ duration=%.3f searchFirstResponder=%d",
                 (long)debugOrientation,
                 NSStringFromCGRect(keyboardFrame),
                 duration,
                 self.searchField.isFirstResponder);

    // 键盘现场取证：收起后一拍快照（与 willShow 对比，确认键盘层退出状态）。
    static NSUInteger cv3KeyboardHideForensicsGeneration = 0;
    NSUInteger hideForensicsGeneration = ++cv3KeyboardHideForensicsGeneration;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.50 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (hideForensicsGeneration != cv3KeyboardHideForensicsGeneration) return;
        CV3DumpKeyboardForensics(@"willHide+0.50s");
    });
    
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
        if ([self isSystemUIActive]) return;

        BOOL launcherNeedsRecovery = (self.windowScene == nil || self.hidden);
        BOOL floatingNeedsRecovery = NO;

        for (CV3FloatingAppWindow *win in floatingWindows) {
            if (![win isKindOfClass:[CV3FloatingAppWindow class]] || win.isClosing || win.isStashed) continue;
            BOOL hostDisconnected = (win.windowScene == nil || win.targetScene == nil || win.hostView == nil);
            BOOL visibilityDrift = win.hidden;
            if (hostDisconnected || visibilityDrift) {
                floatingNeedsRecovery = YES;
                break;
            }
        }

        if (!launcherNeedsRecovery && !floatingNeedsRecovery && !self.isPanelShowing) {
            return;
        }

        if (launcherNeedsRecovery || self.isPanelShowing) {
            [self attachToCurrentActiveScene];
        }

        for (CV3FloatingAppWindow *win in floatingWindows) {
            if ([win isKindOfClass:[CV3FloatingAppWindow class]] &&
                !win.isClosing &&
                !win.isStashed &&
                (floatingNeedsRecovery || win.windowScene == nil || win.targetScene == nil || win.hostView == nil || win.hidden) &&
                [win respondsToSelector:@selector(attachToCurrentActiveScene)]) {
                [win attachToCurrentActiveScene];
            }
        }
    } @catch (NSException *e) {
    }
}

- (BOOL)_shouldAutorotateToInterfaceOrientation:(long long)orientation { return NO; }

- (BOOL)isSystemUIActive {
    if (CV3LockScreenPresented || CV3ControlCenterPresented || CV3GestureCoverSheetPresented) {
        return YES;
    }

    @try {
        id cc = CV3InvokeObject(CV3ClassNamed(@"SBControlCenterController"), @selector(sharedInstance));
        if (cc && CV3InvokeBool(cc, @selector(isPresented), NO)) {
            return YES;
        }
        
        id cs = CV3InvokeObject(CV3ClassNamed(@"SBCoverSheetPresentationManager"), @selector(sharedInstance));
        if (cs && CV3InvokeBool(cs, @selector(isAnyCoverSheetVisible), NO)) {
            return YES;
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
            targetScene = CV3InvokeObject(CV3ClassNamed(@"SBWindowScene"), @selector(mainDisplayWindowScene));
            if (targetScene) {
                NSString *role = targetScene.session.role;
                if ([role isEqualToString:@"SBWindowSceneSessionRoleSystemAperture"] ||
                    [role isEqualToString:@"SBWindowSceneSessionRoleSystemApertureCurtain"] ||
                    [role isEqualToString:@"UISceneSessionRolePlaceholder"] ||
                    [[role lowercaseString] containsString:@"siri"]) {
                    targetScene = nil;
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

                // A scene reattachment may leave the launcher window hidden.
                if (self.hidden) {
                    self.hidden = NO;
                    needsLayoutUpdate = YES;
                }

                CV3SceneRotationContext context = CV3MakeSceneRotationContext(targetScene);
                if (CV3SceneRotationContextNeedsApply(self.targetOrientation, self.baseRotationTransform, context, NO)) {
                    self.targetOrientation = context.orientation;
                    self.baseRotationTransform = context.transform;
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
    CGFloat targetLevel = self.isSuppressedBySystem ? CV3Style.background : CV3Style.panel;
    
    if (self.windowLevel != targetLevel) {
        self.windowLevel = targetLevel;
    }
}

- (void)setSystemUILevelSuppressed:(BOOL)suppressed {
    BOOL stateChanged = self.isSuppressedBySystem != suppressed;
    self.isSuppressedBySystem = suppressed;
    [self applyAdaptiveLevel];

    if (stateChanged) {
        CV3LogToFile(@"[SystemUILevel] suppressed=%d hidden=%d alpha=%.2f level=%.1f panelShowing=%d",
                     suppressed, self.hidden, self.alpha, self.windowLevel, self.isPanelShowing);
    }
}

- (NSInteger)collectionView:(id)c numberOfItemsInSection:(NSInteger)s { return self.filteredApps.count; }
- (id)collectionView:(id)c cellForItemAtIndexPath:(id)i {
    CV3AppCell *cell = [c dequeueReusableCellWithReuseIdentifier:@"C" forIndexPath:i];
    NSInteger index = [(NSIndexPath *)i item];
    CV3AppInfo *info = self.filteredApps[index];
    
    // 增加首项判断逻辑，用于开启搜索首项高亮
    BOOL isFirst = (index == 0 && self.searchField.text.length > 0);
    CV3AppPanelProtectionState protectionState = CV3AppPanelProtectionStateForBundleID(info.bundleId);
    [cell configureWithInfo:info searchText:self.searchField.text isFirst:isFirst protectionState:protectionState];
    [self loadIconForAppInfo:info cell:cell];

    // 应用“熵减”衰老视觉效果
    [self applyAgingEffectToCell:cell withInfo:info];

    // 复用池里的 Cell 可能还带着上一轮的呼吸动画，按当前面板状态对齐。
    // 面板出现前由 CV3RemoveViewAnimationsRecursively 清过一次，这里是唯一重挂点之一。
    [self applyBreathingToCell:cell];

    return cell;
}

- (BOOL)applyBreathingToCell:(CV3AppCell *)cell {
    if (![cell isKindOfClass:[CV3AppCell class]]) return NO;
    if (self.isPanelShowing) return [cell startBreathing];
    [cell stopBreathing];
    return NO;
}

- (void)syncAppCellBreathing {
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self syncAppCellBreathing];
        });
        return;
    }

    NSUInteger visible = 0;
    NSUInteger breathing = 0;
    NSUInteger readded = 0;
    for (UICollectionViewCell *cell in self.collectionView.visibleCells) {
        if (![cell isKindOfClass:[CV3AppCell class]]) continue;
        visible++;
        if ([self applyBreathingToCell:(CV3AppCell *)cell]) readded++;
        if ([((CV3AppCell *)cell) hasBreathingAnimation]) breathing++;
    }

    CV3LogToFile(@"[BreathingTrace] phase=sync panelShowing=%d visible=%lu breathing=%lu readded=%lu reduceMotion=%d",
                 self.isPanelShowing,
                 (unsigned long)visible,
                 (unsigned long)breathing,
                 (unsigned long)readded,
                 UIAccessibilityIsReduceMotionEnabled());
}

- (void)collectionView:(id)c didEndDisplayingCell:(UICollectionViewCell *)cell forItemAtIndexPath:(id)i {
    // 离屏 Cell 不需要继续呼吸，复用池里的残留动画在 cellForItem 时统一对齐。
    if ([cell isKindOfClass:[CV3AppCell class]]) {
        [(CV3AppCell *)cell stopBreathing];
    }
}


- (BOOL)_canBecomeKeyWindow { return YES; }
- (BOOL)canBecomeKeyWindow { return YES; }
- (BOOL)_ignoresHitTest { return NO; }
- (BOOL)_shouldIsolate { return YES; }

#pragma mark - Window visibility
- (void)setHidden:(BOOL)hidden {
    [super setHidden:hidden];
    
    // 状态同步
    if (hidden) {
        CV3SetKeyboardSuppressedByPanel(NO);
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
    if ([e isKindOfClass:[UIEvent class]] && ((UIEvent *)e).type == UIEventTypeTouches) {
        for (UITouch *touch in ((UIEvent *)e).allTouches) {
            UIWindow *sourceWindow = touch.window;
            if (sourceWindow && sourceWindow != self) {
                CV3LogToFile(@"[LauncherTouch] phase=hitTest.reject reason=foreignWindow sourceWindow=%@ point=%@",
                             NSStringFromClass(sourceWindow.class), NSStringFromCGPoint(point));
                return nil;
            }
        }
    }

    if (self.isPanelShowing) {
        // 1. 优先检查搜索框及其容器（最高优先级，防止被拖拽拦截）
        UIView *searchContainer = self.searchField.superview;
        CGPoint pInSearch = [self convertPoint:point toView:searchContainer];
        if (CGRectContainsPoint(searchContainer.bounds, pInSearch)) {
            UIView *hit = [searchContainer hitTest:pInSearch withEvent:e];
            UIInterfaceOrientation orientation = self.targetOrientation != UIInterfaceOrientationUnknown ? self.targetOrientation : UIInterfaceOrientationPortrait;
            CV3LogToFile(@"[Warning][KeyboardDebug] hitTest searchArea point=%@ pInSearch=%@ hit=%@ orientation=%ld fieldWindow=%@",
                         NSStringFromCGPoint(point),
                         NSStringFromCGPoint(pInSearch),
                         hit,
                         (long)orientation,
                         self.searchField.window);
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
        
        // 3. 触控外部拦截：点击面板外部时返回主窗口自身，拦截触控并触发收起手势
        return self;
    }

    // 触控透传架构: 当面板隐藏时，CV3Window 的 hitTest 返回 nil，实现完全透传，
    // 让底层 App 窗口直接接收并处理手势，由 hostWindow 上的 systemEdgePan 触发。
    return nil;
}

@end
