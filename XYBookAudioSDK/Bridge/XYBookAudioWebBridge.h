// H5 业务入口：按 actionName 调用同名方法；窗口、宿主能力和听书命令各自沿用已有业务边界。
#import "XYBookAudioLogger.h"
#import "XYBookAudioBridgeWebView.h"
#import "XYBookAudioMessageProtocol.h"
#import "XYBookAudioWindowRouting.h"

@interface XYBookAudioWebBridge : NSObject

/// 按原工程检查 xh 同名实例方法是否存在；只表示入口已实现，宿主业务能力仍由对应代理提供。
+ (BOOL)supportsAction:(NSString *)action;
/// 从当前类实际实现的 H5 方法生成能力集合，按名称排序；无需额外登记动作名单。
+ (NSArray<NSString *> *)supportedActions;

- (instancetype)initWithSDK:(XYBookAudioSDKManager *)SDK
              configuration:(XYBookAudioConfiguration *)configuration
                    webView:(XYBookAudioBridgeWebView *)webView
                     logger:(XYBookAudioLogger *)logger;
@property (nonatomic, weak) UIViewController *page;
@property (nonatomic, weak) id<XYBookAudioWindowRouting> windowRouter;

/// 文档提交后激活；主文档导航、关闭或进程退出时失效旧请求并取消订阅。
- (void)activate;
- (void)invalidate;
- (void)pageDidAppear;

@end

@interface XYBookAudioSDKManager (SnckBridge)
- (NSDictionary *)snckPlayback;
- (XYBookAudioTimerChange)snckTimerChange;
- (NSDictionary *)snckUserState;
- (NSUInteger)nextSnckEventVersion;
- (void)executeSnckAudio:(NSString *)command
              parameters:(NSDictionary *)parameters
              completion:(XYBookAudioCompletion)completion;
- (void)shareSnck:(NSDictionary *)parameters
         fromPage:(UIViewController *)page
       completion:(XYBookAudioCompletion)completion;
@end
