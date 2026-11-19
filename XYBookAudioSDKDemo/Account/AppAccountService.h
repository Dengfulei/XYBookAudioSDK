// 宿主账号模块：独立保存当前用户并广播账号变更，不依赖听书 SDK，也不管理播放或听书页面。
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN
FOUNDATION_EXPORT NSNotificationName const AppAccountDidChangeNotification;

@interface AppAccountService : NSObject

+ (instancetype)sharedInstance;
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;

/// 主线程读取，nil 表示游客；凭证与认证流程由宿主账号系统负责，听书接入层只读取此标识。
@property (nonatomic, copy, readonly, nullable) NSString *userId;

/// 宿主认证成功后提交非空用户标识；先更新状态，再在主线程通知观察者，相同身份不重复通知。
/// 此方法不执行认证；本地联调由测试登录页调用，正式宿主应在认证接口成功后调用。
- (void)updateAuthenticatedUserId:(NSString *)userId;

/// 宿主退出账号的统一入口；清除当前身份后通知业务模块，已经是游客时无副作用。
/// 当前联调不保存凭证；正式宿主应在自身退出流程完成并清理凭证后提交游客状态。
- (void)logout;

@end
NS_ASSUME_NONNULL_END
