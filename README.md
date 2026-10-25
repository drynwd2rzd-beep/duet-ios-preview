# Duet · iPhone 界面体验版

保留已经确认的聊天界面，使用 SwiftUI + WKWebView 封装成本地 iPhone App。

## 生成 IPA

把本目录的文件放到 GitHub 仓库根目录，推送到 `main` 后自动运行 **Build iPhone IPA**；也可以在 Actions 中手动运行。流程使用 GitHub 的 `macos-26` 虚拟机和 Xcode 26 或更新版本。

成功后，在该次 Actions 运行页面下载 **Duet-unsigned-ipa**，解压得到 `Duet-Preview-unsigned.ipa`。它是未签名包，需要使用自己的自签方式签名后才能安装，不能直接点文件安装。

本流程不需要把 Apple ID、密码、证书或描述文件上传 GitHub。

## 已包含

- 当前聊天／想法／设置界面，单聊和三人聊天、圆形头像、照片叠放与大图手势。
- 底部导航采用原生 SwiftUI：iOS 26 及以上调用苹果 `glassEffect`，iOS 17–18 使用系统 Material 回退。内容页和聊天菜单依然由本地网页渲染，不宣称全部界面是原生 Liquid Glass。
- 原生触感反馈、系统相机入口和照片确认；文件和照片选择使用 WebKit 系统选择器。
- 适配实际屏幕、真实系统状态栏、键盘、安全区；图标与主要英文字体随安装包离线提供。
- 名字、主题、角色文字、确认的记忆与想法等偏好在设备本地保存。

## 体验版边界

- 尚未连接 ChatGPT／Claude，消息不会发给真实 AI。回复演示会明确标注“交互演示”。
- 提醒目前只保存设置，不会触发系统通知。
- 聊天历史、照片、头像图片、背景图片、附件和导入字体目前保留在本次运行中，重新启动会重置这些临时内容。请勿把它当作唯一的记录工具。
- 主界面已在浏览器检查，SwiftUI 编译结果以 GitHub Actions 日志为准，实际相机、键盘和 Liquid Glass 效果需在 iPhone 验证。

## 本机开发（Mac）

安装 Xcode 26+、XcodeGen 后，在项目目录执行：

```bash
xcodegen generate --spec project.yml
bash scripts/build-ipa.sh
```

Xcode 工程可直接打开。若要从 Xcode 安装实机，请在 Signing & Capabilities 选择自己的 Team。

## 参考

- [Apple：Applying Liquid Glass to custom views](https://developer.apple.com/documentation/swiftui/applying-liquid-glass-to-custom-views)
- [GitHub-hosted runners](https://docs.github.com/en/actions/reference/runners/github-hosted-runners)
- [XcodeGen](https://github.com/yonaskolb/XcodeGen)

第三方图标和字体许可见 `THIRD_PARTY_NOTICES.md` 与 `Duet/Web/assets/`。
