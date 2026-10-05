# zbox 仓库规范

## 项目事实

- zbox 是 macOS 15+ 本地命令中心：Swift 6、SwiftUI + AppKit、单进程、后台常驻、无 Dock 图标、Developer ID 直发。
- App Sandbox 关闭，Hardened Runtime 开启；Window Management 内置插件使用 Accessibility 移动和缩放前台窗口，Text Lookup 内置独立扩展在用户启用并触发时读取有限的选区或指针文本，Calculator 内置独立扩展提供本地整数计算。
- `docs/product-design-v0.1.md` 是核心命令中心产品真源，`docs/product/window-management.md`、`docs/product/text-lookup.md` 与 `docs/product/calculator.md` 分别是对应内置插件的产品真源，`docs/product/screenshot.md` 定义 Screenshot 的截图及上传行为；`engineering-guidelines.md` 是项目工程规则真源。
- 活动文档按开发与架构规范、产品约定、技术合同、按需操作参考四类路由；`AGENTS.md` 只提供执行入口，已完成的阶段方案和证据位于非规范的 `docs/archive/`。

## 文档路由

| 变更 | 必读 |
| --- | --- |
| 核心产品范围或命令中心行为 | `docs/product-design-v0.1.md` |
| Window Management 启停、权限、窗口命令或显示器行为 | `docs/product/window-management.md` |
| Text Lookup 产品范围、触发、悬浮窗、翻译或建卡行为 | `docs/product/text-lookup.md` |
| File Search 范围、索引、查询、文件操作 | `docs/product/file-search.md` |
| Quicklinks 入口、参数、执行与存储 | `docs/product/quicklinks.md` |
| Snippets 模板、变量、复制与粘贴 | `docs/product/snippets.md` |
| 应用菜单搜索、读取与执行 | `docs/product/app-menu.md` |
| Audio 设备、音量与静音 | `docs/product/audio.md` |
| Display 模式、预设、恢复和原生 HiDPI 配置 | `docs/product/display.md` |
| Workspace 捕获、保存和恢复布局 | `docs/product/workspace.md` |
| Screenshot 截图、编辑、OCR、贴图、图床、上传或屏幕捕获权限 | `docs/product/screenshot.md` |
| Clipboard History 采集、隐私、存储、粘贴或管理行为 | `docs/product/clipboard-history.md` |
| 自动化（Script Commands）、Apple 快捷指令、参数、输出与进程生命周期 | `docs/product/script-commands.md` |
| Developer Tools 入口、文本编辑、转换语义或会话生命周期 | `docs/product/developer-tools.md` |
| Calculator 入口、窗口、输入、运算或数值语义 | `docs/product/calculator.md` |
| 外部扩展安装、运行、界面、授权及 SDK | `docs/product/extensions.md`、`docs/contracts/extensions.md` |
| Command、快捷键、窗口、Text Lookup、平台、安全或并发边界 | `engineering-guidelines.md` |
| FlashDict 查词表面、资源、bridge payload 或建卡兼容 | `../zdict/Packages/FlashDictIntegrationKit/README.md`；涉及 payload 或跨版本语义时同时读取 `../zdict/docs/contracts/flashcard-contracts.md` |
| Developer ID、公证、翻译模型、真实应用/显示器或跨 App 验收 | 按需读取 `docs/release-readiness.md` |

## 项目特有约束

- Root Search 与 Direct Hotkey 的 App Launch/Window Command 必须经过同一 Command Registry 执行路径。
- Window Management 是随主 App 静态编译的内置插件，拥有独立启停、设置和窗口操作边界；通过核心 Registry 和共享快捷键能力执行。
- Text Lookup 是随主 App 静态编译、拥有独立启停生命周期、状态和设置边界的内置独立扩展；它保留私有触发流，并通过现有 App composition 共享平台能力。Text Lookup 不接入外部扩展协议；可安装扩展的边界见 `docs/product/extensions.md`。
- Calculator 是随主 App 静态编译、由 Command Registry 打开的内置独立扩展；它不增加后台监听、权限或动态插件边界。
- UI、AppKit 和共享运行状态保持 Main Actor 隔离；纯搜索、窗口几何和文本定位规则保持值语义。
- Window Management 不读取窗口内容。Text Lookup 只在用户启用并触发时读取完成查询所需的有限文本和来源，不建立取词历史、不上传捕获内容，只有用户显式建卡时才把约定内容交给 FlashDict。

## 验证

- 代码改动按需运行 macOS build、`zboxTests` 或 `script/build_and_run.sh --verify`。
- 不运行 `zboxUITests`，除非用户明确要求。全局快捷键、NSPanel/Space、Accessibility、登录项、多显示器和跨 App 行为使用人工系统验证。
