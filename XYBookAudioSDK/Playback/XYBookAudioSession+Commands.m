// 播放命令应用层：校验输入与权限，再执行队列替换、音频交接、拖动和切章；不读取 H5 页面状态。
#import "XYBookAudioSessionInternal.h"

@implementation XYBookAudioSession (Commands)

- (void)executeSnckAudio:(NSString *)command
              parameters:(NSDictionary *)parameters
              completion:(XYBookAudioCompletion)completion {
    if (self.disposed) {
        completion(nil, XYBookAudioError(XYBookAudioDisposed, @"The session has been disposed."));
        return;
    }
    if ([command isEqual:@"GetState"]) {
        completion([self snckPlayback], nil);
        return;
    }
    if ([command isEqual:@"GetQueue"]) {
        completion(@{@"items" : self.queue.snckItems ?: @[], @"queueVersion" : @(self.queueVersion)}, nil);
        return;
    }
    if ([command isEqual:@"GetTimer"]) {
        completion([self snckPlayback][@"timer"], nil);
        return;
    }
    if ([command isEqual:XYBookAudioCommandStop]) {
        if (self.queue.snckItems) {
            [self clearSnckQueue];
        }
        completion([self snckPlayback], nil);
        return;
    }
    XYBookAudioCompletion finish = ^(NSDictionary *result, NSError *error) {
        completion(error ? nil : [self snckPlayback], error);
    };
    if ([command isEqual:XYBookAudioCommandSetQueue]) {
        NSError *error = nil;
        XYBookAudioQueue *queue = [XYBookAudioQueue queueWithSnckParameters:parameters error:&error];
        if (!queue) {
            finish(nil, error);
            return;
        }
        [self installQueue:queue index:[parameters[@"startIndex"] integerValue] position:0 identity:self.identity];
        [self publish];
        if ([parameters[@"autoPlay"] boolValue]) {
            [self play:finish];
        } else {
            finish(nil, nil);
        }
        return;
    }
    if ([command isEqual:@"SetTimer"] && [parameters[@"mode"] isEqual:@"OFF"]) {
        if (self.queue.snckItems) {
            [self execute:XYBookAudioCommandCancelSleepTimer parameters:@{} completion:finish];
        } else {
            finish(nil, nil);
        }
        return;
    }
    if (!self.queue.snckItems) {
        finish(nil, XYBookAudioError(XYBookAudioInvalidArgument, @"SetQueue is required before this command."));
        return;
    }
    if ([command isEqual:@"SetTimer"]) {
        NSDictionary *modes =
            @{@"AFTER_ITEMS" : XYBookAudioValueTrackCount, @"AFTER_DURATION" : XYBookAudioValueDuration};
        id mode = modes[parameters[@"mode"] ?: NSNull.null] ?: NSNull.null;
        NSMutableDictionary *timer = [parameters mutableCopy];
        timer[XYBookAudioKeyMode] = mode;
        NSError *error = nil;
        if ([self.sleepTimer configure:timer hasCurrentChapter:YES maximumDurationMs:9007199254740991.0 error:&error]) {
            [self publish];
        }
        finish(nil, error);
        return;
    }
    if ([command isEqual:@"PlayAt"]) {
        id index = parameters[@"index"];
        if (!XYBookAudioNumber(index, 0, self.queue.chapters.count - 1, YES)) {
            finish(nil, XYBookAudioError(XYBookAudioInvalidArgument, @"index is outside the queue."));
            return;
        }
        [self selectIndex:[index integerValue] completion:finish];
        return;
    }
    if ([command isEqual:XYBookAudioCommandSeekTo]) {
        double duration = self.engine.durationMs;
        double limit = duration > 0 ? round(duration) : 9007199254740991.0;
        if (!XYBookAudioNumber(parameters[XYBookAudioKeyPositionMs], 0, limit, YES)) {
            finish(nil, XYBookAudioError(XYBookAudioInvalidArgument, @"positionMs is invalid or beyond the duration."));
            return;
        }
    }
    [self execute:command parameters:parameters completion:finish];
}

/// 命令按业务职责分发；只有成功变更才发布新快照，异步播放／拖动由对应流程结算。
- (void)execute:(NSString *)command parameters:(NSDictionary *)parameters completion:(XYBookAudioCompletion)completion {
    if (self.disposed) {
        completion(nil, XYBookAudioError(XYBookAudioDisposed, @"The session has been disposed."));
        return;
    }
    if ([command isEqual:XYBookAudioCommandPlay]) {
        [self play:completion];
        return;
    }
    NSError *error;
    if ([command isEqual:XYBookAudioCommandSetQueue]) {
        error = [self replaceQueue:parameters];
    } else if ([command isEqual:XYBookAudioCommandSeekTo]) {
        [self seek:parameters completion:completion];
        return;
    } else if ([@[ XYBookAudioCommandPrevious, XYBookAudioCommandNext, XYBookAudioCommandSelectChapter ]
                   containsObject:command]) {
        [self select:command parameters:parameters completion:completion];
        return;
    } else if ([command isEqual:XYBookAudioCommandPause]) {
        self.generation++;
        self.resumeAfterInterruption = NO;
        [self.engine pause];
        self.stateOverride = self.queue ? XYBookAudioValuePaused : XYBookAudioValueIdle;
        [self save];
    } else if ([command isEqual:XYBookAudioCommandStop]) {
        [self stop];
    } else if ([command isEqual:XYBookAudioCommandSetRate]) {
        error = [self changeRate:parameters];
    } else if ([command isEqual:XYBookAudioCommandSetSleepTimer]) {
        [self.sleepTimer configure:parameters
                 hasCurrentChapter:self.engine.hasItem &&
                                   [@[ XYBookAudioValuePlaying, XYBookAudioValuePaused, XYBookAudioValueBuffering ]
                                       containsObject:self.engine.state]
                             error:&error];
    } else if ([command isEqual:XYBookAudioCommandCancelSleepTimer]) {
        [self.sleepTimer cancel];
    } else {
        error = XYBookAudioError(XYBookAudioUnsupported, @"Unknown playback command.");
    }
    if (!error) {
        [self publish];
    }
    completion(error ? nil : [self snapshot], error);
}

/// 完整校验新队列后再替换；读取断点失败时从指定位置或章节起点恢复。
- (NSError *)replaceQueue:(NSDictionary *)parameters {
    NSError *error;
    XYBookAudioQueue *queue = [XYBookAudioQueue queueWithParameters:parameters error:&error];
    if (!queue) {
        return error;
    }
    for (XYBookAudioChapter *chapter in queue.chapters) {
        if (chapter.audioURL && ![self.configuration allowsMediaURL:[NSURL URLWithString:chapter.audioURL]]) {
            return XYBookAudioError(XYBookAudioUntrustedSource,
                                    @"A media source is outside the allowed local resource directory.");
        }
    }
    NSString *selected = parameters[XYBookAudioKeyChapterId];
    if (selected && !XYBookAudioString(selected)) {
        return XYBookAudioError(XYBookAudioInvalidArgument, @"chapterId must be a nonempty string.");
    }
    if (parameters[XYBookAudioKeyPositionMs] &&
        !XYBookAudioNumber(parameters[XYBookAudioKeyPositionMs], 0, DBL_MAX, NO)) {
        return XYBookAudioError(XYBookAudioInvalidArgument, @"positionMs must be a nonnegative number.");
    }
    XYBookAudioIdentity *identity = [self.host bookAudioUserIdentity];
    if (!identity) {
        return XYBookAudioError(XYBookAudioHostFailed, @"Host identity is unavailable.");
    }
    NSError *checkpointError = nil;
    NSDictionary *checkpoint = [self.store readBook:queue.bookId identity:identity.userId error:&checkpointError];
    NSString *target = selected ?: checkpoint[XYBookAudioKeyChapterId];
    NSUInteger index =
        [queue.chapters indexOfObjectPassingTest:^BOOL(XYBookAudioChapter *chapter, NSUInteger index, BOOL *stop) {
            return [chapter.chapterId isEqual:target];
        }];
    if (selected && index == NSNotFound) {
        return XYBookAudioError(XYBookAudioInvalidArgument, @"chapterId is not in the queue.");
    }
    if (index == NSNotFound) {
        index = 0;
    }
    double position = parameters[XYBookAudioKeyPositionMs]
                          ? [parameters[XYBookAudioKeyPositionMs] doubleValue]
                          : ([queue.chapters[index].chapterId isEqual:checkpoint[XYBookAudioKeyChapterId]]
                                 ? [checkpoint[XYBookAudioKeyPositionMs] doubleValue]
                                 : 0);
    [self installQueue:queue index:index position:position identity:identity];
    if (checkpointError) {
        [self.logger error:checkpointError component:XYBookAudioLogStorage operation:@"Checkpoint read"];
        [self report:XYBookAudioError(XYBookAudioStorageFailed, @"Unable to restore the saved playback position.")];
    }
    return nil;
}

- (void)installQueue:(XYBookAudioQueue *)queue
               index:(NSInteger)index
            position:(double)position
            identity:(XYBookAudioIdentity *)identity {
    BOOL replacingSnckQueue = queue.snckItems || self.queue.snckItems;
    if (replacingSnckQueue) {
        [self suspendPlayback];
        self.queueVersion++;
    } else {
        [self yieldPlayback];
    }
    [self.engine clear];
    if (replacingSnckQueue || ![self.queue.bookId isEqual:queue.bookId]) {
        [self.sleepTimer cancel];
    }
    [self.logger write:XYBookAudioLogLevelInfo component:XYBookAudioLogPlayback message:@"Playback queue replaced."];
    self.queue = queue;
    self.index = index;
    self.position = position;
    self.identity = identity;
    self.checkpointIdentity = identity.userId;
    self.stateOverride = XYBookAudioValueReady;
    self.reason = nil;
    [self loadArtwork];
}

/// 先校验身份、音源和定时，再请求宿主让出音频；异步交接采用单次结算与代次校验。
- (void)play:(XYBookAudioCompletion)completion {
    if (![self refreshIdentity]) {
        completion(nil, XYBookAudioError(XYBookAudioHostFailed, @"Host identity is unavailable."));
        return;
    }
    if (!self.queue) {
        completion(nil, XYBookAudioError(XYBookAudioInvalidState, @"SetQueue is required before playback."));
        return;
    }
    if (self.acquiring) {
        completion(nil, XYBookAudioError(XYBookAudioBusy, @"Audio ownership is being acquired."));
        return;
    }
    if ([self expireTimer]) {
        completion([self snapshot], nil);
        return;
    }
    if (self.queue.snckItems && [self.engine.state isEqual:XYBookAudioValueCompleted] &&
        self.index + 1 < (NSInteger)self.queue.chapters.count) {
        [self selectIndex:self.index + 1 completion:completion];
        return;
    }
    XYBookAudioChapter *chapter = self.chapter;
    NSError *error;
    if (chapter.requiresLogin && !self.identity.isLoggedIn) {
        error = XYBookAudioError(XYBookAudioLoginRequired, @"Login is required for this chapter.");
    } else if (!chapter.audioURL) {
        error = XYBookAudioError(XYBookAudioSourceNotReady, @"H5 must provide an authorized audio source.");
    }
    if (error) {
        self.stateOverride = XYBookAudioValueBlocked;
        self.reason = XYBookAudioErrorName(error);
        [self publish];
        completion(nil, error);
        return;
    }
    if (self.media.active) {
        if (![self.media acquire:nil]) {
            completion(nil, XYBookAudioError(XYBookAudioPlaybackFailed, @"Unable to reactivate the audio session."));
            return;
        }
        [self startCurrentChapter:completion afterHandoff:NO];
        return;
    }
    [self requestAudioHandoff:completion];
}

- (void)requestAudioHandoff:(XYBookAudioCompletion)completion {
    id<XYBookAudioHost> host = self.host;
    if (!host) {
        completion(nil, XYBookAudioError(XYBookAudioHostFailed, @"Host has been released."));
        return;
    }
    NSUUID *reservation = [self.media reservePlayback];
    if (!reservation) {
        completion(nil, XYBookAudioError(XYBookAudioBusy, @"Another listening session owns audio playback."));
        return;
    }
    self.acquiring = YES;
    self.acquisitionGeneration = self.generation;
    [self.logger write:XYBookAudioLogLevelDebug component:XYBookAudioLogHost message:@"Requesting host audio handoff."];
    NSUInteger generation = self.generation;
    BOOL snck = self.queue.snckItems != nil;
    __weak typeof(self) weakSelf = self;
    __weak id<XYBookAudioHost> weakHost = host;
    __weak XYBookAudioSystemMedia *weakMedia = self.media;
    __block XYBookAudioCompletion pendingCompletion = [completion copy];
    __block BOOL hostResponded = NO;
    void (^settle)(NSError *) = ^(NSError *hostError) {
        XYBookAudioCompletion finish = pendingCompletion;
        pendingCompletion = nil;
        XYBookAudioSession *session = weakSelf;
        session.acquiring = NO;
        BOOL superseded = !session || session.disposed || generation != session.generation;
        if (superseded || hostError) {
            [weakMedia cancelPlaybackReservation:reservation];
            if (!hostError && [XYBookAudioSystemMedia canReturnLateHandoffForReservation:reservation]) {
                [weakHost bookAudioDidReleasePlayback];
            }
            if (superseded) {
                [session.logger write:XYBookAudioLogLevelDebug component:XYBookAudioLogHost
                              message:@"Superseded audio handoff ignored."];
                NSError *error = snck ? [NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorCancelled userInfo:nil]
                                      : XYBookAudioError(XYBookAudioInvalidState, @"Playback request was superseded.");
                finish(nil, error);
            } else {
                [session.logger error:hostError component:XYBookAudioLogHost operation:@"Host audio handoff"];
                finish(nil, hostError);
            }
            return;
        }
        if (![session.media acquire:nil]) {
            [session.media cancelPlaybackReservation:reservation];
            [weakHost bookAudioDidReleasePlayback];
            finish(nil, XYBookAudioError(XYBookAudioPlaybackFailed, @"Unable to activate the system audio session."));
            return;
        }
        [session startCurrentChapter:finish afterHandoff:YES];
    };
    [host bookAudioAcquirePlayback:^(NSError *hostError) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (hostResponded) {
                return;
            }
            hostResponded = YES;
            if (pendingCompletion) {
                settle(hostError);
            } else if (!hostError && [XYBookAudioSystemMedia canReturnLateHandoffForReservation:reservation]) {
                [weakHost bookAudioDidReleasePlayback];
            }
        });
    }];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 10 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        if (pendingCompletion) {
            [weakSelf.logger write:XYBookAudioLogLevelWarning component:XYBookAudioLogHost
                           message:@"Host audio handoff timed out."];
            settle(snck ? [NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorTimedOut userInfo:nil]
                        : XYBookAudioError(XYBookAudioHostFailed, @"Host audio handoff timed out."));
        }
    });
}

/// 宿主异步交接后重新检查身份与截止时间，避免等待期间权限变化或定时已结束仍启动播放。
- (void)startCurrentChapter:(XYBookAudioCompletion)completion afterHandoff:(BOOL)afterHandoff {
    NSUInteger generation = self.generation;
    if (![self refreshIdentity]) {
        completion(nil, XYBookAudioError(XYBookAudioHostFailed, @"Host identity is unavailable."));
        return;
    }
    if (self.disposed || generation != self.generation) {
        completion(nil, XYBookAudioError(XYBookAudioInvalidState, @"Playback request was superseded."));
        return;
    }
    if ([self expireTimerReleasingSystemPlayback:afterHandoff]) {
        completion([self snapshot], nil);
        return;
    }
    if ((self.chapter.requiresLogin && !self.identity.isLoggedIn) || !self.chapter.audioURL) {
        [self yieldPlayback];
        completion(nil,
                   XYBookAudioError(self.identity.isLoggedIn ? XYBookAudioSourceNotReady : XYBookAudioLoginRequired,
                                    @"Identity changed while preparing playback; provide a fresh source."));
        return;
    }
    BOOL completed = [[self snapshot][XYBookAudioKeyState] isEqual:XYBookAudioValueCompleted] ||
                     (self.queue.snckItems && [self.engine.state isEqual:XYBookAudioValueCompleted]);
    BOOL failed = self.queue.snckItems && [self.engine.state isEqual:XYBookAudioValueFailed];
    self.stateOverride = nil;
    self.reason = nil;
    if (!self.engine.hasItem || completed || failed) {
        if (completed) {
            self.position = 0;
        }
        [self.engine loadURL:[NSURL URLWithString:self.chapter.audioURL] position:self.position rate:self.rate];
    } else {
        [self.engine playWithRate:self.rate];
    }
    [self publish];
    completion([self snapshot], nil);
}

/// 仅接受协议白名单中的倍速；暂停时保存选择，不因设置倍速自动开始播放。
- (NSError *)changeRate:(NSDictionary *)parameters {
    NSNumber *rate = parameters[XYBookAudioKeyRate];
    if (!XYBookAudioNumber(rate, 0.75, 2, NO) || ![XYBookAudioRates() containsObject:rate]) {
        return XYBookAudioError(XYBookAudioInvalidArgument, @"Unsupported playback rate.");
    }
    self.rate = rate.doubleValue;
    if ([@[ XYBookAudioValuePlaying, XYBookAudioValueBuffering ] containsObject:self.engine.state]) {
        [self.engine playWithRate:self.rate];
    }
    return nil;
}

/// 确定目标章节合法后保存旧断点并重新走播放准入；越界请求不改变当前章节。
- (void)select:(NSString *)command parameters:(NSDictionary *)parameters completion:(XYBookAudioCompletion)completion {
    if (!self.queue) {
        completion(nil, XYBookAudioError(XYBookAudioInvalidState, @"No active queue."));
        return;
    }
    NSInteger index = self.index + ([command isEqual:XYBookAudioCommandNext] ? 1 : -1);
    if ([command isEqual:XYBookAudioCommandSelectChapter]) {
        NSString *identifier = parameters[XYBookAudioKeyChapterId];
        if (!XYBookAudioString(identifier)) {
            completion(nil, XYBookAudioError(XYBookAudioInvalidArgument, @"chapterId is required."));
            return;
        }
        index = [self.queue.chapters
            indexOfObjectPassingTest:^BOOL(XYBookAudioChapter *chapter, NSUInteger offset, BOOL *stop) {
                return [chapter.chapterId isEqual:identifier];
            }];
    }
    [self selectIndex:index completion:completion];
}

- (void)selectIndex:(NSInteger)index completion:(XYBookAudioCompletion)completion {
    if (index < 0 || index >= (NSInteger)self.queue.chapters.count) {
        completion(nil, XYBookAudioError(XYBookAudioInvalidArgument, @"No chapter at that position."));
        return;
    }
    [self save];
    self.generation++;
    [self.engine clear];
    self.index = index;
    self.position = 0;
    self.stateOverride = XYBookAudioValueReady;
    [self play:completion];
}

/// 校验毫秒位置并限制到已知时长；未装载播放器时只更新断点，活动拖动只接受最后一次结果。
- (void)seek:(NSDictionary *)parameters completion:(XYBookAudioCompletion)completion {
    NSNumber *position = parameters[XYBookAudioKeyPositionMs];
    if (!self.queue || !XYBookAudioNumber(position, 0, DBL_MAX, NO)) {
        completion(nil,
                   XYBookAudioError(XYBookAudioInvalidArgument, @"A queue and nonnegative positionMs are required."));
        return;
    }
    double target = position.doubleValue;
    double duration = self.engine.durationMs > 0 ? self.engine.durationMs : self.chapter.durationMs.doubleValue;
    if (duration > 0) {
        target = MIN(target, duration);
    }
    if (!self.engine.hasItem) {
        self.position = target;
        [self save];
        [self publish];
        completion([self snapshot], nil);
        return;
    }
    BOOL snck = self.queue.snckItems != nil;
    [self.engine seekTo:target completion:^(BOOL finished) {
        if (!finished) {
            NSError *error = snck ? [NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorCancelled userInfo:nil]
                                  : XYBookAudioError(XYBookAudioInvalidState, @"Seek failed or was superseded.");
            completion(nil, error);
            return;
        }
        [self save];
        [self publish];
        completion([self snapshot], nil);
    }];
}

@end
