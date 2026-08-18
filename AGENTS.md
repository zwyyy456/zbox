# zbox 仓库规范

## 项目事实

- zbox 是 macOS 15+ 本地命令中心：Swift 6、SwiftUI + AppKit、单进程、后台常驻、无 Dock 图标、Developer ID 直发。
- App Sandbox 关闭，Hardened Runtime 开启；Accessibility 仅用于移动和缩放前台窗口。
- M1 搜索、命令、应用信息和配置全部留在本机；快捷键保存在 UserDefaults。
- `docs/product-design-v0.1.md` 定义产品范围，`docs/development-plan-v0.1.md` 记录当前实现形状，`docs/validation-log.md` 只记录实际证据。

## 文档路由

| 变更 | 必读 |
| --- | --- |
| 产品范围或下一阶段能力 | `docs/product-design-v0.1.md` |
| Command Registry、平台边界、快捷键、窗口、安全 | `engineering-guidelines.md` |
| M1 既有设计选择 | `docs/development-plan-v0.1.md` |
| 验证命令或已知人工检查 | `docs/validation-log.md` |

## 项目差量约束

- Root Search 与 Direct Hotkey 的 App Launch/Window Command 必须经过同一 Command Registry 执行路径。
- NSPanel、Carbon、Accessibility、ServiceManagement 与 NSWorkspace 集中在 `zbox/Platform` 或 App 生命周期入口。
- 当前不预留插件、XPC、RPC、独立索引、公共 SDK 或跨平台抽象。
- UI、AppKit 和共享运行状态保持 Main Actor 隔离；纯搜索和窗口几何规则保持值语义。
- Accessibility 权限不用于读取、保存或上传窗口内容。

## 验证

- 代码改动按需运行 macOS build、`zboxTests` 或 `script/build_and_run.sh --verify`。
- 不运行 `zboxUITests`，除非用户明确要求。全局快捷键、NSPanel/Space、Accessibility、登录项和多显示器使用人工系统验证。
