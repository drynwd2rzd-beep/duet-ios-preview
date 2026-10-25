# Duet 0.2 · 原生 iPhone 体验版

本版主界面使用 SwiftUI / UIKit，未使用 WKWebView，不加载 HTML、CSS、JavaScript。聊天、输入框、想法、设置、文件预览和照片浏览均为原生控件。

## 构建与安装

推送到 `main` 后，GitHub 的 macOS runner 自动运行 **Build Native iPhone IPA**。流程先编译 arm64 iPhone IPA，再在 iPhone 模拟器执行 UI 测试；成功后下载 **Duet-native-ipa** 并解压，取得 `Duet-Native-unsigned.ipa`，自行签名安装。最低 iOS 17，版本号 0.2.0，Bundle ID 为 `app.duet.preview`。

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

真实 ChatGPT / Claude 官网账号连接和消息收发仍未实现。发送后会明确显示账号未连接；回复演示始终标注“交互演示”。不会把演示当作真实 AI。未来官网连接只会作为独立账号模块实现，不用网页承载主界面。

## 验证

`scripts/validate.py` 检查原生源文件，并在 IPA 内拒绝 HTML / JS / CSS 文件。UI 测试检查主界面没有 WebView、捏合主页不会改变会话卡片宽度，并操作聊天输入、想法、设置和外观页面。模拟器截图作为 **native-ui-screenshots** 上传。触感、相机、通知和自签后的实机行为仍需在 iPhone 验证。

品牌图标由 LobeHub 开源 SVG 提供，仅用于服务识别，不表示与相关服务有关联。图标许可见 `THIRD_PARTY_NOTICES.md`。字体许可随 `Duet/Resources` 保存。
