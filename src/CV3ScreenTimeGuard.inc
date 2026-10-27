// CV3ScreenTimeGuard.inc —— Screen Time App 限额守卫（2026-10-27 v3 简化版）
// ---------------------------------------------------------------------------
// 目的：App 达到「App 限额」后，ChevronV3 的所有非系统启动路径（面板点击/
// 分屏拖落/浮窗聚焦/通知开分屏/浮窗全屏化/LS 直连/PreWarm）直接拒绝，
// 与主屏图标路径一致，不绕过限制。
//
// 依据（iOS 16.5.1 arm64e dyld_shared_cache 静态分析，证据见
// ScreenTimeLocker16/evidence/20261027-1930-split-bypass-re/）：
//
//   1. 系统判定链（-[SBDeviceApplicationScreenTimeLockoutViewProvider
//      _activateIfPossible] 反汇编）：
//        [[sceneHandle application] info] isBlockedForScreenTimeExpiration
//        → -[FBSApplicationInfo isBlockedForScreenTimeExpiration]
//            == (screenTimePolicy != 0)      // 0x19d08a340 逐指令确认
//
//   2. ⭐ screenTimePolicy 是 64 位整数，不是对象（v1 崩溃根因，实测 .ips：
//      SpringBoard-2026-10-27-203916/203950 两次 SIGSEGV @0x2，栈顶
//      objc_retain ← ARC retain 了这个整数返回值）：
//      -[FBSApplicationInfo screenTimePolicy] = ldr x0,[x0,ivar]
//      （裸 8 字节读，无 retain）。因此全链路一律按 NSInteger 处理
//      （0 = 未拦，非 0 = 拦停），严禁赋给 id / retain。
//
// v3 变更（本版，用户拍板简化）：v2 的系统拦截页呈现链
// （STBlockingViewController + 独立 overlay UIWindow）在真机上呈现不稳定，
// 且无存在必要——命中限额直接拒绝启动即可。删除全部 overlay 呈现代码，
// 闸门收敛为「查询 policy → 非 0 即拒绝」两步。
// ---------------------------------------------------------------------------

#pragma mark - 限额状态查询

// 返回 FBSApplicationInfo._screenTimePolicy（64 位整数；0 = 未拦停，非 0 = 拦停）。
// 与系统 -[FBSApplicationInfo isBlockedForScreenTimeExpiration] 完全同源。
// 仅在 SpringBoard 进程内有意义；非 SB 宿主/类缺失/未安装 → 0。
static NSInteger CV3ScreenTimePolicyForBundleID(NSString *bundleID) {
    if (![bundleID length]) return 0;

    Class controllerClass = CV3ClassNamed(@"SBApplicationController");
    if (!controllerClass) return 0;
    id controller = [controllerClass sharedInstance];
    if (!controller) return 0;

    // 与系统判定链同源：SBApplication → info(FBSApplicationInfo) → screenTimePolicy
    id application = nil;
    @try {
        application = ((id (*)(id, SEL, id))objc_msgSend)(
            controller, @selector(applicationWithBundleIdentifier:), bundleID);
    } @catch (NSException *e) {
        CV3LogToFile(@"[ScreenTimeGuard] applicationWithBundleIdentifier 异常 bundle=%@ %@",
                     bundleID, e);
        return 0;
    }
    if (![application respondsToSelector:@selector(info)]) return 0;
    id info = ((id (*)(id, SEL))objc_msgSend)(application, @selector(info));
    if (![info respondsToSelector:@selector(screenTimePolicy)]) return 0;

    // ⭐ screenTimePolicy 是裸整数返回（ldr x0,[x0,ivar]），严禁走 id/retain 路径
    NSInteger policy = 0;
    @try {
        policy = ((NSInteger (*)(id, SEL))objc_msgSend)(info, @selector(screenTimePolicy));
    } @catch (NSException *e) {
        CV3LogToFile(@"[ScreenTimeGuard] screenTimePolicy 读取异常 bundle=%@ %@",
                     bundleID, e);
        return 0;
    }
    return policy;
}

#pragma mark - 统一入口闸门

// 统一闸门：返回 YES = 放行；NO = 该 App 处于限额中，直接拒绝
//（调用方按各自语义 return / closeWindow / 返回 YES 表示已处理）。
static BOOL CV3ScreenTimeGateBundleID(NSString *bundleID, NSString *source) {
    if (![bundleID length]) return YES;

    NSInteger policy = CV3ScreenTimePolicyForBundleID(bundleID);
    if (policy == 0) return YES;

    CV3LogToFile(@"[ScreenTimeGuard] 拒绝启动 bundle=%@ source=%@ policy=%ld",
                 bundleID, source ?: @"Unknown", (long)policy);
    return NO;
}
