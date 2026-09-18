# 项目记忆

## 设备连接优先级

真机设备连接必须严格按以下优先级选择：

1. USB SSH
2. iOS MCP
3. Tailscale

默认且最高优先级为 USB 转发的 `mobile 989826` SSH 通道：

```sh
SSHPASS=989826 sshpass -e ssh mobile@127.0.0.1 -p 2222
```

需要提权时通过 `sudo -S` 传入同一密码。只有 USB SSH 通道不可用时，才允许降级使用下方的 iOS-MCP 服务；只有 USB SSH 和 iOS MCP 均不可用时，才允许使用 Tailscale。高优先级通道恢复后必须立即切回，不得把 iOS MCP 或 Tailscale 作为默认设备操作通道。

当 USB SSH 与局域网 iOS MCP 均不可用时，先通过 `tailscale status` 获取 iPhone（`brilliantbytestekiiphone`）当前的 Tailscale 地址，再使用以下凭据通过 Tailscale SSH 执行设备操作：

- 用户名：`mobile`
- 密码：`989826`
- 普通命令：`SSHPASS=989826 sshpass -e ssh mobile@<iPhone-Tailscale-IP> '<command>'`
- 提权命令：通过远端 `sudo -S` 输入同一密码 `989826`

不得硬编码或长期假设 Tailscale IP 不变；每次降级到 Tailscale 前都必须重新读取 `tailscale status`。

## 人工复测约定

所有修复后的功能复测必须由用户本人手动执行。代理可以完成代码修改、构建、安装、启动前检查以及日志和截图的读取分析，但不得代替用户操作界面完成复测，也不得自行宣称功能复测通过。部署完成后应停止自动交互，向用户说明需要手动执行的复测步骤，并等待用户反馈结果或提供新的截图和日志。

## 证据驱动诊断约定

每一次代码修改和每一个诊断、修复结论都必须同时以实际日志和屏幕截图为依据。修改前必须先读取与问题对应的最新日志和截图，明确可观察到的异常；修改后必须再次读取用户手动复测产生的新日志和新截图，通过前后对比判断结果。不得仅凭代码阅读、历史经验、构建成功、安装成功或单一证据推断运行时行为，也不得在缺少日志或截图时宣称已经定位、修复或验证通过。证据不足时必须明确标记为“尚不能确定”，说明缺少的日志或截图并等待补充，禁止盲目猜测。

## iOS MCP 设备操作约定

以下规则要求在本项目的每一次对话中触发并遵守。

你可以通过 iOS MCP 服务操作一台 iPhone 设备。各工具的功能和参数见工具列表，这里只列使用时容易踩的坑和约定。

MCP 地址：`http://192.168.1.5:8090/mcp`

1. 开始操作前先用 `describe_screen` 了解当前屏：一次返回前台 App、可点元素和精确坐标，最省 token，是“看一眼当前屏”的默认入口。它默认不含截图和 OCR，需要时显式开 `include_screenshot` / `include_ocr`。
2. 仅在需要细控时才下沉到底层读屏工具：要抓屏外/不可点节点、限制返回量、或排查“AX 为什么抓不到”时，用 `get_ui_elements`（`visible_only` / `limit` / `debug`）；AX 根本看不到的内容（游戏、Flutter/RN/Unity、Canvas、图片里的字），或只想识别某区域、快扫、指定语种时，用 `ocr_screen`（`region` / `fast` / `languages`）。
3. `screenshot` 最占 token，仅在 AX 和 OCR 都拿不到、或确实需要看图时兜底，不要每步都截。处理结果按 image content 解析（图片 base64 在 `result.content[0].data`，`mimeType` 通常为 `image/jpeg`），不要读 `result.content[0].text`。
4. 以上读屏工具坐标统一为 screen points，OCR/AX 返回的点可直接传给 `tap_screen` / `long_press`，无需换算。
5. 如果 `get_screen_info` 显示 `locked=true` / `screen_on=false`，或截图像锁屏，不要继续普通 App 操作；直接调用 `wake_and_home` 唤醒并回到主屏幕，然后用 `get_screen_info` / `describe_screen`（必要时 `screenshot`）确认（不要用单次 `press_home` 代替，锁屏下它通常只是唤醒或进入解锁提示）。
6. 服务端启用了锁屏保护；锁屏或熄屏时，点击、滑动、输入、启动 App、Shell 等交互/写入类工具会被拦截，只允许状态查询、截图和 `wake_and_home` 等恢复工具。
7. 交互时优先用 `tap_element` 按文本/标签点击，或根据 UI 节点坐标点击，不要盲点；页面变化后重新读取 UI 节点，或用 `wait_for_element` 等待目标出现，再继续下一步。
8. 文本输入先用 `input_text`；如果 `input_text` 失败、超时或返回 `isError`，立即用 `type_text` 输入同一段文本，不要反复调用 `input_text`。
9. `read_file` 有大小上限；读大文件或二进制文件改用 `GET /download_file` 下载完整文件。
10. 安装 IPA/DEB：电脑本地文件先 `POST /upload_file`，再把返回的设备路径传给 `install_app`（IPA 可无需签名）；卸载时 App 传 `bundle_id`、DEB 传 `package_id`。
11. `install_app` 装 DEB 只装本地 `.deb`，不会自动联网下载依赖；如有第三方依赖先上传并安装依赖包。
12. DEB 安装/卸载成功后会重启 SpringBoard；之后先等待几秒，再单次运行 `curl -sS --connect-timeout 3 --max-time 5 http://192.168.1.5:8090/health` 检测恢复。确需轮询时使用 `while` / `seq`，不要用 `for i in {1..30}` 这类花括号展开。
