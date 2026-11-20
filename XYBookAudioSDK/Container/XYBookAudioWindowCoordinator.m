#import "XYBookAudioWindowCoordinator.h"
#import "XYBookAudioMessageProtocol.h"
#import "XYBookAudioWebViewController.h"

static void XYBookAudioAfterNavigationTransition(UINavigationController *navigation, dispatch_block_t work) {
    BOOL waiting = [navigation.transitionCoordinator
        animateAlongsideTransition:nil completion:^(id<UIViewControllerTransitionCoordinatorContext> context) {
            dispatch_async(dispatch_get_main_queue(), work);
        }];
    if (!waiting) {
        work();
    }
}

@interface XYBookAudioModalNavigationController : UINavigationController
@property (nonatomic, copy) dispatch_block_t didDismiss;
@end

@implementation XYBookAudioModalNavigationController

- (void)viewDidDisappear:(BOOL)animated {
    [super viewDidDisappear:animated];
    if (self.isBeingDismissed || !self.presentingViewController) {
        dispatch_block_t didDismiss = self.didDismiss;
        self.didDismiss = nil;
        if (didDismiss) {
            didDismiss();
        }
    }
}

@end

@interface XYBookAudioWindowCoordinator ()
@property (nonatomic, weak) XYBookAudioSDKManager *SDK;
@property (nonatomic, strong) XYBookAudioConfiguration *configuration;
@property (nonatomic, strong) XYBookAudioLogger *logger;
@property (nonatomic, weak, readwrite) UINavigationController *navigation;
@property (nonatomic, weak) XYBookAudioWebViewController *rootPage;
@property (nonatomic, strong) NSHashTable<XYBookAudioWebViewController *> *pages;
@property (nonatomic) XYBookAudioOpenStyle style;
@property (nonatomic) BOOL closing;
@end

@implementation XYBookAudioWindowCoordinator

- (instancetype)initWithSDK:(XYBookAudioSDKManager *)SDK
              configuration:(XYBookAudioConfiguration *)configuration
                     logger:(XYBookAudioLogger *)logger
                      style:(XYBookAudioOpenStyle)style {
    if ((self = [super init])) {
        _SDK = SDK;
        _configuration = configuration;
        _logger = logger;
        _style = style;
        _pages = [NSHashTable weakObjectsHashTable];
    }
    return self;
}

- (XYBookAudioWebViewController *)pageWithURL:(NSURL *)URL {
    XYBookAudioWebViewController *page = [[XYBookAudioWebViewController alloc] initWithSDK:self.SDK
                                                                             configuration:self.configuration
                                                                                  entryURL:URL
                                                                              windowRouter:self
                                                                                    logger:self.logger];
    [self.pages addObject:page];
    return page;
}

- (void)openFromViewController:(UIViewController *)controller completion:(void (^)(NSError *))completion {
    XYBookAudioWebViewController *root = [self pageWithURL:self.configuration.entryURL];
    self.rootPage = root;
    __weak typeof(self) weakSelf = self;
    if (self.style == XYBookAudioOpenStylePresent) {
        XYBookAudioModalNavigationController *navigation =
            [[XYBookAudioModalNavigationController alloc] initWithRootViewController:root];
        self.navigation = navigation;
        navigation.modalPresentationStyle = UIModalPresentationFullScreen;
        navigation.didDismiss = ^{
            [weakSelf finishClose];
        };
        [controller presentViewController:navigation animated:YES completion:^{
            [self finishOpeningRoot:root completion:completion];
        }];
        [self.logger write:XYBookAudioLogLevelInfo component:XYBookAudioLogPage message:@"Opening listening page."];
        return;
    }

    UINavigationController *navigation = controller.navigationController;
    self.navigation = navigation;
    root.didLeaveNavigation = ^{
        // UIKit 仍可能在更新导航栈，下一轮主线程再处理剩余 SDK 页面。
        dispatch_async(dispatch_get_main_queue(), ^{
            [weakSelf closeAllPages];
        });
    };
    [navigation pushViewController:root animated:YES];
    [self.logger write:XYBookAudioLogLevelInfo component:XYBookAudioLogPage message:@"Opening listening page."];
    XYBookAudioAfterNavigationTransition(navigation, ^{
        [self finishOpeningRoot:root completion:completion];
    });
}

- (void)finishOpeningRoot:(UIViewController *)root completion:(void (^)(NSError *))completion {
    if (self.closing || ![self.navigation.viewControllers containsObject:root]) {
        [self closeAllPages];
        completion(XYBookAudioError(XYBookAudioBusy, @"The listening page was not opened."));
    } else {
        completion(nil);
    }
}

- (UIViewController *)topPage {
    UIViewController *page = self.navigation.topViewController;
    return !self.closing && page && [self.pages containsObject:(XYBookAudioWebViewController *)page] ? page : nil;
}

- (NSError *)navigationErrorFromPage:(UIViewController *)page {
    UINavigationController *navigation = self.navigation;
    if (page != self.topPage || !page.viewIfLoaded.window || navigation.isBeingDismissed ||
        navigation.transitionCoordinator || navigation.presentedViewController || page.presentedViewController) {
        return XYBookAudioError(XYBookAudioBusy, @"The current web window is not available for navigation.");
    }
    return nil;
}

- (NSError *)openWindowWithURL:(NSURL *)URL title:(NSString *)title fromPage:(UIViewController *)page {
    NSError *error = [self navigationErrorFromPage:page];
    if (error) {
        return error;
    }
    if (![self.configuration allowsURL:URL]) {
        return XYBookAudioError(XYBookAudioUntrustedSource, @"The new window URL is outside the trusted scope.");
    }
    UIViewController *child = [self pageWithURL:URL];
    child.title = title;
    [self.navigation pushViewController:child animated:YES];
    [self.logger write:XYBookAudioLogLevelInfo component:XYBookAudioLogPage message:@"New web window opened."];
    return nil;
}

- (NSError *)closeWindowFromPage:(UIViewController *)page beforeClose:(dispatch_block_t)beforeClose {
    NSError *error = [self navigationErrorFromPage:page];
    if (error) {
        return error;
    }
    if (beforeClose) {
        beforeClose();
    }
    UINavigationController *navigation = self.navigation;
    if (page == self.rootPage && (self.style == XYBookAudioOpenStylePresent || navigation.viewControllers.count == 1)) {
        [self closeAllPages];
    } else {
        [navigation popViewControllerAnimated:YES];
    }
    return nil;
}

- (void)closeAllPages {
    if (self.closing) {
        return;
    }
    self.closing = YES;
    [self invalidatePages];
    UINavigationController *navigation = self.navigation;
    XYBookAudioAfterNavigationTransition(navigation, ^{
        if (self.style == XYBookAudioOpenStylePush) {
            [self removePushedPages];
        } else if (navigation.presentingViewController) {
            [navigation dismissViewControllerAnimated:YES completion:^{
                [self finishClose];
            }];
        } else {
            [self finishClose];
        }
    });
}

- (void)removePushedPages {
    UINavigationController *navigation = self.navigation;
    NSArray<UIViewController *> *stack = navigation.viewControllers;
    NSMutableArray<UIViewController *> *remaining = [stack mutableCopy];
    for (UIViewController *page in self.pages) {
        [remaining removeObjectIdenticalTo:page];
    }
    if (remaining.count != stack.count) {
        [navigation setViewControllers:remaining animated:NO];
    }
    [self finishClose];
}

- (void)invalidatePages {
    for (XYBookAudioWebViewController *page in self.pages) {
        [page invalidatePage];
    }
}

- (void)finishClose {
    if (!self.closing) {
        self.closing = YES;
        [self invalidatePages];
    }
    dispatch_block_t closed = self.closed;
    self.closed = nil;
    if (closed) {
        closed();
    }
}

@end
