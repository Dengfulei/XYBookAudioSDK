// 仅会话生命周期和命令实现共享的私有状态；不对 framework 宿主导出，所有状态归主线程所有。
#import "XYBookAudioSession.h"
#import "XYBookAudioEngine.h"
#import "XYBookAudioQueue.h"
#import "XYBookAudioSleepTimer.h"
#import "XYBookAudioSystemMedia.h"
#import "XYBookAudioCheckpointStore.h"
#import "XYBookAudioMessageProtocol.h"

@interface XYBookAudioSession ()

@property (nonatomic, strong) XYBookAudioConfiguration *configuration;
@property (nonatomic, strong) XYBookAudioLogger *logger;
@property (nonatomic, weak) id<XYBookAudioHost> host;
@property (nonatomic, strong) XYBookAudioIdentity *identity;
@property (nonatomic, strong) XYBookAudioQueue *queue;
@property (nonatomic, strong) XYBookAudioEngine *engine;
@property (nonatomic, strong) XYBookAudioSleepTimer *sleepTimer;
@property (nonatomic, strong) XYBookAudioSystemMedia *media;
@property (nonatomic, strong) XYBookAudioCheckpointStore *store;
@property (nonatomic, strong) NSTimer *ticker;
@property (nonatomic, strong) id backgroundObserver;
@property (nonatomic, strong) UIImage *artwork;
@property (nonatomic, strong) NSURL *artworkURL;
@property (nonatomic, strong) NSURLSessionDataTask *artworkTask;
@property (nonatomic, copy) NSString *checkpointIdentity, *stateOverride, *reason;
@property (nonatomic, copy) NSString *lastPublishedState;
@property (nonatomic) NSInteger index;
@property (nonatomic) double position, rate, lastSave, lastPublish;
@property (nonatomic) NSUInteger generation, acquisitionGeneration;
@property (nonatomic) NSUInteger stateVersion, queueVersion;
@property (nonatomic) BOOL disposed, acquiring, resumeAfterInterruption;

/// 发布播放快照并同步锁屏信息。
- (void)publish;
/// 记录播放错误并发布错误事件。
/// @param error 要交给 SDK 订阅者的业务错误。
- (void)report:(NSError *)error;
/// 为原生队列保存当前章节的播放断点。
- (void)save;
/// 处理当前章节结束，检查定时和队尾后决定是否续播。
/// @param natural YES 表示自然播完，NO 表示手动拖到末尾。
/// @param instance 章节播放实例标识，用于避免同一次自然播完被定时器重复计数。
- (void)finish:(BOOL)natural instance:(NSUUID *)instance;
/// @return 当前章节。没有队列时返回 nil。
- (XYBookAudioChapter *)chapter;
/// @return SNCK 定时快照，时长及连续时钟的截止时刻均使用毫秒。
- (NSDictionary *)snckTimerSnapshot;
/// 检查时长定时并在到期时暂停播放。
/// @return 本次检查触发到期时返回 YES。
- (BOOL)expireTimer;
/// 检查时长定时，供音频交接完成后再次确认是否仍可播放。
/// @param releasePlayback 到期时是否一并释放已取得的系统音频占用。
/// @return 本次检查触发到期时返回 YES。
- (BOOL)expireTimerReleasingSystemPlayback:(BOOL)releasePlayback;
/// 按当前队列和曲目重新加载锁屏封面。
- (void)loadArtwork;
/// 释放系统音频占用，并在占用曾激活时通知宿主。
- (void)releaseSystemPlayback;
/// 暂停、保存断点并释放系统音频占用。
- (void)suspendPlayback;
/// 清空 SNCK 队列、定时和当前播放项，释放系统音频占用。
- (void)clearSnckQueue;

@end

@interface XYBookAudioSession (CommandInternals)

/// 校验当前账号、定时和音源，完成音频交接后开始播放。
/// @param completion 接收原生播放快照或执行错误。
- (void)play:(XYBookAudioCompletion)completion;

@end
