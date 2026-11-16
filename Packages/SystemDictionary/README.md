# SystemDictionary

zento 内置来源的 macOS DictionaryServices 适配。不依赖 FlashDict，不解析或复制系统词典包，不提供建卡。

`SystemDictionaryReader.shared` 串行查询本机活动词典，以启用顺序返回原始词条 HTML、名称和所属资源目录。活动词典列表在本次进程内读取一次；用户改变系统词典启用状态后重新启动 zento 生效。

Objective-C bridge 集中声明非公开 DictionaryServices 接口。版本 1 的 `DCSRecordCopyData` 返回带应用样式的富文本；公开纯文本 API 不作为自动降级路径。系统升级需要验证接口签名、对象所有权和资源布局。

`SystemDictionaryResource.resolve` 仅解析对应词典 Contents 下的文件，并解析符号链接后检查边界。宿主通过局部 WebKit scheme handler 在后台读取资源，不授予 WebView 任意本机文件访问。

技术参考：[EasyDict 的 DictionaryKit](https://github.com/tisfeng/Easydict/blob/dev/Easydict/objc/Libraries/DictionaryKit/TTTDictionary.m)。
