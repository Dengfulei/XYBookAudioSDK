// 宿主接入适配器：管理 SDK 生命周期、事件转发及账号/分享/音频路由；不实现播放或 JS 协议。
#import "AppBookAudioService.h"
#import <sys/utsname.h>
#import "../Account/AppAccountService.h"
#import "../Account/AppLoginViewController.h"

NSNotificationName const AppBookAudioServiceEventNotification = @"AppBookAudioServiceEventNotification";
NSString *const AppBookAudioServiceEventNameKey = @"event";
NSString *const AppBookAudioServiceEventParametersKey = @"parameters";

/// 宿主登录模块不依赖 SDK 枚举，协议类型转换集中在接入边界。
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

/// 宿主已提交新的身份后才发出通知；刷新 SDK 权限与 H5，账号模块本身无需知道听书业务。
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

/// 重建时沿用已确认的配置；Demo 默认读取随包资源，远程联调入口由启动参数显式提供。
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
    configuration.webInspectorEnabled = YES;
#if DEBUG
    // 仅示例本地调试开启日志；正式接入通过统一配置选择日志级别，SDK 默认关闭。
    configuration.logLevel = XYBookAudioLogLevelDebug;
#endif
    return [self configureWithConfiguration:configuration error:error];
}

- (void)openFromViewController:(UIViewController *)controller completion:(void (^)(NSError *))completion {
    [self openFromViewController:controller style:XYBookAudioOpenStylePresent completion:completion];
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

- (NSDictionary *)getSnapshot {
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

- (void)stop {
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

/// 本地宿主使用自己的 IDFV；正式宿主在此接入已有设备标识服务，保持与账号／接口签名一致。
- (NSDictionary *)bookAudioSystemInfoFromViewController:(UIViewController *)controller {
    struct utsname device;
    if (uname(&device) != 0 || !UIDevice.currentDevice.identifierForVendor) {
        return nil;
    }
    NSBundle *bundle = NSBundle.mainBundle;
    // XCTest 精简宿主不带营销版本号，使用其真实构建号；两者都没有时明确拒绝提供资料。
    NSString *version = [bundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"]
                            ?: [bundle objectForInfoDictionaryKey:@"CFBundleVersion"];
    NSString *name = [bundle objectForInfoDictionaryKey:@"CFBundleDisplayName"]
                         ?: [bundle objectForInfoDictionaryKey:@"CFBundleName"];
    if (!version.length || !name.length) {
        return nil;
    }
    return @{
        @"types" : [NSString stringWithUTF8String:device.machine],
        @"debug" : @1,
        @"program_version" : version,
        @"device_token" : UIDevice.currentDevice.identifierForVendor.UUIDString,
        @"program_name" : name,
        @"system" : UIDevice.currentDevice.systemVersion,
        @"appStatusBarHeight" : [NSString
            stringWithFormat:@"%.f", controller.view.window.windowScene.statusBarManager.statusBarFrame.size.height],
        @"bottomSafeHeight" : [NSString stringWithFormat:@"%.f", controller.view.window.safeAreaInsets.bottom]
    };
}

/// 每次从宿主账号模块读取当前身份并映射为 SDK 类型；不缓存副本，也不传递 token。
- (XYBookAudioIdentity *)bookAudioUserIdentity {
    return [[XYBookAudioIdentity alloc] initWithUserId:AppAccountService.sharedInstance.userId];
}

/// 标准 H5 用户资料由宿主账号模块提供；本地账号仅有 id，不捏造其他字段或 ticket。
- (void)bookAudioUserInfoUsingTicket:(BOOL)usingTicket completion:(void (^)(NSDictionary *, NSError *))completion {
    if (usingTicket) {
        completion(nil, XYBookAudioError(XYBookAudioUnsupported, @"本地账号未接入票据服务。"));
        return;
    }
    NSString *userId = AppAccountService.sharedInstance.userId;
    if (!userId.length) {
        completion(nil, XYBookAudioError(XYBookAudioHostFailed, @"读取用户资料时账号已退出。"));
        return;
    }
    completion(@{@"id" : userId, @"info" : @{@"id" : userId}}, nil);
}

/// 在 SDK 回调提供的导航栈中 push 登录；仅弱引用展示控制器，避免会话持有业务页面。
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
