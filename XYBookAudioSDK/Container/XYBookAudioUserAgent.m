// 使用独立的空白文档读取默认 UA，避免初始化阶段的移动 UA 覆盖平板的桌面 UA。
#import "XYBookAudioUserAgent.h"
#import "XYBookAudioTypes.h"

// 与现有 H5 的端内识别约定一致；账号身份继续通过 JS Bridge 同步。
static NSString *const XYBookAudioUserAgentMarker = @"MediaConvergenceXinhua";

@interface XYBookAudioUserAgent () <WKNavigationDelegate>
@property (nonatomic, strong) WKWebView *probeWebView;
@property (nonatomic, copy, nullable) void (^completion)(NSString *_Nullable, NSError *_Nullable);
@end

@implementation XYBookAudioUserAgent

- (instancetype)initWithWebView:(WKWebView *)webView {
    if ((self = [super init])) {
        WKWebViewConfiguration *configuration = [WKWebViewConfiguration new];
        configuration.websiteDataStore = WKWebsiteDataStore.nonPersistentDataStore;
        configuration.defaultWebpagePreferences.preferredContentMode =
            webView.configuration.defaultWebpagePreferences.preferredContentMode;
        _probeWebView = [[WKWebView alloc] initWithFrame:webView.bounds configuration:configuration];
        _probeWebView.navigationDelegate = self;
    }
    return self;
}

- (void)prepareWithCompletion:(void (^)(NSString *, NSError *))completion {
    self.completion = completion;
    // 必须等空白文档完成导航，WebKit 才会按页面偏好确定移动／桌面 UA；此处没有网络请求。
    [self.probeWebView loadHTMLString:@"<!doctype html><html><head></head><body></body></html>" baseURL:nil];
}

/// 文档完成后读取浏览器实际 UA，不拼造系统版本，也不把账号或设备标识附加到 UA。
- (void)webView:(WKWebView *)webView didFinishNavigation:(WKNavigation *)navigation {
    __weak typeof(self) weakSelf = self;
    [webView evaluateJavaScript:@"navigator.userAgent" completionHandler:^(id result, NSError *error) {
        if (error) {
            [weakSelf finishWithUserAgent:nil error:error];
            return;
        }
        if (![result isKindOfClass:NSString.class] || [result length] == 0) {
            [weakSelf
                finishWithUserAgent:nil
                              error:XYBookAudioError(XYBookAudioInvalidState, @"WebView user agent is unavailable.")];
            return;
        }
        NSString *userAgent = result;
        NSArray<NSString *> *tokens =
            [userAgent componentsSeparatedByCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        // 按完整标识去重，已有同名后缀时保留原值；该类不修改宿主或进程全局配置。
        NSString *customUserAgent = [tokens containsObject:XYBookAudioUserAgentMarker]
                                        ? userAgent
                                        : [userAgent stringByAppendingFormat:@" %@", XYBookAudioUserAgentMarker];
        [weakSelf finishWithUserAgent:customUserAgent error:nil];
    }];
}

/// 临时文档加载失败时交由页面显示重试，不返回缺少标识的默认 UA。
- (void)webView:(WKWebView *)webView
    didFailProvisionalNavigation:(WKNavigation *)navigation
                       withError:(NSError *)error {
    [self finishWithUserAgent:nil error:error];
}

- (void)webView:(WKWebView *)webView didFailNavigation:(WKNavigation *)navigation withError:(NSError *)error {
    [self finishWithUserAgent:nil error:error];
}

- (void)webViewWebContentProcessDidTerminate:(WKWebView *)webView {
    [self finishWithUserAgent:nil
                        error:XYBookAudioError(XYBookAudioInvalidState, @"WebView user agent process terminated.")];
}

/// 先清理再回调，保证失败与进程退出同时到达时只结算一次，且临时 WebView 不被接入层长期持有。
- (void)finishWithUserAgent:(NSString *)userAgent error:(NSError *)error {
    void (^completion)(NSString *, NSError *) = self.completion;
    [self cancel];
    if (completion) {
        completion(userAgent, error);
    }
}

- (void)cancel {
    self.completion = nil;
    self.probeWebView.navigationDelegate = nil;
    [self.probeWebView stopLoading];
    self.probeWebView = nil;
}

- (void)dealloc {
    [self cancel];
}

@end
