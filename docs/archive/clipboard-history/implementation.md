# Clipboard History 实施记录

非规范实施记录。产品规则见 `../../product/clipboard-history.md`。

## 阶段 1：平台边界

- 使用隔离的 NSPasteboard 验证纯文本读取、敏感类型和来源排除，不读取实际剪贴板。
- SDK 确认 macOS 15.4 起提供 accessBehavior；后台只在 alwaysAllow 时读取，授权由用户显式发起。
- Text Lookup 已接入临时复制协调对象，供历史采集复用；不添加新的日志、权限或后台监听。
- 最低系统实机、真实授权对话框和目标应用激活仍待人工验证，编译不能证明这些场景通过。

## 阶段 2：文本闭环

- 独立本地 SwiftData 容器（显式关闭 CloudKit），使用有界历史的 Main Actor 串行写入，避免取消与提交之间的跨 actor 竞态；图片解码单独后台处理。
- 文本/链接采集、完整文本搜索、独立面板、复制、删除、清空和启停入口已接通。
- Debug 构建及隔离数据库重开、去重、删除/清空和剪贴板过滤测试通过；未读取真实剪贴板，未运行 UI 测试。

## 阶段 3：粘贴与快捷键

- Clipboard History 接入核心命令快捷键列表、冲突检查和事务式注册；仅启用时注册其直接快捷键。
- 独立面板支持上下键、Control-N/P、Return、Command-Return 和 Escape；保存 CommandContext 的目标应用，激活并复核前台身份后才发送粘贴。
- 权限缺失与目标失效提供明确状态，保留仅复制入口；不推断目标已经消费内容。
- CommandRegistry、HotkeyConfiguration、SearchKeyboardAction 单元测试及 Debug 构建通过。真实跨 App 激活和粘贴未执行，待人工验收。

## 阶段 4：图片与历史管理

- 支持单张 PNG/TIFF，解码前限制字节数和像素数，后台生成受限尺寸预览。
- 接通类型筛选、置顶、保留期限、容量淘汰与排除应用设置。
- 隔离剪贴板图片过滤、数据库容量和置顶保护测试通过；未读取实际剪贴板或执行 UI 测试。
