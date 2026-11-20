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
@property (nonatomic, strong) NSURLSessionDataTask *artworkTask;
@property (nonatomic, copy) NSString *checkpointIdentity, *stateOverride, *reason;
@property (nonatomic, copy) NSString *lastPublishedState;
@property (nonatomic) NSInteger index;
@property (nonatomic) double position, rate, lastSave, lastPublish;
@property (nonatomic) NSUInteger generation, acquisitionGeneration;
@property (nonatomic) NSUInteger stateVersion, queueVersion;
@property (nonatomic) BOOL disposed, acquiring, resumeAfterInterruption;
- (void)publish;
- (void)report:(NSError *)error;
- (void)save;
- (void)finish:(BOOL)natural instance:(NSUUID *)instance;
- (XYBookAudioChapter *)chapter;
- (BOOL)expireTimer;
- (BOOL)expireTimerReleasingSystemPlayback:(BOOL)releasePlayback;
- (void)loadArtwork;
- (void)releaseSystemPlayback;
- (void)suspendPlayback;
- (void)clearSnckQueue;

@end

@interface XYBookAudioSession (CommandInternals)

- (void)play:(XYBookAudioCompletion)completion;

@end
