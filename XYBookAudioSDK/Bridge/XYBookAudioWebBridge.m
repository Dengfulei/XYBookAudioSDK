// 对应原项目 XYWebViewJSBridgeManager：完整 H5 请求直接进入 xh 同名方法，业务状态仍归 SDK 会话。
#import "XYBookAudioWebBridge.h"
#import "XYBookAudioMessageProtocol.h"
#import <objc/runtime.h>

static NSString *const XYBookAudioH5MethodPrefix = @"xh";
static NSUInteger const XYBookAudioMaximumMessageLength = 256 * 1024;
/// 中文 UTF-8 经两次 URI 编码最多放大 15 倍；传输限额为原 JSON 限额预留编码与消息头空间。
static NSUInteger const XYBookAudioMaximumEncodedMessageLength = 4 * 1024 * 1024;

@interface XYBookAudioWebBridge ()
@property (nonatomic, strong) XYBookAudioLogger *logger;
@property (nonatomic, weak) XYBookAudioSDKManager *SDK;
@property (nonatomic, weak) XYBookAudioBridgeWebView *webView;
@property (nonatomic, strong) XYBookAudioConfiguration *configuration;
@property (nonatomic, strong) NSUUID *subscription;
@property (nonatomic) NSUInteger generation;
@property (nonatomic) BOOL active;

/// 只向当前可信文档发送回调，页面代次改变后自动丢弃旧结果。
- (void)send:(NSString *)action parameters:(NSDictionary *)parameters generation:(NSUInteger)generation;
/// 无法解析的消息通过错误事件报告；标准无回调方法自己的错误只记录日志。
- (void)reportInvalidRequest:(NSString *)message;
@end

@implementation XYBookAudioWebBridge

/// xh 前缀保留给标准 H5 入口；actionName 不携带冒号，避免调用内部方法或拼接多个参数。
+ (BOOL)supportsAction:(NSString *)action {
    if (!XYBookAudioString(action) || ![action hasPrefix:XYBookAudioH5MethodPrefix] || [action containsString:@":"]) {
        return NO;
    }
    SEL selector = NSSelectorFromString([action stringByAppendingString:@":"]);
    return [self instancesRespondToSelector:selector];
}

/// 能力集合直接来自实际方法；仅在查询集合时枚举，不参与每次 H5 请求的分发。
+ (NSArray<NSString *> *)supportedActions {
    unsigned int count = 0;
    Method *methods = class_copyMethodList(self, &count);
    NSMutableArray<NSString *> *actions = [NSMutableArray array];
    for (unsigned int index = 0; index < count; index++) {
        NSString *name = NSStringFromSelector(method_getName(methods[index]));
        if (![name hasSuffix:@":"]) {
            continue;
        }
        NSString *action = [name substringToIndex:name.length - 1];
        if ([self supportsAction:action]) {
            [actions addObject:action];
        }
    }
    free(methods);
    return [actions sortedArrayUsingSelector:@selector(compare:)];
}

- (instancetype)initWithSDK:(XYBookAudioSDKManager *)SDK
              configuration:(XYBookAudioConfiguration *)configuration
                    webView:(XYBookAudioBridgeWebView *)webView
                     logger:(XYBookAudioLogger *)logger {
    if ((self = [super init])) {
        _SDK = SDK;
        _configuration = configuration;
        _webView = webView;
        _logger = logger;
        [self registerJSCallNative];
    }
    return self;
}

#pragma mark - JSCallNative 入口

/// 采用原项目的接口对象 + JSCallNativeBlock；弱捕获避免 WebKit 反向持有管理类与页面。
- (void)registerJSCallNative {
    XYBookAudioScriptMessageHandler *interface = [XYBookAudioScriptMessageHandler new];
    __weak typeof(self) weakSelf = self;
    interface.messageValidator = ^BOOL(WKScriptMessage *message) {
        return [weakSelf acceptsScriptMessage:message];
    };
    interface.invalidMessageHandler = ^(NSString *reason) {
        [weakSelf reportInvalidRequest:reason];
    };
    interface.JSCallNativeBlock = ^(NSString *object) {
        [weakSelf handleJSCallNative:object];
    };
    [self.webView addJavascriptInterface:interface];
}

/// 只接收当前可信主文档的有界字符串；来源校验通过后才允许解析 actionName。
- (BOOL)acceptsScriptMessage:(WKScriptMessage *)message {
    if (!self.active || !message.frameInfo.isMainFrame ||
        ![self.configuration allowsURL:message.frameInfo.request.URL] ||
        ![self.configuration allowsURL:self.webView.URL]) {
        [self.logger write:XYBookAudioLogLevelWarning component:XYBookAudioLogBridge
                   message:@"Message outside the active trusted main frame ignored."];
        return NO;
    }
    if (![message.body isKindOfClass:NSString.class] ||
        [message.body length] > XYBookAudioMaximumEncodedMessageLength) {
        [self reportInvalidRequest:@"EasyJS expects a bounded encoded message string."];
        return NO;
    }
    return YES;
}

/// 与原项目一致按 actionName 查找同名方法并调用，新增 xh 入口无需维护另一份名单。
- (void)handleJSCallNative:(NSString *)object {
    // 长度限制针对解码后的业务 JSON，不能因中文、百分号的传输编码而误拒绝合法消息。
    if (object.length > XYBookAudioMaximumMessageLength) {
        [self reportInvalidRequest:@"JSCallNative JSON exceeds the message length limit."];
        return;
    }
    id message = [NSJSONSerialization JSONObjectWithData:[object dataUsingEncoding:NSUTF8StringEncoding] options:0
                                                   error:nil];
    if (![message isKindOfClass:NSDictionary.class]) {
        [self reportInvalidRequest:@"Malformed request object."];
        return;
    }
    NSDictionary *request = message;
    NSString *action = request[XYBookAudioKeyActionName];
    if (![self.class supportsAction:action]) {
        [self reportActionError:XYBookAudioError(XYBookAudioUnsupported, @"Unsupported H5 action.") request:request
                     generation:self.generation];
        return;
    }
    id parameters = request[XYBookAudioKeyParameters];
    id callback = request[XYBookAudioKeyCallbackActionName];
    if ((parameters && ![parameters isKindOfClass:NSDictionary.class]) || (callback && !XYBookAudioString(callback))) {
        NSError *error = XYBookAudioError(
            XYBookAudioInvalidArgument,
            @"parameters must be an object; callbackActionName must be a nonempty string when provided.");
        if ([@[
                XYBookAudioActionOpenWindow, XYBookAudioActionCloseWindow, XYBookAudioActionGoLogin,
                XYBookAudioActionShowShareMenu
            ] containsObject:action]) {
            [self.logger error:error component:XYBookAudioLogBridge operation:action];
        } else {
            [self reportActionError:error request:request generation:self.generation];
        }
        return;
    }
    // 无业务参数的方法允许省略 parameters；需要字段的方法继续由各自业务能力校验。
    if (!parameters) {
        NSMutableDictionary *normalizedRequest = [request mutableCopy];
        normalizedRequest[XYBookAudioKeyParameters] = @{};
        request = normalizedRequest;
    }
    SEL selector = NSSelectorFromString([action stringByAppendingString:@":"]);
    NSMethodSignature *signature = [self methodSignatureForSelector:selector];
    NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:signature];
    invocation.target = self;
    invocation.selector = selector;
    [invocation setArgument:&request atIndex:2];
    [invocation invoke];
}

#pragma mark - 标准 H5 同名方法

// xh 同名方法直接作为 H5 入口；只使用 actionName / parameters / callbackActionName 标准信封。

/// 与原项目同名；无参数时也允许关闭，只关闭当前可见窗口，不扩展 H5 回调。
- (void)xhCloseWindow:(NSDictionary *)request {
    if (![self hasWindowContextForAction:XYBookAudioActionCloseWindow]) {
        return;
    }
    NSError *error = [self.windowRouter closeWindowFromPage:self.page];
    [self logWindowError:error action:XYBookAudioActionCloseWindow];
}

/// 与原项目一致从完整请求的 parameters 中取 url；可信范围由窗口容器统一检查。
- (void)xhOpenWindow:(NSDictionary *)request {
    id address = request[XYBookAudioKeyParameters][XYBookAudioKeyURL];
    NSURL *URL = XYBookAudioString(address) ? [NSURL URLWithString:address] : nil;
    if (!URL.scheme.length) {
        [self logWindowError:XYBookAudioError(XYBookAudioInvalidArgument,
                                              @"xhOpenWindow requires an absolute parameters.url.")
                      action:XYBookAudioActionOpenWindow];
        return;
    }
    if (![self hasWindowContextForAction:XYBookAudioActionOpenWindow]) {
        return;
    }
    NSError *error = [self.windowRouter openWindowWithURL:URL fromPage:self.page];
    [self logWindowError:error action:XYBookAudioActionOpenWindow];
}

/// 对齐 xh.goLogin()：仅请求宿主打开登录页，不要求参数，也不向 H5 返回自定义登录结果。
- (void)xhGoLogin:(NSDictionary *)request {
    UIViewController *page = self.page;
    UINavigationController *navigation = page.navigationController;
    if (!page || !page.viewIfLoaded.window || page != navigation.topViewController ||
        navigation.transitionCoordinator || navigation.isBeingDismissed || navigation.presentedViewController ||
        page.presentedViewController) {
        [self.logger error:XYBookAudioError(XYBookAudioBusy, @"The current page is unavailable for login.")
                 component:XYBookAudioLogBridge
                 operation:XYBookAudioActionGoLogin];
        return;
    }
    [self.logger write:XYBookAudioLogLevelDebug component:XYBookAudioLogBridge
               message:[XYBookAudioActionGoLogin stringByAppendingString:@" received."]];
    // 登录结果只用于诊断，H5 通过 xhGetUserInfo 或身份事件读取账号状态。
    XYBookAudioLogger *logger = self.logger;
    [self.SDK requestHostLoginFromViewController:page completion:^(NSDictionary *result, NSError *error) {
        if (error) {
            [logger error:error component:XYBookAudioLogBridge operation:XYBookAudioActionGoLogin];
        } else if ([result[XYBookAudioKeyStatus] isEqual:XYBookAudioValueFailed]) {
            [logger write:XYBookAudioLogLevelWarning component:XYBookAudioLogBridge
                  message:[XYBookAudioActionGoLogin stringByAppendingString:@" failed at host."]];
        }
    }];
}

/// 沿用原版 xinhua-sdk 的 {data:1/0} 能力查询返回值。
- (void)xhCanIUse:(NSDictionary *)request {
    NSString *callback = request[XYBookAudioKeyCallbackActionName];
    if (!callback) {
        [self reportInvalidRequest:@"actionName, parameters and callbackActionName are required."];
        return;
    }
    NSString *method = request[XYBookAudioKeyParameters][XYBookAudioKeyName];
    BOOL supported = [self.class supportsAction:method];
    [self send:callback parameters:@{XYBookAudioKeyData : @(supported ? 1 : 0)} generation:self.generation];
}

/// 查询已确认的动作、倍速与定时能力；回调直接接收业务对象，不要求额外传输字段。
- (void)xhBookAudioGetCapabilities:(NSDictionary *)request {
    [self send:request[XYBookAudioKeyCallbackActionName] parameters:[self.SDK getCapabilities]
        generation:self.generation];
}

/// 直接读取共享播放会话快照；不经过命令分发，不改变播放状态。
- (void)xhBookAudioGetSnapshot:(NSDictionary *)request {
    [self send:request[XYBookAudioKeyCallbackActionName] parameters:[self.SDK getSnapshot] generation:self.generation];
}

/// xh.getUserInfo 会继续查询系统资料；设备标识必须来自宿主，不能由 SDK 临时生成。
- (void)xhGetSystemInfo:(NSDictionary *)request {
    [self forwardAction:XYBookAudioActionGetSystemInfo request:request];
}

/// 原样回传宿主标准用户资料；goLogin 需要当前页面可展示宿主 UI，useTicket 由宿主处理。
- (void)xhGetUserInfo:(NSDictionary *)request {
    id goLogin = request[XYBookAudioKeyParameters][XYBookAudioKeyGoLogin];
    if ([goLogin isKindOfClass:NSNumber.class] && [goLogin boolValue] &&
        self.page != self.page.navigationController.topViewController) {
        [self reportActionError:XYBookAudioError(XYBookAudioBusy, @"Login requires the current web page.")
                        request:request
                     generation:self.generation];
        return;
    }
    [self forwardAction:XYBookAudioActionGetUserInfo request:request];
}

/// 标准分享菜单不承诺业务成功；仅在宿主确认已选渠道且存在回调名时回传空对象。
- (void)xhShowShareMenu:(NSDictionary *)request {
    if (self.page != self.page.navigationController.topViewController) {
        [self.logger error:XYBookAudioError(XYBookAudioBusy, @"Sharing requires the current web page.")
                 component:XYBookAudioLogBridge
                 operation:XYBookAudioActionShowShareMenu];
        return;
    }
    NSUInteger generation = self.generation;
    [self.SDK executeAction:XYBookAudioActionShowShareMenu parameters:request[XYBookAudioKeyParameters]
                 completion:^(NSDictionary *result, NSError *error) {
                     if (error) {
                         [self.logger error:error component:XYBookAudioLogBridge
                                  operation:XYBookAudioActionShowShareMenu];
                         return;
                     }
                     if ([result[XYBookAudioKeyStatus] isEqual:XYBookAudioValueAccepted]) {
                         [self send:request[XYBookAudioKeyCallbackActionName] parameters:@{} generation:generation];
                     } else if (![result[XYBookAudioKeyStatus] isEqual:XYBookAudioValueCancelled]) {
                         [self.logger write:XYBookAudioLogLevelWarning component:XYBookAudioLogBridge
                                    message:@"xhShowShareMenu was not accepted by the host."];
                     }
                 }];
}

/// 设置章节队列；由播放会话校验字段并原子替换。
- (void)xhBookAudioSetQueue:(NSDictionary *)request {
    [self forwardAction:XYBookAudioActionSetQueue request:request];
}

/// 请求播放当前章；身份准入与音源加载由播放会话处理。
- (void)xhBookAudioPlay:(NSDictionary *)request {
    [self forwardAction:XYBookAudioActionPlay request:request];
}

/// 暂停当前播放，保留队列与断点。
- (void)xhBookAudioPause:(NSDictionary *)request {
    [self forwardAction:XYBookAudioActionPause request:request];
}

/// 停止当前播放并清除定时器。
- (void)xhBookAudioStop:(NSDictionary *)request {
    [self forwardAction:XYBookAudioActionStop request:request];
}

/// 按 positionMs 跳转进度，已知时长时限制在章节范围内。
- (void)xhBookAudioSeekTo:(NSDictionary *)request {
    [self forwardAction:XYBookAudioActionSeekTo request:request];
}

/// 选择上一章并尝试播放；章节边界由会话检查。
- (void)xhBookAudioPrevious:(NSDictionary *)request {
    [self forwardAction:XYBookAudioActionPrevious request:request];
}

/// 选择下一章并尝试播放；到达队尾时沿用会话规则。
- (void)xhBookAudioNext:(NSDictionary *)request {
    [self forwardAction:XYBookAudioActionNext request:request];
}

/// 按 chapterId 选择章节，受限章节由会话拦截。
- (void)xhBookAudioSelectChapter:(NSDictionary *)request {
    [self forwardAction:XYBookAudioActionSelectChapter request:request];
}

/// 设置倍速，合法值由共享播放规则检查。
- (void)xhBookAudioSetRate:(NSDictionary *)request {
    [self forwardAction:XYBookAudioActionSetRate request:request];
}

/// 设置定时关闭；非法参数不得覆盖已有定时。
- (void)xhBookAudioSetSleepTimer:(NSDictionary *)request {
    [self forwardAction:XYBookAudioActionSetSleepTimer request:request];
}

/// 取消当前定时关闭，不改变播放。
- (void)xhBookAudioCancelSleepTimer:(NSDictionary *)request {
    [self forwardAction:XYBookAudioActionCancelSleepTimer request:request];
}

/// 每个文档只订阅一次，随后立即发送快照；重复订阅不会累积事件接收器。
- (void)xhBookAudioSubscribe:(NSDictionary *)request {
    NSUInteger generation = self.generation;
    if (!self.subscription) {
        __weak typeof(self) weakSelf = self;
        self.subscription = [self.SDK subscribe:^(NSString *event, NSDictionary *payload) {
            [weakSelf send:event parameters:payload generation:generation];
        }];
    }
    [self send:request[XYBookAudioKeyCallbackActionName] parameters:@{XYBookAudioKeySubscribed : @YES}
        generation:generation];
    [self send:XYBookAudioPlaybackEvent parameters:[self.SDK getSnapshot] generation:generation];
}

/// 仅取消当前页面订阅；不影响宿主或其他页面。
- (void)xhBookAudioUnsubscribe:(NSDictionary *)request {
    if (self.subscription) {
        [self.SDK unsubscribe:self.subscription];
    }
    self.subscription = nil;
    [self send:request[XYBookAudioKeyCallbackActionName] parameters:@{XYBookAudioKeySubscribed : @NO}
        generation:self.generation];
}

#pragma mark - 窗口诊断

/// 仅检查页面连接并记录动作名；能否导航由窗口容器检查，日志不包含 URL 或账号参数。
- (BOOL)hasWindowContextForAction:(NSString *)action {
    if (!self.windowRouter || !self.page) {
        [self logWindowError:XYBookAudioError(XYBookAudioBusy, @"The web window is unavailable.") action:action];
        return NO;
    }
    [self.logger write:XYBookAudioLogLevelDebug component:XYBookAudioLogBridge
               message:[action stringByAppendingString:@" received."]];
    return YES;
}

/// 三个标准页面方法无业务回调；失败只通过宿主配置的日志通道记录。
- (void)logWindowError:(NSError *)error action:(NSString *)action {
    if (error) {
        [self.logger error:error component:XYBookAudioLogBridge operation:action];
    }
}

#pragma mark - H5 回调

- (void)forwardAction:(NSString *)action request:(NSDictionary *)request {
    [self.SDK executeAction:action parameters:request[XYBookAudioKeyParameters]
                 completion:[self callbackForRequest:request]];
}

/// 异步结果只发回发起请求的文档。
- (XYBookAudioCompletion)callbackForRequest:(NSDictionary *)request {
    NSUInteger generation = self.generation;
    __weak typeof(self) weakSelf = self;
    return ^(NSDictionary *result, NSError *error) {
        if (error) {
            [weakSelf reportActionError:error request:request generation:generation];
            return;
        }
        [weakSelf send:request[XYBookAudioKeyCallbackActionName] parameters:result generation:generation];
    };
}

/// 业务失败进入已确认的错误事件；成功回调保持业务对象原样，不再包装 ok/data/error。
- (void)reportActionError:(NSError *)error request:(NSDictionary *)request generation:(NSUInteger)generation {
    NSString *action = request[XYBookAudioKeyActionName];
    NSString *operation = [self.class supportsAction:action] ? action : @"H5 action";
    [self.logger error:error component:XYBookAudioLogBridge operation:operation];
    NSDictionary *payload =
        @{XYBookAudioKeyCode : XYBookAudioErrorName(error), XYBookAudioKeyMessage : error.localizedDescription};
    [self send:XYBookAudioErrorEvent parameters:payload generation:generation];
}

#pragma mark - 页面生命周期与回调

- (void)activate {
    self.active = YES;
    [self.logger write:XYBookAudioLogLevelDebug component:XYBookAudioLogBridge
               message:@"Trusted page bridge activated."];
}

/// 导航、关闭或进程退出时递增代次并取消页面订阅；未完成回执保留在旧代次，不能送到新页面。
- (void)invalidate {
    if (self.active) {
        [self.logger write:XYBookAudioLogLevelDebug component:XYBookAudioLogBridge message:@"Page bridge invalidated."];
    }
    self.active = NO;
    self.generation++;
    if (self.subscription) {
        [self.SDK unsubscribe:self.subscription];
    }
    self.subscription = nil;
}

/// 格式错误沿用既有错误事件；不输出原始 JSON，避免日志泄露账号与资源地址。
- (void)reportInvalidRequest:(NSString *)message {
    [self.logger write:XYBookAudioLogLevelWarning component:XYBookAudioLogBridge message:message];
    [self send:XYBookAudioErrorEvent
        parameters:@{XYBookAudioKeyCode : @"INVALID_ARGUMENT", XYBookAudioKeyMessage : message}
        generation:self.generation];
}

/// 在发送前再次验证文档代次；WebView 负责结构化回调，管理类只负责决定回调是否仍有效。
- (void)send:(NSString *)action parameters:(NSDictionary *)parameters generation:(NSUInteger)generation {
    if (!XYBookAudioString(action) || !self.active || generation != self.generation ||
        ![self.configuration allowsURL:self.webView.URL]) {
        return;
    }
    [self.webView nativeCallJS:@{XYBookAudioKeyActionName : action, XYBookAudioKeyParameters : parameters}
                    completion:^(NSError *error) {
                        if (error && generation == self.generation && self.active) {
                            [self.logger error:error component:XYBookAudioLogBridge operation:@"JS callback delivery"];
                        }
                    }];
}

- (void)dealloc {
    [self invalidate];
}

@end
