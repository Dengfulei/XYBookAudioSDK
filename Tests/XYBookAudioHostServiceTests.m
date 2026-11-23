// 宿主接入行为测试：通过公开服务、真实页面和 H5 验证会话复用、push 登录以及资源释放。
#import <XCTest/XCTest.h>
#import <WebKit/WebKit.h>
#import "../XYBookAudioSDKDemo/BookAudio/AppBookAudioService.h"
#import "../XYBookAudioSDKDemo/Account/AppAccountService.h"

@interface XYBookAudioHostServiceTests : XCTestCase
@property (nonatomic, strong) AppBookAudioService *service;
@property (nonatomic, strong) XYBookAudioConfiguration *configuration;
@property (nonatomic, strong) UIViewController *originalRoot;
@end

@implementation XYBookAudioHostServiceTests

- (void)setUp {
    [super setUp];
    self.service = AppBookAudioService.sharedInstance;
    [self.service shutdown];
    [AppAccountService.sharedInstance logout];
    self.originalRoot = UIApplication.sharedApplication.delegate.window.rootViewController;
    NSURL *entry = [[NSBundle bundleForClass:self.class] URLForResource:@"index" withExtension:@"html"
                                                           subdirectory:@"Fixture"];
    XCTAssertNotNil(entry);
    self.configuration = [[XYBookAudioConfiguration alloc] initWithHostIdentifier:NSUUID.UUID.UUIDString
                                                                         entryURL:entry];
    self.configuration.environment = @"host-service-tests";
}

- (void)tearDown {
    [self.service shutdown];
    UIViewController *root = UIApplication.sharedApplication.delegate.window.rootViewController;
    [self waitUntil:^BOOL {
        return root.presentedViewController == nil;
    }];
    UIApplication.sharedApplication.delegate.window.rootViewController = self.originalRoot;
    [super tearDown];
}

/// 只等待可观察的 UI／公开状态，不依赖服务内部的 SDK 属性或调用顺序。
- (void)waitUntil:(BOOL (^)(void))condition {
    XCTNSPredicateExpectation *expectation = [[XCTNSPredicateExpectation alloc]
        initWithPredicate:[NSPredicate predicateWithBlock:^BOOL(id object, NSDictionary *bindings) {
            return condition();
        }]
                   object:nil];
    XCTAssertEqual([XCTWaiter waitForExpectations:@[ expectation ] timeout:15], XCTWaiterResultCompleted);
}

- (void)configure {
    NSError *error = nil;
    XCTAssertTrue([self.service configureWithConfiguration:self.configuration error:&error]);
    XCTAssertNil(error);
}

/// 通过视图树寻找用户可见内容，不要求 SDK 暴露 WebView 或登录页的私有实现。
- (UIView *)findView:(UIView *)root matching:(BOOL (^)(UIView *))predicate {
    if (predicate(root)) {
        return root;
    }
    for (UIView *child in root.subviews) {
        UIView *match = [self findView:child matching:predicate];
        if (match) {
            return match;
        }
    }
    return nil;
}

- (WKWebView *)openFrom:(UIViewController *)presenter {
    XCTestExpectation *opened = [self expectationWithDescription:@"听书页面已展示"];
    [self.service openFromViewController:presenter style:XYBookAudioOpenStylePresent completion:^(NSError *error) {
        XCTAssertNil(error);
        [opened fulfill];
    }];
    [self waitForExpectations:@[ opened ] timeout:5];
    WKWebView *web = (WKWebView *)[self findView:presenter.presentedViewController.view matching:^BOOL(UIView *view) {
        return [view isKindOfClass:WKWebView.class];
    }];
    XCTAssertNotNil(web);
    [self waitUntil:^BOOL {
        return [web.title isEqualToString:@"听书集成验证"] && !web.loading;
    }];
    XCTAssertEqualObjects([self runJavaScript:@"return typeof window.call;" web:web], @"function");
    return web;
}

- (id)runJavaScript:(NSString *)script web:(WKWebView *)web {
    XCTestExpectation *done = [self expectationWithDescription:@"H5 命令完成"];
    __block id result;
    [web callAsyncJavaScript:script arguments:@{} inFrame:nil inContentWorld:WKContentWorld.pageWorld
           completionHandler:^(id output, NSError *error) {
               XCTAssertNil(error);
               result = output;
               [done fulfill];
           }];
    [self waitForExpectations:@[ done ] timeout:8];
    return result;
}

- (void)closeFrom:(UIViewController *)presenter {
    XCTestExpectation *closed = [self expectationWithDescription:@"听书页面已关闭"];
    [presenter dismissViewControllerAnimated:NO completion:^{
        [closed fulfill];
    }];
    [self waitForExpectations:@[ closed ] timeout:4];
}

/// 从真实页面读取 UA，验证默认内容保留、重载／重开不重复追加，以及宿主其他 WebView 的隔离。
- (void)testListeningUserAgentPreservesDefaultAndDoesNotAffectHostWebView {
    WKWebView *hostWebView = [[WKWebView alloc] initWithFrame:self.originalRoot.view.bounds];
    [hostWebView loadHTMLString:@"<html><head><title>宿主 UA 验证</title></head><body></body></html>" baseURL:nil];
    [self waitUntil:^BOOL {
        return [hostWebView.title isEqualToString:@"宿主 UA 验证"] && !hostWebView.loading;
    }];
    NSString *defaultUserAgent = [self runJavaScript:@"return navigator.userAgent;" web:hostWebView];
    XCTAssertTrue(defaultUserAgent.length > 0);
    XCTAssertFalse([defaultUserAgent containsString:@"MediaConvergenceXinhua"]);
    NSString *expectedUserAgent = [defaultUserAgent stringByAppendingString:@" MediaConvergenceXinhua"];

    [self configure];
    WKWebView *web = [self openFrom:self.originalRoot];
    if (@available(iOS 16.4, *)) {
        XCTAssertFalse(web.inspectable);
    }
    XCTAssertEqualObjects([self runJavaScript:@"return navigator.userAgent;" web:web], expectedUserAgent);
    [web reload];
    [self waitUntil:^BOOL {
        return [web.title isEqualToString:@"听书集成验证"] && !web.loading;
    }];
    XCTAssertEqualObjects([self runJavaScript:@"return navigator.userAgent;" web:web], expectedUserAgent);

    [self closeFrom:self.originalRoot];
    WKWebView *reopened = [self openFrom:self.originalRoot];
    XCTAssertEqualObjects([self runJavaScript:@"return navigator.userAgent;" web:reopened], expectedUserAgent);
    XCTAssertEqualObjects([self runJavaScript:@"return navigator.userAgent;" web:hostWebView], defaultUserAgent);
    [hostWebView stopLoading];
}

- (void)testWebInspectorCanBeEnabledByTheHost {
    self.configuration.webInspectorEnabled = YES;
    [self configure];
    self.configuration.webInspectorEnabled = NO;
    WKWebView *web = [self openFrom:self.originalRoot];
    if (@available(iOS 16.4, *)) {
        XCTAssertTrue(web.inspectable);
    }
}

- (void)testInvalidConfigurationCanRetryAndExistingSessionRejectsReconfiguration {
    XCTAssertNil([self.service playbackSnapshot]);
    XYBookAudioConfiguration *invalid = [self.configuration copy];
    invalid.environment = @"";
    NSError *error = nil;
    XCTAssertFalse([self.service configureWithConfiguration:invalid error:&error]);
    XCTAssertEqual(error.code, XYBookAudioInvalidArgument);
    XCTAssertNil([self.service playbackSnapshot]);
    [self configure];
    NSDictionary *snapshot = [self.service playbackSnapshot];
    error = nil;
    XCTAssertFalse([self.service configureWithConfiguration:self.configuration error:&error]);
    XCTAssertEqual(error.code, XYBookAudioBusy);
    XCTAssertEqualObjects([self.service playbackSnapshot], snapshot);
}

- (void)testEntryReleaseAndReopenPreserveQueueAndSingleEventStream {
    [self configure];
    __weak UIViewController *weakFirst;
    UIViewController *second = [UIViewController new];
    // UIKit 的属性读取可能产生自动释放引用；先结束用户路径的作用域，再断言入口对象能释放。
    @autoreleasepool {
        UIViewController *first = [UIViewController new];
        weakFirst = first;
        UIWindow *window = UIApplication.sharedApplication.delegate.window;
        window.rootViewController = first;
        WKWebView *web = [self openFrom:first];
        [self runJavaScript:@"await loadQueue('https://example.invalid/fixture.mp3'); return true;" web:web];
        [self.service openFromViewController:first style:XYBookAudioOpenStylePresent completion:^(NSError *error) {
            XCTAssertEqual(error.code, XYBookAudioBusy);
        }];
        [self closeFrom:first];
        window.rootViewController = second;
    }
    [self waitUntil:^BOOL {
        return weakFirst == nil;
    }];
    XCTAssertEqualObjects([self.service playbackSnapshot][@"bookId"], @"SNCK");
    WKWebView *web = [self openFrom:second];
    NSDictionary *snapshot = [self runJavaScript:@"return await call('xhSnckAudioGetState');" web:web];
    XCTAssertEqualObjects(snapshot[@"item"][@"id"], @"fixture");
    XCTAssertEqualObjects(snapshot[@"state"], @"PAUSED");
    __block NSUInteger events = 0;
    id observer = [NSNotificationCenter.defaultCenter
        addObserverForName:AppBookAudioServiceEventNotification
                    object:self.service
                     queue:nil
                usingBlock:^(NSNotification *notification) {
                    if ([notification.userInfo[AppBookAudioServiceEventNameKey] isEqual:@"onBookAudioPlaybackChange"] &&
                        [notification.userInfo[AppBookAudioServiceEventParametersKey][@"positionMs"] isEqual:@2000]) {
                        events++;
                    }
                }];
    [self runJavaScript:@"return await call('xhSnckAudioSeekTo',{positionMs:2000});" web:web];
    [NSNotificationCenter.defaultCenter removeObserver:observer];
    XCTAssertEqual(events, 1u);

    [self.service stopPlayback];
    NSDictionary *stopped = [self.service playbackSnapshot];
    XCTAssertEqualObjects(stopped[@"state"], @"stopped");
    XCTAssertEqualObjects(stopped[@"bookId"], @"SNCK");
}

/// 从宿主协议发起登录，随后验证 SNCK 身份同步。
- (XCTestExpectation *)requestLogin:(UINavigationController *)navigation result:(XYBookAudioLoginResult)expected {
    XCTestExpectation *done = [self expectationWithDescription:@"宿主登录完成"];
    done.assertForOverFulfill = YES;
    id<XYBookAudioHost> host = (id<XYBookAudioHost>)self.service;
    [host bookAudioRequestLoginFrom:navigation.topViewController
                         completion:^(XYBookAudioLoginResult result, NSError *error) {
                             XCTAssertNil(error);
                             XCTAssertEqual(result, expected);
                             [done fulfill];
                         }];
    [self waitUntil:^BOOL {
        return navigation.viewControllers.count == 2 && navigation.topViewController.viewIfLoaded.window != nil &&
               navigation.transitionCoordinator == nil;
    }];
    return done;
}

- (void)tapTitle:(NSString *)title in:(UIView *)view {
    UIButton *button = (UIButton *)[self findView:view matching:^BOOL(UIView *candidate) {
        return [candidate isKindOfClass:UIButton.class] && [((UIButton *)candidate).currentTitle isEqual:title];
    }];
    XCTAssertNotNil(button);
    [button sendActionsForControlEvents:UIControlEventTouchUpInside];
}

- (void)testPushLoginReturnsToListeningAndLogoutRefreshesIdentity {
    [self configure];
    UIViewController *presenter = self.originalRoot;
    WKWebView *web = [self openFrom:presenter];
    [self runJavaScript:@"await loadQueue('https://example.invalid/fixture.mp3'); return true;" web:web];
    UINavigationController *navigation = (UINavigationController *)presenter.presentedViewController;
    __weak UIViewController *weakLogin;
    @autoreleasepool {
        XCTestExpectation *login = [self requestLogin:navigation result:XYBookAudioLoginLoggedIn];
        weakLogin = navigation.topViewController;
        [self tapTitle:@"登录测试账号" in:navigation.topViewController.view];
        [self waitForExpectations:@[ login ] timeout:5];
        [self waitUntil:^BOOL {
            return navigation.viewControllers.count == 1 && navigation.transitionCoordinator == nil;
        }];
    }
    [self waitUntil:^BOOL {
        return weakLogin == nil;
    }];
    [self waitForIdentityText:@"用户：local-user" web:web];
    XCTAssertEqualObjects([self runJavaScript:@"return (await call('xhSnckGetUserInfo')).user.id;" web:web],
                          @"local-user");
    XCTAssertEqualObjects([self runJavaScript:@"return (await call('xhSnckAudioGetState')).items;" web:web], @[]);
    [self runJavaScript:@"await loadQueue('https://example.invalid/fixture.mp3'); return true;" web:web];
    [AppAccountService.sharedInstance logout];
    [self waitForIdentityText:@"游客" web:web];
    NSDictionary *playback = [self runJavaScript:@"return await call('xhSnckAudioGetState');" web:web];
    XCTAssertEqualObjects(playback[@"state"], @"IDLE");
    XCTAssertEqualObjects(playback[@"items"], @[]);
}

- (void)testBackCancellationAllowsAnotherLoginAndFailureResult {
    [self configure];
    WKWebView *web = [self openFrom:self.originalRoot];
    UINavigationController *navigation = (UINavigationController *)self.originalRoot.presentedViewController;
    XCTestExpectation *cancelled = [self requestLogin:navigation result:XYBookAudioLoginCancelled];
    [navigation popViewControllerAnimated:NO];
    [self waitForExpectations:@[ cancelled ] timeout:5];
    XCTestExpectation *failed = [self requestLogin:navigation result:XYBookAudioLoginFailed];
    [self tapTitle:@"模拟失败" in:navigation.topViewController.view];
    [self waitForExpectations:@[ failed ] timeout:5];
    [self waitUntil:^BOOL {
        return navigation.viewControllers.count == 1 && navigation.transitionCoordinator == nil;
    }];
    XCTAssertEqualObjects([self runJavaScript:@"return (await call('xhSnckGetUserInfo')).guest;" web:web], @YES);
}

- (void)testShutdownReleasesSessionAndReopenRetainsConfiguration {
    [self configure];
    WKWebView *web = [self openFrom:self.originalRoot];
    [self runJavaScript:@"await loadQueue('https://example.invalid/fixture.mp3'); return true;" web:web];
    [self.service shutdown];
    XCTAssertNil([self.service playbackSnapshot]);
    [self waitUntil:^BOOL {
        return self.originalRoot.presentedViewController == nil;
    }];
    self.configuration.environment = @"";
    web = [self openFrom:self.originalRoot];
    NSDictionary *snapshot = [self runJavaScript:@"return await call('xhSnckAudioGetState');" web:web];
    XCTAssertEqualObjects(snapshot[@"items"], @[]);
}

/// 账号模块不依赖听书；通知发生时身份已提交，相同账号和重复退出不会产生重复变更。
- (void)testAccountNotificationsExposeCommittedStateWithoutInitializingSDK {
    AppAccountService *account = AppAccountService.sharedInstance;
    NSMutableArray *identities = [NSMutableArray array];
    id observer = [NSNotificationCenter.defaultCenter addObserverForName:AppAccountDidChangeNotification object:account
                                                                   queue:nil
                                                              usingBlock:^(NSNotification *notification) {
                                                                  XCTAssertTrue(NSThread.isMainThread);
                                                                  [identities addObject:account.userId ?: @"guest"];
                                                              }];
    [account updateAuthenticatedUserId:@"account-a"];
    [account updateAuthenticatedUserId:@"account-a"];
    [account updateAuthenticatedUserId:@"account-b"];
    [account logout];
    [account logout];
    [NSNotificationCenter.defaultCenter removeObserver:observer];
    XCTAssertEqualObjects(identities, (@[ @"account-a", @"account-b", @"guest" ]));
    XCTAssertNil([self.service playbackSnapshot]);
}

/// 等待用户可见身份文字，验证初始化查询和事件处理，而不是通过额外查询身份掩盖页面漏更新。
- (void)waitForIdentityText:(NSString *)text web:(WKWebView *)web {
    __block BOOL matches = NO;
    [self waitUntil:^BOOL {
        [web evaluateJavaScript:@"document.getElementById('identity')?.textContent"
              completionHandler:^(id result, NSError *error) {
                  matches = !error && [result isEqual:text];
              }];
        return matches;
    }];
}

- (void)testAccountChangesBeforeOpeningAndWhileClosedAppearOnReopen {
    AppAccountService *account = AppAccountService.sharedInstance;
    [account updateAuthenticatedUserId:@"account-a"];
    [self configure];
    WKWebView *web = [self openFrom:self.originalRoot];
    [self waitForIdentityText:@"用户：account-a" web:web];
    [account updateAuthenticatedUserId:@"account-b"];
    [self waitForIdentityText:@"用户：account-b" web:web];
    [self closeFrom:self.originalRoot];
    [account updateAuthenticatedUserId:@"account-c"];
    web = [self openFrom:self.originalRoot];
    [self waitForIdentityText:@"用户：account-c" web:web];
    [self closeFrom:self.originalRoot];
    [account logout];
    web = [self openFrom:self.originalRoot];
    [self waitForIdentityText:@"游客" web:web];
    XCTAssertEqualObjects([self runJavaScript:@"return (await call('xhSnckGetUserInfo')).guest;" web:web], @YES);
}

@end
