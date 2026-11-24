// 宿主回调可能跨线程、重复或迟到；统一回主线程结算一次，页面关闭后仍允许有效的身份刷新。
#import "XYBookAudioHostActions.h"
#import <sys/utsname.h>
#import "XYBookAudioMessageProtocol.h"
#import "XYBookAudioLogger.h"

static NSTimeInterval const XYBookAudioHostRequestTimeout = 180;
typedef void (^XYBookAudioHostReply)(id result, NSError *error);

/// 宿主回调与超时都在主线程结算，首次结算后释放业务回调。登录的身份刷新可处理迟到结果。
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
         completion:(XYBookAudioCompletion)completion {
    parameters = [parameters copy];
    NSError *error = [self userInfoParametersError:parameters];
    NSDictionary *identity = error ? nil : [self identity:&error];
    if (error) {
        completion(nil, error);
        return;
    }
    if ([identity[XYBookAudioKeyIsLoggedIn] boolValue]) {
        [self readUserInfoWithParameters:parameters completion:completion];
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
        [self readUserInfoWithParameters:parameters completion:completion];
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

/// 登录占用在首次结果或超时后释放；重复／迟到回调不能再次结算，但有效账号变化仍需刷新。
- (void)login:(UIViewController *)presenter completion:(XYBookAudioCompletion)completion {
    if (self.loginPending) {
        completion(nil, XYBookAudioError(XYBookAudioBusy, @"Login is already in progress."));
        return;
    }
    self.loginPending = YES;
    [self.logger write:XYBookAudioLogLevelInfo component:XYBookAudioLogHost message:@"Login requested from host."];
    __weak typeof(self) weakSelf = self;
    dispatch_block_t refreshIdentity = ^{
        dispatch_block_t identityChanged = weakSelf.identityChanged;
        if (identityChanged && !weakSelf.disposed) {
            identityChanged();
        }
    };
    XYBookAudioHostReply reply = XYBookAudioMakeHostReply(
        XYBookAudioHostRequestTimeout, XYBookAudioError(XYBookAudioHostFailed, @"Host login timed out."),
        refreshIdentity, ^(id response, NSError *hostError) {
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
            XYBookAudioLoginResult result = [response integerValue];
            NSString *status = XYBookAudioValueFailed;
            if (!hostError) {
                if (result == XYBookAudioLoginLoggedIn && [identity[XYBookAudioKeyIsLoggedIn] boolValue]) {
                    status = XYBookAudioValueLoggedIn;
                } else if (result == XYBookAudioLoginCancelled) {
                    status = XYBookAudioValueCancelled;
                }
            }
            [self.logger write:XYBookAudioLogLevelInfo component:XYBookAudioLogHost
                       message:[@"Login result: " stringByAppendingString:status]];
            completion(@{XYBookAudioKeyStatus : status, XYBookAudioKeyIdentity : identity}, nil);
        });
    [self.host bookAudioRequestLoginFrom:presenter completion:^(XYBookAudioLoginResult result, NSError *hostError) {
        reply(@(result), hostError);
    }];
}

/// 先验证分享字段再交给宿主；仅透传公开分享契约，回执不承诺第三方平台分享完成。
- (void)share:(NSDictionary *)parameters
     presenter:(UIViewController *)presenter
    completion:(XYBookAudioCompletion)completion {
    if (!XYBookAudioIsNonEmptyString(parameters[XYBookAudioKeyTitle]) ||
        !XYBookAudioIsHTTPSURLString(parameters[XYBookAudioKeyLink]) ||
        (parameters[XYBookAudioKeyDescription] &&
         ![parameters[XYBookAudioKeyDescription] isKindOfClass:NSString.class]) ||
        (parameters[XYBookAudioKeyImageURL] && (![parameters[XYBookAudioKeyImageURL] isKindOfClass:NSString.class] ||
                                                ([parameters[XYBookAudioKeyImageURL] length] &&
                                                 !XYBookAudioIsHTTPSURLString(parameters[XYBookAudioKeyImageURL]))))) {
        completion(nil,
                   XYBookAudioError(XYBookAudioInvalidArgument,
                                    @"Sharing requires title and an HTTPS link; desc and HTTPS imgUrl are optional."));
        return;
    }
    [self dispatchShare:parameters presenter:presenter snck:NO completion:completion];
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
}

@end
