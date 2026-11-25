// AVAudioSession／Now Playing 适配；释放后不再修改系统元数据，避免覆盖接管音频的新宿主。
#import "XYBookAudioSystemMedia.h"
#import "XYBookAudioMessageProtocol.h"
#import <AVFoundation/AVFoundation.h>
#import <MediaPlayer/MediaPlayer.h>

#import "XYBookAudioLogger.h"

// 预留和激活都在主线程结算，覆盖宿主异步让出音频的等待期。
static XYBookAudioSystemMedia *XYBookAudioPlaybackOwner;
static NSUUID *XYBookAudioLatestPlaybackReservation;

@interface XYBookAudioSystemMedia ()

@property (nonatomic, strong) XYBookAudioLogger *logger;

@property (atomic, readwrite) BOOL active;
@property (nonatomic, strong) NSMutableArray<NSDictionary *> *tokens;
@property (nonatomic, strong) NSMutableArray *observers;
@property (nonatomic) NSUInteger generation;

@end

@implementation XYBookAudioSystemMedia

- (instancetype)initWithLogger:(XYBookAudioLogger *)logger {
    if ((self = [super init])) {
        _tokens = [NSMutableArray array];
        _logger = logger;
        _observers = [NSMutableArray array];
        [self observeAudio];
    }
    return self;
}

/// 只处理本实例持有音频时发生的中断、设备断开和媒体服务重置，并回传给会话决策。
- (void)observeAudio {
    __weak typeof(self) weakSelf = self;
    NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
    [self.observers
        addObject:[center addObserverForName:AVAudioSessionInterruptionNotification object:nil
                                       queue:NSOperationQueue.mainQueue
                                  usingBlock:^(NSNotification *note) {
                                      if (!weakSelf.active) {
                                          return;
                                      }
                                      BOOL began = [note.userInfo[AVAudioSessionInterruptionTypeKey] integerValue] ==
                                                   AVAudioSessionInterruptionTypeBegan;
                                      BOOL resume = ([note.userInfo[AVAudioSessionInterruptionOptionKey] integerValue] &
                                                     AVAudioSessionInterruptionOptionShouldResume) != 0;
                                      if (weakSelf.interruption) {
                                          weakSelf.interruption(began, resume);
                                      }
                                  }]];
    [self.observers
        addObject:[center addObserverForName:AVAudioSessionRouteChangeNotification object:nil
                                       queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) {
                                           if (weakSelf.active &&
                                               [note.userInfo[AVAudioSessionRouteChangeReasonKey] integerValue] ==
                                                   AVAudioSessionRouteChangeReasonOldDeviceUnavailable &&
                                               weakSelf.routeLost) {
                                               weakSelf.routeLost();
                                           }
                                       }]];
    [self.observers addObject:[center addObserverForName:AVAudioSessionMediaServicesWereResetNotification object:nil
                                                   queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) {
                                                       if (weakSelf.active && weakSelf.mediaReset) {
                                                           weakSelf.mediaReset();
                                                       }
                                                   }]];
}

- (NSUUID *)reservePlayback {
    if (XYBookAudioPlaybackOwner) {
        return nil;
    }
    XYBookAudioPlaybackOwner = self;
    XYBookAudioLatestPlaybackReservation = NSUUID.UUID;
    return XYBookAudioLatestPlaybackReservation;
}

- (void)cancelPlaybackReservation:(NSUUID *)reservation {
    if (!self.active && XYBookAudioPlaybackOwner == self && XYBookAudioLatestPlaybackReservation == reservation) {
        XYBookAudioPlaybackOwner = nil;
    }
}

+ (BOOL)canReturnLateHandoffForReservation:(NSUUID *)reservation {
    return XYBookAudioPlaybackOwner == nil && XYBookAudioLatestPlaybackReservation == reservation;
}

/// 激活已预留的系统 Playback 会话，再注册锁屏命令。
- (BOOL)acquire:(NSError **)error {
    if (XYBookAudioPlaybackOwner != self) {
        if (error) {
            *error = XYBookAudioError(XYBookAudioBusy, @"This session does not own the playback reservation.");
        }
        return NO;
    }
    AVAudioSession *session = AVAudioSession.sharedInstance;
    NSError *activationError = nil;
    BOOL configured = self.active || [session setCategory:AVAudioSessionCategoryPlayback mode:AVAudioSessionModeDefault
                                                  options:0
                                                    error:&activationError];
    if (!configured || ![session setActive:YES error:&activationError]) {
        [self.logger error:activationError component:XYBookAudioLogAudio operation:@"Audio session activation"];
        if (error) {
            *error = activationError;
        }
        return NO;
    }
    if (self.active) {
        return YES;
    }
    self.active = YES;
    [self.logger write:XYBookAudioLogLevelInfo component:XYBookAudioLogAudio message:@"Audio session acquired."];
    self.generation++;
    [self registerCommands];
    return YES;
}

/// 保留单个远程命令令牌；系统回调切回主线程后再次验证所有权代次。
- (void)bind:(MPRemoteCommand *)command action:(NSString *)action {
    __weak typeof(self) weakSelf = self;
    NSUInteger generation = self.generation;
    id token = [command addTargetWithHandler:^MPRemoteCommandHandlerStatus(MPRemoteCommandEvent *event) {
        if (!weakSelf.active) {
            return MPRemoteCommandHandlerStatusCommandFailed;
        }
        NSDictionary *parameters = @{};
        if ([event isKindOfClass:MPChangePlaybackPositionCommandEvent.class]) {
            parameters =
                @{XYBookAudioKeyPositionMs : @(((MPChangePlaybackPositionCommandEvent *)event).positionTime * 1000)};
        }
        if ([event isKindOfClass:MPChangePlaybackRateCommandEvent.class]) {
            parameters = @{XYBookAudioKeyRate : @(((MPChangePlaybackRateCommandEvent *)event).playbackRate)};
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            if (weakSelf.active && generation == weakSelf.generation && weakSelf.command) {
                weakSelf.command(action, parameters);
            }
        });
        return MPRemoteCommandHandlerStatusSuccess;
    }];
    [self.tokens addObject:@{@"command" : command, @"token" : token}];
    command.enabled = YES;
}

/// 注册本 SDK 支持的锁屏动作；系统决定最终展示哪些控制，不创建自定义锁屏界面。
- (void)registerCommands {
    MPRemoteCommandCenter *center = MPRemoteCommandCenter.sharedCommandCenter;
    [self bind:center.playCommand action:XYBookAudioCommandPlay];
    [self bind:center.pauseCommand action:XYBookAudioCommandPause];
    [self bind:center.togglePlayPauseCommand action:XYBookAudioCommandToggle];
    [self bind:center.nextTrackCommand action:XYBookAudioCommandNext];
    [self bind:center.previousTrackCommand action:XYBookAudioCommandPrevious];
    [self bind:center.changePlaybackPositionCommand action:XYBookAudioCommandSeekTo];
    [self bind:center.changePlaybackRateCommand action:XYBookAudioCommandSetRate];
    center.changePlaybackRateCommand.supportedPlaybackRates = XYBookAudioSupportedPlaybackRates();
}

/// 仅在持有音频时写锁屏快照；按章节位置启用前后切章，不接收或记录音源地址。
- (void)update:(NSDictionary *)snapshot artwork:(UIImage *)artwork {
    if (!self.active) {
        return;
    }
    BOOL playing = [snapshot[XYBookAudioKeyState] isEqual:XYBookAudioValuePlaying];
    NSMutableDictionary *info = [@{
        MPMediaItemPropertyTitle : snapshot[XYBookAudioKeyChapterTitle] ?: @"",
        MPMediaItemPropertyAlbumTitle : snapshot[XYBookAudioKeyTitle] ?: @"",
        MPNowPlayingInfoPropertyElapsedPlaybackTime : @([snapshot[XYBookAudioKeyPositionMs] doubleValue] / 1000),
        MPNowPlayingInfoPropertyPlaybackRate : playing ? snapshot[XYBookAudioKeyRate] : @0,
        MPNowPlayingInfoPropertyDefaultPlaybackRate : snapshot[XYBookAudioKeyRate]
    } mutableCopy];
    if (snapshot[XYBookAudioKeyDurationMs]) {
        info[MPMediaItemPropertyPlaybackDuration] = @([snapshot[XYBookAudioKeyDurationMs] doubleValue] / 1000);
    }
    if (artwork) {
        info[MPMediaItemPropertyArtwork] = [[MPMediaItemArtwork alloc] initWithBoundsSize:artwork.size
                                                                           requestHandler:^UIImage *(CGSize size) {
                                                                               return artwork;
                                                                           }];
    }
    MPNowPlayingInfoCenter.defaultCenter.nowPlayingInfo = info;
    MPRemoteCommandCenter.sharedCommandCenter.previousTrackCommand.enabled =
        [snapshot[XYBookAudioKeyChapterIndex] integerValue] > 0;
    MPRemoteCommandCenter.sharedCommandCenter.nextTrackCommand.enabled =
        [snapshot[XYBookAudioKeyChapterIndex] integerValue] + 1 < [snapshot[XYBookAudioKeyChapterCount] integerValue];
}

/// 仅移除自己注册的令牌并清理元数据；先撤销所有权，再停用音频，避免迟到回调影响新持有者。
- (void)releasePlayback {
    if (!self.active) {
        return;
    }
    self.active = NO;
    [self.logger write:XYBookAudioLogLevelInfo component:XYBookAudioLogAudio message:@"Audio session released."];
    self.generation++;
    for (NSDictionary *binding in self.tokens) {
        [binding[@"command"] removeTarget:binding[@"token"]];
    }
    [self.tokens removeAllObjects];
    MPNowPlayingInfoCenter.defaultCenter.nowPlayingInfo = nil;
    NSError *error;
    if (![AVAudioSession.sharedInstance setActive:NO withOptions:AVAudioSessionSetActiveOptionNotifyOthersOnDeactivation
                                            error:&error]) {
        [self.logger error:error component:XYBookAudioLogAudio operation:@"Audio session deactivation"];
    }
    if (XYBookAudioPlaybackOwner == self) {
        XYBookAudioPlaybackOwner = nil;
    }
}

/// 释放本实例的音频占用和通知观察者；多次调用不重复清理其他播放器。
- (void)dispose {
    [self releasePlayback];
    for (id observer in self.observers) {
        [NSNotificationCenter.defaultCenter removeObserver:observer];
    }
    [self.observers removeAllObjects];
}

- (void)dealloc {
    [self dispose];
}

@end
