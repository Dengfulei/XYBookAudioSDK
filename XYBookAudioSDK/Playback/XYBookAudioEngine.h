// AVPlayer IO 适配器；所有方法和回调限制在主线程，事件只对应当前播放实例。
#import <AVFoundation/AVFoundation.h>

@interface XYBookAudioEngine : NSObject

@property (nonatomic, copy) void (^changed)(void);
@property (nonatomic, copy) void (^finished)(BOOL natural, NSUUID *instance);
@property (nonatomic, copy) void (^failed)(NSError *error);
@property (nonatomic, readonly) double positionMs;
@property (nonatomic, readonly) double durationMs;
@property (nonatomic, readonly) double bufferedPositionMs;
@property (nonatomic, readonly) BOOL wantsPlayback;
@property (nonatomic, readonly) BOOL hasItem;
@property (nonatomic, copy, readonly) NSString *state;

/// 替换播放项并使旧加载、拖动回调失效；位置单位为毫秒。
- (void)loadURL:(NSURL *)URL position:(double)position rate:(float)rate;
- (void)playWithRate:(float)rate;
- (void)pause;
- (void)seekTo:(double)position completion:(void (^)(BOOL finished))completion;
- (void)clear;
- (void)dispose;

@end
