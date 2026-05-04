# ChevronLauncher (ChevronV3) 项目记忆 (Base Index)

## 1. 核心研发环境
- **编辑目标**: 所有的对话与修改均针对 `Tweak.x` 文件。
- **目标设备**: iPhone 14 Pro Max (iOS 16.5.1)
- **越狱环境**: RootHide (via Bootstrap.ipa)

## 2. 底层架构与手势准则
- **窗口系统 (`CV3Window`)**:
    - **Scene 兼容性**: 启用 `SBWindowRoleFloatingCanHostLaunchpad` 角色。
    - **自适应 Level**: WindowLevel 动态计算，上限严禁超过控制中心（2100），常规锁定在 2099 以确保覆盖所有第三方 App。
    - **宿主跟随**: 实时监听主 App 旋转与 Scene 切换，通过 `attachToCurrentActiveScene` 确保窗口始终挂载在活跃场景。
- **手势主权**: 
    - **动态窗口绑定 (Dynamic Window Binding)**: 
        - 弃用全局 `SBSystemGestureManager` 注册。
        - 实时探测活跃场景的主应用窗口 (`SBDeviceApplicationSceneWindow`)，并将手势动态绑定至该窗口，确保手势与 App 逻辑深度融合。
    - **抢占式优先权**: 
        - 在 `gestureRecognizer:shouldBeRequiredToFailByGestureRecognizer:` 中显式要求系统边缘手势（如侧滑返回）失败。
    - **触控透传架构**: 
        - 当面板隐藏时，`CV3Window` 的 `hitTest` 返回 `nil`，实现完全透传，让底层 App 窗口直接接收并处理手势。
    - **键盘智能感知**: 
        - 迁移至 `gestureRecognizerShouldBegin:` 进行判定，当键盘弹出时自动禁用右下 60% 手势区域。

## 3. 视觉与物理规范 (Liquid Glass Engine)
- **液态玻璃特效**:
    - **折射效应**: `_backdropView` 在 `layoutSubviews` 中强制执行 **1.15x** 几何缩放。
    - **动态高光**: 集成 `CoreMotion` 实现 120Hz 镜面高光随设备倾斜流转。
    - **三棱镜色散**: 边缘 0.3pt 青/品红位移层模拟物理分光。
- **几何学与约束**: 
    - **窗口外观**: 圆角 28pt，配备交通灯胶囊（左上）与同心圆手柄（右下）。
    - **安全区域 (Safe Area)**: 强制执行 **10pt 呼吸间距** 钳位，严禁面板遮挡状态栏或 Home 条。
    - **状态持久化**: 引入 `hasBeenMoved` 标志位，确保旋转或布局刷新时不丢失用户自定义位置。
- **动态特性**:
    - **果冻物理**: 阻尼系数 0.45 - 0.55，追求物理过冲感。
    - **呼吸/涟漪**: 全局点击水波纹与图标随机周期 Y 轴浮动。

## 4. 性能与数据规范
- **数据同步**: 
    - **资源库对齐**: 每次唤出面板前必须同步 **App 资源库** 的安装/卸载状态。
    - **异步机制**: 采用图标异步预加载与缓存，确保滚动锁定 120fps。
- **能耗管理**: 物理引擎（陀螺仪）仅在面板可见时激活。

## 5. 操作规范 (Operational Norms)
- **执行优先**: 修改代码时**无需预先展示方案总结**，应优先完成文件编辑与编译验证。
- **验证闭环**: 每次修改必须执行 `make`, `make package` 编译。
- **回复准则**: 
    - 始终采用中文。
    - 编译成功后提供功能总结与 **具有建设性方案的推荐建议 (Geek Advice)**。
- **研发守则**: 
    - 严禁进行无关代码改动。修改必须自审是否影响其他功能，并在回复中明确告知。
    - **严禁硬编码 (No Hard-coding)**: 任何配置参数（如偏移量、颜色、尺寸、阈值等）严禁直接散布在逻辑代码中。必须集中定义为 `static const` 变量或枚举类型，且建议按功能模块划分（例如 `kChevronLayoutConstants`）。
    - **方向监控强制规范 (Hard Mandate)**:
        - 界面方向监听**必须**使用 `UIWindow layoutSubviews` 的 Hook 方式，通过检测 `windowScene.interfaceOrientation` 实现。禁止使用任何 `UIApplication` 级别或 `UIScene` 级别的通知监听。
        - 界面方向变更日志**必须**使用 `CV3LogToFile` 函数，确保日志异步写入至 `/var/mobile/Documents/ChevronV3_Logs.txt`，并严格使用定义好的中文字符串格式。

## 6. 项目维护历史 (Maintenance Log)
- **v1.0.0 关键修正**:
    - 修复了 `setupUI` 中 Backdrop 缩放失效问题（移至 layoutSubviews）。
    - 修复了手势区红色视觉残留（修正为透明）。
    - 修复了布局刷新导致的面板位置复位问题（引入 hasBeenMoved）。
    - 修复了边缘手势与系统翻页冲突（升级为 30pt 抢占式手势）。
    - 解决了多行字符串导致的 16 处编译错误。
- **v1.0.1 界面方向监听实现**:
    - 确立了以 `UIWindow layoutSubviews` 为核心的界面方向监控规范，作为后续开发的硬性准则。
