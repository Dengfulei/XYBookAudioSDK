// 按容器尺寸验证本地 H5 布局，不依赖设备型号分支或宿主的 WebView 集成。
#import <XCTest/XCTest.h>
#import <WebKit/WebKit.h>

@interface XYBookAudioLayoutTests : XCTestCase <WKNavigationDelegate>

@property (nonatomic, strong) XCTestExpectation *loaded;

@end

@implementation XYBookAudioLayoutTests

- (void)webView:(WKWebView *)webView didFinishNavigation:(WKNavigation *)navigation {
    [self.loaded fulfill];
}

- (void)webView:(WKWebView *)webView
    didFailProvisionalNavigation:(WKNavigation *)navigation
                       withError:(NSError *)error {
    XCTFail(@"Fixture failed to load: %@", error);
    [self.loaded fulfill];
}

/// 覆盖标准与大屏手机、展开容器、iPad mini 和 iPad Pro 尺寸，确保底部操作区可见且无溢出。
- (void)testFixtureFitsFiveContainerSizes {
    NSURL *entry = [[NSBundle bundleForClass:self.class] URLForResource:@"index" withExtension:@"html"
                                                           subdirectory:@"Fixture"];
    NSError *error = nil;
    NSString *HTML = [NSString stringWithContentsOfURL:entry encoding:NSUTF8StringEncoding error:&error];
    XCTAssertNil(error);
    // 桥接行为由独立测试覆盖；此处仅验证测试页面自身的结构和样式。
    HTML = [HTML stringByReplacingOccurrencesOfString:@"<script src=\"fixture.js\"></script>" withString:@""];
    NSArray<NSValue *> *sizes = @[
        [NSValue valueWithCGSize:CGSizeMake(390, 844)], [NSValue valueWithCGSize:CGSizeMake(430, 932)],
        [NSValue valueWithCGSize:CGSizeMake(700, 800)], [NSValue valueWithCGSize:CGSizeMake(744, 1133)],
        [NSValue valueWithCGSize:CGSizeMake(1024, 1366)]
    ];
    for (NSValue *value in sizes) {
        // 每次使用新容器，避免上一次尺寸调整尚未提交时测得 WebKit 的过渡布局。
        WKWebView *web = [[WKWebView alloc] initWithFrame:(CGRect){CGPointZero, value.CGSizeValue}];
        web.navigationDelegate = self;
        web.scrollView.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentNever;
        [UIApplication.sharedApplication.delegate.window addSubview:web];
        self.loaded = [self expectationWithDescription:@"fixture layout loaded"];
        [web loadHTMLString:HTML baseURL:entry.URLByDeletingLastPathComponent];
        [self waitForExpectations:@[ self.loaded ] timeout:10];
        XCTestExpectation *measured = [self expectationWithDescription:NSStringFromCGSize(value.CGSizeValue)];
        NSString *script =
            @"await new Promise(resolve=>requestAnimationFrame(()=>requestAnimationFrame(resolve)));const footer=document.querySelector('footer').getBoundingClientRect();return {width:innerWidth,height:innerHeight,scroll:document.documentElement.scrollWidth,left:footer.left,right:footer.right,bottom:footer.bottom,top:footer.top};";
        [web callAsyncJavaScript:script arguments:@{} inFrame:nil inContentWorld:WKContentWorld.pageWorld
               completionHandler:^(NSDictionary *metrics, NSError *failure) {
                   XCTAssertNil(failure);
                   XCTAssertEqualWithAccuracy([metrics[@"width"] doubleValue], value.CGSizeValue.width, 1);
                   XCTAssertLessThanOrEqual([metrics[@"scroll"] doubleValue], [metrics[@"width"] doubleValue] + 1);
                   XCTAssertGreaterThanOrEqual([metrics[@"left"] doubleValue], 0);
                   XCTAssertLessThanOrEqual([metrics[@"right"] doubleValue], [metrics[@"width"] doubleValue] + 1);
                   XCTAssertGreaterThanOrEqual([metrics[@"top"] doubleValue], 0);
                   XCTAssertEqualWithAccuracy([metrics[@"bottom"] doubleValue], [metrics[@"height"] doubleValue], 1);
                   [measured fulfill];
               }];
        [self waitForExpectations:@[ measured ] timeout:5];
        [web removeFromSuperview];
    }
}

@end
