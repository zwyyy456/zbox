# zbox 仓库规范

## 项目事实

- zbox 是 macOS 15+ 本地命令中心：Swift 6、SwiftUI + AppKit、单进程、后台常驻、无 Dock 图标、Developer ID 直发。
- App Sandbox 关闭，Hardened Runtime 开启；Window Management 使用 Accessibility 移动和缩放前台窗口，Text Lookup 内置独立扩展在用户启用并触发时读取有限的选区或指针文本。
- `docs/product-design-v0.1.md` 是当前产品行为真源；`engineering-guidelines.md` 是当前项目工程规则真源。已完成的阶段方案和证据位于 `docs/archive/`。

## 文档路由

| 变更 | 必读 |
| --- | --- |
| 产品范围、命令中心或 Text Lookup 行为 | `docs/product-design-v0.1.md` |
| Command、快捷键、窗口、Text Lookup、平台、安全或并发边界 | `engineering-guidelines.md` |
| Developer ID、公证、翻译模型、真实应用/显示器或跨 App 验收 | 按需读取 `docs/release-readiness.md` |

## 项目特有约束

- Root Search 与 Direct Hotkey 的 App Launch/Window Command 必须经过同一 Command Registry 执行路径。
- Text Lookup 是随主 App 静态编译、拥有独立启停生命周期、状态和设置边界的内置独立扩展；它保留私有触发流，并通过现有 App composition 共享平台能力。当前不建设 macOS App Extension、动态插件 Runtime、XPC/RPC 扩展协议或公共 SDK。
- UI、AppKit 和共享运行状态保持 Main Actor 隔离；纯搜索、窗口几何和文本定位规则保持值语义。
- Window Management 不读取窗口内容。Text Lookup 只在用户启用并触发时读取完成查询所需的有限文本和来源，不建立取词历史、不上传捕获内容，只有用户显式建卡时才把约定内容交给 FlashDict。

## 验证

- 代码改动按需运行 macOS build、`zboxTests` 或 `script/build_and_run.sh --verify`。
- 不运行 `zboxUITests`，除非用户明确要求。全局快捷键、NSPanel/Space、Accessibility、登录项、多显示器和跨 App 行为使用人工系统验证。
