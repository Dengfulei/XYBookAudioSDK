// 宿主入口页面仅处理按钮与状态展示；听书会话和宿主协议由 AppBookAudioService 统一管理。
#import "XYBookAudioDemoViewController.h"
#import "BookAudio/AppBookAudioService.h"
#import "Account/AppAccountService.h"
#import <YYModel/YYModel.h>

@interface XYBookAudioDemoViewController ()

@property (nonatomic, strong) UILabel *status;
@property (nonatomic) BOOL shouldOpenListeningOnAppearance;

@end

@implementation XYBookAudioDemoViewController

- (void)dealloc {
    [NSNotificationCenter.defaultCenter removeObserver:self];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.systemBackgroundColor;
    self.title = @"独立宿主";
    [self buildControls];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(receiveBookAudioEvent:)
                                               name:AppBookAudioServiceEventNotification
                                             object:AppBookAudioService.sharedInstance];
    self.shouldOpenListeningOnAppearance = [NSProcessInfo.processInfo.arguments containsObject:@"--open-listening"];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    if (self.shouldOpenListeningOnAppearance) {
        self.shouldOpenListeningOnAppearance = NO;
        [self openListening];
    }
}

/// 每个入口只传入当前控制器；接入单例负责初始化并复用已有会话。
- (void)openListening {
    [self openListeningWithStyle:XYBookAudioOpenStylePresent];
}

- (void)pushListening {
    [self openListeningWithStyle:XYBookAudioOpenStylePush];
}

- (void)openListeningWithStyle:(XYBookAudioOpenStyle)style {
    __weak typeof(self) weakSelf = self;
    [AppBookAudioService.sharedInstance openFromViewController:self style:style completion:^(NSError *error) {
        if (error) {
            weakSelf.status.text = error.localizedDescription;
        }
    }];
}

/// 页面只订阅展示所需事件；解除订阅不会终止播放，也不改变共享会话的生命周期。
- (void)receiveBookAudioEvent:(NSNotification *)notification {
    NSString *event = notification.userInfo[AppBookAudioServiceEventNameKey];
    NSDictionary *parameters = notification.userInfo[AppBookAudioServiceEventParametersKey];
    self.status.text = [NSString stringWithFormat:@"%@\n%@", event, [parameters yy_modelToJSONString]];
}

/// 页面调用宿主账号模块退出；账号变更通知由听书接入层接收，页面无需直接刷新 SDK。
- (void)logout {
    [AppAccountService.sharedInstance logout];
}

/// 演示其他音频业务开始前同步让出听书的音频控制权。
- (void)takeOver {
    [AppBookAudioService.sharedInstance yieldPlayback];
}

/// 组装宿主入口按钮；听书页面及登录导航不由此控制器管理。
- (void)buildControls {
    self.status = [UILabel new];
    self.status.numberOfLines = 0;
    self.status.font = [UIFont preferredFontForTextStyle:UIFontTextStyleFootnote];
    self.status.text = @"打开听书页面，调试播放、定时、登录和分享。关闭听书页面后可继续播放。";
    UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[ self.status ]];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 20;
    NSArray *titles = @[ @"全屏打开听书", @"Push 打开听书", @"退出登录", @"模拟宿主接管音频" ];
    NSArray *selectors = @[
        NSStringFromSelector(@selector(openListening)), NSStringFromSelector(@selector(pushListening)),
        NSStringFromSelector(@selector(logout)), NSStringFromSelector(@selector(takeOver))
    ];
    for (NSUInteger index = 0; index < titles.count; index++) {
        UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
        button.configuration = UIButtonConfiguration.filledButtonConfiguration;
        [button setTitle:titles[index] forState:UIControlStateNormal];
        [button addTarget:self action:NSSelectorFromString(selectors[index])
            forControlEvents:UIControlEventTouchUpInside];
        [stack addArrangedSubview:button];
    }
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[
        [stack.leadingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.leadingAnchor constant:24],
        [stack.trailingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.trailingAnchor constant:-24],
        [stack.centerYAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.centerYAnchor]
    ]];
}

@end
