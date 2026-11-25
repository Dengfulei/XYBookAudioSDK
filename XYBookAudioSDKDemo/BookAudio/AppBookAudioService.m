// 宿主接入适配器：管理 SDK 生命周期、事件转发及账号/分享/音频路由；不实现播放或 JS 协议。
#import "AppBookAudioService.h"
#import "../Account/AppAccountService.h"
#import "../Account/AppLoginViewController.h"

NSNotificationName const AppBookAudioServiceEventNotification = @"AppBookAudioServiceEventNotification";
NSString *const AppBookAudioServiceEventNameKey = @"event";
NSString *const AppBookAudioServiceEventParametersKey = @"parameters";

 //带 completion 的宿主接入示例使用以下结果映射。
static XYBookAudioLoginResult AppBookAudioLoginResultFromHost(AppLoginResult result) {
    switch (result) {
        case AppLoginSucceeded:
            return XYBookAudioLoginLoggedIn;
        case AppLoginCancelled:
            return XYBookAudioLoginCancelled;
        case AppLoginFailed:
            return XYBookAudioLoginFailed;
    }
}


@interface AppBookAudioService () <XYBookAudioHost>
@property (nonatomic, strong, nullable) XYBookAudioSDKManager *SDK;
@property (nonatomic, copy, nullable) XYBookAudioConfiguration *configuration;
@property (nonatomic, strong, nullable) NSUUID *eventSubscription;
@end

@implementation AppBookAudioService

+ (instancetype)sharedInstance {
    static AppBookAudioService *service;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        service = [[self alloc] initPrivate];
    });
    return service;
}

/// 接入层只观察宿主账号变更，不保存另一份身份；注册观察者不会初始化 SDK。
- (instancetype)initPrivate {
    if ((self = [super init])) {
        [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(accountDidChange:)
                                                   name:AppAccountDidChangeNotification
                                                 object:AppAccountService.sharedInstance];
    }
    return self;
}

- (void)dealloc {
    [NSNotificationCenter.defaultCenter removeObserver:self];
}

/// 账号模块先提交身份再发通知，接入层统一刷新身份并继续等待中的无回调登录。
- (void)accountDidChange:(NSNotification *)notification {
    [self refreshHostIdentity];
}

- (BOOL)configureWithConfiguration:(XYBookAudioConfiguration *)configuration error:(NSError **)error {
    NSParameterAssert(NSThread.isMainThread);
    if (self.SDK) {
        if (error) {
            *error = XYBookAudioError(XYBookAudioBusy, @"听书服务已初始化，请先明确结束已有会话再重新配置。");
        }
        return NO;
    }
    XYBookAudioSDKManager *SDK = [[XYBookAudioSDKManager alloc] initWithConfiguration:configuration host:self
                                                                                error:error];
    if (!SDK) {
        return NO;
    }
    self.configuration = [configuration copy];
    self.SDK = SDK;
    __weak typeof(self) weakSelf = self;
    self.eventSubscription = [SDK subscribe:^(NSString *event, NSDictionary *parameters) {
        AppBookAudioService *service = weakSelf;
        if (service) {
            [NSNotificationCenter.defaultCenter postNotificationName:AppBookAudioServiceEventNotification object:service
                                                            userInfo:@{
                                                                AppBookAudioServiceEventNameKey : event,
                                                                AppBookAudioServiceEventParametersKey : parameters
                                                            }];
        }
    }];
    return YES;
}

/// 重建时沿用已确认的配置；Demo 默认打开参考消息测试环境。
- (BOOL)prepareSessionWithError:(NSError **)error {
    if (self.SDK) {
        return YES;
    }
    if (self.configuration) {
        return [self configureWithConfiguration:self.configuration error:error];
    }
    NSURL *entry = [NSURL URLWithString:@"https://cankaoxiaoxi.testnewmedia.xinhuaapp.com/h5/snck/index.html#/?hideTopView=1&vc=1"];
    XYBookAudioConfiguration *configuration =
        [[XYBookAudioConfiguration alloc] initWithHostIdentifier:NSBundle.mainBundle.bundleIdentifier entryURL:entry];
    XYBookAudioPaymentConfiguration *payment = [XYBookAudioPaymentConfiguration new];
    payment.wechatReturnScheme = [XYBookAudioPaymentConfiguration hostURLSchemeForName:@"weixinScheme"];
    payment.alipayReturnScheme = [XYBookAudioPaymentConfiguration hostURLSchemeForName:@"appScheme"];
    if (payment.wechatReturnScheme || payment.alipayReturnScheme) {
        configuration.payment = payment;
    }
    configuration.webInspectorEnabled = YES;
#if DEBUG
    // 仅示例本地调试开启日志；正式接入通过统一配置选择日志级别，SDK 默认关闭。
    configuration.logLevel = XYBookAudioLogLevelDebug;
#endif
    return [self configureWithConfiguration:configuration error:error];
}

- (void)openFromViewController:(UIViewController *)controller
                         style:(XYBookAudioOpenStyle)style
                    completion:(void (^)(NSError *))completion {
    NSParameterAssert(NSThread.isMainThread);
    NSParameterAssert(completion);
    NSError *error = nil;
    if (![self prepareSessionWithError:&error]) {
        completion(error);
        return;
    }
    [self.SDK openFromViewController:controller style:style completion:completion];
}

- (NSDictionary *)playbackSnapshot {
    NSParameterAssert(NSThread.isMainThread);
    return [self.SDK getSnapshot];
}

- (void)refreshHostIdentity {
    NSParameterAssert(NSThread.isMainThread);
    [self.SDK refreshHostIdentity];
}

- (void)yieldPlayback {
    NSParameterAssert(NSThread.isMainThread);
    [self.SDK yieldPlayback];
}

- (void)stopPlayback {
    NSParameterAssert(NSThread.isMainThread);
    [self.SDK stop];
}

- (void)shutdown {
    NSParameterAssert(NSThread.isMainThread);
    if (self.eventSubscription) {
        [self.SDK unsubscribe:self.eventSubscription];
        self.eventSubscription = nil;
    }
    [self.SDK dispose];
    self.SDK = nil;
}

#pragma mark - 宿主能力适配

/// 每次从宿主账号模块读取当前身份并映射为 SDK 类型；不缓存副本，也不传递 token。
- (XYBookAudioIdentity *)bookAudioUserIdentity {
    return [[XYBookAudioIdentity alloc] initWithUserId:@"f7752098514840b6a70d2cf618c4c0f1"];
}

- (void)bookAudioUserInfoWithParameters:(NSDictionary<NSString *, id> *)parameters
                             completion:(void (^)(NSDictionary *, NSError *))completion {
    completion(@{
        @"guest": @NO,
        @"token": @"eyJhbGciOiJIUzI1NiJ9.eyJqdGkiOiJmNzc1MjA5ODUxNDg0MGI2YTcwZDJjZjYxOGM0YzBmMSIsImlhdCI6MTc5NTU3ODA0NX0.wEE7YkAhLKxxku__MMgzmM01Iv-r9c8_YxiI6b9UXIU"
    }, nil);
}

// 带 completion 的宿主接入示例。
- (void)bookAudioRequestLoginFrom:(UIViewController *)controller
                       completion:(void (^)(XYBookAudioLoginResult, NSError *))completion {
    UINavigationController *navigation = controller.navigationController;
    if (!navigation || navigation.topViewController != controller || controller.presentedViewController) {
        completion(XYBookAudioLoginFailed, XYBookAudioError(XYBookAudioBusy, @"当前页面无法打开登录，请稍后重试。"));
        return;
    }
    __weak UIViewController *returnController = controller;
    __weak UINavigationController *weakNavigation = navigation;
    __block __weak AppLoginViewController *weakLogin;
    AppLoginViewController *login = [[AppLoginViewController alloc] initWithCompletion:^(AppLoginResult result) {
        UIViewController *destination = returnController;
        UINavigationController *currentNavigation = weakNavigation;
        if (destination && currentNavigation.topViewController == weakLogin &&
            [currentNavigation.viewControllers containsObject:destination]) {
            [currentNavigation popToViewController:destination animated:YES];
        }
        // 账号模块已提交身份；此处只转换宿主结果，不执行账号登录或退出。
        completion(AppBookAudioLoginResultFromHost(result), nil);
    }];
    weakLogin = login;
    [navigation pushViewController:login animated:YES];
}

/// 在 SDK 提供的导航栈中 push 宿主登录页。登录结果由账号变更通知处理。
- (void)bookAudioRequestLoginFrom:(UIViewController *)controller {
    UINavigationController *navigation = controller.navigationController;
    if (!navigation || navigation.topViewController != controller || controller.presentedViewController) {
        return;
    }
    AppLoginViewController *login = [[AppLoginViewController alloc] initWithCompletion:nil];
    [navigation pushViewController:login animated:YES];
}

/// 通过系统分享页演示宿主路由；正式宿主可替换为已有分享服务，仍使用回调传入的展示页面。
- (void)bookAudioShare:(NSDictionary *)request
                  from:(UIViewController *)controller
            completion:(void (^)(XYBookAudioShareResult, NSError *))completion {
    UIActivityViewController *share = [[UIActivityViewController alloc]
        initWithActivityItems:@[ request[@"title"], [NSURL URLWithString:request[@"link"]] ]
        applicationActivities:nil];
    share.popoverPresentationController.sourceView = controller.view;
    share.popoverPresentationController.sourceRect =
        CGRectMake(CGRectGetMidX(controller.view.bounds), CGRectGetMidY(controller.view.bounds), 1, 1);
    share.completionWithItemsHandler = ^(UIActivityType activityType, BOOL completed, NSArray *items, NSError *error) {
        XYBookAudioShareResult result = error       ? XYBookAudioShareFailed
                                        : completed ? XYBookAudioShareSucceeded
                                                    : XYBookAudioShareCancelled;
        completion(result, error);
    };
    [controller presentViewController:share animated:YES completion:nil];
}

/// 此示例没有其他播放器；正式宿主应先停止既有播放器并释放锁屏控制，再回调成功。
- (void)bookAudioAcquirePlayback:(void (^)(NSError *))completion {
    completion(nil);
}

/// 听书已经让出音频控制权；此示例无需恢复其他播放器，正式宿主按自身策略处理。
- (void)bookAudioDidReleasePlayback {
}

@end
