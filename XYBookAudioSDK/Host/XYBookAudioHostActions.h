// 编排宿主资料、登录与分享：管理并发占用、超时和身份刷新，不保存凭证或宿主业务模型。
#import "XYBookAudioSDKManager.h"

#import "XYBookAudioLogger.h"

@interface XYBookAudioHostActions : NSObject

@property (nonatomic, copy) void (^identityChanged)(void);
- (instancetype)initWithHost:(id<XYBookAudioHost>)host logger:(XYBookAudioLogger *)logger;

/// 按 goLogin/useTicket 读取标准宿主资料；游客、取消或登录失败返回空字典，与参考协议一致。
- (void)getUserInfo:(NSDictionary *)parameters
          presenter:(UIViewController *)presenter
         completion:(XYBookAudioCompletion)completion;
/// 原样读取宿主系统资料；该能力是原版 JS SDK 用户资料回调的依赖。
- (void)getSystemInfoFrom:(UIViewController *)presenter completion:(XYBookAudioCompletion)completion;

/// 请求宿主登录；账号更新与超时由本模块管理，结果不直接定义 H5 回调。
- (void)requestLoginFrom:(UIViewController *)presenter completion:(XYBookAudioCompletion)completion;
/// 请求宿主分享菜单；参数不转成听书协议，保留宿主选择／取消的业务结果。
- (void)showShareMenu:(NSDictionary *)parameters
            presenter:(UIViewController *)presenter
           completion:(XYBookAudioCompletion)completion;
- (void)dispose;

@end
