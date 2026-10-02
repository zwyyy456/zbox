# Clipboard History 实施记录

非规范实施记录。产品规则见 `../../product/clipboard-history.md`。

## 阶段 1：平台边界

- 使用隔离的 NSPasteboard 验证纯文本读取、敏感类型和来源排除，不读取实际剪贴板。
- SDK 确认 macOS 15.4 起提供 accessBehavior；后台只在 alwaysAllow 时读取，授权由用户显式发起。
- Text Lookup 已接入临时复制协调对象，供历史采集复用；不添加新的日志、权限或后台监听。
- 最低系统实机、真实授权对话框和目标应用激活仍待人工验证，编译不能证明这些场景通过。
