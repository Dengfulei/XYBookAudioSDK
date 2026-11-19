// H5 业务入口：按 actionName 调用同名方法；窗口、宿主能力和听书命令各自沿用已有业务边界。
#import "XYBookAudioSDKManager.h"
#import "XYBookAudioLogger.h"
#import "XYBookAudioBridgeWebView.h"
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

/// 下列同名入口均接收完整请求字典：{ actionName, parameters, callbackActionName }。
/// 关闭当前网页，无业务回调；不改变播放状态。
- (void)xhCloseWindow:(NSDictionary *)request;
/// 使用 parameters.url 打开新的可信网页窗口，无业务回调。
- (void)xhOpenWindow:(NSDictionary *)request;
/// 请求宿主展示登录页，不向 H5 增加登录结果回调。
- (void)xhGoLogin:(NSDictionary *)request;
/// 原版 JS SDK 用户资料回调依赖的系统信息读取。
- (void)xhGetSystemInfo:(NSDictionary *)request;
/// 获取宿主标准用户资料；游客和取消登录返回空对象。
- (void)xhGetUserInfo:(NSDictionary *)request;
/// 打开宿主分享菜单；可选回调仅表示已选择分享渠道。
- (void)xhShowShareMenu:(NSDictionary *)request;
/// 查询 parameters.name 对应的能力，沿用原版 { data: 1/0 } 回调。
- (void)xhCanIUse:(NSDictionary *)request;

@end
