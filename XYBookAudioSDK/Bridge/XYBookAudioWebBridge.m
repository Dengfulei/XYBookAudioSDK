// 对应原项目 XYWebViewJSBridgeManager：完整 H5 请求直接进入 xh 同名方法，业务状态仍归 SDK 会话。
#import "XYBookAudioWebBridge.h"
#import <objc/runtime.h>

static NSString *const XYBookAudioSnckMethodPrefix = @"xhSnck";
static NSUInteger const XYBookAudioSnckMaximumMessageLength = 80 * 1024;
/// 中文 UTF-8 经两次 URI 编码最多放大 15 倍；传输限额为原 JSON 限额预留编码与消息头空间。
static NSUInteger const XYBookAudioMaximumEncodedMessageLength = 4 * 1024 * 1024;

static NSString *const XYBookAudioSnckEventUserChanged = @"snckUserChanged";
static NSString *const XYBookAudioSnckEventQueueChanged = @"snckAudioQueueChanged";
static NSString *const XYBookAudioSnckEventStateChanged = @"snckAudioStateChanged";
static NSString *const XYBookAudioSnckEventTimerChanged = @"snckAudioTimerChanged";
static NSString *const XYBookAudioSnckEventProgress = @"snckAudioProgress";
static NSString *const XYBookAudioSnckEventAudioError = @"snckAudioError";

static NSString *const XYBookAudioSnckReasonQueueReplaced = @"queue_replaced";
static NSString *const XYBookAudioSnckReasonStopped = @"stopped";
static NSString *const XYBookAudioSnckReasonItemChanged = @"item_changed";
static NSString *const XYBookAudioSnckReasonPlaybackStateChanged = @"playback_state_changed";
static NSString *const XYBookAudioSnckReasonTimerSet = @"timer_set";
static NSString *const XYBookAudioSnckReasonItemCompleted = @"item_completed";
static NSString *const XYBookAudioSnckReasonQueueEnded = @"queue_ended";
static NSString *const XYBookAudioSnckReasonTimerExpired = @"timer_expired";
static NSString *const XYBookAudioSnckReasonProgress = @"progress";
static NSString *const XYBookAudioSnckReasonPageResumed = @"page_resumed";
static NSString *const XYBookAudioSnckReasonPlaybackFailed = @"playback_failed";

static NSString *XYBookAudioSnckTimerReason(XYBookAudioTimerChange change) {
    switch (change) {
        case XYBookAudioTimerChangeSet:
            return XYBookAudioSnckReasonTimerSet;
        case XYBookAudioTimerChangeItemCompleted:
            return XYBookAudioSnckReasonItemCompleted;
        case XYBookAudioTimerChangeQueueEnded:
            return XYBookAudioSnckReasonQueueEnded;
        case XYBookAudioTimerChangeExpired:
            return XYBookAudioSnckReasonTimerExpired;
    }
}

static NSArray<NSString *> *XYBookAudioLegacyUIActions(void) {
    return @[
        XYBookAudioActionOpenWindow, XYBookAudioActionCloseWindow, XYBookAudioActionGoLogin,
        XYBookAudioActionShowShareMenu
    ];
}

static BOOL XYBookAudioIsHostInfoAction(NSString *action) {
    return [action isEqual:XYBookAudioActionGetUserInfo] || [action isEqual:XYBookAudioActionGetSystemInfo] ||
           [action isEqual:@"xhSnckGetUserInfo"];
}

static SEL XYBookAudioH5Selector(id action) {
    if (!XYBookAudioIsNonEmptyString(action) || [action containsString:@":"]) {
        return NULL;
    }
    if (![action hasPrefix:XYBookAudioSnckMethodPrefix] && ![action isEqual:XYBookAudioActionCanIUse] &&
        !XYBookAudioIsHostInfoAction(action) && ![XYBookAudioLegacyUIActions() containsObject:action]) {
        return NULL;
    }
    return NSSelectorFromString([action stringByAppendingString:@":"]);
}

@interface XYBookAudioWebBridge ()
@property (nonatomic, strong) XYBookAudioLogger *logger;
@property (nonatomic, weak) XYBookAudioSDKManager *SDK;
@property (nonatomic, weak) XYBookAudioBridgeWebView *webView;
@property (nonatomic, strong) XYBookAudioConfiguration *configuration;
@property (nonatomic, strong) NSUUID *snckSubscription;
@property (nonatomic, copy) NSDictionary *lastSnckPlayback;
@property (nonatomic) NSTimeInterval lastSnckProgress;
@property (nonatomic) NSUInteger generation;
@property (nonatomic) BOOL active;

/// 只向当前可信文档发送回调，页面代次改变后自动丢弃旧结果。
- (void)send:(NSString *)action parameters:(NSDictionary *)parameters generation:(NSUInteger)generation;
/// 无法解析的消息没有可用的回调标识，只记录诊断。
- (void)reportInvalidRequest:(NSString *)message;
@end

@implementation XYBookAudioWebBridge

/// 能力查询和分发共用 H5 同名方法的查找规则。
+ (BOOL)supportsAction:(NSString *)action {
    SEL selector = XYBookAudioH5Selector(action);
    return selector && [self instancesRespondToSelector:selector];
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

/// 与原项目一致按 actionName 查找同名方法并调用，SNCK 入口直接使用同名方法。
- (void)handleJSCallNative:(NSString *)object {
    // 长度限制针对解码后的业务 JSON，不能因中文、百分号的传输编码而误拒绝合法消息。
    if (object.length > XYBookAudioSnckMaximumMessageLength) {
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
    id callback = request[XYBookAudioKeyCallbackActionName];
    if (callback && !XYBookAudioIsNonEmptyString(callback)) {
        NSString *errorMessage = @"callbackActionName must be a nonempty string when provided.";
        if (XYBookAudioIsHostInfoAction(action)) {
            [self answerRequest:request result:nil error:XYBookAudioError(XYBookAudioInvalidArgument, errorMessage)
                     generation:self.generation];
        } else {
            [self reportInvalidRequest:errorMessage];
        }
        return;
    }
    SEL selector = XYBookAudioH5Selector(action);
    NSMethodSignature *signature = selector ? [self methodSignatureForSelector:selector] : nil;
    if (!signature) {
        NSError *error = XYBookAudioIsNonEmptyString(action) ? XYBookAudioMakeSnckError(-3, @"Unsupported SNCK action.")
                                                             : XYBookAudioMakeSnckError(-2, @"actionName is required.");
        [self send:callback parameters:XYBookAudioMakeSnckErrorPayload(error) generation:self.generation];
        return;
    }
    id parameters = request[XYBookAudioKeyParameters];
    if (parameters && ![parameters isKindOfClass:NSDictionary.class]) {
        NSString *errorMessage = @"parameters must be an object.";
        if ([XYBookAudioLegacyUIActions() containsObject:action]) {
            [self.logger error:XYBookAudioError(XYBookAudioInvalidArgument, errorMessage)
                     component:XYBookAudioLogBridge
                     operation:action];
        } else {
            NSError *error = XYBookAudioIsHostInfoAction(action)
                                 ? XYBookAudioError(XYBookAudioInvalidArgument, errorMessage)
                                 : XYBookAudioMakeSnckError(-2, errorMessage);
            [self answerRequest:request result:nil error:error generation:self.generation];
        }
        return;
    }
    if (!self.SDK) {
        NSString *errorMessage = @"The SDK is unavailable.";
        NSError *error = XYBookAudioIsHostInfoAction(action) ? XYBookAudioError(XYBookAudioDisposed, errorMessage)
                                                             : XYBookAudioMakeSnckError(4102, errorMessage);
        [self answerRequest:request result:nil error:error generation:self.generation];
        return;
    }
    // 无业务参数的方法允许省略 parameters；需要字段的方法继续由各自业务能力校验。
    if (!parameters) {
        NSMutableDictionary *normalizedRequest = [request mutableCopy];
        normalizedRequest[XYBookAudioKeyParameters] = @{};
        request = normalizedRequest;
    }
    NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:signature];
    invocation.target = self;
    invocation.selector = selector;
    [invocation setArgument:&request atIndex:2];
    [invocation invoke];
}

#pragma mark - 原有 H5 交互

- (void)xhCloseWindow:(NSDictionary *)request {
    if (![self hasWindowContextForAction:XYBookAudioActionCloseWindow]) {
        return;
    }
    NSError *error = [self.windowRouter closeWindowFromPage:self.page beforeClose:nil];
    [self logWindowError:error action:XYBookAudioActionCloseWindow];
}

- (void)xhOpenWindow:(NSDictionary *)request {
    id address = request[XYBookAudioKeyParameters][XYBookAudioKeyURL];
    NSURL *URL = XYBookAudioIsNonEmptyString(address) ? [NSURL URLWithString:address] : nil;
    if (!URL.scheme.length) {
        [self logWindowError:XYBookAudioError(XYBookAudioInvalidArgument,
                                              @"xhOpenWindow requires an absolute parameters.url.")
                      action:XYBookAudioActionOpenWindow];
        return;
    }
    if (![self hasWindowContextForAction:XYBookAudioActionOpenWindow]) {
        return;
    }
    NSError *error = [self.windowRouter openWindowWithURL:URL title:nil fromPage:self.page];
    [self logWindowError:error action:XYBookAudioActionOpenWindow];
}

- (void)xhGoLogin:(NSDictionary *)request {
    UIViewController *page = self.page;
    UINavigationController *navigation = page.navigationController;
    if (!page.viewIfLoaded.window || page != navigation.topViewController || navigation.transitionCoordinator ||
        navigation.isBeingDismissed || navigation.presentedViewController || page.presentedViewController) {
        [self logWindowError:XYBookAudioError(XYBookAudioBusy, @"The current page is unavailable for login.")
                      action:XYBookAudioActionGoLogin];
        return;
    }
    XYBookAudioLogger *logger = self.logger;
    [self.SDK requestHostLoginFromViewController:page completion:^(NSDictionary *result, NSError *error) {
        if (error) {
            [logger error:error component:XYBookAudioLogBridge operation:XYBookAudioActionGoLogin];
        } else if ([result[XYBookAudioKeyStatus] isEqual:XYBookAudioValueFailed]) {
            [logger write:XYBookAudioLogLevelWarning component:XYBookAudioLogBridge
                  message:@"xhGoLogin failed at host."];
        }
    }];
}

- (void)xhCanIUse:(NSDictionary *)request {
    NSString *callback = request[XYBookAudioKeyCallbackActionName];
    if (!callback) {
        [self reportInvalidRequest:@"xhCanIUse requires callbackActionName."];
        return;
    }
    NSString *method = request[XYBookAudioKeyParameters][XYBookAudioKeyName];
    BOOL supported = [self.class supportsAction:method];
    [self send:callback parameters:@{XYBookAudioKeyData : @(supported ? 1 : 0)} generation:self.generation];
}

- (void)xhGetSystemInfo:(NSDictionary *)request {
    [self.SDK executeAction:XYBookAudioActionGetSystemInfo parameters:request[XYBookAudioKeyParameters]
                 completion:[self callbackForRequest:request]];
}

- (void)xhGetUserInfo:(NSDictionary *)request {
    NSDictionary *parameters = request[XYBookAudioKeyParameters];
    XYBookAudioCompletion reply = [self callbackForRequest:request];
    id goLogin = parameters[XYBookAudioKeyGoLogin];
    UIViewController *page = self.page;
    if ([goLogin isKindOfClass:NSNumber.class] && [goLogin boolValue] &&
        (!page || page != page.navigationController.topViewController)) {
        reply(nil, XYBookAudioError(XYBookAudioBusy, @"Login requires the current web page."));
        return;
    }
    [self.SDK executeAction:XYBookAudioActionGetUserInfo parameters:parameters completion:reply];
}

- (void)xhShowShareMenu:(NSDictionary *)request {
    UIViewController *page = self.page;
    if (!page || page != page.navigationController.topViewController) {
        [self logWindowError:XYBookAudioError(XYBookAudioBusy, @"Sharing requires the current web page.")
                      action:XYBookAudioActionShowShareMenu];
        return;
    }
    NSUInteger generation = self.generation;
    __weak typeof(self) weakSelf = self;
    [self.SDK executeAction:XYBookAudioActionShowShareMenu parameters:request[XYBookAudioKeyParameters]
                 completion:^(NSDictionary *result, NSError *error) {
                     if (error) {
                         [weakSelf logWindowError:error action:XYBookAudioActionShowShareMenu];
                     } else if ([result[XYBookAudioKeyStatus] isEqual:XYBookAudioValueAccepted]) {
                         [weakSelf send:request[XYBookAudioKeyCallbackActionName] parameters:@{} generation:generation];
                     } else if (![result[XYBookAudioKeyStatus] isEqual:XYBookAudioValueCancelled]) {
                         [weakSelf.logger write:XYBookAudioLogLevelWarning component:XYBookAudioLogBridge
                                        message:@"xhShowShareMenu was not accepted by the host."];
                     }
                 }];
}

- (BOOL)hasWindowContextForAction:(NSString *)action {
    if (!self.windowRouter || !self.page) {
        [self logWindowError:XYBookAudioError(XYBookAudioBusy, @"The web window is unavailable.") action:action];
        return NO;
    }
    return YES;
}

- (void)logWindowError:(NSError *)error action:(NSString *)action {
    if (error) {
        [self.logger error:error component:XYBookAudioLogBridge operation:action];
    }
}

#pragma mark - SNCK v1

/// Ready 返回当前快照，能力列表来自实际支持的 H5 方法。
- (void)xhSnckReady:(NSDictionary *)request {
    XYBookAudioSDKManager *SDK = self.SDK;
    self.lastSnckPlayback = [SDK snckPlayback];
    XYBookAudioCompletion reply = [self callbackForRequest:request];
    reply(@{
        @"protocolVersion" : @1,
        @"capabilities" : self.class.supportedActions,
        @"userState" : [SDK snckUserState],
        @"playback" : self.lastSnckPlayback
    },
          nil);
    if (!self.snckSubscription) {
        NSUInteger generation = self.generation;
        __weak typeof(self) weakSelf = self;
        self.snckSubscription = [SDK subscribe:^(NSString *event, NSDictionary *payload) {
            [weakSelf forwardSnckEvent:event payload:payload generation:generation];
        }];
        [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(applicationDidBecomeActive:)
                                                   name:UIApplicationDidBecomeActiveNotification
                                                 object:nil];
    }
}

- (void)xhSnckGetUserInfo:(NSDictionary *)request {
    [self xhGetUserInfo:request];
}

- (void)xhSnckShare:(NSDictionary *)request {
    [self.SDK shareSnck:request[XYBookAudioKeyParameters] fromPage:self.page
             completion:[self callbackForRequest:request]];
}

- (void)xhSnckOpenPage:(NSDictionary *)request {
    XYBookAudioCompletion reply = [self callbackForRequest:request];
    NSDictionary *parameters = request[XYBookAudioKeyParameters];
    NSURL *URL = XYBookAudioParseSnckURL(parameters[@"url"]);
    id title = parameters[@"title"];
    if (!URL || (title && ![title isKindOfClass:NSString.class])) {
        reply(nil, XYBookAudioMakeSnckError(4101, @"OpenPage requires a valid HTTP(S) URL and an optional title."));
        return;
    }
    NSString *trimmedTitle = [title stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    id<XYBookAudioWindowRouting> router = self.windowRouter;
    NSError *error = router ? [router openWindowWithURL:URL title:trimmedTitle.length ? title : nil fromPage:self.page]
                            : XYBookAudioMakeSnckError(4106, @"The page was closed.");
    reply(nil, error);
}

/// 复用窗口关闭流程，在文档失效前交付 SNCK 成功回包。
- (void)xhSnckClosePage:(NSDictionary *)request {
    XYBookAudioCompletion reply = [self callbackForRequest:request];
    id<XYBookAudioWindowRouting> router = self.windowRouter;
    if (!router) {
        reply(nil, XYBookAudioMakeSnckError(4106, @"The page was closed."));
        return;
    }
    NSError *error = [router closeWindowFromPage:self.page beforeClose:^{
        reply(nil, nil);
    }];
    if (error) {
        reply(nil, error);
    }
}

- (void)xhSnckAudioSetQueue:(NSDictionary *)request {
    [self forwardSnckAudio:XYBookAudioCommandSetQueue request:request];
}

- (void)xhSnckAudioGetQueue:(NSDictionary *)request {
    [self forwardSnckAudio:XYBookAudioCommandGetQueue request:request];
}

- (void)xhSnckAudioPlayAt:(NSDictionary *)request {
    [self forwardSnckAudio:XYBookAudioCommandPlayAt request:request];
}

- (void)xhSnckAudioSeekTo:(NSDictionary *)request {
    [self forwardSnckAudio:XYBookAudioCommandSeekTo request:request];
}

- (void)xhSnckAudioPrevious:(NSDictionary *)request {
    [self forwardSnckAudio:XYBookAudioCommandPrevious request:request];
}

- (void)xhSnckAudioNext:(NSDictionary *)request {
    [self forwardSnckAudio:XYBookAudioCommandNext request:request];
}

- (void)xhSnckAudioPlay:(NSDictionary *)request {
    [self forwardSnckAudio:XYBookAudioCommandPlay request:request];
}

- (void)xhSnckAudioPause:(NSDictionary *)request {
    [self forwardSnckAudio:XYBookAudioCommandPause request:request];
}

- (void)xhSnckAudioStop:(NSDictionary *)request {
    [self forwardSnckAudio:XYBookAudioCommandStop request:request];
}

- (void)xhSnckAudioGetState:(NSDictionary *)request {
    [self forwardSnckAudio:XYBookAudioCommandGetState request:request];
}

- (void)xhSnckAudioSetTimer:(NSDictionary *)request {
    [self forwardSnckAudio:XYBookAudioCommandSetTimer request:request];
}

- (void)xhSnckAudioGetTimer:(NSDictionary *)request {
    [self forwardSnckAudio:XYBookAudioCommandGetTimer request:request];
}

#pragma mark - SNCK 事件

- (BOOL)canSendSnckEvents {
    UIViewController *page = self.page;
    return self.SDK && self.snckSubscription && self.active && page.viewIfLoaded.window &&
           page.navigationController.topViewController == page && !page.presentedViewController &&
           UIApplication.sharedApplication.applicationState == UIApplicationStateActive;
}

- (void)sendSnckEvent:(NSString *)event payload:(NSDictionary *)payload reason:(NSString *)reason {
    NSMutableDictionary *parameters = [payload mutableCopy];
    parameters[@"version"] = @([self.SDK nextSnckEventVersion]);
    if (reason) {
        parameters[XYBookAudioKeyReason] = reason;
    }
    [self send:event parameters:parameters generation:self.generation];
}

- (void)pageDidAppear {
    if ([self canSendSnckEvents]) {
        self.lastSnckPlayback = [self.SDK snckPlayback];
        [self sendSnckEvent:XYBookAudioSnckEventUserChanged payload:[self.SDK snckUserState] reason:nil];
        [self sendSnckEvent:XYBookAudioSnckEventStateChanged payload:self.lastSnckPlayback
                     reason:XYBookAudioSnckReasonPageResumed];
    }
}

- (void)applicationDidBecomeActive:(NSNotification *)notification {
    [self pageDidAppear];
}

- (void)forwardSnckEvent:(NSString *)event payload:(NSDictionary *)payload generation:(NSUInteger)generation {
    if (generation != self.generation || ![self canSendSnckEvents]) {
        return;
    }
    if ([event isEqual:XYBookAudioEventUserIdentityChanged]) {
        [self sendSnckEvent:XYBookAudioSnckEventUserChanged payload:[self.SDK snckUserState] reason:nil];
        return;
    }
    NSDictionary *playback = [self.SDK snckPlayback];
    if ([event isEqual:XYBookAudioEventError] && [payload[XYBookAudioKeyCode] isEqual:@"PLAYBACK_FAILED"]) {
        NSMutableDictionary *failure = [playback mutableCopy];
        failure[@"error"] =
            XYBookAudioMakeSnckErrorPayload(XYBookAudioMakeSnckError(4108, payload[XYBookAudioKeyMessage]));
        [self sendSnckEvent:XYBookAudioSnckEventAudioError payload:failure reason:XYBookAudioSnckReasonPlaybackFailed];
        return;
    }
    if (![event isEqual:XYBookAudioEventPlaybackChanged]) {
        return;
    }
    NSDictionary *previous = self.lastSnckPlayback;
    self.lastSnckPlayback = playback;
    BOOL queueChanged = ![previous[XYBookAudioKeyQueueVersion] isEqual:playback[XYBookAudioKeyQueueVersion]];
    BOOL itemChanged = ![previous[XYBookAudioKeyIndex] isEqual:playback[XYBookAudioKeyIndex]];
    BOOL stateChanged = ![previous[XYBookAudioKeyState] isEqual:playback[XYBookAudioKeyState]] ||
                        ![previous[XYBookAudioKeyPlayWhenReady] isEqual:playback[XYBookAudioKeyPlayWhenReady]];
    NSString *queueReason =
        [playback[XYBookAudioKeyItems] count] ? XYBookAudioSnckReasonQueueReplaced : XYBookAudioSnckReasonStopped;
    if (queueChanged) {
        [self sendSnckEvent:XYBookAudioSnckEventQueueChanged payload:playback reason:queueReason];
    }
    if (queueChanged || itemChanged || stateChanged) {
        NSString *reason =
            queueChanged ? queueReason
                         : (itemChanged ? XYBookAudioSnckReasonItemChanged : XYBookAudioSnckReasonPlaybackStateChanged);
        [self sendSnckEvent:XYBookAudioSnckEventStateChanged payload:playback reason:reason];
    }
    NSDictionary *oldTimer = previous[XYBookAudioKeyTimer], *timer = playback[XYBookAudioKeyTimer];
    if (![oldTimer[XYBookAudioKeyMode] isEqual:timer[XYBookAudioKeyMode]] ||
        ![oldTimer[XYBookAudioKeyRemainingCount] isEqual:timer[XYBookAudioKeyRemainingCount]] ||
        ![(oldTimer[XYBookAudioKeyDeadlineElapsedMs] ?: @0) isEqual:(timer[XYBookAudioKeyDeadlineElapsedMs] ?: @0)]) {
        NSString *reason = XYBookAudioSnckTimerReason([self.SDK snckTimerChange]);
        [self sendSnckEvent:XYBookAudioSnckEventTimerChanged payload:playback reason:reason];
    }
    NSTimeInterval now = NSProcessInfo.processInfo.systemUptime;
    if ([playback[XYBookAudioKeyPlaying] boolValue] && now - self.lastSnckProgress >= XYBookAudioProgressInterval) {
        self.lastSnckProgress = now;
        [self sendSnckEvent:XYBookAudioSnckEventProgress payload:playback reason:XYBookAudioSnckReasonProgress];
    }
}

#pragma mark - H5 回调

- (void)forwardSnckAudio:(NSString *)command request:(NSDictionary *)request {
    [self.SDK executeSnckAudio:command parameters:request[XYBookAudioKeyParameters]
                    completion:[self callbackForRequest:request]];
}

/// 异步结果只发回发起请求的文档。
- (XYBookAudioCompletion)callbackForRequest:(NSDictionary *)request {
    NSUInteger generation = self.generation;
    __weak typeof(self) weakSelf = self;
    return ^(NSDictionary *result, NSError *error) {
        [weakSelf answerRequest:request result:result error:error generation:generation];
    };
}

- (void)answerRequest:(NSDictionary *)request
               result:(NSDictionary *)result
                error:(NSError *)error
           generation:(NSUInteger)generation {
    NSString *action = request[XYBookAudioKeyActionName];
    if (error && XYBookAudioIsHostInfoAction(action)) {
        [self.logger error:error component:XYBookAudioLogBridge operation:action];
        NSDictionary *payload =
            @{XYBookAudioKeyCode : XYBookAudioErrorName(error), XYBookAudioKeyMessage : error.localizedDescription};
        [self send:XYBookAudioEventError parameters:payload generation:generation];
        return;
    }
    NSDictionary *parameters = error ? XYBookAudioMakeSnckErrorPayload(error) : result;
    [self send:request[XYBookAudioKeyCallbackActionName] parameters:parameters generation:generation];
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
    if (self.snckSubscription) {
        [self.SDK unsubscribe:self.snckSubscription];
        [NSNotificationCenter.defaultCenter removeObserver:self name:UIApplicationDidBecomeActiveNotification
                                                    object:nil];
    }
    self.snckSubscription = nil;
    self.lastSnckPlayback = nil;
    self.lastSnckProgress = 0;
}

- (void)reportInvalidRequest:(NSString *)message {
    [self.logger write:XYBookAudioLogLevelWarning component:XYBookAudioLogBridge message:message];
}

/// 在发送前再次验证文档代次；WebView 负责结构化回调，管理类只负责决定回调是否仍有效。
- (void)send:(NSString *)action parameters:(NSDictionary *)parameters generation:(NSUInteger)generation {
    if (!XYBookAudioIsNonEmptyString(action) || !self.active || generation != self.generation ||
        ![self.configuration allowsURL:self.webView.URL]) {
        return;
    }
    NSDictionary *message = parameters ? @{XYBookAudioKeyActionName : action, XYBookAudioKeyParameters : parameters}
                                       : @{XYBookAudioKeyActionName : action};
    [self.webView nativeCallJS:message completion:^(NSError *error) {
        if (error && generation == self.generation && self.active) {
            [self.logger error:error component:XYBookAudioLogBridge operation:@"JS callback delivery"];
        }
    }];
}

- (void)dealloc {
    [self invalidate];
}

@end
