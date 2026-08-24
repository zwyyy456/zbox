# zbox 仓库规范

## 项目事实

- zbox 是 macOS 15+ 本地命令中心：Swift 6、SwiftUI + AppKit、单进程、后台常驻、无 Dock 图标、Developer ID 直发。
- App Sandbox 关闭，Hardened Runtime 开启；Accessibility 用于窗口控制和用户启用的 Text Lookup 捕获。
- `docs/product-design-v0.1.md` 是当前产品行为真源；`engineering-guidelines.md` 是当前项目工程规则真源。

## 文档路由

| 变更 | 必读 |
| --- | --- |
| 产品范围、命令中心或 Text Lookup 行为 | `docs/product-design-v0.1.md` |
| Command、快捷键、窗口、Text Lookup、平台、安全或并发边界 | `engineering-guidelines.md` |
| Developer ID、公证、翻译模型、真实应用/显示器或跨 App 验收 | 按需读取 `docs/release-readiness.md` |

## 项目特有约束

- Root Search、Direct Hotkey 和 Text Lookup 入口使用各自明确 owner，并通过现有 App composition 共享平台能力；不建立动态插件 Runtime、XPC/RPC 或公共 SDK。
- UI、AppKit 和共享运行状态保持 Main Actor 隔离；纯搜索、窗口几何和文本定位规则保持值语义。
- 捕获的正文、原句、来源和释义只在当前会话处理，不进入普通日志或本地历史。

## 验证

- 代码改动按需运行 macOS build、`zboxTests` 或 `script/build_and_run.sh --verify`。
- 不运行 `zboxUITests`，除非用户明确要求。全局快捷键、NSPanel/Space、Accessibility、登录项、多显示器和跨 App 行为使用人工系统验证。
