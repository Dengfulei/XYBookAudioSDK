//
//  SceneDelegate.m
//  XYBookAudioSDKDemo
//
//  创建者：唐海洋，创建日期：2026/9/20。
//

#import "SceneDelegate.h"
#import <XYBookAudioSDK/XYBookAudioTypes.h>

@interface SceneDelegate ()

@end

@implementation SceneDelegate

- (void)scene:(UIScene *)scene
    willConnectToSession:(UISceneSession *)session
                 options:(UISceneConnectionOptions *)connectionOptions {
    // 可在此配置 UIWindow，并将其关联到传入的 UIWindowScene。
    // 使用故事板时，系统会自动初始化 window 属性并将其关联到场景。
    // 连接回调不代表新建会话；新会话配置由 AppDelegate 的 configurationForConnectingSceneSession 回调提供。
}

- (void)sceneDidDisconnect:(UIScene *)scene {
    // 系统释放场景时调用。
    // 通常发生在场景进入后台之后，或其会话被丢弃时。
    // 可在此释放下次连接时能够重建的场景资源。
    // 断开连接不等于丢弃会话，场景仍可能重新连接；会话丢弃由 AppDelegate 的 didDiscardSceneSessions 回调通知。
}

- (void)sceneDidBecomeActive:(UIScene *)scene {
    // 场景从非活跃状态恢复为活跃状态后调用。
    // 可在此恢复因场景非活跃而暂停或延迟启动的任务。
}

#if DEBUG
- (void)scene:(UIScene *)scene openURLContexts:(NSSet<UIOpenURLContext *> *)URLContexts {
    NSString *wechatScheme = [XYBookAudioPaymentConfiguration hostURLSchemeForName:@"weixinScheme"].lowercaseString;
    for (UIOpenURLContext *context in URLContexts) {
        if ([context.URL.scheme.lowercaseString isEqualToString:wechatScheme]) {
            NSLog(@"[XYBookAudio][Debug][Page] WeChat return scheme reached the Demo scene.");
            break;
        }
    }
}
#endif

- (void)sceneWillResignActive:(UIScene *)scene {
    // 场景即将从活跃状态切换为非活跃状态时调用。
    // 来电等临时中断也会触发此回调。
}

- (void)sceneWillEnterForeground:(UIScene *)scene {
    // 场景从后台进入前台时调用。
    // 可在此恢复进入后台时调整的界面或资源状态。
}

- (void)sceneDidEnterBackground:(UIScene *)scene {
    // 场景从前台进入后台时调用。
    // 可在此保存数据、释放共享资源，并保存场景恢复所需的状态，
    // 以便后续恢复到当前场景。
}

@end
