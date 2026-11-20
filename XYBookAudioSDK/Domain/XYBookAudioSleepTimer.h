// 纯定时规则：通过注入连续时钟验证休眠计时；不控制播放器、不处理页面生命周期。
#import "XYBookAudioTypes.h"

@interface XYBookAudioSleepTimer : NSObject

@property (nonatomic, copy, readonly) NSString *mode;
@property (nonatomic, readonly) double deadline;
- (instancetype)initWithClock:(NSTimeInterval (^)(void))clock;

/// 非法替换不改变当前定时；仅在全部参数有效时提交新计时状态。
- (BOOL)configure:(NSDictionary *)parameters hasCurrentChapter:(BOOL)hasCurrent error:(NSError **)error;
- (BOOL)configure:(NSDictionary *)parameters
    hasCurrentChapter:(BOOL)hasCurrent
    maximumDurationMs:(double)maximumDuration
                error:(NSError **)error;
- (void)cancel;

/// 时长到期时仅返回一次 YES；不依赖周期进度回调是否准时触发。
- (BOOL)consumeDeadline;

/// 仅对不同播放实例的自然完成计数；拖动或用户跳章不能调用此方法。
- (BOOL)consumeNaturalCompletion:(NSUUID *)playbackInstance;
- (NSDictionary *)snapshot;

@end
