# zbox 仓库规范

## 项目事实

- zbox 是 macOS 15+ 本地命令中心：Swift 6、SwiftUI + AppKit、单进程、后台常驻、无 Dock 图标、Developer ID 直发。
- App Sandbox 关闭，Hardened Runtime 开启；Window Management 使用 Accessibility 移动和缩放前台窗口，Text Lookup 内置独立扩展在用户启用并触发时读取有限的选区或指针文本，Calculator 内置独立扩展提供本地整数计算。
- `docs/product-design-v0.1.md` 是核心命令中心产品真源，`docs/product/text-lookup.md` 与 `docs/product/calculator.md` 分别是对应内置扩展的产品真源，`engineering-guidelines.md` 是项目工程规则真源。
- 活动文档按开发与架构规范、产品约定、技术合同、按需操作参考四类路由；`AGENTS.md` 只提供执行入口，已完成的阶段方案和证据位于非规范的 `docs/archive/`。

## 文档路由

| 变更 | 必读 |
| --- | --- |
| 核心产品范围或命令中心行为 | `docs/product-design-v0.1.md` |
| Text Lookup 产品范围、触发、悬浮窗、翻译或建卡行为 | `docs/product/text-lookup.md` |
| Calculator 入口、窗口、输入、运算或数值语义 | `docs/product/calculator.md` |
| Command、快捷键、窗口、Text Lookup、平台、安全或并发边界 | `engineering-guidelines.md` |
| FlashDict 查词表面、资源、bridge payload 或建卡兼容 | `../zdict/Packages/FlashDictIntegrationKit/README.md`；涉及 payload 或跨版本语义时同时读取 `../zdict/docs/contracts/flashcard-contracts.md` |
| Developer ID、公证、翻译模型、真实应用/显示器或跨 App 验收 | 按需读取 `docs/release-readiness.md` |

## 项目特有约束

- Root Search 与 Direct Hotkey 的 App Launch/Window Command 必须经过同一 Command Registry 执行路径。
- Text Lookup 是随主 App 静态编译、拥有独立启停生命周期、状态和设置边界的内置独立扩展；它保留私有触发流，并通过现有 App composition 共享平台能力。当前不建设 macOS App Extension、动态插件 Runtime、XPC/RPC 扩展协议或公共 SDK。
- Calculator 是随主 App 静态编译、由 Command Registry 打开的内置独立扩展；它不增加后台监听、权限或动态插件边界。
- UI、AppKit 和共享运行状态保持 Main Actor 隔离；纯搜索、窗口几何和文本定位规则保持值语义。
- Window Management 不读取窗口内容。Text Lookup 只在用户启用并触发时读取完成查询所需的有限文本和来源，不建立取词历史、不上传捕获内容，只有用户显式建卡时才把约定内容交给 FlashDict。

## 验证

- 代码改动按需运行 macOS build、`zboxTests` 或 `script/build_and_run.sh --verify`。
- 不运行 `zboxUITests`，除非用户明确要求。全局快捷键、NSPanel/Space、Accessibility、登录项、多显示器和跨 App 行为使用人工系统验证。
