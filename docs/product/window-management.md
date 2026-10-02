# Window Management 产品约定

- 权威性：Normative Product Contract
- 状态：Active
- 最后更新：2026-10-02
- 适用范围：Window Management 内置插件；仍属于 M1 交付与验收范围

## 定位与入口

Window Management 是随主 App 静态编译的内置插件，负责 Left Half、Right Half 和 Maximize。它拥有独立启停状态、Window Management 设置 Tab 和 Accessibility 依赖，不建立动态插件 Runtime、独立进程或 SDK。

窗口命令注册到核心 Command Registry；Root Search 和直接快捷键使用同一执行路径。快捷键录制、持久化和跨功能冲突检查由核心 Shortcuts 设置统一管理。

## 启停与窗口行为

- 操作用户唤起 zbox 前的前台应用窗口，而不是 Root Search Panel。
- Left/Right Half 和 Maximize 使用窗口所在显示器的可用区域，避开菜单栏和 Dock。
- MVP 支持标准、可调整大小的应用窗口。
- 特殊窗口和跨显示器恢复不在范围内，但外接显示器上的基本定位应正确。
- Window Management 默认关闭。关闭时窗口 Command 仍可搜索，但不执行窗口操作，也不注册对应直接快捷键。
- Accessibility 系统提示只由用户在 Settings 中显式启用功能或请求权限时触发；普通 Command 执行只返回错误和真实恢复入口。
- 权限被撤销时立即关闭依赖功能并停止其运行能力，保留用户的其它配置；重新授权后由用户再次启用，不自动恢复监听或快捷键。

## 设置与权限

Window Management 设置页提供启停、权限状态、显式请求权限和系统设置入口。请求前说明 Accessibility 仅用于移动和缩放窗口，不读取窗口内容。退出 App 时停止插件运行，保留启用偏好及快捷键配置；下次启动必须重新检查权限。

现有启用偏好和命令快捷键继续生效，不因调整为插件而重置。

## 验收

- 默认关闭时，窗口命令可搜索，执行只引导设置；直接快捷键不注册。
- 启用且已授权时，搜索和直接快捷键可执行三个窗口动作，使用正确目标和显示器可用区域。
- 启用时快捷键注册失败应保留原有可用注册，并显示错误。
- 关闭或权限撤销只停止窗口管理的运行能力，不影响其它插件或 Root Search；再次授权后需手动启用。
- 真实窗口、权限和多显示器验收仍按核心产品文档第 9 节进行。
