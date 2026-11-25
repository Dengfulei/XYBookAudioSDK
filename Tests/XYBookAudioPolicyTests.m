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

@interface XYBookAudioPaymentTestHistory : NSObject
@property (nonatomic, strong) id currentItem;
@end

@implementation XYBookAudioPaymentTestHistory
@end

@interface XYBookAudioPaymentTestWebView : XYBookAudioBridgeWebView
@property (nonatomic, strong) NSURLRequest *loadedRequest;
@property (nonatomic, strong) XYBookAudioPaymentTestHistory *history;
@end

@implementation XYBookAudioPaymentTestWebView
- (WKBackForwardList *)backForwardList {
    return (WKBackForwardList *)self.history;
}
- (WKNavigation *)loadRequest:(NSURLRequest *)request {
    self.loadedRequest = request;
    return nil;
}
@end

@interface XYBookAudioPaymentTestPage : XYBookAudioWebViewController
@property (nonatomic, strong) NSURL *openedURL;
@property (nonatomic) NSUInteger openCount;
@end

@implementation XYBookAudioPaymentTestPage
- (BOOL)isPaymentCheckoutAction:(WKNavigationAction *)action {
    return action.sourceFrame.isMainFrame;
}
- (void)openPaymentURL:(NSURL *)URL {
    self.openedURL = URL;
    self.openCount++;
}
@end

@interface XYBookAudioPolicyTests : XCTestCase

@end

@implementation XYBookAudioPolicyTests

- (void)testWeChatNavigationReissuesOnceAndAllowsTheNextPayment {
    NSURL *checkout = [NSURL URLWithString:@"https://merchant.example/checkout"];
    XYBookAudioConfiguration *configuration = [[XYBookAudioConfiguration alloc] initWithHostIdentifier:@"host"
                                                                                             entryURL:checkout];
    XYBookAudioPaymentConfiguration *payment = [XYBookAudioPaymentConfiguration new];
    payment.wechatReturnScheme = @"merchant.wechat";
    configuration.payment = payment;
    XYBookAudioPaymentTestPage *page = [[XYBookAudioPaymentTestPage alloc] initWithSDK:nil
        configuration:configuration entryURL:checkout windowRouter:nil logger:nil];
    XYBookAudioPaymentTestWebView *webView = [[XYBookAudioPaymentTestWebView alloc] initWithFrame:CGRectZero
                                                                    configuration:[WKWebViewConfiguration new]];
    webView.history = [XYBookAudioPaymentTestHistory new];
    webView.history.currentItem = [NSObject new];
    [page setValue:webView forKey:@"webView"];

    XYBookAudioPaymentTestAction *action = [XYBookAudioPaymentTestAction new];
    action.sourceFrame = [XYBookAudioPaymentTestFrame new];
    action.targetFrame = [XYBookAudioPaymentTestFrame new];
    action.sourceFrame.mainFrame = YES;
    action.targetFrame.mainFrame = YES;
    action.sourceFrame.request = [NSURLRequest requestWithURL:checkout];
    NSURL *gateway = [NSURL URLWithString:
        @"https://wx.tenpay.com/cgi-bin/mmpayweb-bin/checkmweb?token=test&sign=abc%2bdef%2F%3D"];
    NSString *gatewayWithRedirect = [gateway.absoluteString stringByAppendingString:
        @"&redirect_url=https%3A%2F%2Fmerchant.example%2Fcheckout%3FpayOrder%3Dtest%23%2F"];
    action.request = [NSURLRequest requestWithURL:[NSURL URLWithString:gatewayWithRedirect]];
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
    action.sourceFrame.request = [NSURLRequest requestWithURL:gateway];
    action.request = [NSURLRequest requestWithURL:[NSURL URLWithString:@"weixin://wap/pay?token=test"]];
    XCTAssertEqual(decide(), WKNavigationActionPolicyCancel);
    XCTAssertEqualObjects(page.openedURL, action.request.URL);
    XCTAssertEqual(decide(), WKNavigationActionPolicyCancel);
    XCTAssertEqual(page.openCount, 1u);

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
}

- (void)testWeChatGatewayPreservesOtherReturnURLs {
    NSURL *entry = [NSURL URLWithString:@"https://merchant.example/checkout"];
    NSString *base = @"https://wx.tenpay.com/cgi-bin/mmpayweb-bin/checkmweb?token=test";
    for (NSString *suffix in @[
        @"&redirect_url=https%3A%2F%2Fmerchant.example%2Freceipt",
        @"&redirect_url=https%3A%2F%2Fother.example%2Fcheckout",
        @"&redirect_url=https%3A%2F%2Fmerchant.example%2Fcheckout&sign=abc%2bdef",
        @"&redirect_url="
    ]) {
        NSURL *URL = [NSURL URLWithString:[base stringByAppendingString:suffix]];
        XCTAssertEqualObjects([XYBookAudioPaymentLinks wechatGatewayURLFromURL:URL removingReturnToEntryURL:entry], URL);
    }
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
