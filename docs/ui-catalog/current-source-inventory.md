# 当前 UI 源码入口与采集阻塞记录

日期：2026-10-31。源码版本：`2f41c6ae55fecb5a316ed765141276e671973a8d`。本轮开始时工作区干净。

## 本轮结果

截至 F 批次，现有 75 张截图及配套说明：A–D 历史 42 张、E 正常构建 19 张、F 临时放宽主搜索失焦关闭的构建 14 张。原生控制和主搜索绑定阻塞已通过环境恢复及用户授权的临时行为调整取得进展，主搜索、计算器、开发工具和长设置页下部均已补拍。

临时源码已恢复。版本、构建验证和运行收尾以 [索引](index.md) 为准。仍未覆盖需启用插件、可信样例、账号/服务或额外权限的界面，以及截图工具遗漏的菜单弹层、清除确认。用户手动输入问题尚未诊断，不能据工具输入成功认定手动输入正常。

## 源码候选入口

下表由当前源码中的 SwiftUI View、NSView、弹窗与菜单声明定位。它包含嵌套组件，不能按行数当作独立页面数量；尚未逐一运行确认，也不保证覆盖动态扩展生成的所有界面。历史截图覆盖仍以 [索引](index.md) 为准。

采集时将根界面、主要内容状态、菜单及弹窗分别观察。特别补查原待补表未单列的 Finder 选中文件、开发工具切换确认、扩展任务输出、工作区捕获与显示器映射、滚动截图控制、贴图菜单，以及各系统打开/保存面板。不要为触发状态执行删除、上传、系统模式切换或未知脚本。

| 视图或呈现入口（仅定位源码） | 源码位置 |
| --- | --- |
| `MenuBarView` | [zbox/App/MenuBarView.swift:4](../../zbox/App/MenuBarView.swift#L4) |
| `ExtensionPreferencesView` | [zbox/ExternalExtensions/ExtensionPreferencesView.swift:3](../../zbox/ExternalExtensions/ExtensionPreferencesView.swift#L3) |
| `ExtensionSessionView` | [zbox/ExternalExtensions/ExtensionSessionView.swift:4](../../zbox/ExternalExtensions/ExtensionSessionView.swift#L4) |
| `.confirmationDialog(confirming?.title ?? "Confirm", isPresented: Binding(get: ` | [zbox/ExternalExtensions/ExtensionSessionView.swift:65](../../zbox/ExternalExtensions/ExtensionSessionView.swift#L65) |
| `ExtensionSettingsView` | [zbox/ExternalExtensions/ExtensionSettingsView.swift:3](../../zbox/ExternalExtensions/ExtensionSettingsView.swift#L3) |
| `.sheet(item: Binding(get: ` | [zbox/ExternalExtensions/ExtensionSettingsView.swift:40](../../zbox/ExternalExtensions/ExtensionSettingsView.swift#L40) |
| `.sheet(item: $editing) ` | [zbox/ExternalExtensions/ExtensionSettingsView.swift:56](../../zbox/ExternalExtensions/ExtensionSettingsView.swift#L56) |
| `.sheet(item: $removing) ` | [zbox/ExternalExtensions/ExtensionSettingsView.swift:57](../../zbox/ExternalExtensions/ExtensionSettingsView.swift#L57) |
| `let panel = NSOpenPanel()` | [zbox/ExternalExtensions/ExtensionSettingsView.swift:74](../../zbox/ExternalExtensions/ExtensionSettingsView.swift#L74) |
| `ExtensionTaskView` | [zbox/ExternalExtensions/ExtensionTaskSession.swift:66](../../zbox/ExternalExtensions/ExtensionTaskSession.swift#L66) |
| `AppMenuView` | [zbox/Plugins/AppMenu/AppMenuPlugin.swift:123](../../zbox/Plugins/AppMenu/AppMenuPlugin.swift#L123) |
| `AppMenuSettingsView` | [zbox/Plugins/AppMenu/AppMenuPlugin.swift:152](../../zbox/Plugins/AppMenu/AppMenuPlugin.swift#L152) |
| `AudioControlView` | [zbox/Plugins/Audio/AudioPlugin.swift:116](../../zbox/Plugins/Audio/AudioPlugin.swift#L116) |
| `AudioSettingsView` | [zbox/Plugins/Audio/AudioPlugin.swift:170](../../zbox/Plugins/Audio/AudioPlugin.swift#L170) |
| `CalculatorView` | [zbox/Plugins/Calculator/Presentation/CalculatorView.swift:3](../../zbox/Plugins/Calculator/Presentation/CalculatorView.swift#L3) |
| `let picker = NSOpenPanel()` | [zbox/Plugins/ClipboardHistory/ClipboardHistoryPlugin.swift:163](../../zbox/Plugins/ClipboardHistory/ClipboardHistoryPlugin.swift#L163) |
| `ClipboardHistoryView` | [zbox/Plugins/ClipboardHistory/ClipboardHistoryView.swift:3](../../zbox/Plugins/ClipboardHistory/ClipboardHistoryView.swift#L3) |
| `ClipboardHistorySettingsView` | [zbox/Plugins/ClipboardHistory/ClipboardHistoryView.swift:73](../../zbox/Plugins/ClipboardHistory/ClipboardHistoryView.swift#L73) |
| `.confirmationDialog("Delete all clipboard history, including pinned items?", isPresented: $confirmsClear) ` | [zbox/Plugins/ClipboardHistory/ClipboardHistoryView.swift:110](../../zbox/Plugins/ClipboardHistory/ClipboardHistoryView.swift#L110) |
| `DeveloperTextToolView` | [zbox/Plugins/DeveloperTools/DeveloperTextToolView.swift:3](../../zbox/Plugins/DeveloperTools/DeveloperTextToolView.swift#L3) |
| `DeveloperTimestampView` | [zbox/Plugins/DeveloperTools/DeveloperTimestampView.swift:3](../../zbox/Plugins/DeveloperTools/DeveloperTimestampView.swift#L3) |
| `DeveloperToolsView` | [zbox/Plugins/DeveloperTools/DeveloperToolsView.swift:3](../../zbox/Plugins/DeveloperTools/DeveloperToolsView.swift#L3) |
| `.sheet(isPresented: Binding(get: ` | [zbox/Plugins/DeveloperTools/DeveloperToolsView.swift:30](../../zbox/Plugins/DeveloperTools/DeveloperToolsView.swift#L30) |
| `DisplayHiDPIEditor` | [zbox/Plugins/Display/DisplayHiDPIEditor.swift:3](../../zbox/Plugins/Display/DisplayHiDPIEditor.swift#L3) |
| `DisplaySettingsView` | [zbox/Plugins/Display/DisplaySettingsView.swift:3](../../zbox/Plugins/Display/DisplaySettingsView.swift#L3) |
| `.sheet(item: $configuringHiDPI) ` | [zbox/Plugins/Display/DisplaySettingsView.swift:89](../../zbox/Plugins/Display/DisplaySettingsView.swift#L89) |
| `.confirmationDialog("Remove this zbox display override?", isPresented: Binding(` | [zbox/Plugins/Display/DisplaySettingsView.swift:92](../../zbox/Plugins/Display/DisplaySettingsView.swift#L92) |
| `.sheet(item: $editingPreset) ` | [zbox/Plugins/Display/DisplaySettingsView.swift:103](../../zbox/Plugins/Display/DisplaySettingsView.swift#L103) |
| `DisplayModePicker` | [zbox/Plugins/Display/DisplaySettingsView.swift:109](../../zbox/Plugins/Display/DisplaySettingsView.swift#L109) |
| `DisplayPresetEditor` | [zbox/Plugins/Display/DisplaySettingsView.swift:144](../../zbox/Plugins/Display/DisplaySettingsView.swift#L144) |
| `let panel = NSOpenPanel()` | [zbox/Plugins/FileSearch/FileSearchPlugin.swift:233](../../zbox/Plugins/FileSearch/FileSearchPlugin.swift#L233) |
| `let panel = NSOpenPanel()` | [zbox/Plugins/FileSearch/FileSearchPlugin.swift:246](../../zbox/Plugins/FileSearch/FileSearchPlugin.swift#L246) |
| `FileSearchSettingsView` | [zbox/Plugins/FileSearch/FileSearchSettingsView.swift:3](../../zbox/Plugins/FileSearch/FileSearchSettingsView.swift#L3) |
| `Menu("Add Common Folder") ` | [zbox/Plugins/FileSearch/FileSearchSettingsView.swift:38](../../zbox/Plugins/FileSearch/FileSearchSettingsView.swift#L38) |
| `.alert("Clear File Index?", isPresented: $clearing) ` | [zbox/Plugins/FileSearch/FileSearchSettingsView.swift:50](../../zbox/Plugins/FileSearch/FileSearchSettingsView.swift#L50) |
| `FileSearchView` | [zbox/Plugins/FileSearch/FileSearchView.swift:3](../../zbox/Plugins/FileSearch/FileSearchView.swift#L3) |
| `.contextMenu ` | [zbox/Plugins/FileSearch/FileSearchView.swift:44](../../zbox/Plugins/FileSearch/FileSearchView.swift#L44) |
| `Menu("Actions") ` | [zbox/Plugins/FileSearch/FileSearchView.swift:59](../../zbox/Plugins/FileSearch/FileSearchView.swift#L59) |
| `FinderSelectionView` | [zbox/Plugins/FileSearch/FileSearchView.swift:111](../../zbox/Plugins/FileSearch/FileSearchView.swift#L111) |
| `QuicklinkParameterView` | [zbox/Plugins/Quicklinks/QuicklinkParameterView.swift:3](../../zbox/Plugins/Quicklinks/QuicklinkParameterView.swift#L3) |
| `QuicklinksSettingsView` | [zbox/Plugins/Quicklinks/QuicklinksSettingsView.swift:3](../../zbox/Plugins/Quicklinks/QuicklinksSettingsView.swift#L3) |
| `.sheet(item: $editing) ` | [zbox/Plugins/Quicklinks/QuicklinksSettingsView.swift:42](../../zbox/Plugins/Quicklinks/QuicklinksSettingsView.swift#L42) |
| `QuicklinkEditor` | [zbox/Plugins/Quicklinks/QuicklinksSettingsView.swift:48](../../zbox/Plugins/Quicklinks/QuicklinksSettingsView.swift#L48) |
| `let panel = NSOpenPanel()` | [zbox/Plugins/Quicklinks/QuicklinksSettingsView.swift:72](../../zbox/Plugins/Quicklinks/QuicklinksSettingsView.swift#L72) |
| `ScreenshotSelectionView` | [zbox/Plugins/Screenshot/Capture/ScreenshotSelection.swift:56](../../zbox/Plugins/Screenshot/Capture/ScreenshotSelection.swift#L56) |
| `ScreenshotCanvasView` | [zbox/Plugins/Screenshot/Editor/ScreenshotCanvas.swift:16](../../zbox/Plugins/Screenshot/Editor/ScreenshotCanvas.swift#L16) |
| `ScreenshotEditorView` | [zbox/Plugins/Screenshot/Editor/ScreenshotEditorView.swift:3](../../zbox/Plugins/Screenshot/Editor/ScreenshotEditorView.swift#L3) |
| `ScreenshotDocumentView` | [zbox/Plugins/Screenshot/Editor/ScreenshotEditorView.swift:62](../../zbox/Plugins/Screenshot/Editor/ScreenshotEditorView.swift#L62) |
| `ScreenshotOCRView` | [zbox/Plugins/Screenshot/OCR/ScreenshotOCRView.swift:3](../../zbox/Plugins/Screenshot/OCR/ScreenshotOCRView.swift#L3) |
| `let panel = NSSavePanel()` | [zbox/Plugins/Screenshot/Pins/ScreenshotPinController.swift:93](../../zbox/Plugins/Screenshot/Pins/ScreenshotPinController.swift#L93) |
| `ScreenshotPinView` | [zbox/Plugins/Screenshot/Pins/ScreenshotPinController.swift:131](../../zbox/Plugins/Screenshot/Pins/ScreenshotPinController.swift#L131) |
| `Menu("Image Actions", systemImage: "ellipsis") ` | [zbox/Plugins/Screenshot/Pins/ScreenshotPinController.swift:143](../../zbox/Plugins/Screenshot/Pins/ScreenshotPinController.swift#L143) |
| `.contextMenu ` | [zbox/Plugins/Screenshot/Pins/ScreenshotPinController.swift:152](../../zbox/Plugins/Screenshot/Pins/ScreenshotPinController.swift#L152) |
| `Menu("Opacity") ` | [zbox/Plugins/Screenshot/Pins/ScreenshotPinController.swift:164](../../zbox/Plugins/Screenshot/Pins/ScreenshotPinController.swift#L164) |
| `let panel = NSSavePanel()` | [zbox/Plugins/Screenshot/ScreenshotPlugin.swift:213](../../zbox/Plugins/Screenshot/ScreenshotPlugin.swift#L213) |
| `ScreenshotScrollView` | [zbox/Plugins/Screenshot/Scrolling/ScreenshotScrollSession.swift:137](../../zbox/Plugins/Screenshot/Scrolling/ScreenshotScrollSession.swift#L137) |
| `ScreenshotHostingView` | [zbox/Plugins/Screenshot/Settings/ScreenshotHostingView.swift:3](../../zbox/Plugins/Screenshot/Settings/ScreenshotHostingView.swift#L3) |
| `.sheet(item: $editing) ` | [zbox/Plugins/Screenshot/Settings/ScreenshotHostingView.swift:43](../../zbox/Plugins/Screenshot/Settings/ScreenshotHostingView.swift#L43) |
| `.confirmationDialog("Remove this image host and its saved credentials?", isPresented: $confirmsDelete) ` | [zbox/Plugins/Screenshot/Settings/ScreenshotHostingView.swift:44](../../zbox/Plugins/Screenshot/Settings/ScreenshotHostingView.swift#L44) |
| `ScreenshotHostEditor` | [zbox/Plugins/Screenshot/Settings/ScreenshotHostingView.swift:54](../../zbox/Plugins/Screenshot/Settings/ScreenshotHostingView.swift#L54) |
| `ScreenshotSettingsView` | [zbox/Plugins/Screenshot/Settings/ScreenshotSettingsView.swift:3](../../zbox/Plugins/Screenshot/Settings/ScreenshotSettingsView.swift#L3) |
| `ScriptCommandView` | [zbox/Plugins/ScriptCommands/ScriptCommandsPlugin.swift:181](../../zbox/Plugins/ScriptCommands/ScriptCommandsPlugin.swift#L181) |
| `ScriptCommandsSettingsView` | [zbox/Plugins/ScriptCommands/ScriptCommandsSettingsView.swift:3](../../zbox/Plugins/ScriptCommands/ScriptCommandsSettingsView.swift#L3) |
| `.sheet(item: $editing) ` | [zbox/Plugins/ScriptCommands/ScriptCommandsSettingsView.swift:41](../../zbox/Plugins/ScriptCommands/ScriptCommandsSettingsView.swift#L41) |
| `ScriptCommandEditor` | [zbox/Plugins/ScriptCommands/ScriptCommandsSettingsView.swift:45](../../zbox/Plugins/ScriptCommands/ScriptCommandsSettingsView.swift#L45) |
| `let panel = NSOpenPanel()` | [zbox/Plugins/ScriptCommands/ScriptCommandsSettingsView.swift:141](../../zbox/Plugins/ScriptCommands/ScriptCommandsSettingsView.swift#L141) |
| `SnippetsSettingsView` | [zbox/Plugins/Snippets/SnippetsSettingsView.swift:3](../../zbox/Plugins/Snippets/SnippetsSettingsView.swift#L3) |
| `.sheet(item: $plugin.editingSnippet) ` | [zbox/Plugins/Snippets/SnippetsSettingsView.swift:43](../../zbox/Plugins/Snippets/SnippetsSettingsView.swift#L43) |
| `.alert("Delete Snippet?", isPresented: Binding(get: ` | [zbox/Plugins/Snippets/SnippetsSettingsView.swift:44](../../zbox/Plugins/Snippets/SnippetsSettingsView.swift#L44) |
| `SnippetEditor` | [zbox/Plugins/Snippets/SnippetsSettingsView.swift:54](../../zbox/Plugins/Snippets/SnippetsSettingsView.swift#L54) |
| `Menu("Insert Variable") ` | [zbox/Plugins/Snippets/SnippetsSettingsView.swift:81](../../zbox/Plugins/Snippets/SnippetsSettingsView.swift#L81) |
| `SnippetsView` | [zbox/Plugins/Snippets/SnippetsView.swift:3](../../zbox/Plugins/Snippets/SnippetsView.swift#L3) |
| `TextLookupPanelView` | [zbox/Plugins/TextLookup/Presentation/TextLookupPanelView.swift:5](../../zbox/Plugins/TextLookup/Presentation/TextLookupPanelView.swift#L5) |
| `TextLookupSettingsView` | [zbox/Plugins/TextLookup/Settings/TextLookupSettingsView.swift:3](../../zbox/Plugins/TextLookup/Settings/TextLookupSettingsView.swift#L3) |
| `WindowManagementSettingsView` | [zbox/Plugins/WindowManagement/WindowManagementSettingsView.swift:3](../../zbox/Plugins/WindowManagement/WindowManagementSettingsView.swift#L3) |
| `WorkspaceSettingsView` | [zbox/Plugins/Workspace/WorkspaceSettingsView.swift:3](../../zbox/Plugins/Workspace/WorkspaceSettingsView.swift#L3) |
| `.sheet(item: $plugin.displayMapping) ` | [zbox/Plugins/Workspace/WorkspaceSettingsView.swift:71](../../zbox/Plugins/Workspace/WorkspaceSettingsView.swift#L71) |
| `.sheet(item: $plugin.capture) ` | [zbox/Plugins/Workspace/WorkspaceSettingsView.swift:76](../../zbox/Plugins/Workspace/WorkspaceSettingsView.swift#L76) |
| `.sheet(item: $editing) ` | [zbox/Plugins/Workspace/WorkspaceSettingsView.swift:79](../../zbox/Plugins/Workspace/WorkspaceSettingsView.swift#L79) |
| `WorkspaceEditor` | [zbox/Plugins/Workspace/WorkspaceSettingsView.swift:91](../../zbox/Plugins/Workspace/WorkspaceSettingsView.swift#L91) |
| `WorkspaceCaptureView` | [zbox/Plugins/Workspace/WorkspaceSettingsView.swift:137](../../zbox/Plugins/Workspace/WorkspaceSettingsView.swift#L137) |
| `WorkspaceDisplayMappingView` | [zbox/Plugins/Workspace/WorkspaceSettingsView.swift:215](../../zbox/Plugins/Workspace/WorkspaceSettingsView.swift#L215) |
| `CommandFeedbackView` | [zbox/Search/CommandFeedbackView.swift:3](../../zbox/Search/CommandFeedbackView.swift#L3) |
| `RootSearchView` | [zbox/Search/RootSearchView.swift:3](../../zbox/Search/RootSearchView.swift#L3) |
| `CommandResultRow` | [zbox/Search/RootSearchView.swift:122](../../zbox/Search/RootSearchView.swift#L122) |
| `SettingsView` | [zbox/Settings/SettingsView.swift:3](../../zbox/Settings/SettingsView.swift#L3) |
| `GeneralSettingsView` | [zbox/Settings/SettingsView.swift:69](../../zbox/Settings/SettingsView.swift#L69) |
| `ShortcutSettingsView` | [zbox/Settings/SettingsView.swift:110](../../zbox/Settings/SettingsView.swift#L110) |
| `SettingsErrorView` | [zbox/Settings/SettingsView.swift:193](../../zbox/Settings/SettingsView.swift#L193) |
| `WindowView` | [zbox/Settings/SettingsView.swift:217](../../zbox/Settings/SettingsView.swift#L217) |
