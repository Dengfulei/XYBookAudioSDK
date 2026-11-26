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

/// 创建 SDK 错误对象。
/// @param code SDK 错误码。
/// @param message 写入 `localizedDescription` 的错误说明。
/// @return 错误域为 `XYBookAudioErrorDomain` 的 `NSError`。
FOUNDATION_EXPORT NSError *XYBookAudioError(XYBookAudioErrorCode code, NSString *message);

/// 将错误转换为稳定的字符串标识。
/// @param error 要读取的错误。
/// @return 对应的 SDK 错误名，未知错误返回 `INTERNAL_ERROR`。
FOUNDATION_EXPORT NSString *XYBookAudioErrorName(NSError *error);

@interface XYBookAudioIdentity : NSObject <NSCopying>

/// `userId` 非空时为 YES。
@property (nonatomic, readonly) BOOL isLoggedIn;
/// 宿主账号标识，游客使用空字符串。
@property (nonatomic, copy, readonly) NSString *userId;

/// 创建仅包含账号标识的听书身份。
/// @param userId 宿主账号标识，传 nil 或空字符串表示游客。
/// @return 可交给 SDK 的只读身份对象。
- (instancetype)initWithUserId:(nullable NSString *)userId;

@end

@interface XYBookAudioChapter : NSObject

/// 章节标识，在同一队列内唯一。
@property (nonatomic, copy) NSString *chapterId;
/// 用于播放快照和锁屏显示的章节标题。
@property (nonatomic, copy) NSString *title;
/// 为 YES 时，只有已登录用户可以播放。
@property (nonatomic) BOOL requiresLogin;
/// 当前账号获授权的音源 URL 字符串。音源未提供或授权已撤销时为 nil。
@property (nonatomic, copy, nullable) NSString *audioURL;
/// 已知的章节时长，单位为毫秒。未知时为 nil。
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
/// `level` 为日志级别，`component` 为产生日志的 SDK 模块，`message` 为日志正文。
typedef void (^XYBookAudioLogHandler)(XYBookAudioLogLevel level, NSString *component, NSString *message);

/// 现有 H5 收银台的可选支付配置。每个渠道在提供其回跳 Scheme 时启用。
@interface XYBookAudioPaymentConfiguration : NSObject <NSCopying>

/// 按宿主 Info.plist 的 CFBundleURLName 查找第一个非空的 Scheme，未配置时返回 nil。
+ (nullable NSString *)hostURLSchemeForName:(NSString *)URLName;

/// 宿主注册的微信支付回跳 Scheme（不带 `://`），用于构造微信中转请求的缺省 `Referer`。
@property (nonatomic, copy, nullable) NSString *wechatReturnScheme;
/// 配置 `wechatReturnScheme` 后，选择 H5 微信支付流程。
/// 默认 `YES`，使用原收银台流程，中转请求使用宿主微信 Scheme 作为 Referer。
/// 仅移除末尾指回同一 HTTPS 入口页的 `redirect_url`，拉起微信前恢复原收银台。
/// 设为 `NO` 时，支持直接拉起微信，并在 App 恢复活跃后加载暂存的可信回跳地址。
@property (nonatomic) BOOL usesLegacyWeChatPaymentFlow;
/// 宿主注册的支付宝支付回跳 Scheme（不带 `://`），用于 `SafePay` 链接的 `fromAppUrlScheme`。
@property (nonatomic, copy, nullable) NSString *alipayReturnScheme;

@end

@interface XYBookAudioConfiguration : NSObject <NSCopying>

/// 宿主命名空间，和 `environment` 一起隔离播放断点。
@property (nonatomic, copy) NSString *hostIdentifier;
/// 业务环境，默认为 `production`。
@property (nonatomic, copy) NSString *environment;
/// 听书首页地址。支持可信 HTTPS 入口和显式指定的本地文件入口。
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

/// 默认为 nil。启用后仅允许可信 HTTPS 入口页发起支付，按 origin 和路径匹配。
@property (nonatomic, copy, nullable) XYBookAudioPaymentConfiguration *payment;

/// 允许访问的 HTTPS origin 集合，按协议、主机和端口精确匹配。默认取自入口地址。
@property (nonatomic, copy) NSSet<NSString *> *trustedOrigins;
/// 允许访问的路径前缀，按路径段边界匹配。默认使用入口路径。
@property (nonatomic, copy) NSArray<NSString *> *allowedPathPrefixes;

/// 创建配置，供 SDK 初始化时校验并复制。
/// @param hostIdentifier 非空的宿主命名空间，例如宿主 App 的 Bundle ID。
/// @param entryURL 听书首页地址，用于生成初始可信范围。
/// @return 可在创建 SDK 前调整的配置对象。
- (instancetype)initWithHostIdentifier:(NSString *)hostIdentifier entryURL:(NSURL *)entryURL;

/// 校验页面地址。此方法只检查地址和配置。
/// @param URL 待打开或导航到的页面地址。
/// @return 页面在可信 HTTPS origin 与路径范围内，或在显式配置的本地资源目录内时返回 YES。
- (BOOL)allowsURL:(NSURL *)URL;

/// 校验原生队列音源地址。
/// @param URL 待播放的音源地址。
/// @return HTTPS 地址返回 YES。本地文件仅在显式本地页面模式下且解析后的路径位于入口目录内时返回 YES。
- (BOOL)allowsMediaURL:(NSURL *)URL;

/// 仅 file 入口启用本地资源目录；远程页面始终不能获得文件访问权限。
@property (nonatomic, readonly, nullable) NSURL *localResourceDirectory;

/// 校验命名空间、入口来源和日志级别。
/// @param error 可选的错误输出地址。校验失败时写入错误原因。
/// @return 配置有效时返回 YES，否则返回 NO。
- (BOOL)validate:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
