// SDK 网页窗口栈：管理打开、逐层关闭及整个容器的释放，不拥有播放会话或宿主账号。
#import <UIKit/UIKit.h>
#import "XYBookAudioWindowRouting.h"
#import "XYBookAudioSDKManager.h"
#import "XYBookAudioLogger.h"

@interface XYBookAudioNavigationController : UINavigationController <XYBookAudioWindowRouting>

/// 整个模态容器关闭后通知 SDK 释放展示占用；子页出栈不触发。
@property (nonatomic, copy) void (^closed)(void);
- (instancetype)initWithSDK:(XYBookAudioSDKManager *)SDK
              configuration:(XYBookAudioConfiguration *)configuration
                     logger:(XYBookAudioLogger *)logger;
/// SDK dispose 时关闭所有网页及其上方宿主界面；各页面订阅立即失效。
- (void)closeAllPages;

@end
