# zbox 工程差量规范

## Command 与平台边界

- Command 是搜索入口和直接快捷键共享的稳定业务接口；新增可执行能力不得绕过 Registry 建立旁路。
- 保持 `App`、`Commands`、`Builtins`、`Hotkeys`、`Platform`、`Search`、`Settings` 的当前语义边界，不增加固定的 Features/Core 层或宽泛 Runtime/Services 目录。
- AppKit、Carbon、Accessibility、ServiceManagement 和 NSWorkspace 由具体平台 adapter 隔离；只有真实替换或失败注入需求才增加协议。
- Settings Scene 是全局偏好的唯一写入入口；菜单、搜索和命令只打开或执行它定义的能力。

## 并发与恢复

- UI、AppKit 对象、Carbon 注册表和 app-lifetime 可变状态在 Main Actor 更新；纯 SearchEngine/WindowGeometry 值保持 `Sendable`/`nonisolated`。
- 从 C/Objective-C 回调进入 Main Actor 时，隔离必须能被 Swift 6 编译器验证，不用 `@unchecked Sendable` 掩盖竞态。
- 快捷键更新失败时保留或恢复上一组有效注册。目标窗口消失、不可调整或没有可用显示器时返回明确失败。
- Root Search 的性能问题先测量快捷键到可输入、应用扫描、图标读取、搜索和窗口 I/O，再决定是否引入后台或增量处理。

## 安全与分发

- M1 不上传搜索词、应用列表、窗口信息、快捷键或使用行为；日志不记录搜索词或窗口内容。
- Accessibility 只用于定位、移动和缩放目标窗口，权限缺失必须显示真实恢复动作。
- 分发基线为 Developer ID + Hardened Runtime 且 App Sandbox 关闭；改变这一组合时重新验证快捷键、应用扫描、Accessibility、登录项、签名和公证。
- 仓库不得包含签名、公证凭据或用户本机数据。

## 验证边界

- Command Registry、SearchEngine、WindowGeometry 和 Hotkey 配置使用 Swift Testing 保护纯规则。
- Carbon 快捷键、NSPanel 焦点/Space、Accessibility、登录项、外接显示器和真实应用启动以构建、运行和人工矩阵验证。
- 文档专属改动只做引用、重复、冲突和 diff 检查，不要求构建。
