# 可安装扩展实施进度

非规范实施记录。每阶段验证后独立提交，保留已有工作区改动。

| 阶段 | 内容 | 状态 | 验证 |
| --- | --- | --- | --- |
| P0 | 产品与技术契约 | 完成 | 文档引用与 diff 检查 |
| P1 | 个人自动化作者指南及示例 | 完成 | zsh 语法、参数原样传递、缺参退出码；未运行 UI |
| P2 | 可安装普通包与管理 | 完成 | macOS build；3 项包边界测试；原 ScriptRunner/Store/AppleShortcuts 相关测试通过；系统界面待人工验收 |
| P3 | 交互协议及会话清理 | 完成 | macOS build；分片/null/非法消息、真实双向进程取消测试；ScriptRunner 回归通过 |
| P4 | 原生界面和宿主 API | 完成 | macOS build；7 项扩展测试通过，涵盖旧事件、授权拒绝、敏感设置排除；跨 App 与 Keychain 实机验收待完成 |
| P5 | SDK、作者工具及分发验证 | 代码和本机验证完成；真实分发待验收 | Python/Swift SDK 协议检查通过；Swift SDK、示例及生成模板构建通过；三个示例包通过实际宿主安装器；macOS build 和相关扩展、命令、快捷键、脚本测试通过 |

P5 本机验证覆盖握手、界面更新、宿主调用、权限拒绝、取消后的响应及退出。包测试还覆盖注册失败后的旧版本保留和下载 quarantine 保留。最后一次扩展测试为 8 项，未执行 UI 测试。

当前机器没有 Developer ID Application 签名身份，因此未完成真实 Developer ID 签名、公证及第二台 Mac 下载安装。跨 App、Space、系统权限与 Keychain 的人工步骤记录在 `../release-readiness.md`，这些结果不计入已通过的本机验证。

真实签名、公证、第二台 Mac、Space、Accessibility 和跨 App 焦点由真实环境验收，不以单元测试代替；不运行 zboxUITests。
