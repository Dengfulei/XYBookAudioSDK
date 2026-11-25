// 组装 WebView、导航与加载／重试界面；宿主只负责展示 SDK 页面，文件和 HTTPS 加载在此管理。
#import "XYBookAudioWebViewController.h"
#import "XYBookAudioWebBridge.h"
#import "XYBookAudioUserAgent.h"
#import "XYBookAudioMessageProtocol.h"
#import "XYBookAudioPaymentLinks.h"

#import "XYBookAudioLogger.h"

@interface XYBookAudioWebViewController () <WKNavigationDelegate, WKUIDelegate>

@property (nonatomic, strong) XYBookAudioLogger *logger;

@property (nonatomic, weak) XYBookAudioSDKManager *SDK;
@property (nonatomic, strong) XYBookAudioConfiguration *configuration;
@property (nonatomic, strong) NSURL *entryURL;
@property (nonatomic, weak) id<XYBookAudioWindowRouting> windowRouter;
@property (nonatomic, strong) XYBookAudioWebBridge *webBridge;
@property (nonatomic, strong) XYBookAudioBridgeWebView *webView;
@property (nonatomic, strong) UIActivityIndicatorView *spinner;
@property (nonatomic, strong) UIButton *retryButton;
@property (nonatomic, weak) UINavigationController *navigationWithHiddenBar;
@property (nonatomic) BOOL navigationBarWasHidden;
@property (nonatomic) BOOL closing;
@property (nonatomic, strong) XYBookAudioUserAgent *userAgentProvider;
// 有原收银台历史项时，微信中转流程仍在进行。
@property (nonatomic, strong) WKBackForwardListItem *wechatCheckoutItem;
@property (nonatomic, strong) NSURL *wechatReloadURL;
@property (nonatomic, strong) NSUUID *paymentLaunchToken;

@end

@implementation XYBookAudioWebViewController

- (instancetype)initWithSDK:(XYBookAudioSDKManager *)SDK
              configuration:(XYBookAudioConfiguration *)configuration
                   entryURL:(NSURL *)entryURL
               windowRouter:(id<XYBookAudioWindowRouting>)windowRouter
                     logger:(XYBookAudioLogger *)logger {
    if ((self = [super initWithNibName:nil bundle:nil])) {
        _SDK = SDK;
        _logger = logger;
        _configuration = configuration;
        _entryURL = entryURL;
        _windowRouter = windowRouter;
    }
    return self;
}

/// 创建页面级 Bridge 和 WebView；注入脚本在文档开始前安装，实际播放仍由原生会话承担。
- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = self.title ?: @"听书";
    self.view.backgroundColor = UIColor.systemBackgroundColor;
    WKWebViewConfiguration *configuration = [WKWebViewConfiguration new];
    // 对齐 XYWebBrowerController 的网页存储：同源窗口共享 localStorage 和 Cookie，关闭重开不丢失。
    // 默认数据存储由宿主 App 共用；不要为每页新建匿名存储，也不要在关闭 SDK 时清空宿主网页数据。
    configuration.websiteDataStore = WKWebsiteDataStore.defaultDataStore;
    configuration.mediaTypesRequiringUserActionForPlayback = WKAudiovisualMediaTypeAll;
    self.webView = [[XYBookAudioBridgeWebView alloc] initWithFrame:self.view.bounds configuration:configuration];
    self.webView.scrollView.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentNever;
#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 260000
    if (@available(iOS 26.0, *)) {
        // 页面背景延伸到状态栏，避免系统滚动边缘渐变改变网页顶部颜色。
        self.webView.scrollView.topEdgeEffect.hidden = YES;
    }
#endif
    if (@available(iOS 16.4, *)) {
        self.webView.inspectable = self.configuration.webInspectorEnabled;
    }
    self.webBridge = [[XYBookAudioWebBridge alloc] initWithSDK:self.SDK configuration:self.configuration
                                                       webView:self.webView
                                                        logger:self.logger];
    self.webBridge.page = self;
    self.webBridge.windowRouter = self.windowRouter;
    self.webView.navigationDelegate = self;
    self.webView.UIDelegate = self;
    [self layoutContent];
    [self loadEntry];
}

/// 只在当前听书页显示期间隐藏原生导航栏。
- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    UINavigationController *navigation = self.navigationController;
    if (self.navigationWithHiddenBar != navigation) {
        self.navigationBarWasHidden = navigation.isNavigationBarHidden;
        self.navigationWithHiddenBar = navigation;
    }
    [navigation setNavigationBarHidden:YES animated:animated];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [self.navigationWithHiddenBar setNavigationBarHidden:self.navigationBarWasHidden animated:animated];
    self.navigationWithHiddenBar = nil;
}

/// WebView 贴齐容器上下边缘，原生操作控件留在安全区内。
- (void)layoutContent {
    self.spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
    self.retryButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.retryButton.titleLabel.numberOfLines = 0;
    self.retryButton.titleLabel.textAlignment = NSTextAlignmentCenter;
    [self.retryButton addTarget:self action:@selector(loadEntry) forControlEvents:UIControlEventTouchUpInside];
    for (UIView *view in @[ self.webView, self.spinner, self.retryButton ]) {
        view.translatesAutoresizingMaskIntoConstraints = NO;
        [self.view addSubview:view];
    }
    UILayoutGuide *safe = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [self.webView.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [self.webView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
        [self.webView.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor],
        [self.webView.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [self.spinner.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [self.spinner.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor],
        [self.retryButton.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [self.retryButton.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor],
        [self.retryButton.widthAnchor constraintLessThanOrEqualToAnchor:safe.widthAnchor multiplier:0.85],
    ]];
}

/// 重新加载当前窗口入口；本地页面与读取授权统一解析路径，避免真机路径别名导致沙盒拒绝。
- (void)loadEntry {
    if (self.closing || self.userAgentProvider) {
        return;
    }
    self.retryButton.hidden = YES;
    self.webView.hidden = NO;
    [self.spinner startAnimating];
    // 首次请求必须携带端内标识；配置失败显示重试，不允许带着缺失标识的 UA 继续加载。
    if (self.webView.customUserAgent.length == 0) {
        [self prepareUserAgent];
        return;
    }
    [self.logger write:XYBookAudioLogLevelInfo component:XYBookAudioLogPage
               message:self.entryURL.isFileURL ? @"Loading local page." : @"Loading HTTPS page."];
    if (self.entryURL.isFileURL) {
        // WebKit 对比主资源路径和读取授权路径；两者必须使用相同的规范路径。
        // 真机 Bundle 可能使用 /private/var，而解析后的授权目录使用 /var，不能只规范化一侧。
        NSURL *entryURL = self.entryURL.URLByResolvingSymlinksInPath;
        [self.webView loadFileURL:entryURL allowingReadAccessToURL:self.configuration.localResourceDirectory];
    } else {
        // 入口 HTML 决定本次加载的 JS/CSS 版本，打开和重试时跳过本地缓存。
        NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:self.entryURL];
        request.cachePolicy = NSURLRequestReloadIgnoringLocalCacheData;
        [self.webView loadRequest:request];
    }
}

/// 首次加载前配置实例 UA；读取失败可重试，页面关闭后忽略结果，避免继续请求业务页面。
- (void)prepareUserAgent {
    self.userAgentProvider = [[XYBookAudioUserAgent alloc] initWithWebView:self.webView];
    __weak typeof(self) weakSelf = self;
    [self.userAgentProvider prepareWithCompletion:^(NSString *userAgent, NSError *error) {
        typeof(self) strongSelf = weakSelf;
        if (!strongSelf || strongSelf.closing) {
            return;
        }
        strongSelf.userAgentProvider = nil;
        if (error) {
            [strongSelf.logger error:error component:XYBookAudioLogPage operation:@"Read WebView user agent"];
            [strongSelf showError:@"听书页面初始化失败"];
            return;
        }
        strongSelf.webView.customUserAgent = userAgent;
        [strongSelf.logger write:XYBookAudioLogLevelDebug component:XYBookAudioLogPage
                         message:@"WebView user agent configured."];
        [strongSelf loadEntry];
    }];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    [self.webBridge pageDidAppear];
}

/// 优先回退 H5 历史；没有历史时关闭页面，播放会话继续保留。
- (void)goBack {
    if (self.webView.canGoBack) {
        [self.webView goBack];
        return;
    }
    NSError *error = [self.windowRouter closeWindowFromPage:self beforeClose:nil];
    if (error) {
        [self.logger error:error component:XYBookAudioLogPage operation:XYBookAudioActionCloseWindow];
    }
}

/// 幂等撤销当前文档及异步 UA 任务；播放会话独立于页面生命周期。
- (void)invalidatePage {
    if (self.closing) {
        return;
    }
    self.closing = YES;
    [self clearPayment];
    [self.userAgentProvider cancel];
    self.userAgentProvider = nil;
    [self.webBridge invalidate];
    [self.webView stopLoading];
    [self.logger write:XYBookAudioLogLevelInfo component:XYBookAudioLogPage
               message:@"Page closed; playback session retained."];
}

/// 只有完成出栈才清理，推入子页／宿主登录或取消交互式返回都应保留当前文档。
- (void)didMoveToParentViewController:(UIViewController *)parent {
    [super didMoveToParentViewController:parent];
    if (!parent) {
        [self invalidatePage];
        dispatch_block_t didLeaveNavigation = self.didLeaveNavigation;
        self.didLeaveNavigation = nil;
        if (didLeaveNavigation) {
            didLeaveNavigation();
        }
    }
}

- (void)webView:(WKWebView *)webView
    decidePolicyForNavigationAction:(WKNavigationAction *)action
                    decisionHandler:(void (^)(WKNavigationActionPolicy))decisionHandler {
    if ([self handlePaymentNavigation:action webView:webView decisionHandler:decisionHandler]) {
        return;
    }
    BOOL main = action.targetFrame.isMainFrame || !action.targetFrame;
    BOOL allowed = !main || [self.configuration allowsURL:action.request.URL];
    if (!allowed) {
        [self.logger write:XYBookAudioLogLevelWarning component:XYBookAudioLogPage
                   message:@"Untrusted navigation rejected."];
        [self showError:@"页面地址不在可信范围内"];
    }
    decisionHandler(allowed ? WKNavigationActionPolicyAllow : WKNavigationActionPolicyCancel);
}

- (WKWebView *)webView:(WKWebView *)webView
    createWebViewWithConfiguration:(WKWebViewConfiguration *)configuration
               forNavigationAction:(WKNavigationAction *)action
                    windowFeatures:(WKWindowFeatures *)features {
    if ([self.configuration allowsURL:action.request.URL]) {
        [webView loadRequest:action.request];
    }
    return nil;
}

- (void)webView:(WKWebView *)webView didStartProvisionalNavigation:(WKNavigation *)navigation {
    if (!self.wechatCheckoutItem) {
        [self.webBridge invalidate];
    }
    [self.spinner startAnimating];
}

- (void)webView:(WKWebView *)webView didCommitNavigation:(WKNavigation *)navigation {
    BOOL trusted = [self.configuration allowsURL:webView.URL];
    if (self.wechatCheckoutItem) {
        [self.webBridge invalidate];
        if (trusted && !self.paymentLaunchToken) {
            [self clearPayment];
        }
    }
    if (trusted) {
        [self.webBridge activate];
    }
}

- (void)webView:(WKWebView *)webView didFinishNavigation:(WKNavigation *)navigation {
    [self.spinner stopAnimating];
    [self.logger write:XYBookAudioLogLevelInfo component:XYBookAudioLogPage message:@"Page load finished."];
}

- (void)webView:(WKWebView *)webView didFailNavigation:(WKNavigation *)navigation withError:(NSError *)error {
    [self failed:error];
}

- (void)webView:(WKWebView *)webView
    didFailProvisionalNavigation:(WKNavigation *)navigation
                       withError:(NSError *)error {
    [self failed:error];
}

- (void)webViewWebContentProcessDidTerminate:(WKWebView *)webView {
    [self clearPayment];
    [self.logger write:XYBookAudioLogLevelError component:XYBookAudioLogPage
               message:@"Web content process terminated."];
    [self showError:@"页面进程已退出，播放会话仍保留"];
}

#pragma mark - H5 支付

- (BOOL)isPaymentCheckoutAction:(WKNavigationAction *)action {
    NSURL *entry = self.configuration.entryURL;
    return action.sourceFrame.isMainFrame && self.viewIfLoaded.window &&
           self.navigationController.topViewController == self &&
           [XYBookAudioPaymentLinks checkoutURL:action.sourceFrame.request.URL matchesEntryURL:entry] &&
           [XYBookAudioPaymentLinks checkoutURL:self.webView.backForwardList.currentItem.URL matchesEntryURL:entry];
}

- (BOOL)handlePaymentNavigation:(WKNavigationAction *)action
                        webView:(WKWebView *)webView
                decisionHandler:(void (^)(WKNavigationActionPolicy))decide {
    XYBookAudioPaymentConfiguration *payment = self.configuration.payment;
    if (!payment || self.closing) {
        return NO;
    }
    NSURLRequest *request = action.request;
    NSURL *URL = request.URL;
    XYBookAudioPaymentLinkType type = [XYBookAudioPaymentLinks typeForURL:URL];
    if (type == XYBookAudioPaymentLinkTypeNone) {
        return NO;
    }
    if ((action.targetFrame && !action.targetFrame.isMainFrame) || self.paymentLaunchToken) {
        decide(WKNavigationActionPolicyCancel);
        return YES;
    }
    if (type == XYBookAudioPaymentLinkTypeWeChatGateway && [self.wechatReloadURL isEqual:URL] && action.targetFrame) {
        self.wechatReloadURL = nil;
        decide(WKNavigationActionPolicyAllow);
        return YES;
    }
    if (type == XYBookAudioPaymentLinkTypeWeChatGateway && payment.wechatReturnScheme && !self.wechatCheckoutItem &&
        [request.HTTPMethod isEqualToString:@"GET"] && [self isPaymentCheckoutAction:action]) {
        self.wechatCheckoutItem = webView.backForwardList.currentItem;
        self.wechatReloadURL = URL;
        NSMutableURLRequest *reload = [request mutableCopy];
        [reload setValue:[payment.wechatReturnScheme stringByAppendingString:@"://"] forHTTPHeaderField:@"Referer"];
        decide(WKNavigationActionPolicyCancel);
        [webView loadRequest:reload];
        return YES;
    }

    decide(WKNavigationActionPolicyCancel);
    if (type == XYBookAudioPaymentLinkTypeWeChatApp) {
        BOOL fromGateway = action.sourceFrame.isMainFrame &&
            [XYBookAudioPaymentLinks typeForURL:action.sourceFrame.request.URL] == XYBookAudioPaymentLinkTypeWeChatGateway;
        if (self.wechatCheckoutItem && !self.wechatReloadURL && (fromGateway || [self isPaymentCheckoutAction:action])) {
            [self openPaymentURL:URL];
        }
        return YES;
    }

    if (type == XYBookAudioPaymentLinkTypeAlipayApp && payment.alipayReturnScheme && !self.wechatCheckoutItem &&
        [self isPaymentCheckoutAction:action]) {
        NSURL *appURL = [XYBookAudioPaymentLinks alipayURLFromURL:URL withReturnScheme:payment.alipayReturnScheme];
        if (appURL) {
            [self openPaymentURL:appURL];
        } else {
            [self.logger write:XYBookAudioLogLevelWarning component:XYBookAudioLogPage
                       message:@"Invalid Alipay SafePay URL."];
        }
    }
    return YES;
}

- (void)openPaymentURL:(NSURL *)URL {
    NSUUID *token = NSUUID.UUID;
    self.paymentLaunchToken = token;
    __weak typeof(self) weakSelf = self;
    [UIApplication.sharedApplication openURL:URL options:@{} completionHandler:^(BOOL opened) {
        if (weakSelf.paymentLaunchToken != token) {
            return;
        }
        if (!opened) {
            [weakSelf.logger write:XYBookAudioLogLevelWarning component:XYBookAudioLogPage
                           message:@"Unable to open payment app."];
        }
        [weakSelf returnToPaymentCheckout];
    }];
}

- (void)returnToPaymentCheckout {
    WKBackForwardListItem *checkout = self.wechatCheckoutItem;
    WKBackForwardListItem *current = self.webView.backForwardList.currentItem;
    [self clearPayment];
    [self.spinner stopAnimating];
    if (checkout && current != checkout &&
        [XYBookAudioPaymentLinks typeForURL:current.URL] == XYBookAudioPaymentLinkTypeWeChatGateway) {
        [self.webView goToBackForwardListItem:checkout];
    }
}

- (void)clearPayment {
    self.wechatCheckoutItem = nil;
    self.wechatReloadURL = nil;
    self.paymentLaunchToken = nil;
}

/// 用户取消导航不作为加载失败；其他错误经可配置日志记录域／码，页面显示统一重试提示。
- (void)failed:(NSError *)error {
    // WebKit 用 102 表示导航被策略取消，支付链接拦截也可能收到此回调。
    if (([error.domain isEqualToString:NSURLErrorDomain] && error.code == NSURLErrorCancelled) ||
        ([error.domain isEqualToString:@"WebKitErrorDomain"] && error.code == 102)) {
        return;
    }
    if (self.wechatCheckoutItem) {
        [self.logger error:error component:XYBookAudioLogPage operation:@"H5 payment"];
        [self returnToPaymentCheckout];
        return;
    }
    [self.logger error:error component:XYBookAudioLogPage operation:@"Page load"];
    [self showError:@"听书页面加载失败"];
}

/// 失效页面回调并展示重试入口；原生会话及断点不随网页错误丢失。
- (void)showError:(NSString *)message {
    [self.webBridge invalidate];
    [self.spinner stopAnimating];
    self.webView.hidden = YES;
    self.retryButton.hidden = NO;
    [self.retryButton setTitle:[message stringByAppendingString:@"\n点击重试"] forState:UIControlStateNormal];
}

- (void)dealloc {
    [self.userAgentProvider cancel];
    [self.webBridge invalidate];
    [self.webView removeJavascriptInterface];
}

@end
