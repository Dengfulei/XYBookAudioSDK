// 仅负责读取 WebKit 默认 UA 并追加端内标识；临时 WebView 不加载业务页面，不读取宿主账号。
#import <WebKit/WebKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface XYBookAudioUserAgent : NSObject

/// 沿用目标 WebView 的视口和内容模式，避免移动／桌面模式的默认 UA 不一致。
- (instancetype)initWithWebView:(WKWebView *)webView;
/// 加载空白本地文档后读取 UA；成功返回完整 UA，失败返回错误，取消后不再回调。
- (void)prepareWithCompletion:(void (^)(NSString *_Nullable userAgent, NSError *_Nullable error))completion;
/// 页面关闭时取消探测并释放临时 WebView，不修改任何全局 UA 设置。
- (void)cancel;

@end

NS_ASSUME_NONNULL_END
