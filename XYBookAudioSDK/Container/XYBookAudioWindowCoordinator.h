// 管理当前听书窗口及路由，播放会话由 SDK 单独持有。
#import "XYBookAudioLogger.h"
#import "XYBookAudioSDKManager.h"
#import "XYBookAudioWindowRouting.h"

@interface XYBookAudioWindowCoordinator : NSObject <XYBookAudioWindowRouting>

@property (nonatomic, copy) dispatch_block_t closed;
@property (nonatomic, weak, readonly) UINavigationController *navigation;
@property (nonatomic, readonly) UIViewController *topPage;

/// 创建一组听书页面的导航协调器。
/// @param SDK 当前 SDK 实例，供创建页面并连接桥接。
/// @param configuration 提供根页入口和后续窗口的可信范围。
/// @param logger 当前 SDK 实例的日志出口。
/// @param style 创建独立全屏导航容器或复用宿主导航栈。
- (instancetype)initWithSDK:(XYBookAudioSDKManager *)SDK
              configuration:(XYBookAudioConfiguration *)configuration
                     logger:(XYBookAudioLogger *)logger
                      style:(XYBookAudioOpenStyle)style;

/// 按配置的展示方式打开根页。
/// @param controller 当前可见的宿主控制器。
/// @param completion 原生展示完成后回调。成功时错误为 nil。
- (void)openFromViewController:(UIViewController *)controller completion:(void (^)(NSError *))completion;

/// 使本组页面失效并关闭容器或移除本组页面。
- (void)closeAllPages;

@end
