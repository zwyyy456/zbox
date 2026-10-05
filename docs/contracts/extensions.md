# 外部扩展合同 v1

本文件拥有安装格式和消息语义；使用行为见 `../product/extensions.md`。

## 包

ZIP 根目录为 manifest.json 和资源；也可导入展开目录。包格式 schemaVersion=1。必需字段：id（反向域名形式、小写字母/数字/点/连字符）、name、version（三段非负整数）、commands。可选字段：author、minimumHostVersion、minimumSystemVersion、architectures、capabilities、settings。

命令包括 id、name、keywords、mode（task 或 interactive）、entry（包内相对路径）、interpreter（系统绝对路径或 PATH 中的程序名，缺省直接执行）、arguments、parameters 和 timeout。参数按声明顺序追加独立 argv。包内命令 ID 只使用字母、数字、连字符和下划线。工作目录为包根。interactive 需要 protocolVersion=1。

宿主命令 ID 为 extensions.<扩展 ID>/<命令 ID>。包版本、schemaVersion、protocolVersion 与 SDK 版本互相独立。未知必需能力或不兼容版本拒绝启用，不猜测降级。所有入口必须是包内普通文件；不接受链接、越界路径、重复 ZIP 路径和特殊文件。

## 消息

interactive 使用 UTF-8 JSON-RPC 2.0，每行一条消息（不使用 batch）；stdin 接受宿主消息，stdout 只输出协议，stderr 是有界临时诊断。消息帧上限 8 MiB，文本业务值上限 1 MiB。

宿主 initialize 请求传 protocolVersion、sessionID；插件返回 protocolVersion=1。握手后宿主发送 start（commandID、运行时 arguments、eventID）。固定 arguments 通过进程 argv 传入。query 和 action 通知携带递增 eventID；query 含 query 文本，action 另含 actionID、values、selectedID。cancel 通知终止旧 eventID 的工作，stop 通知结束会话。关闭会话先使宿主授权失效，最多给 SDK 100ms 处理 stop，然后按进程组规则清理。

插件 ui 通知携带 eventID、view。只接受当前事件结果。host API 请求必须包含 eventID；宿主在异步返回和执行副作用前再次验证会话。请求以字符串 ID 匹配；成功返回 result，失败返回 error。未知方法使用 -32601，非法参数 -32602；业务错误使用 -32000。

首版宿主方法为 selection.read、clipboard.read、clipboard.write、clipboard.paste、settings.get、storage.get、storage.set、credentials.get、credentials.set、credentials.delete。授权由宿主连接对应的安装记录决定。API 数据命名与错误细节随实现补充在本合同中，不以 SDK 私有行为定义。

## 生命周期与数据

普通 task 的进程组、argv、输出及环境沿用 ScriptRunner 合同。交互会话握手超时 5 秒；宿主请求默认 30 秒，空闲界面不超时。取消先使会话失效，进程 SIGTERM 后最多等待 2 秒再 SIGKILL 并回收。

协议版本不匹配、超限或不可解析消息结束会话；未知合法方法返回错误。普通日志不记录消息正文、选区、剪贴板、设置值或凭据。

ZIP 支持未加密的 stored/deflate，包及解包内容最大 128 MiB、最多 4096 项；不支持 ZIP64 和分卷。解包保留下载 quarantine。目录导入同样拒绝链接和特殊文件。

## 宿主 API 参数

所有请求 params 都必须包含当前 eventID。最多 64 个进行中的宿主请求；请求 ID 在待处理期间唯一。下面列出的文本最大 1 MiB。

| 方法 | 其他 params | result | 授权 |
| --- | --- | --- | --- |
| selection.read | 无 | 原应用当前选区字符串 | selection.read |
| clipboard.read | 无 | 字符串或 null | clipboard.read |
| clipboard.write / clipboard.paste | text | null | 对应同名能力 |
| settings.get | 无 | 设置 ID 到字符串的对象，排除 secret | 无额外能力 |
| storage.get | key | JSON 值，缺失为 null | storage |
| storage.set | key、value | 写入的 JSON 值 | storage |
| credentials.get | key | 字符串或 null | credentials |
| credentials.set | key、value 字符串 | null | credentials |
| credentials.delete | key | null | credentials |

storage 和 credential 的 key 非空且最多 128 UTF-8 字节。普通设置和整个 JSON 数据文件各限制 1 MiB，使用原子文件替换；凭据由 Keychain 保存。取消不撤销已开始的文件或 Keychain 写入。

选区和剪贴板方法仅限 start 或 action，每个方法在同一个事件中最多一次，query 不能触发这些操作。剪贴板回写还检查从用户操作至回写期间的 changeCount，避免覆盖用户后续复制。

settings 声明为 `{id,name,type,defaultValue?,options?}`，type 支持 text、boolean、choice、secret；值统一为字符串，boolean 使用 true/false。secret 要求 credentials 能力，通过 credentials.get 读取，不通过 settings.get 返回。禁用、升级或卸载后保留的数据位于按扩展 ID 区分的 data 目录；卸载勾选删除时也删除对应 Keychain service。

## 界面快照

ui 通知 params 为 `{eventID,view}`。view 可包含 title、searchable、items、detail、fields、actions、loading、message、error。detail 是纯文本。条目 `{id,title,subtitle?}`；字段 `{id,name,type,value?,options?,error?}` 支持 text、multiline、boolean、choice；操作 `{id,title,enabled?,destructive?}`。

最多 1000 条目、50 字段、20 操作，同类 ID 唯一。每段文本最大 1 MiB。字段 value 只初始化新 ID 的输入，后续快照保留用户输入。selectedID 失效时选择首条。主操作支持 Command-Return，destructive 操作需要宿主确认；过期界面的确认不得执行新界面上的操作。
