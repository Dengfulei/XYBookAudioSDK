// 编排宿主资料、登录与分享：管理并发占用、超时和身份刷新，不保存凭证或宿主业务模型。
#import "XYBookAudioSDKManager.h"

#import "XYBookAudioLogger.h"

@interface XYBookAudioHostActions : NSObject

/// 宿主结果到达后通知会话重新读取账号状态。
@property (nonatomic, copy) void (^identityChanged)(void);

/// 创建宿主动作处理器。
/// @param host 提供登录、资料和分享的宿主对象，由调用方持有。
/// @param logger 当前 SDK 实例的日志出口。
- (instancetype)initWithHost:(id<XYBookAudioHost>)host logger:(XYBookAudioLogger *)logger;

/// 读取用户资料，必要时先请求登录。
/// @param parameters 原始业务参数，包括可选的 `goLogin`、`useTicket` 和宿主自定义字段。
/// @param presenter 需要发起登录时使用的当前听书页。
/// @param completion 接收宿主资料。游客、登录取消和登录失败以空字典结算，资料查询错误通过 error 返回。
- (void)getUserInfo:(NSDictionary *)parameters
          presenter:(UIViewController *)presenter
         completion:(XYBookAudioCompletion)completion;
/// 优先读取宿主系统资料，缺省时从当前 App、设备和窗口读取。
/// @param presenter 当前听书页，未打开听书页时可能为空。
/// @param completion 接收非空 JSON 字典或执行错误。
- (void)getSystemInfoFrom:(UIViewController *)presenter completion:(XYBookAudioCompletion)completion;

/// 已登录时复用当前身份，否则请求宿主登录。
/// @param presenter 当前可见的听书页，用于宿主展示登录界面。
/// @param completion 原生登录回调，接收 `status`、`identity` 或执行错误。
- (void)requestLoginFrom:(UIViewController *)presenter completion:(XYBookAudioCompletion)completion;

/// 读取到已登录身份时结算等待账号通知的登录请求。
- (void)resumePendingLoginIfAuthenticated;

/// 按旧版分享协议请求宿主分享。
/// @param parameters 分享参数，必填 `title` 和 `link`，可含 `desc`、`imgUrl`。
/// @param presenter 当前可见的听书页，用于展示分享界面。
/// @param completion 接收包含 `status` 的结果或执行错误。
- (void)showShareMenu:(NSDictionary *)parameters
            presenter:(UIViewController *)presenter
           completion:(XYBookAudioCompletion)completion;

/// 按 SNCK 分享协议请求宿主分享。
/// @param parameters 含 `title`、`link` 和可选的 `description`、`imageUrl`、`platform`。
/// @param presenter 当前可见的听书页，用于展示分享界面。
/// @param completion 接收包含 `requestId`、`status` 的结果或执行错误。
- (void)shareSnck:(NSDictionary *)parameters
        presenter:(UIViewController *)presenter
       completion:(XYBookAudioCompletion)completion;

/// 关闭宿主动作入口，并结算待处理的登录请求。
- (void)dispose;

@end
