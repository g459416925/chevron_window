# Screen Time 限额守卫（v1.0.18-228+screentime-guard）

> 日期：2026-10-27 · 执行：Byte
> 任务：修复「App 限额生效时，ChevronV3 分屏/面板等非系统路径绕过限额直接进入 App」

## 0. 一句话结论

分屏绕过的根因：分屏挂载走 `launchApplicationWithIdentifier:suspended:YES`（suspended 预启动）+
`-[FBScene updateSettings:...]` 强制前台主权（foreground=YES/visibility=2），**完全不经过
SpringBoard 图标激活链路上的 Screen Time 拦停检查**，所以系统拦截页永远不会出现。

修复：在 ChevronV3 内新增 Screen Time 闸门，用**系统自己的判定 API + 系统自己的拦截页**
（`FBSApplicationInfo.screenTimePolicy` + `STBlockingViewController`），覆盖全部非系统启动入口。

## 1. 系统机制（dyld_shared_cache 静态分析，全部 Observed）

证据基线：`ScreenTimeLocker16/evidence/20261027-1930-split-bypass-re/`（设备 2.8G dyld cache 全量
拉取 + ipsw 3.1.739 提取 SpringBoard/ScreenTimeCore/ScreenTimeUI + 符号级反汇编）。

| # | 事实 | 证据 |
|---|---|---|
| 1 | 系统判定 `-[SBDeviceApplicationScreenTimeLockoutViewProvider _activateIfPossible]`：`[[sceneHandle application] info] isBlockedForScreenTimeExpiration` | 反汇编 0x1c96ad28c-0x1c96ad2b8 |
| 2 | `-[FBSApplicationInfo isBlockedForScreenTimeExpiration]` ≡ `screenTimePolicy != nil` | 反汇编 0x19d08a340（cmp x0,#0; cset） |
| 3 | 拦截页构造配方：`[STBlockingViewController newTranslucentBlockingViewController]` → `setOkButtonHandler:` → `_setIgnoresWrapperViewForContentOverlayInsets:YES` → `updateAppearanceUsingPolicy:forBundleIdentifier:` | 反汇编 0x1c995775c-0x1c99577dc（系统 provider 与 SBAppSwitcherSnapshot 两个 provider 调用序一致） |
| 4 | `+[STBlockingViewController newTranslucentBlockingViewController]` 为类方法 | 符号表 |
| 5 | STL16 ③ 层 hook 的是 STBlockingViewController 实例方法（同进程）→ 本守卫呈现的拦截页自动获得 Face ID/密码回落增强 | ScreenTimeLocker16/src/ScreenTimeLocker16.m |

## 2. ChevronV3 侧绕过点矩阵（修复前 grep 证据）

| 入口 | API | 状态(修复前) |
|---|---|---|
| 主面板点 App | `CV3LaunchApplicationThroughSpringBoard` → `-[UIApplication launchApplicationWithIdentifier:suspended:NO]` | 无限额检查 |
| 拖图标开分屏（本 bug） | `CV3PreWarmAppForSplit`(suspended:YES) → 落点 `CV3FloatingAppWindow initWithBundleID:` → `loadAppScene` → suspended 拉起 + `getSceneForBundleID` + `applyForegroundSovereigntyToSettings` 强制前台 | 无限额检查 |
| 通知点开分屏 | `CV3OpenBundleInFloatingWindow` | 无限额检查 |
| 快捷切换/收起还原聚焦 | `setWindowFocused:YES` / `restoreFromStash` | 无限额检查 |
| 浮窗全屏化 | `activateHostedAppFullscreenAndClose` → `LSApplicationWorkspace.openApplicationWithBundleID:` | 无限额检查 |
| LS 直连启动 hook | `Tweak.x %hook LSApplicationWorkspace openApplicationWithBundleID:` | 无限额检查 |

## 3. 修复内容

新文件 `src/CV3ScreenTimeGuard.inc`（Tweak.x:2146 处引入，位于 CV3FloatingAppWindow.inc 之前）：

- `CV3ScreenTimePolicyForBundleID()`：`SBApplicationController → SBApplication → info(FBSApplicationInfo) → screenTimePolicy`（与系统判定链同源）。
- `CV3PresentScreenTimeBlockingOverlay()`：按系统配方构造真实拦截页并装入独立 UIWindow（windowLevel=UIWindowLevelStatusBar+100），OkButtonHandler 收起浮层并关闭该 bundle 的分屏窗口；STBlockingViewController 缺失时 dlopen ScreenTimeUI。
- `CV3ScreenTimeGateBundleID()`：统一闸门，命中 → 呈现拦截页 + 返回 NO。

闸门插入点（8 处）：

| # | 文件:函数 | 行为 |
|---|---|---|
| 1 | CV3Window.inc `CV3PreWarmAppForSplit` | 限额中跳过预热（不呈现页面） |
| 2 | CV3Window.inc 分屏落点 async 块 | 拦截 + 呈现页面 + 不建窗 |
| 3 | CV3Window.inc `launchApp:`（主面板） | 拦截 + 呈现页面 |
| 4 | CV3Window.inc `CV3OpenBundleInFloatingWindow`（通知/共享入口） | 拦截 + 呈现页面 |
| 5 | CV3FloatingAppWindow.inc `loadAppScene` | 兜底：呈现页面 + closeWindow |
| 6 | CV3FloatingAppWindow.inc `setWindowFocused:(YES)` | 兜底：不允许前台化 + 呈现页面 |
| 7 | CV3FloatingAppWindow.inc `activateHostedAppFullscreenAndClose` | 拦截 + 呈现页面 |
| 8 | Tweak.x `LSApplicationWorkspace.openApplicationWithBundleID:` + `SpringBoard.launchApplicationWithIdentifier:suspended:(NO)` | 拦截 + 呈现页面 |

私有调用纪律：`updateAppearanceUsingPolicy:forBundleIdentifier:` 先 `method_getTypeEncoding`
校验（v32@0:8@16@24），不符走 `setPolicy:`+`setBundleIdentifier:` 兜底并留痕。

## 4. 版本/部署核验（Observed）

- control → `1.0.18-228+screentime-guard`；构建产物 `packages/com.xu.chevronv3_1.0.18-228+screentime-guard_iphoneos-arm64e.deb`。
- `dpkg -i` 升级成功（227+env-fast-1+debug → 228）；`sbreload` 后 SB 正常拉起。
- 设备日志 `/rootfs/private/var/mobile/Library/Logs/ChevronV3_Logs.txt`：
  `[ChevronProbe] springboard.bootstrap pid=57032 version=1.0.18-228+screentime-guard`（12:26:18 UTC）
  另见 logs/bootstrap-and-no-new-crash.log。
- 崩溃检查：部署后无新增 .ips（最新 SpringBoard .ips 为 12:49 CST 当天中午，早于本次部署）。
- 截图：`sb-alive-after-deploy-20261027-2031.jpg`（SB 桌面正常渲染，20:31）。

## 5. 未决项

1. **实机触发验证未做**：需要许总把测试 App 限额打满（或等微信 1 分钟限额自然触发），
   然后依次测：①主面板点该 App ②拖出开分屏 ③通知点开。预期：三条路径均出现系统拦截页
   （STL 日志应同时出现 `[hook] STBlockingViewController -viewDidLoad`，证明走的是真拦截页）。
2. 「分屏窗口存续期间限额才生效」的场景目前只在下一次聚焦/启动时拦（`setWindowFocused` 兜底），
   不会即时盖上拦截页；如需即时覆盖，需订阅 policy 变更通知（候选 `SBScreenTimeChangedChangedExternallyNotification`），v2 再做。
3. 被其他 App 直接调用的 `openApplicationWithBundleID:`（App 外部进程）不在 SB 进程内，闸门管不到
   （与主屏图标路径同等覆盖范围，非本次回归）。

## 6. 回滚

```bash
# 设备侧回退到上一版本 deb
./device-tools/push.sh ChevronV3/dist/com.xu.chevronv3_1.0.18-227+env-fast-1+debug_iphoneos-arm64e.deb /var/tmp/cv3-rollback.deb
./device-tools/iphone.sh -r 'dpkg -i /var/tmp/cv3-rollback.deb && sbreload'
# 源码回滚
cd ChevronV3 && git checkout -- src/Tweak.x src/CV3Window.inc src/CV3FloatingAppWindow.inc control && rm src/CV3ScreenTimeGuard.inc ChevronV3.plist ChevronV3VideoBridge.plist ChevronV3CameraBridge.plist
```
