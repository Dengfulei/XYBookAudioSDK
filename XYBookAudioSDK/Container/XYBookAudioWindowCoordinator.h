// 管理当前听书窗口及路由，播放会话由 SDK 单独持有。
#import "XYBookAudioLogger.h"
#import "XYBookAudioSDKManager.h"
#import "XYBookAudioWindowRouting.h"

@interface XYBookAudioWindowCoordinator : NSObject <XYBookAudioWindowRouting>

@property (nonatomic, copy) dispatch_block_t closed;
@property (nonatomic, weak, readonly) UINavigationController *navigation;
@property (nonatomic, readonly) UIViewController *topPage;

- (instancetype)initWithSDK:(XYBookAudioSDKManager *)SDK
              configuration:(XYBookAudioConfiguration *)configuration
                     logger:(XYBookAudioLogger *)logger
                      style:(XYBookAudioOpenStyle)style;
- (void)openFromViewController:(UIViewController *)controller completion:(void (^)(NSError *))completion;
- (void)closeAllPages;

@end
