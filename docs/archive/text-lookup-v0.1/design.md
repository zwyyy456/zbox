# zbox 鼠标取词插件设计方案 v0.1

> 归档：长期工程边界已合并到 `../../../engineering-guidelines.md`。

> 状态：Archived（首版工程基线快照）
> 日期：2026-08-14
> 输入约束：《zbox 鼠标取词插件需求文档 v0.1》
> 文档职责：定义 Text Lookup Plugin v0.1 的模块边界、状态所有权、平台 adapter、接口、并发、窗口、接入与验证方案。

## 1. 设计目标

本方案需要在不建设动态插件 Runtime 的前提下，把鼠标取词作为静态第一方模块接入 zbox，并集中隐藏以下复杂度：

- 全局鼠标事件和双击修饰键手势；
- Accessibility 选区、指针范围、原句、来源与窗口坐标读取；
- 可选剪贴板兼容取词；
- 不抢焦点的悬浮 `NSPanel` 生命周期和多屏定位；
- FlashDict 跨进程查词、资源渲染和建卡；
- macOS 15 Apple Translation 的 SwiftUI view-bound session 生命周期；
- 新会话取消旧任务、旧结果不得覆盖新 UI；
- 功能设置、应用排除和隐私边界。

宿主 `AppEnvironment` 不应知道 AX 属性名、鼠标候选有效期、FlashDict request ID、TranslationSession、WebView 资源路由或剪贴板恢复规则。

## 2. 现有约束

### 2.1 zbox 基线

- macOS 15+、Swift 6 language mode、默认 MainActor 隔离；
- 单 App target、App Sandbox 关闭、Hardened Runtime 开启；
- 后台常驻、无 Dock 图标；
- 已有 `GlobalHotkeyRegistrar`、`SearchPanelController`、Settings scene 和 Accessibility 权限入口；
- 当前快捷键配置是固定预设，Carbon registrar 只处理普通组合键；
- 当前 `AppEnvironment` 已负责 Root Search、应用命令、窗口命令、快捷键和设置编排，不应继续吸收完整取词功能。

### 2.2 FlashDict 合同

- 调用方只能通过 `FlashDictIntegrationKit` 查词和建卡；
- `lookup(term:requestID:)` 返回主词典的 `LookupDocument`；
- `FlashDictLookupSurface` 负责词典 HTML、资源、音频和义项交互；
- `SenseSelection.cardSeed` 是冻结的建卡输入；
- `FlashcardCreationContext` 支持 `sentence`、`sourceURL` 和 `userNote`；
- FlashDict 必须运行；客户端不自动启动、轮询或自动重连；
- 两个 App 必须使用同一个正式 App Group。

### 2.3 Apple Translation 合同

- macOS 15 的 Translation API 可通过 SwiftUI `.translationTask` 提供 session；
- session 与承载它的 View 生命周期绑定，不应长期保存在全局 model 或功能根对象；
- 首次使用未安装语言时可能出现系统下载授权 UI；
- TranslationSession 取消是协作式行为，UI 仍必须以查词会话身份阻止旧结果提交。

### 2.4 Accessibility 能力边界

- 系统提供选中文字、选区范围、按位置命中文本元素、位置到文字范围、范围到字符串和范围到屏幕矩形等能力；
- 目标应用可以不实现某些属性、返回无值、超时或无法完成；
- 非编辑 Web 文本、PDF、Electron、自绘文本和终端的支持度必须通过真实应用矩阵确认；
- 设计必须允许“有单词无原句”“有选区无坐标”“完全不可读”等部分成功和失败状态。

## 3. 方案比较

### 3.1 方案 A：继续把功能加入 AppEnvironment

形状：

```text
AppEnvironment
  + mouse monitor
  + AX capture
  + lookup state
  + translation state
  + panel state
  + FlashDict client
```

优点：文件和装配最少。

缺点：

- `AppEnvironment` 同时承担 Root Search、窗口管理和取词三套生命周期；
- 取词停用无法形成清晰的资源释放边界；
- Settings、窗口和异步状态继续集中到单一 owner；
- 测试需要穿过完整应用环境，locality 和测试表面都变差。

### 3.2 方案 B：静态第一方功能模块

形状：

```text
AppEnvironment
└── TextLookupPlugin
```

优点：

- 宿主只负责功能启停，接口小于隐藏的行为，模块具有足够 depth；
- 插件内部集中管理监听、任务、窗口和配置，停用时可以完整清理；
- 系统边界、FlashDict 和翻译 adapter 都有真实替换需求，测试 seam 清晰；
- 不需要动态加载、跨进程插件 RPC 或公共 SDK。

代价：需要调整当前快捷键与 Accessibility 权限共享方式。

### 3.3 推荐

采用方案 B。它是静态原生模块，不改变单进程、单 App target 基线，也不把首版内部接口声明为未来公共插件 API。

在线词典不在首版创建统一 `DictionaryLookupProvider`。FlashDict 的输出包含专用 HTML、资源代理和义项 seed，而未来在线 API 的真实数据形状尚未确定；此时强行统一会产生浅层 adapter 和错误公共模型。首版直接使用已有的 `FlashDictLookupProviding` seam，等第一个合法在线来源确定后再比较真实接口。

## 4. 推荐模块形状

```text
ZBoxApp / AppEnvironment
├── Existing Root Search and Commands
└── TextLookupPlugin (@MainActor)
        ├── TextLookupSettingsStore
        ├── TextLookupTriggerMonitor
        │   ├── GlobalHotkeyRegistrar registration
        │   └── Global pointer/modifier event monitor
        ├── TextCaptureCoordinator
        │   ├── AccessibilityTextCapturer
        │   ├── SentenceSegmenter
        │   └── ClipboardSelectionFallback
        ├── TextLookupSessionModel (@MainActor, @Observable)
        ├── TextLookupPanelController
        │   └── TextLookupPanelView
        ├── FlashDictBridgeClient actor
        └── AppleTranslationViewAdapter
```

建议目录随实现一次性形成：

```text
zbox/
├── Plugins/
│   └── TextLookup/
│       ├── TextLookupPlugin.swift
│       ├── Capture/
│       ├── Triggers/
│       ├── Lookup/
│       ├── Translation/
│       ├── Panel/
│       └── Settings/
└── Platform/
    ├── AccessibilityAuthorization.swift
    └── GlobalHotkeyRegistrar.swift
```

`Platform` 只保留确实被多个功能共享的系统 adapter。插件业务状态、选区候选和窗口内容不得放进 `Platform`。

## 5. 模块接口

### 5.1 AppEnvironment 接入

调用者：`AppEnvironment`。

调用者需要完成的工作：随 App 生命周期启动已启用插件、在设置变化时启停插件、退出时停止插件。

调用者不需要知道：插件监听了哪些事件、创建了哪些任务、显示什么窗口或使用什么外部服务。

首版只有 Text Lookup 一个静态第一方功能，`AppEnvironment` 根据持久化的 enabled 状态直接调用：

```swift
textLookupPlugin.start()
textLookupPlugin.stop()
```

约束：

- `start()` 和 `stop()` 必须幂等；
- 启动后的权限或运行错误属于插件状态，不通过生命周期接口暴露复杂错误枚举；
- `stop()` 同步完成监听注销、窗口关闭和任务取消请求；
- 首版不加入通用 plugin protocol/host、动态 bundle、版本协商、权限 manifest 或 settings view type erasure；出现第二个真实模块且生命周期编排确有重复时再评估共用接口。

### 5.2 TextLookupPlugin

Recommended shape：一个 `@MainActor` 深模块，拥有整个取词功能的生命周期和装配。

Public interface：只实现 `start()`、`stop()`，并向具体 Settings view 提供只读状态与用户 intent 方法。

Hidden implementation details：事件监听、候选状态机、Accessibility 查询、剪贴板恢复、查词 request ID、翻译配置、panel controller 和取消任务。

Seam：只在真实变化边界使用协议——文本捕获与 FlashDict 查词/建卡；内部纯函数和未实现的未来 provider 不包装协议。

Testing approach：从插件 intent 和 session model 投影进入，系统 adapter 使用 fake；不直接测试私有 AX 调用顺序。

Trade-offs：插件装配比直接塞入 AppEnvironment 多一层，但删除该模块会把完整跨应用取词复杂度重新散回宿主，模块有实际 leverage。

### 5.3 捕获数据模型

```swift
nonisolated struct TextLookupCapture: Sendable, Equatable {
    let id: UUID
    let term: String
    let sentence: String?
    let sourceURL: URL?
    let anchorRect: CGRect?
    let sourceApplicationBundleIdentifier: String?
}
```

说明：

- `id` 是查词会话身份，不是持久化业务 ID；
- `term` 是清洗后的查询文本；
- `sentence` 保留用户看到的原始文本，不做翻译前改写；
- `anchorRect` 使用 macOS 全局屏幕坐标；无法取得时 panel 使用触发时鼠标位置；
- 不把 AXUIElement、PID、选区 range 或剪贴板对象带入 UI 和 FlashDict 边界。

### 5.4 文本捕获 seam

```swift
nonisolated enum TextCaptureIntent: Sendable {
    case currentSelection
    case pointerLocation(CGPoint)
}

nonisolated struct TextCaptureRequest: Sendable {
    let id: UUID
    let intent: TextCaptureIntent
}

protocol TextCapturing: Sendable {
    func capture(_ request: TextCaptureRequest) async throws -> TextLookupCapture
}
```

request ID 必须在开始异步 Accessibility 调用之前由 coordinator 创建。生产 adapter 原样把该 ID 放入返回的 capture；coordinator 只接受仍匹配当前 capture attempt 的结果。该 seam 是真实平台边界：生产 adapter 访问其它进程 Accessibility，测试 adapter 返回确定性 capture。

错误至少区分：

- permission required；
- excluded application；
- secure text；
- no selection；
- no text at pointer；
- unsupported element；
- selection too long；
- unable to read text；
- clipboard fallback failed。

UI 文案按“用户可修复、权限、目标应用不支持、暂时系统失败”映射，不直接显示 AXError 数值。

### 5.5 Apple Translation 请求与结果

会话模型与 view-bound Apple Translation adapter 之间使用以下值类型：

```swift
nonisolated struct TranslationRequest: Sendable, Equatable {
    let id: UUID
    let text: String
    let sourceLanguage: Locale.Language?
    let targetLanguage: Locale.Language
}

nonisolated struct TranslationResult: Sendable, Equatable {
    let requestID: UUID
    let sourceLanguage: Locale.Language
    let targetLanguage: Locale.Language
    let translatedText: String
}

```

Apple Translation 不能在 macOS 15 上被简单建成全局长生命周期 service。`AppleTranslationViewAdapter` 由 `TextLookupPanelView` 的 `.translationTask` 获得 session，消费 session model 中当前请求，并把带 request ID 的结果回传。`TranslationSession` 不进入 `TextLookupPlugin`、Settings store 或持久化对象。

首版不定义第三方翻译 protocol、配置 DTO 或 Keychain seam。第一个真实 provider 进入已排期闭环后，再基于其鉴权、请求响应、取消、错误与隐私要求设计；不为未知 vendor 预留通用接口。

## 6. 触发与候选状态机

### 6.1 输入来源

插件需要两类系统输入：

1. 普通组合键由现有 Carbon `GlobalHotkeyRegistrar` 注册，以便系统级触发并避免同时传给目标应用；
2. 鼠标抬起和双击修饰键由只监听的全局事件 monitor 观察，回调必须立即返回，不在回调中执行 AX IPC 或查词。

`GlobalHotkeyRegistrar` 需要从“只能全部注销”扩展为按 registration ID 或 token 注销。Text Lookup 停用不得影响 Root Search 和窗口命令快捷键。

双击修饰键只在以下条件同时成立时触发：

- 两次都是同一个支持的修饰键；
- 每次均完成按下和释放；
- 两次之间没有普通键或其它修饰键参与；
- 间隔不超过系统双击时间或插件定义的可测试阈值；
- 事件不是 zbox 自己面板交互产生的递归输入。

首版不支持单修饰键触发。

### 6.2 状态

```text
inactive
  └── start → observing

observing
  ├── valid mouse selection → candidateReady
  ├── shortcut without candidate → capturingPointer
  └── stop → inactive

candidateReady
  ├── automatic mode → capturingSelection
  ├── shortcut before expiry → capturingSelection
  ├── new selection → candidateReady(new)
  ├── expiry/app change → observing
  └── stop → inactive

capturingSelection / capturingPointer
  ├── success → presenting(sessionID)
  ├── failure → feedback or presenting(error)
  └── newer trigger → cancelled
```

### 6.3 划词候选生成

- 在 mouse-up 后做短暂 debounce，让目标应用先提交 Accessibility 选区；初始实现可从约 100–150 ms 验证起步，但该值是需要真实应用测量的实现参数，不是产品合同；
- 只记录触发时鼠标位置、前台应用身份和候选时间，不长期持有 AXUIElement；
- 自动模式直接进入选择捕获；快捷键模式保留约 3 秒；Off 模式不生成候选；
- 新的鼠标动作、前台应用变化或插件停用清除候选。

## 7. Accessibility 捕获方案

### 7.1 划词路径

按以下顺序尝试：

1. 记录前台目标应用，拒绝 zbox、FlashDict、排除应用和安全文本；
2. 获取 focused UI element；
3. 读取 selected text 和 selected text range；
4. 校验清洗后的 term 以及 80 字符/8 词限制；
5. 使用 bounds-for-range 获取锚点；
6. 从范围附近文本提取包含目标范围的原句；
7. 尽力读取来源 URL；
8. 若 AX 选区不可读且用户启用兼容模式，进入剪贴板 fallback。

### 7.2 指针路径

按以下顺序尝试：

1. 使用全局鼠标坐标命中 Accessibility element；
2. 拒绝安全、排除或非文本元素；
3. 使用 range-for-position 取得字符范围；
4. 读取有限上下文并通过 `NLTokenizer(unit: .word)` 确定鼠标所在词；
5. 使用已知字符范围和 `NLTokenizer(unit: .sentence)` 提取原句；
6. 使用 bounds-for-range 取得词的锚点；
7. 尽力读取来源 URL。

若目标只暴露选区而不支持 range-for-position，指针取词明确失败，不通过模拟点击或改写目标选区补救。

### 7.3 上下文与字符串索引

- AX 的 CFRange 使用字符范围语义，Foundation 处理时以 UTF-16/NSString 边界转换，避免直接把整数偏移当作 Swift `String.Index`；
- 优先读取当前可见或目标范围附近的有限文本，不为一句话无上限读取整篇网页或文档；
- 句子提取必须保留目标范围映射，不能只在字符串中搜索第一次出现的相同单词；
- `NLTokenizer` 结果为空时原句为 nil，不使用句号字符串切割作为隐式 fallback；
- term 清洗和句子分割是纯函数，独立测试多语言、emoji、组合字符、缩写和标点。

### 7.4 AX 调用执行边界

跨进程 Accessibility IPC 不放在主线程事件回调中。生产捕获 adapter 使用受控的非 MainActor 执行边界并设置合理消息超时；完成后返回 Sendable 值，再由 `@MainActor` session model 更新 UI。

不使用无所有者 `Task.detached`。若底层同步 AX 调用需要专用串行执行上下文，应把队列封装在 capturer 内并通过 checked continuation 恢复，保证每条路径恰好恢复一次，且取消后结果不会提交给已过期会话。

## 8. 剪贴板兼容取词

兼容取词是独立 adapter，不混入普通 AX 成功路径。

执行条件：

- 用户已明确启用；
- 当前存在非空选区候选；
- 应用未排除且元素不是安全文本；
- AX 无法读取 selected text；
- 本次不是指针取词。

建议流程：

1. 记录当前 pasteboard change count；
2. 尽力快照现有 pasteboard items 和类型；
3. 模拟一次 Copy；
4. 在有上限的短等待内观察 pasteboard 是否产生新文本；
5. 读取选区文本；
6. 只有 pasteboard 仍处于本次兼容操作产生的 change count 时才恢复快照；
7. 用户或其它应用在此期间更新剪贴板时放弃恢复，避免覆盖新内容。

兼容路径最多执行一次，不自动重试，不用于获取指针下的词。恢复是 best effort，Settings 必须明确说明它会暂时使用系统剪贴板。

## 9. 会话状态与并发

### 9.1 状态所有权

`TextLookupSessionModel` 是唯一 UI 会话状态 owner，使用 `@MainActor @Observable`。它拥有：

- 当前 capture/session ID；
- 捕获状态；
- 当前 term、sentence、source URL 和 anchor；
- FlashDict lookup 状态与 LookupDocument；
- Apple 翻译请求、结果和错误；
- 义项 selection states；
- 用户可操作错误；
- 当前目标语言。

View 只渲染状态并发送 intent。Panel controller 只管理 AppKit 窗口，不拥有业务结果。FlashDict client 和 capture adapter 不直接回写 View。

### 9.2 会话更新规则

```swift
@MainActor
func beginLookup(with capture: TextLookupCapture) {
    activeSessionID = capture.id
    lookupTask?.cancel()
    // Reset old definition, translation, and selection state.
    // Start new work and gate every completion by capture.id.
}
```

硬规则：

- 新触发先取消旧 capture task、lookup task 和当前翻译请求；
- `CancellationError` 是正常生命周期事件，不映射为错误 banner；
- 每个 async completion 在提交 UI 前比较 session/request ID；
- FlashDict 释义与 Apple 翻译独立运行、独立完成；
- 翻译目标语言变化只替换 translation request ID，不改变 lookup session ID 或重新查词；
- SwiftUI `.translationTask` 随 panel content 生命周期取消；仍需 request ID gate 防止晚到结果；
- stop 时取消并清空所有任务和状态。

### 9.3 建卡任务

- 建卡由用户明确点击产生，按 selection ID 保存 `.adding` 状态；
- 每次点击生成新的 delivery ID；
- 同一次错误不自动重试；
- panel 被新查词替换后，旧 selection state 不得显示在新文档；
- 插件停止或 App 退出时允许取消未送达请求；FlashDict 已按 delivery ID 接收的请求由服务端幂等合同保证不重复。

## 10. 悬浮窗口设计

### 10.1 窗口所有权

新建独立 `TextLookupPanelController`，不复用 `SearchPanelController`。两者的焦点合同不同：Root Search 必须主动获得输入焦点；Text Lookup 出现时必须保持目标应用和原选区。

建议 AppKit 行为：

- 使用单一 `NSPanel` 承载 SwiftUI；
- `level = .floating`；
- `collectionBehavior` 支持当前 Space 和全屏辅助窗口；
- show 时不调用 `NSApp.activate`、不 `makeKeyAndOrderFront`；
- 点击 panel 后允许 WebView、语言菜单和按钮交互；
- 全局外部点击、Escape、新会话、插件停用时 order out；
- 不因初始 `windowDidResignKey` 立即隐藏，因为 panel 首次出现时本来就不应成为 key window。

Panel 未成为 key window 时不能依赖 `sendEvent` 接收 Escape。显示期间应临时注册可消费的 Escape 快捷键或使用经验证的等价事件过滤方案，关闭时立即注销，且不得影响 panel 隐藏后的目标应用 Escape 行为。

具体 style mask、激活策略和临时 Escape 注册先通过一个最小可运行 probe 验证，最终行为以“不抢焦点、点击后可交互、Escape 只在窗口显示期间关闭窗口、全屏可见”为完成证据。

### 10.2 布局合同

- Panel 是唯一外层尺寸和屏幕边界 owner；View 不自行计算全局位置；
- 建议首版宽度约 520 pt，并在窄屏时限制为可用宽度减去 24 pt；
- 高度按内容增长但设置屏幕相关上限，主词典区域获得剩余空间；
- 顶部 term、原句和翻译共享统一水平内容边界；
- 原句和翻译允许换行，不用固定宽度或单行截断；
- FlashDict `WKWebView` 负责释义区域滚动，外层不再包围一个竞争手势的全窗口 ScrollView；
- 长原句区域设置合理最大高度并提供可访问展开或局部滚动，不能挤掉全部释义；
- 目标语言按钮保持稳定宽度，文本内容承担弹性；
- loading、empty、error、added 和 rejectedQuota 都占用稳定布局位置，避免结果到达时窗口大幅跳动。

### 10.3 定位

定位输入为 anchor rect、触发时鼠标位置和当前屏幕 visible frame，输出为 panel origin。计算独立成纯函数。

顺序：

1. 优先显示在 anchor 下方并保留间距；
2. 下方空间不足时显示在上方；
3. 水平方向以 anchor 中心或鼠标 x 对齐，再夹紧到 visible frame；
4. 多显示器使用包含 anchor/鼠标的屏幕；
5. 无 anchor 时使用触发时鼠标位置，不使用 panel 显示后的实时鼠标位置。

## 11. FlashDict 接入

### 11.1 工程配置

- 给 zbox 添加本地 Swift Package 依赖 `../zdict/Packages/FlashDictIntegrationKit`；
- 添加 `FlashDictIntegrationAppGroupIdentifier = group.tech.hyperseek.flashdict.integration`；
- 为 zbox 配置与 FlashDict 相同的 App Group entitlement；
- 两个 App 使用兼容签名团队进行真实验证；
- App Sandbox 关闭不取消 App Group entitlement 和签名要求。

### 11.2 查词

```text
capture.term
  → UUID requestID
  → FlashDictBridgeClient.lookup
  → verify current session/request
  → LookupDocument
  → FlashDictLookupSurface
```

错误映射：

- `.flashDictNotRunning` → 说明 + 启动按钮；
- `.primaryDictionaryUnavailable` → 提示用户在 FlashDict 配置主词典；
- `.noResult` → 主词典无结果；
- `.incompatibleProtocol` → 提示 zbox/FlashDict 版本不兼容；
- `.requestFailed` → 可重试但不自动重试的失败状态。

运行期间资源请求失败由 LookupSurface event 映射为 FlashDict 已退出或资源不可用，不重建整条查词会话。

### 11.3 建卡

```text
LookupSurfaceEvent.senseSelected(selection)
  → selection state = adding
  → client.createFlashcard(
        deliveryID: new UUID,
        seed: selection.cardSeed,
        context: sentence + sourceURL + nil userNote
    )
  → added / rejectedQuota / failed
```

不得从 term 和 sense index 重新查词构造卡片，也不得把原句翻译写入 userNote。

## 12. Apple Translation 接入

### 12.1 View-bound adapter

`TextLookupPanelView` 持有由 session model 投影出的 `TranslationSession.Configuration?`，并附加 `.translationTask(configuration)`。闭包内：

1. 捕获当前 translation request value；
2. 必要时调用 `prepareTranslation()` 触发系统语言下载授权；
3. 调用 `session.translate(sentence)`；
4. 将带 request ID 的结果发送回 session model；
5. 过滤 CancellationError；
6. session model 只接受仍匹配的 request ID。

不把 `TranslationSession` 存进 AppEnvironment、TextLookupPlugin 或长期 observable state。

### 12.2 语言选择

- source 初始为 nil，由系统自动识别；
- target 从 Settings 读取；没有固定配置时从 macOS preferred languages 解析；
- 使用 LanguageAvailability 判断支持状态；
- target 按钮使用语言名称而不是内部 language code；
- 改变目标语言更新 Settings 并使 configuration invalidate，只重跑翻译；
- 源目标相同、无法识别或 pairing 不支持时显示对应状态，不向网络服务降级。

### 12.3 第三方翻译

首版不展示、持久化或读取第三方翻译配置，也不创建凭据。未来实现具体 provider 时，必须从可执行的翻译闭环出发同时交付配置、鉴权、请求、错误反馈和真实网络验证。

## 13. 设置与持久化

### 13.1 UserDefaults

建议 key 使用 `plugin.text-lookup.*` 前缀，保存：

- enabled；
- selection trigger mode；
- shortcut preset；
- clipboard fallback enabled；
- target language identifier；
- excluded application bundle identifiers；

不使用 SwiftData。取词候选、当前 capture、窗口位置、释义、翻译和 selection states 不持久化。

### 13.2 Settings UI

在现有 Settings 中增加独立 `Text Lookup` section 或 tab，包含：

- 总开关；
- 划词模式 Picker；
- 快捷键 Picker；
- 兼容取词 Toggle 和行为说明；
- 目标语言 Picker；
- 排除应用管理；
- Accessibility 权限状态与操作；

插件关闭时保留设置，但禁用依赖插件运行的子控件。权限状态不是持久化真源，每次显示或执行前读取系统状态。

## 14. 权限、安全与隐私

- 复用一个窄的 `AccessibilityAuthorization` platform adapter，窗口管理与 Text Lookup 不各自复制授权逻辑；
- 永远不读取 secure text field；
- 不请求 Screen Recording；
- 兼容取词只在用户明确开启后模拟 Copy；
- 不把捕获文本、原句、URL、词典 HTML 或翻译内容写入 Release 普通日志；
- 日志可记录 session/request ID、来源 bundle ID、阶段、耗时和错误分类；
- FlashDict HTML 和资源继续遵守 IntegrationKit 的现有信任与资源路由边界，zbox 不额外重写或 sanitize；
- 插件停用后不保留当前取词内存状态。

## 15. 错误模型

面向 session model 的错误按用户动作归类：

```text
TextCaptureFailure
├── permissionRequired       → Request / Open Settings
├── excludedApplication     → Explain exclusion / Open Settings
├── secureText              → Non-actionable protected content
├── noTextAtPointer          → Move pointer over text
├── selectionTooLong        → Select a shorter word or phrase
├── unsupportedElement      → Target app does not expose text
└── clipboardFallbackFailed → Copy manually or disable compatibility mode

DefinitionFailure
├── flashDictNotRunning      → Start FlashDict
├── primaryUnavailable      → Configure primary dictionary
├── noResult                → No result
├── incompatibleProtocol    → Update paired apps
└── requestFailed           → Explicit Retry

TranslationFailure
├── sentenceUnavailable
├── unableToIdentifyLanguage
├── unsupportedLanguagePair
├── modelDownloadCancelled
└── internalFailure         → Explicit Retry
```

取消不属于 Failure，不显示错误。每个 section 独立持有错误；释义失败不能覆盖成功翻译，翻译失败不能移除成功释义。

## 16. 测试设计

### 16.1 纯单元测试

- term 清洗、空白/标点和短语保真；
- 80 字符、8 词边界；
- UTF-16 AXRange 到 Swift String range 转换；
- `NLTokenizer` 单词和句子定位；
- 候选状态机、3 秒有效期和应用变化；
- 双击修饰键的按下/释放、间隔和干扰键；
- session/request ID gate；
- panel 定位、屏幕夹紧和上下翻转；
- Settings 默认值、持久化和快捷键冲突；
- 错误到用户状态的映射。

### 16.2 使用 fake 的模块测试

- fake TextCapturing 驱动成功、部分成功和失败；
- fake FlashDictLookupProviding 验证取消和旧结果隔离；
- fake FlashDictCardCreating 验证 delivery ID 与原句/source URL；
- fake translation completion 验证目标语言变化只重跑翻译；
- fake clipboard adapter 验证 change count 竞争时不覆盖用户新内容；
- 插件 start/stop 验证所有 registration token、任务和 panel 清理。

### 16.3 Package 与构建验证

- zbox macOS build；
- zbox unit tests；
- `FlashDictIntegrationKit` package tests；
- App Group Info/entitlement 静态检查；
- 不默认运行 UI test，除非本次明确进入 UI 验收阶段。

### 16.4 真实系统验证

按需求文档的应用矩阵逐项记录：

- selection text；
- range-for-position；
- sentence context；
- bounds-for-range；
- source URL；
- clipboard fallback；
- panel focus and placement。

必须额外验证真实签名 App Group、FlashDict 正在运行和退出后的跨进程 WebView 资源与音频行为。Apple Translation 不在模拟器验证。

## 17. 实现切片

### Slice 0：系统能力探针

- 用最小代码验证应用矩阵中的 AX selection/range/position/bounds；
- 验证不抢焦点但可点击交互的 NSPanel；
- 验证 panel 显示期间 Escape 可关闭且不会传给目标应用，隐藏后恢复目标应用正常 Escape 行为；
- 验证 macOS 15 `.translationTask` 下载和取消生命周期；
- 验证 zbox 与 FlashDict 真实 App Group 和 LookupSurface。

完成证据：形成能力矩阵，确认没有阻断首版主路径的系统限制。

### Slice 1：模块生命周期与设置

- 增加 TextLookupPlugin，并由 AppEnvironment 直接按 enabled 状态启停；
- 增加总开关、触发模式、快捷键、目标语言和排除应用设置；
- 改造 GlobalHotkeyRegistrar 支持按 registration 注销；
- 抽取共享 AccessibilityAuthorization。

完成证据：启停可重复、Root Search 快捷键不受影响、重启恢复设置。

### Slice 2：触发与文本捕获

- 鼠标候选、普通组合键和双击修饰键；
- AX selection/pointer capture；
- term 清洗、句子、来源 URL 和锚点；
- 捕获错误状态。

完成证据：fake tests 和至少 Safari、TextEdit、Xcode 实测通过。

### Slice 3：悬浮窗口与会话模型

- 独立 NSPanel；
- panel 定位；
- session model、取消和旧结果 gate；
- 基础 loading/partial/error UI。

完成证据：连续快速取词不显示旧结果，普通/全屏/多屏不抢焦点。

### Slice 4：FlashDict 查词与建卡

- Package、Info、entitlement；
- 主词典 lookup 和 LookupSurface；
- FlashDict 启动按钮、错误映射；
- 带原句和 source URL 建卡。

完成证据：真实签名跨进程查词、资源、音频和建卡闭环。

### Slice 5：Apple Translation

- view-bound TranslationSession；
- 自动源语言、默认目标语言和语言快捷按钮；
- 模型下载、不支持、取消和重试状态；
- 翻译结果不进入闪卡。

完成证据：真实 Mac 上完成已安装和未安装语言模型路径。

### Slice 6：兼容与收口

- 剪贴板兼容取词；
- 安全输入、排除应用；
- 完整应用矩阵、隐私日志检查和双语文案。

完成证据：需求文档 TLP-FR-001～023 和完成定义全部闭环。

## 18. 主要风险与处理

| 风险 | 处理 |
| --- | --- |
| 不同应用 AX 能力差异大 | Slice 0 先建立真实应用矩阵；允许部分成功和明确失败。 |
| Panel 出现后选区消失 | 捕获完整上下文后再显示；show 时不激活 zbox。 |
| 双击 Option 误触 | 必须完成按下/释放，排除中间键，使用可测试时间阈值。 |
| AX IPC 阻塞主线程 | capturer 使用受控非 MainActor 边界和消息超时。 |
| 新旧查词竞态 | 取消旧任务，并以 session/request ID 双重 gate。 |
| Apple Translation session 生命周期错误 | session 只存在于 `.translationTask` view 生命周期。 |
| 剪贴板恢复覆盖用户新内容 | change count 校验；发生竞争时放弃恢复。 |
| 插件停用影响其它快捷键 | registrar 按 token/ID 注销，不调用全局 unregisterAll。 |
| FlashDict 资源跨进程失败 | 真实签名 App Group 和 WKWebView 资源/音频验收。 |
| 过早统一在线词典模型 | 首版不建统一 provider，等待真实合法 API。 |
| 未实现第三方翻译却形成产品表面 | 首版不提供接口、配置 UI 或凭据存储，等待真实 provider 进入排期。 |

## 19. 非目标与演进边界

本设计不构成公共插件 SDK。未来若要支持外部插件，必须重新设计：

- 动态发现和加载；
- 版本与兼容合同；
- 权限与 capability manifest；
- 代码签名和信任；
- 进程隔离与崩溃边界；
- Settings 和 UI 扩展点；
- 发布、升级与卸载。

未来接入第一个真实在线词典时，应基于该 API 的合法使用方式、结果数据形状、资源与建卡语义，再比较“结构化统一 entry”“provider-owned surface”或“并列 source section”。不得为了保持本方案不变而强迫真实在线结果适配 FlashDict HTML 模型。

未来实现具体第三方翻译 adapter 时，必须为该 provider 单独定义：鉴权、endpoint、请求/响应 DTO、速率限制、取消、超时、隐私文案和真实网络验证。只有出现第二个真实实现且接口形状确实重复后，才评估抽取通用合同。
