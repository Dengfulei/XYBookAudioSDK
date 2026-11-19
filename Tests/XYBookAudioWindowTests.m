// 通过真实 H5 消息和宿主公开服务验证网页窗口栈；不访问 SDK 私有控制器或 Bridge 状态。
#import <XCTest/XCTest.h>
#import <WebKit/WebKit.h>
#import "../XYBookAudioSDKDemo/BookAudio/AppBookAudioService.h"
#import "../XYBookAudioSDKDemo/Account/AppAccountService.h"
#import "../XYBookAudioSDK/Bridge/XYBookAudioWebBridge.h"

/// 仅链接到 XCTest 的同名方法，用于验证新增 H5 入口不需要额外登记；不编入分发 framework。
@interface XYBookAudioWebBridge (MethodDiscoveryTests)
- (void)xhTestEcho:(NSDictionary *)request;
@end

@implementation XYBookAudioWebBridge (MethodDiscoveryTests)

/// 复用真实系统资料链路，验证原版 JS SDK 能调用直接实现的新增方法。
- (void)xhTestEcho:(NSDictionary *)request {
    [self xhGetSystemInfo:request];
}

@end

@interface XYBookAudioWindowTests : XCTestCase
@property (nonatomic, strong) AppBookAudioService *service;
@property (nonatomic, strong) UIViewController *presenter;
@property (nonatomic, strong) NSURL *resources;
@property (nonatomic, strong) NSURL *entryURL;
@property (nonatomic, strong) NSURL *childURL;
@property (nonatomic, strong) NSMutableArray<NSString *> *errorLogs;
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
    self.errorLogs = [NSMutableArray array];
    NSMutableArray *logs = self.errorLogs;
    configuration.logLevel = XYBookAudioLogLevelError;
    configuration.logHandler = ^(XYBookAudioLogLevel level, NSString *component, NSString *message) {
        [logs addObject:message];
    };
    XCTAssertTrue([self.service configureWithConfiguration:configuration error:&error]);
    XCTAssertNil(error);
}

- (void)tearDown {
    [self.service shutdown];
    [self waitUntil:^BOOL {
        return self.presenter.presentedViewController == nil;
    }];
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
    return (UINavigationController *)self.presenter.presentedViewController;
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

/// 标准窗口接口无成功回调；发送后由导航栈或错误事件验证结果，不依赖网页关闭后的 JS 回执。
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
    WKWebView *web = (WKWebView *)[self findView:self.navigation.topViewController.view matching:^BOOL(UIView *view) {
        return [view isKindOfClass:WKWebView.class];
    }];
    XCTAssertNotNil(web);
    [self waitUntil:^BOOL {
        return !web.loading && [web.title isEqualToString:@"听书集成验证"];
    }];
    XCTAssertEqualObjects([self script:@"return typeof call;" web:web], @"function");
    return web;
}

- (WKWebView *)openRoot {
    XCTestExpectation *opened = [self expectationWithDescription:@"打开听书首页"];
    [self.service openFromViewController:self.presenter completion:^(NSError *error) {
        XCTAssertNil(error);
        [opened fulfill];
    }];
    [self waitForExpectations:@[ opened ] timeout:5];
    return [self pageAtDepth:1];
}

- (void)observeErrors:(WKWebView *)web {
    [self script:@"window.windowErrors=[]; const receive=window.xhWebJSBridge.nativeCallJS;"
                  "window.xhWebJSBridge.nativeCallJS=(message)=>{"
                  "if(message.actionName==='onBookAudioError'){window.windowErrors.push(message.parameters);}"
                  "receive(message);}; return true;"
             web:web];
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

/// 同时验证听书能力查询和标准 xhCanIUse 协议，窗口动作不能错误拼上 xhBookAudio 前缀。
- (void)assertWindowCapabilities:(WKWebView *)web {
    NSArray *actions = [self script:@"return (await call('xhBookAudioGetCapabilities')).actions;" web:web];
    XCTAssertTrue([actions containsObject:@"xhOpenWindow"]);
    XCTAssertTrue([actions containsObject:@"xhCloseWindow"]);
    id result = [self
        script:
            @"const receive = window.xhWebJSBridge.nativeCallJS;"
             "window.windowCapabilities=[];"
             "window.xhWebJSBridge.nativeCallJS=(message)=>{"
             "if(message.actionName==='onWindowCapability'){window.windowCapabilities.push(message.parameters.data);}"
             "else { receive(message); }};"
             "for(const name of ['xhOpenWindow','xhCloseWindow']){"
             "window.xhAppJSBridge.JSCallNative(JSON.stringify({actionName:'xhCanIUse',"
             "parameters:{name},callbackActionName:'onWindowCapability'}));} return true;"
           web:web];
    XCTAssertEqualObjects(result, @YES);
    [self waitForScript:@"window.windowCapabilities.length === 2" web:web];
    XCTAssertEqualObjects([self script:@"return window.windowCapabilities;" web:web], (@[ @1, @1 ]));
}

- (void)testNestedWindowsCloseIndividuallyAndPreservePlaybackAndParentDocument {
    WKWebView *root = [self openRoot];
    [self script:@"await loadQueue(false); await call('xhBookAudioSetRate',{rate:1.5}); await call('xhBookAudioPlay');"
                  "await call('xhBookAudioPause'); window.parentMarker='kept'; return true;"
             web:root];
    [self assertWindowCapabilities:root];
    [self post:@{@"actionName" : @"xhOpenWindow", @"parameters" : @{@"url" : self.childURL.absoluteString}} web:root];
    WKWebView *child = [self pageAtDepth:2];
    XCTAssertNotEqual(root, child);
    XCTAssertEqualObjects(child.URL.URLByResolvingSymlinksInPath, self.childURL.URLByResolvingSymlinksInPath);
    XCTAssertTrue([[self script:@"return navigator.userAgent;" web:child] hasSuffix:@" MediaConvergenceXinhua"]);
    // 子页必须保留最初的授权目录，不能因入口位于 nested 而失去打开同级页面的能力。
    [self post:@{@"actionName" : @"xhOpenWindow", @"parameters" : @{@"url" : self.entryURL.absoluteString}} web:child];
    WKWebView *grandchild = [self pageAtDepth:3];
    XCTAssertEqualObjects([self script:@"return (await call('xhBookAudioGetSnapshot')).rate;" web:grandchild], @1.5);
    [self post:@{@"actionName" : @"xhCloseWindow"} web:grandchild];
    XCTAssertEqual([self pageAtDepth:2], child);
    [self post:@{@"actionName" : @"xhCloseWindow", @"parameters" : @{}} web:child];
    XCTAssertEqual([self pageAtDepth:1], root);
    XCTAssertEqualObjects([self script:@"return window.parentMarker;" web:root], @"kept");
    [self post:@{@"actionName" : @"xhCloseWindow"} web:root];
    [self waitUntil:^BOOL {
        return self.presenter.presentedViewController == nil;
    }];
    XCTAssertEqualObjects([self.service getSnapshot][@"state"], @"paused");
    XCTAssertEqualObjects([self.service getSnapshot][@"bookId"], @"local-free");
    WKWebView *reopened = [self openRoot];
    XCTAssertEqualObjects([self script:@"return (await call('xhBookAudioGetSnapshot')).rate;" web:reopened], @1.5);
}

- (void)testInvalidAndUntrustedWindowRequestsLogFailureWithoutInventedCallbacks {
    WKWebView *root = [self openRoot];
    [self observeErrors:root];
    NSArray *cases = @[
        @{@"parameters" : @{}}, @{@"parameters" : @{@"url" : @7}}, @{@"parameters" : @{@"url" : @"index.html"}},
        @{@"parameters" : @{@"url" : @"https://example.com/"}}, @{@"parameters" : @{@"url" : @"javascript:alert(1)"}},
        @{
            @"parameters" : @{
                @"url" : [self.resources.URLByDeletingLastPathComponent URLByAppendingPathComponent:@"outside.html"]
                    .absoluteString
            }
        }
    ];
    NSUInteger count = 0;
    for (NSDictionary *item in cases) {
        [self post:@{@"actionName" : @"xhOpenWindow", @"parameters" : item[@"parameters"]} web:root];
        count++;
        [self waitUntil:^BOOL {
            return self.errorLogs.count == count;
        }];
        XCTAssertTrue([self.errorLogs.lastObject containsString:@"xhOpenWindow failed:"]);
        XCTAssertEqualObjects([self script:@"return window.windowErrors.length;" web:root], @0);
        XCTAssertEqual(self.navigation.viewControllers.count, 1u);
    }
    [self post:@{@"actionName" : @"xhCloseWindow", @"parameters" : @7} web:root];
    [self waitUntil:^BOOL {
        return self.errorLogs.count == count + 1;
    }];
    XCTAssertTrue([self.errorLogs.lastObject containsString:@"xhCloseWindow failed:"]);
    XCTAssertEqualObjects([self script:@"return window.windowErrors.length;" web:root], @0);
    XCTAssertEqual(self.navigation.viewControllers.count, 1u);
}

/// H5 入口限于 xh 前缀的单参数方法，不能调用管理类内部方法或在 actionName 内拼接 selector。
- (void)testInternalNativeMethodsCannotBeInvokedFromH5 {
    WKWebView *root = [self openRoot];
    NSDictionary *result = [self
        script:
            @"async function invoke(actionName, index) {"
             "return await new Promise(resolve => {"
             "const previous = window.xhWebJSBridge.nativeCallJS;"
             "window.xhWebJSBridge.nativeCallJS = message => {"
             "if (message.actionName === 'onBookAudioError') {"
             "window.xhWebJSBridge.nativeCallJS = previous; resolve(message.parameters);"
             "} else { previous(message); }};"
             "window.xhAppJSBridge.JSCallNative(JSON.stringify({ actionName,"
             "parameters: {},"
             "callbackActionName: 'native-method-check' })); }); }"
             "const errors = [];"
             "for (const [index, name] of ['invalidate', 'setPage', 'setActive', 'handleJSCallNative', 'xhCanIUse:', 'xhMissingMethod'].entries()) {"
             "const result = await invoke(name, index); errors.push(result.code); }"
             "const snapshot = await call('xhBookAudioGetSnapshot');"
             "return { errors, state: snapshot.state };"
           web:root];
    XCTAssertEqualObjects(
        result[@"errors"],
        (@[ @"UNSUPPORTED", @"UNSUPPORTED", @"UNSUPPORTED", @"UNSUPPORTED", @"UNSUPPORTED", @"UNSUPPORTED" ]));
    XCTAssertEqualObjects(result[@"state"], @"idle");
    XCTAssertEqual(self.navigation.viewControllers.count, 1u);
}

- (void)testHiddenParentCannotNavigateAndNativePopKeepsRootUsable {
    WKWebView *root = [self openRoot];
    [self observeErrors:root];
    [self post:@{@"actionName" : @"xhOpenWindow", @"parameters" : @{@"url" : self.childURL.absoluteString}} web:root];
    [self pageAtDepth:2];
    [self post:@{@"actionName" : @"xhCloseWindow"} web:root];
    [self waitUntil:^BOOL {
        return self.errorLogs.count == 1;
    }];
    XCTAssertEqualObjects([self script:@"return window.windowErrors.length;" web:root], @0);
    XCTAssertEqual(self.navigation.viewControllers.count, 2u);
    [self.navigation popViewControllerAnimated:NO];
    XCTAssertEqual([self pageAtDepth:1], root);
    [self post:@{@"actionName" : @"xhOpenWindow", @"parameters" : @{@"url" : self.childURL.absoluteString}} web:root];
    [self pageAtDepth:2];
}

- (void)testLoginFromChildReturnsToThatChild {
    WKWebView *root = [self openRoot];
    [self post:@{@"actionName" : @"xhOpenWindow", @"parameters" : @{@"url" : self.childURL.absoluteString}} web:root];
    WKWebView *child = [self pageAtDepth:2];
    UIViewController *childController = self.navigation.topViewController;
    [self
        script:
            @"window.loginResult=null; call('xhGetUserInfo',{goLogin:true,useTicket:false}).then((result)=>{window.loginResult=result;}); return true;"
           web:child];
    [self waitUntil:^BOOL {
        return self.navigation.viewControllers.count == 3 && !self.navigation.transitionCoordinator;
    }];
    UIButton *button = (UIButton *)[self findView:self.navigation.topViewController.view matching:^BOOL(UIView *view) {
        return [view isKindOfClass:UIButton.class] &&
               [[(UIButton *)view titleForState:UIControlStateNormal] isEqual:@"登录测试账号"];
    }];
    XCTAssertNotNil(button);
    [button sendActionsForControlEvents:UIControlEventTouchUpInside];
    XCTAssertEqual([self pageAtDepth:2], child);
    XCTAssertEqual(self.navigation.topViewController, childController);
    [self waitForScript:@"window.loginResult !== null" web:child];
    XCTAssertEqualObjects([self script:@"return window.loginResult.info.id;" web:child], @"local-user");
}

/// 加载参考前端实际安装的原版 xinhua-sdk，不通过手写信封代替兼容性验证。
- (void)installReferenceSDK:(WKWebView *)web {
    NSURL *URL = [[NSBundle bundleForClass:self.class] URLForResource:@"xinhua-sdk" withExtension:@"js"
                                                         subdirectory:@"Fixtures/XinhuaSDK"];
    NSError *error = nil;
    NSString *source = [NSString stringWithContentsOfURL:URL encoding:NSUTF8StringEncoding error:&error];
    XCTAssertNil(error);
    XCTAssertNotNil(source);
    XCTestExpectation *installed = [self expectationWithDescription:@"加载原版 xinhua-sdk"];
    [web evaluateJavaScript:source completionHandler:^(id result, NSError *failure) {
        XCTAssertNil(failure);
        [installed fulfill];
    }];
    [self waitForExpectations:@[ installed ] timeout:5];
    XCTAssertEqualObjects([self script:@"return xh.isMediaConvergenceXinhuaApp();" web:web], @YES);
    [self
        script:@"xh.addEventListener('compatibilityProbe',()=>{}); window.nativeMessages=[];"
                "const receive=window.xhWebJSBridge.nativeCallJS;"
                "window.xhWebJSBridge.nativeCallJS=(message)=>{window.nativeMessages.push(message); receive(message);};"
                "return true;"
           web:web];
}

/// 通过网页实际读写验证同源窗口共享数据；关闭容器和重建 SDK 都不应清空网页持久数据。
- (void)testReferenceSDKWindowsShareLocalStorageAcrossCloseAndReopen {
    NSString *storageKey = NSUUID.UUID.UUIDString;
    NSString *readStorage = [NSString stringWithFormat:@"return localStorage.getItem('%@');", storageKey];
    NSString *clearStorage = [NSString stringWithFormat:@"localStorage.removeItem('%@'); return true;", storageKey];
    WKWebView *root = [self openRoot];
    [self installReferenceSDK:root];
    [self script:[NSString stringWithFormat:@"localStorage.setItem('%@','parent-session'); return true;", storageKey]
             web:root];
    XCTAssertEqualObjects([self script:readStorage web:root], @"parent-session");
    [self script:@"xh.openWindow({url:location.href}); return true;" web:root];
    WKWebView *child = [self pageAtDepth:2];
    XCTAssertNotEqual(root, child);
    XCTAssertEqualObjects(root.URL, child.URL);
    XCTAssertEqualObjects([self script:readStorage web:child], @"parent-session");
    [self script:[NSString stringWithFormat:@"localStorage.setItem('%@','updated-session'); return true;", storageKey]
             web:child];
    [self installReferenceSDK:child];
    [self script:@"xh.closeWindow(); return true;" web:child];
    XCTAssertEqual([self pageAtDepth:1], root);
    XCTAssertEqualObjects([self script:readStorage web:root], @"updated-session");
    [self script:@"xh.closeWindow(); return true;" web:root];
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
- (void)testReferenceSDKWindowsShareCookiesWithHostDefaultDataStore {
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
    [self installReferenceSDK:root];
    [self script:@"xh.openWindow({url:location.href}); return true;" web:root];
    [self assertCookie:cookie availableInWebView:[self pageAtDepth:2]];
    // 默认存储属于整个宿主 App，测试只能删除自己写入的 Cookie。
    XCTestExpectation *removed = [self expectationWithDescription:@"移除测试 Cookie"];
    [hostStore deleteCookie:cookie completionHandler:^{
        [removed fulfill];
    }];
    [self waitForExpectations:@[ removed ] timeout:5];
}

/// 通过真实 H5 入口验证“实现即支持”，并确保能力集合与逐项查询一致，无需修改任何动作名单。
- (void)testImplementedH5MethodWorksWithoutSeparateRegistration {
    WKWebView *web = [self openRoot];
    [self installReferenceSDK:web];
    NSDictionary *result = [self
        script:
            @"const capability=await new Promise(complete=>xh.canIUse({name:'testEcho',complete}));"
             "const capabilities=await new Promise(success=>xh.execCustomMethod('bookAudioGetCapabilities',{success}));"
             "const response=await new Promise(resolve=>{xh.addEventListener('onBookAudioError',error=>resolve({error}));"
             "xh.execCustomMethod('testEcho',{success:system=>resolve({system})});});"
             "const checks=[]; for (const action of capabilities.actions) {"
             "checks.push(await new Promise(complete=>xh.canIUse({name:action.slice(2),complete})));}"
             "return {capability,actions:capabilities.actions,response,checks};"
           web:web];
    XCTAssertEqualObjects(result[@"capability"][@"data"], @1);
    XCTAssertTrue([result[@"actions"] containsObject:@"xhTestEcho"]);
    XCTAssertEqualObjects(result[@"response"][@"system"][@"device_token"],
                          UIDevice.currentDevice.identifierForVendor.UUIDString);
    XCTAssertNil(result[@"response"][@"error"]);
    for (NSDictionary *check in result[@"checks"]) {
        XCTAssertEqualObjects(check[@"data"], @1);
    }
}

/// 原版 xh.goLogin 不传版本、请求 ID 或业务回调；必须能直接打开宿主登录页。
- (void)testReferenceSDKGoLoginPresentsHostLoginWithoutCustomEnvelope {
    WKWebView *root = [self openRoot];
    [self installReferenceSDK:root];
    [self script:@"xh.goLogin(); return true;" web:root];
    [self waitUntil:^BOOL {
        return self.navigation.viewControllers.count == 2 && !self.navigation.transitionCoordinator;
    }];
    XCTAssertEqualObjects([self script:@"return window.nativeMessages.length;" web:root], @0);
    // 返回取消后仍能再次通过同一标准接口登录，不要求 H5 等待自定义登录回执。
    [self.navigation popViewControllerAnimated:NO];
    XCTAssertEqual([self pageAtDepth:1], root);
    XCTAssertNil(AppAccountService.sharedInstance.userId);
    [self script:@"xh.goLogin(); return true;" web:root];
    [self waitUntil:^BOOL {
        return self.navigation.viewControllers.count == 2 && !self.navigation.transitionCoordinator;
    }];
    UIButton *button = (UIButton *)[self findView:self.navigation.topViewController.view matching:^BOOL(UIView *view) {
        return [view isKindOfClass:UIButton.class] &&
               [[(UIButton *)view titleForState:UIControlStateNormal] isEqual:@"登录测试账号"];
    }];
    XCTAssertNotNil(button);
    [button sendActionsForControlEvents:UIControlEventTouchUpInside];
    XCTAssertEqual([self pageAtDepth:1], root);
    XCTAssertGreaterThan(AppAccountService.sharedInstance.userId.length, 0u);
}

/// 使用前端公开 API 完成能力查询、开窗和关窗，回调直接收到 parameters，不依赖实验包装。
- (void)testReferenceSDKWindowMethodsAndCapabilityCallbacks {
    WKWebView *root = [self openRoot];
    [self installReferenceSDK:root];
    [self script:@"window.capabilities=[]; for(const name of ['openWindow','closeWindow','goLogin']){"
                  "xh.canIUse({name,complete:(result)=>{window.capabilities.push(result);}});} return true;"
             web:root];
    [self waitForScript:@"window.capabilities.length === 3" web:root];
    NSArray *expected = @[ @{@"data" : @1}, @{@"data" : @1}, @{@"data" : @1} ];
    XCTAssertEqualObjects([self script:@"return window.capabilities;" web:root], expected);
    [self
        script:
            @"window.nativeMessages=[]; xh.openWindow({url:new URL('nested/index.html',location.href).href}); return true;"
           web:root];
    WKWebView *child = [self pageAtDepth:2];
    XCTAssertEqualObjects(child.URL.URLByResolvingSymlinksInPath, self.childURL.URLByResolvingSymlinksInPath);
    XCTAssertEqualObjects([self script:@"return window.nativeMessages.length;" web:root], @0);
    [self installReferenceSDK:child];
    [child evaluateJavaScript:@"xh.closeWindow();" completionHandler:nil];
    XCTAssertEqual([self pageAtDepth:1], root);
    XCTAssertEqualObjects([self script:@"return window.nativeMessages.length;" web:root], @0);
    [root evaluateJavaScript:@"xh.closeWindow();" completionHandler:nil];
    [self waitUntil:^BOOL {
        return self.presenter.presentedViewController == nil;
    }];
}

/// 从原项目的 EasyJS 线格式进入原生，验证两次 URI 解码和回调中的特殊字符不丢失。
- (void)testReferenceEasyJSFrameRoundTripsSpecialCharacters {
    WKWebView *web = [self openRoot];
    NSString *title = @"中文:100%:%3A:%25 + \"引号\" \\ 换行\n\u2028\u2029 🎧";
    XCTestExpectation *done = [self expectationWithDescription:@"EasyJS 编码消息往返"];
    NSString *script =
        @"const available=typeof window.EasyJS==='object' && typeof EasyJS.call==='function' && typeof EasyJS.inject==='function';"
         "const request=JSON.stringify({actionName:'xhBookAudioSetQueue',parameters:{bookId:'easyjs-book',title,"
         "chapters:[{chapterId:'chapter-1',title,requiresLogin:false,audioURL:new URL('chapter-1.wav',location.href).href}]},"
         "callbackActionName:'easyjs-roundtrip'});"
         "const frame='xhAppJSBridge:'+encodeURIComponent('JSCallNative:')+':'+encodeURIComponent(encodeURIComponent(request));"
         "const reply=await new Promise(resolve=>{const previous=window.xhWebJSBridge.nativeCallJS;"
         "window.xhWebJSBridge.nativeCallJS=message=>{"
         "if(message.actionName==='easyjs-roundtrip'||message.actionName==='onBookAudioError'){"
         "window.xhWebJSBridge.nativeCallJS=previous;resolve(message);}else{previous(message);}};"
         "window.webkit.messageHandlers.xhAppJSBridge.postMessage(frame);});"
         "return {available,reply};";
    [web callAsyncJavaScript:script arguments:@{@"title" : title} inFrame:nil inContentWorld:WKContentWorld.pageWorld
           completionHandler:^(NSDictionary *result, NSError *error) {
               XCTAssertNil(error);
               XCTAssertEqualObjects(result[@"available"], @YES);
               XCTAssertEqualObjects(result[@"reply"][@"actionName"], @"easyjs-roundtrip");
               XCTAssertEqualObjects(result[@"reply"][@"parameters"][@"title"], title);
               XCTAssertEqualObjects(result[@"reply"][@"parameters"][@"chapterTitle"], title);
               [done fulfill];
           }];
    [self waitForExpectations:@[ done ] timeout:8];
}

/// 非法外层消息不能调用任意原生方法；错误可观察，拒绝后标准请求仍然可用。
- (void)testMalformedEasyJSFramesAreRejectedWithoutChangingPlayback {
    WKWebView *web = [self openRoot];
    NSDictionary *result = [self
        script:
            @"const request=JSON.stringify({actionName:'xhBookAudioSetRate',parameters:{rate:2},callbackActionName:'unexpected-success'});"
             "const encoded=encodeURIComponent(encodeURIComponent(request));"
             "const prefix='xhAppJSBridge:'+encodeURIComponent('JSCallNative:')+':';"
             "const frames=[request,'xhAppJSBridge','other:'+encodeURIComponent('JSCallNative:')+':'+encoded,"
             "'xhAppJSBridge:'+encodeURIComponent('setJSCallNativeBlock:')+':'+encoded,"
             "prefix+'%GG',prefix+encodeURIComponent('%GG'),prefix+encodeURIComponent(encodeURIComponent(request)+':extra'),"
             "{actionName:'xhBookAudioSetRate',parameters:{rate:2}},prefix+'x'.repeat(4*1024*1024)];"
             "const errors=[];"
             "for(const frame of frames){"
             "errors.push(await new Promise(resolve=>{const previous=window.xhWebJSBridge.nativeCallJS;"
             "window.xhWebJSBridge.nativeCallJS=message=>{"
             "if(message.actionName==='onBookAudioError'||message.actionName==='unexpected-success'){"
             "window.xhWebJSBridge.nativeCallJS=previous;resolve(message);}else{previous(message);}};"
             "window.webkit.messageHandlers.xhAppJSBridge.postMessage(frame);}));}"
             "return {errors,snapshot:await call('xhBookAudioGetSnapshot')};"
           web:web];
    NSArray *errors = result[@"errors"];
    XCTAssertEqual(errors.count, 9u);
    for (NSDictionary *error in errors) {
        XCTAssertEqualObjects(error[@"actionName"], @"onBookAudioError");
        XCTAssertEqualObjects(error[@"parameters"][@"code"], @"INVALID_ARGUMENT");
    }
    XCTAssertEqualObjects(result[@"snapshot"][@"rate"], @1);
    XCTAssertEqualObjects(result[@"snapshot"][@"state"], @"idle");
}

/// 编码会放大中文消息；业务 JSON 未超限时应成功，解码后超限时明确拒绝且保留原队列。
- (void)testEasyJSLengthLimitAppliesToDecodedJSON {
    WKWebView *web = [self openRoot];
    NSDictionary *result = [self
        script:
            @"const title='书'.repeat(20000);"
             "const parameters={bookId:'unicode-book',title,chapters:[{chapterId:'chapter-1',title:'Chapter',requiresLogin:false,"
             "audioURL:new URL('chapter-1.wav',location.href).href}]};"
             "const snapshot=await call('xhBookAudioSetQueue',parameters);"
             "const error=await new Promise(resolve=>{const previous=window.xhWebJSBridge.nativeCallJS;"
             "window.xhWebJSBridge.nativeCallJS=message=>{if(message.actionName==='onBookAudioError'){"
             "window.xhWebJSBridge.nativeCallJS=previous;resolve(message.parameters);}else{previous(message);}};"
             "window.xhAppJSBridge.JSCallNative(JSON.stringify({actionName:'xhBookAudioSetQueue',"
             "parameters:{...parameters,title:'x'.repeat(256*1024)}}));});"
             "const current=await call('xhBookAudioGetSnapshot');"
             "return {titleLength:snapshot.title.length,code:error.code,currentTitleLength:current.title.length};"
           web:web];
    XCTAssertEqualObjects(result[@"titleLength"], @20000);
    XCTAssertEqualObjects(result[@"code"], @"INVALID_ARGUMENT");
    XCTAssertEqualObjects(result[@"currentTitleLength"], @20000);
}

/// 原版 JS SDK 只发送标准请求；快照直接返回业务对象，新确认名称可查询，旧别名不可调用。
- (void)testReferenceSDKSnapshotUsesOnlyStandardCallbackAndConfirmedMethods {
    WKWebView *web = [self openRoot];
    [self installReferenceSDK:web];
    NSDictionary *result = [self
        script:
            @"const snapshot = await new Promise(success => xh.execCustomMethod('bookAudioGetSnapshot', {success}));"
             "const names = ['getUserInfo', 'showShareMenu', 'bookAudioGetUserIdentity', 'bookAudioRequestLogin', 'bookAudioShare'];"
             "const capabilities = [];"
             "for (const name of names) {"
             "capabilities.push(await new Promise(complete => xh.canIUse({name, complete}))); }"
             "return {snapshot, capabilities};"
           web:web];
    XCTAssertEqualObjects(result[@"snapshot"][@"state"], @"idle");
    XCTAssertNil(result[@"snapshot"][@"protocolVersion"]);
    XCTAssertNil(result[@"snapshot"][@"requestId"]);
    XCTAssertNil(result[@"snapshot"][@"ok"]);
    XCTAssertNil(result[@"snapshot"][@"data"]);
    XCTAssertEqualObjects(result[@"capabilities"],
                          (@[ @{@"data" : @1}, @{@"data" : @1}, @{@"data" : @0}, @{@"data" : @0}, @{@"data" : @0} ]));
}

/// 直接运行原版用户资料 API，覆盖其内部系统资料查询；SDK 不替宿主生成账号资料或票据。
- (void)testReferenceSDKUserInfoReadsHostDataAndReportsUnsupportedTicket {
    WKWebView *web = [self openRoot];
    [self installReferenceSDK:web];
    NSDictionary *guest =
        [self script:@"return await new Promise(success=>xh.getUserInfo({goLogin:false,useTicket:false,success}));"
                 web:web];
    XCTAssertEqualObjects(guest, @{});
    [AppAccountService.sharedInstance updateAuthenticatedUserId:@"profile-user"];
    NSDictionary *profile =
        [self script:@"return await new Promise(success=>xh.getUserInfo({goLogin:false,useTicket:false,success}));"
                 web:web];
    XCTAssertEqualObjects(profile[@"id"], @"profile-user");
    XCTAssertEqualObjects(profile[@"info"][@"id"], @"profile-user");
    NSDictionary *system = [self script:@"return await new Promise(success=>xh.getSystemInfo({success}));" web:web];
    XCTAssertEqualObjects(system[@"device_token"], UIDevice.currentDevice.identifierForVendor.UUIDString);
    NSDictionary *failure =
        [self script:@"window.ticketSuccess=false; return await new Promise(resolve=>{"
                      "xh.addEventListener('onBookAudioError',resolve);"
                      "xh.getUserInfo({goLogin:false,useTicket:true,success:()=>{window.ticketSuccess=true;}});});"
                 web:web];
    XCTAssertEqualObjects(failure[@"code"], @"UNSUPPORTED");
    XCTAssertEqualObjects([self script:@"return window.ticketSuccess;" web:web], @NO);
}

/// 原版分享 API 不注册成功回调；弹出系统菜单和取消后都不应收到自造业务回执。
- (void)testReferenceSDKShareMenuPresentsAndCancellationDoesNotReportSuccess {
    WKWebView *web = [self openRoot];
    [self installReferenceSDK:web];
    [self
        script:
            @"window.nativeMessages=[]; xh.showShareMenu({title:'Book',link:'https://example.com/book',desc:'Book description',imgUrl:''}); return true;"
           web:web];
    UIViewController *page = self.navigation.topViewController;
    [self waitUntil:^BOOL {
        return [page.presentedViewController isKindOfClass:UIActivityViewController.class] &&
               !page.presentedViewController.transitionCoordinator;
    }];
    UIActivityViewController *share = (UIActivityViewController *)page.presentedViewController;
    XCTAssertEqualObjects([self script:@"return window.nativeMessages;" web:web], @[]);
    // 系统分享是外部 UI 边界，通过其公开 completion 模拟用户取消，保持真实 H5 到宿主展示链路。
    share.completionWithItemsHandler(nil, NO, nil, nil);
    XCTestExpectation *closed = [self expectationWithDescription:@"share menu closed"];
    [share dismissViewControllerAnimated:NO completion:^{
        [closed fulfill];
    }];
    [self waitForExpectations:@[ closed ] timeout:3];
    XCTAssertEqualObjects([self script:@"return window.nativeMessages;" web:web], @[]);
    XCTAssertEqual(self.navigation.viewControllers.count, 1u);
}

/// 原版扩展入口执行全部听书动作；成功返回业务对象，订阅和取消订阅仍以当前文档为边界。
- (void)testReferenceSDKExecutesConfirmedListeningActionsWithoutEnvelopeFields {
    WKWebView *web = [self openRoot];
    [self installReferenceSDK:web];
    NSDictionary *result = [self
        script:
            @"const invoke=(name,parameters={})=>new Promise(success=>xh.execCustomMethod(name,{...parameters,success}));"
             "window.playbackEvents=[]; xh.addEventListener('onBookAudioPlaybackChange',snapshot=>window.playbackEvents.push(snapshot));"
             "const capability=await invoke('bookAudioGetCapabilities');"
             "const subscribed=await invoke('bookAudioSubscribe');"
             "const chapters=[1,2,3].map(index=>({chapterId:'chapter-'+index,title:'Chapter '+index,requiresLogin:false,"
             "audioURL:new URL('chapter-'+index+'.wav',location.href).href,durationMs:4000}));"
             "await invoke('bookAudioSetQueue',{bookId:'reference-book',title:'Reference',chapters});"
             "const rate=await invoke('bookAudioSetRate',{rate:1.5});"
             "await invoke('bookAudioPlay'); await invoke('bookAudioPause');"
             "await invoke('bookAudioSeekTo',{positionMs:100});"
             "const next=await invoke('bookAudioNext'); await invoke('bookAudioPause');"
             "const previous=await invoke('bookAudioPrevious'); await invoke('bookAudioPause');"
             "const selected=await invoke('bookAudioSelectChapter',{chapterId:'chapter-3'}); await invoke('bookAudioPause');"
             "const timer=await invoke('bookAudioSetSleepTimer',{mode:'trackCount',count:2});"
             "const cancelled=await invoke('bookAudioCancelSleepTimer');"
             "await invoke('bookAudioStop');"
             "const snapshots=await Promise.all([invoke('bookAudioGetSnapshot'),invoke('bookAudioGetSnapshot')]);"
             "const unsubscribed=await invoke('bookAudioUnsubscribe');"
             "return {capability,subscribed,rate,next,previous,selected,timer,cancelled,snapshots,unsubscribed,events:window.playbackEvents};"
           web:web];
    XCTAssertEqualObjects(result[@"subscribed"], (@{@"subscribed" : @YES}));
    XCTAssertEqualObjects(result[@"rate"][@"rate"], @1.5);
    XCTAssertEqualObjects(result[@"next"][@"chapterId"], @"chapter-2");
    XCTAssertEqualObjects(result[@"previous"][@"chapterId"], @"chapter-1");
    XCTAssertEqualObjects(result[@"selected"][@"chapterId"], @"chapter-3");
    XCTAssertEqualObjects(result[@"timer"][@"sleepTimer"][@"mode"], @"trackCount");
    XCTAssertEqualObjects(result[@"cancelled"][@"sleepTimer"][@"mode"], @"off");
    NSArray *snapshots = result[@"snapshots"];
    XCTAssertEqual(snapshots.count, 2u);
    for (NSDictionary *snapshot in snapshots) {
        XCTAssertEqualObjects(snapshot[@"state"], @"stopped");
        XCTAssertEqualObjects(snapshot[@"bookId"], @"reference-book");
        XCTAssertNil(snapshot[@"ok"]);
    }
    XCTAssertGreaterThan([result[@"events"] count], 0u);
    XCTAssertEqualObjects(result[@"unsubscribed"], (@{@"subscribed" : @NO}));
    XCTAssertNil(result[@"capability"][@"protocolVersion"]);
    XCTAssertTrue([result[@"capability"][@"actions"] containsObject:@"xhGetSystemInfo"]);
}

/// 业务参数错误仍被拒绝；只触发已有错误事件，不能冒充成功或使 WebContent 进程异常。
- (void)testInvalidUserInfoAndPlaybackParametersDoNotInvokeSuccess {
    WKWebView *web = [self openRoot];
    [self installReferenceSDK:web];
    NSArray *errors = [self
        script:
            @"window.successCount=0; const failures=[];"
             "for(const [name,parameters] of [['getUserInfo',{goLogin:{}}],['bookAudioSetRate',{rate:99}]]){"
             "const result=await new Promise(resolve=>{const receive=window.xhWebJSBridge.nativeCallJS;"
             "window.xhWebJSBridge.nativeCallJS=message=>{receive(message); if(message.actionName==='onBookAudioError'){"
             "window.xhWebJSBridge.nativeCallJS=receive;resolve(message.parameters);}};"
             "xh.execCustomMethod(name,{...parameters,success:()=>{window.successCount++;}});}); failures.push(result.code);}"
             "return failures;"
           web:web];
    XCTAssertEqualObjects(errors, (@[ @"INVALID_ARGUMENT", @"INVALID_ARGUMENT" ]));
    XCTAssertEqualObjects([self script:@"return window.successCount;" web:web], @0);
    NSDictionary *snapshot =
        [self script:@"return await new Promise(success=>xh.execCustomMethod('bookAudioGetSnapshot',{success}));"
                 web:web];
    XCTAssertEqualObjects(snapshot[@"rate"], @1);
    XCTAssertEqualObjects(snapshot[@"state"], @"idle");
}

- (void)testShutdownDismissesAllWindowsAndAllowsNewSession {
    WKWebView *root = [self openRoot];
    [self post:@{@"actionName" : @"xhOpenWindow", @"parameters" : @{@"url" : self.childURL.absoluteString}} web:root];
    [self pageAtDepth:2];
    [self.service shutdown];
    [self waitUntil:^BOOL {
        return self.presenter.presentedViewController == nil;
    }];
    XCTAssertNil([self.service getSnapshot]);
    [self openRoot];
}

@end
