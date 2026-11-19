// 宿主账号模块的登录页面：提交认证后的账号状态并返回宿主结果，不依赖听书 SDK。
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, AppLoginResult) {
    AppLoginSucceeded,
    AppLoginCancelled,
    AppLoginFailed
};

@interface AppLoginViewController : UIViewController

/// 用于 push 登录；按钮操作、返回和外部关闭均只回调一次，成功不代表付费权益已授权。
- (instancetype)initWithCompletion:(void (^)(AppLoginResult result))completion;

@end

NS_ASSUME_NONNULL_END
