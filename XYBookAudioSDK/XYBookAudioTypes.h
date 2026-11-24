// 公开配置、值类型和错误定义；不暴露宿主模型或三方库类型，时间与播放位置统一使用毫秒。
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN
FOUNDATION_EXPORT NSErrorDomain const XYBookAudioErrorDomain;
typedef NS_ERROR_ENUM(XYBookAudioErrorDomain, XYBookAudioErrorCode){
    XYBookAudioInvalidArgument = 1,
    XYBookAudioInvalidState,
    XYBookAudioBusy,
    XYBookAudioLoginRequired,
    XYBookAudioSourceNotReady,
    XYBookAudioUnsupported,
    XYBookAudioPlaybackFailed,
    XYBookAudioHostFailed,
    XYBookAudioUntrustedSource,
    XYBookAudioDisposed,
    XYBookAudioStorageFailed
};
FOUNDATION_EXPORT NSError *XYBookAudioError(XYBookAudioErrorCode code, NSString *message);
FOUNDATION_EXPORT NSString *XYBookAudioErrorName(NSError *error);

@interface XYBookAudioIdentity : NSObject <NSCopying>

@property (nonatomic, readonly) BOOL isLoggedIn;
@property (nonatomic, copy, readonly) NSString *userId;

/// 空 userId 表示游客；只保留身份标识，不携带 token、密码或完整用户资料。
- (instancetype)initWithUserId:(nullable NSString *)userId;

@end

@interface XYBookAudioChapter : NSObject

@property (nonatomic, copy) NSString *chapterId;
@property (nonatomic, copy) NSString *title;
@property (nonatomic) BOOL requiresLogin;
@property (nonatomic, copy, nullable) NSString *audioURL;
@property (nonatomic, strong, nullable) NSNumber *durationMs;

@end

/// 日志级别按输出范围递增；Off 禁用全部 SDK 日志，Debug 包含其余级别。
typedef NS_ENUM(NSInteger, XYBookAudioLogLevel) {
    XYBookAudioLogLevelOff = 0,
    XYBookAudioLogLevelError,
    XYBookAudioLogLevelWarning,
    XYBookAudioLogLevelInfo,
    XYBookAudioLogLevelDebug
};

/// 日志在主线程同步回调，默认脱敏。回调应快速返回，避免强引用 SDK 或重入业务接口。
typedef void (^XYBookAudioLogHandler)(XYBookAudioLogLevel level, NSString *component, NSString *message);

@interface XYBookAudioConfiguration : NSObject <NSCopying>

@property (nonatomic, copy) NSString *hostIdentifier;
@property (nonatomic, copy) NSString *environment;
@property (nonatomic, copy) NSURL *entryURL;

/// 默认 Off；初始化 SDK 时复制配置，仅影响该实例。设置后仍会照常返回业务错误。
@property (nonatomic) XYBookAudioLogLevel logLevel;

/// 可选输出回调；设置后替代默认 NSLog。Off 时既不回调，也不输出控制台日志。
/// 此开关仅控制 SDK 自身日志，不能关闭系统 WebKit、AVFoundation 或宿主日志。
@property (nonatomic, copy, nullable) XYBookAudioLogHandler logHandler;

/// 默认 NO。设为 YES 并启用 Debug 日志时，输出 H5 调用 JSCallNative: 的请求原文，可能包含敏感数据。
@property (nonatomic) BOOL bridgeRequestPayloadLoggingEnabled;

/// 默认 NO；宿主可在联调时启用 iOS 16.4 及以上内置 WebView 的 Safari 检查。
@property (nonatomic) BOOL webInspectorEnabled;

/// HTTPS origin 精确匹配；路径另按目录段边界校验，不采用字符串包含匹配。
@property (nonatomic, copy) NSSet<NSString *> *trustedOrigins;
@property (nonatomic, copy) NSArray<NSString *> *allowedPathPrefixes;

/// 创建配置；SDK 初始化时会校验入口并复制全部配置，修改原配置不会影响运行中的实例。
- (instancetype)initWithHostIdentifier:(NSString *)hostIdentifier entryURL:(NSURL *)entryURL;

/// 校验页面是否位于可信 HTTPS origin／路径段或本地资源目录；不触发网络请求。
- (BOOL)allowsURL:(NSURL *)URL;

/// 允许 HTTPS 音源；仅在显式本地页面模式下允许入口目录内的文件音源，并解析符号链接阻止越界。
- (BOOL)allowsMediaURL:(NSURL *)URL;

/// 仅 file 入口启用本地资源目录；远程页面始终不能获得文件访问权限。
@property (nonatomic, readonly, nullable) NSURL *localResourceDirectory;

/// 校验命名空间、入口来源和日志级别；失败返回 NO 并写入错误，不修改当前配置。
- (BOOL)validate:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
