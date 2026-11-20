// 页面和原生入口共用的播放会话；主线程持有队列、身份、进度与定时状态，不依赖页面存活。
#import "XYBookAudioLogger.h"
#import "XYBookAudioMessageProtocol.h"
#import "XYBookAudioSDKManager.h"

@interface XYBookAudioSession : NSObject

@property (nonatomic, copy) XYBookAudioEventHandler event;
- (instancetype)initWithConfiguration:(XYBookAudioConfiguration *)configuration
                                 host:(id<XYBookAudioHost>)host
                               logger:(XYBookAudioLogger *)logger;
- (NSDictionary *)snapshot;
- (NSDictionary *)snckPlayback;
- (XYBookAudioTimerChange)snckTimerChange;
- (NSDictionary *)snckUserState;

/// 宿主身份读取失败时先暂停并释放音频，再返回 NO；不能沿用缓存身份继续播放。
- (BOOL)refreshIdentity;
- (void)yieldPlayback;
- (void)stop;
- (void)dispose;

@end

@interface XYBookAudioSession (Commands)

- (void)execute:(NSString *)command parameters:(NSDictionary *)parameters completion:(XYBookAudioCompletion)completion;
- (void)executeSnckAudio:(NSString *)command
              parameters:(NSDictionary *)parameters
              completion:(XYBookAudioCompletion)completion;

@end
