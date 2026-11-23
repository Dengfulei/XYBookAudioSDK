# SNCK v1 的 iOS 接入

iOS 按《JS_PROTOCOL.md》的 SNCK v1 接入。H5 调用 `window.xhAppJSBridge.JSCallNative(JSON.stringify(request))`，原生通过 `window.xhWebJSBridge.nativeCallJS(payload)` 返回 JS 对象。

```js
window.xhWebJSBridge = {
  nativeCallJS(payload) {
    // 按 actionName 匹配请求回调或处理主动事件。
    console.log(payload);
  }
};

window.xhAppJSBridge.JSCallNative(JSON.stringify({
  actionName: 'xhSnckReady',
  callbackActionName: 'snck_cb_ready_1',
  parameters: {}
}));
```

请求内的 `parameters` 是对象。回包用请求的 `callbackActionName` 作为 `actionName`，成功回传业务数据，开关页面成功时省略 `parameters`。失败时 `parameters` 为 `{code, message}`，`code` 为数字。未支持的动作返回 `-3`。

原生通过 `actionName + ":"` 调用同名 Objective-C 方法。例如 `xhSnckClosePage` 对应 `xhSnckClosePage:`。Ready 能力列表直接从这些方法生成。

## H5 动作

| 动作 | 参数 | 成功结果 |
| --- | --- | --- |
| `xhSnckReady` | 无 | `protocolVersion`、`capabilities`、`userState`、`playback` |
| `xhSnckGetUserInfo` | 无 | UserState |
| `xhSnckOpenPage` | `url`，可选 `title` | 无 |
| `xhSnckClosePage` | 无 | 无 |
| `xhSnckShare` | `title`、`link`，可选 `description`、`imageUrl`、`platform` | `requestId`、`status` |
| `xhSnckAudioSetQueue` | `items`，可选 `startIndex`、`autoPlay` | PlaybackSnapshot |
| `xhSnckAudioGetQueue` | 无 | `items`、`queueVersion` |
| `xhSnckAudioPlayAt` | `index` | PlaybackSnapshot |
| `xhSnckAudioSeekTo` | `positionMs` | PlaybackSnapshot |
| `xhSnckAudioPrevious` | 无 | PlaybackSnapshot |
| `xhSnckAudioNext` | 无 | PlaybackSnapshot |
| `xhSnckAudioPlay` | 无 | PlaybackSnapshot |
| `xhSnckAudioPause` | 无 | PlaybackSnapshot |
| `xhSnckAudioStop` | 无 | PlaybackSnapshot |
| `xhSnckAudioGetState` | 无 | PlaybackSnapshot |
| `xhSnckAudioSetTimer` | `mode`，按模式提供 `count` 或 `durationMs` | PlaybackSnapshot |
| `xhSnckAudioGetTimer` | 无 | TimerState |

每个文档先设置回包入口，再调用 Ready。原生向已 Ready 且可见的页面发送 `snckUserChanged`、`snckAudioStateChanged`、`snckAudioQueueChanged`、`snckAudioProgress`、`snckAudioTimerChanged` 和 `snckAudioError`。重开页面从 Ready 的快照恢复展示。关闭听书页面保留会话，`xhSnckAudioStop` 清空队列和定时。

用户查询读取宿主同步后的身份。登录、退出或切换账号后，宿主接入层调用 `refreshHostIdentity`，SDK 停止播放并清空队列，H5 可按新身份重新下发音源。分享复用宿主接口，宿主返回 `XYBookAudioShareAccepted` 对应 `DISPATCHED`，`XYBookAudioShareSucceeded` 对应 `SUCCESS`。

iOS 只允许可信 HTTPS 窗口使用线上 Bridge。音源使用绝对 HTTP(S) 地址，HTTP 是否可播放取决于宿主 App 的网络安全配置。解码后的请求最多 81920 个 UTF-16 代码单元。无法解析或缺少回调标识的请求可能没有回包，H5 应保留超时处理。
