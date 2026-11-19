// 宿主回调可能跨线程、重复或迟到；统一回主线程结算一次，页面关闭后仍允许有效的身份刷新。
#import "XYBookAudioHostActions.h"
#import "XYBookAudioMessageProtocol.h"
#import "XYBookAudioLogger.h"
static NSTimeInterval const XYBookAudioHostUITimeout = 180;

@interface XYBookAudioHostActions ()

@property (nonatomic, strong) XYBookAudioLogger *logger;

@property (nonatomic, weak) id<XYBookAudioHost> host;
@property (nonatomic) BOOL loginPending, sharePending, disposed;

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
    return @{XYBookAudioKeyIsLoggedIn : @(identity.isLoggedIn), XYBookAudioKeyUserId : identity.userId};
}

/// 系统资料和设备标识属于宿主；只校验 JSON 边界，不伪造缺失字段。
- (void)getSystemInfoFrom:(UIViewController *)presenter completion:(XYBookAudioCompletion)completion {
    if (![self.host respondsToSelector:@selector(bookAudioSystemInfoFromViewController:)]) {
        completion(nil, XYBookAudioError(XYBookAudioUnsupported, @"Host system-info provider is unavailable."));
        return;
    }
    NSDictionary *information = [self.host bookAudioSystemInfoFromViewController:presenter];
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
         completion:(XYBookAudioCompletion)completion {
    NSError *error = [self userInfoParametersError:parameters];
    NSDictionary *identity = error ? nil : [self identity:&error];
    if (error) {
        completion(nil, error);
        return;
    }
    BOOL usingTicket = [parameters[XYBookAudioKeyUseTicket] boolValue];
    if ([identity[XYBookAudioKeyIsLoggedIn] boolValue]) {
        [self readUserInfoUsingTicket:usingTicket completion:completion];
        return;
    }
    if (![parameters[XYBookAudioKeyGoLogin] boolValue]) {
        completion(@{}, nil);
        return;
    }
    [self requestLoginFrom:presenter completion:^(NSDictionary *result, NSError *loginError) {
        if (loginError) {
            completion(nil, loginError);
            return;
        }
        if (![result[XYBookAudioKeyStatus] isEqual:XYBookAudioValueLoggedIn]) {
            completion(@{}, nil);
            return;
        }
        [self readUserInfoUsingTicket:usingTicket completion:completion];
    }];
}

/// 宿主异步资料原样回传；账号变化或实例销毁后拒绝旧资料，避免跨账号泄露。
- (void)readUserInfoUsingTicket:(BOOL)usingTicket completion:(XYBookAudioCompletion)completion {
    if (![self.host respondsToSelector:@selector(bookAudioUserInfoUsingTicket:completion:)]) {
        completion(nil, XYBookAudioError(XYBookAudioUnsupported, @"Host user-info provider is unavailable."));
        return;
    }
    NSString *userId = [self.host bookAudioUserIdentity].userId;
    __block BOOL settled = NO;
    void (^resolve)(NSDictionary *, NSError *) = ^(NSDictionary *userInfo, NSError *hostError) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (settled) {
                return;
            }
            settled = YES;
            NSError *error = [self userInfoResultError:userInfo hostError:hostError expectedUserId:userId];
            completion(error ? nil : userInfo, error);
        });
    };
    [self.host bookAudioUserInfoUsingTicket:usingTicket completion:resolve];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, XYBookAudioHostUITimeout * NSEC_PER_SEC), dispatch_get_main_queue(),
                   ^{
                       if (!settled) {
                           resolve(nil, XYBookAudioError(XYBookAudioHostFailed, @"Host user-info request timed out."));
                       }
                   });
}

/// 只检查资料是否仍属于当前账号及 JSON 可用性；具体字段由宿主和 H5 标准约定。
- (NSError *)userInfoResultError:(NSDictionary *)userInfo
                       hostError:(NSError *)hostError
                  expectedUserId:(NSString *)userId {
    if (self.disposed) {
        return XYBookAudioError(XYBookAudioDisposed, @"SDK was disposed.");
    }
    if (hostError) {
        [self.logger error:hostError component:XYBookAudioLogHost operation:XYBookAudioActionGetUserInfo];
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

/// 登录占用在首次结果或超时后释放；重复／迟到回调不能再次结算，但有效账号变化仍需刷新。
- (void)login:(UIViewController *)presenter completion:(XYBookAudioCompletion)completion {
    if (self.loginPending) {
        completion(nil, XYBookAudioError(XYBookAudioBusy, @"Login is already in progress."));
        return;
    }
    self.loginPending = YES;
    [self.logger write:XYBookAudioLogLevelInfo component:XYBookAudioLogHost message:@"Login requested from host."];
    __block BOOL settled = NO;
    void (^resolve)(XYBookAudioLoginResult, NSError *) = ^(XYBookAudioLoginResult result, NSError *hostError) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (self.identityChanged && !self.disposed) {
                self.identityChanged();
            }
            if (settled) {
                return;
            }
            settled = YES;
            self.loginPending = NO;
            if (hostError) {
                [self.logger error:hostError component:XYBookAudioLogHost operation:@"Login"];
            }
            if (self.disposed) {
                completion(nil, XYBookAudioError(XYBookAudioDisposed, @"SDK was disposed."));
                return;
            }
            if ([hostError.domain isEqual:XYBookAudioErrorDomain] && hostError.code == XYBookAudioBusy) {
                completion(nil, hostError);
                return;
            }
            NSError *identityError;
            NSDictionary *identity = [self identity:&identityError];
            if (identityError) {
                completion(nil, identityError);
                return;
            }
            BOOL valid = result == XYBookAudioLoginLoggedIn && [identity[XYBookAudioKeyIsLoggedIn] boolValue];
            NSString *status = valid                                 ? XYBookAudioValueLoggedIn
                               : result == XYBookAudioLoginCancelled ? XYBookAudioValueCancelled
                                                                     : XYBookAudioValueFailed;
            if (hostError || identityError) {
                status = XYBookAudioValueFailed;
            }
            [self.logger write:XYBookAudioLogLevelInfo component:XYBookAudioLogHost
                       message:[@"Login result: " stringByAppendingString:status]];
            completion(@{XYBookAudioKeyStatus : status, XYBookAudioKeyIdentity : identity}, nil);
        });
    };
    [self.host bookAudioRequestLoginFrom:presenter completion:resolve];
    dispatch_after(
        dispatch_time(DISPATCH_TIME_NOW, XYBookAudioHostUITimeout * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
            if (!settled) {
                resolve(XYBookAudioLoginFailed, XYBookAudioError(XYBookAudioHostFailed, @"Host login timed out."));
            }
        });
}

/// 先验证分享字段再交给宿主；仅透传公开分享契约，回执不承诺第三方平台分享完成。
- (void)share:(NSDictionary *)parameters
     presenter:(UIViewController *)presenter
    completion:(XYBookAudioCompletion)completion {
    if (!XYBookAudioString(parameters[XYBookAudioKeyTitle]) || !XYBookAudioHTTPS(parameters[XYBookAudioKeyLink]) ||
        (parameters[XYBookAudioKeyDesc] && ![parameters[XYBookAudioKeyDesc] isKindOfClass:NSString.class]) ||
        (parameters[XYBookAudioKeyImageURL] &&
         (![parameters[XYBookAudioKeyImageURL] isKindOfClass:NSString.class] ||
          ([parameters[XYBookAudioKeyImageURL] length] && !XYBookAudioHTTPS(parameters[XYBookAudioKeyImageURL]))))) {
        completion(nil,
                   XYBookAudioError(XYBookAudioInvalidArgument,
                                    @"Sharing requires title and an HTTPS link; desc and HTTPS imgUrl are optional."));
        return;
    }
    if (self.sharePending) {
        completion(nil, XYBookAudioError(XYBookAudioBusy, @"Sharing is already in progress."));
        return;
    }
    self.sharePending = YES;
    [self.logger write:XYBookAudioLogLevelInfo component:XYBookAudioLogHost message:@"Share requested from host."];
    __block BOOL settled = NO;
    void (^resolve)(XYBookAudioShareResult, NSError *) = ^(XYBookAudioShareResult result, NSError *hostError) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (settled) {
                return;
            }
            settled = YES;
            self.sharePending = NO;
            if (hostError) {
                [self.logger error:hostError component:XYBookAudioLogHost operation:@"Share"];
            }
            if (self.disposed) {
                completion(nil, XYBookAudioError(XYBookAudioDisposed, @"SDK was disposed."));
                return;
            }
            NSString *status = hostError                               ? XYBookAudioValueFailed
                               : result == XYBookAudioShareAccepted    ? XYBookAudioValueAccepted
                               : result == XYBookAudioShareUnsupported ? XYBookAudioValueUnsupported
                               : result == XYBookAudioShareCancelled   ? XYBookAudioValueCancelled
                                                                       : XYBookAudioValueFailed;
            [self.logger write:XYBookAudioLogLevelInfo component:XYBookAudioLogHost
                       message:[@"Share result: " stringByAppendingString:status]];
            completion(@{XYBookAudioKeyStatus : status}, nil);
        });
    };
    [self.host bookAudioShare:[parameters copy] from:presenter completion:resolve];
    dispatch_after(
        dispatch_time(DISPATCH_TIME_NOW, XYBookAudioHostUITimeout * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
            if (!settled) {
                resolve(XYBookAudioShareFailed, XYBookAudioError(XYBookAudioHostFailed, @"Host sharing timed out."));
            }
        });
}

/// 终止宿主动作入口并移除身份刷新回调；已有异步请求随后以终止状态结算。
- (void)dispose {
    self.disposed = YES;
    self.identityChanged = nil;
}

@end
