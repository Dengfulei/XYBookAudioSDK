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

/// 替换播放项并使旧加载、拖动回调失效。
/// @param URL 当前章节的可播放音源。
/// @param position 资源就绪后定位到的起始位置，单位为毫秒。
/// @param rate 资源就绪后启动播放的倍速，1 表示原速。
- (void)loadURL:(NSURL *)URL position:(double)position rate:(float)rate;

/// 记录播放意图，资源已就绪时立即播放。
/// @param rate 播放倍速，1 表示原速。
- (void)playWithRate:(float)rate;

/// 暂停播放器并清除播放意图。
- (void)pause;

/// 定位当前播放项，以最后一次拖动为准。
/// @param position 目标播放位置，单位为毫秒。
/// @param completion 在主线程接收拖动结果。拖动失败或被后续操作取代时传 NO。
- (void)seekTo:(double)position completion:(void (^)(BOOL finished))completion;

/// 移除当前播放项及其观察者，并使待处理结果失效。
- (void)clear;

/// 清除当前播放项并移除周期性进度观察者。
- (void)dispose;

@end
