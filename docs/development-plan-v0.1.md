# zbox 开发方案 v0.1

> 状态：Implemented（M1 代码基线）
> 初始日期：2026-08-13
> 最后校正：2026-08-14
> 输入约束：《zbox 产品设计文档 v0.1》
> 文档职责：记录 M0/M1 已实施的代码形状和实现顺序；实际完成证据以《zbox 实施验证记录》为准。

## 1. M1 实施基线

仓库已经完成 M0 与 M1 的四个功能切片：

- 一个 macOS App target、一个 Swift Testing 单元测试 target 和一个最小 UI 冒烟测试 target；
- 使用 `MenuBarExtra`、独立 `Settings` scene 和由 `NSPanel` 承载的 Root Search，不创建普通 `WindowGroup`；
- App Launch、Window Command、Root Search 和 Direct Hotkey 共用 Command Registry；
- 已实现应用枚举/启动、三种窗口操作、快捷键配置、开机启动设置和 Accessibility 恢复入口；
- 配置使用 UserDefaults，不使用模板 SwiftData 持久化；
- 最低系统设为 macOS 15；
- Swift Language Mode 设为 Swift 6；
- App Sandbox 关闭，Hardened Runtime 开启。

本文件保留 M0/M1 的实施设计，后续能力不得把其中的阶段描述误当作当前待办；通过、跳过和受环境限制的检查统一记录在 `docs/validation-log.md`。

## 2. 已确定的技术选择

- 单进程、单 App target；
- Developer ID 直发，不做 Mac App Store 适配；
- 后台常驻，不显示 Dock 图标；
- 菜单栏固定提供 Root Search、Settings 和 Quit；
- Root Search 使用 `NSPanel` 承载 SwiftUI；
- Settings 使用 SwiftUI `Settings` scene；
- App Launch 和 Window Command 从第一个功能切片开始共用 Command Registry；
- 应用列表启动后加载一次并保存在内存中；
- 图标按需读取并只做进程内复用；
- 不引入 XPC、RPC、Plugin API、独立索引进程或额外 Swift Package。

## 3. M1 代码形状

```text
ZBoxApp / AppEnvironment
    ├── Root Search
    │     ├── CommandRegistry
    │     └── SearchEngine
    ├── Built-in Commands
    │     ├── Application Commands
    │     └── Window Commands
    └── macOS Integration
          ├── SearchPanelController
          ├── GlobalHotkeyRegistrar
          ├── ApplicationCatalog
          ├── ApplicationLauncher
          ├── ApplicationIconProvider
          └── AccessibilityWindowController
```

依赖规则：

- SwiftUI View 只呈现状态和发送用户动作；
- SearchEngine 只做字符串匹配和排序；
- AppKit、Global Hotkey 和 AX 代码留在 macOS Integration；
- Window Command 不直接操作 `AXUIElement`；
- 不为每个类都创建 protocol，只有测试确实需要替换系统行为时才提供小接口。

建议目录随实现出现，不提前创建空文件：

```text
zbox/
├── App/
├── Commands/
├── Search/
├── Builtins/
├── Platform/
└── Settings/
```

## 4. App 生命周期

M1 采用类似 Raycast 的简单常驻形态：

1. App 启动后进入 accessory/UIElement 模式，不创建普通主窗口；
2. 菜单栏图标始终存在，提供打开 Root Search、Settings 和 Quit；
3. 全局快捷键触发时，先记录当前前台应用 PID，再显示 Root Search Panel；
4. Panel 显示在当前 Space，获得键盘焦点，但不丢失已经记录的目标应用；
5. 再次按快捷键、按 Escape、失焦或命令完成后隐藏 Panel；
6. Settings 作为独立普通窗口打开，不复用 Panel；
7. App 没有任何可见窗口时继续后台常驻。

实现时移除模板 `WindowGroup`，使用 `MenuBarExtra`、`Settings` scene 和一个窄的 `SearchPanelController`。`NSPanel` 的焦点、Space 和全屏行为由 AppKit adapter 负责，不把 `NSWindow` 操作散落到 SwiftUI View。

## 5. 最小 Command 模型

Slice 1 直接使用最小版 `CommandID + CommandDescriptor + CommandRegistry`：

```swift
struct CommandID: Hashable, Sendable {
    let rawValue: String
}

struct CommandDescriptor: Identifiable, Sendable {
    let id: CommandID
    let title: String
    let subtitle: String?
    let keywords: [String]
}

enum CommandSource: Sendable {
    case rootSearch
    case directHotkey
}

struct CommandContext: Sendable {
    let source: CommandSource
    let frontmostApplicationPID: Int32?
}

@MainActor
final class CommandRegistry {
    func register(
        _ descriptor: CommandDescriptor,
        perform: @escaping @MainActor (CommandContext) async throws -> Void
    ) throws

    var descriptors: [CommandDescriptor] { get }

    func execute(_ id: CommandID, context: CommandContext) async throws
}
```

`CommandID` 的 `Hashable` 只用于作为 Registry 字典键，从而按 ID 查找并拒绝重复注册；不涉及内容哈希、磁盘索引或缓存协议。`CommandDescriptor` 不需要 `Hashable`。

Slice 1 不实现统一错误对象、耗时统计、使用频率或插件序列化。执行失败先抛出具体错误，由调用处显示简单反馈；等错误类型真的重复后再收拢。

应用命令 ID 优先使用 bundle identifier。缺少 bundle identifier 时使用标准化后的应用 URL；不额外计算文件内容哈希。

## 6. SearchEngine

```swift
nonisolated struct SearchEngine {
    func search(
        query: String,
        in commands: [CommandDescriptor],
        limit: Int
    ) -> [SearchMatch]
}
```

SearchEngine 是同步纯计算，只实现：

- 大小写和变音符号归一化；
- title 和 keywords 匹配；
- 简单模糊匹配；
- 相同结果的固定排序；
- `limit`。

M1 不实现 frecency、搜索历史、后台搜索任务或可插拔 ranking provider。本机应用和内置命令数量足够小时，同步搜索更容易理解；只有实际使用出现明显卡顿时再改变执行方式。

## 7. 应用枚举、启动与图标

### 7.1 ApplicationCatalog

启动后读取系统和用户常见应用目录，生成一个 `[ApplicationInfo]` 并保存在 AppEnvironment 中。M1 不监听应用安装变化；新安装应用可在重启 zbox 后出现，也可以通过菜单栏的 Reload Applications 手动重载。

每个应用只保存 MVP 需要的数据：

- 显示名；
- bundle identifier；
- app URL。

处理标准目录中的 `.app`、同一 bundle identifier 的重复项和无法启动的条目。用户自定义搜索目录以后再做。

### 7.2 ApplicationLauncher

根据应用 URL 使用 `NSWorkspace` 启动或激活应用。Catalog 和 Launcher 如果实现很短，可以先放在同一文件中，不强行创建两层转发。

### 7.3 ApplicationIconProvider

图标实现保持简单：

- Search View 根据 app URL 请求图标；
- 第一次请求时通过 `NSWorkspace` 读取；
- 使用 `[URL: NSImage]` 在进程内复用；
- 不写磁盘、不预取、不监听文件变化；
- zbox 退出后缓存自然消失。

图标不进入 `CommandDescriptor`，避免搜索模型依赖 `NSImage`。

## 8. 窗口命令与 CommandContext

`AccessibilityWindowController` 对外只提供：

```swift
enum WindowAction {
    case leftHalf
    case rightHalf
    case maximize
}

func perform(_ action: WindowAction, targetPID: Int32?) throws
```

内部处理 Accessibility 权限、目标应用的 focused window、坐标转换、当前显示器的 `visibleFrame` 以及不可调整窗口的错误。

两种触发方式都产生相同的 `CommandContext`：

- Root Search：在 Panel 显示之前记录前台应用 PID；
- Direct Hotkey：在热键回调时记录前台应用 PID 并立即执行。

MVP 不长期持有 `AXUIElement`，也不建设复杂的窗口身份系统。执行时根据已经记录的 PID 获取该应用的 focused window；窗口已经关闭或不可用时明确失败。

## 9. M0 技术检查

M0 只做三个小型可运行验证，每个验证保留结论和必要代码。

### Check 1：Hotkey、生命周期与 Search Panel

- App 在后台常驻且不显示 Dock 图标；
- 菜单栏可以打开 Settings 和退出；
- 全局快捷键可以显示、隐藏 Panel；
- 输入框立即获得焦点；
- Escape、重复快捷键、失焦行为一致；
- 普通桌面、全屏应用和不同 Space 下可以使用。

### Check 2：应用枚举与启动

- 能读取常见应用目录；
- 名称、bundle identifier 和 URL 足够生成应用 Command；
- 可以启动未运行应用并激活已运行应用；
- 重复应用和启动失败不会让搜索崩溃。

### Check 3：Accessibility 窗口操作

- 完成授权提示和进入系统设置的入口；
- Left Half、Right Half、Maximize 能操作唤起前的窗口；
- Root Search 和 Direct Hotkey 都能传递正确目标 PID；
- 单显示器和外接显示器下使用 `visibleFrame`；
- 无窗口、窗口不可调整和权限缺失都有明确错误。

三个检查完成后即可进入 M1，不要求额外性能报告或架构文档。

## 10. M1 实现顺序

### Slice 1：统一 Command 路径的 App Search

一次交付：

```text
App Launch
  → 后台常驻和菜单栏
  → Global Hotkey
  → Root Search Panel
  → ApplicationCatalog
  → Application Command 注册
  → SearchEngine
  → Registry.execute
  → Launch / Activate
```

这一阶段就建立最小 `CommandID`、`CommandDescriptor`、`CommandContext` 和 `CommandRegistry`，不存在应用专用执行旁路。

完成证据：可以只用键盘搜索并启动/激活应用；Registry 和 SearchEngine 有单元测试。

### Slice 2：Window Commands

加入 Left Half、Right Half、Maximize、Accessibility 权限引导和简单错误反馈。三个命令注册到同一个 Registry。

完成证据：矩形计算有单元测试；常见应用、外接显示器和权限变化经过手工验证。

### Slice 3：Direct Hotkey 与 Settings

加入 Root Search 快捷键设置、命令快捷键、冲突提示和开机启动。配置使用 `CommandID.rawValue` 保存到 UserDefaults；不使用 SwiftData。

完成证据：配置重启后仍然存在；移除快捷键可以立即注销；Root Search 和 Direct Hotkey 操作同一目标窗口规则。

### Slice 4：产品收口

统一成功和错误提示，补齐菜单栏命令、键盘操作、Accessibility 文案和真实使用中发现的问题。

## 11. Swift 6 与并发规则

- 所有 target 使用 Swift 6 language mode；
- App target 保持 MainActor 默认隔离，适合 SwiftUI、AppKit、Registry 和系统 adapter；
- SearchEngine 显式 `nonisolated`，因为它只接收值并返回值；
- 不因为方法可能失败或调用系统 API 就自动改成 async；
- 只有真正异步等待的 launch API 或 Command 执行使用 async；
- 不创建自定义 actor、后台队列或无所有者的 `Task`，除非实际实现出现需要共享的并发状态。

## 12. 测试与验收

### 单元测试

- Command 注册、重复 ID、列表和执行；
- Search 归一化、模糊匹配、关键词、limit 和固定顺序；
- 窗口矩形计算和显示器选择；
- 快捷键配置保存和冲突检测。

### 少量集成测试

- 测试用 ApplicationLauncher 下的应用 Command；
- 测试用 WindowController 下的三个窗口 Command；
- Root Search 与 Direct Hotkey 的 CommandContext。

### 手工验收

- Finder、Safari、Xcode、系统设置和至少一个跨平台 App；
- 普通桌面、全屏应用和多个 Space；
- 单显示器和外接显示器；
- Accessibility 首次授权、拒绝、撤销和重新授权；
- 启动应用、激活应用、隐藏 Panel、打开 Settings 和退出。

## 13. 当前决策记录

| ID | 决策 |
| --- | --- |
| DEC-001 | 最低 macOS 15，Swift 6 |
| DEC-002 | Developer ID 直发，关闭 App Sandbox，保留 Hardened Runtime |
| DEC-003 | 后台常驻、无 Dock、固定菜单栏入口、临时 Root Search Panel、独立 Settings 窗口 |
| DEC-004 | Slice 1 即使用最小 Command Registry |
| DEC-005 | 应用列表内存保存；图标只做按需进程内复用 |
| DEC-006 | Global Hotkey 使用 Carbon `RegisterEventHotKey`，注册与回调状态保持 MainActor 隔离 |
| DEC-007 | 窗口所属显示器优先按中心点判断，必要时以最大交叠面积回退 |

以上选择构成当前 M1 基线。后续实现继续以满足 macOS 15 和真实产品需求为准，不为未来键盘引擎或 Display 管理预留额外层次。

## 14. 主要风险

| 风险 | 处理方式 |
| --- | --- |
| Panel 抢走前台上下文 | 显示 Panel 前记录目标 PID；Root Search 和 Direct Hotkey 共用 CommandContext |
| 全屏或 Space 中 Panel 不出现 | M0 Check 1 验证 `NSPanel.CollectionBehavior` 和激活顺序 |
| 多显示器坐标错误 | 几何计算独立成纯函数，并对 `visibleFrame` 做单元测试 |
| Accessibility 权限变化后无法恢复 | 每次窗口命令执行前检查权限，不把授权状态永久保存在内存中 |
| 应用重复或无法启动 | Catalog 去重；Launcher 返回明确错误 |
| 提前抽象导致代码变散 | 保持单 target；只为 Hotkey、App Launch 和 AX 等真实系统边界设置替换点 |

M2 开始后仍不默认引入插件 Runtime、跨进程通信、独立索引、公共 SDK 或 Package 拆分；只有真实复用和隔离需求出现后再单独设计。
