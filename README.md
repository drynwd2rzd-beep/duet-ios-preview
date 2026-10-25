# Duet 0.3 · 原生 iPhone + Windows 消息桥

本版主界面使用 SwiftUI / UIKit，未使用 WKWebView，不加载 HTML、CSS、JavaScript。聊天、输入框、想法、设置、文件预览和照片浏览均为原生控件。

## 构建与安装

推送到 `main` 后，GitHub 的 macOS runner 自动运行 **Build Native iPhone IPA**。流程先编译 arm64 iPhone IPA，再在 iPhone 模拟器执行 UI 测试；成功后下载 **Duet-native-ipa** 并解压，取得 `Duet-Native-unsigned.ipa`，自行签名安装。最低 iOS 17，版本号 0.3.0，Bundle ID 为 `app.duet.preview`。

## 原生范围

- 主界面无网页层；整页不支持网页式缩放。只有照片大图的专用 UIScrollView 支持捏合与双击缩放。
- iOS 26+ 底部导航和辅助按钮使用苹果 `glassEffect`；旧系统回退到系统 Material。导航、菜单、表单和弹出页采用 SwiftUI 系统组件。
- 圆形头像、可编辑名字、右滑置顶、聊天搜索、群聊 @、照片叠放与展开、左右浏览和大图缩放。
- 系统相机、PhotosPicker 多图选择、原生文件导入与 Quick Look 预览。
- 想法编辑、左右滑动快捷操作、系统本地提醒（保存提醒时申请权限）。
- 独立角色档案和可编辑记忆，群聊可用范围由用户决定，称呼跟随“我的资料”。
- 主题色、纯色全局背景、独立聊天背景、全局系统／衬线／用户导入字体。原生字体导入支持 TTF / OTF。
- 数据与素材保存于设备 Application Support。旧混合版已保存的名字、主题、想法和角色文字会尽量迁移；旧版运行期内的临时照片无法恢复。

## 当前边界

GPT 文字聊天通过自己的 Windows 消息桥转交给本地 Codex app-server。用 ChatGPT 账号为 Duet 独立登录 Codex，无需填写 API 密钥；不读取 ChatGPT 官网原聊天记录。消息桥的本机真实连接测试已返回 GPT 回复。

iPhone 在“想法 → 设置 → 电脑连接”中保存 WSS 地址和配对码，也可扫描电脑生成的 Duet 配对二维码，核对地址后点击“保存并连接”。配对码保存在设备钥匙串。App 前台连接消息桥，后台暂停连接，回到前台重连；未确认的文字消息使用相同 UUID 重试。编辑并重发会产生新消息，不改写服务器已有记录。

Claude、照片和文件的真实 AI 收发、手机端模型/强度切换、后台 AI 推送仍未接入。原有相册、相机和文件预览 UI 保留。不会把演示回复或服务器接收确认显示成已获真实 AI 回复。当前使用 Codex 账号默认模型。

Windows 消息桥需要在聊天时保持运行。外网连接使用用户选择的 Cloudflare 临时 HTTPS/WSS 入口；临时地址在隧道重启后会改变，需要重新配对。手机实测、自签后的钥匙串和扫码行为仍需在 iPhone 验证。

## 验证

`scripts/validate.py` 检查原生源文件，并在 IPA 内拒绝 HTML / JS / CSS 文件。UI 测试检查主界面没有 WebView、捏合主页不会改变会话卡片宽度，并操作聊天输入、想法、设置和外观页面。模拟器截图作为 **native-ui-screenshots** 上传。触感、相机、通知和自签后的实机行为仍需在 iPhone 验证。

品牌图标由 LobeHub 开源 SVG 提供，仅用于服务识别，不表示与相关服务有关联。图标许可见 `THIRD_PARTY_NOTICES.md`。字体许可随 `Duet/Resources` 保存。
