// 使用可控的连续时钟，验证队列输入的严格校验与定时关闭语义。
#import <XCTest/XCTest.h>
#import "XYBookAudioQueue.h"
#import "XYBookAudioSleepTimer.h"
#import "XYBookAudioPaymentLinks.h"
#import "XYBookAudioBridgeWebView.h"
#import "XYBookAudioWebViewController.h"

@interface XYBookAudioPaymentTestFrame : NSObject
@property (nonatomic, getter=isMainFrame) BOOL mainFrame;
@property (nonatomic, strong) NSURLRequest *request;
@end

@implementation XYBookAudioPaymentTestFrame
@end

@interface XYBookAudioPaymentTestAction : NSObject
@property (nonatomic, strong) XYBookAudioPaymentTestFrame *sourceFrame;
@property (nonatomic, strong) XYBookAudioPaymentTestFrame *targetFrame;
@property (nonatomic, strong) NSURLRequest *request;
@end

@implementation XYBookAudioPaymentTestAction
@end

@interface XYBookAudioPaymentTestHistoryItem : NSObject
@property (nonatomic, strong) NSURL *URL;
@end

@implementation XYBookAudioPaymentTestHistoryItem
@end

@interface XYBookAudioPaymentTestHistory : NSObject
@property (nonatomic, strong) XYBookAudioPaymentTestHistoryItem *currentItem;
@end

@implementation XYBookAudioPaymentTestHistory
@end

@interface XYBookAudioPaymentTestWebView : XYBookAudioBridgeWebView
@property (nonatomic, strong) NSURLRequest *loadedRequest;
@property (nonatomic, strong) XYBookAudioPaymentTestHistory *history;
@property (nonatomic) NSUInteger loadCount;
@end

@implementation XYBookAudioPaymentTestWebView
- (WKBackForwardList *)backForwardList {
    return (WKBackForwardList *)self.history;
}

- (WKNavigation *)goToBackForwardListItem:(WKBackForwardListItem *)item {
    self.history.currentItem = (XYBookAudioPaymentTestHistoryItem *)item;
    return nil;
}

- (WKNavigation *)loadRequest:(NSURLRequest *)request {
    self.loadedRequest = request;
    self.loadCount++;
    return nil;
}
@end

@interface XYBookAudioPaymentTestPage : XYBookAudioWebViewController
@property (nonatomic, strong) NSURL *openedURL;
@property (nonatomic) NSUInteger openCount;
@property (nonatomic, copy) void (^openCompletion)(BOOL success);
@end

@implementation XYBookAudioPaymentTestPage

- (BOOL)isPaymentCheckoutAction:(WKNavigationAction *)action {
    NSURL *entry = [self valueForKey:@"entryURL"];
    return action.sourceFrame.isMainFrame &&
           [XYBookAudioPaymentLinks checkoutURL:action.sourceFrame.request.URL matchesEntryURL:entry];
}

- (void)openPaymentURL:(NSURL *)URL completion:(void (^)(BOOL success))completion {
    self.openedURL = URL;
    self.openCount++;
    self.openCompletion = completion;
}
@end

@interface XYBookAudioPolicyTests : XCTestCase

@end

@implementation XYBookAudioPolicyTests

- (void)testLegacyWeChatRestoresCheckoutAndAllowsTheNextPaymentWithoutLoadingReturnURL {
    NSURL *checkout = [NSURL URLWithString:@"https://merchant.example/checkout"];
    XYBookAudioConfiguration *configuration = [[XYBookAudioConfiguration alloc] initWithHostIdentifier:@"host"
                                                                                             entryURL:checkout];
    XYBookAudioPaymentConfiguration *payment = [XYBookAudioPaymentConfiguration new];
    payment.wechatReturnScheme = @"merchant.wechat";
    payment.usesLegacyWeChatPaymentFlow = YES;
    configuration.payment = payment;
    XYBookAudioPaymentTestPage *page = [[XYBookAudioPaymentTestPage alloc] initWithSDK:nil
        configuration:configuration entryURL:checkout windowRouter:nil logger:nil];
    UIWindow *window = UIApplication.sharedApplication.delegate.window;
    UIWindowScene *scene = window.windowScene;
    XCTAssertNotNil(scene);
    page.view = [UIView new];
    [window addSubview:page.view];
    XYBookAudioPaymentTestWebView *webView = [[XYBookAudioPaymentTestWebView alloc] initWithFrame:CGRectZero
                                                                    configuration:[WKWebViewConfiguration new]];
    webView.history = [XYBookAudioPaymentTestHistory new];
    XYBookAudioPaymentTestHistoryItem *checkoutItem = [XYBookAudioPaymentTestHistoryItem new];
    checkoutItem.URL = checkout;
    webView.history.currentItem = checkoutItem;
    [page setValue:webView forKey:@"webView"];

    XYBookAudioPaymentTestAction *action = [XYBookAudioPaymentTestAction new];
    action.sourceFrame = [XYBookAudioPaymentTestFrame new];
    action.targetFrame = [XYBookAudioPaymentTestFrame new];
    action.sourceFrame.mainFrame = YES;
    action.targetFrame.mainFrame = YES;
    action.sourceFrame.request = [NSURLRequest requestWithURL:checkout];
    NSURL *gateway = [NSURL URLWithString:@"https://wx.tenpay.com/cgi-bin/mmpayweb-bin/checkmweb?"
                                         "prepay_id=test&ct=1&sign=abc%2bdef%2F%3D&package=one%2520"];
    NSString *redirectQuery = @"&redirect_url=https%3A%2F%2Fmerchant.example%2Fcheckout"
                               "%3FpayOrder%3Da%252Bb%23%2Fresult%3Ffrom%3Dwx";
    NSString *gatewayWithRedirect = [gateway.absoluteString stringByAppendingString:redirectQuery];
    NSMutableURLRequest *original = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:gatewayWithRedirect]];
    [original setValue:@"https://merchant.example/" forHTTPHeaderField:@"Referer"];
    action.request = original;
    WKNavigationActionPolicy (^decide)(void) = ^{
        __block WKNavigationActionPolicy policy = -1;
        [(id<WKNavigationDelegate>)page webView:webView decidePolicyForNavigationAction:(WKNavigationAction *)action
                                decisionHandler:^(WKNavigationActionPolicy result) { policy = result; }];
        return policy;
    };

    XCTAssertEqual(decide(), WKNavigationActionPolicyCancel);
    XCTAssertEqualObjects(webView.loadedRequest.URL.absoluteString, gateway.absoluteString);
    XCTAssertEqualObjects([webView.loadedRequest valueForHTTPHeaderField:@"Referer"], @"merchant.wechat://");
    action.request = webView.loadedRequest;
    XCTAssertEqual(decide(), WKNavigationActionPolicyAllow);
    XCTAssertEqual(decide(), WKNavigationActionPolicyCancel);
    action.request = [NSURLRequest requestWithURL:[NSURL URLWithString:@"weixin://wap/pay?token=test"]];
    action.sourceFrame.request = [NSURLRequest requestWithURL:[NSURL URLWithString:@"https://other.example/"]];
    XCTAssertEqual(decide(), WKNavigationActionPolicyCancel);
    XCTAssertEqual(page.openCount, 0u);
    XYBookAudioPaymentTestHistoryItem *gatewayItem = [XYBookAudioPaymentTestHistoryItem new];
    gatewayItem.URL = gateway;
    webView.history.currentItem = gatewayItem;
    action.sourceFrame.request = [NSURLRequest requestWithURL:gateway];
    XCTAssertEqual(decide(), WKNavigationActionPolicyCancel);
    XCTAssertEqualObjects(page.openedURL, action.request.URL);
    XCTAssertEqualObjects(webView.history.currentItem, checkoutItem);
    XCTAssertNil(page.openCompletion);
    XCTAssertEqual(decide(), WKNavigationActionPolicyCancel);
    XCTAssertEqual(page.openCount, 1u);

    NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
    [center postNotificationName:UISceneDidEnterBackgroundNotification object:scene];
    [center postNotificationName:UISceneDidActivateNotification object:scene];
    XCTAssertEqual(webView.loadCount, 1u);
    XCTAssertEqualObjects(webView.history.currentItem, checkoutItem);

    NSURL *nextGateway = [NSURL URLWithString:@"https://wx.tenpay.com/cgi-bin/mmpayweb-bin/checkmweb?token=next"];
    action.sourceFrame.request = [NSURLRequest requestWithURL:checkout];
    action.request = [NSURLRequest requestWithURL:nextGateway];
    XCTAssertEqual(decide(), WKNavigationActionPolicyCancel);
    XCTAssertEqualObjects(webView.loadedRequest.URL, nextGateway);
    action.request = webView.loadedRequest;
    XCTAssertEqual(decide(), WKNavigationActionPolicyAllow);
    action.sourceFrame.request = [NSURLRequest requestWithURL:nextGateway];
    action.request = [NSURLRequest requestWithURL:[NSURL URLWithString:@"weixin://wap/pay?token=next"]];
    XCTAssertEqual(decide(), WKNavigationActionPolicyCancel);
    XCTAssertEqual(page.openCount, 2u);
    XCTAssertNil(page.openCompletion);
    [page.view removeFromSuperview];
}

- (void)testWeChatGatewayPreservesInvalidReturnURLs {
    NSURL *entry = [NSURL URLWithString:@"https://merchant.example/checkout"];
    XYBookAudioConfiguration *configuration = [[XYBookAudioConfiguration alloc] initWithHostIdentifier:@"host"
                                                                                              entryURL:entry];
    XYBookAudioPaymentConfiguration *payment = [XYBookAudioPaymentConfiguration new];
    payment.wechatReturnScheme = @"merchant.wechat";
    configuration.payment = payment;
    NSString *base = @"https://wx.tenpay.com/cgi-bin/mmpayweb-bin/checkmweb?token=test";
    for (NSString *suffix in @[
             @"", @"&redirect_url=https%3A%2F%2Fmerchant.example%2Freceipt",
             @"&redirect_url=https%3A%2F%2Fother.example%2Fcheckout",
             @"&redirect_url=https%3A%2F%2Fmerchant.example%3A444%2Fcheckout",
             @"&redirect_url=http%3A%2F%2Fmerchant.example%2Fcheckout",
             @"&redirect_url=https%253A%252F%252Fmerchant.example%252Fcheckout",
             @"&redirect_url=https%3A%2F%2Fmerchant.example%2Fcheckout&%72edirect_url=other", @"&redirect_url="
         ]) {
        NSURL *URL = [NSURL URLWithString:[base stringByAppendingString:suffix]];
        NSURL *returnURL = entry;
        NSURLRequest *reload =
            [XYBookAudioPaymentLinks wechatGatewayRequestFromRequest:[NSURLRequest requestWithURL:URL]
                                                       configuration:configuration
                                                           returnURL:&returnURL];
        XCTAssertEqualObjects(reload.URL, URL);
        XCTAssertNil(returnURL);
    }
}

- (void)testWeChatReferenceUsesRedirectHostWhenItCannotTakeOverTheReturn {
    NSURL *entry = [NSURL URLWithString:@"https://merchant.example/checkout"];
    XYBookAudioConfiguration *configuration = [[XYBookAudioConfiguration alloc] initWithHostIdentifier:@"host"
                                                                                              entryURL:entry];
    XYBookAudioPaymentConfiguration *payment = [XYBookAudioPaymentConfiguration new];
    payment.wechatReturnScheme = @"merchant.wechat";
    payment.usesLegacyWeChatPaymentFlow = NO;
    configuration.payment = payment;
    NSString *base = @"https://wx.tenpay.com/cgi-bin/mmpayweb-bin/checkmweb?sign=abc%2bdef"
                      "&redirect_url=https%3A%2F%2Flegacy.example%2Fcheckout"
                      "&referer=https%3A%2F%2Fmerchant.web%2Fcashier";
    NSArray<NSString *> *appReferers = @[ @"merchant.app%3A%2F%2F", @"invalid%0D%0Aheader", @"" ];
    for (NSString *appReferer in appReferers) {
        NSURL *URL = [NSURL URLWithString:[base stringByAppendingFormat:@"&appReferer=%@", appReferer]];
        NSURL *returnURL;
        NSURLRequest *reload =
            [XYBookAudioPaymentLinks wechatGatewayRequestFromRequest:[NSURLRequest requestWithURL:URL]
                                                       configuration:configuration
                                                           returnURL:&returnURL];
        XCTAssertEqualObjects(reload.URL.absoluteString, URL.absoluteString);
        XCTAssertNil(returnURL);
        XCTAssertEqualObjects([reload valueForHTTPHeaderField:@"Referer"],
                              [appReferer hasPrefix:@"merchant"] ? @"merchant.app://" : @"legacy.example://");
    }
}

- (void)testWeChatGatewayRequestsPreserveParametersAndSetRefererForEachFlow {
    NSURL *entry = [NSURL URLWithString:@"https://merchant.example/checkout"];
    XYBookAudioConfiguration *configuration = [[XYBookAudioConfiguration alloc] initWithHostIdentifier:@"host"
                                                                                              entryURL:entry];
    XYBookAudioPaymentConfiguration *payment = [XYBookAudioPaymentConfiguration new];
    payment.wechatReturnScheme = @"merchant.wechat";
    configuration.payment = payment;

    NSString *gatewayWithoutRedirect =
        @"https://wx.tenpay.com/cgi-bin/mmpayweb-bin/checkmweb?token=test&sign=abc%2bdef%2F%3D"
         "&referer=https%3A%2F%2Fref.example"
         "&appReferer=https%253A%252F%252Fapp.example%252F%25E6%2594%25AF%25E4%25BB%2598";
    NSURL *gateway = [NSURL
        URLWithString:
            [gatewayWithoutRedirect
                stringByAppendingString:
                    @"&redirect_url=https%3A%2F%2Fmerchant.example%2Fcheckout%23%2F%3FhideTopView%3D1%26payOrder%3Dtest"]];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:gateway];
    [request setValue:@"fixture" forHTTPHeaderField:@"X-Checkout"];
    request.timeoutInterval = 23;

    NSURL *returnURL;
    NSURLRequest *reload = [XYBookAudioPaymentLinks wechatGatewayRequestFromRequest:request configuration:configuration
                                                                          returnURL:&returnURL];
    XCTAssertEqualObjects(reload.URL.absoluteString, gatewayWithoutRedirect);
    XCTAssertEqualObjects([reload valueForHTTPHeaderField:@"X-Checkout"], @"fixture");
    XCTAssertEqual(reload.timeoutInterval, 60);
    XCTAssertEqualObjects([reload valueForHTTPHeaderField:@"Referer"], @"app.example://");
    XCTAssertEqualObjects(returnURL.absoluteString, @"https://merchant.example/checkout#/?hideTopView=1&payOrder=test");

    NSURLRequest *legacy = [XYBookAudioPaymentLinks legacyWeChatGatewayRequestFromRequest:request
                                                                            configuration:configuration];
    XCTAssertEqualObjects(legacy.URL.absoluteString, gatewayWithoutRedirect);
    XCTAssertEqualObjects([legacy valueForHTTPHeaderField:@"X-Checkout"], @"fixture");
    XCTAssertEqual(legacy.timeoutInterval, 23);
    XCTAssertEqualObjects([legacy valueForHTTPHeaderField:@"Referer"], @"merchant.wechat://");

    for (NSString *query in @[
             @"redirect_url=https%3A%2F%2Fmerchant.example%2Fcheckout&sign=abc%2bdef",
             @"sign=abc%2bdef&redirect_url=https%3A%2F%2Fmerchant.example%2Fcheckout%2Freceipt",
             @"sign=abc%2bdef&redirect_url=https%3A%2F%2Fother.example%2Fcheckout",
         ]) {
        NSURL *URL = [NSURL
            URLWithString:[@"https://wx.tenpay.com/cgi-bin/mmpayweb-bin/checkmweb?" stringByAppendingString:query]];
        NSURLRequest *legacy =
            [XYBookAudioPaymentLinks legacyWeChatGatewayRequestFromRequest:[NSURLRequest requestWithURL:URL]
                                                             configuration:configuration];
        XCTAssertEqualObjects(legacy.URL, URL);
    }
}

- (void)testLegacyWeChatFlowDefaultsToDisabledAndCopiesConfiguration {
    XYBookAudioPaymentConfiguration *payment = [XYBookAudioPaymentConfiguration new];
    XCTAssertFalse(payment.usesLegacyWeChatPaymentFlow);

    payment.usesLegacyWeChatPaymentFlow = YES;
    XYBookAudioPaymentConfiguration *copy = [payment copy];

    payment.usesLegacyWeChatPaymentFlow = NO;
    XCTAssertTrue(copy.usesLegacyWeChatPaymentFlow);
}

- (void)testWeChatClearsPendingReturnOnFailureReplacementAndPageClosure {
    NSURL *checkout = [NSURL URLWithString:@"https://merchant.example/checkout"];
    XYBookAudioConfiguration *configuration = [[XYBookAudioConfiguration alloc] initWithHostIdentifier:@"host"
                                                                                              entryURL:checkout];
    XYBookAudioPaymentConfiguration *payment = [XYBookAudioPaymentConfiguration new];
    payment.wechatReturnScheme = @"merchant.wechat";
    payment.usesLegacyWeChatPaymentFlow = NO;
    configuration.payment = payment;
    XYBookAudioPaymentTestPage *page = [[XYBookAudioPaymentTestPage alloc] initWithSDK:nil configuration:configuration
                                                                              entryURL:checkout
                                                                          windowRouter:nil
                                                                                logger:nil];
    UIWindow *window = UIApplication.sharedApplication.delegate.window;
    UIWindowScene *scene = window.windowScene;
    XCTAssertNotNil(scene);
    page.view = [UIView new];
    [window addSubview:page.view];
    XYBookAudioPaymentTestWebView *webView =
        [[XYBookAudioPaymentTestWebView alloc] initWithFrame:CGRectZero configuration:[WKWebViewConfiguration new]];
    [page setValue:webView forKey:@"webView"];

    XYBookAudioPaymentTestAction *action = [XYBookAudioPaymentTestAction new];
    void (^decide)(WKNavigationActionPolicy) = ^(WKNavigationActionPolicy expected) {
        [(id<WKNavigationDelegate>)page webView:webView decidePolicyForNavigationAction:(WKNavigationAction *)action
                                decisionHandler:^(WKNavigationActionPolicy policy) {
                                    XCTAssertEqual(policy, expected);
                                }];
    };
    void (^startPayment)(NSString *) = ^(NSString *order) {
        NSString *gateway =
            [NSString stringWithFormat:@"https://wx.tenpay.com/cgi-bin/mmpayweb-bin/checkmweb?prepay_id=%@", order];
        NSString *signature = @"&sign=abc%2bdef";
        NSString *redirect = [NSString stringWithFormat:@"&redirect_url=https%%3A%%2F%%2Fmerchant.example%%2Fcheckout"
                                                         "%%3FpayOrder%%3D%@%%23%%2Fresult",
                                                        order];
        NSString *link = [@[ gateway, redirect, signature ] componentsJoinedByString:@""];
        action.request = [NSURLRequest requestWithURL:[NSURL URLWithString:link]];
        decide(WKNavigationActionPolicyCancel);
        XCTAssertEqualObjects(webView.loadedRequest.URL.absoluteString, [gateway stringByAppendingString:signature]);
        action.request = webView.loadedRequest;
        decide(WKNavigationActionPolicyAllow);
        action.request = [NSURLRequest requestWithURL:[NSURL URLWithString:@"weixin://wap/pay"]];
        decide(WKNavigationActionPolicyCancel);
        XCTAssertNotNil(page.openCompletion);
    };
    void (^returnToScene)(void) = ^{
        [NSNotificationCenter.defaultCenter postNotificationName:UISceneDidEnterBackgroundNotification object:scene];
        [NSNotificationCenter.defaultCenter postNotificationName:UISceneDidActivateNotification object:scene];
    };

    startPayment(@"failed");
    page.openCompletion(NO);
    returnToScene();
    XCTAssertEqual(webView.loadCount, 1u);

    startPayment(@"old");
    void (^oldCompletion)(BOOL) = page.openCompletion;
    startPayment(@"next");
    oldCompletion(NO);
    [NSNotificationCenter.defaultCenter postNotificationName:UISceneDidActivateNotification object:scene];
    XCTAssertEqual(webView.loadCount, 3u);
    returnToScene();
    XCTAssertEqual(webView.loadCount, 4u);
    page.openCompletion(YES);
    XCTAssertEqual(webView.loadCount, 4u);
    XCTAssertEqualObjects(webView.loadedRequest.URL.absoluteString,
                          @"https://merchant.example/checkout?payOrder=next#/result");

    action.request = [NSURLRequest requestWithURL:[NSURL URLWithString:@"weixin://wap/pay?token=direct"]];
    decide(WKNavigationActionPolicyCancel);
    XCTAssertEqualObjects(page.openedURL, action.request.URL);
    XCTAssertNil(page.openCompletion);

    startPayment(@"closed");
    [page invalidatePage];
    page.openCompletion(YES);
    returnToScene();
    XCTAssertEqual(webView.loadCount, 5u);
    [page.view removeFromSuperview];
}

- (void)testWeChatReferenceWithoutRedirectClearsThePreviousReturn {
    NSURL *checkout = [NSURL URLWithString:@"https://merchant.example/checkout"];
    XYBookAudioConfiguration *configuration = [[XYBookAudioConfiguration alloc] initWithHostIdentifier:@"host"
                                                                                              entryURL:checkout];
    XYBookAudioPaymentConfiguration *payment = [XYBookAudioPaymentConfiguration new];
    payment.wechatReturnScheme = @"merchant.wechat";
    payment.usesLegacyWeChatPaymentFlow = NO;
    configuration.payment = payment;
    XYBookAudioPaymentTestPage *page = [[XYBookAudioPaymentTestPage alloc] initWithSDK:nil configuration:configuration
                                                                              entryURL:checkout
                                                                          windowRouter:nil
                                                                                logger:nil];
    UIWindow *window = UIApplication.sharedApplication.delegate.window;
    XCTAssertNotNil(window.windowScene);
    page.view = [UIView new];
    [window addSubview:page.view];
    XYBookAudioPaymentTestWebView *webView =
        [[XYBookAudioPaymentTestWebView alloc] initWithFrame:CGRectZero configuration:[WKWebViewConfiguration new]];
    [page setValue:webView forKey:@"webView"];

    XYBookAudioPaymentTestAction *action = [XYBookAudioPaymentTestAction new];
    void (^decide)(WKNavigationActionPolicy) = ^(WKNavigationActionPolicy expected) {
        [(id<WKNavigationDelegate>)page webView:webView decidePolicyForNavigationAction:(WKNavigationAction *)action
                                decisionHandler:^(WKNavigationActionPolicy policy) {
                                    XCTAssertEqual(policy, expected);
                                }];
    };
    NSURL *previous =
        [NSURL URLWithString:@"https://wx.tenpay.com/cgi-bin/mmpayweb-bin/checkmweb?prepay_id=previous"
                              "&redirect_url=https%3A%2F%2Fmerchant.example%2Fcheckout%3FpayOrder%3Dprevious"];
    action.request = [NSURLRequest requestWithURL:previous];
    decide(WKNavigationActionPolicyCancel);

    NSString *base = @"https://wx.tenpay.com/cgi-bin/mmpayweb-bin/checkmweb?prepay_id=next"
                      "&sign=abc%2b%2F%3D&package=one%2520";
    NSArray<NSArray<NSString *> *> *cases = @[
        @[ @"&appReferer=https%3A%2F%2Fapp.example&referer=https%3A%2F%2Fweb.example", @"app.example://" ],
        @[ @"&referer=https%3A%2F%2Fweb.example", @"web.example://" ],
        @[ @"", @"merchant.wechat://" ],
    ];
    for (NSArray<NSString *> *testCase in cases) {
        NSURL *gateway = [NSURL URLWithString:[base stringByAppendingString:testCase[0]]];
        NSUInteger loadsBeforePay = webView.loadCount;
        NSUInteger launchesBeforePay = page.openCount;
        action.request = [NSURLRequest requestWithURL:gateway];
        decide(WKNavigationActionPolicyCancel);
        XCTAssertEqualObjects(webView.loadedRequest.URL.absoluteString, gateway.absoluteString);
        XCTAssertEqualObjects([webView.loadedRequest valueForHTTPHeaderField:@"Referer"], testCase[1]);

        action.request = webView.loadedRequest;
        decide(WKNavigationActionPolicyAllow);
        action.request = [NSURLRequest requestWithURL:[NSURL URLWithString:@"weixin://wap/pay"]];
        decide(WKNavigationActionPolicyCancel);
        XCTAssertEqual(page.openCount, launchesBeforePay + 1);
        XCTAssertNil(page.openCompletion);
        [NSNotificationCenter.defaultCenter postNotificationName:UISceneDidEnterBackgroundNotification
                                                          object:window.windowScene];
        [NSNotificationCenter.defaultCenter postNotificationName:UISceneDidActivateNotification
                                                          object:window.windowScene];
        XCTAssertEqual(webView.loadCount, loadsBeforePay + 1);
    }
    [page.view removeFromSuperview];
}

- (void)testPaymentLinksMatchEndpointsExactly {
    NSDictionary<NSString *, NSNumber *> *types = @{
        @"https://wx.tenpay.com/cgi-bin/mmpayweb-bin/checkmweb?prepay_id=example" :
            @(XYBookAudioPaymentLinkTypeWeChatGateway),
        @"https://wx.tenpay.com.example.org/cgi-bin/mmpayweb-bin/checkmweb?prepay_id=example" :
            @(XYBookAudioPaymentLinkTypeNone),
        @"https://example.org/?next=https://wx.tenpay.com/cgi-bin/mmpayweb-bin/checkmweb?prepay_id=example" :
            @(XYBookAudioPaymentLinkTypeNone),
        @"weixin://wap/pay?example=1" : @(XYBookAudioPaymentLinkTypeWeChatApp),
        @"weixin://wap/pay-extra?example=1" : @(XYBookAudioPaymentLinkTypeNone),
        @"alipay://alipayclient/?payload=test" : @(XYBookAudioPaymentLinkTypeAlipayApp),
        @"alipay://alipayclient/other?payload=test" : @(XYBookAudioPaymentLinkTypeNone)
    };
    for (NSString *URL in types) {
        XCTAssertEqual([XYBookAudioPaymentLinks typeForURL:[NSURL URLWithString:URL]], types[URL].unsignedIntegerValue);
    }
}

- (void)testAlipayRewritesOnlyTheReturnSchemeAndRejectsMalformedPayloads {
    NSURLComponents *parts = [NSURLComponents componentsWithString:@"alipay://alipayclient/"];
    parts.percentEncodedQuery = @"%7B%22requestType%22%3A%22SafePay%22%2C%22fromAppUrlScheme%22%3A%22alipays%22%2C"
                                 "%22dataString%22%3A%22order%3Dhello%252Bworld%26sign%3Dx%2By%3D%22%7D";
    NSURL *rewritten = [XYBookAudioPaymentLinks alipayURLFromURL:parts.URL withReturnScheme:@"example.alipay"];
    NSURLComponents *parsed = [NSURLComponents componentsWithURL:rewritten resolvingAgainstBaseURL:NO];
    NSDictionary *payload = [NSJSONSerialization JSONObjectWithData:[parsed.query dataUsingEncoding:NSUTF8StringEncoding]
                                                            options:0 error:nil];
    XCTAssertEqualObjects(parsed.scheme, @"alipay");
    XCTAssertEqualObjects(parsed.host, @"alipayclient");
    XCTAssertEqualObjects(payload[@"requestType"], @"SafePay");
    XCTAssertEqualObjects(payload[@"fromAppUrlScheme"], @"example.alipay");
    XCTAssertEqualObjects(payload[@"dataString"], @"order=hello%2Bworld&sign=x+y=");
    XCTAssertNil([XYBookAudioPaymentLinks alipayURLFromURL:[NSURL URLWithString:@"alipay://alipayclient/?bad"]
                                         withReturnScheme:@"example.alipay"]);
    XCTAssertNil([XYBookAudioPaymentLinks alipayURLFromURL:[NSURL URLWithString:@"alipay://alipayclient/"]
                                         withReturnScheme:@"example.alipay"]);
}

- (void)testAlipayNavigationOpensSafePayWithTheConfiguredScheme {
    NSURL *entry = [NSURL URLWithString:@"https://merchant.example/checkout"];
    XYBookAudioConfiguration *configuration =
        [[XYBookAudioConfiguration alloc] initWithHostIdentifier:@"host" entryURL:entry];
    XYBookAudioPaymentConfiguration *payment = [XYBookAudioPaymentConfiguration new];
    payment.alipayReturnScheme = @"example.alipay";
    configuration.payment = payment;
    XYBookAudioPaymentTestPage *page = [[XYBookAudioPaymentTestPage alloc] initWithSDK:nil
        configuration:configuration entryURL:entry windowRouter:nil logger:nil];
    XYBookAudioPaymentTestWebView *webView = [[XYBookAudioPaymentTestWebView alloc] initWithFrame:CGRectZero
                                                                    configuration:[WKWebViewConfiguration new]];
    XYBookAudioPaymentTestAction *action = [XYBookAudioPaymentTestAction new];
    action.sourceFrame = [XYBookAudioPaymentTestFrame new];
    action.sourceFrame.request = [NSURLRequest requestWithURL:entry];
    NSURLComponents *link = [NSURLComponents componentsWithString:@"alipay://alipayclient/"];
    link.query = @"{\"requestType\":\"SafePay\",\"fromAppUrlScheme\":\"alipays\",\"dataString\":\"order%2Bsignature\"}";
    action.request = [NSURLRequest requestWithURL:link.URL];
    void (^decide)(void) = ^{
        [(id<WKNavigationDelegate>)page webView:webView decidePolicyForNavigationAction:(WKNavigationAction *)action
                                decisionHandler:^(WKNavigationActionPolicy result) {
            XCTAssertEqual(result, WKNavigationActionPolicyCancel);
        }];
    };
    decide();
    XCTAssertNil(page.openedURL);

    action.sourceFrame.mainFrame = YES;
    decide();
    XCTAssertEqual(page.openCount, 1u);
    NSURLComponents *opened = [NSURLComponents componentsWithURL:page.openedURL resolvingAgainstBaseURL:NO];
    NSDictionary *payload = [NSJSONSerialization JSONObjectWithData:[opened.query dataUsingEncoding:NSUTF8StringEncoding]
                                                            options:0 error:nil];
    XCTAssertEqualObjects(payload[@"fromAppUrlScheme"], @"example.alipay");
    XCTAssertEqualObjects(payload[@"dataString"], @"order%2Bsignature");
}

- (void)testPaymentConfigurationRequiresATrustedHTTPSEntryAndCopiesSchemes {
    NSURL *entry = [NSURL URLWithString:@"https://merchant.example/listening"];
    XYBookAudioConfiguration *configuration = [[XYBookAudioConfiguration alloc] initWithHostIdentifier:@"host"
                                                                                             entryURL:entry];
    XCTAssertTrue([configuration validate:nil]);
    XYBookAudioPaymentConfiguration *payment = [XYBookAudioPaymentConfiguration new];
    payment.wechatReturnScheme = @"merchant.wechat";
    payment.alipayReturnScheme = @"merchant.alipay";
    configuration.payment = payment;
    XCTAssertTrue([configuration validate:nil]);
    XCTAssertTrue([XYBookAudioPaymentLinks checkoutURL:[NSURL URLWithString:@"https://merchant.example/listening?order=1"]
                                       matchesEntryURL:entry]);
    XCTAssertFalse([XYBookAudioPaymentLinks checkoutURL:[NSURL URLWithString:@"https://merchant.example/listening/other"]
                                        matchesEntryURL:entry]);
    XYBookAudioConfiguration *copied = [configuration copy];
    configuration.entryURL = [NSURL fileURLWithPath:@"/fixture/index.html"];
    XCTAssertFalse([configuration validate:nil]);
    XCTAssertTrue([copied validate:nil]);
    XCTAssertEqualObjects(copied.payment.alipayReturnScheme, @"merchant.alipay");
    copied.payment.alipayReturnScheme = @"merchant.WECHAT";
    XCTAssertFalse([copied validate:nil]);
}

- (void)testCountIncludesCurrentChapterAndDeduplicatesCompletion {
    XYBookAudioSleepTimer *timer = [[XYBookAudioSleepTimer alloc] initWithClock:^{
        return 0.0;
    }];
    XCTAssertTrue(([timer configure:@{@"mode" : @"trackCount", @"count" : @2} hasCurrentChapter:YES error:nil]));
    XCTAssertEqual(timer.lastChange, XYBookAudioTimerChangeSet);
    NSUUID *first = NSUUID.UUID;
    XCTAssertFalse(([timer consumeNaturalCompletion:first]));
    XCTAssertFalse(([timer consumeNaturalCompletion:first]));
    XCTAssertEqualObjects([timer snapshot][@"remainingCount"], @1);
    XCTAssertEqual(timer.lastChange, XYBookAudioTimerChangeItemCompleted);
    XCTAssertTrue(([timer consumeNaturalCompletion:NSUUID.UUID]));
    XCTAssertEqualObjects([timer snapshot][@"mode"], @"off");
    XCTAssertFalse(([timer consumeNaturalCompletion:NSUUID.UUID]));
    XCTAssertEqual(timer.lastChange, XYBookAudioTimerChangeExpired);
}

- (void)testInvalidReplacementPreservesActiveTimer {
    XYBookAudioSleepTimer *timer = [[XYBookAudioSleepTimer alloc] initWithClock:^{
        return 0.0;
    }];
    XCTAssertTrue(([timer configure:@{@"mode" : @"trackCount", @"count" : @3} hasCurrentChapter:YES error:nil]));
    for (id value in @[ @0, @(-1), @1.5, @YES, @"3", NSNull.null ]) {
        NSError *error;
        XCTAssertFalse(([timer configure:@{@"mode" : @"trackCount", @"count" : value} hasCurrentChapter:YES
                                   error:&error]));
        XCTAssertNotNil(error);
        XCTAssertEqualObjects([timer snapshot][@"remainingCount"], @3);
    }
}

- (void)testDurationCountsSuspendedTimeAndExpiresOnlyOnce {
    __block NSTimeInterval now = 100;
    XYBookAudioSleepTimer *timer = [[XYBookAudioSleepTimer alloc] initWithClock:^{
        return now;
    }];
    XCTAssertTrue(([timer configure:@{@"mode" : @"duration", @"durationMs" : @900000} hasCurrentChapter:NO error:nil]));
    now += 899;
    XCTAssertFalse(([timer consumeDeadline]));
    XCTAssertEqualObjects([timer snapshot][@"remainingMs"], @1000);
    now += 61;
    XCTAssertTrue(([timer consumeDeadline]));
    XCTAssertFalse(([timer consumeDeadline]));
    XCTAssertEqual(timer.lastChange, XYBookAudioTimerChangeExpired);
    XCTAssertTrue(([timer configure:@{@"mode" : @"trackCount", @"count" : @2} hasCurrentChapter:YES error:nil]));
    XCTAssertEqual(timer.lastChange, XYBookAudioTimerChangeSet);
    [timer queueDidEnd];
    XCTAssertEqualObjects([timer snapshot][@"mode"], @"off");
    XCTAssertEqual(timer.lastChange, XYBookAudioTimerChangeQueueEnded);
}

- (void)testQueueRejectsDuplicateIdentifiersAndMissingLoginFlag {
    NSDictionary *chapter = @{@"chapterId" : @"one", @"title" : @"First", @"requiresLogin" : @NO};
    NSError *error;
    XCTAssertNil(([XYBookAudioQueue
        queueWithParameters:@{@"bookId" : @"book", @"title" : @"Book", @"chapters" : @[ chapter, chapter ]}
                      error:&error]));
    XCTAssertNotNil(error);
    XCTAssertNil(([XYBookAudioQueue queueWithParameters:@{
        @"bookId" : @"book",
        @"title" : @"Book",
        @"chapters" : @[ @{@"chapterId" : @"one", @"title" : @"First"} ]
    }
                                                  error:&error]));
}

- (void)testExplicitLocalSampleQueueCanDescribeBundledAudio {
    NSDictionary *chapter = @{
        @"chapterId" : @"one",
        @"title" : @"First",
        @"requiresLogin" : @YES,
        @"audioURL" : @"file:///fixture/tone.wav",
        @"durationMs" : @4000.25
    };
    NSError *error = nil;
    XYBookAudioQueue *queue =
        [XYBookAudioQueue queueWithParameters:@{@"bookId" : @"book", @"title" : @"Book", @"chapters" : @[ chapter ]}
                                        error:&error];
    XCTAssertNil(error);
    XCTAssertEqual(queue.chapters.count, 1u);
    XYBookAudioChapter *model = queue.chapters.firstObject;
    XCTAssertEqualObjects(model.chapterId, @"one");
    XCTAssertEqualObjects(model.title, @"First");
    XCTAssertTrue(model.requiresLogin);
    XCTAssertEqualObjects(model.audioURL, @"file:///fixture/tone.wav");
    XCTAssertEqualObjects(model.durationMs, @4000.25);
}

@end
