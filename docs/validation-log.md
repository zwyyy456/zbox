# zbox 实施验证记录

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
