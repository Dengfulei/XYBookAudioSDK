// 宿主账号模块的登录页面：提交认证后的账号状态并返回宿主结果，不依赖听书 SDK。
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, AppLoginResult) {
    AppLoginSucceeded,
    AppLoginCancelled,
    AppLoginFailed
};

@interface AppLoginViewController : UIViewController

/// 用于 push 登录。传入 completion 时只回调一次。传 nil 时，按钮操作由登录页自行返回。
- (instancetype)initWithCompletion:(nullable void (^)(AppLoginResult result))completion;

@end

NS_ASSUME_NONNULL_END
