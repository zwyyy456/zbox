# Screenshot 实施记录

非规范阶段记录。基础版包含单屏区域、窗口和当前屏幕截图、基础编辑与图床上传；OCR、贴图和滚动截图不纳入本轮。

## 阶段 1：截图基础

- 接入独立插件、设置、Command Registry 和用户可配置快捷键；默认关闭，仅显式触发时请求屏幕捕获权限。
- 使用支持 macOS 15 的 ScreenCaptureKit 单帧 API，区域选框限制在一个显示器内；窗口截图排除自身窗口。
- Debug 构建与负坐标显示器、屏幕坐标翻转、选区裁切测试通过。未读取真实屏幕，也未运行 UI 测试。
- 实际授权、窗口高亮、Retina、多显示器和 Space 仍待人工验证。

## 阶段 2：编辑与输出

- 增加单会话编辑模型，原图与标注分离；撤销／重做只保存编辑状态，不复制整张原图。
- 支持裁剪、箭头、矩形、文字、实色遮挡、画布缩放、PNG 复制和 PNG／JPEG 保存。复制使用本机剪贴板并通知现有协调对象，避免额外进入剪贴板历史。
- 预览、复制与保存共用渲染逻辑；后台编码，取消或替换会话后不提交旧导出结果。
- Debug 构建与裁剪、撤销重做、遮挡后导出像素测试通过。未运行真实截图或 UI 测试。
- 图床服务名称尚待确认，上传协议和配置字段需据此确定；当前“完成”执行复制图片，上传阶段将接入已配置的自动上传行为。

## 阶段 3：图床配置与手动上传

- 用户确认首批服务：Cloudflare R2、Amazon S3、阿里云 OSS、腾讯云 COS、七牛云、又拍云、SM.MS。SM.MS 依据官方迁移说明接入 S.EE 现行上传接口，界面保留对应名称与凭据说明。
- 使用 S3 SigV4、OSS V4、COS SHA1 签名、七牛上传凭证和又拍云 HMAC 签名；上传与公开访问域名分开配置，不改变桶权限。
- 多图床配置保存普通偏好，凭据保存到本机 Keychain；提供手动上传、进度、取消、复制链接及生成图片测试。网络层拒绝重定向，不将凭据转发到其它目标，也不展示响应正文。
- Debug 构建及七种请求／响应测试通过；AWS、又拍云官方签名样例，以及根据 OSS／COS／七牛协议独立计算的固定样例通过。
- 未读取真实账号凭据或上传截图；真实网络、账户权限与公开链接仍需逐服务实测。

### 接口依据

- [R2 S3 API](https://developers.cloudflare.com/r2/api/s3/api/)
- [AWS SigV4](https://docs.aws.amazon.com/AmazonS3/latest/developerguide/sig-v4-header-based-auth.html)
- [OSS V4](https://www.alibabacloud.com/help/en/oss/developer-reference/recommend-to-use-signature-version-4)
- [COS 请求签名](https://intl.cloud.tencent.com/zh/document/product/436/7778)
- [七牛上传凭证](https://developer.qiniu.com/kodo/1208/upload-token)与[直传文件](https://developer.qiniu.com/kodo/1312/upload)
- [又拍云鉴权](https://help.upyun.com/knowledge-base/object_storage_authorization/)
- [SM.MS 迁移说明](https://s.ee/docs/developers/smms-compatibility/)与[S.EE 上传接口](https://s.ee/docs/api/UploadFile/)

## 阶段 4：自动上传与任务收尾

- 自动上传默认关闭；启用后“完成”明确显示为“完成并上传”，只上传最终合成图。支持 URL／Markdown 输出及上传期间的新剪贴板内容保护。
- 失败或手动取消后只保留当前会话的导出字节、原图床配置和对象名，显式重试重新签名；配置发生变化时提示重新发起上传。无启动重传、自动重试或后台队列。
- 停用、关闭编辑器或开始新截图会取消旧任务；旧进度、错误和成功结果须匹配任务身份才可更新。取消不宣称删除已到达远端的图片。
- 上传中禁用 SwiftUI 编辑控件及 AppKit 画布手势；任务结束释放任务引用。
- 隔离剪贴板测试确认等待期间的新复制不会被上传结果覆盖，Markdown 回写会通知历史协调对象；图床协议测试和最终 Debug 构建通过。真实网络取消／重试仍待人工验收。

## 阶段 5：本地化、系统交互与验收文档

- 补齐英文／简体中文界面、上传错误提示、配置说明与独立产品约定，更新文档路由和人工验收清单。
- 删除默认图床后不自动切换目的地；补齐选框鼠标跟踪、首次点击与 Escape、取消后返回已有编辑器、权限设置入口和活动 Space 窗口行为。
- 区域确认后在选框仍存在时重新枚举共享内容，再关闭选框并按应用过滤截图，避免只依赖窗口隐藏的时序。保存对话框返回时核对原编辑会话。
- 全部 `zboxTests` 通过；最终系统交互改动完成后 Debug 构建通过；S.EE 业务错误提示调整后的图床测试再次通过。String Catalog 文案完整性检查和 `git diff --check` 通过。
- 未执行 UI 测试、真实屏幕捕获、真实 Keychain 凭据读写或远端上传。人工验收见 `docs/release-readiness.md` 的 Screenshot 部分；无真实账号验收证据时，不宣称七种服务已实传通过。
