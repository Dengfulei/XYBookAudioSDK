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
/// @param configuration 提供日志级别和可选的宿主日志回调。
- (instancetype)initWithConfiguration:(XYBookAudioConfiguration *)configuration;

/// 按实例日志级别输出诊断消息。
/// @param level 本条日志的级别。
/// @param component 产生日志的 SDK 模块，使用对应的模块常量。
/// @param message 使用固定文案或已知状态。仅在宿主显式开启桥接请求诊断时可传入请求原文。
- (void)write:(XYBookAudioLogLevel)level component:(NSString *)component message:(NSString *)message;

/// 记录错误域及数值错误码。
/// @param error 诊断错误。未知错误域统一输出为 `ExternalError`。
/// @param component 发生错误的 SDK 模块。
/// @param operation 固定的操作名，用于定位错误来源。
- (void)error:(nullable NSError *)error component:(NSString *)component operation:(NSString *)operation;

@end

NS_ASSUME_NONNULL_END
