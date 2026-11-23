// 通过真实 H5 消息和宿主公开服务验证网页窗口栈；不访问 SDK 私有控制器或 Bridge 状态。
#import <XCTest/XCTest.h>
#import <WebKit/WebKit.h>
#import "../XYBookAudioSDKDemo/BookAudio/AppBookAudioService.h"
#import "../XYBookAudioSDKDemo/Account/AppAccountService.h"

@interface XYBookAudioWindowTests : XCTestCase <UINavigationControllerDelegate>
@property (nonatomic, strong) AppBookAudioService *service;
@property (nonatomic, strong) UIViewController *presenter;
@property (nonatomic, strong) NSURL *resources;
@property (nonatomic, strong) NSURL *entryURL;
@property (nonatomic, strong) NSURL *childURL;
@property (nonatomic, strong) NSMutableArray<NSString *> *bridgeWarnings;
@property (nonatomic, strong) UINavigationController *hostNavigation;
@end

@implementation XYBookAudioWindowTests

- (void)setUp {
    [super setUp];
    self.service = AppBookAudioService.sharedInstance;
    [self.service shutdown];
    [AppAccountService.sharedInstance logout];
    self.presenter = UIApplication.sharedApplication.delegate.window.rootViewController;
    NSURL *fixture = [[NSBundle bundleForClass:self.class] URLForResource:@"Fixture" withExtension:nil];
    self.resources = [[NSURL fileURLWithPath:NSTemporaryDirectory()
                                 isDirectory:YES] URLByAppendingPathComponent:NSUUID.UUID.UUIDString isDirectory:YES];
    NSError *error = nil;
    XCTAssertTrue([NSFileManager.defaultManager copyItemAtURL:fixture toURL:self.resources error:&error]);
    self.entryURL = [self.resources URLByAppendingPathComponent:@"index.html"];
    NSURL *nested = [self.resources URLByAppendingPathComponent:@"nested" isDirectory:YES];
    XCTAssertTrue([NSFileManager.defaultManager createDirectoryAtURL:nested withIntermediateDirectories:NO
                                                          attributes:nil
                                                               error:&error]);
    NSString *html = [NSString stringWithContentsOfURL:self.entryURL encoding:NSUTF8StringEncoding error:&error];
    html = [html stringByReplacingOccurrencesOfString:@"src=\"fixture.js\"" withString:@"src=\"../fixture.js\""];
    html = [html stringByReplacingOccurrencesOfString:@"href=\"style.css\"" withString:@"href=\"../style.css\""];
    self.childURL = [nested URLByAppendingPathComponent:@"index.html"];
    XCTAssertTrue([html writeToURL:self.childURL atomically:YES encoding:NSUTF8StringEncoding error:&error]);
    XYBookAudioConfiguration *configuration =
        [[XYBookAudioConfiguration alloc] initWithHostIdentifier:NSUUID.UUID.UUIDString entryURL:self.entryURL];
    self.bridgeWarnings = [NSMutableArray array];
    NSMutableArray *warnings = self.bridgeWarnings;
    configuration.logLevel = XYBookAudioLogLevelWarning;
    configuration.logHandler = ^(XYBookAudioLogLevel level, NSString *component, NSString *message) {
        if ([component isEqual:@"Bridge"]) {
            [warnings addObject:message];
        }
    };
    XCTAssertTrue([self.service configureWithConfiguration:configuration error:&error]);
    XCTAssertNil(error);
}

- (void)tearDown {
    [self.service shutdown];
    [self waitUntil:^BOOL {
        return self.presenter.presentedViewController == nil;
    }];
    if (self.hostNavigation) {
        UIApplication.sharedApplication.delegate.window.rootViewController = self.presenter;
    }
    NSError *error = nil;
    XCTAssertTrue([NSFileManager.defaultManager removeItemAtURL:self.resources error:&error]);
    XCTAssertNil(error);
    [super tearDown];
}

/// 仅等待可见导航状态，不依赖 SDK 内部类名。
- (void)waitUntil:(BOOL (^)(void))condition {
    XCTNSPredicateExpectation *expectation = [[XCTNSPredicateExpectation alloc]
        initWithPredicate:[NSPredicate predicateWithBlock:^BOOL(id object, NSDictionary *bindings) {
            return condition();
        }]
                   object:nil];
    XCTAssertEqual([XCTWaiter waitForExpectations:@[ expectation ] timeout:12], XCTWaiterResultCompleted);
}

- (UINavigationController *)navigation {
    return self.hostNavigation ?: (UINavigationController *)self.presenter.presentedViewController;
}

/// 通过 UIKit 视图树定位真实页面或账号按钮。
- (UIView *)findView:(UIView *)view matching:(BOOL (^)(UIView *))matches {
    if (matches(view)) {
        return view;
    }
    for (UIView *child in view.subviews) {
        UIView *found = [self findView:child matching:matches];
        if (found) {
            return found;
        }
    }
    return nil;
}

- (id)script:(NSString *)script web:(WKWebView *)web {
    XCTestExpectation *done = [self expectationWithDescription:@"网页脚本完成"];
    __block id output;
    [web callAsyncJavaScript:script arguments:@{} inFrame:nil inContentWorld:WKContentWorld.pageWorld
           completionHandler:^(id result, NSError *error) {
               XCTAssertNil(error);
               output = result;
               [done fulfill];
           }];
    [self waitForExpectations:@[ done ] timeout:8];
    return output;
}

/// 关闭页面后的 JS 回执可能随文档销毁，以实际导航状态验证关闭结果。
- (void)post:(NSDictionary *)request web:(WKWebView *)web {
    NSError *error = nil;
    NSData *data = [NSJSONSerialization dataWithJSONObject:request options:0 error:&error];
    XCTAssertNil(error);
    NSString *message = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    [web callAsyncJavaScript:@"window.xhAppJSBridge.JSCallNative(message);" arguments:@{@"message" : message}
                     inFrame:nil
              inContentWorld:WKContentWorld.pageWorld
           completionHandler:nil];
}

- (WKWebView *)pageAtDepth:(NSUInteger)depth {
    [self waitUntil:^BOOL {
        return self.navigation.viewControllers.count == depth && !self.navigation.transitionCoordinator;
    }];
    WKWebView *web = [self currentWebView];
    XCTAssertNotNil(web);
    [self waitUntil:^BOOL {
        return !web.loading && [web.title isEqualToString:@"听书集成验证"];
    }];
    XCTAssertEqualObjects([self script:@"return typeof call;" web:web], @"function");
    return web;
}

- (WKWebView *)currentWebView {
    return (WKWebView *)[self findView:self.navigation.topViewController.view matching:^BOOL(UIView *view) {
        return [view isKindOfClass:WKWebView.class];
    }];
}

- (void)assertWebViewFillsPageVertically:(WKWebView *)web {
    UIView *page = self.navigation.topViewController.view;
    CGRect frame = [web convertRect:web.bounds toView:page];
    XCTAssertEqualWithAccuracy(CGRectGetMinY(frame), CGRectGetMinY(page.bounds), 0.5);
    XCTAssertEqualWithAccuracy(CGRectGetMaxY(frame), CGRectGetMaxY(page.bounds), 0.5);
    XCTAssertEqualWithAccuracy(web.scrollView.adjustedContentInset.top, 0, 0.5);
    XCTAssertEqualWithAccuracy(web.scrollView.adjustedContentInset.bottom, 0, 0.5);
}

- (WKWebView *)openRoot {
    XCTestExpectation *opened = [self expectationWithDescription:@"打开听书首页"];
    [self.service openFromViewController:self.presenter style:XYBookAudioOpenStylePresent completion:^(NSError *error) {
        XCTAssertNil(error);
        [opened fulfill];
    }];
    [self waitForExpectations:@[ opened ] timeout:5];
    return [self pageAtDepth:1];
}

- (void)installSnckBridgeInWeb:(WKWebView *)web {
    [self
        script:
            @"const previous = window.xhWebJSBridge.nativeCallJS;"
             "let id = 0; const pending = new Map(); window.snckEvents = [];"
             "window.xhWebJSBridge.nativeCallJS = message => {"
             "  if (pending.has(message.actionName)) {"
             "    const resolve = pending.get(message.actionName); pending.delete(message.actionName); resolve(message);"
             "  } else if (message.actionName.startsWith('snck')) { snckEvents.push(message); }"
             "  else { previous(message); }"
             "};"
             "window.snckCall = (actionName, parameters = {}) => new Promise(resolve => {"
             "  const callbackActionName = 'snck_cb_' + (++id); pending.set(callbackActionName, resolve);"
             "  window.xhAppJSBridge.JSCallNative(JSON.stringify({actionName, callbackActionName, parameters}));"
             "}); return true;"
           web:web];
}

- (void)testSnckReadyQueueTimerAndStopUseProtocolV1 {
    WKWebView *web = [self openRoot];
    [self installSnckBridgeInWeb:web];
    NSDictionary *result =
        [self script:@"const call = async (name, params) => (await snckCall('xhSnck' + name, params)).parameters;"
                      "const items = [{id:'a',title:'First',url:'https://example.invalid/a.mp3',extra:'ignored'},"
                      "               {id:'b',title:'Second',url:'https://example.invalid/b.mp3',author:'Author'}];"
                      "const queued = await call('AudioSetQueue',{items,startIndex:1});"
                      "const ready = await call('Ready');"
                      "const queue = await call('AudioGetQueue');"
                      "const seek = await call('AudioSeekTo',{positionMs:2500});"
                      "const invalid = await call('AudioSetQueue',{items:[items[0],items[0]]});"
                      "const wrongIndex = await call('AudioPlayAt',{index:true});"
                      "const timer = await call('AudioSetTimer',{mode:'AFTER_ITEMS',count:2});"
                      "const duration = await call('AudioSetTimer',{mode:'AFTER_DURATION',durationMs:900000});"
                      "const timerQuery = await call('AudioGetTimer');"
                      "const stopped = await call('AudioStop');"
                      "const emptyPlay = await call('AudioPlay');"
                      "const unknown = await call('AudioUnknown');"
                      "return {ready,queue,queued,seek,invalid,wrongIndex,timer,duration,timerQuery,"
                      "        stopped,emptyPlay,unknown,events:snckEvents.map(event=>event.actionName)};"
                 web:web];
    XCTAssertEqualObjects(result[@"ready"][@"protocolVersion"], @1);
    NSArray *capabilities = result[@"ready"][@"capabilities"];
    NSPredicate *snckAction = [NSPredicate predicateWithFormat:@"SELF BEGINSWITH 'xhSnck'"];
    XCTAssertEqual([capabilities filteredArrayUsingPredicate:snckAction].count, 17u);
    XCTAssertEqualObjects(result[@"ready"][@"userState"][@"user"], NSNull.null);
    XCTAssertEqualObjects(result[@"ready"][@"playback"][@"queueVersion"], result[@"queued"][@"queueVersion"]);
    XCTAssertEqualObjects(result[@"ready"][@"playback"][@"item"], result[@"queued"][@"item"]);
    XCTAssertEqualObjects(result[@"queue"][@"queueVersion"], result[@"queued"][@"queueVersion"]);
    XCTAssertNil(result[@"queue"][@"items"][0][@"extra"]);
    XCTAssertEqualObjects(result[@"queued"][@"item"][@"id"], @"b");
    XCTAssertEqualObjects(result[@"queued"][@"state"], @"PAUSED");
    XCTAssertEqualObjects(result[@"seek"][@"positionMs"], @2500);
    XCTAssertEqualObjects(result[@"invalid"][@"code"], @4101);
    XCTAssertEqualObjects(result[@"wrongIndex"][@"code"], @4101);
    XCTAssertEqualObjects(result[@"timer"][@"timer"][@"remainingCount"], @2);
    XCTAssertEqualObjects(result[@"duration"][@"timer"][@"mode"], @"AFTER_DURATION");
    XCTAssertGreaterThan([result[@"timerQuery"][@"remainingMs"] longLongValue], 0);
    XCTAssertEqualObjects(result[@"stopped"][@"items"], @[]);
    XCTAssertEqualObjects(result[@"stopped"][@"state"], @"IDLE");
    XCTAssertEqualObjects(result[@"stopped"][@"index"], @(-1));
    XCTAssertEqualObjects(result[@"stopped"][@"timer"][@"mode"], @"OFF");
    XCTAssertEqualObjects(result[@"emptyPlay"][@"code"], @4101);
    XCTAssertEqualObjects(result[@"unknown"][@"code"], @(-3));
    XCTAssertTrue([result[@"events"] containsObject:@"snckAudioQueueChanged"]);
    XCTAssertTrue([result[@"events"] containsObject:@"snckAudioStateChanged"]);
    XCTAssertTrue([result[@"events"] containsObject:@"snckAudioTimerChanged"]);
}

- (void)testSnckTimerSetAfterExpirationReportsNewChange {
    WKWebView *web = [self openRoot];
    [self installSnckBridgeInWeb:web];
    [self script:@"await snckCall('xhSnckReady');"
                  "await snckCall('xhSnckAudioSetQueue',{items:[{id:'a',title:'A',url:'https://example.invalid/a.mp3'}]});"
                  "await snckCall('xhSnckAudioSetTimer',{mode:'AFTER_DURATION',durationMs:250});"
                  "return true;"
             web:web];
    [self waitForScript:@"snckEvents.some(e=>e.actionName==='snckAudioTimerChanged' && "
                         "e.parameters.reason==='timer_expired' && e.parameters.timer.mode==='OFF')"
                    web:web];
    NSDictionary *timer =
        [self script:@"const result=await snckCall('xhSnckAudioSetTimer',{mode:'AFTER_ITEMS',count:2});"
                      "return result.parameters.timer;"
                 web:web];
    XCTAssertEqualObjects(timer[@"remainingCount"], @2);
    [self waitForScript:@"snckEvents.some(e=>e.actionName==='snckAudioTimerChanged' && "
                         "e.parameters.timer.mode==='AFTER_ITEMS')"
                    web:web];
    NSString *reason =
        [self script:@"return snckEvents.find(e=>e.actionName==='snckAudioTimerChanged' && "
                      "e.parameters.timer.mode==='AFTER_ITEMS').parameters.reason;"
                 web:web];
    XCTAssertEqualObjects(reason, @"timer_set");
}

- (void)testSnckUsesHostAccountAndShareAndClosesCurrentPage {
    WKWebView *web = [self openRoot];
    [self installSnckBridgeInWeb:web];
    [self script:@"await snckCall('xhSnckReady'); return true;" web:web];
    [AppAccountService.sharedInstance updateAuthenticatedUserId:@"snck-user"];
    [self waitForScript:
              @"snckEvents.some(event=>event.actionName==='snckUserChanged' && event.parameters.user?.id==='snck-user')"
                    web:web];
    NSDictionary *user = [self script:@"return (await snckCall('xhSnckGetUserInfo')).parameters;" web:web];
    XCTAssertEqualObjects(user[@"initialization"], @"AUTHENTICATED");
    XCTAssertEqualObjects(user[@"user"][@"id"], @"snck-user");
    NSDictionary *invalid =
        [self script:@"return (await snckCall('xhSnckOpenPage',{url:'file:///etc/hosts'})).parameters;" web:web];
    XCTAssertEqualObjects(invalid[@"code"], @4101);
    [self
        script:@"window.shareReply = null;"
                "snckCall('xhSnckShare',{title:'Book',link:'https://example.com/book'}).then(reply=>shareReply=reply);"
                "return true;"
           web:web];
    UIViewController *page = self.navigation.topViewController;
    [self waitUntil:^BOOL {
        return [page.presentedViewController isKindOfClass:UIActivityViewController.class] &&
               !page.presentedViewController.transitionCoordinator;
    }];
    UIActivityViewController *share = (UIActivityViewController *)page.presentedViewController;
    share.completionWithItemsHandler(nil, NO, nil, nil);
    XCTestExpectation *closed = [self expectationWithDescription:@"share closed"];
    [share dismissViewControllerAnimated:NO completion:^{
        [closed fulfill];
    }];
    [self waitForExpectations:@[ closed ] timeout:3];
    [self waitForScript:@"Boolean(shareReply)" web:web];
    NSDictionary *reply = [self script:@"return shareReply.parameters;" web:web];
    XCTAssertEqualObjects(reply[@"status"], @"CANCELLED");
    XCTAssertNotNil([[NSUUID alloc] initWithUUIDString:reply[@"requestId"]]);
    [self post:@{@"actionName" : @"xhSnckClosePage", @"callbackActionName" : @"snck_cb_close"} web:web];
    [self waitUntil:^BOOL {
        return self.presenter.presentedViewController == nil;
    }];
}

/// 等待 H5 接收器真正收到事件，避免原生发送与 JS 执行的时序影响断言。
- (void)waitForScript:(NSString *)script web:(WKWebView *)web {
    __block BOOL ready = NO;
    [self waitUntil:^BOOL {
        [web evaluateJavaScript:script completionHandler:^(id result, NSError *error) {
            ready = error == nil && [result boolValue];
        }];
        return ready;
    }];
}

/// 旧版 H5 入口支持当前夹具的可信本地地址。
- (void)openFixturePage:(NSURL *)URL {
    [self post:@{@"actionName" : @"xhOpenWindow", @"parameters" : @{@"url" : URL.absoluteString}}
           web:[self currentWebView]];
}

- (void)testNestedWindowsCloseIndividuallyAndPreserveQueue {
    WKWebView *root = [self openRoot];
    XCTAssertTrue(self.navigation.isNavigationBarHidden);
    [self assertWebViewFillsPageVertically:root];
    [self script:@"await loadQueue('https://example.invalid/fixture.mp3'); window.parentMarker = 'kept'; return true;"
             web:root];
    [self openFixturePage:self.childURL];
    WKWebView *child = [self pageAtDepth:2];
    XCTAssertTrue(self.navigation.isNavigationBarHidden);
    [self assertWebViewFillsPageVertically:child];
    XCTAssertNotEqual(root, child);
    XCTAssertEqualObjects(child.URL.URLByResolvingSymlinksInPath, self.childURL.URLByResolvingSymlinksInPath);
    [self post:@{@"actionName" : @"xhGoLogin"} web:child];
    [self waitUntil:^BOOL {
        return self.navigation.viewControllers.count == 3 && !self.navigation.transitionCoordinator;
    }];
    XCTAssertFalse(self.navigation.isNavigationBarHidden);
    [self.navigation popViewControllerAnimated:NO];
    XCTAssertEqual([self pageAtDepth:2], child);
    XCTAssertTrue(self.navigation.isNavigationBarHidden);
    [self openFixturePage:self.entryURL];
    WKWebView *grandchild = [self pageAtDepth:3];
    XCTAssertEqualObjects([self script:@"return (await call('xhSnckAudioGetState')).item.id;" web:grandchild],
                          @"fixture");
    [self post:@{@"actionName" : @"xhSnckClosePage"} web:grandchild];
    XCTAssertEqual([self pageAtDepth:2], child);
    XCTAssertTrue(self.navigation.isNavigationBarHidden);
    [self post:@{@"actionName" : @"xhSnckClosePage"} web:child];
    XCTAssertEqual([self pageAtDepth:1], root);
    XCTAssertTrue(self.navigation.isNavigationBarHidden);
    XCTAssertEqualObjects([self script:@"return window.parentMarker;" web:root], @"kept");
    [self post:@{@"actionName" : @"xhSnckClosePage"} web:root];
    [self waitUntil:^BOOL {
        return self.presenter.presentedViewController == nil;
    }];
    WKWebView *reopened = [self openRoot];
    XCTAssertEqualObjects([self script:@"return (await call('xhSnckAudioGetState')).item.id;" web:reopened],
                          @"fixture");
}

- (void)testInvalidAndUntrustedWindowRequestsReturnNumericErrors {
    WKWebView *root = [self openRoot];
    NSDictionary *result = [self
        script:@"const codes = [];"
                "for (const url of [7, 'index.html', 'javascript:alert(1)', location.href, 'https://example.com/']) {"
                "  try { await call('xhSnckOpenPage', {url}); } catch (error) { codes.push(error.code); }"
                "}"
                "try { await call('xhSnckClosePage', 7); } catch (error) { codes.push(error.code); }"
                "return {codes, state:(await call('xhSnckAudioGetState')).state};"
           web:root];
    XCTAssertEqualObjects(result[@"codes"], (@[ @4101, @4101, @4101, @4101, @4103, @(-2) ]));
    XCTAssertEqualObjects(result[@"state"], @"IDLE");
    XCTAssertEqual(self.navigation.viewControllers.count, 1u);
}

- (void)testUndocumentedAndInternalActionsAreRejected {
    WKWebView *root = [self openRoot];
    NSDictionary *result = [self
        script:@"const actions = ['xhInitClientFont', 'xhGetClientSign',"
                "  'xhBookAudioGetSnapshot', 'xhBookAudioSubscribe', 'xhBookAudioPlay', 'xhSnckReady:',"
                "  'xhCanIUse:', 'xhGetUserInfo:', 'invalidate', 'setPage'];"
                "const codes = {};"
                "for (const action of actions) {"
                "  try { await call(action); } catch (error) { codes[action] = error.code; }"
                "}"
                "return {actions, codes, capabilities:(await call('xhSnckReady')).capabilities};"
           web:root];
    XCTAssertEqual([result[@"capabilities"] count], 24u);
    for (NSString *action in result[@"actions"]) {
        XCTAssertEqualObjects(result[@"codes"][action], @(-3), @"%@", action);
        XCTAssertFalse([result[@"capabilities"] containsObject:action]);
    }
    XCTAssertEqual(self.navigation.viewControllers.count, 1u);
}

- (void)testLegacyWindowLoginAndCapabilityActions {
    WKWebView *root = [self openRoot];
    NSDictionary *result = [self
        script:@"const actions = ['xhOpenWindow', 'xhCloseWindow', 'xhGoLogin', 'xhCanIUse', 'xhShowShareMenu',"
                "  'xhGetUserInfo', 'xhGetSystemInfo'];"
                "const names = [...actions, 'xhSnckReady', 'xhGetClientSign', 'xhCanIUse:', 'setPage'];"
                "const checks = await Promise.all(names.map(name => call('xhCanIUse', {name})));"
                "const {capabilities} = await call('xhSnckReady');"
                "return {checks, listed:actions.every(action => capabilities.includes(action))};"
           web:root];
    XCTAssertEqualObjects([result[@"checks"] valueForKey:@"data"], (@[ @1, @1, @1, @1, @1, @1, @1, @1, @0, @0, @0 ]));
    XCTAssertEqualObjects(result[@"listed"], @YES);
    [self post:@{@"actionName" : @"xhOpenWindow", @"parameters" : @{@"url" : self.childURL.absoluteString}} web:root];
    WKWebView *child = [self pageAtDepth:2];
    XCTAssertEqualObjects(child.URL.URLByResolvingSymlinksInPath, self.childURL.URLByResolvingSymlinksInPath);
    [self post:@{@"actionName" : @"xhGoLogin"} web:child];
    [self waitUntil:^BOOL {
        return self.navigation.viewControllers.count == 3 && !self.navigation.transitionCoordinator;
    }];
    [self.navigation popViewControllerAnimated:NO];
    XCTAssertEqual([self pageAtDepth:2], child);
    [self post:@{@"actionName" : @"xhCloseWindow"} web:child];
    XCTAssertEqual([self pageAtDepth:1], root);
}

- (void)testLegacyInfoReturnsRawHostDataAndTicketErrorEvent {
    WKWebView *web = [self openRoot];
    NSDictionary *guest =
        [self script:@"return await call('xhGetUserInfo', {goLogin:false, useTicket:false});" web:web];
    XCTAssertEqualObjects(guest, @{});
    NSDictionary *system = [self script:@"return await call('xhGetSystemInfo');" web:web];
    XCTAssertEqualObjects(system[@"device_token"], UIDevice.currentDevice.identifierForVendor.UUIDString);
    XCTAssertEqualObjects(system[@"system"], UIDevice.currentDevice.systemVersion);
    XCTAssertTrue([system[@"types"] length] > 0);
    XCTAssertEqualObjects(system[@"debug"], @1);
    NSBundle *bundle = NSBundle.mainBundle;
    XCTAssertEqualObjects(system[@"program_version"], [bundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"]
                                                          ?: [bundle objectForInfoDictionaryKey:@"CFBundleVersion"]);
    XCTAssertEqualObjects(system[@"program_name"], [bundle objectForInfoDictionaryKey:@"CFBundleDisplayName"]
                                                       ?: [bundle objectForInfoDictionaryKey:@"CFBundleName"]);
    UIWindow *window = web.window;
    NSString *statusBarHeight =
        [NSString stringWithFormat:@"%.f", window.windowScene.statusBarManager.statusBarFrame.size.height];
    NSString *bottomSafeHeight = [NSString stringWithFormat:@"%.f", window.safeAreaInsets.bottom];
    XCTAssertEqualObjects(system[@"appStatusBarHeight"], statusBarHeight);
    XCTAssertEqualObjects(system[@"bottomSafeHeight"], bottomSafeHeight);

    [AppAccountService.sharedInstance updateAuthenticatedUserId:@"profile-user"];
    NSDictionary *profile =
        [self script:@"return await call('xhGetUserInfo', {goLogin:false, useTicket:false});" web:web];
    XCTAssertEqualObjects(profile, (@{@"id" : @"profile-user", @"info" : @{@"id" : @"profile-user"}}));

    NSDictionary *failure = [self
        script:@"return await new Promise(resolve => {"
                "  const receive = window.xhWebJSBridge.nativeCallJS;"
                "  window.xhWebJSBridge.nativeCallJS = message => {"
                "    if (message.actionName === 'onBookAudioError') resolve(message.parameters);"
                "    else if (message.actionName === 'ticket-reply') resolve(null);"
                "    else receive(message);"
                "  };"
                "  window.xhAppJSBridge.JSCallNative(JSON.stringify({actionName:'xhGetUserInfo',"
                "    parameters:{useTicket:true}, callbackActionName:'ticket-reply'}));"
                "});"
           web:web];
    XCTAssertEqualObjects(failure[@"code"], @"UNSUPPORTED");
}

- (void)testLegacyShareOnlyRepliesWhenAccepted {
    WKWebView *web = [self openRoot];
    [self script:@"window.shareReplies = []; const receive = window.xhWebJSBridge.nativeCallJS;"
                  "window.xhWebJSBridge.nativeCallJS = message => {"
                  "  if (message.actionName === 'legacy-share') shareReplies.push(message.parameters);"
                  "  else receive(message);"
                  "}; return true;"
             web:web];
    UIViewController *page = self.navigation.topViewController;
    for (NSNumber *completed in @[ @NO, @YES ]) {
        [self post:@{
            @"actionName" : @"xhShowShareMenu",
            @"callbackActionName" : @"legacy-share",
            @"parameters" : @{@"title" : @"Book", @"link" : @"https://example.com/book", @"desc" : @"Description",
                              @"imgUrl" : @""}
        } web:web];
        [self waitUntil:^BOOL {
            return [page.presentedViewController isKindOfClass:UIActivityViewController.class] &&
                   !page.presentedViewController.transitionCoordinator;
        }];
        UIActivityViewController *share = (UIActivityViewController *)page.presentedViewController;
        share.completionWithItemsHandler(nil, completed.boolValue, nil, nil);
        [share dismissViewControllerAnimated:NO completion:nil];
        [self waitUntil:^BOOL {
            return page.presentedViewController == nil;
        }];
        if (completed.boolValue) {
            [self waitForScript:@"shareReplies.length === 1" web:web];
        }
        NSArray *expected = completed.boolValue ? @[ @{} ] : @[];
        XCTAssertEqualObjects([self script:@"return shareReplies;" web:web], expected);
    }
}

- (void)testHiddenParentCannotCloseChild {
    WKWebView *root = [self openRoot];
    [self openFixturePage:self.childURL];
    [self pageAtDepth:2];
    XCTAssertEqualObjects(
        [self script:@"try { await call('xhSnckClosePage'); } catch (error) { return error.code; }" web:root], @4104);
    XCTAssertEqual(self.navigation.viewControllers.count, 2u);
    [self.navigation popViewControllerAnimated:NO];
    XCTAssertEqual([self pageAtDepth:1], root);
    XCTAssertEqualObjects([self script:@"return (await call('xhSnckReady')).protocolVersion;" web:root], @1);
}

/// 通过网页实际读写验证同源窗口共享数据；关闭容器和重建 SDK 都不应清空网页持久数据。
- (void)testWindowsShareLocalStorageAcrossCloseAndReopen {
    NSString *storageKey = NSUUID.UUID.UUIDString;
    NSString *readStorage = [NSString stringWithFormat:@"return localStorage.getItem('%@');", storageKey];
    NSString *clearStorage = [NSString stringWithFormat:@"localStorage.removeItem('%@'); return true;", storageKey];
    WKWebView *root = [self openRoot];
    [self script:[NSString stringWithFormat:@"localStorage.setItem('%@','parent-session'); return true;", storageKey]
             web:root];
    XCTAssertEqualObjects([self script:readStorage web:root], @"parent-session");
    [self openFixturePage:self.entryURL];
    WKWebView *child = [self pageAtDepth:2];
    XCTAssertNotEqual(root, child);
    XCTAssertEqualObjects(root.URL, child.URL);
    XCTAssertEqualObjects([self script:readStorage web:child], @"parent-session");
    [self script:[NSString stringWithFormat:@"localStorage.setItem('%@','updated-session'); return true;", storageKey]
             web:child];
    [self post:@{@"actionName" : @"xhSnckClosePage"} web:child];
    XCTAssertEqual([self pageAtDepth:1], root);
    XCTAssertEqualObjects([self script:readStorage web:root], @"updated-session");
    [self post:@{@"actionName" : @"xhSnckClosePage"} web:root];
    [self waitUntil:^BOOL {
        return self.presenter.presentedViewController == nil;
    }];
    WKWebView *reopened = [self openRoot];
    XCTAssertEqualObjects([self script:readStorage web:reopened], @"updated-session");
    [self.service shutdown];
    [self waitUntil:^BOOL {
        return self.presenter.presentedViewController == nil;
    }];
    WKWebView *rebuilt = [self openRoot];
    XCTAssertEqualObjects([self script:readStorage web:rebuilt], @"updated-session");
    // 只移除本用例的随机键；保留其他测试或宿主网页的数据。
    for (WKWebView *web in @[ root, child, reopened, rebuilt ]) {
        [self script:clearStorage web:web];
    }
}

/// 本地 HTML 无法设置 HTTPS Cookie，因此从公开 Cookie 存储边界验证共享，不伪造网络响应。
- (void)assertCookie:(NSHTTPCookie *)expected availableInWebView:(WKWebView *)web {
    XCTestExpectation *read = [self expectationWithDescription:@"读取窗口 Cookie"];
    [web.configuration.websiteDataStore.httpCookieStore getAllCookies:^(NSArray<NSHTTPCookie *> *cookies) {
        NSPredicate *matchingCookie = [NSPredicate predicateWithFormat:@"name == %@ AND domain == %@ AND path == %@",
                                                                       expected.name, expected.domain, expected.path];
        NSArray<NSHTTPCookie *> *matches = [cookies filteredArrayUsingPredicate:matchingCookie];
        XCTAssertEqual(matches.count, 1u);
        XCTAssertEqualObjects(matches.firstObject.value, expected.value);
        [read fulfill];
    }];
    [self waitForExpectations:@[ read ] timeout:5];
}

/// 对齐参考浏览器：SDK 窗口可读取同一 App 默认网页存储中的 Cookie；不依赖某个进程池实例。
- (void)testWindowsShareCookiesWithHostDefaultDataStore {
    NSHTTPCookie *cookie = [NSHTTPCookie cookieWithProperties:@{
        NSHTTPCookieName : NSUUID.UUID.UUIDString,
        NSHTTPCookieValue : @"host-session",
        NSHTTPCookieDomain : @"book-audio.example.test",
        NSHTTPCookiePath : @"/",
        NSHTTPCookieSecure : @"TRUE",
        NSHTTPCookieExpires : [NSDate dateWithTimeIntervalSinceNow:3600]
    }];
    XCTAssertNotNil(cookie);
    WKHTTPCookieStore *hostStore = WKWebsiteDataStore.defaultDataStore.httpCookieStore;
    XCTestExpectation *created = [self expectationWithDescription:@"宿主写入 Cookie"];
    [hostStore setCookie:cookie completionHandler:^{
        [created fulfill];
    }];
    [self waitForExpectations:@[ created ] timeout:5];
    WKWebView *root = [self openRoot];
    [self assertCookie:cookie availableInWebView:root];
    [self openFixturePage:self.entryURL];
    [self assertCookie:cookie availableInWebView:[self pageAtDepth:2]];
    // 默认存储属于整个宿主 App，测试只能删除自己写入的 Cookie。
    XCTestExpectation *removed = [self expectationWithDescription:@"移除测试 Cookie"];
    [hostStore deleteCookie:cookie completionHandler:^{
        [removed fulfill];
    }];
    [self waitForExpectations:@[ removed ] timeout:5];
}

/// 从原项目的 EasyJS 线格式进入原生，验证两次 URI 解码和回调中的特殊字符不丢失。
- (void)testReferenceEasyJSFrameRoundTripsSpecialCharacters {
    WKWebView *web = [self openRoot];
    NSString *title = @"中文:100%:%3A:%25 + \"引号\" \\ 换行\n\u2028\u2029 🎧";
    XCTestExpectation *done = [self expectationWithDescription:@"EasyJS 编码消息往返"];
    NSString *script =
        @"const available=typeof window.EasyJS==='object' && typeof EasyJS.call==='function' && typeof EasyJS.inject==='function';"
         "const request=JSON.stringify({actionName:'xhSnckAudioSetQueue',parameters:{items:[{id:'chapter-1',title,url:'https://example.invalid/audio.mp3'}]},"
         "callbackActionName:'easyjs-roundtrip'});"
         "const frame='xhAppJSBridge:'+encodeURIComponent('JSCallNative:')+':'+encodeURIComponent(encodeURIComponent(request));"
         "const reply=await new Promise(resolve=>{const previous=window.xhWebJSBridge.nativeCallJS;"
         "window.xhWebJSBridge.nativeCallJS=message=>{"
         "if(message.actionName==='easyjs-roundtrip'){"
         "window.xhWebJSBridge.nativeCallJS=previous;resolve(message);}else{previous(message);}};"
         "window.webkit.messageHandlers.xhAppJSBridge.postMessage(frame);});"
         "return {available,reply};";
    [web callAsyncJavaScript:script arguments:@{@"title" : title} inFrame:nil inContentWorld:WKContentWorld.pageWorld
           completionHandler:^(NSDictionary *result, NSError *error) {
               XCTAssertNil(error);
               XCTAssertEqualObjects(result[@"available"], @YES);
               XCTAssertEqualObjects(result[@"reply"][@"actionName"], @"easyjs-roundtrip");
               XCTAssertEqualObjects(result[@"reply"][@"parameters"][@"item"][@"title"], title);
               [done fulfill];
           }];
    [self waitForExpectations:@[ done ] timeout:8];
}

- (void)testMalformedEasyJSFramesAreIgnoredAndValidRequestsStillWork {
    WKWebView *web = [self openRoot];
    NSUInteger warningCount = self.bridgeWarnings.count;
    NSDictionary *result = [self
        script:@"const request=JSON.stringify({actionName:'xhSnckAudioStop',callbackActionName:'unexpected-success'});"
                "const encoded=encodeURIComponent(encodeURIComponent(request));"
                "const prefix='xhAppJSBridge:'+encodeURIComponent('JSCallNative:')+':';"
                "const frames=[request, 'other:'+encodeURIComponent('JSCallNative:')+':'+encoded,"
                "  'xhAppJSBridge:'+encodeURIComponent('setJSCallNativeBlock:')+':'+encoded,"
                "  prefix+'%GG', prefix+encodeURIComponent('%GG'),"
                "  prefix+encodeURIComponent(encodeURIComponent(request)+':extra'), prefix+'x'.repeat(4*1024*1024)];"
                "const unexpected=[]; const receive=window.xhWebJSBridge.nativeCallJS;"
                "window.xhWebJSBridge.nativeCallJS=message=>{"
                "  if (message.actionName==='unexpected-success') unexpected.push(message);"
                "  receive(message);"
                "};"
                "frames.forEach(frame=>window.webkit.messageHandlers.xhAppJSBridge.postMessage(frame));"
                "return {unexpected, state:(await call('xhSnckAudioGetState')).state};"
           web:web];
    XCTAssertEqual(self.bridgeWarnings.count - warningCount, 7u);
    XCTAssertEqualObjects(result[@"unexpected"], @[]);
    XCTAssertEqualObjects(result[@"state"], @"IDLE");
}

- (void)testEasyJSLengthLimitAppliesToDecodedJSON {
    WKWebView *web = [self openRoot];
    NSUInteger warningCount = self.bridgeWarnings.count;
    NSDictionary *result = [self
        script:
            @"const title='书'.repeat(20000);"
             "const result=await call('xhSnckAudioSetQueue',{items:[{id:'unicode',title,url:'https://example.invalid/a.mp3'}]});"
             "window.xhAppJSBridge.JSCallNative(JSON.stringify({actionName:'xhSnckAudioStop',"
             "  parameters:{padding:'x'.repeat(80*1024)},callbackActionName:'oversized'}));"
             "const current=await call('xhSnckAudioGetState');"
             "return {titleLength:result.item.title.length, currentTitleLength:current.item.title.length};"
           web:web];
    XCTAssertEqualObjects(result[@"titleLength"], @20000);
    XCTAssertEqualObjects(result[@"currentTitleLength"], @20000);
    XCTAssertEqual(self.bridgeWarnings.count - warningCount, 1u);
}

- (void)testShutdownDismissesAllWindowsAndAllowsNewSession {
    [self openRoot];
    [self openFixturePage:self.childURL];
    [self pageAtDepth:2];
    [self.service shutdown];
    [self waitUntil:^BOOL {
        return self.presenter.presentedViewController == nil;
    }];
    XCTAssertNil([self.service playbackSnapshot]);
    [self openRoot];
}

- (UIViewController *)installHostNavigation {
    UIViewController *host = [UIViewController new];
    self.hostNavigation = [[UINavigationController alloc] initWithRootViewController:host];
    self.hostNavigation.delegate = self;
    UIApplication.sharedApplication.delegate.window.rootViewController = self.hostNavigation;
    [self waitUntil:^BOOL {
        return host.viewIfLoaded.window != nil;
    }];
    return host;
}

- (WKWebView *)openPushedRootFrom:(UIViewController *)host {
    XCTestExpectation *opened = [self expectationWithDescription:@"Push 打开听书首页"];
    [self.service openFromViewController:host style:XYBookAudioOpenStylePush completion:^(NSError *error) {
        XCTAssertNil(error);
        XCTAssertFalse(self.hostNavigation.viewControllers.lastObject == host);
        [opened fulfill];
    }];
    [self waitForExpectations:@[ opened ] timeout:5];
    return [self pageAtDepth:2];
}

- (void)testPushUsesHostStackAndAllowsReopenAfterClosing {
    UIViewController *host = [self installHostNavigation];
    XCTAssertFalse(self.hostNavigation.isNavigationBarHidden);
    WKWebView *root = [self openPushedRootFrom:host];
    XCTAssertTrue(self.hostNavigation.isNavigationBarHidden);
    [self assertWebViewFillsPageVertically:root];
    XCTAssertNil(host.presentedViewController);
    XCTAssertEqual(self.hostNavigation.delegate, self);
    [self script:@"await loadQueue('https://example.invalid/fixture.mp3'); return true;" web:root];
    [self openFixturePage:self.childURL];
    WKWebView *child = [self pageAtDepth:3];
    XCTAssertTrue(self.hostNavigation.isNavigationBarHidden);
    [self assertWebViewFillsPageVertically:child];
    [self post:@{@"actionName" : @"xhGoLogin"} web:child];
    [self waitUntil:^BOOL {
        return self.hostNavigation.viewControllers.count == 4 && !self.hostNavigation.transitionCoordinator;
    }];
    XCTAssertFalse(self.hostNavigation.isNavigationBarHidden);
    UIButton *button =
        (UIButton *)[self findView:self.hostNavigation.topViewController.view matching:^BOOL(UIView *view) {
            return [view isKindOfClass:UIButton.class] &&
                   [[(UIButton *)view titleForState:UIControlStateNormal] isEqual:@"登录测试账号"];
        }];
    XCTAssertNotNil(button);
    [button sendActionsForControlEvents:UIControlEventTouchUpInside];
    XCTAssertEqual([self pageAtDepth:3], child);
    XCTAssertTrue(self.hostNavigation.isNavigationBarHidden);
    XCTAssertGreaterThan(AppAccountService.sharedInstance.userId.length, 0u);
    [self post:@{@"actionName" : @"xhCloseWindow"} web:child];
    XCTAssertEqual([self pageAtDepth:2], root);
    XCTAssertTrue(self.hostNavigation.isNavigationBarHidden);
    XCTAssertEqualObjects([self script:@"return (await call('xhSnckAudioGetState')).items;" web:root], @[]);
    [self script:@"await loadQueue('https://example.invalid/fixture.mp3'); return true;" web:root];
    [self post:@{@"actionName" : @"xhSnckClosePage"} web:root];
    [self waitUntil:^BOOL {
        return self.hostNavigation.topViewController == host && !self.hostNavigation.transitionCoordinator;
    }];
    XCTAssertFalse(self.hostNavigation.isNavigationBarHidden);
    root = [self openPushedRootFrom:host];
    XCTAssertEqualObjects([self script:@"return (await call('xhSnckAudioGetState')).item.id;" web:root], @"fixture");
    [self.hostNavigation popViewControllerAnimated:NO];
    [self waitUntil:^BOOL {
        return self.hostNavigation.topViewController == host && !self.hostNavigation.transitionCoordinator;
    }];
    XCTAssertFalse(self.hostNavigation.isNavigationBarHidden);
    XCTestExpectation *presented = [self expectationWithDescription:@"返回后切换到 Present"];
    [self.service openFromViewController:host style:XYBookAudioOpenStylePresent completion:^(NSError *error) {
        XCTAssertNil(error);
        [presented fulfill];
    }];
    [self waitForExpectations:@[ presented ] timeout:5];
    XCTAssertTrue([host.presentedViewController isKindOfClass:UINavigationController.class]);
    UINavigationController *presentedNavigation = (UINavigationController *)host.presentedViewController;
    XCTAssertTrue(presentedNavigation.isNavigationBarHidden);
    XCTAssertFalse(self.hostNavigation.isNavigationBarHidden);
    XCTAssertEqualObjects(self.hostNavigation.viewControllers, (@[ host ]));
    [self.service shutdown];
    [self waitUntil:^BOOL {
        return host.presentedViewController == nil;
    }];
}

- (void)testPushDisposalPreservesHostControllersAndRejectsInvalidSource {
    XCTestExpectation *rejected = [self expectationWithDescription:@"没有导航栈时拒绝 Push"];
    [self.service openFromViewController:self.presenter style:XYBookAudioOpenStylePush completion:^(NSError *error) {
        XCTAssertEqualObjects(error.domain, XYBookAudioErrorDomain);
        XCTAssertEqual(error.code, XYBookAudioInvalidArgument);
        [rejected fulfill];
    }];
    [self waitForExpectations:@[ rejected ] timeout:5];

    UIViewController *host = [self installHostNavigation];
    self.hostNavigation.navigationBarHidden = YES;
    [self openPushedRootFrom:host];
    XCTAssertTrue(self.hostNavigation.navigationBarHidden);
    [self.service openFromViewController:host style:XYBookAudioOpenStylePresent completion:^(NSError *error) {
        XCTAssertEqual(error.code, XYBookAudioBusy);
    }];
    [self openFixturePage:self.childURL];
    [self pageAtDepth:3];
    UIViewController *otherHostPage = [UIViewController new];
    [self.hostNavigation pushViewController:otherHostPage animated:NO];
    [self.service shutdown];
    [self waitUntil:^BOOL {
        return self.hostNavigation.viewControllers.count == 2;
    }];
    XCTAssertEqualObjects(self.hostNavigation.viewControllers, (@[ host, otherHostPage ]));
    XCTAssertEqual(self.hostNavigation.delegate, self);
    XCTAssertTrue(self.hostNavigation.navigationBarHidden);
}

@end
