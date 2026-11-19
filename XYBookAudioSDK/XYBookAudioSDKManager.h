// 宿主唯一业务入口；持有独立播放会话，页面关闭不销毁会话。公开方法必须在主线程调用。
#import <UIKit/UIKit.h>
#import "XYBookAudioTypes.h"
#import "XYBookAudioHost.h"

NS_ASSUME_NONNULL_BEGIN
typedef void (^XYBookAudioCompletion)(NSDictionary *_Nullable result, NSError *_Nullable error);
typedef void (^XYBookAudioEventHandler)(NSString *event, NSDictionary *parameters);

@interface XYBookAudioSDKManager : NSObject

/// 复制配置并创建独立会话；无效配置／身份返回 nil 和 error，不产生网络或音频激活副作用。宿主需持有 SDK 和 host。
/// 同一个 App 内同一时间只有一个 SDK 会话可以申请或持有系统音频控制权。
- (nullable instancetype)initWithConfiguration:(XYBookAudioConfiguration *)configuration
                                          host:(id<XYBookAudioHost>)host
                                         error:(NSError **)error;
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;

/// 模态打开内置听书窗口栈；H5 可在栈内开关子页，重复打开容器返回 BUSY。
/// completion 仅表示容器已展示，不代表网页加载或播放成功。
- (void)openFromViewController:(UIViewController *)controller completion:(void (^)(NSError *_Nullable error))completion;

/// 执行已确认的播放命令、宿主资料查询及分享；parameters 为业务参数，completion 在主线程返回结果或错误，日志不改变回执。
- (void)executeAction:(NSString *)action
           parameters:(NSDictionary *)parameters
           completion:(XYBookAudioCompletion)completion;

/// 返回已确认的 H5 动作、倍速与定时能力，不要求或输出协议版本。
- (NSDictionary *)getCapabilities;
/// 从 SDK 当前可见页面请求宿主登录；主要供内置 H5 使用，不产生自定义 H5 登录回执。
- (void)requestHostLoginFromViewController:(UIViewController *)controller completion:(XYBookAudioCompletion)completion;

/// 返回可用于 JSON 的只读快照，不含音源地址；获取快照不启动播放。
- (NSDictionary *)getSnapshot;

/// 持有事件回调并返回订阅令牌；回调在主线程触发，调用方应避免通过回调强引用 SDK。
- (NSUUID *)subscribe:(XYBookAudioEventHandler)handler;

/// 释放指定订阅；未知令牌无副作用。关闭页面只清理页面自身订阅。
- (void)unsubscribe:(NSUUID *)subscription;

/// 宿主登录、退出或切换账号后调用；撤销上一身份的受限音源，并按规则暂停付费章节。
- (void)refreshHostIdentity;

/// 同步暂停并移除本 SDK 的系统音频控制；宿主其他播放器应在此方法返回后再激活音频。
- (void)yieldPlayback;

/// 保存位置、停止当前播放并取消定时；保留队列，后续仍可显式调用 Play。
- (void)stop;

/// 终止实例：关闭页面并释放订阅、观察者及媒体资源；可重复调用，之后不可重新打开或执行业务动作。
- (void)dispose;

@end

NS_ASSUME_NONNULL_END
