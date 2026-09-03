# zbox Text Lookup 产品约定 v0.1

- 权威性：Normative Product Contract
- 加载方式：涉及 Text Lookup 产品范围、触发、悬浮窗、FlashDict 查词与建卡、翻译、隐私或验收边界时读取
- 状态：Active
- 最后更新：2026-08-29
- 适用范围：Text Lookup 内置独立扩展 v0.1
- 职责：定义 Text Lookup 的当前产品范围、用户行为与验收边界；实现 ownership、平台 seam 和并发边界见 `../../engineering-guidelines.md`

## 产品定位

Text Lookup 是随主 App 静态编译、拥有独立启停生命周期、状态和设置边界的当前内置独立扩展。它不是 macOS App Extension 或动态插件系统，也不建立第三方 Runtime、SDK 或插件市场。

## 用户行为与边界

- 用户可通过选区自动触发、选区快捷键确认或显式指针快捷键发起取词；安全输入、排除应用和不支持的文本表面必须明确拒绝。
- 取词窗口显示当前单词、尽力提取的原句和来源、FlashDict 释义、Apple 本地翻译及义项级建卡状态。悬浮窗口不主动抢走当前应用焦点。
- FlashDict 必须已经运行。zbox 不自动启动、不轮询，也不建立本地词典 fallback；失败提供可理解的状态和用户主动重试入口。
- 建卡以用户选择的义项为准，并携带当次冻结的原句与来源 URL。只有 FlashDict 返回实际成功后才能显示“已添加”。
- Apple Translation 只处理当前原句；切换词条、原句或目标语言后，旧结果不能覆盖当前会话。首版不提供第三方翻译服务入口。
- 捕获的单词、原句和来源只存在于当前会话，除非用户明确创建闪卡；不建立取词历史，不上传内容，也不把正文写入普通日志。
- Accessibility 被拒绝时提供系统设置入口；兼容复制只在用户启用后作为单次受控操作，并避免覆盖用户随后产生的剪贴板内容。

## 真实系统验收

真实应用兼容、Apple 语言模型、Developer ID 分发、外接显示器和真实建卡验收按需读取 `../release-readiness.md`。
