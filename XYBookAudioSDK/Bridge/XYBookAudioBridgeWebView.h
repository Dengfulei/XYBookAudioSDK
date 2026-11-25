// WebView 传输层：注册 H5 对象及原生回调，不解析业务协议，不决定窗口导航或播放行为。
#import <WebKit/WebKit.h>
#import "XYBookAudioScriptMessageHandler.h"

@interface XYBookAudioBridgeWebView : WKWebView

/// 在加载页面前通过 EasyJS.inject 注册 window.xhAppJSBridge.JSCallNative；每个 WebView 使用独立接口对象。
/// @param interface 本 WebView 的 EasyJS 消息处理器。
- (void)addJavascriptInterface:(XYBookAudioScriptMessageHandler *)interface;
/// 页面释放时解除 WebKit 对接口对象的持有。
- (void)removeJavascriptInterface;
/// 通过 `window.xhWebJSBridge.nativeCallJS` 发送原生消息。
/// @param message 含 `actionName` 和可选 `parameters` 的 JSON 字典。
/// @param completion 可选的发送结果回调。收到的错误来自 JSON 序列化或 JavaScript 执行。
- (void)nativeCallJS:(NSDictionary *)message completion:(void (^)(NSError *error))completion;

@end
