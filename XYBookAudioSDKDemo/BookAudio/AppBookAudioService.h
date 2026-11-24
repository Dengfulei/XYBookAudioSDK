// 宿主听书接入层：统一持有会话并适配宿主能力；页面仅传入展示入口，不持有 SDK。
#import <UIKit/UIKit.h>
#import <XYBookAudioSDK/XYBookAudioSDK.h>

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSNotificationName const AppBookAudioServiceEventNotification;
FOUNDATION_EXPORT NSString *const AppBookAudioServiceEventNameKey;
FOUNDATION_EXPORT NSString *const AppBookAudioServiceEventParametersKey;

@interface AppBookAudioService : NSObject

/// 全 App 共用一个听书会话；业务方法均在主线程调用，单例不保存入口控制器。
+ (instancetype)sharedInstance;
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;

/// 可在首次打开前配置远程 H5；初始化失败返回 NO，已有会话时返回 BUSY，避免覆盖播放状态。
/// 不调用此方法时，首次打开使用本地 Fixture 配置；正式宿主应统一提供自己的入口和可信范围。
- (BOOL)configureWithConfiguration:(XYBookAudioConfiguration *)configuration error:(NSError **)error;

/// 按需初始化并打开听书；重复打开及初始化失败均通过 completion 返回，不长期持有 controller。
- (void)openFromViewController:(UIViewController *)controller
                         style:(XYBookAudioOpenStyle)style
                    completion:(void (^)(NSError *_Nullable error))completion;

/// 未初始化时返回 nil；读取已有会话快照不创建播放器或页面。
- (nullable NSDictionary *)playbackSnapshot;

/// 刷新身份并继续等待中的无回调登录。账号变更通知自动触发，也可由宿主主动调用。
/// 未初始化时不创建 SDK，下次初始化读取最新身份。
- (void)refreshHostIdentity;

/// 宿主其他播放器开始播放前调用，先同步让出听书的音频控制权。
- (void)yieldPlayback;

/// 保存断点并停止播放，保留 SDK 实例，之后仍可打开页面继续操作。
- (void)stopPlayback;

/// 明确结束听书服务时调用；释放会话和订阅，下次打开会重新初始化。页面退出不得调用此方法。
/// 保留最近一次成功配置；如需重新打开，应等待已有听书容器关闭，也可在关闭后配置新入口。
- (void)shutdown;

@end

NS_ASSUME_NONNULL_END
