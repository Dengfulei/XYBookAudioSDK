// 宿主回调可能跨线程、重复或迟到；统一回主线程结算一次，页面关闭后仍允许有效的身份刷新。
#import "XYBookAudioHostActions.h"
#import <sys/utsname.h>
#import "XYBookAudioMessageProtocol.h"
#import "XYBookAudioLogger.h"

static NSTimeInterval const XYBookAudioHostRequestTimeout = 180;
typedef void (^XYBookAudioHostReply)(id result, NSError *error);

/// 宿主回调与超时都在主线程结算，首次结算后释放业务回调。登录的身份刷新可处理迟到结果。
/// @param timeout 等待宿主结果的时间，单位为秒。
/// @param timeoutError 超时时送入结算流程的错误。
/// @param didReply 可选的副作用回调。每次收到结果时先执行它，包含迟到的结果。
/// @param completion 首次结算时执行的业务回调。
/// @return 供宿主回调或 SDK 终止流程送入结果的 block。
static XYBookAudioHostReply XYBookAudioMakeHostReply(NSTimeInterval timeout, NSError *timeoutError,
                                                     dispatch_block_t didReply, XYBookAudioHostReply completion) {
    __block XYBookAudioHostReply pending = [completion copy];
    XYBookAudioHostReply reply = ^(id result, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (didReply) {
                didReply();
            }
            XYBookAudioHostReply finish = pending;
            pending = nil;
            if (finish) {
                finish(result, error);
            }
        });
    };
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, timeout * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        if (pending) {
            reply(nil, timeoutError);
        }
    });
    return reply;
}

static NSString *XYBookAudioShareStatus(XYBookAudioShareResult result) {
    switch (result) {
        case XYBookAudioShareAccepted:
        case XYBookAudioShareSucceeded:
            return XYBookAudioValueAccepted;
        case XYBookAudioShareUnsupported:
            return XYBookAudioValueUnsupported;
        case XYBookAudioShareCancelled:
            return XYBookAudioValueCancelled;
        case XYBookAudioShareFailed:
            return XYBookAudioValueFailed;
    }
    return XYBookAudioValueFailed;
}

static NSString *XYBookAudioLegacyShareLink(id value) {
    if (XYBookAudioIsHTTPSURLString(value)) {
        return value;
    }
    if (![value isKindOfClass:NSString.class]) {
        return nil;
    }
    NSString *text = value;
    if (![text hasPrefix:@"["] || ![text hasSuffix:@")"]) {
        return nil;
    }
    NSRange separator = [text rangeOfString:@"]("];
    if (separator.location == NSNotFound) {
        return nil;
    }
    NSUInteger start = NSMaxRange(separator);
    NSString *link = [text substringWithRange:NSMakeRange(start, text.length - start - 1)];
    NSString *label = [text substringWithRange:NSMakeRange(1, separator.location - 1)];
    return [label isEqualToString:link] && XYBookAudioIsHTTPSURLString(link) ? link : nil;
}

static NSDictionary *XYBookAudioDefaultSystemInfo(UIViewController *presenter) {
    UIDevice *device = UIDevice.currentDevice;
    NSBundle *bundle = NSBundle.mainBundle;
    UIWindow *window = presenter.viewIfLoaded.window;
    UIStatusBarManager *statusBarManager = window.windowScene.statusBarManager;
    CGFloat statusBarHeight = statusBarManager ? statusBarManager.statusBarFrame.size.height : 0;
    CGFloat bottomSafeHeight = window ? window.safeAreaInsets.bottom : 0;
    NSMutableDictionary *information = [@{
        @"debug" : @1,
        @"system" : device.systemVersion,
        @"appStatusBarHeight" : [NSString stringWithFormat:@"%.f", statusBarHeight],
        @"bottomSafeHeight" : [NSString stringWithFormat:@"%.f", bottomSafeHeight]
    } mutableCopy];
    struct utsname hardware;
    if (uname(&hardware) == 0) {
        information[@"types"] = [NSString stringWithUTF8String:hardware.machine];
    }
    information[@"device_token"] = device.identifierForVendor.UUIDString;
    information[@"program_version"] = [bundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"]
                                          ?: [bundle objectForInfoDictionaryKey:@"CFBundleVersion"];
    information[@"program_name"] = [bundle objectForInfoDictionaryKey:@"CFBundleDisplayName"]
                                       ?: [bundle objectForInfoDictionaryKey:@"CFBundleName"];
    return [information copy];
}

@interface XYBookAudioHostActions ()

@property (nonatomic, strong) XYBookAudioLogger *logger;

@property (nonatomic, weak) id<XYBookAudioHost> host;
@property (nonatomic, copy) XYBookAudioHostReply loginReply;
@property (nonatomic) BOOL loginAwaitsNotification, sharePending, disposed;

@end

@implementation XYBookAudioHostActions

- (instancetype)initWithHost:(id<XYBookAudioHost>)host logger:(XYBookAudioLogger *)logger {
    if ((self = [super init])) {
        _host = host;
        _logger = logger;
    }
    return self;
}

/// 只返回登录标记和标识；身份提供器不可用时明确失败，不能用空对象假装游客。
- (NSDictionary *)identity:(NSError **)error {
    XYBookAudioIdentity *identity = [self.host bookAudioUserIdentity];
    if (!identity) {
        if (error) {
            *error = XYBookAudioError(XYBookAudioHostFailed, @"Host identity is unavailable.");
        }
        return nil;
    }
    return @{XYBookAudioKeyIsLoggedIn : @(identity.isLoggedIn), XYBookAudioKeyUserID : identity.userId};
}

/// 宿主可覆盖系统资料。缺省时使用当前 App 和设备的系统信息。
- (void)getSystemInfoFrom:(UIViewController *)presenter completion:(XYBookAudioCompletion)completion {
    id<XYBookAudioHost> host = self.host;
    NSDictionary *information = [host respondsToSelector:@selector(bookAudioSystemInfoFromViewController:)]
                                    ? [host bookAudioSystemInfoFromViewController:presenter]
                                    : XYBookAudioDefaultSystemInfo(presenter);
    if (![information isKindOfClass:NSDictionary.class] || !information.count ||
        ![NSJSONSerialization isValidJSONObject:information]) {
        completion(nil, XYBookAudioError(XYBookAudioHostFailed, @"Host system info must be a nonempty JSON object."));
        return;
    }
    completion(information, nil);
}

/// goLogin/useTicket 使用 JSON 布尔值；不接受字符串或业务参数类型错误后默认为成功。
- (NSError *)userInfoParametersError:(NSDictionary *)parameters {
    for (NSString *key in @[ XYBookAudioKeyGoLogin, XYBookAudioKeyUseTicket ]) {
        id value = parameters[key];
        if (value &&
            (![value isKindOfClass:NSNumber.class] || CFGetTypeID((__bridge CFTypeRef)value) != CFBooleanGetTypeID())) {
            return XYBookAudioError(XYBookAudioInvalidArgument, @"goLogin and useTicket must be booleans.");
        }
    }
    return nil;
}

/// 游客仅在 goLogin 为 true 时拉起登录；取消／失败返回 {}，不能用 SDK 的简化身份替代宿主资料。
- (void)getUserInfo:(NSDictionary *)parameters
          presenter:(UIViewController *)presenter
         completion:(XYBookAudioCompletion)replyToUserInfo {
    parameters = [parameters copy];
    NSError *error = [self userInfoParametersError:parameters];
    NSDictionary *identity = error ? nil : [self identity:&error];
    if (error) {
        replyToUserInfo(nil, error);
        return;
    }
    if ([identity[XYBookAudioKeyIsLoggedIn] boolValue]) {
        [self readUserInfoWithParameters:parameters completion:replyToUserInfo];
        return;
    }
    if (![parameters[XYBookAudioKeyGoLogin] boolValue]) {
        replyToUserInfo(@{}, nil);
        return;
    }
    __weak typeof(self) weakSelf = self;
    [self requestLoginFrom:presenter completion:^(NSDictionary *loginResult, NSError *loginError) {
        if (loginError) {
            replyToUserInfo(nil, loginError);
            return;
        }
        if (![loginResult[XYBookAudioKeyStatus] isEqual:XYBookAudioValueLoggedIn]) {
            replyToUserInfo(@{}, nil);
            return;
        }
        [weakSelf readUserInfoWithParameters:parameters completion:replyToUserInfo];
    }];
}

/// 宿主异步资料原样回传；账号变化或实例销毁后拒绝旧资料，避免跨账号泄露。
- (void)readUserInfoWithParameters:(NSDictionary *)parameters completion:(XYBookAudioCompletion)completion {
    id<XYBookAudioHost> host = self.host;
    BOOL acceptsParameters = [host respondsToSelector:@selector(bookAudioUserInfoWithParameters:completion:)];
    if (!acceptsParameters && ![host respondsToSelector:@selector(bookAudioUserInfoUsingTicket:completion:)]) {
        completion(nil, XYBookAudioError(XYBookAudioUnsupported, @"Host user-info provider is unavailable."));
        return;
    }
    NSString *userId = [host bookAudioUserIdentity].userId;
    XYBookAudioHostReply reply = XYBookAudioMakeHostReply(
        XYBookAudioHostRequestTimeout, XYBookAudioError(XYBookAudioHostFailed, @"Host user-info request timed out."),
        nil, ^(id userInfo, NSError *hostError) {
            NSError *error = [self userInfoResultError:userInfo hostError:hostError expectedUserId:userId];
            completion(error ? nil : userInfo, error);
        });
    void (^hostCompletion)(NSDictionary *, NSError *) = ^(NSDictionary *userInfo, NSError *hostError) {
        reply(userInfo, hostError);
    };
    if (acceptsParameters) {
        [host bookAudioUserInfoWithParameters:parameters completion:hostCompletion];
    } else {
        [host bookAudioUserInfoUsingTicket:[parameters[XYBookAudioKeyUseTicket] boolValue] completion:hostCompletion];
    }
}

/// 只检查资料是否仍属于当前账号及 JSON 可用性；具体字段由宿主和 H5 标准约定。
- (NSError *)userInfoResultError:(NSDictionary *)userInfo
                       hostError:(NSError *)hostError
                  expectedUserId:(NSString *)userId {
    if (self.disposed) {
        return XYBookAudioError(XYBookAudioDisposed, @"SDK was disposed.");
    }
    if (hostError) {
        [self.logger error:hostError component:XYBookAudioLogHost operation:XYBookAudioActionSnckGetUserInfo];
        return [hostError.domain isEqual:XYBookAudioErrorDomain]
                   ? hostError
                   : XYBookAudioError(XYBookAudioHostFailed, @"Host user-info request failed.");
    }
    if (!userId.length || ![[self.host bookAudioUserIdentity].userId isEqual:userId]) {
        return XYBookAudioError(XYBookAudioHostFailed, @"Host account changed while reading user info.");
    }
    if (![userInfo isKindOfClass:NSDictionary.class] || !userInfo.count ||
        ![NSJSONSerialization isValidJSONObject:userInfo]) {
        return XYBookAudioError(XYBookAudioHostFailed, @"Host user info must be a nonempty JSON object.");
    }
    return nil;
}

/// 宿主 UI 只允许当前可见且没有其他弹窗的页面发起；不代替宿主账号生命周期。
- (NSError *)presentationError:(UIViewController *)presenter {
    if (!presenter.viewIfLoaded.window || presenter.presentedViewController || presenter.isBeingDismissed ||
        presenter.navigationController.topViewController != presenter ||
        presenter.navigationController.transitionCoordinator) {
        return XYBookAudioError(XYBookAudioBusy, @"The listening page must be visible and available for host UI.");
    }
    return nil;
}

/// 复用已登录身份；游客仅从当前可见页面打开宿主登录，结果在主线程结算一次。
- (void)requestLoginFrom:(UIViewController *)presenter completion:(XYBookAudioCompletion)completion {
    NSError *error = nil;
    NSDictionary *identity = [self identity:&error];
    if (error) {
        completion(nil, error);
        return;
    }
    if ([identity[XYBookAudioKeyIsLoggedIn] boolValue]) {
        completion(@{XYBookAudioKeyStatus : XYBookAudioValueLoggedIn, XYBookAudioKeyIdentity : identity}, nil);
        return;
    }
    error = [self presentationError:presenter];
    if (error) {
        completion(nil, error);
        return;
    }
    [self login:presenter completion:completion];
}

/// 展示分享前检查宿主页面状态；字段检查和渠道选择结果由分享流程负责。
- (void)showShareMenu:(NSDictionary *)parameters
            presenter:(UIViewController *)presenter
           completion:(XYBookAudioCompletion)completion {
    NSError *error = [self presentationError:presenter];
    if (error) {
        completion(nil, error);
        return;
    }
    [self share:parameters presenter:presenter completion:completion];
}

/// 首次结果或超时会释放登录占用。迟到的宿主回调仍可刷新账号。
/// @param presenter 宿主用于打开登录页的当前听书控制器。
/// @param replyToLogin 将 SDK 判定后的结果交给原生调用方的回调。
- (void)login:(UIViewController *)presenter completion:(XYBookAudioCompletion)replyToLogin {
    if (self.loginReply) {
        replyToLogin(nil, XYBookAudioError(XYBookAudioBusy, @"Login is already in progress."));
        return;
    }
    id<XYBookAudioHost> host = self.host;
    BOOL usesHostCallback = [host respondsToSelector:@selector(bookAudioRequestLoginFrom:completion:)];
    if (!usesHostCallback && ![host respondsToSelector:@selector(bookAudioRequestLoginFrom:)]) {
        replyToLogin(nil, XYBookAudioError(XYBookAudioUnsupported, @"Host login is unavailable."));
        return;
    }
    self.loginAwaitsNotification = !usesHostCallback;
    __weak typeof(self) weakSelf = self;
    dispatch_block_t refreshIdentity = ^{
        dispatch_block_t identityChanged = weakSelf.identityChanged;
        if (identityChanged && !weakSelf.disposed) {
            identityChanged();
        }
    };
    XYBookAudioHostReply receiveHostResult = XYBookAudioMakeHostReply(
        XYBookAudioHostRequestTimeout, XYBookAudioError(XYBookAudioHostFailed, @"Host login timed out."),
        refreshIdentity, ^(id response, NSError *hostError) {
            XYBookAudioHostActions *actions = weakSelf;
            actions.loginReply = nil;
            if (!actions || actions.disposed) {
                replyToLogin(nil, XYBookAudioError(XYBookAudioDisposed, @"SDK was disposed."));
                return;
            }
            [actions finishLoginWithResult:[response integerValue] hostError:hostError reply:replyToLogin];
        });
    self.loginReply = receiveHostResult;
    [self.logger write:XYBookAudioLogLevelInfo component:XYBookAudioLogHost message:@"Login requested from host."];
    if (self.disposed) {
        return;
    }
    if (usesHostCallback) {
        [host bookAudioRequestLoginFrom:presenter completion:^(XYBookAudioLoginResult result, NSError *hostError) {
            receiveHostResult(@(result), hostError);
        }];
    } else {
        [host bookAudioRequestLoginFrom:presenter];
    }
}

/// 重新读取账号状态，结算已返回的登录请求。
/// @param result 宿主提供的登录结果。
/// @param hostError 宿主或请求流程产生的错误。正常回调时可为 nil。
/// @param replyToLogin 交给登录发起方的回调，接收状态和身份，或接收 SDK 执行错误。
- (void)finishLoginWithResult:(XYBookAudioLoginResult)result
                    hostError:(NSError *)hostError
                        reply:(XYBookAudioCompletion)replyToLogin {
    if (hostError) {
        [self.logger error:hostError component:XYBookAudioLogHost operation:@"Login"];
        if ([hostError.domain isEqual:XYBookAudioErrorDomain] && hostError.code == XYBookAudioBusy) {
            replyToLogin(nil, hostError);
            return;
        }
    }
    NSError *identityError = nil;
    NSDictionary *identity = [self identity:&identityError];
    if (identityError) {
        replyToLogin(nil, identityError);
        return;
    }

    NSString *status = XYBookAudioValueFailed;
    if (!hostError && result == XYBookAudioLoginCancelled) {
        status = XYBookAudioValueCancelled;
    } else if (!hostError && result == XYBookAudioLoginLoggedIn && [identity[XYBookAudioKeyIsLoggedIn] boolValue]) {
        status = XYBookAudioValueLoggedIn;
    }
    [self.logger write:XYBookAudioLogLevelInfo component:XYBookAudioLogHost
               message:[@"Login result: " stringByAppendingString:status]];
    replyToLogin(@{XYBookAudioKeyStatus : status, XYBookAudioKeyIdentity : identity}, nil);
}

- (void)resumePendingLoginIfAuthenticated {
    if (!self.disposed && self.loginReply && self.loginAwaitsNotification &&
        [self.host bookAudioUserIdentity].isLoggedIn) {
        self.loginReply(@(XYBookAudioLoginLoggedIn), nil);
    }
}

/// 先验证分享字段再交给宿主；仅透传公开分享契约，回执不承诺第三方平台分享完成。
- (void)share:(NSDictionary *)parameters
     presenter:(UIViewController *)presenter
    completion:(XYBookAudioCompletion)completion {
    NSString *link = XYBookAudioLegacyShareLink(parameters[XYBookAudioKeyLink]);
    id description = parameters[XYBookAudioKeyDescription];
    if (!XYBookAudioIsNonEmptyString(parameters[XYBookAudioKeyTitle]) || !link ||
        (description && ![description isKindOfClass:NSString.class])) {
        completion(nil,
                   XYBookAudioError(XYBookAudioInvalidArgument,
                                    @"Sharing requires a title and an HTTPS link. Optional desc must be a string."));
        return;
    }
    NSMutableDictionary *request = [parameters mutableCopy];
    request[XYBookAudioKeyLink] = link;
    if (!XYBookAudioIsNonEmptyString(request[XYBookAudioKeyImageURL])) {
        [request removeObjectForKey:XYBookAudioKeyImageURL];
    }
    [self dispatchShare:request presenter:presenter snck:NO completion:completion];
}

- (void)shareSnck:(NSDictionary *)parameters
        presenter:(UIViewController *)presenter
       completion:(XYBookAudioCompletion)completion {
    NSString *title = parameters[@"title"];
    id link = parameters[@"link"], description = parameters[@"description"], image = parameters[@"imageUrl"];
    id platform = parameters[@"platform"];
    NSCharacterSet *whitespace = NSCharacterSet.whitespaceAndNewlineCharacterSet;
    if (!XYBookAudioIsNonEmptyString(title) || ![title stringByTrimmingCharactersInSet:whitespace].length ||
        !XYBookAudioParseSnckURL(link) || (description && ![description isKindOfClass:NSString.class]) ||
        (image && (![image isKindOfClass:NSString.class] ||
                   ([image stringByTrimmingCharactersInSet:whitespace].length && !XYBookAudioParseSnckURL(image)))) ||
        (platform && ![platform isKindOfClass:NSString.class])) {
        completion(nil, XYBookAudioMakeSnckError(4101, @"Invalid share parameters."));
        return;
    }
    if (![self.host respondsToSelector:@selector(bookAudioShare:from:completion:)]) {
        completion(nil, XYBookAudioMakeSnckError(4107, @"Host sharing is unavailable."));
        return;
    }
    NSError *error = [self presentationError:presenter];
    if (error) {
        completion(nil, error);
        return;
    }
    NSMutableDictionary *request = [@{@"title" : title, @"link" : link, @"desc" : description ?: @""} mutableCopy];
    if (XYBookAudioParseSnckURL(image)) {
        request[XYBookAudioKeyImageURL] = image;
    }
    if (platform) {
        request[@"platform"] = platform;
    }
    [self dispatchShare:request presenter:presenter snck:YES completion:completion];
}

- (void)dispatchShare:(NSDictionary *)parameters
            presenter:(UIViewController *)presenter
                 snck:(BOOL)snck
           completion:(XYBookAudioCompletion)completion {
    if (self.sharePending) {
        completion(nil, XYBookAudioError(XYBookAudioBusy, @"Sharing is already in progress."));
        return;
    }
    self.sharePending = YES;
    [self.logger write:XYBookAudioLogLevelInfo component:XYBookAudioLogHost message:@"Share requested from host."];
    NSString *requestId = snck ? NSUUID.UUID.UUIDString : nil;
    NSError *timeout = snck ? XYBookAudioMakeSnckError(4105, @"Host sharing timed out.")
                            : XYBookAudioError(XYBookAudioHostFailed, @"Host sharing timed out.");
    XYBookAudioHostReply reply = XYBookAudioMakeHostReply(
        snck ? 120 : XYBookAudioHostRequestTimeout, timeout, nil, ^(id response, NSError *hostError) {
            self.sharePending = NO;
            if (hostError) {
                [self.logger error:hostError component:XYBookAudioLogHost operation:@"Share"];
            }
            if (self.disposed) {
                completion(nil, XYBookAudioError(XYBookAudioDisposed, @"SDK was disposed."));
                return;
            }
            XYBookAudioShareResult result = hostError ? XYBookAudioShareFailed : [response integerValue];
            if (snck) {
                NSDictionary *statuses = @{
                    @(XYBookAudioShareAccepted) : @"DISPATCHED",
                    @(XYBookAudioShareSucceeded) : @"SUCCESS",
                    @(XYBookAudioShareCancelled) : @"CANCELLED"
                };
                NSString *status = statuses[@(result)];
                if (status) {
                    completion(@{@"requestId" : requestId, @"status" : status}, nil);
                } else {
                    NSInteger code = result == XYBookAudioShareUnsupported ? 4107 : 4109;
                    completion(nil, hostError == timeout ? timeout
                                                         : XYBookAudioMakeSnckError(code, @"Host sharing failed."));
                }
                return;
            }
            NSString *status = XYBookAudioShareStatus(result);
            [self.logger write:XYBookAudioLogLevelInfo component:XYBookAudioLogHost
                       message:[@"Share result: " stringByAppendingString:status]];
            completion(@{XYBookAudioKeyStatus : status}, nil);
        });
    [self.host bookAudioShare:[parameters copy] from:presenter
                   completion:^(XYBookAudioShareResult result, NSError *hostError) {
                       reply(@(result), hostError);
                   }];
}

/// 终止宿主动作入口并移除身份刷新回调；已有异步请求随后以终止状态结算。
- (void)dispose {
    self.disposed = YES;
    self.identityChanged = nil;
    if (self.loginReply) {
        self.loginReply(nil, XYBookAudioError(XYBookAudioDisposed, @"SDK was disposed."));
    }
}

@end
