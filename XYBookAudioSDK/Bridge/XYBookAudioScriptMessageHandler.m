// 将原项目 EasyJS 消息解码为 JSCallNative: 调用；不持有 WebView、页面或播放会话。
#import "XYBookAudioScriptMessageHandler.h"

@implementation XYBookAudioScriptMessageHandler

/// 先验证来源和传输长度，再按 EasyJS 的对象名／方法名／参数串解码；不接受简化的裸 JSON 传输。
- (void)userContentController:(WKUserContentController *)controller didReceiveScriptMessage:(WKScriptMessage *)message {
    if (!self.messageValidator || !self.messageValidator(message)) {
        return;
    }
    NSString *argument = [self argumentFromEasyJSMessage:message];
    if (argument) {
        [self JSCallNative:argument];
    }
}

/// JSCallNative: 只有一个参数；两次解码之间检查参数分隔符，避免把多个参数误拼成一个 JSON 字符串。
- (NSString *)argumentFromEasyJSMessage:(WKScriptMessage *)message {
    NSArray<NSString *> *components = [message.body componentsSeparatedByString:@":"];
    if (components.count != 3 || ![components.firstObject isEqual:message.name]) {
        [self rejectMessage:@"EasyJS expects object:encodedMethod:encodedArguments."];
        return nil;
    }
    NSString *method = components[1].stringByRemovingPercentEncoding;
    if (![method isEqual:NSStringFromSelector(@selector(JSCallNative:))]) {
        [self rejectMessage:@"EasyJS only exposes JSCallNative:."];
        return nil;
    }
    NSString *encodedArgument = components[2].stringByRemovingPercentEncoding;
    if (!encodedArgument || [encodedArgument containsString:@":"]) {
        [self rejectMessage:@"JSCallNative: expects exactly one URI-encoded argument."];
        return nil;
    }
    NSString *argument = encodedArgument.stringByRemovingPercentEncoding;
    if (!argument) {
        [self rejectMessage:@"EasyJS argument has invalid URI encoding."];
        return nil;
    }
    return argument;
}

/// 传输错误沿用管理类的日志和错误事件，避免在适配层另造一套回执。
- (void)rejectMessage:(NSString *)reason {
    if (self.invalidMessageHandler) {
        self.invalidMessageHandler(reason);
    }
}

- (void)JSCallNative:(NSString *)object {
    if (self.JSCallNativeBlock) {
        self.JSCallNativeBlock(object);
    }
}

@end
