# zbox UI 图册

[离线 HTML 图册](catalog.html) · [设计分析提示词](analysis-prompt.md) · [本轮设计与实现](design-review.md)

## 当前覆盖：H 批次补拍（2026-10-31 至 2026-11-01）

新增 **14 张（89–102）**，总计 **102 张**真实截图。H 批次使用 dev `2f41c6ae55fecb5a316ed765141276e671973a8d` 的临时采集构建，版本 1.0（1）。历史批次的数量与阻塞描述保留为当时记录；当前覆盖以本节及最新待补表为准。

工具通过临时普通菜单自行打开主搜索，补齐自动化参数/输出、音频面板、片段预览、网址参数、剪贴板预览、公开工作区、应用菜单结果、截图编辑/OCR 与交互式扩展。临时构建还在启动时展示主搜索、取消失焦隐藏，并为截图选择层增加窗口标题元数据；不据此验证正式焦点行为。

| 界面与源码说明 | 截图 |
| --- | --- |
| [自动化运行参数](89-capture-script-parameters.md) | [PNG](89-capture-script-parameters.png) |
| [自动化成功输出](90-capture-script-output.md) | [PNG](90-capture-script-output.png) |
| [音频控制面板](91-capture-audio-panel.md) | [PNG](91-capture-audio-panel.png) |
| [文本片段独立预览](92-capture-snippet-preview.md) | [PNG](92-capture-snippet-preview.png) |
| [快捷入口运行参数](93-capture-quicklink-parameter.md) | [PNG](93-capture-quicklink-parameter.png) |
| [剪贴板公开文本预览](94-capture-clipboard-preview.md) | [PNG](94-capture-clipboard-preview.png) |
| [截图权限提示](95-capture-screenshot-permission.md) | [PNG](95-capture-screenshot-permission.png) |
| [公开工作区窗口选择](96-capture-workspace-selection.md) | [PNG](96-capture-workspace-selection.png) |
| [公开工作区编辑](97-capture-workspace-editor.md) | [PNG](97-capture-workspace-editor.png) |
| [应用菜单搜索结果](98-capture-app-menu-results.md) | [PNG](98-capture-app-menu-results.png) |
| [截图编辑与裁剪](99-capture-screenshot-editor.md) | [PNG](99-capture-screenshot-editor.png) |
| [OCR 识别进行中](100-capture-ocr-processing.md) | [PNG](100-capture-ocr-processing.png) |
| [OCR 识别结果](101-capture-ocr-result.md) | [PNG](101-capture-ocr-result.png) |
| [交互式扩展列表与详情](102-capture-extension-interactive.md) | [PNG](102-capture-extension-interactive.png) |

本轮新增启用的快捷入口、片段、自动化、音频、工作区、应用菜单、取词、截图均已关闭并逐项回读；剪贴板记录已在公开样例采集后立即关闭。Hello 与 UI Catalog Text Case 均保留安装但停用。公开测试条目、两份文件及脚本保留供复拍。公开文本编辑窗口已关闭；未改变原文内容。

用户已授予 zbox 屏幕录制权限，实际截图和 OCR 已成功；该系统授权保留。未上传、切换音频/显示模式、恢复工作区布局、安装 HiDPI 配置或创建 FlashDict 卡片。固定输出脚本运行一次；交互式扩展仅打开初始界面，未读取选区或写剪贴板。系统剪贴板保留公开测试文本，未恢复未知的原始内容。

## 2026-10-31 临时采集构建补拍（F 批次）

新增 **14 张**（62–75），总计 **75 张**。覆盖主搜索默认与无匹配、开发工具五页（含 UUID 空/有内容状态）、内置计算器两种进制、剪贴板设置底部、显示器中部与底部、脚本表单底部。

用户授权临时取消主搜索 `windowDidResignKey` 的隐藏调用，并设置 `hidesOnDeactivate = false`。该临时构建经 macOS Debug build 后运行；F 批次均属于此构建。它不能验证正常版本的失焦关闭、焦点恢复或跨应用行为。主搜索透明背景在截图工具输出中呈灰色，不能替代桌面合成效果的观察。

工具全局快捷键仍未可靠唤起主搜索，用户协助打开主搜索及开发工具。后续由工具在搜索框输入 `hex` 并点击结果，成功进入内置计算器。期间用户反馈无法手动输入，原因未确认；工具已能输入、执行本地转换和操作计算器，但不据此宣称修复了手动输入问题。

所有公开转换样例均已清除，UUID 清回空列表，计算器清零并恢复十进制；没有复制结果、保存条目、启用插件、执行脚本、授予权限或上传内容。脚本空白表单已取消。

临时源代码已恢复为 HEAD 的原始实现；正常版本的重建和运行收尾见本页末尾。F 批次使用临时构建的事实保留在每张说明中。需要额外权限、测试数据或可信外部代码的分支仍按下方待补表处理。

## 2026-10-31 当前 dev 采集（E 批次）

已从远端拉取 `dev`，返回 Already up to date；HEAD 为 `2f41c6ae55fecb5a316ed765141276e671973a8d`。当前源码完成 macOS Debug build（版本 1.0，构建号 1），运行包 `/private/tmp/zbox-ui-capture-build/Build/Products/Debug/zbox.app`。本轮新增 **19 张**（43–61），覆盖全部 15 个设置入口和 4 个未保存表单；连同历史批次共 **61 张**。

当前系统为深色外观，未切换系统设置。运行进程路径已核对为本轮构建产物。原生应用控制已恢复，最初“原生 API 禁用”的阻塞已经解除；设置窗口可读取与截图，但主搜索面板在工具快捷键和用户手动打开后仍连接超时，尚未补拍本轮主搜索、计算器和开发工具。历史图不能替代本轮观察。

截图保留工具原始尺寸；工具输出 JPEG，使用 sips 实际转换为 PNG，未缩放。清除文件索引确认虽能读取控件，但截图全白；常用目录菜单截图遗漏弹层，均未保留或计入数量。清除确认已取消，未清除索引或添加目录。

本轮只启动应用、导航和取消空白表单；未修改产品代码、插件开关、权限、设备配置或系统外观，未保存条目、执行脚本、上传内容或读取剪贴板历史。关闭了设置窗口以尝试主搜索；Finder 导航到构建目录，未恢复其原导航位置。未运行单元测试或 UI 测试。

[当前源码候选入口与续采记录](current-source-inventory.md) · 下方“待准备或受阻”表列出其余条件。截图是界面资料，不等于所有功能或状态已验收。

## 版本与操作范围

采集日期：2026-10-30。应用版本：1.0，Debug，macOS 原生窗口。

运行包路径：`/private/tmp/zbox-audit-build/Build/Products/Debug/zbox.app`。采集时仓库 HEAD 为 `7ea914bd2f0bdbe6481654fb84c0e629c21e7362`，最终源码为该 HEAD 加本轮未提交 UI 改动。

A（01–15）：优化前。运行包没有 Git 版本标记，精确版本未知；代码摘录来自采集时 HEAD。
B（16–26）：首次设置核对，侧栏、筛选和空状态已经实施。
C（27–38）：主搜索、计算器、开发工具核对；32 记录未生效的场景修饰符，34–38 中的标签、空状态和图标随后修正。
D（39–42）：最终细节核对。39–41 确认开发工具细节和紧凑工具栏；42 确认窗口缩放。42 的运行包含临时窗口属性诊断，最终源码已移除日志，保留相同的有效时序修正。

截图保留原始分辨率。紫色窗口共享标记属于采集环境，不属于 zbox。只记录可见区域，未把截图当成功能验收。没有授予权限、启用采集、导入扩展、保存草稿、执行脚本或上传资料。公开样例只作本地转换，之后清除，没有复制结果；设置导航和窗口尺寸发生变化。

## 已采集（75 张：历史 42 张、E 批次 19 张、F 批次 14 张）

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

| E · 当前 dev 深色 | [通用设置](43-current-general.md) | [PNG](43-current-general.png) | 已截图 |
| E · 当前 dev 深色 | [快捷键设置](44-current-shortcuts.md) | [PNG](44-current-shortcuts.png) | 已截图 |
| E · 当前 dev 深色 | [扩展设置](45-current-extensions.md) | [PNG](45-current-extensions.png) | 已截图 |
| E · 当前 dev 深色 | [文件搜索设置](46-current-file-search.md) | [PNG](46-current-file-search.png) | 已截图 |
| E · 当前 dev 深色 | [快捷入口设置](47-current-quicklinks.md) | [PNG](47-current-quicklinks.png) | 已截图 |
| E · 当前 dev 深色 | [新增快捷入口表单](48-current-quicklink-editor.md) | [PNG](48-current-quicklink-editor.png) | 已截图 |
| E · 当前 dev 深色 | [文本片段设置](49-current-snippets.md) | [PNG](49-current-snippets.png) | 已截图 |
| E · 当前 dev 深色 | [新增文本片段表单](50-current-snippet-editor.md) | [PNG](50-current-snippet-editor.png) | 已截图 |
| E · 当前 dev 深色 | [剪贴板历史设置](51-current-clipboard-settings.md) | [PNG](51-current-clipboard-settings.png) | 已截图 |
| E · 当前 dev 深色 | [截图设置](52-current-screenshot-settings.md) | [PNG](52-current-screenshot-settings.png) | 已截图 |
| E · 当前 dev 深色 | [新增图床表单](53-current-hosting-editor.md) | [PNG](53-current-hosting-editor.png) | 已截图 |
| E · 当前 dev 深色 | [文本取词设置](54-current-text-lookup.md) | [PNG](54-current-text-lookup.png) | 已截图 |
| E · 当前 dev 深色 | [自动化设置](55-current-automation.md) | [PNG](55-current-automation.png) | 已截图 |
| E · 当前 dev 深色 | [新增脚本表单](56-current-script-editor.md) | [PNG](56-current-script-editor.png) | 已截图 |
| E · 当前 dev 深色 | [应用菜单设置](57-current-app-menu.md) | [PNG](57-current-app-menu.png) | 已截图 |
| E · 当前 dev 深色 | [音频设置](58-current-audio.md) | [PNG](58-current-audio.png) | 已截图 |
| E · 当前 dev 深色 | [显示器设置](59-current-display.md) | [PNG](59-current-display.png) | 已截图 |
| E · 当前 dev 深色 | [工作区设置](60-current-workspace.md) | [PNG](60-current-workspace.png) | 已截图 |
| E · 当前 dev 深色 | [窗口管理设置](61-current-window-management.md) | [PNG](61-current-window-management.png) | 已截图 |

| F · 临时采集构建 | [主搜索默认结果（临时采集构建）](62-capture-root-default.md) | [PNG](62-capture-root-default.png) | 已截图 |
| F · 临时采集构建 | [主搜索无匹配（临时采集构建）](63-capture-root-empty.md) | [PNG](63-capture-root-empty.png) | 已截图 |
| F · 临时采集构建 | [JSON 格式化结果](64-capture-developer-json.md) | [PNG](64-capture-developer-json.png) | 已截图 |
| F · 临时采集构建 | [时间戳转换结果](65-capture-timestamp-result.md) | [PNG](65-capture-timestamp-result.png) | 已截图 |
| F · 临时采集构建 | [UUID 空状态](66-capture-uuid-empty.md) | [PNG](66-capture-uuid-empty.png) | 已截图 |
| F · 临时采集构建 | [UUID 生成结果](67-capture-uuid-result.md) | [PNG](67-capture-uuid-result.png) | 已截图 |
| F · 临时采集构建 | [URL 编码结果](68-capture-url-result.md) | [PNG](68-capture-url-result.png) | 已截图 |
| F · 临时采集构建 | [Base64 编码结果](69-capture-base64-result.md) | [PNG](69-capture-base64-result.png) | 已截图 |
| F · 临时采集构建 | [剪贴板历史设置底部](70-capture-clipboard-bottom.md) | [PNG](70-capture-clipboard-bottom.png) | 已截图 |
| F · 临时采集构建 | [显示器设置中部](71-capture-display-middle.md) | [PNG](71-capture-display-middle.png) | 已截图 |
| F · 临时采集构建 | [显示器设置底部](72-capture-display-bottom.md) | [PNG](72-capture-display-bottom.png) | 已截图 |
| F · 临时采集构建 | [脚本表单底部](73-capture-script-editor-bottom.md) | [PNG](73-capture-script-editor-bottom.png) | 已截图 |
| F · 临时采集构建 | [内置计算器十进制初始状态](74-capture-calculator-decimal.md) | [PNG](74-capture-calculator-decimal.png) | 已截图 |
| F · 临时采集构建 | [内置计算器十六进制结果](75-capture-calculator-hex.md) | [PNG](75-capture-calculator-hex.png) | 已截图 |

## G 批次增量采集（入口受阻，已收尾）

2026-10-31，正常 dev `2f41c6a`、1.0（1），新增 76–88 共 13 张，当前总计 88 张。已授权创建公开测试条目并在结束后关闭本轮启用功能。

| 说明 | 截图 |
| --- | --- |
| [文本片段编辑（公开样例）](76-capture-snippet-filled.md) | [PNG](76-capture-snippet-filled.png) |
| [文本片段有内容列表](77-capture-snippet-list.md) | [PNG](77-capture-snippet-list.png) |
| [带参数的网址编辑](78-capture-quicklink-filled.md) | [PNG](78-capture-quicklink-filled.png) |
| [显示预设编辑](79-capture-display-preset.md) | [PNG](79-capture-display-preset.png) |
| [HiDPI 配置表单](80-capture-hidpi-editor.md) | [PNG](80-capture-hidpi-editor.png) |
| [扩展安装确认](81-capture-extension-install.md) | [PNG](81-capture-extension-install.png) |
| [已安装扩展列表](82-capture-extension-installed.md) | [PNG](82-capture-extension-installed.png) |
| [扩展偏好设置](83-capture-extension-preferences.md) | [PNG](83-capture-extension-preferences.png) |

| [文件搜索结果列表](84-capture-file-results.md) | [PNG](84-capture-file-results.png) |
| [文件搜索扩展名筛选](85-capture-file-filter.md) | [PNG](85-capture-file-filter.png) |
| [公开文本文件 Quick Look](86-capture-file-quicklook.md) | [PNG](86-capture-file-quicklook.png) |

| [Hello 扩展运行参数](87-capture-extension-parameter.md) | [PNG](87-capture-extension-parameter.png) |

| [Hello 扩展成功输出](88-capture-extension-output.md) | [PNG](88-capture-extension-output.png) |

当前已准备：文件搜索仅索引 fixtures/files 中两份公开文件；UI Catalog 示例片段、参数网址、固定输出脚本和当前显示预设已保存。Hello 示例经单独确认安装。文件搜索、文本片段、快捷入口、自动化、音频、显示器均已关闭并回读确认；Hello 保留安装但已停用。工作区已恢复关闭，未保存布局或截图（表单包含个人窗口标题）。没有切换音频设备、显示模式，未安装 HiDPI 配置。

扩展安装确认、列表及偏好页已补齐；参数及成功输出已在 87–88 补齐。工具发送全局快捷键未触发主搜索，文件搜索结果、扩展名筛选及 Quick Look 已补齐，操作菜单浮层仍未进入截图。Hello 已运行完成并关闭。全局快捷键无法由工具触发，菜单也没有其他工具入口；剩余独立窗口待控制入口可用后补拍。以下旧待补表结合本段阅读。

## 仅定位源码 / 待准备或受阻（截至 H 批次）

未截图不等于功能缺失。主搜索、设置、主要独立工具及扩展的当前覆盖见 E–H 批次；以下仍未取得有效截图。

| 界面 | 源码 | 具体限制 |
| --- | --- | --- |
| 取词浮窗、查词/翻译/建卡反馈 | `zbox/Plugins/TextLookup/Presentation/TextLookupPanelView.swift` | 已启用且辅助功能已授权，在公开 TextEdit 文档选中 public 后仍未捕获浮窗；原因未确认。未准备翻译模型或创建卡片。 |
| 贴图、滚动截图会话 | `zbox/Plugins/Screenshot/Pins/ScreenshotPinController.swift`、`zbox/Plugins/Screenshot/Capture/` | 编辑器中贴图按钮调用后，工具仍绑定编辑器，未获得可确认的贴图截图；滚动会话未完成采集。编辑器及 OCR 已补齐，非权限阻塞。 |
| 图床上传/结果/失败重试 | `zbox/Plugins/Screenshot/Editor/ScreenshotEditorView.swift` | 无测试图床配置；未上传，设置与空白配置表单已有截图。 |
| 菜单栏菜单、文件操作浮层、清除/删除确认 | `zbox/App/MenuBarView.swift`、`zbox/Plugins/FileSearch/FileSearchView.swift` | 部分弹层截图遗漏或全白；不计入覆盖。未执行清除或删除。 |
| Apple 快捷指令选择 | `zbox/Plugins/ScriptCommands/ScriptCommandsSettingsView.swift` | 未提供测试快捷指令，未读取个人列表；脚本参数及输出已补齐。 |
| 命令错误、显示切换确认、工作区恢复映射 | `zbox/Search/CommandFeedbackView.swift`、`zbox/Plugins/Workspace/WorkspaceSettingsView.swift` | 未人为制造错误，未执行授权范围外的设备切换或布局恢复。 |
| 长英文与完整键盘焦点顺序 | `zbox/Settings/SettingsView.swift` | 当前以中文深色实际窗口为主，未完整核对焦点或改变系统语言/外观。 |

## 验证

PNG 格式、同名说明配对、源码路径、行号、内嵌图片数与 HTML 锚点做结构核对。代码摘录仅用于导航，完整项目执行 macOS build；未运行单元测试或 UI 测试。离线 HTML 已在 Safari 核对搜索计数、无匹配、代码展开、截图放大和 Escape 退出。新版 UI 核对状态见设计记录。

### E 批次验证补充

19 张新增图均已逐张查看后保存，并从工具 JPEG 实际转为 PNG；61 张 PNG/同名说明配对、HTML 内嵌数量、唯一锚点与新增源码路径/行号核对通过。图册约 18.55 MiB，未压缩尺寸。HTML 内联脚本做语法检查；本轮浏览器拒绝 file 协议，未完成新版图册视觉及交互预览，不沿用历史图册的预览结论。

### F 批次恢复与验证

采集结束后已删除 `hidesOnDeactivate = false`，并恢复 `windowDidResignKey` 中的 `hide()`；`git diff --exit-code -- zbox/Platform/SearchPanelController.swift` 通过，产品源码没有残留修改。正常版本重新执行 macOS Debug build 成功。临时实例通过应用退出命令结束，进程检查确认退出；随后从 Finder 启动同一路径下恢复后的构建，确认新进程运行。

正常失焦行为及用户报告的手动输入问题未做人工复验，不以源码恢复或工具输入成功代替该验证。未运行单元测试或 UI 测试。新增 14 张逐张观察、PNG 转换与说明配对已核对；HTML 结构和脚本语法检查通过，浏览器本地文件协议限制仍在，未重复绕行尝试视觉预览。

### G 批次最终收尾

新增 76–88 共 13 张，总计 88 张。文件搜索结果、扩展名筛选和 Quick Look，以及 Hello 安装、偏好、参数和成功输出均已补齐，旧待补表中对应内容以本段为准。操作菜单浮层未进入截图。显示预设和 HiDPI 表单已补齐，未应用显示模式或安装配置。

六项临时功能开关及 Hello 已关闭并回读确认，工作区此前已恢复关闭。公开 UI Catalog 条目和 fixtures 保留供复拍。固定输出脚本尚未运行，参数网址未打开；未启用剪贴板记录、取词或截图，未增加系统权限。工作区表单包含个人窗口标题，未保存截图。

剩余主要缺口：片段独立预览、快捷入口运行参数、自动化运行、音频面板、截图编辑/OCR/贴图、取词浮窗、剪贴板列表、交互式扩展、公开环境下的工作区表单。此次未完成全部主要界面，不再要求用户逐个代操作。

88 份 PNG/同名说明及 HTML 内嵌数量、唯一锚点和脚本语法检查通过。产品源码无改动；本批未构建、未运行单元或 UI 测试。浏览器策略限制仍导致 HTML 视觉预览未完成。

### H 批次恢复与验证

四处临时源码（应用菜单、启动展示、主搜索失焦、截图选择层标题）均已撤销，`git diff --exit-code -- zbox` 通过。正常版本 macOS Debug build 成功；临时实例已退出，并通过 Finder 启动恢复后的构建。功能开关逐项回读确认关闭，公开测试数据与授权范围见本页开头。正常版本手动输入、全局快捷键和失焦行为未做人工复验。

新增14张保留原始尺寸并转换为真实PNG；102份PNG/同名说明配对、内嵌图片数、唯一锚点、源码路径/行号及HTML脚本语法做结构检查。未运行单元测试或UI测试。浏览器本地文件策略仍限制图册视觉预览，未绕过。
