# H5 标准交互与当前接入范围

本 SDK 与参考工程 `XYBookAudioModule` 使用相同的 H5 方法、事件和回调格式。兼容 `xinhua-sdk@1.15.8`。调用传入标准信封，成功回调的 `parameters` 是业务数据。

## 原生代码查找入口

实现沿用原项目 `XYInterfaceWKWebView` → `XYWebInterfaceJSBridge` → `XYWebViewJSBridgeManager` 的职责和同名方法分发方式，SDK 类名前缀统一为 `XYBookAudio`，避免接入原宿主后发生 Objective-C 类名冲突。

| 原项目职责 | SDK 实现文件 | 阅读入口 |
|---|---|---|
| WebView 注入与回调 | `Bridge/XYBookAudioBridgeWebView.m` | `addJavascriptInterface:`、`nativeCallJS:completion:` |
| JS 对象方法接入 | `Bridge/XYBookAudioScriptMessageHandler.m` | `JSCallNative:`、`JSCallNativeBlock` |
| 全部 H5 同名业务方法 | `Bridge/XYBookAudioWebBridge.m` | `#pragma mark - 标准 H5 同名方法`：窗口、登录、能力查询及全部现有听书入口 |

各业务方法都接收完整请求字典，与原项目一致：业务入参从 `request[@"parameters"]` 读取，回调名从 `request[@"callbackActionName"]` 读取。查找一个 H5 方法时，直接搜索同名 Objective-C 方法即可。

分发与原项目一致：用 `actionName + ":"` 查找同名方法，通过 `NSInvocation` 传入完整请求。H5 入口统一使用 `xh` 前缀和单个字典参数，actionName 本身不带冒号；未实现的方法明确返回不支持。`xhCanIUse` 根据同名方法是否存在返回 `{data:1/0}`；`xhBookAudioGetCapabilities` 的 actions 从实际方法生成并按名称排序，不再维护 `XYBookAudioActions()` 手工名单。新增 H5 接口直接实现 `- (void)xh方法名:(NSDictionary *)request` 即可；宿主数据、UI 条件和播放状态仍由对应业务方法检查。窗口管理沿用 `closeWindowFromPage:` 和 `openWindowWithURL:fromPage:`。

## 统一传输方式

前端使用 `xinhua-sdk` 公开 API，库负责前缀转换、序列化以及回调注册；业务页面不应再自建一套 Bridge：

```js
import xh from 'xinhua-sdk';

xh.closeWindow();
xh.openWindow({ url: 'https://your-trusted-host.example/listening/detail' });
xh.goLogin();
```

H5 向 `JSCallNative` 传入 JSON 字符串：

```js
window.xhAppJSBridge.JSCallNative(JSON.stringify({
  actionName: 'xhOpenWindow',
  parameters: { url: 'https://your-trusted-host.example/listening/detail' }
}));
```

有回调的方法，由 JS SDK 注册函数并生成 `callbackActionName`。原生按该名称返回 `{actionName, parameters}`；JS SDK 将 **parameters 原样传给 success/complete**，不会自动拆 `ok/data/error`。各方法自己的参数结构按对应协议定义，不能另加全局业务包装。SDK 不读取、校验或返回 `protocolVersion`、`requestId`。标准信封只使用 `actionName/parameters/callbackActionName`；无业务参数时允许省略 parameters。

WebView 在文档开始时先注入与原项目一致的 `XYBookAudioEasyJSScript`（`EasyJS.call` / `EasyJS.inject`），再执行 `EasyJS.inject("xhAppJSBridge", ["JSCallNative:"])`。原生注册和移除的 WebKit message handler 同样叫 `xhAppJSBridge`。

EasyJS 先对每个参数执行 encodeURIComponent，再对用冒号拼接的参数串编码。单个 JSON 参数实际通过 WebKit 发送为：

```text
xhAppJSBridge:JSCallNative%3A:<两次 URI 编码后的 JSON 字符串>
```

原生校验对象名和方法名，对参数串对应解码两次，再将原 JSON 交给 `JSCallNative:`。该入口只接受一个参数，不通过 runtime 把属性访问器或任意原生方法暴露给 H5。错误的对象／方法、参数个数或 URI 编码进入既有错误事件及可配置日志；不保留裸 JSON 直发 WebKit 的另一套传输。

原生用系统 JSON 序列化构造 `window.xhWebJSBridge.nativeCallJS(<JSON>)`，再通过 `evaluateJavaScript:completionHandler:` 执行。`XYBookAudioBridgeWebView.m` 中的 `XYBookAudioNativeCallbackJSFunction` 沿用参考项目的回调入口。

## 三个已确认页面方法

| 业务 | H5 API | 原生 actionName | 参数 | 业务回调 |
|---|---|---|---|---|
| 关闭当前窗口 | `xh.closeWindow()` | `xhCloseWindow` | 无业务参数 | 无 |
| 打开新窗口 | `xh.openWindow({url})` | `xhOpenWindow` | `url`，绝对地址 | 无 |
| 打开登录页 | `xh.goLogin()` | `xhGoLogin` | 无业务参数 | 无 |

- 新网页由 SDK 自有导航栈 push，保留父页文档与原生播放会话。关闭子页返回上一页，关闭首页退出模态容器；关闭窗口不停止播放。
- 网页数据存储对齐 `XYWebBrowerController`，使用 `WKWebsiteDataStore.defaultDataStore`。同一 App 内使用默认存储的同源页面共享 `localStorage`；Cookie 按 WebKit 的域、路径和有效期规则使用。数据采用默认持久化行为，关闭窗口、重建 SDK 不主动清理；退出登录后的网页凭据由 H5 按身份变更处理，SDK 不清空整个宿主的网页存储。
- 新页面继承原来的可信域名、路径、本地文件授权范围和网页检查设置，并继续设置 `MediaConvergenceXinhua` UA。远程生产页仅接受配置允许的 HTTPS 地址，本地测试页仅访问最初授权目录。
- 只有可见顶层网页能发起页面导航或登录。隐藏父页、转场或宿主界面占用时拒绝操作，并经配置日志记录原因。
- `xhGoLogin` 复用宿主登录代理，支持宿主通过 SDK 当前页面的导航栈 push 登录页。账号仍属于宿主；登录成功、取消或失败不额外发送自定义登录回执。身份读取使用 `xhGetUserInfo`，变更通知使用 `onBookAudioUserIdentityChange`。
- 与参考代码一致，这三个方法不声明业务回调；不要等待 Promise 或依赖 success。参数或导航失败仅进入可配置诊断日志，不再擅自发送 `onBookAudioError`。新网页实际加载失败仍显示重试入口。
- 参考原生的可选 `pointName` 用于原 App 埋点；SDK 当前不实现该埋点能力，接收后不上传，也不将它用作标题。
- 宿主继续使用公开原生方法打开听书容器，无需新增网页路由代理。这三个页面动作不通过原生 `executeAction:` 代发。

## 能力查询

```js
xh.canIUse({
  name: 'goLogin',
  complete(res) {
    // res 直接等于原生回调的 parameters：{ data: 1 } 或 { data: 0 }。
    console.log(res.data);
  }
});
```

上例原生消息为 `actionName: 'xhCanIUse'`、`parameters: {name: 'xhGoLogin'}`，并带 JS SDK 生成的 `callbackActionName`。原生返回该回调名及 `{data:1}`。`xh.canIUse` 和 `xh.execCustomMethod` 的调用名不要预先加 `xh`，库会自动处理前缀和首字母大写。

## 用户资料和系统资料

```js
xh.getUserInfo({
  goLogin: false,
  useTicket: false,
  success(profile) {
    // 游客或取消登录是 {}；已登录是宿主提供的原始资料。
    console.log(profile.info?.id);
  }
});
```

`goLogin/useTicket` 若提供，必须为 JSON boolean。游客且 goLogin=true 时请求宿主登录；取消或登录失败返回 `{}`，成功后读取资料。已有账号不会再展示登录页。原版 JS API 默认 goLogin=true，未传 useTicket 时原生按 false 处理。

已登录资料由 `bookAudioUserInfoUsingTicket:completion:` 提供；SDK 不将 `isLoggedIn/userId` 伪装成宿主完整资料。宿主根据自己的账号协议返回 id、info、phone 等真实字段。useTicket=true 时由宿主刷新票据，缺失能力明确返回 UNSUPPORTED。Demo 仅提供本地账号 id/info.id，未接入票据服务。

原版 `xh.getUserInfo()` 收到原生资料后，还会调用 `xhGetSystemInfo`，再由 JS 库合并自己的字段并触发 success。宿主需实现 `bookAudioSystemInfoFromViewController:`，返回参考协议的系统资料：types/debug/program_version/device_token/program_name/system/appStatusBarHeight/bottomSafeHeight。`device_token` 必须沿用宿主已有标识；SDK 不生成标识或自行拼装登录凭证。也可以直接调用 `xh.getSystemInfo({success})`。

资料请求期间退出、换号或销毁 SDK，旧资料不能回传。宿主 completion 统一在主线程结算一次，180 秒无响应明确失败。

## 分享菜单

```js
xh.showShareMenu({
  title: '书名',
  link: 'https://your-trusted-host.example/book/1',
  desc: '内容简介',
  imgUrl: 'https://your-trusted-host.example/cover.jpg'
});
```

title/link 必填，link 必须 HTTPS；desc/imgUrl 可选，非空 imgUrl 必须 HTTPS。SDK 透传参数给宿主 `bookAudioShare:from:completion:`，额外的内容／海报参数由宿主真实分享能力解释，SDK 不实现分享渠道或海报生成。

原版 `xh.showShareMenu()` 不注册业务回调，不能等待 success。与参考原生代码一致，若通过标准信封另传 callbackActionName，仅在宿主报告已选择渠道后返回 `{}`；失败／不支持进入配置日志，取消不返回成功，不输出自定义 status 包装。Demo 使用系统分享页，在系统 completion 确认完成后回调 accepted，取消回调 cancelled。

## 听书方法与业务参数

前端使用原版扩展入口，方法名不预先加 xh：

```js
xh.execCustomMethod('bookAudioGetSnapshot', {
  success(snapshot) {
    console.log(snapshot.state, snapshot.positionMs);
  }
});
```

对应请求：

```js
{ actionName: 'xhBookAudioGetSnapshot', parameters: {}, callbackActionName: 'onSnapshot' }
// 对应成功回调；parameters 本身就是快照。
{ actionName: 'onSnapshot', parameters: { state: 'idle', rate: 1, positionMs: 0, sleepTimer: {mode: 'off'} } }
```

| actionName | parameters | 成功回调 parameters |
|---|---|---|
| `xhBookAudioGetCapabilities` | 无 | actions/rates/sleepModes |
| `xhBookAudioGetSnapshot` | 无 | 当前快照 |
| `xhBookAudioSubscribe` | 无 | `{subscribed:true}`，随后立即推送快照 |
| `xhBookAudioUnsubscribe` | 无 | `{subscribed:false}` |
| `xhBookAudioSetQueue` | bookId/title/chapters；可选 coverURL/chapterId/positionMs | 替换后的快照，不自动播放 |
| `xhBookAudioPlay` | 无 | 当前快照；实际缓冲／播放状态继续通过事件更新 |
| `xhBookAudioPause` | 无 | 暂停后的快照 |
| `xhBookAudioStop` | 无 | 停止后的快照，清除定时器 |
| `xhBookAudioSeekTo` | positionMs，非负数；已知时长时限制到章末 | 跳转结果快照 |
| `xhBookAudioPrevious` / `xhBookAudioNext` | 无 | 选章并尝试播放后的快照；越界报错 |
| `xhBookAudioSelectChapter` | chapterId | 选章结果；受限时停在该章，不跳过 |
| `xhBookAudioSetRate` | rate: 0.75/1/1.25/1.5/1.75/2 | 倍速调整后的快照 |
| `xhBookAudioSetSleepTimer` | mode=trackCount,count=正整数；或 mode=duration,durationMs=正整数 | 定时设置后的快照 |
| `xhBookAudioCancelSleepTimer` | 无 | 关闭定时后的快照，不改变播放 |

队列至少包含一章。每章必须有 chapterId/title/requiresLogin，chapterId 不得重复；requiresLogin 必须 JSON boolean，0/1 不代替布尔。audioURL 为可播放音源，受限待授权章节可以暂不提供，durationMs 可选。数字字段不接受布尔或字符串。队列校验失败不覆盖已有队列。普通生产音源和封面使用 HTTPS，本地测试音源使用入口授权目录的 file URL；当前全 URL 放行策略的例外见上文。

## 快照、订阅与错误

```js
xh.addEventListener('onBookAudioPlaybackChange', snapshot => console.log(snapshot));
xh.addEventListener('onBookAudioUserIdentityChange', identity => console.log(identity));
xh.addEventListener('onBookAudioError', error => console.error(error.code, error.message));
xh.execCustomMethod('bookAudioSubscribe', { success: result => console.log(result.subscribed) });
```

快照始终有 state/rate/positionMs/sleepTimer。有队列时增加 bookId/title/chapterId/chapterTitle/chapterIndex/chapterCount，已知时长才返回 durationMs，不返回签名音源 URL。state 为 idle/ready/buffering/playing/paused/blocked/completed/stopped/failed；reason 表示结束或拦截原因。

- `onBookAudioPlaybackChange`：快照。状态变化立即发送，普通进度和倒计时最多每秒一次。
- `onBookAudioUserIdentityChange`：isLoggedIn/userId；退出为 `{isLoggedIn:false,userId:""}`。新开页面先订阅，再查询用户资料；关闭期间的历史事件不补发，先到的新事件不能被较旧查询覆盖。
- `onBookAudioError`：沿用现有 `{code,message}`。业务请求错误直接发给发起文档，不调用成功回调；会话异步错误通过订阅推送。新增 actionName/callbackActionName 关联字段尚未确认，因此没有添加；不要按到达顺序将错误配给某个并发请求。开窗／关窗／打开登录／分享的标准无业务回调行为仍按各自约定处理。

错误码包括 INVALID_ARGUMENT、INVALID_STATE、BUSY、LOGIN_REQUIRED、SOURCE_NOT_READY、UNSUPPORTED、PLAYBACK_FAILED、HOST_FAILED、UNTRUSTED_SOURCE、DISPOSED、STORAGE_FAILED。解码后的业务 JSON 仍限 256 Ki 个 UTF-16 单元（NSString.length）；编码消息另设 4 MiB 长度上限，为中文等字符的 URI 编码膨胀预留空间。导航、关闭、Web 内容进程终止后，旧文档的异步结果不投递到新页面；这与客户端版本兼容无关。

sleepTimer.mode 为 off/duration/trackCount。duration 返回 durationMs/remainingMs；trackCount 返回 targetCount/remainingCount，时长完整且可播时才返回 estimatedRemainingMs。H5 用 Math.ceil(ms/60000) 展示分钟，缺失时显示“时长待获取”。

按数量定时从当前播放或暂停章算起，自然完成计 1；手动切章、Seek 到章末不计数。同一媒体实例只结算一次，达到数量先停止再决定续章；队列不足时在末尾结束，不循环。没有有效当前媒体项时拒绝设置。

按时长定时在暂停、缓冲、后台和设备睡眠期间继续计时；倍速不改变截止时间。到期暂停并保存断点。Stop/Dispose/换书清除定时，同书 SetQueue、关页、重开及手动切章保留。

## 联调资源

`DemoResources/Fixture` 提供本地页面及测试音频。`Tests/Fixtures/XinhuaSDK` 保存原版前端库，供 XCTest 在实际 WKWebView 中验证窗口、账号、分享、听书命令和事件。正式 H5、账号及资源由宿主配置。
