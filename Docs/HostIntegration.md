# 宿主接入契约

H5 通过 SNCK v1 调用客户端。动作和回包格式见 [H5 交互](H5Protocol.md)。

对外产品为 `XYBookAudioSDK.framework` / `.xcframework`，类入口为 `XYBookAudioSDKManager`。在宿主新增的接入类中实现协议并调用 SDK，无需引入本工程实现源码或改写原有 WebView。

## 初始化与打开

最低 iOS 15，公开头 `XYBookAudioSDK.h`，支持 ObjC 与 Swift。初始化不请求业务网络、不激活 AVAudioSession。宿主完成 `XYBookAudioHost`，强持有 SDK 和 host，所有方法在主线程调用。

`entryURL` 为 HTTPS 线上入口。`trustedOrigins` 是精确 origin（scheme、host、可选端口），`allowedPathPrefixes` 按路径段边界校验，不做字符串包含匹配。远程页面不能提供本地文件音源。

开发联调可显式传入 `fileURL`：SDK 使用 `loadFileURL:allowingReadAccessToURL:`，页面和音频限制在入口文件所在目录，解析符号链接后再次检查。此能力用于本地测试；生产 H5 和业务资源仍由宿主配置。

SDK 在加载 H5 前通过临时 WebView 的空白本地文档读取实际 `navigator.userAgent`，追加固定标识 `MediaConvergenceXinhua` 并设置该实例的 `customUserAgent`，保留系统 UA 的移动／桌面模式内容。首次页面加载即生效，重载和重开不会重复追加；仅影响当前 SDK 页面，宿主无需额外设置 UA。读取失败会显示可重试的页面初始化错误，诊断信息遵循日志配置，关闭页面后不继续加载。H5 可用 `navigator.userAgent.includes('MediaConvergenceXinhua')` 识别端内环境。UA 不携带账号信息，身份查询和变更继续使用 JS Bridge 协议。

```objc
// 宿主按业务入口选择 XYBookAudioOpenStylePush 或 XYBookAudioOpenStylePresent。
[sdk openFromViewController:self style:XYBookAudioOpenStylePush completion:^(NSError *error) {
    if (error) {
        [self handleBookAudioOpenError:error];
    }
}];
```

`XYBookAudioOpenStylePush` 将听书首页推入宿主导航栈，要求传入当前可见的栈顶控制器。没有导航栈时返回 `INVALID_ARGUMENT`。`XYBookAudioOpenStylePresent` 全屏展示 SDK 自己的导航容器。直接调用 `XYBookAudioSDKManager` 的 `openFromViewController:completion:` 时，默认使用 Present。打开回调确认原生展示，网页加载结果由 SDK 页面处理。

两种方式下，听书页及其子页均隐藏原生导航栏。离开听书页进入宿主页或登录页时，恢复导航栏此前的显示状态。H5 通过原有接口打开或关闭页面，并在网页内提供返回入口。

WebView 顶部和底部贴齐听书容器。H5 可使用 `viewport-fit=cover` 和 CSS 的 `env(safe-area-inset-top)`、`env(safe-area-inset-bottom)`，让网页按钮或文字避开状态栏和底部手势区。

每个 SDK 实例同一时间只打开一组听书页面。重复打开或当前控制器无法导航时返回 `BUSY`。H5 用原有接口打开和关闭子页，两种模式都复用当前导航栈和初始可信地址范围。关页后保留播放器、队列和定时器。新开或重开 H5 调用 `xhSnckReady` 获取当前快照。

宿主登录使用 SDK 回调传入的当前网页及其 `navigationController`。`dispose` 释放会话。Present 模式关闭 SDK 导航容器，Push 模式只移除这次打开的 SDK 网页控制器。新页面的地址与标题参数见 [SNCK v1](H5Protocol.md)。

## WebView 调试

Safari 网页检查默认关闭。联调时在初始化 SDK 前设置 `configuration.webInspectorEnabled = YES`，即可在 iOS 16.4 及以上为内置听书 WebView 启用网页检查。该配置独立于日志级别，适用于 Debug 和 Release framework。包内 Demo 可通过启动参数 `--listening-web-inspector` 启用。

真机联调时，在设备的 Safari 设置中进入“高级”，开启“Web 检查器”。Mac Safari 开启“开发”菜单，连接并信任设备后，先在宿主中打开听书页，再通过“开发 → 设备 → 对应听书网页”检查 DOM、JavaScript 和网络请求。模拟器无需开启设备侧开关。具体说明见 [WebKit 官方调试指南](https://webkit.org/blog/13936/enabling-the-inspection-of-web-content-in-apps/)。

## 统一接入类

正式宿主可采用发行包 `Demo/Sources/BookAudio/AppBookAudioService` 的接入结构；开发工程中对应 `XYBookAudioSDKDemo/BookAudio/`。该类是宿主侧源码，不属于 framework 的公开类型。整个 App 共用一个实例，内部强持有 SDK 并实现 `XYBookAudioHost`，业务页面不再实现协议。

职责分配：

| 模块 | 责任 |
|---|---|
| `AppBookAudioService` | SDK 配置、会话生命周期、事件转发、宿主账号／登录／分享／音频能力适配 |
| `XYBookAudioDemoViewController` | 按钮动作、传入当前展示控制器、订阅事件更新界面 |
| `AppAccountService` | 宿主账号状态的唯一来源，完成身份提交／退出后发送账号变更通知，不依赖 SDK |
| `AppLoginViewController` | 宿主登录页，认证成功后提交账号状态，再返回宿主定义的结果；本地使用测试账号 |
| framework | 听书 WebView、JS 协议、播放、定时和断点存储 |

业务页面在主线程调用：

```objc
#import "BookAudio/AppBookAudioService.h"

__weak typeof(self) weakSelf = self;
[AppBookAudioService.sharedInstance openFromViewController:self
                                                    style:XYBookAudioOpenStylePresent
                                               completion:^(NSError *error) {
    if (error) {
        weakSelf.status.text = error.localizedDescription;
    }
}];
```

Demo 默认加载少年参考测试页。正式宿主在统一启动入口或首次打开前配置自己的 H5。

```objc
NSURL *entry = [NSURL URLWithString:@"https://h5.example.com/book-audio/index.html"];
XYBookAudioConfiguration *configuration = [[XYBookAudioConfiguration alloc]
    initWithHostIdentifier:NSBundle.mainBundle.bundleIdentifier entryURL:entry];
// 替换为实际业务路径；来源默认使用入口的 HTTPS 协议、域名和端口。
configuration.allowedPathPrefixes = @[@"/book-audio/"];
#if DEBUG
configuration.logLevel = XYBookAudioLogLevelDebug;
#endif
NSError *error = nil;
if (![AppBookAudioService.sharedInstance configureWithConfiguration:configuration error:&error]) {
    // 将错误交给宿主的错误展示或诊断入口，不能继续按初始化成功处理。
    [self handleBookAudioConfigurationError:error];
    return;
}
```

`handleBookAudioConfigurationError:` 代表宿主自己的错误处理方法；示例域名需要替换。配置无效时返回失败且允许修正后重试；已有会话时再次配置返回 BUSY。接入层保存成功配置的副本，修改调用方原配置不会影响现有会话或之后的重建。

生命周期约束：

- 打开时通过 `style` 指定全屏展示或 Push。两种方式均复用已有会话，同一时间只打开一组听书页面，重复打开返回 `BUSY`。
- 页面销毁只移除自己的 `AppBookAudioServiceEventNotification` 监听，不调用 SDK `dispose` 或服务 `shutdown`。通知在主线程发送，`object` 是服务实例，字段使用公开的 `AppBookAudioServiceEventNameKey`、`AppBookAudioServiceEventParametersKey`。
- 账号登录、退出和切换由 `AppAccountService` 完成，先提交状态，再发送 `AppAccountDidChangeNotification`。`AppBookAudioService` 监听通知并调用 `refreshHostIdentity`；`bookAudioUserIdentity` 每次读取宿主账号，不再缓存或修改身份。账号模块和页面无需调用任何 SDK 的退出接口，登录状态不等于购买权益。
- 其他播放器启动前调用 `yieldPlayback`。要停止听书播放，调用 `stopPlayback`。两者都保留 SDK 实例。
- 明确结束听书服务用 `shutdown`，释放会话与事件订阅，同时保留最近成功配置及宿主账号。等待已有容器关闭后，可直接再次打开，或重新配置入口。未初始化时 `playbackSnapshot` 返回 `nil`。

登录使用 SDK 回调传入的 `controller.navigationController` push，接入类只弱引用导航和返回页面。登录页仍在栈顶且来源网页仍在栈中时，登录结束回到来源网页。账号模块先提交登录后的身份，接入层负责将 `AppLoginResult` 转换为 SDK 结果。按钮取消、导航返回和容器关闭都只结算一次。

宿主页面退出账号只调用账号模块：

```objc
- (void)logout {
    [AppAccountService.sharedInstance logout];
}
```

接入类监听账号变更后刷新 SDK。登录、退出或切换账号时，SDK 停止当前播放并清空 SNCK 队列，H5 可按新身份重新下发音源。可见且已 Ready 的 H5 会收到 `snckUserChanged`，重开页面时从 Ready 快照读取当前身份和播放状态。

SDK 对游客身份使用空 userId；账号模块本身使用 nil。这个转换在 `bookAudioUserIdentity` 中完成。SDK 未初始化时，账号通知不会创建播放器；首次初始化读取最新账号。当前登录页使用本地测试账号，并不代表已接入真实认证服务；正式宿主在认证成功后调用自身的身份提交入口，退出失败时不能提前发布游客状态。

`XYBookAudioSwiftExample.swift` 保留为 framework 的 Swift 编译兼容示例，不参与 Demo 业务会话的创建。

## 日志配置

SDK 自身日志默认关闭。请在创建 `XYBookAudioSDKManager` **之前**配置；SDK 复制配置并为该实例创建独立日志出口，之后修改原配置不会改变运行中的实例，也不会影响其他实例。

```objc
XYBookAudioConfiguration *configuration = [[XYBookAudioConfiguration alloc]
    initWithHostIdentifier:NSBundle.mainBundle.bundleIdentifier entryURL:listeningURL];
configuration.logLevel = XYBookAudioLogLevelDebug; // 全部诊断；设为 Off 完全关闭

// 可选：接入宿主日志系统。设置后替代默认 NSLog，不会再重复打印。
configuration.logHandler = ^(XYBookAudioLogLevel level, NSString *component, NSString *message) {
    // 可替换成宿主现有日志组件；这里示范宿主统一输出。
    NSLog(@"[HostLog][%ld][%@] %@", (long)level, component, message);
};

NSError *error = nil;
self.bookAudio = [[XYBookAudioSDKManager alloc]
    initWithConfiguration:configuration host:self error:&error];
```

如果直接查看 Xcode 控制台，**不设置 `logHandler`**，SDK 使用如下格式输出：

```text
[XYBookAudio][Info][Page] Page load finished.
[XYBookAudio][Error][Page] Page load failed: WebKitInternal (0).
```

| `logLevel` | 输出范围 |
|---|---|
| `XYBookAudioLogLevelOff` | 全部关闭，日志回调也不执行 |
| `XYBookAudioLogLevelError` | 错误 |
| `XYBookAudioLogLevelWarning` | 错误、警告 |
| `XYBookAudioLogLevelInfo` | 错误、警告、关键生命周期与状态变化 |
| `XYBookAudioLogLevelDebug` | 以上全部及已知命令、Bridge 生命周期等调试信息 |

Swift 同样在初始化前设置：`configuration.logLevel = .debug`，关闭为 `.off`。本工程 Demo 仅在 `DEBUG` 编译配置下显式开启 Debug 日志，Release 保持默认 Off。

日志回调在主线程同步执行，应快速返回；异步写文件或上传由宿主自己的日志组件处理。回调不要强引用 SDK，避免形成持有环；不要从日志回调中触发业务动作。SDK 会阻止递归日志回调，但不会阻止回调里自行发起的业务操作。

日志覆盖页面加载与失败、可信来源拒绝、JS 传输错误、命令接收／回执、播放状态、宿主登录／分享／音频交接、定时结束和断点错误。周期进度不会逐秒打印。日志不输出用户标识、完整请求／快照、音源或页面 URL、token、错误 userInfo 或原始错误描述；未知的宿主错误域统一标记为 `ExternalError`，原始业务错误仍照常返回调用方。

此配置只控制 **XYBookAudioSDK 自己的日志**。iOS 的 WebKit／AVFoundation 系统输出和宿主日志不受此开关控制。关闭日志不会隐藏加载失败界面、错误事件或 completion 错误。SDK 不写日志文件、不上传日志。

## 宿主能力

| 方法 | 宿主责任 |
|---|---|
| `bookAudioUserIdentity` | 返回身份对象；游客用 `[[XYBookAudioIdentity alloc] initWithUserId:nil]`。不得返回 token、密码、完整用户资料。 |
| `bookAudioRequestLoginFrom:completion:` | 在给定控制器之上展示已有登录；回调 loggedIn/cancelled/failed。SDK 会重新读取身份。 |
| `bookAudioShare:from:completion:` | 接收标准分享参数；accepted 表示已选择渠道，cancelled 表示取消，不承诺平台成功。 |
| `bookAudioUserInfoWithParameters:completion:` | 可选。`xhSnckGetUserInfo` 在已登录时调用。接收完整请求参数，宿主校验自定义参数、处理票据并定义返回字段。SDK 原样回传非空 JSON 字典。 |
| `bookAudioUserInfoUsingTicket:completion:` | 可选。旧版资料接口，在宿主未实现完整参数方法时调用。`useTicket: true` 时由宿主刷新票据。两个资料方法均缺失时返回 `UNSUPPORTED`。 |
| `bookAudioSystemInfoFromViewController:` | 可选。覆盖 SDK 默认系统资料，适用于宿主需要提供自己的 `device_token` 或其他定制字段的情况。 |
| `bookAudioAcquirePlayback:` | 通过宿主已有接口让出音频控制权并在 10 秒内回调。没有其他播放器时直接 completion(nil)。无法按时完成时，宿主应撤销待处理的交接。 |
| `bookAudioDidReleasePlayback` | SDK 释放了音频控制权，或宿主已确认让出音频但请求未能启动播放。宿主根据当前音频状态决定后续操作。 |

`xhShowShareMenu` 的 `link` 使用 HTTPS 地址。`[URL](URL)` 中两处地址相同时，SDK 会提取 HTTPS 地址。SDK 将非空的 `imgUrl` 字符串原样传给宿主，宿主按分享渠道处理图片。

登录、分享必须结算一次，SDK 会拦截重复结果并在 180 秒后释放请求占用。账号变化时调用 `refreshHostIdentity`。SDK 会停止播放、取消定时和待处理的播放请求，并释放系统音频及锁屏控制。原生队列保留章节和原身份断点，旧付费音源会被撤销。每次播放或恢复时，SDK 都会重新读取身份。

其他音频业务开始前调用 `yieldPlayback`，完成后再激活自身会话。此调用保留队列与定时器，听书不会自动抢回。`Stop` 清除定时器并保存位置；`Dispose` 还释放页面、观察者和事件订阅，实例不可再用。

五个基础 host 方法必须实现，用户资料和系统资料方法在协议中为 optional。不需要账号或分享时，返回游客身份、登录取消和分享不支持；没有其他播放器时，释放通知可为空实现。所有能力都通过公开协议接入。

宿主未实现系统资料方法时，`xhGetSystemInfo` 默认返回设备型号、系统版本、App 名称和版本、系统 IDFV（`device_token`）以及当前听书窗口的状态栏和底部安全区高度。默认 `debug` 沿用 Demo 的数值 `1`。SDK 省略取不到的设备和 App 字段，缺少窗口时两项高度均为字符串 `"0"`。宿主实现该方法后，有效的 JSON 字典会原样返回，无效资料返回 `HOST_FAILED`。

同一 App 的播放器共享系统音频会话和锁屏控制。SDK 实例间互斥覆盖宿主交接等待期和系统媒体占用期，期间其他 SDK 实例的播放请求返回 BUSY。SDK 与宿主播放器之间由统一接入层通过宿主已有的停止及释放接口交接，其他业务开始播放前应调用 SDK 的 `yieldPlayback`。待处理的 SDK 播放请求被取消后，已发起的宿主交接会结算到收到回调或超时为止。

## 二进制集成

解压发行包后在宿主 Podfile 中添加：

```ruby
platform :ios, '15.0'
target 'YourApp' do
  pod 'XYBookAudioSDK', :path => '/path/to/XYBookAudioSDK-1.0.0'
end
```

安装后导入 `<XYBookAudioSDK/XYBookAudioSDK.h>`，Swift 使用 `import XYBookAudioSDK`。包内 Demo 也只按此方式集成。podspec 的远程 URL 是明确的占位配置；当前支持本地 :path，远程发布前必须替换为真实发行地址。

手动接入时，将 `Frameworks/XYBookAudioSDK.xcframework` 添加到宿主 App target，并选择 Embed & Sign。

## 后台与数据

宿主 Info.plist 必须包含 `UIBackgroundModes = [audio]`。声音从 AVPlayer 输出；H5 不应同时创建自己的音频播放器。SDK 仅在播放时激活 Playback 类别。锁屏 UI 是否展示倍速、上一首、下一首由系统决定。

进入后台时，SDK 会校验身份并保存断点。身份相同时继续播放。后台运行期间，宿主在账号变化后仍应在主线程调用 `refreshHostIdentity`，SDK 会同步停止播放并释放锁屏控制。

断点存入 Application Support，按 hostIdentifier、environment、userId、bookId 隔离；内容只有 bookId、chapterId、positionMs。音源 URL、凭证和付费权益不落盘。恢复需 H5 再次提供可用队列，未提供位置时匹配断点。读取失败时上报存储错误，队列仍从显式位置或章节起点装载。损坏的断点会移入同目录的 `.corrupt` 文件，后续进度写入原断点位置。

SDK 不实现购买、下载、离线、TTS、云同步、原生悬浮播放器。登录不是付费授权，H5／服务端必须确认权益并提供新地址。

## 依赖与隐私

SDK 只链接 iOS 系统库。发行包中的 `DEPENDENCIES.txt` 列出二进制的动态链接项。

SDK 无埋点上传；封面、音频和网页请求只访问配置／H5 给定资源。简化用户 ID 用于本地状态隔离。系统资料和宿主提供的标准用户资料按 H5 请求回传，不进入 SDK 日志或持久化。宿主与 H5 的数据收集行为由各自的隐私声明覆盖。

`PrivacyInfo.xcprivacy` 声明无 SDK 自有收集／跟踪，并为本地定时计算声明 SystemBootTime / 35F9.1；不上传原始启动时间。依据 [Apple required reason API 文档](https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacyaccessedapitypes/nsprivacyaccessedapitype)。发布前应结合最终 H5、宿主及全部依赖完成 App 的隐私核对。
