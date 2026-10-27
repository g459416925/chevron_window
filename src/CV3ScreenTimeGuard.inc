// CV3ScreenTimeGuard.inc —— Screen Time App 限额守卫（2026-10-27）
// ---------------------------------------------------------------------------
// 目的：App 达到「App 限额」后，ChevronV3 的所有非系统启动路径（分屏/面板/
// 浮窗聚焦/通知开分屏/浮窗全屏）必须与主屏图标路径一致：呈现系统拦截页，
// 而不是绕过限制直接进入应用。
//
// 依据（iOS 16.5.1 arm64e dyld_shared_cache 静态分析，证据见
// ScreenTimeLocker16/evidence/20261027-1930-split-bypass-re/）：
//
//   1. 系统判定链（-[SBDeviceApplicationScreenTimeLockoutViewProvider
//      _activateIfPossible] 反汇编）：
//        [[sceneHandle application] info] isBlockedForScreenTimeExpiration
//        → -[FBSApplicationInfo isBlockedForScreenTimeExpiration]
//            == (self.screenTimePolicy != nil)      // 0x19d08a344 逐指令确认
//      即 FBSApplicationInfo._screenTimePolicy 非 nil == 该 App 当前被限额拦停。
//
//   2. 系统拦截页构造链（SBDeviceApplicationScreenTimeLockoutViewProvider
//      _newBlockingViewControllerWithBundleIdentifier: / SBAppSwitcherSnapshot-
//      LockoutViewControllerProvider 反汇编，两处调用序一致）：
//        vc = [STBlockingViewController newTranslucentBlockingViewController]  (类方法)
//        [vc setOkButtonHandler:[STBlockingViewController closeApplicationHandler]]
//        [vc _setIgnoresWrapperViewForContentOverlayInsets:YES]
//        [vc updateAppearanceUsingPolicy:policy forBundleIdentifier:bundleID]
//      本文件按同一配方构造，policy 直接取自 FBSApplicationInfo，不自行实现
//      任何「是否限额」的判断逻辑。
//
//   3. STBlockingViewController 由 ScreenTimeUI.framework 提供，在 SpringBoard
//      中懒加载；class 取不到时 dlopen 后重取。
//
// 与 ScreenTimeLocker16 的关系：STL16 ③ 层 hook 的是 STBlockingViewController
// 的实例方法（同进程），因此本守卫呈现的拦截页自动获得 STL16 的
// Face ID/密码回落增强，无需任何额外对接。
//
// 私有调用纪律：所有私有 selector 先 respondsToSelector + method_getTypeEncoding
// 校验（签名不符则走 setPolicy:/setBundleIdentifier: 兜底并留痕），不盲调。
// ---------------------------------------------------------------------------

#pragma mark - 限额状态查询

#include <string.h>

// 返回 FBSApplicationInfo._screenTimePolicy（非 nil = 当前被限额拦停）。
// 仅在 SpringBoard 进程内有意义；非 SB 宿主/类缺失/未安装 → nil。
static id CV3ScreenTimePolicyForBundleID(NSString *bundleID) {
    if (![bundleID length]) return nil;

    Class controllerClass = CV3ClassNamed(@"SBApplicationController");
    if (!controllerClass) return nil;
    id controller = [controllerClass sharedInstance];
    if (!controller) return nil;

    // 与系统判定链同源：SBApplication → info(FBSApplicationInfo) → screenTimePolicy
    id application = nil;
    @try {
        application = ((id (*)(id, SEL, id))objc_msgSend)(
            controller, @selector(applicationWithBundleIdentifier:), bundleID);
    } @catch (NSException *e) {
        CV3LogToFile(@"[ScreenTimeGuard] applicationWithBundleIdentifier 异常 bundle=%@ %@",
                     bundleID, e);
        return nil;
    }
    if (![application respondsToSelector:@selector(info)]) return nil;
    id info = ((id (*)(id, SEL))objc_msgSend)(application, @selector(info));
    if (![info respondsToSelector:@selector(screenTimePolicy)]) return nil;

    id policy = nil;
    @try {
        policy = ((id (*)(id, SEL))objc_msgSend)(info, @selector(screenTimePolicy));
    } @catch (NSException *e) {
        CV3LogToFile(@"[ScreenTimeGuard] screenTimePolicy 读取异常 bundle=%@ %@",
                     bundleID, e);
        return nil;
    }
    return policy;
}

#pragma mark - 系统拦截页呈现

static UIWindow *CV3ScreenTimeOverlayWindow = nil;
static NSString *CV3ScreenTimeOverlayBundleID = nil;

static void CV3DismissScreenTimeBlockingOverlay(void) {
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            CV3DismissScreenTimeBlockingOverlay();
        });
        return;
    }
    UIWindow *overlay = CV3ScreenTimeOverlayWindow;
    NSString *bundleID = CV3ScreenTimeOverlayBundleID;
    if (!overlay) return;
    CV3ScreenTimeOverlayWindow = nil;
    CV3ScreenTimeOverlayBundleID = nil;

    CV3LogToFile(@"[ScreenTimeGuard] 拦截页收起 bundle=%@", bundleID);
    [UIView animateWithDuration:0.18
                          delay:0
                        options:UIViewAnimationOptionBeginFromCurrentState
                     animations:^{ overlay.alpha = 0.0; }
                     completion:^(BOOL finished) {
        overlay.hidden = YES;
        overlay.rootViewController = nil;
    }];
}

// 呈现系统拦截页（STBlockingViewController）。幂等：同一 bundle 已在呈现
// 则不重复叠层；不同 bundle 则先收起旧的。preferredScene 允许为 nil。
static BOOL CV3PresentScreenTimeBlockingOverlay(NSString *bundleID,
                                                NSString *source,
                                                UIWindowScene *preferredScene) {
    if (![bundleID length]) return NO;
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            CV3PresentScreenTimeBlockingOverlay(bundleID, source, preferredScene);
        });
        return YES;
    }

    id policy = CV3ScreenTimePolicyForBundleID(bundleID);
    if (!policy) return NO;

    if (CV3ScreenTimeOverlayWindow) {
        if ([CV3ScreenTimeOverlayBundleID isEqualToString:bundleID]) {
            CV3LogToFile(@"[ScreenTimeGuard] 拦截页已在呈现，忽略重复请求 bundle=%@ source=%@",
                         bundleID, source ?: @"Unknown");
            return YES;
        }
        CV3DismissScreenTimeBlockingOverlay();
    }

    Class blockingClass = CV3ClassNamed(@"STBlockingViewController");
    if (!blockingClass) {
        // ScreenTimeUI 在 SB 内懒加载：先 dlopen 再重取
        dlopen("/System/Library/PrivateFrameworks/ScreenTimeUI.framework/ScreenTimeUI",
               RTLD_LAZY | RTLD_GLOBAL);
        blockingClass = CV3ClassNamed(@"STBlockingViewController");
    }
    if (!blockingClass) {
        CV3LogToFile(@"[ScreenTimeGuard] STBlockingViewController 不可用，仅拒绝启动 bundle=%@ source=%@",
                     bundleID, source ?: @"Unknown");
        return NO;
    }

    // 系统配方 1：+newTranslucentBlockingViewController
    id blockingVC = nil;
    if ([blockingClass respondsToSelector:@selector(newTranslucentBlockingViewController)]) {
        @try {
            blockingVC = ((id (*)(id, SEL))objc_msgSend)(
                blockingClass, @selector(newTranslucentBlockingViewController));
        } @catch (NSException *e) {
            CV3LogToFile(@"[ScreenTimeGuard] newTranslucentBlockingViewController 异常 %@",
                         e);
        }
    }
    if (!blockingVC) {
        CV3LogToFile(@"[ScreenTimeGuard] 拦截页构造失败 bundle=%@ source=%@",
                     bundleID, source ?: @"Unknown");
        return NO;
    }

    // 系统配方 2：ok 按钮 → 收起拦截页并关掉该 bundle 的分屏窗口
    if ([blockingVC respondsToSelector:@selector(setOkButtonHandler:)]) {
        NSString *capturedBundleID = [bundleID copy];
        void (^okHandler)(void) = ^{
            CV3DismissScreenTimeBlockingOverlay();
            // 关闭同 bundle 的所有分屏窗口（运行时取，不依赖编译期声明）
            for (NSInteger i = (NSInteger)floatingWindows.count - 1; i >= 0; i--) {
                id win = floatingWindows[(NSUInteger)i];
                if ([win isKindOfClass:[UIWindow class]] &&
                    [win respondsToSelector:@selector(bundleID)] &&
                    [[(id)win valueForKey:@"bundleID"] isEqualToString:capturedBundleID] &&
                    [win respondsToSelector:@selector(closeWindow)]) {
                    [win performSelector:@selector(closeWindow)];
                }
            }
        };
        ((void (*)(id, SEL, id))objc_msgSend)(
            blockingVC, @selector(setOkButtonHandler:), okHandler);
    }

    // 系统配方 3：内容边距按 overlay 场景解析（不套 wrapper view 的 inset）
    if ([blockingVC respondsToSelector:@selector(_setIgnoresWrapperViewForContentOverlayInsets:)]) {
        ((void (*)(id, SEL, BOOL))objc_msgSend)(
            blockingVC, @selector(_setIgnoresWrapperViewForContentOverlayInsets:), YES);
    }

    // 系统配方 4：updateAppearanceUsingPolicy:forBundleIdentifier:
    //   签名 v32@0:8@16@24（self/SEL/policy/bundleID 各 8 字节）
    BOOL appearanceApplied = NO;
    Method updateMethod = class_getInstanceMethod([blockingVC class],
                                                   @selector(updateAppearanceUsingPolicy:forBundleIdentifier:));
    if (updateMethod) {
        const char *types = method_getTypeEncoding(updateMethod);
        if (types && strcmp(types, "v32@0:8@16@24") == 0) {
            ((void (*)(id, SEL, id, id))objc_msgSend)(
                blockingVC, @selector(updateAppearanceUsingPolicy:forBundleIdentifier:),
                policy, bundleID);
            appearanceApplied = YES;
        } else {
            CV3LogToFile(@"[ScreenTimeGuard] updateAppearance 签名异常 types=%s 走兜底",
                         types ?: "(null)");
        }
    }
    if (!appearanceApplied) {
        // 兜底：直接注入 policy 与 bundleIdentifier（属性 setter 均存在）
        if ([blockingVC respondsToSelector:@selector(setPolicy:)]) {
            ((void (*)(id, SEL, id))objc_msgSend)(
                blockingVC, @selector(setPolicy:), policy);
        }
        if ([blockingVC respondsToSelector:@selector(setBundleIdentifier:)]) {
            ((void (*)(id, SEL, id))objc_msgSend)(
                blockingVC, @selector(setBundleIdentifier:), bundleID);
        }
    }

    // 容器：独立 UIWindow 盖在浮窗之上，铺满 preferredScene（回退到任一活跃 scene）
    UIWindowScene *scene = preferredScene;
    if (!scene) {
        for (UIScene *candidate in [UIApplication sharedApplication].connectedScenes.allObjects) {
            if ([candidate isKindOfClass:[UIWindowScene class]] &&
                candidate.activationState != UISceneActivationStateUnattached) {
                scene = (UIWindowScene *)candidate;
                break;
            }
        }
    }
    if (!scene) {
        CV3LogToFile(@"[ScreenTimeGuard] 无可用 UIWindowScene，拦截页放弃呈现 bundle=%@",
                     bundleID);
        return NO;
    }

    UIWindow *overlay = [[UIWindow alloc] initWithWindowScene:scene];
    overlay.windowLevel = UIWindowLevelStatusBar + 100.0;
    UIViewController *host = [[UIViewController alloc] init];
    host.view.backgroundColor = [UIColor colorWithWhite:0.0 alpha:1.0];
    [host addChildViewController:(UIViewController *)blockingVC];
    ((UIViewController *)blockingVC).view.frame = host.view.bounds;
    ((UIViewController *)blockingVC).view.autoresizingMask = UIViewAutoresizingFlexibleWidth |
                                                            UIViewAutoresizingFlexibleHeight;
    [host.view addSubview:((UIViewController *)blockingVC).view];
    [(UIViewController *)blockingVC didMoveToParentViewController:host];
    overlay.rootViewController = host;
    overlay.alpha = 0.0;
    overlay.hidden = NO;

    CV3ScreenTimeOverlayWindow = overlay;
    CV3ScreenTimeOverlayBundleID = [bundleID copy];

    [UIView animateWithDuration:0.18 animations:^{ overlay.alpha = 1.0; }];
    NSString *policyClassName = NSStringFromClass([policy class]);

    CV3LogToFile(@"[ScreenTimeGuard] 拦截页已呈现 bundle=%@ source=%@ policy=%@",
                 bundleID, source ?: @"Unknown", policyClassName);
    return YES;
}

#pragma mark - 统一入口闸门

// 统一闸门：返回 YES = 放行；NO = 已被限额拦停（同时呈现系统拦截页）。
// presentPage = NO 用于预热等无界面阶段（只静默跳过）。
static BOOL CV3ScreenTimeGateBundleID(NSString *bundleID,
                                      NSString *source,
                                      BOOL presentPage,
                                      UIWindowScene *preferredScene) {
    if (![bundleID length]) return YES;

    id policy = CV3ScreenTimePolicyForBundleID(bundleID);
    if (!policy) return YES;

    NSString *policyClassName2 = NSStringFromClass([policy class]);
    CV3LogToFile(@"[ScreenTimeGuard] 命中限额拦截 bundle=%@ source=%@ policy=%@ present=%d",
                 bundleID, source ?: @"Unknown", policyClassName2, presentPage);
    if (presentPage) {
        CV3PresentScreenTimeBlockingOverlay(bundleID, source, preferredScene);
    }
    return NO;
}
