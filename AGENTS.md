# Repository Guidelines

本文件是 Codex / Agent 在 zbox 仓库中的执行入口。只保留会改变实现、验证或 review 结论的硬规则；具体工程规则按需读取根目录 `engineering-guidelines.md`。

## 1. 项目定位

- 项目类型：macOS 15+ 本地命令中心，Swift 6，SwiftUI + AppKit。
- 交付形态：单进程、单 App target、后台常驻、无 Dock 图标、Developer ID 直发。
- 安全基线：App Sandbox 关闭，Hardened Runtime 开启；Accessibility 仅用于移动和缩放前台窗口。
- 数据边界：M1 搜索、命令和配置全部在本机完成；快捷键配置使用 UserDefaults，不使用 SwiftData。
- 当前架构以最小 Command Registry 为主链路；不得为假想插件、XPC、RPC、独立索引、公共 SDK 或跨平台需求预留抽象。

## 2. 规范优先级

实现决策按以下顺序使用当前真源：

1. `/Users/zwyyy/code/swift/zbox/AGENTS.md`
2. `/Users/zwyyy/code/swift/zbox/docs/product-design-v0.1.md`
3. `/Users/zwyyy/code/swift/zbox/engineering-guidelines.md`
4. `/Users/zwyyy/code/swift/zbox/docs/development-plan-v0.1.md`
5. `/Users/zwyyy/code/swift/zbox/docs/validation-log.md`

产品设计定义当前产品范围；工程规范定义实现与 review 约束；开发方案记录 M0/M1 已实施基线；验证记录只陈述实际完成和跳过的检查。发现冲突时必须修正文档，不得仅依赖优先级长期解释冲突。

## 3. 按需加载

只读取会影响当前任务的最小文档集：

| 任务范围 | 必读文档 |
| --- | --- |
| 项目导览、产品范围、下一阶段能力 | `docs/product-design-v0.1.md` |
| Swift 架构、状态、并发、错误、日志、安全、文件或测试 | `engineering-guidelines.md` |
| M1 代码形状、平台边界或既有设计选择 | `docs/development-plan-v0.1.md` |
| 验证命令选择、历史检查结果或剩余人工验证 | `docs/validation-log.md` |

不要默认加载全部文档。计划、实现说明和 review 只在规则确实解释决策时引用规则 ID。

## 4. 文档规则

- 规范只写当前会执行、会影响实现、验证或 review 结论的内容。
- 同一主题只能有一个规范真源；其他文档可以链接或引用规则 ID，不得复制后重新解释。
- 新增规则前先查重；能合并、替换或删除旧规则时，不新增平行规则。
- 阶段计划、历史背景和一次性验证结果不得写入长期工程规范。
- 规则与代码或当前产品事实不一致时，必须同步修正，不保留已失效的“当前状态”。

## 5. 实现边界

- SwiftUI View 只呈现状态、保留局部交互状态并发送用户意图。
- NSPanel、Carbon、Accessibility、ServiceManagement 与 NSWorkspace 操作集中在 `zbox/Platform` 或明确的平台 adapter 中；App 生命周期入口可以留在 `zbox/App`。
- App Launch 与 Window Command 无论由 Root Search 还是 Direct Hotkey 触发，都必须继续经过统一的 Command Registry 执行路径。
- 纯计算优先使用值类型和 `nonisolated`；UI、AppKit 和共享可变运行状态保持 MainActor 隔离。
- 不为每个类型创建 protocol。只有真实多实现、平台隔离或回归测试需要替换系统行为时，才增加窄 seam。
- 新能力按可验收的纵向用户闭环实现，不先做脱离真实功能的整体架构改造。
- 并发、错误、日志、安全、隐私、依赖和质量门禁遵守 `engineering-guidelines.md`。

## 6. 验证策略

- 默认构建：

```bash
xcodebuild -project zbox.xcodeproj -scheme zbox -destination 'platform=macOS' build
```

- 默认单元测试：

```bash
xcodebuild -project zbox.xcodeproj -scheme zbox -destination 'platform=macOS' -only-testing:zboxTests test
```

- 构建、启动并确认进程存活：

```bash
script/build_and_run.sh --verify
```

- **默认不运行 UI 测试；只有用户明确要求时才可运行 `zboxUITests`。**
- 文档专属改动默认执行文档一致性和 diff 检查，不强制构建或测试。
- Accessibility、全局快捷键、全屏、Space、外接显示器和登录项等系统行为优先采用受影响范围内的人工验证；无法执行时必须记录原因，不得伪造通过。

## 7. Swift Skills

Swift / SwiftUI 任务应按需使用当前用户级 `swift-*` skills：

- `swift-concurrency-pro`：异步任务、MainActor、Sendable、取消与系统回调边界。
- `swift-testing-pro`：Swift Testing、单元测试和回归验证。
- `swiftui-pro`：SwiftUI View、scene、状态驱动渲染、可访问性和平台语义。
- 与 AppKit 窗口或 responder chain 互操作时，按需使用 macOS AppKit 相关 skill。

Skills 为建议性工具；本仓库部署目标、构建设置和根级规范始终优先。
