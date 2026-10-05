# 外部扩展合同 v1

本文件拥有安装格式和消息语义；使用行为见 `../product/extensions.md`。

## 包

ZIP 根目录为 manifest.json 和资源；也可导入展开目录。包格式 schemaVersion=1。必需字段：id（反向域名形式、小写字母/数字/点/连字符）、name、version（三段非负整数）、commands。可选字段：author、minimumHostVersion、minimumSystemVersion、architectures、capabilities、settings。

命令包括 id、name、keywords、mode（task 或 interactive）、entry（包内相对路径）、interpreter（系统绝对路径或 PATH 中的程序名，缺省直接执行）、arguments、parameters 和 timeout。参数按声明顺序追加独立 argv。包内命令 ID 只使用字母、数字、连字符和下划线。工作目录为包根。interactive 需要 protocolVersion=1。

宿主命令 ID 为 extensions.<扩展 ID>/<命令 ID>。包版本、schemaVersion、protocolVersion 与 SDK 版本互相独立。未知必需能力或不兼容版本拒绝启用，不猜测降级。所有入口必须是包内普通文件；不接受链接、越界路径、重复 ZIP 路径和特殊文件。

## 消息

interactive 使用 UTF-8 JSON-RPC 2.0，每行一条消息（不使用 batch）；stdin 接受宿主消息，stdout 只输出协议，stderr 是有界临时诊断。消息帧上限 8 MiB，文本业务值上限 1 MiB。

宿主 initialize 请求传 protocolVersion、sessionID；插件返回 protocolVersion=1。握手后宿主发送 start（commandID、arguments、settings、eventID）。query 和 action 通知携带递增 eventID；action 另含 actionID、values、selectedID。cancel 通知终止当前工作，stop 通知结束会话。

插件 ui 通知携带 eventID、view。只接受当前事件结果。host API 请求必须包含 eventID；宿主在异步返回和执行副作用前再次验证会话。请求以字符串 ID 匹配；成功返回 result，失败返回 error。未知方法使用 -32601，非法参数 -32602；业务错误使用 -32000。

首版宿主方法为 selection.read、clipboard.read、clipboard.write、clipboard.paste、settings.get、storage.get、storage.set、credentials.get、credentials.set、credentials.delete。授权由宿主连接对应的安装记录决定。API 数据命名与错误细节随实现补充在本合同中，不以 SDK 私有行为定义。

## 生命周期与数据

普通 task 的进程组、argv、输出及环境沿用 ScriptRunner 合同。交互会话握手超时 5 秒；宿主请求默认 30 秒，空闲界面不超时。取消先使会话失效，进程 SIGTERM 后最多等待 2 秒再 SIGKILL 并回收。

协议版本不匹配、超限或不可解析消息结束会话；未知合法方法返回错误。普通日志不记录消息正文、选区、剪贴板、设置值或凭据。
