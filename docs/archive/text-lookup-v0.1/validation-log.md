# zbox 实施验证记录

> 归档：历史实施证据；当前发布与真实系统验收见 `../../release-readiness.md`。

只记录每个阶段实际完成的检查和因环境限制跳过的项目，不设置性能闸门、基线、快照或哈希校验。

## M0：macOS 能力验证

- 通过：使用 Swift 6、macOS 15 deployment target 完成 Debug 构建。
- 通过：统一运行脚本可以构建、启动并确认 zbox 进程存活。
- 通过：应用以 `LSUIElement` 辅助应用运行，无 Dock 图标；App Sandbox 未启用，Hardened Runtime 保持启用。
- 通过：搜索面板可以由全局快捷键显示，面板可获得输入焦点并接收文本。
- 通过：扫描 `/Applications`、`/System/Applications` 和用户 Applications 目录，当前环境读取到 128 个应用。
- 通过：应用启动链路实际打开目标应用；回车执行前显式同步 AppKit 输入框文本，避免 SwiftUI 绑定尚未提交时误选首项。
- 通过：当前开发环境已授予辅助功能权限，窗口半屏与最大化命令已实现基于可见屏幕区域的坐标换算。
- 发现：当前机器运行中的 Raycast 已占用 Option-Space；M1 临时默认键改用 Control-Option-Space，快捷键配置与冲突提示留到 Slice 3。
- 跳过：外接显示器、不同 Space 和全屏应用上的人工验证，当前运行环境不具备稳定自动化条件。

## Slice 1：统一 Command 路径的 App Search

- 通过：应用使用 Swift 6、macOS 15 deployment target 完成签名构建并启动进程。
- 通过：应用目录当前读取到 128 个应用，并全部注册为最小 `CommandDescriptor`；应用执行只经过 `CommandRegistry.execute`。
- 通过：Registry 的注册顺序、重复 ID、未知 ID 和执行上下文测试通过。
- 通过：SearchEngine 的大小写与变音符号归一化、关键词、简单模糊匹配、限制数量和固定排序测试通过。
- 通过：8 个 Swift Testing 单元测试全部通过。
- 通过：应用图标按搜索结果所需读取，并只在当前进程内复用。
- 跳过：合成全局按键和辅助功能菜单点击未触发 SwiftUI action；达到本项验证时间限制后停止，保留 M0 已完成的真实面板与应用启动验证结果。

## Slice 2：Window Commands

- 通过：Left Half、Right Half 和 Maximize 以三个内置 Command 注册到应用命令使用的同一个 Registry。
- 通过：窗口命令使用 Root Search 显示前记录的目标应用 PID；没有应用专用或窗口专用执行旁路。
- 通过：权限缺失、目标应用消失、无焦点窗口、读写窗口失败和无可用显示器都会显示现有的简短错误。
- 通过：半屏、最大化、AX/Cocoa 坐标转换、中心点显示器选择、最大交叠回退和完全离屏场景测试通过。
- 通过：13 个 Swift Testing 单元测试全部通过，签名构建与进程启动通过。
- 通过：当前开发环境的 Accessibility 授权状态为已授权。
- 跳过：常见应用窗口和外接显示器的人工操作验证；当前自动化无法可靠触发 Root Search action，且没有外接显示器条件。

## Slice 3：Direct Hotkey 与 Settings

- 通过：Root Search 快捷键可在四个常见 Space 组合中修改；默认使用不与当前 Raycast 冲突的 Control-Option-Space。
- 通过：Left Half、Right Half 和 Maximize 可选择快捷键预设，也可设为 None 立即注销。
- 通过：zbox 内部重复快捷键会被拒绝；系统注册失败时恢复上一组仍可用配置并显示错误。
- 通过：命令快捷键以 `CommandID.rawValue` 作为 UserDefaults key 的一部分保存，不使用 SwiftData。
- 通过：直接快捷键执行时重新读取当前前台应用 PID，并和 Root Search 共用 Registry 与窗口命令执行路径。
- 通过：Settings 提供开机启动开关，使用系统 `SMAppService.mainApp` 注册和注销。
- 通过：快捷键默认值、保存、移除、内部冲突和不同快捷键组合测试通过；总计 16 个 Swift Testing 测试通过。
- 通过：签名构建与进程启动通过。
- 跳过：未实际切换系统登录项，避免验证过程改变用户当前登录配置。
- 跳过：合成键盘事件无法可靠验证 Carbon 全局热键回调，保留代码、冲突回滚和运行构建验证结果。

## Slice 4：产品收口

- 通过：空查询优先展示 Left Half、Right Half、Maximize，再展示应用；无结果时显示明确空状态。
- 通过：窗口命令缺少 Accessibility 权限时，Root Search 提供直接打开系统设置的入口。
- 通过：菜单栏展示当前 Root Search 快捷键，继续提供搜索、Settings、重载应用和退出入口。
- 通过：Settings 权限文案明确说明只移动/缩放前台窗口，不读取或保存窗口内容。
- 通过：搜索结果提供组合式可访问性标签和选中状态。
- 通过：移除模板启动性能测试与自动截图，只保留最小进程启动 UI 冒烟测试。
- 通过：16 个 Swift Testing 单元测试全部通过。
- 通过：最终签名 Debug 构建启用 Hardened Runtime、关闭 App Sandbox；开发签名仅包含 Xcode 注入的 `get-task-allow`。
- 说明：`codesign --strict` 在当前机器返回开发证书链不受信任；签名元数据与 Apple Development 证书链可读取，应用仍可构建和启动。Developer ID 分发签名与公证不在本次 MVP 实施范围内。
- 跳过：UI 冒烟测试运行超过 4 分钟且不再输出，已主动终止；不阻塞最终签名构建和交付。

## Text Lookup Slice 0：系统能力探针

- 通过：当前基线完成签名 Debug 构建、启动和进程验证。
- 通过：真实 zbox 进程具备 Accessibility、全局事件监听和事件发送授权。
- 通过：从 TextEdit 的前台应用 AX 对象取得 `AXTextArea` 焦点元素，并读取完整选区、选区范围、范围文本和范围屏幕矩形；位置命中、位置到字符范围和范围到字符串均返回有效结果。
- 发现：直接从 system-wide AX 对象读取焦点元素时只得到 `AXWindow`；正式实现必须先取得前台应用 PID，再从该应用 AX 对象读取焦点文本元素。
- 通过：临时 `.nonactivatingPanel` 显示后没有改变前台应用，zbox 保持非激活，面板可见且不成为 key window。
- 通过：Carbon 可成功注册不带修饰键的 Escape 全局热键；真实关闭交互随 Slice 3 面板实现验证。
- 通过：以 macOS 15 deployment target 编译包含 SwiftUI `.translationTask` 和 `TranslationSession.translate` 的最小调用；真实语言模型下载和翻译结果随 Slice 5 验证。
- 通过：相邻 zdict 的 `FlashDictIntegrationKit` 可独立构建，8 个契约测试全部通过。
- 延后：FlashDict App Group 的真实跨进程往返随 Slice 4 接入验证；Safari、Chrome、Xcode、VS Code 和 Preview 的完整兼容矩阵随 Slice 6 验证。
- 说明：一次性探针代码已从产品源代码移除，不作为运行时诊断设施保留。

## Text Lookup Slice 1：插件生命周期与设置

- 通过：增加静态 `BuiltinPluginHost` 与幂等的 Text Lookup 启停边界；应用退出时先停止插件，再清理剩余全局快捷键。
- 通过：总开关、划词模式、`⌥C`/双击 `⌥` 预设、剪贴板兼容模式、目标语言和排除应用使用 `plugin.text-lookup.*` UserDefaults key 持久化；停用不删除配置。
- 通过：GlobalHotkeyRegistrar 支持按注册 ID 注销；Text Lookup 重载或停用只注销自身快捷键，不清理 Root Search 与窗口命令注册。
- 通过：Text Lookup 快捷键加入现有内部冲突检查；注册失败时恢复上一预设并展示错误。
- 通过：窗口管理与 Text Lookup 共用窄的 Accessibility 授权 adapter。
- 通过：19 个 Swift Testing 单元测试全部通过，其中新增 3 个必要测试覆盖设置恢复、宿主幂等启停和快捷键冲突。
- 通过：签名 Debug 构建与真实进程启动验证通过。

## Text Lookup Slice 2：触发与文本捕获

- 通过：全局鼠标抬起产生划词候选；自动模式延迟 130 ms 后发布，快捷键模式保留 3 秒候选，关闭模式不捕获。
- 通过：`⌥C` 与完整、无中断的双击 `⌥` 共用同一取词入口；没有可用候选时按当前鼠标位置取词。
- 通过：生产捕获 adapter 在 actor 边界执行 AX IPC，按 request ID 取消和隔离旧请求；停用插件会取消任务并清空候选和结果。
- 通过：选区与鼠标位置路径返回清洗后的 term、UTF-16 正确的所在句、来源 URL（应用可提供时）、来源 bundle ID 和 Cocoa 坐标锚点；排除应用与安全输入在读取正文前拒绝。
- 通过：用户显式开启时，AX 选区读取失败可单次发送复制事件；最多等待约 300 ms，并仅在剪贴板仍是本次写入版本时恢复完整 item 数据，避免覆盖用户并发写入。
- 通过：TextEdit 真实签名进程实测取得 `The quick brown fox jumps`、完整原句与有效范围矩形。
- 通过：Xcode 真实签名进程可读取当前编辑器选区并对超过 80 字符/8 词的内容返回预期 `selectionTooLong`，证明编辑器 AX 选区路径可达。
- 发现：Safari 网页正文视觉选区不暴露原生 AX selected text，位置命中也不提供 `AXRangeForPosition`；因此 Safari 划词需用户开启剪贴板兼容模式，鼠标指针取词在首版标记为不支持。
- 限制：一次性启动探针会短暂改变前台进程，无法可靠自动验收 Safari 的复制事件；真实常驻插件的 Safari 兼容闭环随 Slice 6 应用矩阵复验，不保留为产品运行时探针。
- 通过：23 个 Swift Testing 测试全部通过，其中新增 4 个必要测试覆盖清洗边界、长度限制、UTF-16 单词/句子定位和双击 `⌥` 手势。
- 通过：临时探针移除后的签名 Debug 干净构建通过。

## Text Lookup Slice 3：悬浮窗口与会话模型

- 通过：独立 `TextLookupPanelController` 使用单一 borderless、nonactivating `NSPanel`，显示时只 `orderFrontRegardless`，不激活 zbox 或调用 `makeKeyAndOrderFront`。
- 通过：面板使用 floating level，并加入 all Spaces、全屏辅助窗口、transient 与忽略窗口循环行为；点击控件时仅按需成为 key window。
- 通过：显示期间临时注册无修饰键 Escape 并消费关闭动作，隐藏时立即按 registration ID 注销；外部鼠标按下、新会话和插件停用也会关闭面板。
- 通过：`TextLookupSessionModel` 成为 capture 与捕获错误的唯一 UI 状态 owner；新 capture 替换旧 session ID，后续异步结果可用 `accepts` gate 拒绝旧会话。
- 通过：首版面板渲染 term、最多四行原句、释义/翻译独立 loading 占位、可操作错误和紧凑目标语言菜单；未保存任何翻译结果。
- 通过：定位纯函数优先锚点下方、空间不足时上方显示，并把水平和垂直位置夹紧到目标屏幕 visible frame；无锚点时固定使用触发时鼠标位置。
- 通过：25 个 Swift Testing 测试全部通过，其中新增 2 个必要测试覆盖上下定位/边界夹紧与新 session 拒绝旧 ID。
- 通过：签名 Debug 构建通过；不抢焦点的 panel、当前 Space/全屏辅助行为和 Escape 注册已在 Text Lookup Slice 0 的真实签名探针验证。
- 跳过：当前环境没有外接显示器，双屏定位仅验证纯函数边界，留待 Slice 6 兼容矩阵人工复验。

## Text Lookup Slice 4：FlashDict 主词典与带原句建卡

- 通过：zbox target 直接依赖相邻 `../zdict/Packages/FlashDictIntegrationKit`，没有引入 MDX/MDD、索引、extractor 或多词典抽象。
- 通过：Debug/Release 均配置 `group.tech.hyperseek.flashdict.integration` App Group entitlement；显式 Info.plist 写入 `FlashDictIntegrationAppGroupIdentifier`，签名产物复查两项均存在。
- 通过：每次新 capture 立即取消旧查词和建卡任务，以独立 request ID 调用主词典 lookup，并在提交 `LookupDocument` 前校验 capture session ID。
- 通过：成功结果直接渲染 IntegrationKit 的 `FlashDictLookupSurface`，资源、音频、词条内跳转和义项点击继续走共享合同；zbox 不解析或改写词典 HTML。
- 通过：FlashDict 未运行、未配置主词典、无结果、协议不兼容和请求失败映射为独立 UI；只为可恢复失败提供手动重试，未运行状态另提供用户主动启动 FlashDict 的按钮。
- 通过：义项点击直接使用 surface 返回的冻结 `cardSeed`，每次生成新的 delivery ID；建卡上下文只附加原句和 source URL，`userNote` 固定为 nil，翻译不进入闪卡。
- 通过：建卡的 adding、added、rejectedQuota 和 failed 状态按 selection ID 回传给共享 surface；新会话或插件停止时取消未完成任务，晚到结果由 session ID gate 丢弃。
- 通过：26 个 Swift Testing 测试全部通过，其中新增 1 个必要 fake 合同测试验证冻结义项及原句/source URL 建卡上下文；IntegrationKit 自身 8 个合同测试已在 Slice 0 通过。
- 通过：移除一次性探针后的 zbox 签名 Debug 干净构建通过；产物保留 Hardened Runtime、关闭 App Sandbox，并带正确 App Group/Info 配置。
- 历史限制：`/Users/zwyyy/Downloads/vm-mount/FlashDict.app` 是不包含新集成 key 的旧构建且签名已损坏，不能代表当前 FlashDict 工程；后续复验改用相邻 zdict 当前源码的签名产物。
- 通过：相邻 zdict 当前 Debug/Release provisioning profile 均已包含 `group.tech.hyperseek.flashdict.integration`；当前源码的 Debug 与 Release FlashDict 均完成 Apple Development 签名构建和严格签名校验。
- 通过：真实 Release FlashDict 在 App Group 中监听 `bridge.sock`，主词典 lookup 返回 OALDPE 的完整 `LookupDocument`；随后成功读取 `text/css` 词典资源与 `audio/mpeg` 发音资源。
- 未执行：没有为了验收向用户现有 FlashDict 数据写入测试闪卡；建卡成功路径保留 IntegrationKit 合同测试与 zbox 冻结 seed、delivery ID、原句/source URL 上下文测试证据，不作为实施阻断。

## Text Lookup Slice 5：Apple 与第三方翻译边界

- 通过：原句与释义独立进入会话状态；无原句时不创建翻译请求，有原句时使用独立 translation request ID，旧结果不能覆盖新目标语言或新查词会话。
- 通过：`TextLookupPanelView` 通过 `.translationTask(configuration)` 持有 Apple `TranslationSession`；先检查 `LanguageAvailability`，随后调用系统 `prepareTranslation()` 和本地 `translate()`，没有把 session 放进长期 model 或插件。
- 通过：Apple Translation 覆盖原句缺失、加载、成功、无法识别语言、不支持语言对、模型下载取消和内部失败；取消或晚到结果只有 request ID 仍有效时才会显示。
- 通过：弹窗语言菜单更新持久化目标语言并只替换当前翻译 request/configuration，不重新捕获文本或查询 FlashDict；翻译结果只保留在内存中，建卡上下文仍固定不含翻译。
- 通过：当前 Mac 上英文到简体中文的真实 `LanguageAvailability` 返回 `supported`，证明语言对受系统支持但模型尚未安装；没有在自动验证中替用户确认下载。首次实际翻译将使用系统下载授权体验。
- 通过：定义 provider/request/result/error 通用合同，以及 Google、DeepL、LLM 的非秘密配置结构；这些 provider 在设置中明确标注仅保存配置、没有网络 adapter，Apple 仍是唯一可工作的来源。
- 通过：endpoint、model、credential reference 和可选语言映射使用 `plugin.text-lookup.*` UserDefaults；API secret 只由 `TranslationCredentialVault` 以稳定 service/account 存入 Keychain，普通插件停用不删除。
- 通过：27 个 Swift Testing 测试全部通过，其中新增目标语言 request 替换/旧结果 gate，并扩展设置恢复测试确认只持久化 Keychain reference。
- 通过：一次性语言状态探针已移除，签名 Debug 干净构建通过；未向任何第三方翻译服务发送网络请求，也未使用真实第三方 API key。
- 延后：当前语言模型未安装，Apple Translation 的真实成功文本与用户取消下载路径需在用户首次授权模型下载后复验。

## Text Lookup Slice 6：兼容、隐私与本地化收口

- 通过：默认排除 zbox 与 FlashDict 的正式/开发 bundle ID；selection 和 pointer 两条 AX 路径均在读取正文前检查排除项，并沿父链拒绝 `AXSecureTextField`。
- 通过：剪贴板兼容模式仍默认关闭，只用于已存在选区的单次 AX 失败；指针、安全输入和排除应用不会进入兼容路径，恢复前检查 change count。
- 通过：Text Lookup 设置页加入简体中文 String Catalog；签名产物实际生成 `zh-Hans.lproj/Localizable.strings`，覆盖启停、触发、快捷键、兼容模式、翻译、权限、排除应用和第三方配置文案。
- 通过：权限/隐私文案明确说明触发时读取选区或指针文字、只保留当前会话、建卡是唯一显式持久化、无需 Screen Recording 且不建立历史；窗口管理文案不再笼统声称应用不读取任何文本。
- 通过：静态检查 Text Lookup 模块没有 Logger、os_log 或 print；UserDefaults 写入项仅为启停/触发/目标语言/排除列表/第三方非秘密配置，不包含 term、原句、URL、释义 HTML、翻译结果或 API secret。
- 通过：第三方 API secret 仅进入 Keychain，设置模型和日志只持有随机 credential reference；未实现 provider 无法被设为当前翻译来源。

### 应用兼容矩阵（当前机器）

| 应用 | 选区/原句 | 指针取词 | 当前结论 |
| --- | --- | --- | --- |
| TextEdit | 实测成功，取得 term、完整原句和范围矩形 | Slice 0 实测 `AXRangeForPosition` 成功 | 原生 AX 主路径支持 |
| Safari | 网页正文视觉选区不暴露 selected text | 网页 WebArea 不暴露 range-for-position | 划词需用户开启剪贴板兼容；指针模式首版明确不支持 |
| Xcode | 编辑器选区可读，超长选区正确返回长度错误 | 未完成稳定坐标自动化 | selection 支持；pointer 待人工复验 |
| 备忘录 | 已安装 | 未执行稳定人工矩阵 | 待人工复验 |
| Visual Studio Code | 已安装 | 未执行稳定人工矩阵 | Electron 边界待人工复验 |
| Preview PDF | 已安装 | 未执行稳定人工矩阵 | 可选中文本 PDF 待人工复验 |
| Google Chrome | 当前机器未安装 | 当前机器未安装 | 无法在本机验收 |

- 限制：当前没有外接显示器，普通/全屏/多 Space 的 nonactivating panel 行为已有 Slice 0 探针证据，但外接双屏仍只有定位纯函数验证。
- 未闭环：完整人工应用矩阵、Apple 已安装模型成功翻译/取消下载、Developer ID 分发签名和真实建卡写入仍缺少人工证据；这些项目只记录验收边界，不阻断已完成的 v0.1 实施。FlashDict 查词、词典资源与音频的真实 App Group 跨进程路径已经通过。

## Text Lookup v0.1：最终合并验证

- 通过：zbox 27 个 Swift Testing 测试全部通过。
- 通过：相邻 FlashDictIntegrationKit 8 个合同测试全部通过。
- 通过：zbox Release 配置完成签名构建，Hardened Runtime、App Group entitlement、FlashDict Info key 和简体中文资源均存在。
- 通过：工作区无未提交实现改动；需求、探针、Slice 1～6 和最终验证均按阶段形成独立提交。
- 限制：当前 Release 产物使用 Apple Development 证书并包含 `get-task-allow`，不是最终 Developer ID 分发签名；Developer ID、公证和 Gatekeeper 分发验证尚未完成。
- 结论：Text Lookup v0.1 代码实施完成；Developer ID 分发、Apple 模型下载、完整应用/显示器矩阵和真实建卡写入作为后续人工验收记录，不作为实施状态的阻断条件。

## Text Lookup v0.1：合并后边界审查

- 通过：新增乱序词典响应回归测试，先复现旧请求普通失败覆盖新词条成功结果，再以独立 dictionary request ID 同时约束成功与失败提交；切换词条时同步取消旧建卡任务并清空义项状态。
- 通过：剪贴板兼容回退前重新核对前台应用 PID，应用已切换时不再向新应用发送复制事件；selection 与 pointer 均保存触发时锚点，AX 矩形缺失及错误路径不再读取展示时的鼠标位置。
- 通过：AX 原句上下文只使用 `AXNumberOfCharacters` 与有界 `AXStringForRange`，移除读取完整 `AXValue` 的回退，单次上下文范围保持在目标附近约 2,048 个 UTF-16 单元内。
- 通过：28 个 zbox Swift Testing 单元测试全部通过，包含新增的取消不敏感、乱序失败回归测试。
- 通过：zbox Release 配置重新完成签名构建。
- 限制：包含 UI target 的完整 `test` 命令中，全部单元测试通过，但 UI Test Runner 因系统认证正在运行而初始化失败；该环境失败不作为功能断言通过，也未以产品代码绕过。

## Text Lookup v0.1：逐条完成度审计修正

- 通过：快捷键触发新查词时先关闭旧 panel 并清理旧 session；候选以目标应用 PID 和 3 秒时限校验，捕获完成前应用已切换时不再发布旧选区。
- 通过：词典内链跳转后保留当前 lookup term；首次失败后的明确重试继续查询当前内链词条，不再退回最初捕获词。
- 通过：任意外部鼠标按键均可关闭 panel；原句不再四行截断，长内容在最高 88 pt 的原句区域内可滚动查看全文；目标语言菜单与翻译状态归入同一信息区。
- 通过：`AppEnvironment` 使用既有 `TranslationCredentialStoring` seam；内存 fake 验证 secret 只进入凭据存储、UserDefaults 只含 credential reference，删除配置同步删除凭据。
- 通过：新增 3 个必要合同测试覆盖候选过期/应用切换、内链词条重试和第三方凭据边界；zbox 共 31 个 Swift Testing 单元测试全部通过。
- 通过：FlashDictIntegrationKit 当前源码 8 个合同测试重新通过；zbox Release 配置重新完成签名构建。
- 限制：长原句与翻译区布局已通过代码和构建检查，但当前系统认证状态阻止 UI Test Runner 初始化，本轮没有取得新的 panel 截图或人工交互证据。
- 更正：沙箱内执行 `security find-identity` 得到的 `0 valid identities` 不能代表真实钥匙串状态；在允许访问登录钥匙串后确认本机有 2 个有效 Apple Development identity。旧 FlashDict 1.4.0 仍不是有效验收服务端，但当前源码签名产物已替代它完成 App Group 复验。

## Text Lookup v0.1：完成定义补证

- 通过：补充 80/81 字符边界断言，与既有 8/9 词测试共同覆盖自动触发长度合同。
- 通过：显式指针快捷键在 AX 捕获期间立即显示轻量读取状态；Escape、外部点击、新触发或停用会通过 panel dismiss 边界取消当前 capture attempt，晚到结果不能重新弹窗。
- 通过：新增 1 个 session 状态测试；zbox 共 32 个 Swift Testing 单元测试全部通过。
- 记录：新增 `text-lookup-plugin-completion-audit-v0.1.md`，逐项区分 TLP-FR-001～023 的实现、自动化证据和仍缺失的真实验收。
- 限制：尝试以 argument domain 启动 Release zbox 并使用临时 TextEdit 文稿复验 panel；zbox 启动成功，但 TextEdit 对自身 AppleScript 与 System Events 均返回空窗口列表，无法安全定位内容。本轮未生成截图，临时进程和文件均已清理。

## Text Lookup v0.1：签名与 FlashDict 跨进程补证

- 通过：zbox 32 个 Swift Testing 单元测试、FlashDictIntegrationKit 8 个合同测试和 zbox Release 签名构建重新通过；未运行 UI 测试。
- 通过：真实钥匙串环境下 `security find-identity -v -p codesigning` 返回 2 个有效 Apple Development identity；FlashDict 使用 `Apple Development: changjun zheng (M69C6U5MT3)`。
- 通过：FlashDict Debug profile `6855851f-1b74-4216-9122-5193a971d47e` 与 Release profile `79ab823d-ee9d-4272-a57b-ebcc07dda767` 均包含 `group.tech.hyperseek.flashdict.integration`。
- 通过：当前 FlashDict Debug 与 Release 均完成签名构建；最终 Info.plist 包含 `FlashDictIntegrationAppGroupIdentifier`，签名 entitlements 包含相同 App Group，`codesign --verify --deep --strict` 通过。
- 通过：FlashDict Dev 启动后创建并监听 App Group `bridge.sock`；未配置主词典时真实返回 `primaryDictionaryUnavailable`，验证失败映射所需的服务端路径。
- 通过：FlashDict Release 使用现有主词典成功返回 `run` 的 OALDPE `LookupDocument`；随后跨进程读取 `oaldpe.css`（`text/css`）和 `run__us_1.mp3`（`audio/mpeg`）成功。
- 未执行：没有向用户现有数据写入验证闪卡；Developer ID、公证、Apple 翻译模型下载和完整应用/多显示器人工矩阵继续作为发布或人工验收记录，不阻断本次实施完成。

## ZWY-208 / ZWY-210 / ZWY-264：实施收口（2026-08-23）

- 通过：Root Search 与 Direct Hotkey 继续共用 `CommandRegistry.execute`；直接快捷键成功保持安静，失败由非激活反馈 Panel 显示，并为权限缺失和窗口管理未启用提供对应恢复操作。
- 通过：窗口管理默认关闭；命令仍可在 Root Search 中发现，只有功能已启用且 Accessibility 已授权时才注册直接快捷键。权限撤销后相关功能关闭并停止运行能力，配置保留；重新授权后由用户手动启用。
- 通过：用户快捷键改为可编码的 `keyCode + normalized modifiers`，设置页使用 AppKit recorder 录制；支持添加、修改、取消和清除命令快捷键，Root Search 不可清空。旧预设字符串直接丢弃，不保留迁移路径。
- 通过：快捷键注册继续使用事务式替换；内部冲突、无效普通组合、未知 CommandID 忽略和注册失败回滚均由定向单元测试覆盖。Text Lookup 双击 Option 保持独立触发类型。
- 通过：Root Search 增加纯 Control-N/P 导航映射；应用命令预生成中文全拼、紧凑全拼和首字母别名，`微信`、`wei xin`、`weixin`、`wx` 与固定排名测试通过。
- 通过：Settings 拆分为 General、Shortcuts、Window Management 和 Text Lookup 四个原生 Tab；应用路径开关默认关闭且只影响应用结果副标题；Root Search 的 SwiftUI 内容和 AppKit hosting view 共用 16 pt 连续圆角。
- 通过：Settings、菜单栏、Root Search、命令、快捷键、窗口和 Text Lookup 可见文案统一进入 String Catalog；共 141 个条目，141 个具备简体中文翻译，0 个 stale，签名 Debug 产物包含 `zh-Hans.lproj/Localizable.strings`。产品名称统一为 `zbox`。
- 通过：默认 Debug 构建命令 `xcodebuild -project zbox.xcodeproj -scheme zbox -destination 'platform=macOS' build` 成功。
- 通过：默认单元测试命令加 `-only-testing:zboxTests` 成功，42 个 Swift Testing 测试全部通过；命令虽会构建 scheme 中的 UI test bundle，但未执行任何 UI 测试。
- 通过：`script/build_and_run.sh --verify` 在独立 DerivedData 中完成签名构建、启动和进程存活检查。
- 通过：`git diff --check` 无空白错误；开发方案已校正为当前实现基线。
- 未执行：真实 Carbon 按键录制、动态键盘布局显示、系统级快捷键占用与注册失败的人工交互矩阵。
- 未执行：Direct Hotkey 失败 Panel 的非激活交互，以及无窗口、窗口不可调整、权限缺失从两种入口得到相同错误语义的真实窗口操作矩阵。
- 未执行：Accessibility 首次请求、拒绝、撤销、重新授权并手动重新启用，以及普通桌面、全屏、多 Space 和外接显示器的人工系统验收。
- 未执行：Root Search 在浅色、深色和不同桌面背景下的边缘/阴影截图，以及 English/简体中文真实界面的截断与布局检查。
