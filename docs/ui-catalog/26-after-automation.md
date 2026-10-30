# 新版自动化空状态

批次：B · 首次设置核对。

进入路径：设置 → 自动化。

状态：空状态及两种添加入口正常显示；未启用功能或运行脚本。

![新版自动化空状态](26-after-automation.png)

## 源码定位

`zbox/Plugins/ScriptCommands/ScriptCommandsSettingsView.swift:3`（当前工作区）。使用 SwiftUI 原生控件、系统语义颜色及字体；用户可见文案位于 `zbox/Localizable.xcstrings`。设置外层布局由 `zbox/Settings/SettingsView.swift` 管理。

以下为定位用摘录，可能截断组件并省略回调、服务依赖，不能独立运行：

```swift
struct ScriptCommandsSettingsView: View {
    let environment: AppEnvironment
    @State private var editing: ScriptCommand?
    private var plugin: ScriptCommandsPlugin { environment.scriptCommandsPlugin }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle("Enable Automation", isOn: Binding(get: { plugin.isEnabled }, set: environment.setScriptCommandsEnabled))
            Text("Scripts run as your user. Apple Shortcuts handles its own permissions and prompts. Add only automation you trust.")
                .font(.caption).foregroundStyle(.secondary)
            List(plugin.store.items) { item in
                HStack {
                    VStack(alignment: .leading) {
                        Text(item.name)
                        Text(item.shortcut?.name ?? item.path).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer()
                    if !item.enabled { Text("Disabled").foregroundStyle(.secondary) }
                    Button("Edit") { editing = item }
                    Button("Delete", role: .destructive) { environment.deleteScriptCommand(item) }
                }
            }
            .overlay {
                if plugin.store.items.isEmpty && plugin.store.loadError == nil {
                    ContentUnavailableView("No Automation Yet", systemImage: "terminal",
                                           description: Text("Add a script or Apple Shortcut to run from zbox."))
                }
            }
            HStack {
                Button("Add Script") { editing = ScriptCommand() }
                Button("Add Apple Shortcut") {
                    var item = ScriptCommand()
                    item.shortcut = AppleShortcutConfiguration(identifier: UUID(), name: "")
                    editing = item
```

版本及覆盖限制见 [总索引](index.md)。截图只包含当前可见区域。表单草稿均取消；公开示例仅用于本地转换，采集后清除，未复制结果或保存设置。
