# 设置最终紧凑工具栏

批次：D · 最终修正核对。

进入路径：开发者工具 → ⌘,。

状态：工具栏已收紧，侧栏内容上移，15 个设置入口可见。当时工具无法拖动窗口，最终缩放已在 42 号截图与用户操作中确认。

![设置最终紧凑工具栏](41-final-settings-window.png)

## 源码定位

`zbox/Settings/SettingsView.swift:3`（当前工作区）。使用 SwiftUI 原生控件、系统语义颜色及字体；用户可见文案位于 `zbox/Localizable.xcstrings`。设置外层布局由 `zbox/Settings/SettingsView.swift` 管理。

以下为定位用摘录，可能截断组件并省略回调、服务依赖，不能独立运行：

```swift
struct SettingsView: View {
    let environment: AppEnvironment

    var body: some View {
        @Bindable var environment = environment

        NavigationSplitView {
            List(selection: Binding<SettingsTab?>(
                get: { environment.selectedSettingsTab },
                set: { if let tab = $0 { environment.selectedSettingsTab = tab } }
            )) {
                settingsSection("zbox", tabs: [.general, .shortcuts, .extensions])
                settingsSection("Tools", tabs: [.fileSearch, .quicklinks, .snippets, .clipboardHistory,
                                                .screenshot, .textLookup, .scriptCommands])
                settingsSection("System", tabs: [.appMenu, .audio, .display, .workspace, .windowManagement])
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 180, ideal: 210, max: 260)
        } detail: {
            settingsDetail
                .frame(minWidth: 600, maxWidth: .infinity, maxHeight: .infinity)
                .navigationTitle(environment.selectedSettingsTab.title)
        }
        .frame(minWidth: 860, idealWidth: 940, maxWidth: .infinity,
               minHeight: 580, idealHeight: 660, maxHeight: .infinity)
        .background(SettingsWindowConfiguration())
    }

    private func settingsSection(_ title: LocalizedStringKey, tabs: [SettingsTab]) -> some View {
        Section(title) {
            ForEach(tabs, id: \.self) { tab in
                Label(tab.title, systemImage: tab.systemImage)
                    .tag(tab)
            }
```

版本及覆盖限制见 [总索引](index.md)。截图只包含当前可见区域。表单草稿均取消；公开示例仅用于本地转换，采集后清除，未复制结果或保存设置。
