# 原生 HiDPI 实现依据与验证状态

2026-10-02。研究记录，不是产品合同。

- BetterDisplay 官方 Wiki 提供原生 Flexible Scaling 与虚拟屏幕两条路线，优先原生配置：https://github.com/waydabber/BetterDisplay/wiki/Fully-scalable-HiDPI-desktop
- 作者在讨论 #737 中确认 `/Library/Displays/Contents/Resources/Overrides/DisplayVendorID-…/DisplayProductID-…` 的命名与型号 0 不补零的要求：https://github.com/waydabber/BetterDisplay/discussions/737
- one-key-hidpi 与 Crisp 的开源实现表明 `scale-resolutions` 数组使用大端渲染宽高。Crisp 使用逻辑宽度每档 16 点、保持宽高比的序列。本项目独立实现该数据格式，不复制特权脚本或修改 EDID。
  - https://github.com/xzhih/one-key-hidpi/blob/master/hidpi.sh
  - https://github.com/didriksg/Crisp/blob/main/Crisp/Services/HiDPIService.swift
- 原型仅生成 plist 并验证编码，没有安装系统配置或重新启动。
- 只读设备检测：M1 Pro；两块外接屏当前已提供 HiDPI。该设备状态不能证明无 HiDPI 屏幕的解锁效果。
- 当前路线不覆盖已有 Override，不依赖私有重新探测 API，不自动重启；安装后须重启并确认系统是否生成可用模式。虚拟屏幕尚未实施。
