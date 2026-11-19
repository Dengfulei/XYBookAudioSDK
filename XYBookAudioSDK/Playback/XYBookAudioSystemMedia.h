// 管理本 SDK 的系统音频占用和远程控制令牌；不得移除其他播放器注册的控制或元数据。
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

#import "XYBookAudioLogger.h"

@interface XYBookAudioSystemMedia : NSObject

@property (nonatomic, copy) void (^command)(NSString *action, NSDictionary *parameters);
@property (nonatomic, copy) void (^interruption)(BOOL began, BOOL shouldResume);
@property (nonatomic, copy) void (^routeLost)(void);
@property (nonatomic, copy) void (^mediaReset)(void);
@property (atomic, readonly) BOOL active;
- (instancetype)initWithLogger:(XYBookAudioLogger *)logger;
/// 交接前预留 App 共享的音频控制权；占用期间其他 SDK 实例返回 BUSY。
- (NSUUID *)reservePlayback;
- (void)cancelPlaybackReservation:(NSUUID *)reservation;
/// 超时后的成功回调仅在预留未被新请求替代时允许通知宿主。
+ (BOOL)canReturnLateHandoffForReservation:(NSUUID *)reservation;
- (BOOL)acquire:(NSError **)error;
- (void)update:(NSDictionary *)snapshot artwork:(UIImage *)artwork;
- (void)releasePlayback;
- (void)dispose;

@end
