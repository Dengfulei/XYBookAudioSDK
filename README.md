# XYBookAudioSDK

面向 iOS 15 及以上的独立听书 SDK，源码使用 Objective-C，公开接口支持 Objective-C 和 Swift。宿主打开 SDK 的听书页，H5 提供章节和音源，原生会话负责播放、切章、进度、倍速、定时和断点。后台播控和音频交接通过 iOS 系统媒体接口及宿主协议完成。登录、用户资料和分享由宿主提供。

## 在项目中调试

```sh
open XYBookAudioSDK.xcworkspace
```

在 Xcode 选择 `XYBookAudioSDKDemo` scheme 和 iPhone 模拟器。点击「打开听书页面」进入少年参考测试页。添加启动参数 `--open-listening` 可在启动时直接进入听书页。宿主通过 `AppBookAudioService` 配置入口、可信域名和路径。真机运行 Demo 时在 Xcode 选择自己的开发团队。接入方法见 [宿主接入](Docs/HostIntegration.md) 和 [SNCK v1](Docs/H5Protocol.md)。

运行全部 XCTest 和格式校验。将下方模拟器名称替换为 Xcode 中可用的设备名称。

```sh
xcodebuild -workspace XYBookAudioSDK.xcworkspace -scheme XYBookAudioSDK \
  -destination 'platform=iOS Simulator,name=iPhone 18 Pro' \
  -parallel-testing-enabled NO -derivedDataPath build/Debug test CODE_SIGNING_ALLOWED=NO
bash Scripts/format.sh --check
```

## 导出给其他宿主

打包使用 Xcode、Python 3，以及装有 `xcodeproj` gem 的 Ruby。通过 `XYBOOK_RUBY` 可指定 Ruby 的路径。

```sh
bash Scripts/package.sh
```

- `Products/Frameworks/XYBookAudioSDK.xcframework` 包含 arm64 真机、arm64／x86_64 模拟器切片及符号文件。
- `Products/XYBookAudioSDK-1.0.0.zip` 包含 SDK、SHA-256 校验清单、接入文档和独立二进制 Demo。
- 解压后可用本地 CocoaPods `:path` 接入。手动接入时添加 `XYBookAudioSDK.xcframework` 并选择 Embed & Sign。详细步骤见 [二进制集成](Docs/HostIntegration.md#二进制集成)。

## 命名规范

- SDK 工程、模块、Pod、umbrella header 和 framework 使用 `XYBookAudioSDK`。发行包使用 `XYBookAudioSDK-<版本>.zip`。Demo、测试、测试宿主和打包 target 分别使用 `Demo`、`Tests`、`TestHost` 和 `Package` 后缀。
- SDK 的 Objective-C 类和协议、跨文件引用的常量与函数使用 `XYBookAudio` 前缀。类文件与主类型同名，分类实现使用 `类名+分类名.m`。测试类及其文件以 `Tests` 结尾。
- H5 动作名、事件名和 JSON 字段以 [H5 协议](Docs/H5Protocol.md) 为准。原生协议常量按 `Key`、`Value`、`Action` 和 `Command` 标明用途。

## 代码入口

| 路径 | 职责 |
|---|---|
| `XYBookAudioSDK/XYBookAudioSDK.h` | SDK 的 umbrella header，导出配置、宿主协议和 `XYBookAudioSDKManager` |
| `XYBookAudioSDK/Container`、`Bridge` | 内置 WebView、窗口导航及 EasyJS 请求和回调 |
| `XYBookAudioSDK/Playback`、`Domain`、`Storage` | 播放会话、队列、定时规则和本地断点 |
| `XYBookAudioSDK/Host`、`Diagnostics` | 宿主登录、分享、资料及日志出口 |
| `XYBookAudioSDKDemo`、`DemoResources` | 源码调试宿主和本地 H5；统一接入类是 `AppBookAudioService` |
| `Tests`、`Scripts` | XCTest、格式化与发布打包 |
