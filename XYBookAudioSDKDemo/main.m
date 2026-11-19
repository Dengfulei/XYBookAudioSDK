//
//  main.m
//  XYBookAudioSDKDemo
//
//  创建者：唐海洋，创建日期：2026/9/20。
//

#import <UIKit/UIKit.h>
#import "AppDelegate.h"

int main(int argc, char *argv[]) {
    NSString *appDelegateClassName;
    @autoreleasepool {
        // 可能创建自动释放对象的启动准备逻辑应放在此自动释放池中。
        appDelegateClassName = NSStringFromClass([AppDelegate class]);
    }
    return UIApplicationMain(argc, argv, nil, appDelegateClassName);
}
