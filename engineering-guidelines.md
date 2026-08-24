# zbox 工程规范

## Command 与平台边界

- Command 是搜索入口和直接快捷键共享的稳定业务接口；新增可执行能力不得绕过 Registry 建立旁路。
- 保持 `App`、`Commands`、`Builtins`、`Hotkeys`、`Platform`、`Search`、`Settings` 的当前语义边界，不增加固定的 Features/Core 层或宽泛 Runtime/Services 目录。
- AppKit、Carbon、Accessibility、ServiceManagement 和 NSWorkspace 由具体平台 adapter 隔离；只有真实替换或失败注入需求才增加协议。
- Settings Scene 是全局偏好的唯一写入入口；菜单、搜索和命令只打开或执行它定义的能力。

## 并发与恢复

- UI、AppKit 对象、Carbon 注册表和 app-lifetime 可变状态在 Main Actor 更新；纯 SearchEngine/WindowGeometry 值保持 `Sendable`/`nonisolated`。
- 从 C/Objective-C 回调进入 Main Actor 时，隔离必须能被 Swift 6 编译器验证，不用 `@unchecked Sendable` 掩盖竞态。
- 快捷键更新失败时保留或恢复上一组有效注册。目标窗口消失、不可调整或没有可用显示器时返回明确失败。
- Root Search 的性能问题先测量快捷键到可输入、应用扫描、图标读取、搜索和窗口 I/O，再决定是否引入后台或增量处理。

## 安全与分发

- M1 不上传搜索词、应用列表、窗口信息、快捷键或使用行为；日志不记录搜索词或窗口内容。
- Accessibility 只用于用户启用的窗口定位/移动/缩放和 Text Lookup 选中文本捕获；权限缺失必须显示真实恢复动作，不得借此采集无关窗口或文本内容。
- 分发基线为 Developer ID + Hardened Runtime 且 App Sandbox 关闭；改变这一组合时重新验证快捷键、应用扫描、Accessibility、登录项、签名和公证。
- 仓库不得包含签名、公证凭据或用户本机数据。

## Text Lookup 边界

- `TextLookupPlugin` 拥有取词生命周期和当前会话；`TextLookupSessionModel` 拥有悬浮窗口可观察状态。`AppEnvironment` 只负责组合、启停和共享平台能力，不吸收完整取词流程。
- Accessibility 捕获、兼容复制、FlashDict IntegrationKit 和 Apple Translation 是独立平台边界。业务层只消费稳定值和明确结果，不持有 AX、pasteboard、跨进程或 Translation session 对象。
- 每次捕获先建立新的 session/request identity，并取消旧捕获、查词、翻译和建卡任务；成功与失败结果都必须匹配当前 identity 后才能提交。
- Apple `TranslationSession` 保持 View 生命周期绑定；不进入 App 级 service、Settings store 或持久化对象。
- 剪贴板兼容路径只执行一次受控复制，并以 change count 防止恢复操作覆盖用户后续修改。
- 捕获文本、原句、来源 URL、释义和翻译不持久化，也不进入普通日志。停用功能或关闭会话时释放相关内存状态。
- NSPanel 定位以锚点、鼠标位置和当前屏幕可用区域为输入；全屏、Space、多显示器和不同应用兼容性属于真实系统验证边界。

## 验证边界

- Command Registry、SearchEngine、WindowGeometry 和 Hotkey 配置使用 Swift Testing 保护纯规则。
- Carbon 快捷键、NSPanel 焦点/Space、Accessibility、登录项、外接显示器和真实应用启动以构建、运行和人工矩阵验证。
- Text Lookup 的系统兼容、翻译模型、FlashDict 跨进程与真实建卡按需使用 `docs/release-readiness.md`。
- 文档专属改动只做引用、重复、冲突和 diff 检查，不要求构建。
