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

static void CV3OpenApplicationFast(NSString *bundleID, NSString *reason) {
    if (bundleID.length == 0) return;

    CV3ExitExposeModeIfNeeded(nil, NO);
    
    NSString *currentActive = CV3CurrentWorkspaceBundleID();
    CV3LogToFile(@"[Launcher] Fast open 准备启动: %@, 当前前台App: %@, reason: %@", bundleID, currentActive, reason ?: @"Unknown");

    // 建议 2：使用高优先级全局队列异步启动，防止主线程 UI 渲染被阻塞以实现秒级跳转
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
        @try {
            id workspace = [CV3ClassNamed(@"LSApplicationWorkspace") defaultWorkspace];
            BOOL opened = NO;
            if (workspace) {
                if ([workspace respondsToSelector:@selector(openApplicationWithBundleID:)]) {
                    opened = ((BOOL (*)(id, SEL, id))objc_msgSend)(workspace, @selector(openApplicationWithBundleID:), bundleID);
                    CV3LogToFile(@"[Launcher] Fast open 调用结果: target=%@, 成功=%d, 前台App=%@", bundleID, opened, CV3CurrentWorkspaceBundleID());
                } else {
                    CV3LogToFile(@"[Launcher] Fast open 错误: LSApplicationWorkspace 不响应 openApplicationWithBundleID:");
                }
            } else {
                CV3LogToFile(@"[Launcher] Fast open 错误: LSApplicationWorkspace 为 nil");
            }

            if (!opened) {
                // 降级使用 SpringBoard 进程内直接启动机制，必须在主线程执行
                dispatch_async(dispatch_get_main_queue(), ^{
                    @try {
                        id sb = [UIApplication sharedApplication];
                        if ([sb respondsToSelector:@selector(launchApplicationWithIdentifier:suspended:)]) {
                            CV3LogToFile(@"[Launcher] 尝试 SpringBoard 级联降级启动: %@", bundleID);
                            ((void (*)(id, SEL, id, BOOL))objc_msgSend)(sb, @selector(launchApplicationWithIdentifier:suspended:), bundleID, NO);
                        } else {
                            CV3LogToFile(@"[Launcher] SpringBoard 不支持 launchApplicationWithIdentifier:suspended:");
                        }
                    } @catch (NSException *ex) {
                        CV3LogToFile(@"[Launcher] SpringBoard 级联降级异常: %@", ex);
                    }
                });
            }
        } @catch (NSException *e) {
            CV3LogToFile(@"[Launcher] Fast open 异常 %@: %@", bundleID, e);
        }
    });
}

__attribute__((unused)) static id CV3SpringBoardIconForBundleID(NSString *bundleID) {
    if (bundleID.length == 0) return nil;

    @try {
        id iconController = [CV3ClassNamed(@"SBIconController") sharedInstance];
        id iconModel = nil;
        id iconManager = CV3InvokeObject(iconController, @selector(iconManager));
        if (iconManager) iconModel = CV3InvokeObject(iconManager, @selector(model));
        if (!iconModel) iconModel = CV3InvokeObject(iconController, @selector(model));

        for (id icon in CV3InvokeObject(iconModel, @selector(leafIcons))) {
            NSString *iconBundleID = CV3InvokeObject(icon, @selector(applicationBundleID));
            if (iconBundleID.length == 0) iconBundleID = CV3InvokeObject(icon, @selector(leafIdentifier));
            if ([iconBundleID isEqualToString:bundleID]) return icon;
        }
    } @catch (NSException *e) {
        CV3LogToFile(@"[Launcher] 查找 SBIcon 异常 %@: %@", bundleID, e);
    }

    return nil;
}

__attribute__((unused)) static BOOL CV3LaunchSpringBoardIconFast(CV3AppInfo *info, NSString *reason) {
    if (info.bundleId.length == 0) return NO;

    CV3ExitExposeModeIfNeeded(nil, NO);

    id icon = info.sbIcon ?: CV3SpringBoardIconForBundleID(info.bundleId);
    if (!icon) return NO;

    NSString *location = @"ChevronLauncher";

    @try {
        SEL launchFromLocationContext = @selector(launchFromLocation:context:);
        if ([icon respondsToSelector:launchFromLocationContext]) {
            ((void (*)(id, SEL, id, id))objc_msgSend)(icon, launchFromLocationContext, location, nil);
            CV3LogToFile(@"[Launcher] SBIcon launchFromLocation:context: %@ (%@)", info.bundleId, reason ?: @"Unknown");
            return YES;
        }

        SEL privateLaunchFromLocationContext = @selector(_launchFromLocation:context:);
        if ([icon respondsToSelector:privateLaunchFromLocationContext]) {
            ((void (*)(id, SEL, id, id))objc_msgSend)(icon, privateLaunchFromLocationContext, location, nil);
            CV3LogToFile(@"[Launcher] SBIcon _launchFromLocation:context: %@ (%@)", info.bundleId, reason ?: @"Unknown");
            return YES;
        }

        SEL launchFromLocation = @selector(launchFromLocation:);
        if ([icon respondsToSelector:launchFromLocation]) {
            ((void (*)(id, SEL, id))objc_msgSend)(icon, launchFromLocation, location);
            CV3LogToFile(@"[Launcher] SBIcon launchFromLocation: %@ (%@)", info.bundleId, reason ?: @"Unknown");
            return YES;
        }

        SEL launch = @selector(launch);
        if ([icon respondsToSelector:launch]) {
            ((void (*)(id, SEL))objc_msgSend)(icon, launch);
            CV3LogToFile(@"[Launcher] SBIcon launch %@ (%@)", info.bundleId, reason ?: @"Unknown");
            return YES;
        }
    } @catch (NSException *e) {
        CV3LogToFile(@"[Launcher] SBIcon launch 异常 %@: %@", info.bundleId, e);
    }

    @try {
        id iconController = [CV3ClassNamed(@"SBIconController") sharedInstance];
        NSArray<NSString *> *controllerSelectors = @[
            @"launchIcon:fromLocation:",
            @"_launchIcon:fromLocation:",
            @"launchIcon:"
        ];

        for (NSString *selectorName in controllerSelectors) {
            SEL selector = NSSelectorFromString(selectorName);
            if (![iconController respondsToSelector:selector]) continue;

            if ([selectorName hasSuffix:@":fromLocation:"]) {
                ((void (*)(id, SEL, id, id))objc_msgSend)(iconController, selector, icon, location);
            } else {
                ((void (*)(id, SEL, id))objc_msgSend)(iconController, selector, icon);
            }
            CV3LogToFile(@"[Launcher] SBIconController %@ %@ (%@)", selectorName, info.bundleId, reason ?: @"Unknown");
            return YES;
        }
    } @catch (NSException *e) {
        CV3LogToFile(@"[Launcher] SBIconController launch 异常 %@: %@", info.bundleId, e);
    }

    return NO;
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

// Entry point shared by the launcher and notification taps. Notification
// callbacks are owned by SpringBoard, so keep all hosted-window work on the
// main thread and do not require the launcher panel to be visible.
static BOOL CV3OpenBundleInFloatingWindow(NSString *bundleID, NSString *reason) {
    if (bundleID.length == 0) return NO;

    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            CV3OpenBundleInFloatingWindow(bundleID, reason);
        });
        return YES;
    }

    if (CV3EnsureFreshClientBridgeBeforeHosting(bundleID, ^{
        CV3OpenBundleInFloatingWindow(bundleID, reason);
    })) {
        return YES;
    }

    CV3FloatingAppWindow *existingWindow = CV3FloatingWindowForBundleID(bundleID);
    if (existingWindow) {
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

    floatingWindow.targetOrientation = CV3TrustedInterfaceOrientation(scene);
    [floatingWindows addObject:floatingWindow];
    [floatingWindow makeKeyAndVisible];
    floatingWindow.windowLevel = CV3Style.floatingApp;
    CV3RefreshFloatingHomeBarAfterPresentation(floatingWindow);
    CV3UpdateFloatingBackdrop(scene);
    [[NSNotificationCenter defaultCenter] postNotificationName:CV3FloatingWindowsDidChangeNotification object:nil];
    CV3LogToFile(@"[NotificationSplit] 通知点击开启分屏: %@ (%@)", bundleID, reason ?: @"Unknown");
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
    [view.layer removeAllAnimations];
    for (UIView *subview in view.subviews) {
        CV3RemoveViewAnimationsRecursively(subview);
    }
}

static void CV3CancelHomeScreenPanRecognizersInView(UIView *view, UIGestureRecognizer *ownedGesture) {
    if (!view) return;

    for (UIGestureRecognizer *recognizer in view.gestureRecognizers) {
        if (recognizer == ownedGesture || !recognizer.enabled ||
            ![recognizer isKindOfClass:[UIPanGestureRecognizer class]]) {
            continue;
        }

        // Toggling enabled cancels this touch sequence without disabling the
        // Home Screen gesture for the user's next interaction.
        recognizer.enabled = NO;
        recognizer.enabled = YES;
    }

    NSString *className = NSStringFromClass([view class]);
    if ([className containsString:@"IconView"]) return;
    for (UIView *subview in view.subviews) {
        CV3CancelHomeScreenPanRecognizersInView(subview, ownedGesture);
    }
}

static void CV3CancelCompetingHomeScreenPans(UIGestureRecognizer *ownedGesture) {
    for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
        if (![scene isKindOfClass:[UIWindowScene class]]) continue;
        for (UIWindow *window in ((UIWindowScene *)scene).windows) {
            NSString *windowClass = NSStringFromClass([window class]);
            if (![windowClass containsString:@"HomeScreenWindow"]) continue;
            CV3CancelHomeScreenPanRecognizersInView(window, ownedGesture);
        }
    }
}

static void CV3FinalizePanelHiddenState(CV3Window *launcherWindow) {
    if (!launcherWindow) return;

    launcherWindow.interactionCount++;
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
        launcherWindow.appPanel.alpha = 0.0;
        launcherWindow.collectionView.alpha = 0.0;
        launcherWindow.contrastBackdrop.hidden = YES;
        launcherWindow.bezierContainer.alpha = 0.0;
        launcherWindow.bezierLayer.opacity = 0.0;
        launcherWindow.bezierLayer.shadowOpacity = 0.0;
        launcherWindow.bezierLayer.path = nil;
        [CATransaction commit];
    }];
    [CATransaction flush];
}

static void CV3HidePanelImmediately(CV3Window *launcherWindow) {
    if (!launcherWindow) return;

    CV3SetKeyboardSuppressedByPanel(NO);
    CV3SetHomeScreenPullDownSuppressed(NO);
    launcherWindow.isPanelShowing = NO;
    launcherWindow.isAnimating = NO;
    CV3FinalizePanelHiddenState(launcherWindow);
    [launcherWindow.searchField resignFirstResponder];
}

@implementation CV3Window

- (void)applyBackgroundTint:(UIColor *)color {
    (void)color;
    [UIView animateWithDuration:0.8 animations:^{
        self.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:CV3Style.maskAlpha];
        [self refreshGlassAccentSurfaces];
    }];
}

- (void)refreshGlassAccentSurfaces {
    if (self.appPanel) {
        self.appPanel.contentView.backgroundColor = [UIColor clearColor];
        self.appPanel.layer.borderColor = [[UIColor whiteColor] colorWithAlphaComponent:self.isPanelShowing ? 0.18 : 0.12].CGColor;
        self.appPanel.layer.borderWidth = 0.5 / [UIScreen mainScreen].scale;
    }

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
    [button setTitleColor:[UIColor labelColor] forState:UIControlStateNormal];
}

- (void)handleDoubleTap:(UITapGestureRecognizer *)gesture {
    CV3ExitExposeModeIfNeeded(nil, NO);
    // 建议 5：搜索极速启动
    // 如果搜索框有内容且有结果，双击面板直接启动第一个
    if (self.searchField.text.length > 0 && self.filteredApps.count > 0) {
        [self launchApp:self.filteredApps[0]];
        return;
    }
    
    [self.feedback impactOccurred];
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
        UINotificationFeedbackGenerator *blockedFeedback = [[UINotificationFeedbackGenerator alloc] init];
        [blockedFeedback notificationOccurred:UINotificationFeedbackTypeWarning];
        CV3LogToFile(@"[Launcher] 已阻止主App面板操作: 目标=%@, 原因=%@",
                     bid,
                     CV3AppPanelProtectionReason(protectionState) ?: @"Unknown");
        [self.collectionView reloadData];
        return;
    }

    if (self.launchDebounce) return;
    CV3ExitExposeModeIfNeeded(nil, NO);
    self.launchDebounce = YES;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.4 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        self.launchDebounce = NO;
    });

    UIImpactFeedbackGenerator *launcherImpact = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium];
    [launcherImpact impactOccurred];

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

    [self animateSpotlight:NO fromPoint:self.panelContainer.center velocity:0.0];
    CV3OpenApplicationFast(bid, [NSString stringWithFormat:@"LauncherOpen:%@", bid]);
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

    // 列表刷新后只保留轻量入场动画，避免旧的磁吸/波纹 transform 干扰图标漂浮。
    NSInteger filterGeneration = self.interactionCount;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.01 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (filterGeneration != self.interactionCount) return;
        if (!CV3ScrollViewIsActivelyControlled(self.collectionView)) {
            [self animateIconsStaggered];
        }
        if (hasSearch && self.filteredApps.count > 0) {
            [self.feedback impactOccurredWithIntensity:0.75];
        }
    });

    UIInterfaceOrientation accessoryOrientation = self.targetOrientation != UIInterfaceOrientationUnknown ? self.targetOrientation : UIInterfaceOrientationPortrait;
    BOOL accessoryAllowed = !UIInterfaceOrientationIsLandscape(accessoryOrientation);

    // 优化：仅在必要时刷新 inputAccessoryView。横屏时禁用，避免键盘附件脱离主面板旋转坐标。
    if (!hasSearch && accessoryAllowed) {
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
        UIInterfaceOrientation orientation = self.targetOrientation != UIInterfaceOrientationUnknown ? self.targetOrientation : UIInterfaceOrientationPortrait;
        CV3LogToFile(@"[Warning][KeyboardDebug] didBegin searchField orientation=%ld isFirstResponder=%d window=%@ keyWindow=%d accessory=%@ inputView=%@",
                     (long)orientation,
                     textField.isFirstResponder,
                     textField.window,
                     self.isKeyWindow,
                     textField.inputAccessoryView,
                     textField.inputView);
        UIView *container = textField.superview;
        
        // 建议2：搜索框液态响应 (Liquid Search Focus)
        // 面板圆角呼吸动画：28pt -> 32pt -> 28pt
        CABasicAnimation *cornerAnim = [CABasicAnimation animationWithKeyPath:@"cornerRadius"];
        cornerAnim.fromValue = @(CV3Style.cornerRadius);
        cornerAnim.toValue = @(32.0);
        cornerAnim.duration = 0.6;
        cornerAnim.autoreverses = YES;
        cornerAnim.repeatCount = HUGE_VALF;
        cornerAnim.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
        [self.appPanel.layer addAnimation:cornerAnim forKey:@"liquidCorner"];

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
        [self.appPanel.layer removeAnimationForKey:@"liquidCorner"];

        [UIView animateWithDuration:0.3 animations:^{
            container.transform = CGAffineTransformIdentity;
            self.searchBackground.shadowOpacity = 0;
            self.searchBackground.shadowRadius = 0;
            self.searchBackground.path = [UIBezierPath bezierPathWithRoundedRect:self.searchBackground.bounds cornerRadius:10].CGPath;
            self.searchBackground.strokeColor = [[UIColor whiteColor] colorWithAlphaComponent:0.1].CGColor;
        }];
    }
}

- (void)collectionView:(UICollectionView *)cv didSelectItemAtIndexPath:(NSIndexPath *)indexPath {
    [cv deselectItemAtIndexPath:indexPath animated:NO];

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

    // 如果是绑定在 UIWindow 上的全屏 tap 收起手势，且触点在面板物理边界内，不拦截，让子视图（如 CollectionView Cell）正常接收触控
    if (gestureRecognizer.view == self) {
        CGPoint location = [touch locationInView:self.panelContainer];
        if (CGRectContainsPoint(self.panelContainer.bounds, location)) {
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

- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)gesture {
    if (gesture == self.systemEdgePan) {
        if (self.isPanelShowing) {
            return NO;
        }

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
        self.feedback = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleHeavy];
        self.selectionFeedback = [[UISelectionFeedbackGenerator alloc] init];
        
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
    
    self.bezierBlur = [[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemUltraThinMaterial]];
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



    self.trafficCapsule = [[UIView alloc] initWithFrame:CGRectMake(16, 14, CV3Style.trafficCapsuleW, CV3Style.trafficCapsuleH)];
    self.trafficCapsule.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.08];
    self.trafficCapsule.layer.cornerRadius = CV3Style.trafficCapsuleH / 2.0;
    [self.panelContainer addSubview:self.trafficCapsule];
    
    NSMutableArray *dots = [NSMutableArray array];
    NSArray *tc = @[[UIColor colorWithRed:1.00 green:0.37 blue:0.33 alpha:1.0], [UIColor colorWithRed:1.00 green:0.75 blue:0.18 alpha:1.0], [UIColor colorWithRed:0.15 green:0.79 blue:0.25 alpha:1.0]];
    for (int i = 0; i < 3; i++) {
        UIButton *dotBtn = [UIButton buttonWithType:UIButtonTypeCustom];
        // 扩展热区：每个按钮占据更大的点击范围 (约 17.3x24)
        CGFloat btnW = (CV3Style.trafficCapsuleW - 12) / 3.0;
        dotBtn.frame = CGRectMake(6 + i * btnW, 0, btnW, CV3Style.trafficCapsuleH);
        
        // 视觉圆点作为子视图，保持原有 8x8 外观
        UIView *visualDot = [[UIView alloc] initWithFrame:CGRectMake((btnW - CV3Style.trafficDotSize)/2, (CV3Style.trafficCapsuleH - CV3Style.trafficDotSize)/2, CV3Style.trafficDotSize, CV3Style.trafficDotSize)];
        visualDot.backgroundColor = tc[i];
        visualDot.layer.cornerRadius = CV3Style.trafficDotSize / 2.0;
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
    UIView *searchContainer = [[UIView alloc] initWithFrame:CGRectMake(15, 50, CV3Style.panelW - 30, 36)];
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
    self.noResultsLabel = [[UILabel alloc] initWithFrame:CGRectMake(0, 150, CV3Style.panelW, 40)];
    self.noResultsLabel.text = @"未找到相关应用";
    self.noResultsLabel.textColor = [UIColor secondaryLabelColor];
    self.noResultsLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightMedium];
    self.noResultsLabel.textAlignment = NSTextAlignmentCenter;
    self.noResultsLabel.hidden = YES;
    [self.appPanel.contentView addSubview:self.noResultsLabel];

    self.selectedCategory = @"全部";
    self.categoryBar = [[UIScrollView alloc] initWithFrame:CGRectMake(15, 96, CV3Style.panelW - 30, 40)];
    self.categoryBar.showsHorizontalScrollIndicator = NO;
    self.categoryBar.backgroundColor = [UIColor clearColor];
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
    self.collectionView = [[UICollectionView alloc] initWithFrame:CGRectMake(0, 140, CV3Style.panelW, CV3Style.panelH-140) collectionViewLayout:layout];
    self.collectionView.dataSource = self; self.collectionView.delegate = self;
    self.collectionView.backgroundColor = [UIColor clearColor];
    self.collectionView.delaysContentTouches = NO; // 关键：禁用触碰延迟实现即时反馈
    self.collectionView.showsVerticalScrollIndicator = NO;   // 隐藏纵向滚动条
    self.collectionView.showsHorizontalScrollIndicator = NO; // 隐藏横向滚动条
    self.collectionView.keyboardDismissMode = UIScrollViewKeyboardDismissModeOnDrag; // 滚动时自动收起键盘
    [self.collectionView registerClass:[CV3AppCell class] forCellWithReuseIdentifier:@"C"];
    [self.appPanel.contentView addSubview:self.collectionView];

    // 增加长按置顶手势
    UILongPressGestureRecognizer *pinLongPress = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(handleAppLongPress:)];
    pinLongPress.minimumPressDuration = 0.6;
    pinLongPress.allowableMovement = kCV3AppDragLongPressAllowableMovement;
    pinLongPress.delegate = self;
    [self.collectionView addGestureRecognizer:pinLongPress];
}


- (CGRect)splitDropPreviewFrameForCenter:(CGPoint)center {
    CGRect screen = self.windowScene ? self.windowScene.coordinateSpace.bounds : self.bounds;
    if (CGRectIsEmpty(screen)) screen = [UIScreen mainScreen].bounds;

    UIInterfaceOrientation orientation = CV3TrustedInterfaceOrientation(self.windowScene);
    BOOL isLandscape = UIInterfaceOrientationIsLandscape(orientation);
    CGFloat portraitW = MIN(screen.size.width, screen.size.height);
    CGFloat portraitH = MAX(screen.size.width, screen.size.height);
    CGFloat logicalW = portraitW * 0.45;
    CGFloat logicalH = logicalW * (portraitH / MAX(portraitW, 1.0));
    CGSize physicalSize = isLandscape ? CGSizeMake(logicalH, logicalW) : CGSizeMake(logicalW, logicalH);

    UIEdgeInsets safe = self.safeAreaInsets;
    CGFloat breath = CV3Style.safeAreaBreath;
    CGFloat visibleW = MAX(1.0, screen.size.width - safe.left - safe.right - breath * 2.0);
    CGFloat visibleH = MAX(1.0, screen.size.height - safe.top - safe.bottom - breath * 2.0);
    CGFloat fitScale = MIN(1.0, MIN(visibleW / MAX(physicalSize.width, 1.0),
                                   visibleH / MAX(physicalSize.height, 1.0)));
    if (fitScale < 1.0) {
        physicalSize.width *= fitScale;
        physicalSize.height *= fitScale;
    }

    CGRect frame = CGRectMake(center.x - physicalSize.width * 0.5,
                              center.y - physicalSize.height * 0.5,
                              physicalSize.width,
                              physicalSize.height);

    CGFloat minX = safe.left + breath;
    CGFloat minY = safe.top + breath;
    CGFloat maxX = screen.size.width - safe.right - breath - frame.size.width;
    CGFloat maxY = screen.size.height - safe.bottom - breath - frame.size.height;
    if (maxX < minX) maxX = minX;
    if (maxY < minY) maxY = minY;
    frame.origin.x = MIN(MAX(frame.origin.x, minX), maxX);
    frame.origin.y = MIN(MAX(frame.origin.y, minY), maxY);
    return frame;
}

- (void)layoutSplitDropPreviewLayer {
    if (!self.splitDropPreviewView || !self.splitDropPreviewLayer) return;

    CGRect bounds = self.splitDropPreviewView.bounds;
    UIInterfaceOrientation orientation = CV3TrustedInterfaceOrientation(self.windowScene);
    BOOL isLandscape = UIInterfaceOrientationIsLandscape(orientation);
    CGSize logicalSize = isLandscape
        ? CGSizeMake(MIN(bounds.size.width, bounds.size.height), MAX(bounds.size.width, bounds.size.height))
        : bounds.size;
    CGRect logicalBounds = CGRectMake(0, 0, logicalSize.width, logicalSize.height);
    CGFloat cornerRadius = MIN(CV3Style.floatingChromeCornerRadius, MIN(logicalSize.width, logicalSize.height) * 0.5);
    UIBezierPath *path = [UIBezierPath bezierPathWithRoundedRect:CGRectInset(logicalBounds, 2.0, 2.0)
                                                    cornerRadius:cornerRadius];
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    self.splitDropPreviewLayer.bounds = logicalBounds;
    self.splitDropPreviewLayer.position = CGPointMake(CGRectGetMidX(bounds), CGRectGetMidY(bounds));
    self.splitDropPreviewLayer.path = path.CGPath;
    self.splitDropPreviewLayer.cornerRadius = cornerRadius;
    [self.splitDropPreviewLayer setAffineTransform:CV3RotationTransformForInterfaceOrientation(orientation)];
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
                UINotificationFeedbackGenerator *blockedFeedback = [[UINotificationFeedbackGenerator alloc] init];
                [blockedFeedback notificationOccurred:UINotificationFeedbackTypeWarning];
                CV3LogToFile(@"[Launcher] 已阻止主App面板长按操作: 目标=%@, 原因=%@",
                             self.draggedAppInfo.bundleId,
                             CV3AppPanelProtectionReason(protectionState) ?: @"Unknown");
                self.draggedAppInfo = nil;
                [self.collectionView reloadData];
                return;
            }

            CV3ExitExposeModeIfNeeded(nil, NO);
            
            [self.feedback impactOccurredWithIntensity:0.85];
            
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
                UINotificationFeedbackGenerator *blockedFeedback = [[UINotificationFeedbackGenerator alloc] init];
                [blockedFeedback notificationOccurred:UINotificationFeedbackTypeWarning];
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
                [self.feedback impactOccurredWithIntensity:1.0];
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
                        floatingWindow.targetOrientation = CV3TrustedInterfaceOrientation(self.windowScene);
                        [floatingWindows addObject:floatingWindow];
                        [floatingWindow makeKeyAndVisible];
                        floatingWindow.windowLevel = CV3Style.floatingApp;
                        CV3RefreshFloatingHomeBarAfterPresentation(floatingWindow);
                        CV3UpdateFloatingBackdrop(self.windowScene);
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
                    [self hideSplitDropPreviewAnimated:NO];
                    [self.draggedIconView removeFromSuperview];
                    self.draggedIconView = nil;
                    self.draggedAppInfo = nil;
                    [self loadAppsAsync];
                }];
            }
        }
    }
}

- (void)handleCategoryTap:(UIButton *)sender {
    CV3ExitExposeModeIfNeeded(nil, NO);
    [self.searchField resignFirstResponder];
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

        // 建议1：触觉反馈深度耦合 (Haptic Coupling)
        // 如果检测到位置发生了磁吸偏移，触发一次刚性震动
        if (!CGPointEqualToPoint(currentCenter, targetCenter)) {
            UIImpactFeedbackGenerator *rigid = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleRigid];
            [rigid impactOccurredWithIntensity:1.0];
        }

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
    CV3ExitExposeModeIfNeeded(nil, NO);
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

- (void)handleTrafficLight:(UIButton *)sender {
    CV3ExitExposeModeIfNeeded(nil, NO);
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
            CGFloat targetW = MIN(CV3Style.panelW, maxSize.width);
            CGFloat targetH = MIN(CV3Style.panelH, maxSize.height);
            targetH = MAX(targetH, CV3Style.minHeight);
            
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

    switch (orientation) {
        case UIInterfaceOrientationLandscapeLeft:
            self.systemEdgePan.edges = UIRectEdgeTop;
            self.edgeTriggerView.frame = CGRectMake(0, 0, w, CV3Style.triggerHotzoneWidth);
            break;
        case UIInterfaceOrientationLandscapeRight:
            self.systemEdgePan.edges = UIRectEdgeBottom;
            self.edgeTriggerView.frame = CGRectMake(0, h - CV3Style.triggerHotzoneWidth, w, CV3Style.triggerHotzoneWidth);
            break;
        case UIInterfaceOrientationPortraitUpsideDown:
            self.systemEdgePan.edges = UIRectEdgeLeft;
            self.edgeTriggerView.frame = CGRectMake(0, safe.top, CV3Style.triggerHotzoneWidth, h - safe.top - CV3Style.triggerBottomOffset);
            break;
        case UIInterfaceOrientationPortrait:
        default:
            self.systemEdgePan.edges = UIRectEdgeRight;
            self.edgeTriggerView.frame = CGRectMake(w - CV3Style.triggerHotzoneWidth, safe.top, CV3Style.triggerHotzoneWidth, h - safe.top - CV3Style.triggerBottomOffset);
            break;
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
            
            self.trafficCapsule.frame = CGRectMake(16, 14, CV3Style.trafficCapsuleW, CV3Style.trafficCapsuleH);
            [self updateResizingHandleFrame];
            
            [CATransaction begin];
            [CATransaction setDisableActions:YES];
            self.contrastBackdrop.frame = self.appPanel.bounds;
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
    
    // 在 layoutSubviews 结尾更新 shadowPath，保证在拖动或 resize 时阴影能同步 bounds 并采用硬件加速
    if (self.isPanelShowing) {
        self.panelContainer.layer.shadowPath = [UIBezierPath bezierPathWithRoundedRect:self.panelContainer.bounds cornerRadius:CV3Style.cornerRadius].CGPath;
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
        CV3CancelCompetingHomeScreenPans(gesture);
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
            CGFloat triggerProgress = MIN(1.0, MAX(0.0, stretch / MAX(triggerDistance, 1.0)));
            CGFloat hapticInterval = MAX(8.0, 20.0 - triggerProgress * 12.0);
            if (fabs(stretch - self.lastHapticX) > hapticInterval) {
                UIImpactFeedbackGenerator *rigid = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleRigid];
                [rigid impactOccurredWithIntensity:0.3 + triggerProgress * 0.4];
                
                AudioServicesPlaySystemSound(1104); 
                self.lastHapticX = stretch;
            }

            if (stretch > triggerDistance) {
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

        if (self.bezierContainer.alpha > 0 && !self.isPanelShowing && vel > 300 && gesture.state != UIGestureRecognizerStateCancelled) {
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
    if (self.isPanelShowing || self.isAnimating || CV3PendingPanelPresentation) return;

    __weak CV3Window *weakSelf = self;
    CV3QueuePanelPresentationAfterSystemGesture(^{
        CV3Window *strongSelf = weakSelf;
        if (!strongSelf || strongSelf.isPanelShowing || strongSelf.isAnimating) return;
        [strongSelf animateSpotlight:YES fromPoint:point velocity:velocity];
    });
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
    if (visible) {
        CV3SetHomeScreenPullDownSuppressed(YES);
        CV3ExitExposeModeIfNeeded(nil, NO);
    }
    self.isPanelShowing = visible; self.isAnimating = YES;
    if (visible) {
        CV3SetKeyboardSuppressedByPanel(YES);
        [self startPanelStateRefreshTimer];
        self.searchField.text = @"";
        self.selectedCategory = @"全部";
        [self filterApps];
        self.backgroundColor = [UIColor clearColor];
        self.lastTriggerPoint = point;
        [self loadAppsAsync];
        [self updateTrafficLightsFocus:YES];
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
        
        self.trafficCapsule.frame = CGRectMake(16, 14, CV3Style.trafficCapsuleW, CV3Style.trafficCapsuleH);
        [self updateResizingHandleFrame];
        self.contrastBackdrop.frame = self.appPanel.bounds;
        [self refreshGlassAccentSurfaces];
        [self.collectionView.collectionViewLayout invalidateLayout];

        // 阴影硬件加速与大阴影配置
        self.panelContainer.layer.shadowColor = [UIColor blackColor].CGColor;
        self.panelContainer.layer.shadowOffset = CGSizeZero;
        self.panelContainer.layer.shadowOpacity = 0.0;
        self.panelContainer.layer.shadowRadius = CV3Style.shadowRadiusMask;
        self.panelContainer.layer.shadowPath = [UIBezierPath bezierPathWithRoundedRect:self.panelContainer.bounds cornerRadius:CV3Style.cornerRadius].CGPath;

        // Start compact and asymmetrical so the spring visibly overshoots in
        // both axes, producing the launcher panel's jelly-like pop.
        CGFloat jellyStrength = kCV3PanelJellyStrength;
        CGFloat velocityStretch = MIN(fabs(velocity) / 8000.0, 0.08) * jellyStrength;
        CGFloat initialScaleX = 0.90 - jellyStrength * 0.43 - velocityStretch;
        CGFloat initialScaleY = 0.90 - jellyStrength * 0.19 + velocityStretch * 0.25;
        CGFloat springVelocity = MIN(2.4, MAX(1.15, fabs(velocity) / 1400.0));
        CGFloat springDamping = 0.82 - jellyStrength * 0.42;
        self.panelPresentationStartTransform = CGAffineTransformScale(initialRotation,
                                                                       initialScaleX,
                                                                       initialScaleY);
        CV3RemoveViewAnimationsRecursively(self.panelContainer);
        self.panelContainer.transform = self.panelPresentationStartTransform;
        self.panelContainer.alpha = 0;
        self.appPanelPresentationStartTransform = CGAffineTransformIdentity;
        self.appPanel.transform = CGAffineTransformIdentity;

        // 建议3：使用预热缓存的中心点 (Layout Pre-warming)
        CGPoint targetCenter = (self.cachedTargetCenter.x > 0) ? self.cachedTargetCenter : [self calculateTargetCenter];
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
            self.isAnimating = NO; 
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
        // 关键修复：不要同步收起键盘，因为 resignFirstResponder 是重度同步操作，会阻塞动画开始
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.searchField resignFirstResponder];
        });

        [self updateTrafficLightsFocus:NO];
        [self refreshGlassAccentSurfaces];
        
        CALayer *presentationLayer = self.panelContainer.layer.presentationLayer;
        if (presentationLayer) {
            self.panelContainer.center = presentationLayer.position;
            self.panelContainer.transform = CATransform3DGetAffineTransform(presentationLayer.transform);
            self.panelContainer.alpha = presentationLayer.opacity;
        }

        // Flatten the visual-effect subtree for the short closing transition.
        // This permits a subtle settle without asking Backdrop to resample every
        // transformed frame, which previously produced visible edge trails.
        self.panelContainer.layer.shouldRasterize = YES;
        self.panelContainer.layer.rasterizationScale = [UIScreen mainScreen].scale;
        CGAffineTransform baseTransform = self.panelContainer.transform;
        CGAffineTransform settleTransform = CGAffineTransformScale(baseTransform, 1.008, 1.008);
        CGAffineTransform dismissTransform = CGAffineTransformScale(baseTransform, 0.94, 0.94);
        CGPoint dismissCenter = self.panelContainer.center;
        CGPoint edgePoint = self.lastTriggerPoint;
        CGFloat dx = edgePoint.x - dismissCenter.x;
        CGFloat dy = edgePoint.y - dismissCenter.y;
        CGFloat distance = sqrt(dx * dx + dy * dy);
        if (distance > 1.0) {
            dismissCenter.x += (dx / distance) * 14.0;
            dismissCenter.y += (dy / distance) * 14.0;
        }

        [UIView animateKeyframesWithDuration:kCV3PanelDismissDuration
                                       delay:0
                                     options:UIViewKeyframeAnimationOptionBeginFromCurrentState | UIViewKeyframeAnimationOptionAllowUserInteraction | UIViewKeyframeAnimationOptionCalculationModeCubic
                                  animations:^{
            [UIView addKeyframeWithRelativeStartTime:0.0 relativeDuration:0.22 animations:^{
                self.panelContainer.transform = settleTransform;
                self.panelContainer.layer.shadowOpacity = CV3Style.shadowOpacityMask * 0.55;
            }];
            [UIView addKeyframeWithRelativeStartTime:0.18 relativeDuration:0.82 animations:^{
                self.backgroundColor = [UIColor clearColor];
                self.panelContainer.center = dismissCenter;
                self.panelContainer.alpha = 0.0;
                self.panelContainer.transform = dismissTransform;
                self.panelContainer.layer.shadowOpacity = 0.0;
                self.bezierContainer.alpha = 0.0;
            }];
        } completion:^(BOOL f){
            self.panelContainer.layer.shouldRasterize = NO;
            self.panelContainer.layer.rasterizationScale = 1.0;
            self.isAnimating = NO;
            CV3FinalizePanelHiddenState(self);
            CV3SetKeyboardSuppressedByPanel(NO);
            // Re-enable Home Screen pull-down only after the panel's dismissal
            // animation has completed and the panel is no longer visible.
            CV3SetHomeScreenPullDownSuppressed(NO);
        }];
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
    [self.searchField resignFirstResponder];
    [self.collectionView.layer removeAllAnimations];
    for (UICollectionViewCell *cell in self.collectionView.visibleCells) {
        [cell.layer removeAllAnimations];
        cell.transform = CGAffineTransformIdentity;
        cell.alpha = 1.0;
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

static NSSet<NSString *> *CV3LaunchableSpringBoardIconBundleIDs(void) {
    if (![NSThread isMainThread]) return [NSSet set];

    id iconController = [CV3ClassNamed(@"SBIconController") sharedInstance];
    id iconManager = CV3InvokeObject(iconController, @selector(iconManager));
    id iconModel = CV3InvokeObject(iconManager, @selector(model));
    if (!iconModel) iconModel = CV3InvokeObject(iconController, @selector(model));

    NSMutableSet<NSString *> *bundleIDs = [NSMutableSet set];
    id leafIcons = CV3InvokeObject(iconModel, @selector(leafIcons));
    if ([leafIcons conformsToProtocol:@protocol(NSFastEnumeration)]) {
        for (id icon in leafIcons) {
            NSString *bundleID = CV3BundleIdentifierFromIconObject(icon);
            if (bundleID.length > 0) [bundleIDs addObject:bundleID];
        }
    }
    return [bundleIDs copy];
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

    if (launchableBundleIDs.count > 0 && ![launchableBundleIDs containsObject:bundleId]) {
        return NO;
    }
    // Icon model unavailable is rare during early SpringBoard startup. In that
    // fallback only accept user Apps; once the model is ready its launchable
    // icon set also admits normal Apple system Apps such as Settings or Safari.
    if (launchableBundleIDs.count == 0 &&
        !CV3InvokeBool(appProxy, @selector(isUserApplication), YES)) {
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
    NSSet<NSString *> *launchableBundleIDs = CV3LaunchableSpringBoardIconBundleIDs();

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

                self.apps = [sortedApps mutableCopy];
                if (needsFullReload) self.needsFullReload = NO;
                self.recentlyUsedApps = [self.apps subarrayWithRange:NSMakeRange(0, MIN(12, self.apps.count))];
                [self updateCategoryBar];
                [self filterApps];
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

    NSArray<NSIndexPath *> *visibleIndexPaths = [self.collectionView indexPathsForVisibleItems];
    if (visibleIndexPaths.count == 0) return;

    [UIView performWithoutAnimation:^{
        [self.collectionView reloadItemsAtIndexPaths:visibleIndexPaths];
    }];
}

- (void)startPanelStateRefreshTimer {
    if (self.panelStateRefreshTimer) return;

    self.panelStateRefreshTimer = [NSTimer scheduledTimerWithTimeInterval:0.5
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

                // 核心修复：调用 setHidden 触发重写后的压制检查
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
    // 建议：层级对齐 (Level Alignment)
    // 根据 GEMINI.md 规范，锁定在 panel (2099) 以确保覆盖所有第三方 App，且保持在控制中心之下
    CGFloat targetLevel = CV3Style.panel; 
    
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
    CV3AppPanelProtectionState protectionState = CV3AppPanelProtectionStateForBundleID(info.bundleId);
    [cell configureWithInfo:info searchText:self.searchField.text isFirst:isFirst protectionState:protectionState];
    [self loadIconForAppInfo:info cell:cell];

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
        self.windowLevel = CV3Style.background; // 降到最低层
        return;
    }
    
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
