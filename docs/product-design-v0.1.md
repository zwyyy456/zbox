# zbox 产品设计文档 v0.1

> 权威性：Normative Product Baseline
> 加载方式：涉及核心产品范围、命令中心行为或 M1 验收边界时读取
> 状态：Active（当前产品基线）
> 初始日期：2026-08-13
> 最后校正：2026-10-03
> 适用范围：M1 命令中心与 Window Management 内置插件
> 文档职责：定义核心命令中心的当前产品范围、用户行为与验收边界；Text Lookup 产品约定见 `product/text-lookup.md`，工程边界见根目录 `engineering-guidelines.md`。

## 1. 产品定义

zbox 是一个面向 macOS power users 的本地命令中心，让应用、窗口和系统操作都可以通过搜索和键盘快速完成。

长期愿景是成为“macOS 原生能力平台 + 命令入口 + 扩展生态”。MVP 不以插件生态为卖点，也不复刻 Raycast 的完整功能集。

### 1.1 已确定的产品与平台选择

- 最低支持 macOS 15；
- 使用 Swift 6；
- MVP 以 Developer ID 签名并在 Mac App Store 之外分发；
- App Sandbox 关闭，Hardened Runtime 保持开启；
- 采用类似 Raycast 的后台常驻体验：启动时不显示普通主窗口，也不出现在 Dock；
- 菜单栏提供打开 Root Search、Settings 和退出入口；
- 全局快捷键在用户当前工作的 Space 上显示 Root Search；
- Settings 使用独立窗口，可通过 Root Search、菜单栏或 `Command-,` 打开。

### 1.2 核心与内置插件

核心负责 Root Search、Command Registry、全局快捷键协调、设置入口以及应用搜索与启动。Window Management、Text Lookup、Calculator、Clipboard History、Screenshot、Workspace、Display、Quicklinks、Snippets、File Search、Developer Tools、Script Commands、Audio、Application Menu 是随主 App 静态编译的内置插件，分别管理自身功能状态与界面。窗口管理通过 Registry 暴露命令，并使用共享的快捷键与授权能力。

### 1.3 MVP 要验证的核心假设

1. 用户能够比 Dock、Spotlight 或菜单操作更快地完成应用启动和窗口整理。
2. `Command` 可以成为搜索和直接快捷键共同使用的产品抽象。
3. 当搜索反馈足够快、行为足够稳定时，目标用户愿意让 zbox 常驻并形成使用习惯。

## 2. 目标用户

首批用户是使用 macOS 工作的开发者和效率工具重度用户。他们通常：

- 高频使用键盘，愿意学习 command palette；
- 同时运行多个应用，经常整理窗口；
- 可能连接外部显示器；
- 已经理解 Spotlight、Alfred 或 Raycast 一类工具；
- 重视响应速度、可预测性、本地优先和快捷键定制。

暂不优先服务只使用鼠标和 Dock 的轻度用户，以及首版就需要完整插件市场、AI、云服务或跨平台 SaaS 集成的用户。

## 3. 用户问题

### P-01：常用操作入口分散

启动应用、移动窗口和触发系统操作需要在 Dock、菜单栏、快捷键工具之间切换，用户需要记住多套入口。

### P-02：窗口操作缺少统一、可搜索的模型

窗口动作通常只能通过鼠标拖动或预先记住的快捷键完成；用户难以发现动作，也难以在搜索和快捷键之间自由切换。

### P-03：命令入口必须稳定

Root Search 如果抢焦点、跨 Space 行为混乱、操作了错误窗口或经常唤起失败，就无法替代用户已有的工作流。

## 4. 核心使用路径

```text
全局快捷键
  → Root Search
  → 搜索应用或命令
  → 执行
  → 成功或错误反馈
```

用户留下来的理由是以下体验同时成立：

- 一个入口同时覆盖应用启动和窗口操作；
- 不必先记住窗口命令的快捷键，先搜索即可发现；
- 高频命令可以再绑定直接快捷键；
- 权限缺失、不支持或执行失败时都有明确反馈；
- 所有 MVP 搜索和配置都在本机完成。

## 5. 产品原则

1. **键盘优先，但行为可发现。** 命令可以搜索，常用命令可以绑定快捷键。
2. **本地优先。** MVP 不依赖账号或网络，不上传搜索词和使用内容。
3. **统一而非堆叠。** 应用启动和窗口动作都表现为 Command。
4. **明确失败。** 不静默吞掉权限、焦点或窗口操作错误。
5. **先满足日用，再平台化。** 不为未来插件提前建设 Runtime、RPC 或公共 SDK。

## 6. MVP 使用场景

### S-01：启动应用

用户按全局快捷键，输入应用名的部分字符，选中结果并回车。zbox 启动应用；如果应用已经运行，则将其激活。

### S-02：通过搜索整理当前窗口

用户唤起 zbox，搜索 `Left Half`、`Right Half` 或 `Maximize` 并执行。zbox 操作唤起前的前台应用窗口，然后给出成功或失败反馈。

Window Management 默认关闭，但窗口命令始终保留在 Root Search 中供用户发现。功能尚未启用时，执行窗口命令只提供进入对应设置的恢复操作，不直接请求 Accessibility 权限或操作窗口。

### S-03：为命令绑定直接快捷键

用户在 Settings 中直接录制某个内置命令的全局快捷键。此后无需打开 Root Search 即可执行；冲突、无效组合或系统注册失败必须显示在对应录制项附近。功能关闭或缺少所需权限时，对应直接快捷键不注册。

### S-04：处理权限缺失或不可操作窗口

用户显式启用 Window Management 时，zbox 先解释 Accessibility 用途，再由用户请求权限。普通命令失败不得自动触发系统授权提示。权限被撤销后，窗口管理自动关闭并停止相关快捷键，但保留其它配置；用户重新授权后再次启用功能即可恢复。目标应用没有窗口、窗口不可调整或操作失败时，Root Search 与 Direct Hotkey 显示相同、具体而简短的错误语义。

## 7. MVP 功能需求

优先级说明：P0 是 MVP 必需，P1 可以根据实际进度延后。

| ID | 优先级 | 需求 | 验收摘要 |
| --- | --- | --- | --- |
| FR-01 | P0 | 全局快捷键唤起/隐藏 Root Search | 在普通前台应用、全屏应用和不同 Space 中行为一致 |
| FR-02 | P0 | 键盘完成查询、选择、执行和退出 | 输入焦点默认在搜索框；方向键、`Control-N` / `Control-P`、Return、Escape 行为明确 |
| FR-03 | P0 | 枚举、搜索并启动本机应用 | 支持应用名、中文应用名的全拼/首字母和简单模糊匹配；已运行应用可被激活 |
| FR-04 | P0 | 搜索并执行内置 Command | App Launch 与内置命令使用同一个 Registry 和结果模型 |
| FR-05 | P0 | Left Half、Right Half、Maximize | Window Management 默认关闭但命令保持可发现；启用后作用于唤起 zbox 前的目标窗口，并按当前显示器可用区域计算 |
| FR-06 | P0 | 成功、失败和权限反馈 | 权限缺失、无目标窗口、不支持调整和执行失败均不静默；Direct Hotkey 成功静默、失败显示非激活反馈 |
| FR-07 | P1 | 为内置 Command 录制全局快捷键 | 可添加、修改、移除；检测无效组合、zbox 内部冲突和系统注册失败；失败不覆盖上一可用配置 |
| FR-08 | P1 | 基础设置 | 使用 General、Shortcuts 两个核心 Tab，并为 Window Management、Text Lookup、Clipboard History、Screenshot、Workspace、Display、Quicklinks、Snippets、File Search 内置插件提供独立 Tab；核心设置负责快捷键、开机启动和应用路径显示，插件设置分别由 `product/window-management.md`、`product/text-lookup.md`、`product/clipboard-history.md`、`product/screenshot.md`、`product/workspace.md`、`product/display.md`、`product/quicklinks.md`、`product/snippets.md` 和 `product/file-search.md` 定义 |
| FR-09 | P1 | 英文与简体中文界面 | Settings、菜单栏、Root Search、Command、错误与权限说明使用同一 String Catalog 真源，不混用未本地化硬编码文案 |

### 7.1 搜索行为

- 空查询展示少量固定命令；后续根据实际使用再调整。
- 搜索数据只来自本机应用和内置命令，不访问网络。
- 匹配标题和关键词，支持简单、确定性的模糊匹配。
- 中文应用名在 Command 创建时预生成带空格全拼、无空格全拼和拼音首字母别名；SearchEngine 仍保持与应用枚举和拼音转写无关的同步纯匹配器。
- 排名保持字面标题高于全拼别名、全拼别名高于首字母别名、首字母别名高于模糊匹配；同分结果保持固定顺序。
- 暂不加入 frecency、别名学习或搜索历史排序。

### 7.2 窗口管理插件

Window Management 以内置插件提供窗口命令，其启停、权限、目标窗口及显示器行为见 [Window Management 产品约定](product/window-management.md)。它仍属于 M1 交付与验收范围。

### 7.3 App 生命周期

- 登录或手动启动 zbox 后，应用在后台常驻，不自动弹出普通窗口。
- Root Search 是临时 Panel：全局快捷键显示，再次按快捷键、按 Escape 或完成命令后隐藏。
- Root Search 默认显示在当前工作的 Space；全屏应用前台时也应可用。
- 菜单栏图标在 M1 固定显示，提供 Root Search、Settings 和 Quit；是否允许隐藏以后再决定。
- Settings 是普通独立窗口，不和 Root Search 共用窗口生命周期。
- Root Search 外层使用统一连续圆角裁剪；应用路径默认不显示，可在 General 设置中开启且不影响搜索关键词。

## 8. MVP 范围

本节界定 M1 命令中心及随附的 Window Management 内置插件。Text Lookup 不并入 M1 完成定义；它作为内置独立扩展按 `product/text-lookup.md` 单独实施和验收。

### 8.1 包含

- Root Search Panel；
- 应用搜索、启动和激活；
- Command Registry 与内置命令；
- Window Management 内置插件的三个窗口命令；
- Root Search 全局快捷键；
- 命令快捷键；
- 最小 Settings；
- 菜单栏入口；
- 成功和错误反馈；
- Accessibility 权限引导。

### 8.2 不包含

- 第三方插件、Extension SDK、JS Runtime、RPC 或 XPC；
- 文件索引和文件内容搜索；
- Clipboard History、通用 Selected Text 命令或文本工具箱；
- Display 开关、拓扑控制和 Workspace；
- Calendar、Contacts、Snippets、Calculator；
- AI、云同步、账号、团队功能；
- Hyper Key、chord、tap/hold 等高级键盘引擎；
- Mac App Store 适配；
- 复杂排名、使用频率学习和磁盘图标缓存。

## 9. MVP 验收

M1 可以被称为“可日用 MVP”，需要满足：

1. FR-01 至 FR-06 可以在真实工作流中稳定完成；
2. Finder、Safari、Xcode、系统设置和至少一个跨平台 App 可以被搜索、启动和激活；
3. 三个窗口命令在常见可调整窗口上工作，并验证单显示器和外接显示器；
4. Accessibility 首次授权、拒绝、撤销后重新授权均可恢复；
5. Root Search 在普通桌面、全屏应用和多个 Space 下行为一致；
6. 没有常规路径崩溃、快捷键失效后无法恢复或窗口严重错位的问题；
7. 至少进行一轮真实使用，并记录阻碍日用的问题。

FR-07 和 FR-08 已进入 M1 实施基线；仍需真实系统或分发环境的验收见 `release-readiness.md`。

## 10. MVP 之后

| 阶段 | 产品目标 |
| --- | --- |
| M2 System Toolkit | Text Lookup、Clipboard History、Screenshot、Workspace 与 Display 已进入当前产品 |
| M3 Internal Extensions | Window Management、Text Lookup、Calculator、Clipboard History 和 Screenshot 以真实功能检验内置插件边界 |
| M4 Plugin Preview | 再决定独立 Runtime、权限和 SDK |

Window Management、Text Lookup 与 Calculator 作为内置独立扩展验证单 App target 内的功能边界，但不构成动态插件系统；其当前产品约定分别见 `product/window-management.md`、`product/text-lookup.md` 与 `product/calculator.md`。只有真实功能需要复用或隔离时，才引入新的 Package、进程或公共插件接口。

Clipboard History 作为默认关闭的内置插件独立实施和验收，产品约定见 `product/clipboard-history.md`；不改变上述 M1 完成定义。

Screenshot 作为默认关闭的内置插件独立实施和验收，包含用户配置的图床上传；产品约定见 `product/screenshot.md`，不改变 M1 的本地命令中心范围。

## 11. M1 已决问题

| ID | 决策 |
| --- | --- |
| OQ-01 | 默认不开启开机启动；用户通过 Settings 中的 Launch at Login 显式控制。 |
| OQ-02 | 空查询先展示 Left Half、Right Half、Maximize，再展示应用命令。 |
| OQ-03 | M1 只枚举 `/Applications`、`/System/Applications` 和 `~/Applications`，不支持自定义目录。 |
| OQ-04 | 优先按窗口中心点选择显示器；中心点不在任何显示器时，以最大交叠面积回退；完全离屏时明确失败。 |
| OQ-05 | Window Management 默认关闭；窗口 Command 始终留在 Root Search 中，功能关闭时执行只引导用户进入对应设置。 |
| OQ-06 | 权限撤销后自动关闭依赖功能并保留其它配置；重新授权后不自动恢复，由用户再次启用。 |
| OQ-07 | Direct Hotkey 成功静默；失败使用不激活 zbox 的轻量反馈 Panel。 |
| OQ-08 | 用户快捷键使用真实录制，不保留旧预设枚举兼容；Root Search 无有效持久化值时回落默认快捷键，Command 回落未分配。 |
| OQ-09 | 用户可见产品名暂统一为小写 `zbox`；后续名称调整通过 String Catalog 统一完成。 |

Workspace 作为默认关闭的内置插件，保存并恢复每个应用一个普通主窗口的布局；产品约定见 `product/workspace.md`，不改变 M1 完成定义。

Display 作为默认关闭的内置插件，管理现有显示模式、刷新率、预设及切换确认；原生 HiDPI 配置需要管理员授权并在重启后验证。产品约定见 `product/display.md`，不改变 M1 完成定义。

Quicklinks 与 Snippets 作为默认关闭的内置插件，分别管理快捷入口及可复制／粘贴的纯文本模板；产品约定见 `product/quicklinks.md` 与 `product/snippets.md`，不改变 M1 完成定义。

File Search 作为默认关闭的内置插件，为用户选择的本地目录建立文件名索引并提供搜索、预览和文件操作；产品约定见 `product/file-search.md`，不改变 M1 完成定义。

Developer Tools 作为始终可用的内置插件，提供本地 JSON、时间戳、UUID、URL 与 Base64 工具，共用独立窗口；产品约定见 `product/developer-tools.md`，不增加设置 Tab 或后台监听。

Script Commands 作为默认关闭的内置插件，提供本地脚本的配置、参数输入、执行与输出查看；产品约定见 `product/script-commands.md`，不增加动态插件运行时。
