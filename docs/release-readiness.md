# zbox 发布与真实系统验收参考

- 权威性：Reference
- 加载时机：Developer ID 分发、系统能力或 Text Lookup 真实环境验收时按需读取
- 状态：Active

本文只保留无法由普通构建和单元测试证明的当前验收事项。已完成实施过程和历史证据位于 `docs/archive/`。

## 分发

- [ ] 使用 Developer ID Application identity 构建最终 Release，确认不包含 `get-task-allow`。
- [ ] 完成公证、staple 和 Gatekeeper 验证，并复核 Hardened Runtime、非沙盒、登录项和 Accessibility 行为。
- [ ] 确认发布产物不包含签名凭据、用户数据、调试入口或正文日志。

## Text Lookup 系统闭环

- [ ] 在 TextEdit、Safari、Xcode、备忘录、VS Code 和可选中文本 PDF 上验证选区与指针路径；不支持的表面显示明确结果。
- [ ] 覆盖 Accessibility 首次拒绝、授权、撤销和恢复，以及安全输入和排除应用。
- [ ] 覆盖普通桌面、全屏、多个 Space、单显示器和外接显示器的悬浮窗口定位、焦点、Escape 与外部点击关闭。
- [ ] 在启用兼容复制时验证 Safari 等应用，并确认恢复操作不会覆盖用户并发剪贴板修改。
- [ ] 安装 Apple 英文到简体中文模型，验证成功翻译、下载授权取消、切换目标语言和旧结果抑制。
- [ ] 使用当前源码 FlashDict 和合法测试词典验证查词、CSS/图片/音频、失败状态和手动重试。
- [ ] 使用隔离测试数据验证义项级建卡、原句/source URL、成功、额度拒绝和失败结果；不得写入用户现有卡片数据。

## 记录原则

只记录实际运行的构建版本、系统环境、场景、结果和未覆盖风险。未执行或受环境限制的项目保持未完成，不推断为通过。
