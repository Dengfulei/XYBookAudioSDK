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

/// 创建系统媒体适配器并注册音频通知。
/// @param logger 当前 SDK 实例的日志出口。
- (instancetype)initWithLogger:(XYBookAudioLogger *)logger;

/// 宿主音频交接前预留 App 共享的音频控制权。
/// @return 本次预留的令牌。已有会话预留或占用音频时返回 nil。
- (NSUUID *)reservePlayback;

/// 撤销尚未激活的音频预留。
/// @param reservation `reservePlayback` 返回的令牌。只撤销当前实例匹配的预留。
- (void)cancelPlaybackReservation:(NSUUID *)reservation;

/// 判断迟到的宿主交接能否归还给宿主。
/// @param reservation 原音频交接的预留令牌。
/// @return 无会话占用且该预留尚未被新请求替代时返回 YES。
+ (BOOL)canReturnLateHandoffForReservation:(NSUUID *)reservation;

/// 激活已预留的系统音频会话，首次激活时注册锁屏命令。
/// @param error 可选的错误输出地址，接收预留或系统音频激活错误。
/// @return 成功激活或重新激活时返回 YES。
- (BOOL)acquire:(NSError **)error;

/// 在本实例持有音频时更新锁屏播放信息。
/// @param snapshot 原生播放快照，含章节、位置、倍速和播放状态。
/// @param artwork 当前封面。没有封面时传 nil。
- (void)update:(NSDictionary *)snapshot artwork:(UIImage *)artwork;

/// 释放本实例激活的音频会话与锁屏控制。
- (void)releasePlayback;
/// 释放音频占用并取消系统通知观察。
- (void)dispose;

@end
