# Text Lookup Plugin v0.1 完成度审计

> 归档：已完成实施证据；尚未闭环的真实系统项目见 `../../release-readiness.md`。

> 日期：2026-08-15
> 基准：`requirements.md`、`design.md`
> 目的：区分“产品代码已实现”“自动化证据已通过”和“真实环境验收已闭环”，不以构建成功替代完整完成定义。

## 1. 当前自动化基线

- zbox：32 个 Swift Testing 单元测试通过。
- FlashDictIntegrationKit：8 个合同测试通过。
- zbox：Debug 测试构建与 Release 签名构建通过。
- 静态边界：无多词典、在线词典、第三方翻译接口/配置/凭据/网络 adapter、动态插件 Runtime、取词历史或捕获正文日志。

## 2. 功能需求追踪

| ID | 实现证据 | 自动化/静态证据 | 当前结论 |
| --- | --- | --- | --- |
| TLP-FR-001 | `AppEnvironment` 直接按 enabled 状态调用 `TextLookupPlugin.start/stop`、设置恢复 | start/stop 幂等 guard 与设置持久化测试 | 已实现；真实退出路径已由签名进程验证 |
| TLP-FR-002 | Automatic、Shortcut Required、Off 三种模式 | 默认值与持久化测试 | 已实现 |
| TLP-FR-003 | `TextLookupTextProcessor.cleanSelection` | 空/标点、短语保真、80/81 字符与 8/9 词边界测试 | 已实现 |
| TLP-FR-004 | 3 秒候选、PID 校验、新候选替换 | 候选过期与应用进程变化测试 | 已实现 |
| TLP-FR-005 | `⌥C`、双击 `⌥`、内部冲突校验 | 手势与冲突测试 | 已实现 |
| TLP-FR-006 | AX position/range 指针路径；不进入剪贴板 fallback | UTF-16 单词定位测试；TextEdit 能力探针 | 已实现；应用兼容范围待完整矩阵 |
| TLP-FR-007 | capture 包含 term、sentence、URL、anchor、bundle ID | capture 纯函数与真实 TextEdit 探针 | 已实现 |
| TLP-FR-008 | 有界上下文与范围映射的 `NLTokenizer` 句子识别 | 重复词与 UTF-16 范围测试 | 已实现；失败时 sentence 为 nil |
| TLP-FR-009 | 沿 AX 父链尽力读取 `AXURL` | 静态代码审查 | 已实现；浏览器真实 URL 矩阵未完成 |
| TLP-FR-010 | Settings 授权状态、请求与系统设置入口 | 共享授权 adapter 静态审查 | 已实现；首次拒绝、撤销、恢复的人工矩阵未完成 |
| TLP-FR-011 | 单次 Copy、change count 保护、快照恢复 | 静态代码审查 | 已实现；Safari 真实兼容复制闭环未完成 |
| TLP-FR-012 | 单例 nonactivating NSPanel、Escape、外部鼠标关闭、屏幕定位 | 定位测试与 Slice 0 panel 探针 | 已实现；全屏/Space/外接显示器最终矩阵未完成 |
| TLP-FR-013 | term、原句、翻译、语言菜单、主词典 surface、建卡状态 | Session 与独立请求 gate 测试 | 已实现；长原句可局部滚动查看全文 |
| TLP-FR-014 | 显式指针捕获、释义、翻译与建卡的独立 section 状态 | 捕获状态重置、错误映射代码审查及 model 测试 | 已实现；系统模型下载与权限错误人工路径未完整验证 |
| TLP-FR-015 | 只使用 `FlashDictIntegrationKit` 主词典 lookup/surface | 乱序结果与 IntegrationKit 合同测试 | 已实现；真实 App Group lookup、CSS 资源和发音资源已通过 |
| TLP-FR-016 | 未运行状态、用户启动按钮、明确重试 | 静态代码审查 | 已实现；无自动启动、轮询或自动重连 |
| TLP-FR-017 | view-bound Apple `TranslationSession` 与本地 prepare/translate | request gate 与真实语言可用性探针 | 已实现；本机模型未安装，成功翻译/取消下载未闭环 |
| TLP-FR-018 | popup 语言菜单更新设置并只替换 translation request | 目标语言替换测试 | 已实现 |
| TLP-FR-019 | 首版不暴露第三方翻译接口、配置或凭据入口 | 静态边界检查 | 已实现；等待第一个真实 provider 进入排期后按实际 API 设计 |
| TLP-FR-020 | 冻结 `cardSeed`、新 delivery ID、sentence/URL context | 建卡上下文合同测试 | 已实现；未为验收向用户现有数据写入测试闪卡 |
| TLP-FR-021 | secure field 父链拒绝、默认/自定义排除应用 | 默认设置与静态路径审查 | 已实现；安全输入人工矩阵未完成 |
| TLP-FR-022 | 会话内存状态与 UserDefaults 非敏感设置 | 日志/持久化静态检查 | 已实现 |
| TLP-FR-023 | capture/session/dictionary/translation request gate 与 stop 取消 | 乱序失败、旧翻译、生命周期测试 | 已实现 |

## 3. Slice 完成定义审计

| Slice | 代码与自动化 | 真实证据 | 状态 |
| --- | --- | --- | --- |
| 0 系统能力探针 | AX、NSPanel、Escape、Translation 编译与 IntegrationKit 合同已探测 | TextEdit/Xcode 与真实 App Group 有证据；完整应用矩阵不足 | 部分闭环 |
| 1 生命周期与设置 | 已实现并独立提交 | 签名进程启动通过 | 闭环 |
| 2 触发与捕获 | 已实现并独立提交 | TextEdit/Xcode 通过；Safari 记录限制；其它应用不足 | 部分闭环 |
| 3 Panel 与会话 | 已实现并独立提交 | nonactivating probe 通过；全屏/多屏最终矩阵不足 | 部分闭环 |
| 4 FlashDict | 已实现并独立提交 | 当前源码服务端的 lookup、CSS 与音频跨进程通过；未写入测试卡 | 实施闭环，建卡待人工验收 |
| 5 Apple Translation | 已实现并独立提交 | 支持语言对已确认；模型未安装 | 部分闭环 |
| 6 兼容与收口 | 已实现并独立提交 | 完整应用、系统与设备矩阵不足 | 部分闭环 |

## 4. 剩余验收记录

以下项目不阻断 v0.1 实施完成，仅保留为发布或人工验收记录：

1. 本机有 2 个有效 Apple Development identity；尚未确认可用于最终直发的 Developer ID Application identity，因此分发签名、公证和 Gatekeeper 验证未完成。
2. 当前源码 FlashDict 已通过真实 App Group lookup、CSS 与音频请求；没有为了验收向用户现有数据写入测试闪卡。
3. Apple 英文到简体中文语言对受支持但模型未安装；没有替用户触发下载授权，成功翻译和取消下载路径未验收。
4. 当前没有外接显示器，且系统认证状态会阻止 UI Test Runner 初始化；全屏、Space、多显示器和完整应用矩阵没有充分人工证据。
5. 本轮尝试以 argument domain 启动 Release zbox 并用临时 TextEdit 文稿复验 panel；zbox 启动成功，但 TextEdit 对自身 AppleScript 与 System Events 都返回空窗口列表，无法安全定位测试内容。未生成截图，临时进程和文件均已清理。

这些项目不以单元测试、代码推断或旧 FlashDict 构建冒充通过，也不再作为代码实施的阻断项。
