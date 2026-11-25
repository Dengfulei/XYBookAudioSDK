// 宿主唯一业务入口；持有独立播放会话，页面关闭不销毁会话。公开方法必须在主线程调用。
#import <UIKit/UIKit.h>
#import <XYBookAudioSDK/XYBookAudioTypes.h>
#import <XYBookAudioSDK/XYBookAudioHost.h>

NS_ASSUME_NONNULL_BEGIN

/// SDK 操作回调，在主线程执行。
/// `result` 是业务结果字典，字段由具体操作定义。`error` 为执行错误，正常结算时为 nil。
typedef void (^XYBookAudioCompletion)(NSDictionary *_Nullable result, NSError *_Nullable error);

/// SDK 事件回调，在主线程执行。
/// `event` 是事件名，`parameters` 是该事件的数据，例如播放快照、当前身份或错误信息。
typedef void (^XYBookAudioEventHandler)(NSString *event, NSDictionary *parameters);

/// 听书容器的原生展示方式。
typedef NS_ENUM(NSInteger, XYBookAudioOpenStyle) {
    /// 使用 SDK 的导航容器全屏模态展示。
    XYBookAudioOpenStylePresent,
    /// 将听书首页推入宿主现有导航栈。
    XYBookAudioOpenStylePush
};

@interface XYBookAudioSDKManager : NSObject

/// 校验配置、读取宿主身份并创建独立播放会话。同一 App 内只有一个 SDK 会话可申请或持有系统音频控制权。
/// @param configuration 听书入口、可信范围和日志等配置。SDK 保存副本。
/// @param host 实现身份、登录、分享和音频交接的宿主对象。SDK 弱引用该对象，由宿主负责持有。
/// @param error 可选的错误输出地址。配置无效或宿主身份不可用时写入错误。
/// @return 新建的 SDK 实例，初始化失败时返回 nil。
- (nullable instancetype)initWithConfiguration:(XYBookAudioConfiguration *)configuration
                                          host:(id<XYBookAudioHost>)host
                                         error:(NSError **)error;
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;

/// 全屏模态打开听书容器。重复打开时返回 BUSY。
/// @param controller 当前可见、可用于展示听书容器的宿主控制器。
/// @param completion 容器展示结果回调。展示成功时 `error` 为 nil，网页加载和播放各自有独立结果。
- (void)openFromViewController:(UIViewController *)controller completion:(void (^)(NSError *_Nullable error))completion;

/// 按指定方式打开听书容器。
/// @param controller 当前可见的宿主控制器。Push 模式要求它位于现有导航栈顶部。
/// @param style 全屏模态或 Push，见 `XYBookAudioOpenStyle`。
/// @param completion 容器展示结果回调。展示成功时 `error` 为 nil。
- (void)openFromViewController:(UIViewController *)controller
                         style:(XYBookAudioOpenStyle)style
                    completion:(void (^)(NSError *_Nullable error))completion;

/// 执行原生播放命令、宿主资料查询或分享。
/// @param action 原生动作名，例如 `xhBookAudioPlay`、`xhBookAudioSeekTo` 或 `xhSnckGetUserInfo`。
/// @param parameters 该动作的业务字典。无参数时传 `@{}`，拖动进度时传入以毫秒为单位的 `positionMs`。
/// @param completion 在主线程接收业务结果或执行错误。结果字段由 `action` 决定。
- (void)executeAction:(NSString *)action
           parameters:(NSDictionary *)parameters
           completion:(XYBookAudioCompletion)completion;

/// 查询 SDK 的 H5 动作与播放能力。
/// @return 包含 H5 动作名 `actions`、支持倍速 `rates` 和定时模式 `sleepModes` 的字典。
- (NSDictionary *)getCapabilities;

/// 从当前听书页请求宿主登录，已登录时直接返回当前身份。
/// @param controller 当前可见的 SDK 页面，必须是听书窗口的栈顶页面。
/// @param completion 原生调用方的结果回调。结果含 `status` 和 `identity`，请求错误通过 `error` 返回。
/// `status` 为 `loggedIn`、`cancelled` 或 `failed`，`identity` 含 `isLoggedIn` 和 `userId`。
- (void)requestHostLoginFromViewController:(UIViewController *)controller completion:(XYBookAudioCompletion)completion;

/// 读取当前播放状态，不启动播放。
/// @return 可序列化为 JSON 的快照，包含播放状态、位置和定时信息，已装载队列时还包含当前章节信息。
- (NSDictionary *)getSnapshot;

/// 订阅 SDK 事件。
/// @param handler 在主线程接收事件名及数据。SDK 持有此回调，回调内应避免强引用 SDK。
/// @return 用于调用 `unsubscribe:` 的订阅令牌。
- (NSUUID *)subscribe:(XYBookAudioEventHandler)handler;

/// 移除指定的事件订阅。
/// @param subscription `subscribe:` 返回的令牌。未知或已移除的令牌会被忽略。
- (void)unsubscribe:(NSUUID *)subscription;

/// 宿主提交登录、退出或切换账号的状态后，于主线程调用。身份变化时停止播放并撤销上一身份的受限音源。
/// 读取到已登录身份时继续处理等待中的无 completion 登录请求。身份仍为游客时继续等待。
- (void)refreshHostIdentity;

/// 同步暂停并移除本 SDK 的系统音频控制；宿主其他播放器应在此方法返回后再激活音频。
- (void)yieldPlayback;

/// 保存位置、停止当前播放并取消定时；保留队列，后续仍可显式调用 Play。
- (void)stop;

/// 终止实例：关闭页面并释放订阅、观察者及媒体资源；可重复调用，之后不可重新打开或执行业务动作。
- (void)dispose;

@end

NS_ASSUME_NONNULL_END
