// SDK 编排入口：分发公开动作、管理页面与订阅，并为内部模块共享本实例的配置和日志出口。
#import "XYBookAudioSDKManager.h"
#import "XYBookAudioMessageProtocol.h"
#import "XYBookAudioSession.h"
#import "XYBookAudioHostActions.h"
#import "XYBookAudioWindowCoordinator.h"
#import "XYBookAudioWebBridge.h"

#import "XYBookAudioLogger.h"

static NSString *const XYBookAudioPlaybackActionPrefix = @"xhBookAudio";
static NSString *const XYBookAudioCommandGetCapabilities = @"GetCapabilities";
static NSString *const XYBookAudioCommandGetSnapshot = @"GetSnapshot";
static NSString *const XYBookAudioCommandSubscribe = @"Subscribe";
static NSString *const XYBookAudioCommandUnsubscribe = @"Unsubscribe";

@interface XYBookAudioSDKManager ()

@property (nonatomic, strong) XYBookAudioLogger *logger;

@property (nonatomic, strong) XYBookAudioConfiguration *configuration;
@property (nonatomic, strong) XYBookAudioSession *session;
@property (nonatomic, strong) XYBookAudioHostActions *hostActions;
@property (nonatomic, strong) XYBookAudioWindowCoordinator *windowCoordinator;
@property (nonatomic, strong) NSMutableDictionary<NSUUID *, XYBookAudioEventHandler> *subscriptions;
@property (nonatomic) BOOL disposed;
@property (nonatomic) NSUInteger snckEventVersion;

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
    [self openFromViewController:controller style:XYBookAudioOpenStylePresent completion:completion];
}

- (void)openFromViewController:(UIViewController *)controller
                         style:(XYBookAudioOpenStyle)style
                    completion:(void (^)(NSError *))completion {
    NSParameterAssert(NSThread.isMainThread);
    if (self.disposed) {
        completion(XYBookAudioError(XYBookAudioDisposed, @"SDK was disposed."));
        return;
    }
    if (style != XYBookAudioOpenStylePresent && style != XYBookAudioOpenStylePush) {
        completion(XYBookAudioError(XYBookAudioInvalidArgument, @"Unknown listening page open style."));
        return;
    }
    if (self.windowCoordinator.navigation || controller.presentedViewController || controller.isBeingDismissed ||
        !controller.viewIfLoaded.window) {
        completion(XYBookAudioError(XYBookAudioBusy, @"A listening page is open or the presenter is unavailable."));
        return;
    }
    if (style == XYBookAudioOpenStylePush) {
        UINavigationController *navigation = controller.navigationController;
        if (!navigation) {
            completion(XYBookAudioError(XYBookAudioInvalidArgument, @"Push requires a host navigation controller."));
            return;
        }
        if (navigation.topViewController != controller || navigation.transitionCoordinator ||
            navigation.isBeingDismissed || navigation.presentedViewController) {
            completion(XYBookAudioError(XYBookAudioBusy, @"Push requires the current visible host page."));
            return;
        }
    }
    [self.windowCoordinator closeAllPages];
    XYBookAudioWindowCoordinator *windows = [[XYBookAudioWindowCoordinator alloc] initWithSDK:self
                                                                                configuration:self.configuration
                                                                                       logger:self.logger
                                                                                        style:style];
    self.windowCoordinator = windows;
    __weak typeof(self) weakSelf = self;
    __weak XYBookAudioWindowCoordinator *weakWindows = windows;
    windows.closed = ^{
        if (weakSelf.windowCoordinator == weakWindows) {
            weakSelf.windowCoordinator = nil;
        }
    };
    [windows openFromViewController:controller completion:completion];
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

/// 原生调用使用宿主能力与播放命令，H5 入口由 Bridge 独立处理。
- (void)executeAction:(NSString *)action
           parameters:(NSDictionary *)parameters
           completion:(XYBookAudioCompletion)completion {
    NSParameterAssert(NSThread.isMainThread);
    NSString *command = XYBookAudioIsNonEmptyString(action) && [action hasPrefix:XYBookAudioPlaybackActionPrefix]
                            ? [action substringFromIndex:XYBookAudioPlaybackActionPrefix.length]
                            : nil;
    BOOL pageAction = XYBookAudioIsNonEmptyString(action) && [@[
                          XYBookAudioActionOpenWindow, XYBookAudioActionCloseWindow, XYBookAudioActionGoLogin,
                          XYBookAudioActionCanIUse
                      ] containsObject:action];
    BOOL hostAction =
        XYBookAudioIsNonEmptyString(action) &&
        [@[ XYBookAudioActionGetSystemInfo, XYBookAudioActionSnckGetUserInfo, XYBookAudioActionShowShareMenu ]
            containsObject:action];
    BOOL playbackAction =
        command && [@[
            XYBookAudioCommandSetQueue, XYBookAudioCommandPlay, XYBookAudioCommandPause, XYBookAudioCommandStop,
            XYBookAudioCommandSeekTo, XYBookAudioCommandPrevious, XYBookAudioCommandNext,
            XYBookAudioCommandSelectChapter, XYBookAudioCommandSetRate, XYBookAudioCommandSetSleepTimer,
            XYBookAudioCommandCancelSleepTimer, XYBookAudioCommandGetCapabilities, XYBookAudioCommandGetSnapshot,
            XYBookAudioCommandSubscribe, XYBookAudioCommandUnsubscribe
        ] containsObject:command];
    BOOL supported = pageAction || hostAction || playbackAction;
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
    if (pageAction) {
        completion(nil, XYBookAudioError(XYBookAudioInvalidArgument, @"This is not a native command."));
        return;
    }
    UIViewController *presenter = self.windowCoordinator.topPage;
    if ([action isEqual:XYBookAudioActionGetSystemInfo]) {
        [self.hostActions getSystemInfoFrom:presenter completion:completion];
        return;
    }
    if ([action isEqual:XYBookAudioActionSnckGetUserInfo]) {
        [self.hostActions getUserInfo:parameters presenter:presenter completion:completion];
        return;
    }
    if ([action isEqual:XYBookAudioActionShowShareMenu]) {
        [self.hostActions showShareMenu:parameters presenter:presenter completion:completion];
        return;
    }
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
        XYBookAudioKeyRates : XYBookAudioSupportedPlaybackRates(),
        XYBookAudioKeySleepModes : @[ XYBookAudioValueOff, XYBookAudioValueDuration, XYBookAudioValueTrackCount ]
    };
}

- (void)requestHostLoginFromViewController:(UIViewController *)controller completion:(XYBookAudioCompletion)completion {
    NSParameterAssert(NSThread.isMainThread);
    if (self.disposed) {
        completion(nil, XYBookAudioError(XYBookAudioDisposed, @"SDK was disposed."));
        return;
    }
    if (!controller || controller != self.windowCoordinator.topPage) {
        completion(nil, XYBookAudioError(XYBookAudioBusy, @"Login requires the current SDK page."));
        return;
    }
    [self.hostActions requestLoginFrom:controller completion:completion];
}

- (NSDictionary *)getSnapshot {
    NSParameterAssert(NSThread.isMainThread);
    return [self.session snapshot];
}

- (NSDictionary *)snckPlayback {
    return [self.session snckPlayback];
}

- (XYBookAudioTimerChange)snckTimerChange {
    return [self.session snckTimerChange];
}

- (NSDictionary *)snckUserState {
    return [self.session snckUserState];
}

- (NSUInteger)nextSnckEventVersion {
    return ++self.snckEventVersion;
}

- (void)executeSnckAudio:(NSString *)command
              parameters:(NSDictionary *)parameters
              completion:(XYBookAudioCompletion)completion {
    [self.session executeSnckAudio:command parameters:parameters completion:completion];
}

- (void)shareSnck:(NSDictionary *)parameters
         fromPage:(UIViewController *)page
       completion:(XYBookAudioCompletion)completion {
    [self.hostActions shareSnck:parameters presenter:page completion:completion];
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
    [self.windowCoordinator closeAllPages];
    [self.hostActions dispose];
    [self.session dispose];
    [self.subscriptions removeAllObjects];
}

- (void)dealloc {
    [self.session dispose];
    [self.hostActions dispose];
}

@end
