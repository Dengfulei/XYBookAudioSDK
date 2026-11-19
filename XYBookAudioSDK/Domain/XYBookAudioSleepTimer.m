// 只持有定时状态；按时间到期或自然完成次数结算，命中后立即关闭，避免重复触发。
#import "XYBookAudioSleepTimer.h"
#import "XYBookAudioMessageProtocol.h"

@interface XYBookAudioSleepTimer ()

@property (nonatomic, copy) NSTimeInterval (^clock)(void);
@property (nonatomic, copy, readwrite) NSString *mode;
@property (nonatomic) double deadline, durationMs;
@property (nonatomic) NSInteger targetCount, remainingCount;
@property (nonatomic, strong) NSMutableSet<NSUUID *> *completed;

@end

@implementation XYBookAudioSleepTimer

/// 使用可注入的连续时钟；设备休眠仍计入时长，测试不依赖真实等待。
- (instancetype)initWithClock:(NSTimeInterval (^)(void))clock {
    if ((self = [super init])) {
        _clock = [clock copy];
        [self cancel];
    }
    return self;
}

/// 验证全部参数后才替换定时；非法新配置不会取消已生效的定时。
- (BOOL)configure:(NSDictionary *)parameters hasCurrentChapter:(BOOL)hasCurrent error:(NSError **)error {
    NSString *mode = parameters[XYBookAudioKeyMode];
    BOOL countMode = [mode isKindOfClass:NSString.class] && [mode isEqualToString:XYBookAudioValueTrackCount];
    BOOL durationMode = [mode isKindOfClass:NSString.class] && [mode isEqualToString:XYBookAudioValueDuration];
    BOOL valid = (countMode && XYBookAudioNumber(parameters[XYBookAudioKeyCount], 1, INT_MAX, YES)) ||
                 (durationMode && XYBookAudioNumber(parameters[XYBookAudioKeyDurationMs], 1, INT_MAX, YES));
    if (!valid || (countMode && !hasCurrent)) {
        if (error) {
            *error = XYBookAudioError(valid ? XYBookAudioInvalidState : XYBookAudioInvalidArgument,
                                      valid ? @"A current chapter is required."
                                            : @"Expected durationMs or a positive integer count with its mode.");
        }
        return NO;
    }
    [self cancel];
    self.mode = mode;
    self.durationMs = durationMode ? [parameters[XYBookAudioKeyDurationMs] doubleValue] : 0;
    self.deadline = self.clock() + self.durationMs / 1000.0;
    self.targetCount = countMode ? [parameters[XYBookAudioKeyCount] integerValue] : 0;
    self.remainingCount = self.targetCount;
    return YES;
}

/// 清空截止时间和已完成实例集合；不改变播放器状态。
- (void)cancel {
    self.mode = XYBookAudioValueOff;
    self.completed = [NSMutableSet set];
    self.remainingCount = 0;
    self.targetCount = 0;
    self.durationMs = 0;
    self.deadline = 0;
}

/// 按绝对截止时间结算一次；即使进度回调因后台挂起延迟，也不会重新计算一个完整时长。
- (BOOL)consumeDeadline {
    if (![self.mode isEqualToString:XYBookAudioValueDuration] || self.clock() < self.deadline) {
        return NO;
    }
    [self cancel];
    return YES;
}

/// 同一播放实例只扣一次计数；调用方必须区分自然播完与拖动／跳章。
- (BOOL)consumeNaturalCompletion:(NSUUID *)playbackInstance {
    if (![self.mode isEqualToString:XYBookAudioValueTrackCount] || [self.completed containsObject:playbackInstance]) {
        return NO;
    }
    [self.completed addObject:playbackInstance];
    self.remainingCount--;
    if (self.remainingCount > 0) {
        return NO;
    }
    [self cancel];
    return YES;
}

- (NSDictionary *)snapshot {
    if ([self.mode isEqualToString:XYBookAudioValueDuration]) {
        return @{
            XYBookAudioKeyMode : self.mode,
            XYBookAudioKeyDurationMs : @(self.durationMs),
            XYBookAudioKeyRemainingMs : @(MAX(0, (self.deadline - self.clock()) * 1000))
        };
    }
    if ([self.mode isEqualToString:XYBookAudioValueTrackCount]) {
        return @{
            XYBookAudioKeyMode : self.mode,
            XYBookAudioKeyTargetCount : @(self.targetCount),
            XYBookAudioKeyRemainingCount : @(self.remainingCount)
        };
    }
    return @{XYBookAudioKeyMode : XYBookAudioValueOff};
}

@end
