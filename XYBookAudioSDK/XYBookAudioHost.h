// 宿主提供身份、登录、分享和音频交接；SDK 不实现宿主账号体系，所有 completion 应恰好回调一次。
#import <UIKit/UIKit.h>
#import <XYBookAudioSDK/XYBookAudioTypes.h>

NS_ASSUME_NONNULL_BEGIN
typedef NS_ENUM(NSInteger, XYBookAudioLoginResult) {
    XYBookAudioLoginLoggedIn,
    XYBookAudioLoginCancelled,
    XYBookAudioLoginFailed
};
typedef NS_ENUM(NSInteger, XYBookAudioShareResult) {
    XYBookAudioShareAccepted,
    XYBookAudioShareUnsupported,
    XYBookAudioShareFailed,
    XYBookAudioShareCancelled,
    XYBookAudioShareSucceeded
};

@protocol XYBookAudioHost <NSObject>

/// 主线程在播放前及账号变化后读取；必须返回身份对象，游客使用空 userId，不在这里弹登录页。
- (XYBookAudioIdentity *)bookAudioUserIdentity;

/// 在给定页面上展示宿主登录；登录成功只代表身份变化，受限章节仍需 H5 重新确认权益并供源。
- (void)bookAudioRequestLoginFrom:(UIViewController *)controller
                       completion:(void (^)(XYBookAudioLoginResult result, NSError *_Nullable error))completion;

/// 接收标准分享参数；accepted 表示已调起渠道，succeeded 表示宿主确认实际分享成功。
- (void)bookAudioShare:(NSDictionary<NSString *, id> *)request
                  from:(UIViewController *)controller
            completion:(void (^)(XYBookAudioShareResult result, NSError *_Nullable error))completion;

/// 先停止宿主其他播放器并注销其锁屏控制，再在 10 秒内回调。无法按时交接时，宿主应撤销待处理操作。
- (void)bookAudioAcquirePlayback:(void (^)(NSError *_Nullable error))completion;

/// SDK 释放系统媒体占用，或宿主已让出音频但该请求最终未开始播放时通知。
/// 回调可能对应已取消的交接，宿主应按当前音频状态决定后续操作。
- (void)bookAudioDidReleasePlayback;

@optional
/// 为原版 xh.getUserInfo 后续的 xhGetSystemInfo 调用提供标准系统资料。
/// device_token 必须沿用宿主自己的设备标识；SDK 不生成、替换或记录该标识。
/// 返回可 JSON 序列化的非空字典；缺失实现或返回无效资料会产生 UNSUPPORTED/HOST_FAILED。
- (nullable NSDictionary *)bookAudioSystemInfoFromViewController:(UIViewController *)controller;

/// 为 xhGetUserInfo 提供宿主标准资料字典（例如 id、info、phone），SDK 原样回传，不拼造字段。
/// usingTicket 为 YES 时由宿主完成票据刷新；不支持时返回错误，不得返回伪造票据。
/// 仅在已登录时调用；completion 必须返回非空且可 JSON 序列化的字典，或明确错误。
- (void)bookAudioUserInfoUsingTicket:(BOOL)usingTicket
                          completion:(void (^)(NSDictionary *_Nullable userInfo, NSError *_Nullable error))completion;

@end

NS_ASSUME_NONNULL_END
