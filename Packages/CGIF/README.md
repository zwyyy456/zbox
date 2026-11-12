# CGIF

静态编译的 cgif C 库，供 Screenshot 的 `GIFEncoder` 使用，无运行时外部程序依赖。

源码来自 [dloebl/cgif](https://github.com/dloebl/cgif/tree/b68f18ac125085923cae83b458e019e89feebe25)，固定于该上游版本（包含 RGB API 及其整数溢出修复）；RGB API 尚未包含在 v0.5.4 发布版中。保留原始 MIT 许可证，App 资源中同时分发 `cgif-LICENSE.txt`。

本地修改仅一处：`cgif_rgb_addframe` 将 `CGIFrgb_FrameConfig.genFlags` 传给底层 `CGIF_FrameConfig`，使变化区域编码开关生效。Swift 关闭 RGB API 的默认误差扩散抖动，并开启变化区域编码；未变化像素的透明化由 RGB API 完成。

C 实例和传入像素仅由现有串行编码路径访问；上游在 `addframe` 返回前复制所需数据，Swift 不向 C 留存临时缓冲指针。
