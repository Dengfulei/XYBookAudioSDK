// 宿主登录页演示本地认证，成功后将身份写入账号模块。
#import "AppLoginViewController.h"
#import "AppAccountService.h"

static NSString *const AppLoginFixtureUserId = @"local-user";
static CGFloat const AppLoginSpacing = 20;
static CGFloat const AppLoginMargin = 24;

@interface AppLoginViewController ()
@property (nonatomic, copy, nullable) void (^completion)(AppLoginResult);
@end

@implementation AppLoginViewController

- (instancetype)initWithCompletion:(void (^)(AppLoginResult))completion {
    if ((self = [super initWithNibName:nil bundle:nil])) {
        _completion = [completion copy];
    }
    return self;
}

/// 展示三种可验证结果；真实登录网络请求和账号写入由正式宿主的账号模块负责。
- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"模拟宿主登录";
    self.view.backgroundColor = UIColor.systemBackgroundColor;
    UILabel *description = [UILabel new];
    description.text = @"此页面通过 push 打开。登录后返回听书页；受限章节仍需 H5 重新确认权益并提供音源。";
    description.numberOfLines = 0;
    UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[ description ]];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = AppLoginSpacing;
    [stack addArrangedSubview:[self buttonWithTitle:@"登录测试账号" action:@selector(login)]];
    [stack addArrangedSubview:[self buttonWithTitle:@"模拟失败" action:@selector(fail)]];
    [stack addArrangedSubview:[self buttonWithTitle:@"取消" action:@selector(cancel)]];
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[
        [stack.leadingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.leadingAnchor
                                            constant:AppLoginMargin],
        [stack.trailingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.trailingAnchor
                                             constant:-AppLoginMargin],
        [stack.centerYAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.centerYAnchor]
    ]];
}

- (UIButton *)buttonWithTitle:(NSString *)title action:(SEL)action {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    button.configuration = UIButtonConfiguration.filledButtonConfiguration;
    [button setTitle:title forState:UIControlStateNormal];
    [button addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    return button;
}

/// 导航栏返回、完成的侧滑返回或容器关闭都属于取消；被其他页面临时覆盖不会结束登录。
- (void)viewDidDisappear:(BOOL)animated {
    [super viewDidDisappear:animated];
    if (self.isMovingFromParentViewController || self.isBeingDismissed || self.navigationController.isBeingDismissed) {
        [self finishWithResult:AppLoginCancelled];
    }
}

/// 实际移出导航栈后才结算取消；交互式返回被用户取消时不会触发此分支。
- (void)didMoveToParentViewController:(UIViewController *)parent {
    [super didMoveToParentViewController:parent];
    if (!parent) {
        [self finishWithResult:AppLoginCancelled];
    }
}

/// 先释放回调再通知宿主，避免宿主 pop 导致的生命周期回调重复结算。
- (void)finishWithResult:(AppLoginResult)result {
    void (^completion)(AppLoginResult) = self.completion;
    self.completion = nil;
    if (completion) {
        completion(result);
    }
}

- (void)finishFromButtonWithResult:(AppLoginResult)result {
    if (self.completion) {
        [self finishWithResult:result];
    } else if (self.navigationController.topViewController == self) {
        [self.navigationController popViewControllerAnimated:YES];
    }
}

/// 本地测试账号替代尚未接入的认证服务；正式宿主在认证成功后通过同一账号入口提交身份。
- (void)login {
    [AppAccountService.sharedInstance updateAuthenticatedUserId:AppLoginFixtureUserId];
    [self finishFromButtonWithResult:AppLoginSucceeded];
}

- (void)fail {
    [self finishFromButtonWithResult:AppLoginFailed];
}

- (void)cancel {
    [self finishFromButtonWithResult:AppLoginCancelled];
}

@end
