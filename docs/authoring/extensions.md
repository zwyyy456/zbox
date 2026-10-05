# 编写和分享扩展

安装行为见 `../product/extensions.md`，字段、能力、消息和版本以 `../contracts/extensions.md` 为准。普通脚本无需 SDK，参见 `automation.md`。不要依赖 zbox 内部 Swift 类型。

## 创建项目

以下命令在仓库根目录运行。作者工具需要 Python 3.9+，不运行项目内的安装脚本。

```sh
python3 script/extension.py init --language shell --id org.example.hello /tmp/my-hello
python3 script/extension.py validate /tmp/my-hello
python3 script/extension.py pack /tmp/my-hello /tmp/my-hello.zbox-extension
```

输出目录和包文件必须尚不存在。`--language` 也支持 python、swift。Python 模板复制当前 SDK；Swift 模板包含当前 SDK 源码的本地开发依赖，编译后包内只需要可执行文件和资源。扩展 ID 应由作者稳定维护，命令 ID 不随名称或版本改变。

在 zbox 设置 → 扩展 → 导入中选择生成的包，检查来源、命令和能力后安装。也可导入开发目录；宿主会复制目录，后续源文件修改需要再次导入才生效。重新导入同一 ID 就是手动更新，不扫描目录或自动执行。

## Python 示例

`examples/extensions/python-text/main.py` 使用 `SDK/python/zbox_sdk.py`，只有标准库依赖。打包时将 SDK 放到 main.py 同目录：

```sh
python3 script/extension.py pack examples/extensions/python-text /tmp/python-text.zbox-extension --python-sdk
```

SDK 的入口是 `await run(handler)`，handler 接收消息对象和事件上下文 api。`api.show(view)` 提交快照；`await api.call("selection.read")` 读取选区，`await api.call("clipboard.write", text=result)` 复制结果。SDK 自动添加事件身份、匹配响应，并在取消或新事件到达时取消旧 handler。

stdout 只用于协议。不要 print 业务内容、选区、凭据或完整消息来调试。运行环境不加载 shell 配置，机器必须能在宿主约定的 PATH 中找到 Python 3.9+；缺少 Python 时先安装和检查解释器。

## Swift 示例

Swift 作者需要 Swift 6.2+；用户运行编译后的扩展不需要 SDK 或编译器。包产品 `ZboxExtensionSDK` 提供 ExtensionClient、ExtensionEvent 和 ExtensionContext，`ZboxExtensionProtocol` 提供消息值及界面描述。

```sh
xcrun swift build --package-path examples/extensions/swift-text --scratch-path /tmp/zbox-text-build -c release
python3 script/extension.py pack examples/extensions/swift-text /tmp/swift-text.zbox-extension --binary /tmp/zbox-text-build/release/TextCaseExtension
```

程序调用 `try await ExtensionClient.run { event, api in ... }`。使用 `try await api.show(ExtensionViewSnapshot(...))` 和 `try await api.call(...)`。宿主与 SDK 使用同一份协议类型，作者程序不导入 zbox 模块。

一个事件被取消后，SDK 不再发送其界面结果或新的 API 请求。作者自己的异步工作仍应支持取消；跨 await 写入自己的共享状态前检查取消。已发生的外部副作用不会自动撤销。

## 界面和数据

示例提供转换方式列表、前缀表单、预览详情和读取/复制按钮。“读取并转换”才访问选区，普通打开或查询不读取。宿主保留稳定字段 ID 的用户输入；字段 value 用于初始化，不用反复发送 value 强制覆盖输入。

操作 params.values 的值是字符串，布尔字段使用 true/false；params.selectedID 是当前选中条目的 ID 或 null。query 通知只发生在扩展窗口，不包含 Root Search 的搜索词。

权限由 manifest.capabilities 声明并由用户授权，可以在扩展设置中撤销。settings.get 排除 secret；secret 通过 credentials.get 读取。配置变化会结束现有会话，下次启动读取新配置。storage 数据和 Keychain 凭据在普通升级时保留。

失败通过明确的 API error 返回。SDK 把 handler 错误显示在当前界面并保留操作，方便用户修改输入后重试。不要通过重试权限请求、循环读取剪贴板或绕过系统安全机制来掩盖错误。

## 分享和兼容

打包工具只做静态检查，宿主还会检查版本、运行环境和包安全边界。工具不会安装 Python 依赖、下载程序或执行构建钩子；需要的非标准库依赖由作者明确打包或告知用户安装。

普通包 manifest.version 必须是三段版本号。更新通过重新导入完成。提高最低宿主版本或新增能力时必须在 manifest 中声明；不要在旧协议版本内改变字段语义。

原生可执行程序应为声明的 CPU 架构和最低 macOS 版本构建。`pack --binary` 使用系统 lipo 读取架构写入 manifest，不执行程序。发布前按 Apple Developer ID 和公证流程处理二进制与最终分发包，不移除下载 quarantine 或要求关闭系统检查。打包工具不会替作者签名、公证或验证发布者身份。

## 验证一个完整扩展

先用系统环境运行静态检查并打包；再在宿主导入，从搜索和快捷键分别触发。验证权限拒绝、选区为空、快速查询、运行中关闭、禁用、更新和卸载。最后在另一台满足依赖的 Mac 下载并安装发布包，验证签名、公证、Space 和跨 App 焦点。

本机协议检查只能证明消息和 SDK 行为，不能代替真实系统与分发验收。宿主诊断不记录完整消息；作者排错优先查看退出原因和结构性错误，不导出用户内容。

仓库的双语言示例打包后，可运行协议检查；检查只使用合成文本：

```sh
python3 script/test_extension_sdks.py --python-package /tmp/python-text.zbox-extension --swift-package /tmp/swift-text.zbox-extension
```
