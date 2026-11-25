// 宿主提供身份、登录、分享和音频交接；SDK 不实现宿主账号体系，所有 completion 应恰好回调一次。
#import <UIKit/UIKit.h>
#import <XYBookAudioSDK/XYBookAudioTypes.h>

NS_ASSUME_NONNULL_BEGIN

/// 宿主登录操作的业务结果。
typedef NS_ENUM(NSInteger, XYBookAudioLoginResult) {
    /// 账号已保存，可立即通过 `bookAudioUserIdentity` 读取。
    XYBookAudioLoginLoggedIn,
    /// 用户取消、关闭或退出登录页。
    XYBookAudioLoginCancelled,
    /// 登录操作失败。
    XYBookAudioLoginFailed
};

/// 宿主分享操作的业务结果。
typedef NS_ENUM(NSInteger, XYBookAudioShareResult) {
    /// 分享已交给渠道处理。
    XYBookAudioShareAccepted,
    /// 宿主不支持该分享操作或渠道。
    XYBookAudioShareUnsupported,
    /// 分享操作失败。
    XYBookAudioShareFailed,
    /// 用户取消分享。
    XYBookAudioShareCancelled,
    /// 宿主已确认分享实际成功。
    XYBookAudioShareSucceeded
};

@protocol XYBookAudioHost <NSObject>

/// 在主线程同步读取宿主已保存的账号状态。
/// @return 当前身份对象。游客返回以空 `userId` 创建的身份对象。
- (XYBookAudioIdentity *)bookAudioUserIdentity;

/// 根据 SDK 提供的参数调起宿主分享。
/// @param request 分享字典，含 `title`、`link`，可含 `desc`、`imgUrl` 或 `platform`。旧版动作的非空 `imgUrl` 原样传入。
/// @param controller SDK 提供的当前页面，用于展示分享界面。
/// @param completion 宿主结算时调用一次，传入 `XYBookAudioShareResult`。有执行错误时可附带 `NSError`。
- (void)bookAudioShare:(NSDictionary<NSString *, id> *)request
                  from:(UIViewController *)controller
            completion:(void (^)(XYBookAudioShareResult result, NSError *_Nullable error))completion;

/// 停止宿主其他播放器并释放其锁屏控制。无法按时交接时，宿主应撤销待处理操作。
/// @param completion 在 10 秒内调用一次。已让出音频或没有其他播放器时传 nil，交接失败时传 NSError。
- (void)bookAudioAcquirePlayback:(void (^)(NSError *_Nullable error))completion;

/// SDK 释放系统媒体占用，或宿主已让出音频但该请求最终未开始播放时通知。
/// 回调可能对应已取消的交接，宿主应按当前音频状态决定后续操作。
- (void)bookAudioDidReleasePlayback;

@optional
/// 展示宿主登录页并回传结果。两个登录方法都实现时，SDK 优先使用此方法。
/// @param controller SDK 提供的当前听书页。可用其 `navigationController` 推入宿主登录页。
/// @param completion 宿主只调用一次。保存账号后传 `XYBookAudioLoginLoggedIn` 和 nil，取消时传
/// `XYBookAudioLoginCancelled` 和 nil，失败时传 `XYBookAudioLoginFailed`，有错误信息时附带 NSError。
- (void)bookAudioRequestLoginFrom:(UIViewController *)controller
                       completion:(void (^)(XYBookAudioLoginResult result, NSError *_Nullable error))completion;

/// 在给定页面上展示宿主登录。登录成功并保存账号后，由宿主账号模块调用 SDK 的 refreshHostIdentity。
/// @param controller SDK 提供的当前听书页。可用其 `navigationController` 推入宿主登录页。
- (void)bookAudioRequestLoginFrom:(UIViewController *)controller;

/// 为 `xhGetSystemInfo` 提供宿主系统资料。省略此方法时 SDK 使用 App、设备及窗口的默认数据。
/// @param controller 当前听书页面，可用于读取状态栏和安全区。原生查询时可能还没有打开听书页。
/// @return 非空且可序列化为 JSON 的字典。无效结果会使 SDK 返回 HOST_FAILED。
- (nullable NSDictionary *)bookAudioSystemInfoFromViewController:(UIViewController *)controller;

/// 查询已登录用户的资料。两种资料方法都实现时，SDK 优先使用此方法。
/// @param parameters 原始业务参数，可能含 `goLogin`、`useTicket` 和自定义字段。宿主应校验自己使用的字段。
/// @param completion 成功时传非空且可序列化为 JSON 的字典和 nil，失败时传 nil 和 NSError。资料字典原样回传。
- (void)bookAudioUserInfoWithParameters:(NSDictionary<NSString *, id> *)parameters
                             completion:
                                 (void (^)(NSDictionary *_Nullable userInfo, NSError *_Nullable error))completion;

/// 宿主只实现此资料方法时，用它查询已登录用户的资料。
/// @param usingTicket YES 时宿主需要刷新票据。不支持刷新时通过 `completion` 返回错误。
/// @param completion 成功时传非空且可序列化为 JSON 的字典和 nil，失败时传 nil 和 NSError。
- (void)bookAudioUserInfoUsingTicket:(BOOL)usingTicket
                          completion:(void (^)(NSDictionary *_Nullable userInfo, NSError *_Nullable error))completion;

@end

NS_ASSUME_NONNULL_END
