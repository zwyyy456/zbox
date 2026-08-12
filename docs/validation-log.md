# zbox 实施验证记录

只记录每个阶段实际完成的检查和因环境限制跳过的项目，不设置性能闸门、基线、快照或哈希校验。

## M0：macOS 能力验证

- 通过：使用 Swift 6、macOS 15 deployment target 完成 Debug 构建。
- 通过：统一运行脚本可以构建、启动并确认 zbox 进程存活。
- 通过：应用以 `LSUIElement` 辅助应用运行，无 Dock 图标；App Sandbox 未启用，Hardened Runtime 保持启用。
- 通过：搜索面板可以由全局快捷键显示，面板可获得输入焦点并接收文本。
- 通过：扫描 `/Applications`、`/System/Applications` 和用户 Applications 目录，当前环境读取到 128 个应用。
- 通过：应用启动链路实际打开目标应用；回车执行前显式同步 AppKit 输入框文本，避免 SwiftUI 绑定尚未提交时误选首项。
- 通过：当前开发环境已授予辅助功能权限，窗口半屏与最大化命令已实现基于可见屏幕区域的坐标换算。
- 发现：当前机器运行中的 Raycast 已占用 Option-Space；M1 临时默认键改用 Control-Option-Space，快捷键配置与冲突提示留到 Slice 3。
- 跳过：外接显示器、不同 Space 和全屏应用上的人工验证，当前运行环境不具备稳定自动化条件。

## Slice 1：统一 Command 路径的 App Search

- 通过：应用使用 Swift 6、macOS 15 deployment target 完成签名构建并启动进程。
- 通过：应用目录当前读取到 128 个应用，并全部注册为最小 `CommandDescriptor`；应用执行只经过 `CommandRegistry.execute`。
- 通过：Registry 的注册顺序、重复 ID、未知 ID 和执行上下文测试通过。
- 通过：SearchEngine 的大小写与变音符号归一化、关键词、简单模糊匹配、限制数量和固定排序测试通过。
- 通过：8 个 Swift Testing 单元测试全部通过。
- 通过：应用图标按搜索结果所需读取，并只在当前进程内复用。
- 跳过：合成全局按键和辅助功能菜单点击未触发 SwiftUI action；达到本项验证时间限制后停止，保留 M0 已完成的真实面板与应用启动验证结果。

## Slice 2：Window Commands

- 通过：Left Half、Right Half 和 Maximize 以三个内置 Command 注册到应用命令使用的同一个 Registry。
- 通过：窗口命令使用 Root Search 显示前记录的目标应用 PID；没有应用专用或窗口专用执行旁路。
- 通过：权限缺失、目标应用消失、无焦点窗口、读写窗口失败和无可用显示器都会显示现有的简短错误。
- 通过：半屏、最大化、AX/Cocoa 坐标转换、中心点显示器选择、最大交叠回退和完全离屏场景测试通过。
- 通过：13 个 Swift Testing 单元测试全部通过，签名构建与进程启动通过。
- 通过：当前开发环境的 Accessibility 授权状态为已授权。
- 跳过：常见应用窗口和外接显示器的人工操作验证；当前自动化无法可靠触发 Root Search action，且没有外接显示器条件。
