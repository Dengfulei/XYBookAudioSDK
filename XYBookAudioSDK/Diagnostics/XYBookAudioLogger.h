// 每个 SDK 实例独立的诊断出口：负责级别过滤和输出，不持有业务状态、不上传或持久化日志。
#import "XYBookAudioTypes.h"

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSString *const XYBookAudioLogSDK;
FOUNDATION_EXPORT NSString *const XYBookAudioLogPage;
FOUNDATION_EXPORT NSString *const XYBookAudioLogBridge;
FOUNDATION_EXPORT NSString *const XYBookAudioLogPlayback;
FOUNDATION_EXPORT NSString *const XYBookAudioLogHost;
FOUNDATION_EXPORT NSString *const XYBookAudioLogAudio;
FOUNDATION_EXPORT NSString *const XYBookAudioLogStorage;

@interface XYBookAudioLogger : NSObject

/// 复制级别和回调，避免外部配置变更串扰运行中的实例；由主线程中的 SDK 对象共享。
- (instancetype)initWithConfiguration:(XYBookAudioConfiguration *)configuration;

/// 仅允许传入固定文案、已实现的动作／已知状态和数值；禁止原始 URL、用户标识及协议字典。
- (void)write:(XYBookAudioLogLevel)level component:(NSString *)component message:(NSString *)message;

/// 仅输出可信错误域和数值错误码；不展开 localizedDescription、userInfo 或宿主自定义错误域。
- (void)error:(nullable NSError *)error component:(NSString *)component operation:(NSString *)operation;

@end

NS_ASSUME_NONNULL_END
