# zbox 工程规范

- 权威性：Normative
- 加载方式：涉及 Command、快捷键、窗口、Text Lookup、平台、安全或并发边界时读取
- 状态：Active
- 职责：定义 zbox 专用的长期工程与架构边界；产品行为由对应产品约定定义

## Command 与平台边界

- Command 是 Root Search 和直接快捷键共享的稳定业务接口；从这两个入口暴露的 App Launch、Window Command 或其它 Command 能力不得绕过 Registry 建立旁路。Text Lookup 的鼠标/取词快捷键属于扩展私有触发流，不强行接入 Command Registry。
- 保持 `App`、`Commands`、`Builtins`、`Hotkeys`、`Platform`、`Search`、`Settings`、`Plugins/WindowManagement`、`Plugins/TextLookup`、`Plugins/ClipboardHistory`、`Plugins/Screenshot`、`Plugins/Display`、`Plugins/Workspace`、`Plugins/FileSearch`、`Plugins/Quicklinks`、`Plugins/Snippets`、`Plugins/DeveloperTools`、`Plugins/ScriptCommands` 与 `Plugins/Calculator` 的当前语义边界，不增加固定的 Features/Core 层或宽泛 Runtime/Services 目录。`Plugins` 下的目录是内置独立扩展实现，不代表动态插件系统。
- AppKit、Carbon、Accessibility、ServiceManagement 和 NSWorkspace 由具体平台 adapter 隔离；跨功能共享的 adapter 放在 `Platform`，只服务单个内置扩展的实现留在扩展内部。只有真实替换或失败注入需求才增加协议。
- Settings Scene 是完整管理全局偏好的入口；菜单、搜索和命令只打开或执行它定义的能力。只有产品合同明确要求的就地操作可以持久化对应偏好，例如 Text Lookup 悬浮窗中的目标语言快捷调整。

## 并发与恢复

- UI、AppKit 对象、Carbon 注册表和 app-lifetime 可变状态在 Main Actor 更新；纯 SearchEngine/WindowGeometry 值保持 `Sendable`/`nonisolated`。
- 从 C/Objective-C 回调进入 Main Actor 时，隔离必须能被 Swift 6 编译器验证，不用 `@unchecked Sendable` 掩盖竞态。
- 快捷键更新失败时保留或恢复上一组有效注册。目标窗口消失、不可调整或没有可用显示器时返回明确失败。
- Root Search 的性能问题先测量快捷键到可输入、应用扫描、图标读取、搜索和窗口 I/O，再决定是否引入后台或增量处理。

## 安全与分发

- 核心命令中心不上传搜索词、应用列表、窗口信息、快捷键或使用行为；日志不记录搜索词或窗口内容。
- Window Management 只用 Accessibility 定位、移动和缩放目标窗口。Text Lookup 仅在用户启用并触发时读取有限的选区或指针文本、原句与尽力获取的来源；捕获内容只保留在当前会话，除非用户显式创建 FlashDict 闪卡。两项能力在权限缺失时都必须显示真实恢复动作。
- 分发基线为 Developer ID + Hardened Runtime 且 App Sandbox 关闭；改变这一组合时重新验证快捷键、应用扫描、Accessibility、登录项、签名和公证。
- 仓库不得包含签名、公证凭据或用户本机数据。

## Window Management 边界

- 产品行为由 `docs/product/window-management.md` 定义。`WindowManagementPlugin` 拥有启用偏好、运行状态、设置反馈、命令注册和停止自身快捷键的生命周期；AppEnvironment 负责组合、共享权限入口和跨功能快捷键事务。
- 窗口命令、AccessibilityWindowController 和 WindowManagementSettingsView 位于 `Plugins/WindowManagement`；共享窗口读写与 WindowGeometry 位于 `Platform`。AccessibilityAuthorization 与 GlobalHotkeyRegistrar 继续作为共享平台能力。
- 插件生成自己的快捷键注册请求，由 App 统一协调替换；请求回调只交回 CommandID，经 App 的统一执行入口进入 Registry。核心 Shortcuts 继续管理命令快捷键的录制、存储与冲突检查。
- 停止插件不删除启用偏好；用户关闭或权限撤销时才持久化停用。沿用现有命令 ID 和设置 key。

## Text Lookup 边界

- Text Lookup 的当前产品范围与用户行为由 `docs/product/text-lookup.md` 定义；本节只定义其实现 ownership、平台 seam、并发和数据生命周期。
- Text Lookup 是随主 App 静态编译的内置独立扩展，不是 macOS App Extension 或动态插件系统。`TextLookupPlugin` 拥有取词生命周期和当前会话；`TextLookupSessionModel` 拥有悬浮窗口可观察状态。`AppEnvironment` 只负责组合、启停和共享平台能力，不吸收完整取词流程。
- Accessibility 捕获、兼容复制、FlashDict IntegrationKit 和 Apple Translation 是独立平台边界。业务层只消费稳定值和明确结果，不持有 AX、pasteboard、跨进程或 Translation session 对象。
- 每次捕获先建立新的 session/request identity，并取消旧捕获、查词、翻译和建卡任务；成功与失败结果都必须匹配当前 identity 后才能提交。
- Apple `TranslationSession` 保持 View 生命周期绑定；不进入 App 级 service、Settings store 或持久化对象。
- 剪贴板兼容路径只执行一次受控复制，并以 change count 防止恢复操作覆盖用户后续修改。
- 捕获文本、原句、来源 URL、释义和翻译不持久化，也不进入普通日志。停用功能或关闭会话时释放相关内存状态。
- NSPanel 定位以锚点、鼠标位置和当前屏幕可用区域为输入；全屏、Space、多显示器和不同应用兼容性属于真实系统验证边界。

## Clipboard History 边界

- 产品行为由 `docs/product/clipboard-history.md` 定义；插件拥有采集任务、历史数据库、面板和设置状态，由 AppEnvironment 组合并注册命令。
- 仅在显式启用后记录后续复制。SwiftData 使用独立本地容器并关闭 CloudKit；数据库操作保持 Main Actor 串行，图片预览解码离开 Main Actor，取消或选择变化后不提交旧预览。
- Text Lookup 的临时复制通过共享 ClipboardAccessCoordinator 排除；插件自身回写以 changeCount 排除。停止、删除和清空取消待处理粘贴。
- 直接粘贴在激活和发送按键前检查原目标应用；剪贴板访问授权与 Accessibility 粘贴权限独立处理。

## Screenshot 边界

- 产品行为与图床范围由 `docs/product/screenshot.md` 定义。ScreenshotPlugin 拥有截图、编辑会话和上传任务，AppEnvironment 只组合与协调命令快捷键。
- 使用支持 macOS 15 的 ScreenCaptureKit 单帧接口；区域和窗口选择、屏幕坐标转换留在插件内。普通截图不依赖 Accessibility。
- 编辑器只在会话内保存原图和标注，导出必须合成裁剪及遮挡结果。编码、签名和网络工作离开 Main Actor，UI 和 AppKit 状态保持 Main Actor。
- 上传是用户配置并触发的独立网络边界；平台协议、Keychain、URLSession 留在插件内，不建立通用上传 Runtime。重试保留同一导出快照，停止后拒绝旧任务的成功、错误及进度结果。
- 普通配置只保存服务参数；凭据只进入本机 Keychain。上传结果的自动剪贴板回写必须检查 changeCount，所有自身回写通知现有协调对象。

- OCR 使用 Apple Vision 处理截图最终合成像素，贴图保存独立合成快照；两者不读取未合成的裁剪外或遮挡前内容，不自行上传。所有图片／文字回写通过已有剪贴板协调器登记。

## Display 边界

- 产品行为由 `docs/product/display.md` 定义。插件拥有显示器枚举、切换确认、预设及原生 HiDPI 配置；App 只组合命令、设置和快捷键。
- CoreGraphics 屏幕配置与特权文件写入是独立副作用边界。模式切换前完整校验；试用与确认分离，恢复错误不得吞掉。
- 显示器配置只针对明确选择的厂商/型号，禁止覆盖其它工具配置。安装与移除由用户触发系统管理员授权；不建立常驻特权服务。

## Workspace 边界

- 产品行为由 `docs/product/workspace.md` 定义。插件拥有本地布局、捕获选择和恢复任务；AppEnvironment 组合命令与共享快捷键。
- Workspace 和 Window Management 共享平台窗口读写，不互相依赖启停。AX 对象保持 Main Actor 隔离；布局规则保持值语义。
- 工作区 UUID 稳定标识命令，删除同时注销和删除快捷键；停止任务后不提交旧结果。

## Calculator 边界

- Calculator 的当前产品范围与数值语义由 `docs/product/calculator.md` 定义；`CalculatorPlugin` 拥有窗口和会话内计算状态，`AppEnvironment` 只负责组合并把打开入口注册到核心 Command Registry。
- 运算引擎保持无 UI、AppKit 或持久化依赖的值语义；窗口与可观察状态保持 Main Actor 隔离。
- Calculator 不增加后台生命周期、权限、网络、动态插件 Runtime 或公共 SDK。只有出现真实的新数值需求时才扩展运算类型和表示范围。

## Quicklinks 与 Snippets 边界

- 产品行为分别由 `docs/product/quicklinks.md` 与 `docs/product/snippets.md` 定义。插件拥有条目、独立 JSON 存储、临时面板与命令；AppEnvironment 只组合设置、Registry 和快捷键。两者不建立通用模板框架或持久化框架。
- QuicklinkTemplate 与 SnippetTemplate 保持纯值语义。前者约束 URL 占位符位置并编码参数，后者只做一次模板展开；系统打开、剪贴板读取和写入留在对应副作用边界。
- ClipboardPasteController 与 ClipboardContentPolicy 位于 Platform，由 Clipboard History 和 Snippets 共同使用。平台层不依赖插件错误或面板类型；粘贴任务归各插件所有，取消与停用后不提交旧结果。

## File Search 边界

- 产品行为由 `docs/product/file-search.md` 定义。FileSearchPlugin 拥有范围设置、面板、扫描／查询任务和 FSEvents 生命周期；AppEnvironment 组合 Registry 与共享快捷键。
- FileIndexStore actor 隔离 SQLite，FileIndexScanner actor 隔离目录访问。查询解析和排序规则使用值类型；扫描分批写入、查询逐条检查取消，UI 不遍历目录或执行数据库查询。
- FSEvents 使用主队列回调并显式管理 C context 生命周期；停用先停止监听再取消任务。事件只是重新核对目录的依据，只有对应更新成功才推进事件位置。扫描失败不清理未读范围。
- 文件操作及 Quick Look 留在插件内。剪贴板写入复用 ClipboardAccessCoordinator，不为此扩展通用文件操作框架。

## Developer Tools 边界

- 产品行为由 `docs/product/developer-tools.md` 定义。DeveloperToolsPlugin 拥有普通窗口和会话，AppEnvironment 组合 Registry 与共享快捷键；各工具不互相依赖。
- 文本转换使用纯值算法，DeveloperTextSession 拥有后台计算任务；修改输入、操作或关闭窗口时取消，取消后的成功与错误均不得回写。UI、AppKit 编辑器及剪贴板保持 Main Actor 隔离。
- JSON 以显式解析状态验证语法并原样保留 token，不递归消耗线程栈或把数值转换成浮点。时间戳在数值解析和单位转换时使用整数毫秒，仅在系统日期边界转换为 Date。
- 原生文本编辑器关闭系统自动替换，窗口关闭时释放编辑器及其撤销记录。结果复制复用 ClipboardAccessCoordinator，文本不持久化。

## 验证边界

- Command Registry、SearchEngine、WindowGeometry、Hotkey 配置、Calculator 运算语义以及 Text Lookup 的纯文本、会话和生命周期规则使用 Swift Testing 保护。
- Carbon 快捷键、NSPanel 焦点/Space、Accessibility、登录项、外接显示器、真实应用启动和 Text Lookup 应用兼容性以构建、运行和人工矩阵验证。
- Text Lookup 的系统兼容、翻译模型、FlashDict 跨进程与真实建卡按需使用 `docs/release-readiness.md`。
- 文档专属改动只做引用、重复、冲突和 diff 检查，不要求构建。

## Script Commands 边界

- 产品行为由 `docs/product/script-commands.md` 定义。插件拥有脚本配置、运行任务和结果窗口；App 负责 Registry、快捷键事务和退出时等待任务清理。
- `ScriptRunner` 是进程副作用边界：argv 不拼接，标准输入关闭交互，双路输出有界且持续排空，工作线程负责启动、进程组终止和回收。Main Actor 只消费输出快照与结果。
