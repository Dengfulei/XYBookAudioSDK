// 对应原项目 XYInterfaceWKWebView：通过 EasyJS 注入接口，按标准回调入口返回 JSON 对象。
#import "XYBookAudioBridgeWebView.h"
#import "XYBookAudioTypes.h"

static NSString *const XYBookAudioScriptHandlerName = @"xhAppJSBridge";
static NSString *const XYBookAudioNativeCallbackJSFunction = @"window.xhWebJSBridge.nativeCallJS";

/// 沿用原项目 EasyJS 的编码顺序：先编码每个参数，再编码拼接后的参数串；原生必须对应解码两次。
static NSString *const XYBookAudioEasyJSScript =
    @"window.EasyJS = {\n"
     "    call: function (obj, functionName, args) {\n"
     "        var formattedArgs = [];\n"
     "        for (var index = 0, length = args.length; index < length; index++) {\n"
     "            formattedArgs.push(encodeURIComponent(args[index]));\n"
     "        }\n"
     "        var argStr = formattedArgs.length > 0 ? ':' + encodeURIComponent(formattedArgs.join(':')) : '';\n"
     "        window.webkit.messageHandlers[obj].postMessage(obj + ':' + encodeURIComponent(functionName) + argStr);\n"
     "    },\n"
     "    inject: function (obj, methods) {\n"
     "        window[obj] = {};\n"
     "        var jsObj = window[obj];\n"
     "        for (var index = 0, length = methods.length; index < length; index++) {\n"
     "            (function () {\n"
     "                var method = methods[index];\n"
     "                var jsMethod = method.replace(new RegExp(':', 'g'), '');\n"
     "                jsObj[jsMethod] = function () {\n"
     "                    return EasyJS.call(obj, method, Array.prototype.slice.call(arguments));\n"
     "                };\n"
     "            })();\n"
     "        }\n"
     "    }\n"
     "};";

@implementation XYBookAudioBridgeWebView

/// 先注入 EasyJS，再注册标准对象；只导出 JSCallNative:，不把属性访问器等原生 selector 暴露给 H5。
- (void)addJavascriptInterface:(XYBookAudioScriptMessageHandler *)interface {
    WKUserContentController *controller = self.configuration.userContentController;
    [controller addScriptMessageHandler:interface name:XYBookAudioScriptHandlerName];
    WKUserScript *script = [[WKUserScript alloc] initWithSource:XYBookAudioEasyJSScript
                                                  injectionTime:WKUserScriptInjectionTimeAtDocumentStart
                                               forMainFrameOnly:YES];
    [controller addUserScript:script];
    NSString *injection = [NSString stringWithFormat:@"EasyJS.inject(\"%@\", [\"%@\"]);", XYBookAudioScriptHandlerName,
                                                     NSStringFromSelector(@selector(JSCallNative:))];
    WKUserScript *interfaceScript = [[WKUserScript alloc] initWithSource:injection
                                                           injectionTime:WKUserScriptInjectionTimeAtDocumentStart
                                                        forMainFrameOnly:YES];
    [controller addUserScript:interfaceScript];
}

/// 移除与注入对象同名的 WebKit 接收器，释放接口对象；不影响宿主其他 WebView。
- (void)removeJavascriptInterface {
    [self.configuration.userContentController removeScriptMessageHandlerForName:XYBookAudioScriptHandlerName];
}

/// 与参考项目一致调用“回调方法(JSON)”；JSON 由系统序列化，不能直接拼接业务字段或再次 URI 编码。
- (void)nativeCallJS:(NSDictionary *)message completion:(void (^)(NSError *error))completion {
    if (![NSJSONSerialization isValidJSONObject:message]) {
        if (completion) {
            completion(XYBookAudioError(XYBookAudioInvalidArgument, @"Native callback requires a JSON object."));
        }
        return;
    }
    NSError *error = nil;
    NSData *data = [NSJSONSerialization dataWithJSONObject:message options:0 error:&error];
    if (!data) {
        if (completion) {
            completion(error);
        }
        return;
    }
    NSString *JSON = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    NSString *script = [NSString stringWithFormat:@"%@(%@)", XYBookAudioNativeCallbackJSFunction, JSON];
    [self evaluateJavaScript:script completionHandler:^(id result, NSError *error) {
        if (completion) {
            completion(error);
        }
    }];
}

@end
