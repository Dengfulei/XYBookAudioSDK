// SDK 编排入口：分发公开动作、管理页面与订阅，并为内部模块共享本实例的配置和日志出口。
#import "XYBookAudioSDKManager.h"
#import "XYBookAudioMessageProtocol.h"
#import "XYBookAudioSession.h"
#import "XYBookAudioHostActions.h"
#import "XYBookAudioNavigationController.h"
#import "XYBookAudioWebBridge.h"

#import "XYBookAudioLogger.h"

@interface XYBookAudioSDKManager ()

@property (nonatomic, strong) XYBookAudioLogger *logger;

@property (nonatomic, strong) XYBookAudioConfiguration *configuration;
@property (nonatomic, strong) XYBookAudioSession *session;
@property (nonatomic, strong) XYBookAudioHostActions *hostActions;
@property (nonatomic, strong) XYBookAudioNavigationController *navigation;
@property (nonatomic, strong) NSMutableDictionary<NSUUID *, XYBookAudioEventHandler> *subscriptions;
@property (nonatomic) BOOL disposed;

@end

@implementation XYBookAudioSDKManager

/// 创建会话和实例日志出口；host 使用弱引用，宿主负责保证整个 SDK 生命周期内 host 可用。
- (instancetype)initWithConfiguration:(XYBookAudioConfiguration *)configuration
                                 host:(id<XYBookAudioHost>)host
                                error:(NSError **)error {
    NSParameterAssert(NSThread.isMainThread);
    if (!host || !configuration) {
        if (error) {
            *error = XYBookAudioError(XYBookAudioInvalidArgument, @"A valid configuration and host are required.");
        }
        return nil;
    }
    if (![configuration validate:error]) {
        return nil;
    }
    if (![host bookAudioUserIdentity]) {
        if (error) {
            *error = XYBookAudioError(XYBookAudioHostFailed, @"Host identity is unavailable.");
        }
        return nil;
    }
    if ((self = [super init])) {
        _configuration = [configuration copy];
        _logger = [[XYBookAudioLogger alloc] initWithConfiguration:_configuration];
        _subscriptions = [NSMutableDictionary dictionary];
        _session = [[XYBookAudioSession alloc] initWithConfiguration:_configuration host:host logger:_logger];
        _hostActions = [[XYBookAudioHostActions alloc] initWithHost:host logger:_logger];
        __weak typeof(self) weakSelf = self;
        _session.event = ^(NSString *event, NSDictionary *parameters) {
            for (XYBookAudioEventHandler handler in weakSelf.subscriptions.allValues.copy) {
                handler(event, parameters);
            }
        };
        _hostActions.identityChanged = ^{
            [weakSelf refreshHostIdentity];
        };
    }
    [_logger write:XYBookAudioLogLevelInfo component:XYBookAudioLogSDK message:@"SDK initialized."];
    return self;
}

/// 校验展示条件并保留当前页面；回调只确认原生展示，WebView 的加载失败由页面提供重试。
- (void)openFromViewController:(UIViewController *)controller completion:(void (^)(NSError *))completion {
    NSParameterAssert(NSThread.isMainThread);
    if (self.disposed) {
        completion(XYBookAudioError(XYBookAudioDisposed, @"SDK was disposed."));
        return;
    }
    if (self.navigation || controller.presentedViewController || controller.isBeingDismissed ||
        !controller.viewIfLoaded.window) {
        completion(XYBookAudioError(XYBookAudioBusy, @"A listening page is open or the presenter is unavailable."));
        return;
    }
    [self.logger write:XYBookAudioLogLevelInfo component:XYBookAudioLogPage message:@"Opening listening page."];
    XYBookAudioNavigationController *navigation =
        [[XYBookAudioNavigationController alloc] initWithSDK:self configuration:self.configuration logger:self.logger];
    self.navigation = navigation;
    __weak typeof(self) weakSelf = self;
    navigation.closed = ^{
        weakSelf.navigation = nil;
    };
    navigation.modalPresentationStyle = UIModalPresentationFullScreen;
    [controller presentViewController:navigation animated:YES completion:^{
        completion(nil);
    }];
}

/// 只记录已实现的动作名称；完整参数、回执和未知动作不进入诊断，原始 completion 的结果保持不变。
- (XYBookAudioCompletion)loggedCompletionForOperation:(NSString *)operation
                                           completion:(XYBookAudioCompletion)completion {
    XYBookAudioLogger *logger = self.logger;
    return ^(NSDictionary *result, NSError *error) {
        if (error) {
            [logger error:error component:XYBookAudioLogSDK operation:operation];
        } else {
            [logger write:XYBookAudioLogLevelDebug component:XYBookAudioLogSDK
                  message:[operation stringByAppendingString:@" completed."]];
        }
        completion(result, error);
    };
}

/// 原生入口按已有宿主能力和播放命令分发；H5 同名方法的动态调用只由 Bridge 负责。
- (void)executeAction:(NSString *)action
           parameters:(NSDictionary *)parameters
           completion:(XYBookAudioCompletion)completion {
    NSParameterAssert(NSThread.isMainThread);
    BOOL supported = [XYBookAudioWebBridge supportsAction:action];
    completion = [self loggedCompletionForOperation:supported ? action : @"Command" completion:completion];
    if (self.disposed) {
        completion(nil, XYBookAudioError(XYBookAudioDisposed, @"SDK was disposed."));
        return;
    }
    if (![parameters isKindOfClass:NSDictionary.class] || ![action isKindOfClass:NSString.class]) {
        completion(
            nil, XYBookAudioError(XYBookAudioInvalidArgument, @"An action string and parameters object are required."));
        return;
    }
    if (!supported) {
        [self.logger write:XYBookAudioLogLevelWarning component:XYBookAudioLogSDK
                   message:@"Unsupported command rejected."];
        completion(nil, XYBookAudioError(XYBookAudioUnsupported, @"Unsupported action."));
        return;
    }
    [self.logger write:XYBookAudioLogLevelDebug component:XYBookAudioLogSDK
               message:[action stringByAppendingString:@" received."]];
    // 页面交互要求来源网页上下文，不能进入听书前缀解析或由宿主 executeAction 代发。
    if ([action isEqual:XYBookAudioActionOpenWindow] || [action isEqual:XYBookAudioActionCloseWindow] ||
        [action isEqual:XYBookAudioActionGoLogin] || [action isEqual:XYBookAudioActionCanIUse]) {
        completion(nil, XYBookAudioError(XYBookAudioInvalidArgument, @"Page actions must originate from an H5 page."));
        return;
    }
    UIViewController *presenter = self.navigation.topViewController;
    if ([action isEqual:XYBookAudioActionGetSystemInfo]) {
        [self.hostActions getSystemInfoFrom:presenter completion:completion];
        return;
    }
    if ([action isEqual:XYBookAudioActionGetUserInfo]) {
        [self.hostActions getUserInfo:parameters presenter:presenter completion:completion];
        return;
    }
    if ([action isEqual:XYBookAudioActionShowShareMenu]) {
        [self.hostActions showShareMenu:parameters presenter:presenter completion:completion];
        return;
    }
    // 新增通用 H5 方法不一定是播放命令，必须先确认前缀，不能按固定长度截取任意方法名。
    if (![action hasPrefix:XYBookAudioPlaybackActionPrefix]) {
        completion(nil,
                   XYBookAudioError(XYBookAudioUnsupported, @"This H5 action has no native command implementation."));
        return;
    }
    NSString *command = [action substringFromIndex:[XYBookAudioPlaybackActionPrefix length]];
    if ([command isEqual:XYBookAudioCommandGetCapabilities]) {
        completion([self getCapabilities], nil);
        return;
    }
    if ([command isEqual:XYBookAudioCommandGetSnapshot]) {
        completion([self getSnapshot], nil);
        return;
    }
    if ([@[ XYBookAudioCommandSubscribe, XYBookAudioCommandUnsubscribe ] containsObject:command]) {
        completion(nil, XYBookAudioError(
                            XYBookAudioInvalidArgument,
                            @"Native callers use subscribe: and unsubscribe:; H5 subscriptions are page-scoped."));
        return;
    }
    [self.session execute:command parameters:parameters completion:completion];
}

- (NSDictionary *)getCapabilities {
    NSParameterAssert(NSThread.isMainThread);
    return @{
        XYBookAudioKeyActions : [XYBookAudioWebBridge supportedActions],
        XYBookAudioKeyRates : XYBookAudioRates(),
        XYBookAudioKeySleepModes : @[ XYBookAudioValueOff, XYBookAudioValueDuration, XYBookAudioValueTrackCount ]
    };
}

- (void)requestHostLoginFromViewController:(UIViewController *)controller completion:(XYBookAudioCompletion)completion {
    NSParameterAssert(NSThread.isMainThread);
    if (self.disposed) {
        completion(nil, XYBookAudioError(XYBookAudioDisposed, @"SDK was disposed."));
        return;
    }
    if (controller != self.navigation.topViewController) {
        completion(nil, XYBookAudioError(XYBookAudioBusy, @"Login requires the current SDK page."));
        return;
    }
    [self.hostActions requestLoginFrom:controller completion:completion];
}

- (NSDictionary *)getSnapshot {
    NSParameterAssert(NSThread.isMainThread);
    return [self.session snapshot];
}

- (NSUUID *)subscribe:(XYBookAudioEventHandler)handler {
    NSParameterAssert(NSThread.isMainThread);
    NSParameterAssert(handler);
    NSUUID *identifier = NSUUID.UUID;
    if (!self.disposed) {
        self.subscriptions[identifier] = [handler copy];
    }
    return identifier;
}

- (void)unsubscribe:(NSUUID *)subscription {
    NSParameterAssert(NSThread.isMainThread);
    [self.subscriptions removeObjectForKey:subscription];
}

- (void)refreshHostIdentity {
    NSParameterAssert(NSThread.isMainThread);
    if (!self.disposed) {
        [self.session refreshIdentity];
    }
}

- (void)yieldPlayback {
    NSParameterAssert(NSThread.isMainThread);
    if (!self.disposed) {
        [self.session yieldPlayback];
    }
}

- (void)stop {
    NSParameterAssert(NSThread.isMainThread);
    if (!self.disposed) {
        [self.session stop];
    }
}

/// 先标记终止再清理页面与会话，避免清理期间的回调重新发起业务动作。
- (void)dispose {
    NSParameterAssert(NSThread.isMainThread);
    if (self.disposed) {
        return;
    }
    self.disposed = YES;
    [self.logger write:XYBookAudioLogLevelInfo component:XYBookAudioLogSDK message:@"SDK disposing."];
    [self.navigation closeAllPages];
    [self.hostActions dispose];
    [self.session dispose];
    [self.subscriptions removeAllObjects];
}

- (void)dealloc {
    [self.session dispose];
    [self.hostActions dispose];
}

@end
