# 可安装扩展实施进度

非规范实施记录。每阶段验证后独立提交，保留已有工作区改动。

| 阶段 | 内容 | 状态 | 验证 |
| --- | --- | --- | --- |
| P0 | 产品与技术契约 | 完成 | 文档引用与 diff 检查 |
| P1 | 个人自动化作者指南及示例 | 完成 | zsh 语法、参数原样传递、缺参退出码；未运行 UI |
| P2 | 可安装普通包与管理 | 完成 | macOS build；3 项包边界测试；原 ScriptRunner/Store/AppleShortcuts 相关测试通过；系统界面待人工验收 |
| P3 | 交互协议及会话清理 | 完成 | macOS build；分片/null/非法消息、真实双向进程取消测试；ScriptRunner 回归通过 |
| P4 | 原生界面和宿主 API | 完成 | macOS build；7 项扩展测试通过，涵盖旧事件、授权拒绝、敏感设置排除；跨 App 与 Keychain 实机验收待完成 |
| P5 | SDK、作者工具及分发验证 | 待实施 | |

真实签名、公证、第二台 Mac、Space、Accessibility 和跨 App 焦点由真实环境验收，不以单元测试代替；不运行 zboxUITests。
