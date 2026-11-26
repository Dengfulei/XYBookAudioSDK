// 配置和值类型的复制、来源校验与错误映射；不读取宿主账号，不执行网页或播放 IO。
#import "XYBookAudioTypes.h"
#import "XYBookAudioMessageProtocol.h"

NSErrorDomain const XYBookAudioErrorDomain = @"com.xinhuamm.bookaudio";

NSError *XYBookAudioError(XYBookAudioErrorCode code, NSString *message) {
    return [NSError errorWithDomain:XYBookAudioErrorDomain code:code userInfo:@{NSLocalizedDescriptionKey : message}];
}

NSString *XYBookAudioErrorName(NSError *error) {
    NSArray *names = @[
        @"INVALID_ARGUMENT", @"INVALID_STATE", @"BUSY", @"LOGIN_REQUIRED", @"SOURCE_NOT_READY", @"UNSUPPORTED",
        @"PLAYBACK_FAILED", @"HOST_FAILED", @"UNTRUSTED_SOURCE", @"DISPOSED", @"STORAGE_FAILED"
    ];
    if (![error.domain isEqualToString:XYBookAudioErrorDomain] || error.code < 1 ||
        error.code > (NSInteger)names.count) {
        return @"INTERNAL_ERROR";
    }
    return names[error.code - 1];
}

@implementation XYBookAudioIdentity

- (instancetype)initWithUserId:(NSString *)userId {
    if ((self = [super init])) {
        _userId = [userId copy] ?: @"";
        _isLoggedIn = _userId.length > 0;
    }
    return self;
}

/// 复制身份值；空身份仍保持游客语义，不读取宿主账号或凭证。
- (id)copyWithZone:(NSZone *)zone {
    return [[XYBookAudioIdentity alloc] initWithUserId:self.userId];
}

@end

@implementation XYBookAudioChapter

@end

static NSString *XYBookAudioOrigin(NSURL *URL) {
    if (!URL.host || !URL.scheme) {
        return @"";
    }
    NSString *port =
        URL.port && URL.port.integerValue != 443 ? [@":" stringByAppendingString:URL.port.stringValue] : @"";
    return [NSString stringWithFormat:@"%@://%@%@", URL.scheme.lowercaseString, URL.host.lowercaseString, port];
}

static BOOL XYBookAudioIsPaymentScheme(NSString *scheme) {
    if (!scheme) {
        return YES;
    }
    NSArray *reserved = @[ @"http", @"https", @"file", @"about", @"data", @"javascript", @"weixin",
                           @"alipay", @"alipays", @"tel", @"sms", @"mailto" ];
    if (!scheme.length || [reserved containsObject:scheme.lowercaseString]) {
        return NO;
    }
    return [scheme rangeOfString:@"^[A-Za-z][A-Za-z0-9+.-]*$" options:NSRegularExpressionSearch].length == scheme.length;
}

@implementation XYBookAudioPaymentConfiguration

- (instancetype)init {
    if ((self = [super init])) {
        _usesLegacyWeChatPaymentFlow = YES;
    }
    return self;
}

+ (NSString *)hostURLSchemeForName:(NSString *)URLName {
    id URLTypes = [NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleURLTypes"];
    if (![URLTypes isKindOfClass:NSArray.class]) {
        return nil;
    }
    for (id URLType in URLTypes) {
        if (![URLType isKindOfClass:NSDictionary.class] || ![URLType[@"CFBundleURLName"] isEqual:URLName]) {
            continue;
        }
        id schemes = URLType[@"CFBundleURLSchemes"];
        if (![schemes isKindOfClass:NSArray.class]) {
            continue;
        }
        for (id scheme in schemes) {
            if ([scheme isKindOfClass:NSString.class] && [scheme length]) {
                return scheme;
            }
        }
    }
    return nil;
}

- (id)copyWithZone:(NSZone *)zone {
    XYBookAudioPaymentConfiguration *copy = [[self.class allocWithZone:zone] init];
    copy.wechatReturnScheme = self.wechatReturnScheme;
    copy.usesLegacyWeChatPaymentFlow = self.usesLegacyWeChatPaymentFlow;
    copy.alipayReturnScheme = self.alipayReturnScheme;
    return copy;
}

@end

@implementation XYBookAudioConfiguration

- (instancetype)initWithHostIdentifier:(NSString *)hostIdentifier entryURL:(NSURL *)entryURL {
    if ((self = [super init])) {
        _hostIdentifier = [hostIdentifier copy];
        _entryURL = [entryURL copy];
        _environment = @"production";
        _logLevel = XYBookAudioLogLevelOff;
        _trustedOrigins = [NSSet setWithObject:XYBookAudioOrigin(entryURL)];
        _allowedPathPrefixes = @[ entryURL.path.length ? entryURL.path : @"/" ];
    }
    return self;
}

/// 复制配置和日志回调，确保宿主后续修改配置不会串扰已有实例。
- (id)copyWithZone:(NSZone *)zone {
    XYBookAudioConfiguration *copy = [[self.class alloc] initWithHostIdentifier:self.hostIdentifier
                                                                       entryURL:self.entryURL];
    copy.environment = self.environment;
    copy.logLevel = self.logLevel;
    copy.logHandler = self.logHandler;
    copy.bridgeRequestPayloadLoggingEnabled = self.bridgeRequestPayloadLoggingEnabled;
    copy.webInspectorEnabled = self.webInspectorEnabled;
    copy.payment = self.payment;
    copy.trustedOrigins = self.trustedOrigins;
    copy.allowedPathPrefixes = self.allowedPathPrefixes;
    return copy;
}

- (BOOL)allowsURL:(NSURL *)URL {
    if (self.entryURL.isFileURL) {
        return [self allowsLocalURL:URL];
    }
    if (!XYBookAudioIsHTTPSURLString(URL.absoluteString) ||
        ![self.trustedOrigins containsObject:XYBookAudioOrigin(URL)]) {
        return NO;
    }
    NSString *path = URL.path.length ? URL.path.stringByStandardizingPath : @"/";
    for (NSString *prefix in self.allowedPathPrefixes) {
        NSString *directory = [prefix hasSuffix:@"/"] ? prefix : [prefix stringByAppendingString:@"/"];
        if ([path isEqualToString:prefix] || [path hasPrefix:directory]) {
            return YES;
        }
    }
    return NO;
}

- (NSURL *)localResourceDirectory {
    return self.entryURL.isFileURL ? self.entryURL.URLByResolvingSymlinksInPath.URLByDeletingLastPathComponent : nil;
}

/// 解析路径后按目录段边界校验，阻止同名前缀兄弟目录和符号链接逃逸；此检查不扩大 WebKit 读取权限。
- (BOOL)allowsLocalURL:(NSURL *)URL {
    if (!URL.isFileURL || URL.user || URL.password || (URL.host.length && ![URL.host isEqual:@"localhost"])) {
        return NO;
    }
    NSString *root = self.localResourceDirectory.path;
    return root.length > 1 && [URL.URLByResolvingSymlinksInPath.path hasPrefix:[root stringByAppendingString:@"/"]];
}

- (BOOL)allowsMediaURL:(NSURL *)URL {
    return XYBookAudioIsHTTPSURLString(URL.absoluteString) || (self.entryURL.isFileURL && [self allowsLocalURL:URL]);
}

- (BOOL)hasValidPaymentConfiguration {
    XYBookAudioPaymentConfiguration *payment = self.payment;
    if (!payment) {
        return YES;
    }
    if ((!payment.wechatReturnScheme && !payment.alipayReturnScheme) ||
        !XYBookAudioIsPaymentScheme(payment.wechatReturnScheme) || !XYBookAudioIsPaymentScheme(payment.alipayReturnScheme) ||
        [payment.wechatReturnScheme.lowercaseString isEqualToString:payment.alipayReturnScheme.lowercaseString] ||
        (payment.wechatReturnScheme && [self.trustedOrigins containsObject:@"https://wx.tenpay.com"])) {
        return NO;
    }
    return [self.entryURL.scheme.lowercaseString isEqualToString:@"https"] &&
           !self.entryURL.user && !self.entryURL.password;
}

- (BOOL)validate:(NSError **)error {
    if (self.logLevel < XYBookAudioLogLevelOff || self.logLevel > XYBookAudioLogLevelDebug) {
        if (error) {
            *error = XYBookAudioError(XYBookAudioInvalidArgument, @"Unsupported log level.");
        }
        return NO;
    }
    if (!self.hostIdentifier.length || !self.environment.length || ![self allowsURL:self.entryURL]) {
        if (error) {
            *error = XYBookAudioError(
                XYBookAudioInvalidArgument,
                @"A host namespace, environment and trusted HTTPS entry or explicit local file entry are required.");
        }
        return NO;
    }
    if (![self hasValidPaymentConfiguration]) {
        if (error) {
            *error = XYBookAudioError(XYBookAudioInvalidArgument, @"Invalid H5 payment configuration.");
        }
        return NO;
    }
    return YES;
}

@end
