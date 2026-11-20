// 窗口导航仅作用于 SDK 自有容器；子页沿用初始可信范围，不通过更换入口扩大文件或域名权限。
#import "XYBookAudioNavigationController.h"
#import "XYBookAudioWebViewController.h"
#import "XYBookAudioMessageProtocol.h"

@interface XYBookAudioNavigationController ()
@property (nonatomic, weak) XYBookAudioSDKManager *SDK;
@property (nonatomic, strong) XYBookAudioConfiguration *configuration;
@property (nonatomic, strong) XYBookAudioLogger *logger;
@property (nonatomic) BOOL closing;
@end

@implementation XYBookAudioNavigationController

/// 初始化唯一根窗口；配置由 SDK 持有副本，所有子页共享同一播放和可信地址边界。
- (instancetype)initWithSDK:(XYBookAudioSDKManager *)SDK
              configuration:(XYBookAudioConfiguration *)configuration
                     logger:(XYBookAudioLogger *)logger {
    if ((self = [super initWithNavigationBarClass:nil toolbarClass:nil])) {
        _SDK = SDK;
        _configuration = configuration;
        _logger = logger;
        self.viewControllers = @[ [self pageWithURL:configuration.entryURL] ];
    }
    return self;
}

/// 每个窗口拥有独立 WebView 和 Bridge；入口地址与可信配置分开，避免本地子目录缩窄授权。
- (XYBookAudioWebViewController *)pageWithURL:(NSURL *)URL {
    return [[XYBookAudioWebViewController alloc] initWithSDK:self.SDK configuration:self.configuration entryURL:URL
                                                windowRouter:self
                                                      logger:self.logger];
}

/// 隐藏父页、转场或宿主界面占用时拒绝导航，避免误操作其他窗口。
- (NSError *)navigationErrorFromPage:(UIViewController *)page {
    if (self.closing || self.isBeingDismissed || page != self.topViewController || !page.viewIfLoaded.window ||
        self.transitionCoordinator || self.presentedViewController || page.presentedViewController) {
        return XYBookAudioError(XYBookAudioBusy, @"The current web window is not available for navigation.");
    }
    return nil;
}

/// 关闭当前网页：子页返回上一页，唯一根页 dismiss SDK 容器，播放会话继续保留。
- (NSError *)closeWindowFromPage:(UIViewController *)page beforeClose:(dispatch_block_t)beforeClose {
    NSError *error = [self navigationErrorFromPage:page];
    if (error) {
        return error;
    }
    if (beforeClose) {
        beforeClose();
    }
    if (self.viewControllers.count == 1) {
        [self closeAllPages];
    } else {
        [self popViewControllerAnimated:YES];
    }
    return nil;
}

/// 子页复用最初的可信范围；接受导航不代表网页已经加载成功。
- (NSError *)openWindowWithURL:(NSURL *)URL title:(NSString *)title fromPage:(UIViewController *)page {
    NSError *error = [self navigationErrorFromPage:page];
    if (error) {
        return error;
    }
    if (![self.configuration allowsURL:URL]) {
        return XYBookAudioError(XYBookAudioUntrustedSource, @"The new window URL is outside the trusted scope.");
    }
    UIViewController *child = [self pageWithURL:URL];
    child.title = title;
    [self pushViewController:child animated:YES];
    [self.logger write:XYBookAudioLogLevelInfo component:XYBookAudioLogPage message:@"New web window opened."];
    return nil;
}

/// 幂等关闭整个容器；先撤销全部网页回调，再完成展示释放，播放状态仍由 SDK 会话管理。
- (void)closeAllPages {
    if (self.closing) {
        return;
    }
    self.closing = YES;
    [self invalidatePages];
    [self dismissViewControllerAnimated:YES completion:^{
        [self notifyClosed];
    }];
}

/// 宿主可能直接 dismiss 导航容器；仅在容器被移除时清理，登录覆盖页面不触发此路径。
- (void)viewDidDisappear:(BOOL)animated {
    [super viewDidDisappear:animated];
    if (self.isBeingDismissed || !self.presentingViewController) {
        self.closing = YES;
        [self invalidatePages];
        [self notifyClosed];
    }
}

/// 隐藏在栈内的父网页也要撤销订阅；宿主推入的登录控制器由宿主自身处理生命周期。
- (void)invalidatePages {
    for (UIViewController *controller in self.viewControllers) {
        if ([controller isKindOfClass:XYBookAudioWebViewController.class]) {
            [(XYBookAudioWebViewController *)controller invalidatePage];
        }
    }
}

/// 外部 dismiss 与主动关闭可能同时完成，先清空回调保证 SDK 只释放一次展示占用。
- (void)notifyClosed {
    void (^closed)(void) = self.closed;
    self.closed = nil;
    if (closed) {
        closed();
    }
}

@end
