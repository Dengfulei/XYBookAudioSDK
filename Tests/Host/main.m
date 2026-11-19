// 最小 XCTest 宿主仅提供 UIKit 和 WebKit 所需的进程环境，不包含听书界面或桥接逻辑。
#import <UIKit/UIKit.h>

@interface XYBookAudioTestApp : UIResponder <UIApplicationDelegate>

@property (nonatomic, strong) UIWindow *window;

@end

@interface XYBookAudioTestScene : UIResponder <UIWindowSceneDelegate>

@property (nonatomic, strong) UIWindow *window;

@end

@implementation XYBookAudioTestApp

- (UISceneConfiguration *)application:(UIApplication *)application
    configurationForConnectingSceneSession:(UISceneSession *)session
                                   options:(UISceneConnectionOptions *)options {
    UISceneConfiguration *configuration = [[UISceneConfiguration alloc] initWithName:@"Test Window"
                                                                         sessionRole:session.role];
    configuration.delegateClass = XYBookAudioTestScene.class;
    return configuration;
}

@end

@implementation XYBookAudioTestScene

- (void)scene:(UIScene *)scene
    willConnectToSession:(UISceneSession *)session
                 options:(UISceneConnectionOptions *)options {
    self.window = [[UIWindow alloc] initWithWindowScene:(UIWindowScene *)scene];
    self.window.rootViewController = [UIViewController new];
    XYBookAudioTestApp *app = (XYBookAudioTestApp *)UIApplication.sharedApplication.delegate;
    app.window = self.window;
    [self.window makeKeyAndVisible];
}

@end

int main(int argc, char *argv[]) {
    @autoreleasepool {
        return UIApplicationMain(argc, argv, nil, NSStringFromClass(XYBookAudioTestApp.class));
    }
}
