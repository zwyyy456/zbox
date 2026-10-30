# zbox UI 图册

[离线 HTML 图册](catalog.html) · [设计分析提示词](analysis-prompt.md) · [本轮设计与实现](design-review.md)

## 版本与操作范围

采集日期：2026-10-30。应用版本：1.0，Debug，macOS 原生窗口。

运行包路径：`/private/tmp/zbox-audit-build/Build/Products/Debug/zbox.app`。采集时仓库 HEAD 为 `7ea914bd2f0bdbe6481654fb84c0e629c21e7362`，最终源码为该 HEAD 加本轮未提交 UI 改动。

A（01–15）：优化前。运行包没有 Git 版本标记，精确版本未知；代码摘录来自采集时 HEAD。
B（16–26）：首次设置核对，侧栏、筛选和空状态已经实施。
C（27–38）：主搜索、计算器、开发工具核对；32 记录未生效的场景修饰符，34–38 中的标签、空状态和图标随后修正。
D（39–42）：最终细节核对。39–41 确认开发工具细节和紧凑工具栏；42 确认窗口缩放。42 的运行包含临时窗口属性诊断，最终源码已移除日志，保留相同的有效时序修正。

截图保留原始分辨率。紫色窗口共享标记属于采集环境，不属于 zbox。只记录可见区域，未把截图当成功能验收。没有授予权限、启用采集、导入扩展、保存草稿、执行脚本或上传资料。公开样例只作本地转换，之后清除，没有复制结果；设置导航和窗口尺寸发生变化。

## 已采集（42 张）

| 批次 | 界面说明 | 截图 | 状态 |
| --- | --- | --- | --- |
| A · 改动前 | [通用设置](01-before-general.md) | [PNG](01-before-general.png) | 已截图 |
| A · 改动前 | [快捷键设置](02-before-shortcuts.md) | [PNG](02-before-shortcuts.png) | 已截图 |
| A · 改动前 | [扩展设置](03-before-extensions.md) | [PNG](03-before-extensions.png) | 已截图 |
| A · 改动前 | [自动化设置](04-before-automation.md) | [PNG](04-before-automation.png) | 已截图 |
| A · 改动前 | [新增脚本表单](05-before-script-editor.md) | [PNG](05-before-script-editor.png) | 已截图 |
| A · 改动前 | [文件搜索设置](06-before-file-search-settings.md) | [PNG](06-before-file-search-settings.png) | 已截图 |
| A · 改动前 | [文本片段设置](07-before-snippets-settings.md) | [PNG](07-before-snippets-settings.png) | 已截图 |
| A · 改动前 | [新增文本片段](08-before-snippet-editor.md) | [PNG](08-before-snippet-editor.png) | 已截图 |
| A · 改动前 | [快捷入口设置](09-before-quicklinks-settings.md) | [PNG](09-before-quicklinks-settings.png) | 已截图 |
| A · 改动前 | [新增快捷入口](10-before-quicklink-editor.md) | [PNG](10-before-quicklink-editor.png) | 已截图 |
| A · 改动前 | [应用菜单设置](11-before-app-menu-settings.md) | [PNG](11-before-app-menu-settings.png) | 已截图 |
| A · 改动前 | [音频设置](12-before-audio-settings.md) | [PNG](12-before-audio-settings.png) | 已截图 |
| A · 改动前 | [显示器设置](13-before-display-settings.md) | [PNG](13-before-display-settings.png) | 已截图 |
| A · 改动前 | [工作区设置](14-before-workspace-settings.md) | [PNG](14-before-workspace-settings.png) | 已截图 |
| A · 改动前 | [窗口管理设置](15-before-window-management-settings.md) | [PNG](15-before-window-management-settings.png) | 已截图 |
| B · 首次设置核对 | [新版通用与分组侧栏](16-after-general.md) | [PNG](16-after-general.png) | 已截图 |
| B · 首次设置核对 | [快捷键筛选结果](17-after-shortcuts-filter.md) | [PNG](17-after-shortcuts-filter.png) | 已截图 |
| B · 首次设置核对 | [快捷键无匹配](18-after-shortcuts-empty.md) | [PNG](18-after-shortcuts-empty.png) | 已截图 |
| B · 首次设置核对 | [新版扩展空状态](19-after-extensions.md) | [PNG](19-after-extensions.png) | 已截图 |
| B · 首次设置核对 | [新版快捷入口空状态](20-after-quicklinks.md) | [PNG](20-after-quicklinks.png) | 已截图 |
| B · 首次设置核对 | [新版文本片段空状态](21-after-snippets.md) | [PNG](21-after-snippets.png) | 已截图 |
| B · 首次设置核对 | [剪贴板历史设置](22-after-clipboard-settings.md) | [PNG](22-after-clipboard-settings.png) | 已截图 |
| B · 首次设置核对 | [截图设置](23-after-screenshot-settings.md) | [PNG](23-after-screenshot-settings.png) | 已截图 |
| B · 首次设置核对 | [新增图床表单](24-after-hosting-editor.md) | [PNG](24-after-hosting-editor.png) | 已截图 |
| B · 首次设置核对 | [文本取词设置](25-after-text-lookup-settings.md) | [PNG](25-after-text-lookup-settings.png) | 已截图 |
| B · 首次设置核对 | [新版自动化空状态](26-after-automation.md) | [PNG](26-after-automation.png) | 已截图 |
| C · 主搜索与工具核对 | [主搜索默认结果](27-after-root-search.md) | [PNG](27-after-root-search.png) | 已截图 |
| C · 主搜索与工具核对 | [主搜索键盘滚动](28-after-root-selection.md) | [PNG](28-after-root-selection.png) | 已截图 |
| C · 主搜索与工具核对 | [主搜索无匹配](29-after-root-empty.md) | [PNG](29-after-root-empty.png) | 已截图 |
| C · 主搜索与工具核对 | [计算器十进制模式](30-after-calculator.md) | [PNG](30-after-calculator.png) | 已截图 |
| C · 主搜索与工具核对 | [计算器十六进制结果](31-after-calculator-hex.md) | [PNG](31-after-calculator-hex.png) | 已截图 |
| C · 主搜索与工具核对 | [设置场景修饰符未生效](32-after-settings-compact.md) | [PNG](32-after-settings-compact.png) | 已截图 |
| C · 主搜索与工具核对 | [JSON 格式化结果](33-after-developer-json.md) | [PNG](33-after-developer-json.png) | 已截图 |
| C · 主搜索与工具核对 | [时间戳空输入](34-after-developer-timestamp.md) | [PNG](34-after-developer-timestamp.png) | 已截图 |
| C · 主搜索与工具核对 | [时间戳结果](35-after-timestamp-result.md) | [PNG](35-after-timestamp-result.png) | 已截图 |
| C · 主搜索与工具核对 | [UUID 空列表（补正前）](36-after-developer-uuid.md) | [PNG](36-after-developer-uuid.png) | 已截图 |
| C · 主搜索与工具核对 | [URL 编码结果](37-after-developer-url.md) | [PNG](37-after-developer-url.png) | 已截图 |
| C · 主搜索与工具核对 | [Base64 编码结果（图标补正前）](38-after-developer-base64.md) | [PNG](38-after-developer-base64.png) | 已截图 |
| D · 最终修正核对 | [UUID 最终空状态与侧栏图标](39-final-uuid-empty.md) | [PNG](39-final-uuid-empty.png) | 已截图 |
| D · 最终修正核对 | [时间戳最终输入标签](40-final-timestamp-label.md) | [PNG](40-final-timestamp-label.png) | 已截图 |
| D · 最终修正核对 | [设置最终紧凑工具栏](41-final-settings-window.md) | [PNG](41-final-settings-window.png) | 已截图 |
| D · 最终修正核对 | [设置窗口缩放确认](42-final-settings-resizable.md) | [PNG](42-final-settings-resizable.png) | 已截图 |

## 仅定位源码 / 待准备或受阻

下表所列运行状态未计入截图覆盖；截图设置和空白图床表单已拍摄，编辑、OCR、上传等运行状态仍未覆盖。下表是下一轮补拍入口，不表示对应功能缺失或有缺陷。

| 界面 | 源码 | 条件或限制 |
| --- | --- | --- |
| 命令错误与恢复反馈 | `zbox/Search/CommandFeedbackView.swift` | 尚未采集，不人为撤销权限或执行会影响系统的命令以制造错误。 |
| 菜单栏菜单 | `zbox/App/MenuBarView.swift` | 后台应用未显示窗口时，工具无法绑定；需正常展开菜单后补拍。 |
| 文件搜索结果、筛选、操作菜单和 Quick Look | `zbox/Plugins/FileSearch/FileSearchView.swift` | 需用户启用并选择无敏感内容的测试目录；不自动索引个人目录。 |
| 文本片段列表预览与删除确认 | `zbox/Plugins/Snippets/SnippetsView.swift` | 需启用功能并准备公开示例片段；确认弹窗可取消，不执行删除。 |
| 快捷入口参数表单 | `zbox/Plugins/Quicklinks/QuicklinkParameterView.swift` | 需已启用的测试参数 URL，例如公开搜索网址，不提交导航。 |
| 自动化参数、输出、Apple 快捷指令选择 | `zbox/Plugins/ScriptCommands/ScriptCommandsSettingsView.swift` | 需用户选定可信的无副作用脚本/测试快捷指令。未读取个人快捷指令列表。 |
| 外部扩展安装确认、偏好与运行会话 | `zbox/ExternalExtensions/ExtensionSessionView.swift` | 需可信样例扩展及明确安装授权；未安装或运行未知代码。 |
| 剪贴板历史、过滤、预览与清空确认 | `zbox/Plugins/ClipboardHistory/ClipboardHistoryView.swift` | 需用户启用采集并准备公开测试内容；不读取个人剪贴板历史。 |
| 截图编辑、OCR、滚动截图、贴图与图床配置 | `zbox/Plugins/Screenshot/Editor/ScreenshotEditorView.swift` | 需屏幕录制权限和非敏感截图；图床需测试配置，不上传或展示凭据。 |
| 取词浮窗、查词、翻译与建卡反馈 | `zbox/Plugins/TextLookup/Presentation/TextLookupPanelView.swift` | 需启用功能、辅助功能权限、公开样本文本；翻译模型及 FlashDict 条件待准备，不创建个人卡片。 |
| 音频设备控制、显示模式确认与 HiDPI、工作区保存恢复 | `zbox/Plugins/Display/DisplaySettingsView.swift` | 需用户启用对应功能和授权；模式切换、管理员配置、移动窗口会影响当前桌面，未执行。 |
| 深色外观、长英文文案及完整键盘焦点顺序 | `zbox/Settings/SettingsView.swift` | 中文默认尺寸与调整宽度后的布局已核对；深色、长英文与完整焦点顺序尚未核对，未修改系统外观。 |

## 验证

PNG 格式、同名说明配对、源码路径、行号、内嵌图片数与 HTML 锚点做结构核对。代码摘录仅用于导航，完整项目执行 macOS build；未运行单元测试或 UI 测试。离线 HTML 已在 Safari 核对搜索计数、无匹配、代码展开、截图放大和 Escape 退出。新版 UI 核对状态见设计记录。
