// 日志统一经过本实例过滤器；关闭时在任何输出之前返回，宿主回调与控制台二选一。
#import "XYBookAudioLogger.h"

NSString *const XYBookAudioLogSDK = @"SDK";
NSString *const XYBookAudioLogPage = @"Page";
NSString *const XYBookAudioLogBridge = @"Bridge";
NSString *const XYBookAudioLogPlayback = @"Playback";
NSString *const XYBookAudioLogHost = @"Host";
NSString *const XYBookAudioLogAudio = @"AudioSession";
NSString *const XYBookAudioLogStorage = @"Checkpoint";

@interface XYBookAudioLogger ()

@property (nonatomic) XYBookAudioLogLevel level;
@property (nonatomic, copy, nullable) XYBookAudioLogHandler handler;
@property (nonatomic) BOOL delivering;

@end

@implementation XYBookAudioLogger

- (instancetype)initWithConfiguration:(XYBookAudioConfiguration *)configuration {
    if ((self = [super init])) {
        _level = configuration.logLevel;
        _handler = [configuration.logHandler copy];
    }
    return self;
}

- (void)write:(XYBookAudioLogLevel)level component:(NSString *)component message:(NSString *)message {
    if (level <= XYBookAudioLogLevelOff || level > XYBookAudioLogLevelDebug || level > self.level) {
        return;
    }
    // 同步回调若间接触发新的 SDK 日志，只跳过嵌套日志，防止无限递归；业务调用仍正常执行。
    if (self.delivering) {
        return;
    }
    if (self.handler) {
        self.delivering = YES;
        self.handler(level, component, message);
        self.delivering = NO;
        return;
    }
    NSArray<NSString *> *names = @[ @"Off", @"Error", @"Warning", @"Info", @"Debug" ];
    NSLog(@"[XYBookAudio][%@][%@] %@", names[level], component, message);
}

- (void)error:(NSError *)error component:(NSString *)component operation:(NSString *)operation {
    if (self.level < XYBookAudioLogLevelError) {
        return;
    }
    // 宿主或网络错误可能把 token、用户信息放进错误描述甚至域名；只放行已知系统域名。
    NSSet<NSString *> *domains = [NSSet setWithArray:@[
        XYBookAudioErrorDomain, NSURLErrorDomain, NSCocoaErrorDomain, NSOSStatusErrorDomain, @"AVFoundationErrorDomain",
        @"WKErrorDomain", @"WebKitInternal"
    ]];
    NSString *domain = error && [domains containsObject:error.domain] ? error.domain : @"ExternalError";
    NSString *message = [NSString stringWithFormat:@"%@ failed: %@ (%ld).", operation, domain, (long)error.code];
    [self write:XYBookAudioLogLevelError component:component message:message];
}

@end
