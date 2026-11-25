// 页面和原生入口共用的播放会话；主线程持有队列、身份、进度与定时状态，不依赖页面存活。
#import "XYBookAudioLogger.h"
#import "XYBookAudioMessageProtocol.h"
#import "XYBookAudioSDKManager.h"

@interface XYBookAudioSession : NSObject

@property (nonatomic, copy) XYBookAudioEventHandler event;

/// 初始化播放器、定时器和断点存储，并连接会话事件。
/// @param configuration 当前 SDK 已校验的配置，其中的宿主名和环境用于隔离断点。
/// @param host 提供账号身份及音频交接的宿主对象，由调用方持有。
/// @param logger 当前 SDK 实例的日志出口。
- (instancetype)initWithConfiguration:(XYBookAudioConfiguration *)configuration
                                 host:(id<XYBookAudioHost>)host
                               logger:(XYBookAudioLogger *)logger;

/// @return 原生播放快照，位置与时长使用毫秒。
- (NSDictionary *)snapshot;
/// @return SNCK v1 播放快照，包含队列版本、当前曲目和定时状态。
- (NSDictionary *)snckPlayback;
/// @return 最近一次定时状态变化的原因。
- (XYBookAudioTimerChange)snckTimerChange;
/// @return SNCK 用户状态，含游客标记和当前用户标识。
- (NSDictionary *)snckUserState;

/// 重新读取宿主身份。账号变化时撤销上一身份的播放权限。
/// @return 身份可用时返回 YES。读取失败时先暂停并释放音频，再返回 NO。
- (BOOL)refreshIdentity;

/// 暂停、保存播放位置并让出系统音频占用。
- (void)yieldPlayback;
/// 停止播放并取消定时，保留队列。
- (void)stop;
/// 停止播放并释放会话持有的系统资源。
- (void)dispose;

@end

@interface XYBookAudioSession (Commands)

/// 执行原生播放命令。
/// @param command 命令名，例如 `Play` 或 `SeekTo`，已由调用方去掉 `xhBookAudio` 前缀。
/// @param parameters 命令参数，无参数的命令传空字典。
/// @param completion 接收原生播放快照或执行错误。
- (void)execute:(NSString *)command parameters:(NSDictionary *)parameters completion:(XYBookAudioCompletion)completion;

/// 按 SNCK v1 解释参数并执行播放命令。
/// @param command 从 H5 动作映射出的命令名，例如 `SetQueue` 或 `GetTimer`。
/// @param parameters 原始 SNCK 业务参数。
/// @param completion 接收命令对应的 SNCK 结果或执行错误。
- (void)executeSnckAudio:(NSString *)command
              parameters:(NSDictionary *)parameters
              completion:(XYBookAudioCompletion)completion;

@end
