//
//  AppDelegate.m
//  XYBookAudioSDKDemo
//
//  创建者：唐海洋，创建日期：2026/9/20。
//

#import "AppDelegate.h"

@interface AppDelegate ()

@end

@implementation AppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    // 可在此扩展应用启动后的初始化逻辑。
    return YES;
}

#pragma mark - UISceneSession 生命周期

- (UISceneConfiguration *)application:(UIApplication *)application
    configurationForConnectingSceneSession:(UISceneSession *)connectingSceneSession
                                   options:(UISceneConnectionOptions *)options {
    // 创建新的场景会话时调用。
    // 返回用于创建该场景的配置。
    return [[UISceneConfiguration alloc] initWithName:@"Default Configuration" sessionRole:connectingSceneSession.role];
}

- (void)application:(UIApplication *)application didDiscardSceneSessions:(NSSet<UISceneSession *> *)sceneSessions {
    // 用户丢弃场景会话后调用。
    // 若会话在应用未运行时被丢弃，将在应用完成启动后回调此方法。
    // 可在此释放被丢弃场景的专属资源；这些场景不会再恢复。
}

@end
