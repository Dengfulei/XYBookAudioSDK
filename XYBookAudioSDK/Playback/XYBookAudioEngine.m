// 单章 AVPlayer 适配：会话决定下一章；generation 隔离旧资源回调，seekGeneration 保证最后一次拖动生效。
#import "XYBookAudioEngine.h"
#import "XYBookAudioMessageProtocol.h"
static void *XYBookAudioItemContext = &XYBookAudioItemContext;

@interface XYBookAudioEngine ()

@property (nonatomic, strong) AVPlayer *player;
@property (nonatomic, strong) AVPlayerItem *item;
@property (nonatomic, strong) id progressObserver, endObserver, failureObserver;
@property (nonatomic, strong) NSUUID *instance;
@property (nonatomic) NSUInteger generation, seekGeneration;
@property (nonatomic) BOOL wantsPlayback, completed, seekToEnd, seeking, prepared;
@property (nonatomic) float rate;
@property (nonatomic) double initialPosition;

@end

@implementation XYBookAudioEngine

- (instancetype)init {
    if ((self = [super init])) {
        _player = [AVPlayer new];
        __weak typeof(self) weakSelf = self;
        _progressObserver =
            [_player addPeriodicTimeObserverForInterval:CMTimeMakeWithSeconds(XYBookAudioProgressInterval, NSEC_PER_SEC)
                                                  queue:dispatch_get_main_queue() usingBlock:^(CMTime time) {
                                                      if (weakSelf.changed) {
                                                          weakSelf.changed();
                                                      }
                                                  }];
    }
    return self;
}

- (double)positionMs {
    double value = CMTimeGetSeconds(self.player.currentTime) * 1000;
    return isfinite(value) ? MAX(0, value) : 0;
}

- (double)durationMs {
    double value = CMTimeGetSeconds(self.item.duration) * 1000;
    return isfinite(value) && value > 0 ? value : 0;
}

- (BOOL)hasItem {
    return self.item != nil;
}

- (NSString *)state {
    if (!self.item) {
        return XYBookAudioValueIdle;
    }
    if (self.item.status == AVPlayerItemStatusFailed) {
        return XYBookAudioValueFailed;
    }
    if (self.completed) {
        return XYBookAudioValueCompleted;
    }
    if (!self.wantsPlayback) {
        return XYBookAudioValuePaused;
    }
    return self.player.timeControlStatus == AVPlayerTimeControlStatusPlaying ? XYBookAudioValuePlaying
                                                                             : XYBookAudioValueBuffering;
}

/// 替换当前播放项并建立新实例标识；等待资源就绪后再定位到传入毫秒位置并按指定倍速播放。
- (void)loadURL:(NSURL *)URL position:(double)position rate:(float)rate {
    [self clear];
    self.initialPosition = position;
    self.rate = rate;
    self.wantsPlayback = YES;
    self.instance = NSUUID.UUID;
    self.item = [AVPlayerItem playerItemWithURL:URL];
    [self.player replaceCurrentItemWithPlayerItem:self.item];
    [self.item addObserver:self forKeyPath:XYBookAudioKeyStatus
                   options:NSKeyValueObservingOptionInitial | NSKeyValueObservingOptionNew
                   context:XYBookAudioItemContext];
    [self observeItemEnd];
}

/// 资源替换后仍可能收到旧通知；使用 generation 和实例标识防止重复结束或错误推进下一章。
- (void)observeItemEnd {
    __weak typeof(self) weakSelf = self;
    NSUInteger generation = self.generation;
    self.endObserver = [NSNotificationCenter.defaultCenter
        addObserverForName:AVPlayerItemDidPlayToEndTimeNotification
                    object:self.item
                     queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) {
                         typeof(self) self = weakSelf;
                         if (!self || generation != self.generation || self.completed || self.seeking) {
                             return;
                         }
                         self.completed = YES;
                         self.wantsPlayback = NO;
                         if (self.finished) {
                             self.finished(!self.seekToEnd, self.instance);
                         }
                     }];
    self.failureObserver = [NSNotificationCenter.defaultCenter
        addObserverForName:AVPlayerItemFailedToPlayToEndTimeNotification
                    object:self.item
                     queue:NSOperationQueue.mainQueue
                usingBlock:^(NSNotification *note) {
                    if (generation != weakSelf.generation) {
                        return;
                    }
                    NSError *error = note.userInfo[AVPlayerItemFailedToPlayToEndTimeErrorKey];
                    if (weakSelf.failed) {
                        weakSelf.failed(
                            error ?: XYBookAudioError(XYBookAudioPlaybackFailed, @"Playback did not reach the end."));
                    }
                }];
}

/// 只处理当前资源的就绪／失败事件；切回主线程后再次校验代次，避免旧 KVO 污染新资源。
- (void)observeValueForKeyPath:(NSString *)keyPath
                      ofObject:(id)object
                        change:(NSDictionary *)change
                       context:(void *)context {
    if (context != XYBookAudioItemContext) {
        [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
        return;
    }
    NSUInteger generation = self.generation;
    dispatch_async(dispatch_get_main_queue(), ^{
        if (object != self.item || generation != self.generation) {
            return;
        }
        if (self.item.status == AVPlayerItemStatusFailed) {
            if (self.failed) {
                self.failed(self.item.error);
            }
            return;
        }
        if (self.item.status != AVPlayerItemStatusReadyToPlay || self.prepared) {
            return;
        }
        self.prepared = YES;
        [self seekTo:self.initialPosition completion:^(BOOL finished) {
            if (finished && self.wantsPlayback) {
                [self.player playImmediatelyAtRate:self.rate];
            }
            if (self.changed) {
                self.changed();
            }
        }];
    });
}

/// 记录继续播放意图；资源未就绪或仍在拖动时延后启动，不强行跨过准备过程。
- (void)playWithRate:(float)rate {
    self.wantsPlayback = YES;
    self.rate = rate;
    self.completed = NO;
    if (self.item.status == AVPlayerItemStatusReadyToPlay && !self.seeking) {
        [self.player playImmediatelyAtRate:rate];
    }
}

- (void)pause {
    self.wantsPlayback = NO;
    [self.player pause];
}

/// 以毫秒精确拖动，最后一次请求生效；回调 NO 表示失败或被新操作取代，拖到结尾不算自然播完。
- (void)seekTo:(double)position completion:(void (^)(BOOL))completion {
    NSUInteger generation = self.generation, seek = ++self.seekGeneration;
    self.seeking = YES;
    self.completed = NO;
    if (self.durationMs > 0) {
        position = MIN(position, self.durationMs);
    }
    self.seekToEnd = self.durationMs > 0 && position >= self.durationMs;
    CMTime time = CMTimeMakeWithSeconds(position / 1000.0, NSEC_PER_SEC);
    [self.player seekToTime:time toleranceBefore:kCMTimeZero toleranceAfter:kCMTimeZero
          completionHandler:^(BOOL finished) {
              dispatch_async(dispatch_get_main_queue(), ^{
                  if (generation != self.generation || seek != self.seekGeneration) {
                      completion(NO);
                      return;
                  }
                  self.seeking = NO;
                  BOOL reachedEnd = finished && self.seekToEnd;
                  BOOL advance = reachedEnd && self.wantsPlayback;
                  if (reachedEnd) {
                      self.completed = YES;
                      [self pause];
                  }
                  completion(finished);
                  // AVPlayer 可能在拖动中发送结束通知；手动拖到末尾由此处单次结算，不能计为自然播完。
                  if (advance && generation == self.generation && seek == self.seekGeneration && self.finished) {
                      self.finished(NO, self.instance);
                  }
              });
          }];
}

/// 先使异步回调过期，再移除旧资源观察者和播放器项目；可重复清理。
- (void)clear {
    self.generation++;
    self.seekGeneration++;
    [self pause];
    if (self.item) {
        [self.item removeObserver:self forKeyPath:XYBookAudioKeyStatus context:XYBookAudioItemContext];
    }
    if (self.endObserver) {
        [NSNotificationCenter.defaultCenter removeObserver:self.endObserver];
    }
    if (self.failureObserver) {
        [NSNotificationCenter.defaultCenter removeObserver:self.failureObserver];
    }
    self.endObserver = nil;
    self.failureObserver = nil;
    self.item = nil;
    self.completed = NO;
    self.seekToEnd = NO;
    self.seeking = NO;
    self.prepared = NO;
    [self.player replaceCurrentItemWithPlayerItem:nil];
}

/// 释放资源与周期进度观察者；外部回调归会话层管理。
- (void)dispose {
    [self clear];
    if (self.progressObserver) {
        [self.player removeTimeObserver:self.progressObserver];
    }
    self.progressObserver = nil;
}

- (void)dealloc {
    [self dispose];
}

@end
