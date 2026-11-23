// 编排播放器 IO、系统媒体、定时与断点；不请求业务内容或购买权益，状态变化由快照统一发布。
#import "XYBookAudioSessionInternal.h"
#import <mach/mach_time.h>

static const NSTimeInterval XYBookAudioCheckpointInterval = 5;

static NSTimeInterval XYBookAudioContinuousTime(void) {
    mach_timebase_info_data_t info;
    mach_timebase_info(&info);
    return (double)mach_continuous_time() * info.numer / info.denom / NSEC_PER_SEC;
}

@implementation XYBookAudioSession

- (instancetype)initWithConfiguration:(XYBookAudioConfiguration *)configuration
                                 host:(id<XYBookAudioHost>)host
                               logger:(XYBookAudioLogger *)logger {
    if ((self = [super init])) {
        _configuration = configuration;
        _logger = logger;
        _host = host;
        _identity = [host bookAudioUserIdentity];
        _rate = 1;
        _index = 0;
        _stateOverride = XYBookAudioValueIdle;
        _engine = [XYBookAudioEngine new];
        _media = [[XYBookAudioSystemMedia alloc] initWithLogger:logger];
        _sleepTimer = [[XYBookAudioSleepTimer alloc] initWithClock:^{
            return XYBookAudioContinuousTime();
        }];
        _store = [[XYBookAudioCheckpointStore alloc] initWithHost:configuration.hostIdentifier
                                                      environment:configuration.environment];
        [self bindEvents];
    }
    return self;
}

/// 连接播放器和系统事件；弱引用避免定时器／通知持有会话，所有状态更新回到主线程。
- (void)bindEvents {
    __weak typeof(self) weakSelf = self;
    self.engine.changed = ^{
        [weakSelf tick];
    };
    self.engine.finished = ^(BOOL natural, NSUUID *instance) {
        [weakSelf finish:natural instance:instance];
    };
    self.engine.failed = ^(NSError *error) {
        [weakSelf.logger error:error component:XYBookAudioLogPlayback operation:@"Audio source playback"];
        [weakSelf.engine pause];
        weakSelf.stateOverride = XYBookAudioValueFailed;
        [weakSelf save];
        [weakSelf report:XYBookAudioError(XYBookAudioPlaybackFailed,
                                          @"The audio source could not be played. Supply a fresh source and retry.")];
        [weakSelf publish];
    };
    self.media.command = ^(NSString *action, NSDictionary *parameters) {
        if ([action isEqual:XYBookAudioCommandToggle]) {
            action = [weakSelf.engine.state isEqual:XYBookAudioValuePlaying] ? XYBookAudioCommandPause
                                                                             : XYBookAudioCommandPlay;
        }
        [weakSelf execute:action parameters:parameters completion:^(NSDictionary *result, NSError *error) {
            if (error) {
                [weakSelf report:error];
            }
        }];
    };
    self.media.interruption = ^(BOOL began, BOOL shouldResume) {
        [weakSelf interrupted:began resume:shouldResume];
    };
    self.media.routeLost = ^{
        [weakSelf.logger write:XYBookAudioLogLevelInfo component:XYBookAudioLogAudio
                       message:@"Output device disconnected; pausing."];
        [weakSelf execute:XYBookAudioCommandPause parameters:@{} completion:^(NSDictionary *result, NSError *error){
        }];
    };
    self.media.mediaReset = ^{
        [weakSelf.logger write:XYBookAudioLogLevelWarning component:XYBookAudioLogAudio
                       message:@"System audio services reset."];
        [weakSelf yieldPlayback];
        [weakSelf.engine clear];
        weakSelf.stateOverride = XYBookAudioValuePaused;
        [weakSelf
            report:XYBookAudioError(XYBookAudioPlaybackFailed, @"System audio services restarted; resume explicitly.")];
    };
    self.ticker = [NSTimer timerWithTimeInterval:XYBookAudioProgressInterval repeats:YES block:^(NSTimer *timer) {
        [weakSelf tick];
    }];
    [NSRunLoop.mainRunLoop addTimer:self.ticker forMode:NSRunLoopCommonModes];
    self.backgroundObserver =
        [NSNotificationCenter.defaultCenter addObserverForName:UIApplicationDidEnterBackgroundNotification object:nil
                                                         queue:NSOperationQueue.mainQueue
                                                    usingBlock:^(NSNotification *note) {
                                                        if ([weakSelf refreshIdentity]) {
                                                            [weakSelf save];
                                                        }
                                                    }];
}

- (XYBookAudioChapter *)chapter {
    return self.queue && self.index < (NSInteger)self.queue.chapters.count ? self.queue.chapters[self.index] : nil;
}

/// 生成当前业务快照；仅输出展示状态和位置，不返回可能过期或包含鉴权的音源地址。
- (NSDictionary *)snapshot {
    NSMutableDictionary *result = [@{
        XYBookAudioKeyState : self.stateOverride ?: self.engine.state,
        XYBookAudioKeyRate : @(self.rate),
        XYBookAudioKeyPositionMs : @(self.engine.hasItem ? self.engine.positionMs : self.position),
        XYBookAudioKeySleepTimer : [self timerSnapshot]
    } mutableCopy];
    if (!self.queue) {
        return result;
    }
    XYBookAudioChapter *chapter = [self chapter];
    [result addEntriesFromDictionary:@{
        XYBookAudioKeyBookID : self.queue.bookId,
        XYBookAudioKeyTitle : self.queue.title,
        XYBookAudioKeyChapterID : chapter.chapterId,
        XYBookAudioKeyChapterTitle : chapter.title,
        XYBookAudioKeyChapterIndex : @(self.index),
        XYBookAudioKeyChapterCount : @(self.queue.chapters.count)
    }];
    double duration = self.engine.durationMs > 0 ? self.engine.durationMs : chapter.durationMs.doubleValue;
    if (duration > 0) {
        result[XYBookAudioKeyDurationMs] = @(duration);
    }
    if (self.reason) {
        result[XYBookAudioKeyReason] = self.reason;
    }
    return result;
}

- (NSDictionary *)snckUserState {
    XYBookAudioIdentity *identity = self.identity;
    id user = identity.isLoggedIn
                  ? @{@"id" : identity.userId, @"nickname" : @"", @"avatarUrl" : NSNull.null, @"extensions" : @{}}
                  : NSNull.null;
    return @{
        @"guest" : @(!identity.isLoggedIn),
        @"initialization" : identity.isLoggedIn ? @"AUTHENTICATED" : @"GUEST",
        @"user" : user
    };
}

- (XYBookAudioTimerChange)snckTimerChange {
    return self.sleepTimer.lastChange;
}

- (NSDictionary *)snckPlayback {
    NSArray *items = self.queue.snckItems ?: @[];
    BOOL hasQueue = items.count > 0;
    BOOL preparing = self.acquiring && self.acquisitionGeneration == self.generation;
    NSString *state = self.stateOverride ?: self.engine.state;
    NSString *snckState = @"IDLE";
    if (hasQueue) {
        if ([state isEqual:XYBookAudioValuePlaying]) {
            snckState = @"PLAYING";
        } else if (preparing || [state isEqual:XYBookAudioValueBuffering]) {
            snckState = @"BUFFERING";
        } else if ([state isEqual:XYBookAudioValueFailed]) {
            snckState = @"ERROR";
        } else if ([state isEqual:XYBookAudioValueCompleted] && self.index == (NSInteger)items.count - 1) {
            snckState = @"ENDED";
        } else {
            snckState = @"PAUSED";
        }
    }
    NSDictionary *timer = hasQueue ? [self.sleepTimer snapshot] : @{};
    NSDictionary *modes = @{
        XYBookAudioValueDuration : XYBookAudioSnckTimerModeAfterDuration,
        XYBookAudioValueTrackCount : XYBookAudioSnckTimerModeAfterItems
    };
    NSString *mode = timer[XYBookAudioKeyMode];
    NSMutableDictionary *snckTimer = [@{
        XYBookAudioKeyMode : (mode ? modes[mode] : nil) ?: XYBookAudioSnckTimerModeOff,
        XYBookAudioKeyRemainingCount : timer[XYBookAudioKeyRemainingCount] ?: @0,
        XYBookAudioKeyRemainingMs : @(llround([timer[XYBookAudioKeyRemainingMs] doubleValue]))
    } mutableCopy];
    if ([mode isEqual:XYBookAudioValueDuration]) {
        snckTimer[XYBookAudioKeyDeadlineElapsedMs] = @(llround(self.sleepTimer.deadline * 1000));
    }
    return @{
        @"stateVersion" : @(self.stateVersion),
        XYBookAudioKeyQueueVersion : @(self.queueVersion),
        XYBookAudioKeyItems : items,
        XYBookAudioKeyIndex : @(hasQueue ? self.index : -1),
        @"item" : hasQueue ? items[self.index] : NSNull.null,
        XYBookAudioKeyState : snckState,
        XYBookAudioKeyPlaying : @([snckState isEqual:@"PLAYING"]),
        XYBookAudioKeyPlayWhenReady :
            @(hasQueue && (self.engine.wantsPlayback || preparing || self.resumeAfterInterruption)),
        XYBookAudioKeyPositionMs :
            @(hasQueue ? llround(self.engine.hasItem ? self.engine.positionMs : self.position) : 0),
        XYBookAudioKeyDurationMs : @(hasQueue ? llround(self.engine.durationMs) : 0),
        @"bufferedPositionMs" : @(hasQueue ? llround(self.engine.bufferedPositionMs) : 0),
        XYBookAudioKeyTimer : snckTimer
    };
}

/// 剩余时长只用于展示；缺失时长或无访问权限的章节不按零时长估算。
- (NSDictionary *)timerSnapshot {
    NSMutableDictionary *timer = [[self.sleepTimer snapshot] mutableCopy];
    if (![timer[XYBookAudioKeyMode] isEqual:XYBookAudioValueTrackCount] || !self.queue) {
        return timer;
    }
    NSInteger count = MIN([timer[XYBookAudioKeyRemainingCount] integerValue], self.queue.chapters.count - self.index);
    double duration = 0;
    for (NSInteger offset = 0; offset < count; offset++) {
        XYBookAudioChapter *chapter = self.queue.chapters[self.index + offset];
        if (!chapter.audioURL || (chapter.requiresLogin && !self.identity.isLoggedIn)) {
            return timer;
        }
        double chapterDuration =
            offset == 0 && self.engine.durationMs > 0 ? self.engine.durationMs : chapter.durationMs.doubleValue;
        if (chapterDuration <= 0) {
            return timer;
        }
        duration += offset == 0
                        ? MAX(0, chapterDuration - (self.engine.hasItem ? self.engine.positionMs : self.position))
                        : chapterDuration;
    }
    timer[XYBookAudioKeyEstimatedRemainingMs] = @(duration / self.rate);
    return timer;
}

/// 更新锁屏信息并发布快照；日志只记录状态变化，周期进度更新不会重复刷屏。
- (void)publish {
    if (self.disposed) {
        return;
    }
    self.stateVersion++;
    NSDictionary *snapshot = [self snapshot];
    self.lastPublish = XYBookAudioContinuousTime();
    if (![self.lastPublishedState isEqual:snapshot[XYBookAudioKeyState]]) {
        [self.logger write:XYBookAudioLogLevelInfo component:XYBookAudioLogPlayback
                   message:[NSString stringWithFormat:@"State changed: %@ -> %@.",
                                                      self.lastPublishedState ?: XYBookAudioValueIdle,
                                                      snapshot[XYBookAudioKeyState]]];
    }
    self.lastPublishedState = snapshot[XYBookAudioKeyState];
    [self.media update:snapshot artwork:self.artwork];
    if (self.event) {
        self.event(XYBookAudioEventPlaybackChanged, snapshot);
    }
}

/// 通过事件上报业务错误，同时按配置写入脱敏日志；关闭日志不会关闭错误回调。
- (void)report:(NSError *)error {
    [self.logger error:error component:XYBookAudioLogPlayback operation:@"Playback session"];
    if (self.event) {
        self.event(
            XYBookAudioEventError,
            @{XYBookAudioKeyCode : XYBookAudioErrorName(error), XYBookAudioKeyMessage : error.localizedDescription});
    }
}

/// 先判断定时到期，再同步播放位置和断点；不依赖进度回调准时触发来保证截止时间。
- (void)tick {
    if (self.disposed) {
        return;
    }
    if ([self expireTimer]) {
        return;
    }
    if (self.engine.hasItem) {
        self.position = self.engine.positionMs;
    }
    if (XYBookAudioContinuousTime() - self.lastSave >= XYBookAudioCheckpointInterval &&
        [self.engine.state isEqual:XYBookAudioValuePlaying]) {
        [self save];
    }
    NSString *state = self.stateOverride ?: self.engine.state;
    if (self.queue && (XYBookAudioContinuousTime() - self.lastPublish >= XYBookAudioProgressInterval ||
                       ![state isEqual:self.lastPublishedState])) {
        [self publish];
    }
}

/// 断点写入最初装载队列时的身份空间，避免切换账号后把旧队列进度写给新用户。
- (void)save {
    if (!self.queue || self.queue.snckItems) {
        return;
    }
    if (self.engine.hasItem) {
        self.position = self.engine.positionMs;
    }
    NSError *error;
    BOOL saved = [self.store saveBook:self.queue.bookId chapter:self.chapter.chapterId position:self.position
                             identity:self.checkpointIdentity
                                error:&error];
    self.lastSave = XYBookAudioContinuousTime();
    if (!saved) {
        [self.logger error:error component:XYBookAudioLogStorage operation:@"Checkpoint write"];
    }
    if (!saved) {
        [self report:XYBookAudioError(XYBookAudioStorageFailed, @"Unable to save the playback checkpoint.")];
    }
}

/// 截止时间命中后撤销待处理播放请求并暂停；定时策略结算一次，恢复前需用户显式操作。
- (BOOL)expireTimer {
    return [self expireTimerReleasingSystemPlayback:NO];
}

- (BOOL)expireTimerReleasingSystemPlayback:(BOOL)releasePlayback {
    if (![self.sleepTimer consumeDeadline]) {
        return NO;
    }
    self.generation++;
    self.resumeAfterInterruption = NO;
    [self.engine pause];
    self.stateOverride = XYBookAudioValuePaused;
    self.reason = XYBookAudioValueSleepDuration;
    if (releasePlayback) {
        [self releaseSystemPlayback];
    }
    [self.logger write:XYBookAudioLogLevelInfo component:XYBookAudioLogPlayback
               message:@"Sleep duration elapsed; playback paused."];
    [self save];
    [self publish];
    return YES;
}

/// 先保存位置，再处理自然播完计数、时间截止和队尾；用户拖到末尾不消耗自然完成次数。
- (void)finish:(BOOL)natural instance:(NSUUID *)instance {
    [self save];
    if (natural && [self.sleepTimer consumeNaturalCompletion:instance]) {
        [self.logger write:XYBookAudioLogLevelInfo component:XYBookAudioLogPlayback
                   message:@"Sleep chapter count reached."];
        self.reason = XYBookAudioValueSleepTrackCount;
        self.stateOverride = XYBookAudioValueCompleted;
        [self publish];
        return;
    }
    if ([self expireTimer]) {
        return;
    }
    if (self.index + 1 >= (NSInteger)self.queue.chapters.count) {
        [self.sleepTimer queueDidEnd];
        self.reason = XYBookAudioValueQueueEnded;
        self.stateOverride = XYBookAudioValueCompleted;
        [self publish];
        return;
    }
    self.index++;
    self.position = 0;
    [self.engine clear];
    [self loadArtwork];
    [self play:^(NSDictionary *result, NSError *error) {
        if (error) {
            [self report:error];
        }
    }];
}

/// 身份变化时停止播放并撤销旧音源权限，原生队列的断点仍归装载时的身份。
- (BOOL)refreshIdentity {
    XYBookAudioIdentity *identity = [self.host bookAudioUserIdentity];
    // 身份读取失败时必须撤销播放，不能继续使用缓存账号为当前操作授权。
    if (!identity) {
        [self yieldPlayback];
        self.stateOverride = XYBookAudioValueBlocked;
        NSError *error = XYBookAudioError(XYBookAudioHostFailed, @"Host did not supply a user identity.");
        self.reason = XYBookAudioErrorName(error);
        [self report:error];
        [self publish];
        return NO;
    }
    if ([self.identity.userId isEqual:identity.userId]) {
        return YES;
    }
    self.identity = identity;
    if (self.queue.snckItems) {
        [self clearSnckQueue];
    } else if (self.queue) {
        for (XYBookAudioChapter *chapter in self.queue.chapters) {
            if (chapter.requiresLogin) {
                chapter.audioURL = nil;
            }
        }
        [self stopCurrentPlayback];
    }
    [self.logger write:XYBookAudioLogLevelInfo component:XYBookAudioLogHost
               message:@"Identity changed; previous restricted sources revoked."];
    if (self.event) {
        self.event(XYBookAudioEventUserIdentityChanged,
                   @{XYBookAudioKeyIsLoggedIn : @(identity.isLoggedIn), XYBookAudioKeyUserID : identity.userId});
    }
    [self publish];
    return YES;
}

/// 中断开始时保存暂停前意图；结束后仅在系统允许且当前身份、定时规则仍满足时尝试恢复。
- (void)interrupted:(BOOL)began resume:(BOOL)shouldResume {
    [self.logger write:XYBookAudioLogLevelInfo component:XYBookAudioLogAudio
               message:began ? @"Audio interruption began." : @"Audio interruption ended."];
    if (began) {
        self.resumeAfterInterruption = [self.engine.state isEqual:XYBookAudioValuePlaying] ||
                                       [self.engine.state isEqual:XYBookAudioValueBuffering];
        [self.engine pause];
        [self save];
        [self publish];
        return;
    }
    BOOL resume = self.resumeAfterInterruption && shouldResume;
    self.resumeAfterInterruption = NO;
    if (resume) {
        [self play:^(NSDictionary *result, NSError *error) {
            if (error) {
                [self report:error];
            }
        }];
    }
}

/// 撤销异步播放代次，保存断点并释放自己的系统媒体占用；不会自动重新抢占音频。
- (void)yieldPlayback {
    [self suspendPlayback];
    self.reason = XYBookAudioValueHostTakeover;
    [self publish];
}

- (void)suspendPlayback {
    [self pauseAndSavePlayback];
    [self releaseSystemPlayback];
}

- (void)pauseAndSavePlayback {
    self.generation++;
    self.resumeAfterInterruption = NO;
    [self.engine pause];
    [self save];
}

- (void)clearSnckQueue {
    [self pauseAndSavePlayback];
    [self.engine clear];
    [self.sleepTimer cancel];
    if (self.queue.snckItems) {
        self.queueVersion++;
    }
    self.queue = nil;
    self.index = 0;
    self.position = 0;
    self.stateOverride = XYBookAudioValueIdle;
    self.reason = nil;
    [self loadArtwork];
    [self releaseSystemPlayback];
}

- (void)releaseSystemPlayback {
    BOOL active = self.media.active;
    [self.media releasePlayback];
    if (active) {
        [self.host bookAudioDidReleasePlayback];
    }
}

/// 保留队列但清空播放器项目与定时器；下次 Play 将从已保存位置重新装载。
- (void)stop {
    [self stopCurrentPlayback];
    [self publish];
}

- (void)stopCurrentPlayback {
    [self pauseAndSavePlayback];
    [self.engine clear];
    [self.sleepTimer cancel];
    self.stateOverride = XYBookAudioValueStopped;
    self.reason = XYBookAudioValueStopped;
    [self releaseSystemPlayback];
}

/// 释放定时器、播放器、系统通知和封面任务；幂等执行，不影响其他 SDK 实例的日志或订阅。
- (void)dispose {
    if (self.disposed) {
        return;
    }
    [self stop];
    self.disposed = YES;
    [self.ticker invalidate];
    [self.engine dispose];
    [self.media dispose];
    [self.artworkTask cancel];
    [NSNotificationCenter.defaultCenter removeObserver:self.backgroundObserver];
    self.backgroundObserver = nil;
    self.event = nil;
}

/// SNCK 使用当前曲目的封面，只接受仍在使用的下载结果。
- (void)loadArtwork {
    NSString *coverURL = self.queue.coverURL;
    NSURL *URL = coverURL ? [NSURL URLWithString:coverURL] : nil;
    if (self.queue.snckItems) {
        URL = XYBookAudioParseSnckURL(self.queue.snckItems[self.index][@"coverUrl"]);
    }
    if ([URL isEqual:self.artworkURL] && (self.artwork || self.artworkTask)) {
        return;
    }

    [self.artworkTask cancel];
    self.artworkTask = nil;
    self.artwork = nil;
    self.artworkURL = URL;
    if (!URL) {
        return;
    }

    __weak typeof(self) weakSelf = self;
    __block __weak NSURLSessionDataTask *weakTask;
    NSURLSessionDataTask *task = [NSURLSession.sharedSession
          dataTaskWithURL:URL completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
              dispatch_async(dispatch_get_main_queue(), ^{
                  XYBookAudioSession *session = weakSelf;
                  NSURLSessionDataTask *completedTask = weakTask;
                  if (!completedTask || session.disposed || session.artworkTask != completedTask) {
                      return;
                  }
                  session.artworkTask = nil;
                  if (error.code == NSURLErrorCancelled) {
                      return;
                  }
                  UIImage *image = data.length <= 5 * 1024 * 1024 ? [UIImage imageWithData:data] : nil;
                  if (image) {
                      session.artwork = image;
                      [session publish];
                  } else {
                      [session report:XYBookAudioError(XYBookAudioSourceNotReady,
                                                       @"Cover artwork could not be loaded; audio remains available.")];
                  }
              });
          }];
    weakTask = task;
    self.artworkTask = task;
    [task resume];
}

- (void)dealloc {
    [self dispose];
}

@end
