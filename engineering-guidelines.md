# zbox 开发与工程规范

- 类型：Normative（规范）
- 状态：Active
- 版本：v1.0.0
- 最后验证日期：2026-08-14
- 适用平台：macOS 15+
- 职责域：架构、状态、并发、错误、性能、日志、安全、测试与质量门禁
- 代码对应路径：`/Users/zwyyy/code/swift/zbox/zbox`、`/Users/zwyyy/code/swift/zbox/zboxTests`

## 1. 必要复杂度

1. `ENG-SIMP-001`：优先选择能准确表达当前产品模型、平台行为、状态归属和错误语义的最简单设计；精简不等于压缩行数，必要复杂度必须显式建模，不必要复杂度必须删除。
2. `ENG-SIMP-002`：状态、入口和抽象必须服务当前真实需求；状态必须有明确 owner、读者、写者、持久化位置和 reset 条件，抽象必须隔离真实平台边界、提供真实测试替换或消除已经出现的有意义重复。
3. `ENG-SIMP-003`：禁止为假想插件生态、跨进程通信、跨平台、远程服务或未来功能预留 adapter、fallback、legacy path、config switch、runtime wrapper、空配置对象或无行为差异的中间层。
4. `ENG-SIMP-004`：新增 fallback、legacy 或 compatibility path 必须先明确保护的真实对象、缺少该路径会破坏的行为、适用范围和删除条件；运行环境失败默认显式报错，不得吞错、伪造成功或自动切换旧路径。
5. `ENG-SIMP-005`：测试失败不构成新增生产兼容的理由；测试不再代表当前产品契约或真实用户行为时，应更新或删除测试。
6. `ENG-SIMP-006`：实现完成后主动删除未使用入口、过渡 adapter、无行为差异 wrapper、永久关闭分支、占位设置和过期测试夹具。

## 2. 架构与 Ownership

1. `ENG-ARCH-001`：采用 SwiftUI 状态驱动架构；UI 由状态推导，用户意图进入 owner 或 capability 后再产生状态变化，不以 view-to-view 调用或散落的全局单例作为主链路。
2. `ENG-ARCH-002`：`ZBoxApp` / `AppDelegate` 是 composition root 和生命周期入口；`AppEnvironment` 负责 M1 app-lifetime 装配与编排，但不得在新增 Clipboard、Selected Text、Display、Workspace 等能力时无限吸收各功能内部状态。
3. `ENG-ARCH-003`：瞬时 UI 状态留在 View；跨 View、跨任务或持久化状态必须有单一 owner 和单一写入真源，镜像只能是只读 projection 或 derived value。
4. `ENG-ARCH-004`：View 只负责渲染、局部交互状态和转发用户意图；应用枚举、应用启动、全局快捷键、Accessibility、登录项和窗口控制不得实现在 View 中。
5. `ENG-ARCH-005`：新增能力默认按可运行、可验收的纵向用户闭环推进；局部重构只能服务当前闭环实际经过的路径，不借功能开发横向重写无关模块。
6. `ENG-ARCH-006`：Command 是搜索入口与直接快捷键共享的稳定业务接口；新增可执行能力不得绕过 Registry 建立专用执行旁路。

## 3. 目录、模块与依赖

1. `ENG-MOD-001`：保持当前按语义能力组织的目录：`App`、`Commands`、`Builtins`、`Hotkeys`、`Platform`、`Search`、`Settings`；新增文件必须进入实际 ownership 所在目录。
2. `ENG-MOD-002`：`App` 负责 composition、lifecycle 和 app-lifetime orchestration；`Commands` 定义稳定命令模型；`Builtins` 负责能力注册；`Platform` 隔离系统 API；`Search` 保持纯匹配与展示；`Settings` 只承载设置表面。
3. `ENG-MOD-003`：当前不引入固定的 `Features/Core` 层级、额外 Swift Package 或宽泛的 `Utilities`、`Runtime`、`Services` 目录；只有真实复用或隔离需求出现后再设计边界。
4. `ENG-MOD-004`：职责边界优先于文件体量；行数、类型数和嵌套深度只作预警，按行数机械切文件不构成架构改善。
5. `ENG-MOD-005`：View 不直接创建真实平台 capability；非 UI 调用方只需要单一能力时，不得传入完整 `AppEnvironment`。
6. `ENG-MOD-006`：默认使用最小安全可见性；类型使用 `UpperCamelCase`，成员使用 `lowerCamelCase`，命名表达业务语义，注释解释复杂平台或业务约束而不复述代码。

## 4. Seam 与可测试性

1. `ENG-DI-001`：系统边界首先通过语义明确的具体 adapter 隔离；只有存在真实多实现、平台变化或回归测试无法通过公开接口覆盖时，才引入窄 protocol、intent closure 或 value contract。
2. `ENG-DI-002`：不得为了“依赖注入完整性”为只有一个实现且没有替换需求的类型创建一对一 protocol。
3. `ENG-DI-003`：纯规则优先提取为无副作用值类型，通过公开接口测试；不得为了测试私有实现而增加生产 API。
4. `ENG-DI-004`：系统 adapter 的测试替换点应位于行为真实变化的 seam，调用方只学习完成任务所需的最小接口。

## 5. Swift 6 与并发

1. `ENG-CONC-001`：UI 可观察状态、AppKit 对象、Carbon 注册表和共享 app-lifetime 可变状态只在 MainActor 更新。
2. `ENG-CONC-002`：纯值计算明确保持 `Sendable` / `nonisolated`；不要因为方法可能失败或调用系统 API 就自动改成 async。
3. `ENG-CONC-003`：优先 async/await 和结构化并发；禁止无理由 `Task.detached`、自定义后台队列或无 owner 的 fire-and-forget `Task`。
4. `ENG-CONC-004`：owner 创建的可取消任务必须保存 handle，在新任务替换、功能停止或 owner 生命周期结束时取消，并单独处理 `CancellationError`。
5. `ENG-CONC-005`：长循环、批量扫描或真正长耗时任务必须支持合作式取消；只有存在真实外部等待上界时才增加超时，不为短同步系统调用套异步 wrapper。
6. `ENG-CONC-006`：从 Carbon、AppKit delegate 或其他 C/Objective-C 回调进入 MainActor 时，必须让隔离假设可被代码和 Swift 6 编译器验证，不使用 `@unchecked Sendable` 掩盖竞态。

## 6. 错误与恢复

1. `ENG-ERR-001`：区分用户可修复错误、权限错误、目标状态已变化和系统 API 异常；错误类型与文案必须反映真实失败原因。
2. `ENG-ERR-002`：用户可见错误必须简短、可操作；权限缺失提供进入系统设置或重新请求的真实恢复动作。
3. `ENG-ERR-003`：关键路径不得静默失败、伪造成功或停留在无限等待状态；恢复路径只能对应真实用户动作或系统状态变化。
4. `ENG-ERR-004`：快捷键更新失败必须保留或恢复上一组可用注册；窗口目标消失、无 focused window、不可调整和无可用显示器必须明确失败。
5. `ENG-ERR-005`：成功、错误和恢复提示使用同一业务术语；不得让菜单、Settings、Root Search 和直接快捷键对同一结果给出冲突语义。

## 7. 性能与可观测性

1. `ENG-PERF-001`：Root Search 唤起、输入、搜索和选中执行出现可感知阻塞时，必须定位应用扫描、图标读取、窗口 IO 或无关状态更新的实际影响；当前同步搜索只有真实测量证明不够用时才改为后台或增量架构。
2. `ENG-PERF-002`：性能问题必须通过 Instruments、OSLog signpost 或可复现的真实计时定位；重点关注快捷键到 Panel 可输入、搜索计算、应用扫描和命令执行耗时。
3. `ENG-PERF-003`：不得为没有测量证据的性能问题增加磁盘缓存、预取、后台索引、任务队列或多层缓存协议。
4. `ENG-OBS-001`：排障优先使用 `Logger` / OSLog，禁止散乱 `print`；关键平台边界按需记录 command ID、source、结果类别和 elapsed，不记录搜索词或窗口内容。
5. `ENG-OBS-002`：Release 日志必须脱敏并控制级别；应用路径、bundle identifier 和前台进程信息只在排障确实需要时记录，不形成使用画像。

## 8. 安全、隐私与文件边界

1. `ENG-SEC-001`：M1 不上传搜索词、应用列表、窗口信息、快捷键或使用行为；禁止采集与核心功能无关的可识别数据。
2. `ENG-SEC-002`：Accessibility 权限只用于定位、移动和缩放目标窗口；不得读取、保存或上传窗口内容，不得把权限状态伪装成普通功能开关。
3. `ENG-SEC-003`：未验证的外部字符串、URL、文件内容或未来插件输入不得直接进入命令执行、脚本执行或动态加载上下文。
4. `ENG-SEC-004`：新增文件访问必须明确用户授权、路径 ownership、持久化方式、失效恢复和删除条件；临时产物放入 tmp，可重建缓存放入 Caches，不把缓存当作用户资产。
5. `ENG-SEC-005`：仓库不得提交密钥、Developer ID 私钥、notarization 凭据或用户本机隐私数据。

## 9. macOS UI 与可访问性

1. `ENG-UI-001`：优先使用 macOS 系统 scene、control、menu、Settings、material 和键盘语义；AppKit escape 只用于 SwiftUI 无法正确表达的 Panel、焦点、Space、Carbon 或 Accessibility 行为。
2. `ENG-UI-002`：Root Search 是键盘优先的 command palette，可以使用专用结果表面，但查询、选择、执行、关闭和错误恢复必须同时具备清晰的键盘与可访问性语义。
3. `ENG-UI-003`：Settings Scene 是全局偏好的单一权威入口；菜单栏和命令只能打开它，不得建立第二份设置真源。
4. `ENG-UI-004`：同一动作在菜单栏、Root Search、Settings 和快捷键说明中的标题与结果语义必须一致；系统保留快捷键和已注册快捷键冲突时必须明确拒绝或回滚。
5. `ENG-UI-005`：所有交互元素必须具有准确且唯一的可访问名称；颜色不得成为选中、成功、失败或权限状态的唯一表达。
6. `ENG-UI-006`：View 拆分按 layout、interaction、platform surface 或纯渲染单元进行；单纯按行数切分不构成 UI 架构改善。
7. `ENG-UI-007`：当前产品未声明多语言范围；用户可见文案必须集中使用一致术语。若引入第二语言，必须一次性建立 String Catalog 真源，不得长期混用硬编码和局部本地化。

## 10. 测试与验证

1. `ENG-TEST-001`：用户可见行为、命令契约、持久化配置、窗口几何、快捷键冲突或错误恢复变化必须有最小对应验证；测试覆盖产品结果，不为临时 shim 或私有实现细节补安全感。
2. `ENG-TEST-002`：Command Registry、SearchEngine、WindowGeometry、Hotkey 配置与其他纯规则优先使用 Swift Testing 单元测试。
3. `ENG-TEST-003`：Carbon 全局快捷键、NSPanel 焦点与 Space、Accessibility、登录项、外接显示器和真实应用启动属于平台集成边界；采用受影响范围内的构建、运行与人工矩阵，自动化无法可靠覆盖时记录限制。
4. `ENG-TEST-004`：测试失败若只反映已确认的产品行为变化，应修改或删除测试；不得为了旧测试通过而在生产代码保留 fallback、alias、legacy path 或 dormant 设置项。
5. `ENG-TEST-005`：测试执行命令与 UI 测试默认策略由根目录 `AGENTS.md` 维护；本文不建立第二份命令真源。

## 11. 依赖、发布与质量门禁

1. `ENG-SUP-001`：新依赖必须说明当前能力缺口、许可证、维护状态、隐私/安全影响和删除成本；标准框架能满足时不引入第三方依赖。
2. `ENG-SUP-002`：依赖升级必须记录版本变化、风险和回滚方式；来源不明的二进制产物不得进入仓库或发布包。
3. `ENG-REL-001`：分发基线是 Developer ID + Hardened Runtime；App Sandbox 关闭是当前产品决策，任何反向切换必须重新验证全局快捷键、应用扫描、Accessibility、登录项、签名和公证链路。
4. `ENG-QG-001`：代码变更完成前至少通过目标 macOS build；关键行为变化必须补测试、更新测试或记录不能自动验证的系统条件。
5. `ENG-QG-002`：文档专属改动必须检查链接、路径、规则重复、规则冲突和 diff；除非改动构建命令、项目设置或用户明确要求，不强制运行构建。
6. `ENG-QG-003`：架构重构必须声明收敛的是 ownership、dependency、state、surface、platform boundary 或 command contract 中哪类问题，并给出 before/after 耦合与 reachability 证据。
7. `ENG-QG-004`：若重构只把原对象的 fan-in/fan-out 转移到新的 Context、Runtime、Coordinator、Graph 或 wrapper，且没有缩小接口或提高 locality，视为未完成。
8. `ENG-QG-005`：提交或 PR 说明应包含变更范围、验证步骤、跳过项、风险和回滚点；不得把未执行检查写成已通过。

## 12. 例外

1. `ENG-EXC-001`：偏离规范必须记录影响范围、风险、负责人、回归条件和失效日期；临时例外最长 90 天。
2. `ENG-EXC-002`：例外到期前必须删除、完成标准实现或重新评审；过期例外不得作为新变更的依据。
