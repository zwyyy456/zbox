# 新版扩展空状态

批次：B · 首次设置核对。

进入路径：设置 → 扩展。

状态：空状态、中文风险说明和导入按钮正常显示；未安装扩展。

![新版扩展空状态](19-after-extensions.png)

## 源码定位

`zbox/ExternalExtensions/ExtensionSettingsView.swift:3`（当前工作区）。使用 SwiftUI 原生控件、系统语义颜色及字体；用户可见文案位于 `zbox/Localizable.xcstrings`。设置外层布局由 `zbox/Settings/SettingsView.swift` 管理。

以下为定位用摘录，可能截断组件并省略回调、服务依赖，不能独立运行：

```swift
struct ExtensionSettingsView: View {
    @Bindable var manager: ExtensionManager
    @State private var editing: ExtensionInstallation?
    @State private var removing: ExtensionInstallation?
    @State private var deleteData = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Extensions run as your user and can access files and the network. Install only code you trust.")
                .font(.caption).foregroundStyle(.secondary)
            List(manager.items) { item in
                HStack {
                    Toggle(isOn: Binding(get: { item.enabled }, set: { enabled in Task { await manager.setEnabled(item, enabled) } })) {
                        VStack(alignment: .leading) {
                            Text(item.manifest.name)
                            Text("\(item.id) · \(item.manifest.version)").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    Button("Settings…") { editing = item }
                    Button("Uninstall") { deleteData = false; removing = item }
                }
            }
            .overlay {
                if manager.items.isEmpty && !manager.busy && !manager.loadFailed {
                    ContentUnavailableView("No Extensions Installed", systemImage: "puzzlepiece.extension",
                                           description: Text("Import a trusted extension package to add commands to zbox."))
                }
            }
            HStack {
                Button("Import Package…", action: choosePackage)
                    .buttonStyle(.borderedProminent)
                if manager.busy { ProgressView().controlSize(.small) }
            }
```

版本及覆盖限制见 [总索引](index.md)。截图只包含当前可见区域。表单草稿均取消；公开示例仅用于本地转换，采集后清除，未复制结果或保存设置。
