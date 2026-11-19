// WebView 传输层：注册 H5 对象及原生回调，不解析业务协议，不决定窗口导航或播放行为。
#import <WebKit/WebKit.h>
#import "XYBookAudioScriptMessageHandler.h"

@interface XYBookAudioBridgeWebView : WKWebView

/// 在加载页面前通过 EasyJS.inject 注册 window.xhAppJSBridge.JSCallNative；每个 WebView 使用独立接口对象。
- (void)addJavascriptInterface:(XYBookAudioScriptMessageHandler *)interface;
/// 页面释放时解除 WebKit 对接口对象的持有。
- (void)removeJavascriptInterface;
/// 按原项目的“回调方法(JSON)”方式回调原版 xinhua-sdk，保持 actionName / parameters 原样传递。
- (void)nativeCallJS:(NSDictionary *)message completion:(void (^)(NSError *error))completion;

@end
