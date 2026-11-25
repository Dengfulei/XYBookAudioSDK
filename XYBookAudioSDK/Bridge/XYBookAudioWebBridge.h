// H5 业务入口：按 actionName 调用同名方法；窗口、宿主能力和听书命令各自沿用已有业务边界。
#import "XYBookAudioLogger.h"
#import "XYBookAudioBridgeWebView.h"
#import "XYBookAudioMessageProtocol.h"
#import "XYBookAudioSDKManager.h"
#import "XYBookAudioWindowRouting.h"

@interface XYBookAudioWebBridge : NSObject

/// 检查 H5 入口是否已实现。
/// @param action 请求里的 `actionName`。
/// @return 存在允许分发的同名入口时返回 YES。
+ (BOOL)supportsAction:(NSString *)action;

/// @return 当前类实际实现的 H5 动作名，按名称排序。
+ (NSArray<NSString *> *)supportedActions;

/// 创建页面专用的 H5 桥接并注册消息入口。
/// @param SDK 当前播放会话的业务入口。
/// @param configuration 用于校验可信页面及配置请求日志。
/// @param webView 收发 H5 消息的 WebView。
/// @param logger 当前 SDK 实例的日志出口。
- (instancetype)initWithSDK:(XYBookAudioSDKManager *)SDK
              configuration:(XYBookAudioConfiguration *)configuration
                    webView:(XYBookAudioBridgeWebView *)webView
                     logger:(XYBookAudioLogger *)logger;
@property (nonatomic, weak) UIViewController *page;
@property (nonatomic, weak) id<XYBookAudioWindowRouting> windowRouter;

/// 主文档提交后启用桥接。
- (void)activate;
/// 主文档导航、关闭或进程退出时使旧请求失效并取消订阅。
- (void)invalidate;
/// 页面重新可见时向已 Ready 的 H5 同步身份和播放状态。
- (void)pageDidAppear;

@end

@interface XYBookAudioSDKManager (SnckBridge)
/// @return 当前 SNCK 播放快照。
- (NSDictionary *)snckPlayback;
/// @return 最近一次定时状态变更的原因。
- (XYBookAudioTimerChange)snckTimerChange;
/// @return 当前 SNCK 用户状态，包含游客标记和身份。
- (NSDictionary *)snckUserState;
/// 递增并返回同一 SDK 实例内的 SNCK 事件版本。
- (NSUInteger)nextSnckEventVersion;

/// 执行 SNCK 播放命令。
/// @param command 播放命令名，例如 `SetQueue` 或 `GetTimer`。
/// @param parameters H5 的业务参数字典。
/// @param completion 接收命令对应的结果或错误，供桥接回传原请求页面。
- (void)executeSnckAudio:(NSString *)command
              parameters:(NSDictionary *)parameters
              completion:(XYBookAudioCompletion)completion;

/// 执行 SNCK 分享请求。
/// @param parameters 含标题、链接及可选分享字段的字典。
/// @param page 发起分享的听书窗口。
/// @param completion 接收分享结果或错误，供桥接回传原请求页面。
- (void)shareSnck:(NSDictionary *)parameters
         fromPage:(UIViewController *)page
       completion:(XYBookAudioCompletion)completion;
@end
