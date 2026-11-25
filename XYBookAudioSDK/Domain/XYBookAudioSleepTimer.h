// 纯定时规则：通过注入连续时钟验证休眠计时；不控制播放器、不处理页面生命周期。
#import "XYBookAudioMessageProtocol.h"

@interface XYBookAudioSleepTimer : NSObject

@property (nonatomic, copy, readonly) NSString *mode;
@property (nonatomic, readonly) double deadline;
@property (nonatomic, readonly) XYBookAudioTimerChange lastChange;

/// 创建初始为关闭状态的定时器。
/// @param clock 连续时钟，返回以秒计的时间。生产时钟须将设备休眠计入经过时间。
- (instancetype)initWithClock:(NSTimeInterval (^)(void))clock;

/// 更新定时。全部参数有效后才替换当前定时。
/// @param parameters 定时模式和对应的 `count` 或 `durationMs`。
/// @param hasCurrent 按章节计数时是否有当前章节。
/// @param error 可选的校验错误输出地址。
/// @return 新定时已生效时返回 YES。
- (BOOL)configure:(NSDictionary *)parameters hasCurrentChapter:(BOOL)hasCurrent error:(NSError **)error;

/// 更新定时并使用调用方指定的时长上限。
/// @param parameters 定时模式和对应的 `count` 或 `durationMs`。
/// @param hasCurrent 按章节计数时是否有当前章节。
/// @param maximumDuration 可接受的最大定时时长，单位为毫秒。
/// @param error 可选的校验错误输出地址。
/// @return 新定时已生效时返回 YES。
- (BOOL)configure:(NSDictionary *)parameters
    hasCurrentChapter:(BOOL)hasCurrent
    maximumDurationMs:(double)maximumDuration
                error:(NSError **)error;

/// 关闭定时并记录设置变更。
- (void)cancel;
/// 队列到达末尾时关闭定时并记录队列结束。
- (void)queueDidEnd;

/// 按连续时钟检查时长定时，触发时关闭定时。
/// @return 本次检查触发到期时返回 YES。
- (BOOL)consumeDeadline;

/// 在当前章节自然播完时消耗一次计数。同一播放实例只计一次。
/// @param playbackInstance 自然播完的章节实例标识。
/// @return 本次扣减触发到期时返回 YES。
- (BOOL)consumeNaturalCompletion:(NSUUID *)playbackInstance;

/// @return 当前模式及对应的剩余章节数或剩余毫秒数。
- (NSDictionary *)snapshot;

@end
