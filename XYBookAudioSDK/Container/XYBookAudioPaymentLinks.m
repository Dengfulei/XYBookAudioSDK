#import "XYBookAudioPaymentLinks.h"
#import "XYBookAudioTypes.h"

@implementation XYBookAudioPaymentLinks

/// 基于已解析的 URL 组件识别链接类型。
/// @param components 已解析的 URL 组件，可传 `nil`。
/// @return 匹配的支付链接类型。组件为空或未匹配时返回 `XYBookAudioPaymentLinkTypeNone`。
+ (XYBookAudioPaymentLinkType)typeForURLComponents:(nullable NSURLComponents *)components {
    if (components.user || components.password || components.port || components.fragment) {
        return XYBookAudioPaymentLinkTypeNone;
    }
    NSString *scheme = components.scheme.lowercaseString;
    NSString *host = components.host.lowercaseString;
    NSString *path = components.percentEncodedPath;
    if ([scheme isEqualToString:@"https"] && [host isEqualToString:@"wx.tenpay.com"] &&
        [path isEqualToString:@"/cgi-bin/mmpayweb-bin/checkmweb"] && components.percentEncodedQuery.length) {
        return XYBookAudioPaymentLinkTypeWeChatGateway;
    }
    if ([scheme isEqualToString:@"weixin"] && [host isEqualToString:@"wap"] && [path isEqualToString:@"/pay"]) {
        return XYBookAudioPaymentLinkTypeWeChatApp;
    }
    if ([scheme isEqualToString:@"alipay"] && [host isEqualToString:@"alipayclient"] &&
        ([path isEqualToString:@""] || [path isEqualToString:@"/"])) {
        return XYBookAudioPaymentLinkTypeAlipayApp;
    }
    return XYBookAudioPaymentLinkTypeNone;
}

+ (XYBookAudioPaymentLinkType)typeForURL:(NSURL *)URL {
    return URL ? [self typeForURLComponents:[NSURLComponents componentsWithURL:URL resolvingAgainstBaseURL:NO]]
               : XYBookAudioPaymentLinkTypeNone;
}

+ (BOOL)checkoutURL:(NSURL *)URL matchesEntryURL:(NSURL *)entryURL {
    return [URL.scheme.lowercaseString isEqualToString:@"https"] &&
           [entryURL.scheme.lowercaseString isEqualToString:@"https"] &&
           !URL.user && !URL.password && [URL.host.lowercaseString isEqualToString:entryURL.host.lowercaseString] &&
           [(URL.port ?: @443) isEqual:(entryURL.port ?: @443)] &&
           [(URL.path ?: @"") isEqualToString:(entryURL.path ?: @"")];
}

+ (NSURLRequest *)wechatGatewayRequestFromRequest:(NSURLRequest *)request
                                    configuration:(XYBookAudioConfiguration *)configuration
                                        returnURL:(NSURL **)returnURL {
    *returnURL = nil;
    NSURLComponents *components = [NSURLComponents componentsWithURL:request.URL resolvingAgainstBaseURL:NO];
    NSArray<NSURLQueryItem *> *items = components.queryItems;
    NSMutableURLRequest *reload = [request mutableCopy];
    NSURL *rewrittenURL = [self wechatGatewayURLFromComponents:components queryItems:items configuration:configuration
                                                     returnURL:returnURL];
    if (rewrittenURL) {
        reload.URL = rewrittenURL;
    }
    for (NSString *name in @[ @"appReferer", @"referer" ]) {
        for (NSURLQueryItem *item in items) {
            if ([item.name isEqualToString:name] && [self isUsableReferer:item.value]) {
                [reload setValue:item.value forHTTPHeaderField:@"Referer"];
                return reload;
            }
        }
    }
    [reload setValue:[configuration.payment.wechatReturnScheme stringByAppendingString:@"://"]
        forHTTPHeaderField:@"Referer"];
    return reload;
}

+ (nullable NSURL *)wechatGatewayURLFromComponents:(NSURLComponents *)components
                                        queryItems:(NSArray<NSURLQueryItem *> *)items
                                     configuration:(XYBookAudioConfiguration *)configuration
                                         returnURL:(NSURL **)returnURL {
    NSUInteger redirectIndex = NSNotFound;
    for (NSUInteger index = 0; index < items.count; index++) {
        if ([items[index].name isEqualToString:@"redirect_url"]) {
            if (redirectIndex != NSNotFound) {
                return nil;
            }
            redirectIndex = index;
        }
    }
    if (redirectIndex == NSNotFound) {
        return nil;
    }

    // queryItems 已解码一层，回跳地址中的查询和片段保持原样。
    NSString *target = items[redirectIndex].value;
    if (!target.length) {
        return nil;
    }
    NSURL *destination;
    if (@available(iOS 17.0, *)) {
        destination = [NSURL URLWithString:target encodingInvalidCharacters:NO];
    } else {
        destination = [NSURL URLWithString:target];
    }
    if (![destination.scheme.lowercaseString isEqualToString:@"https"] || ![configuration allowsURL:destination]) {
        return nil;
    }
    *returnURL = destination;
    if (!configuration.payment.removesWeChatRedirectURL) {
        return nil;
    }

    // 用解码后的参数定位，直接从原始查询移除，避免重新编码微信的签名参数。
    NSMutableArray<NSString *> *rawItems =
        [[components.percentEncodedQuery componentsSeparatedByString:@"&"] mutableCopy];
    [rawItems removeObjectAtIndex:redirectIndex];
    components.percentEncodedQuery = [rawItems componentsJoinedByString:@"&"];
    NSURL *rewritten = components.URL;
    return [self typeForURL:rewritten] == XYBookAudioPaymentLinkTypeWeChatGateway ? rewritten : nil;
}

+ (BOOL)isUsableReferer:(nullable NSString *)referer {
    return referer.length &&
           [referer rangeOfCharacterFromSet:NSCharacterSet.whitespaceAndNewlineCharacterSet].location == NSNotFound &&
           [referer rangeOfCharacterFromSet:NSCharacterSet.controlCharacterSet].location == NSNotFound;
}

+ (NSURL *)alipayURLFromURL:(NSURL *)URL withReturnScheme:(NSString *)returnScheme {
    NSURLComponents *parts = URL ? [NSURLComponents componentsWithURL:URL resolvingAgainstBaseURL:NO] : nil;
    if ([self typeForURLComponents:parts] != XYBookAudioPaymentLinkTypeAlipayApp) {
        return nil;
    }
    NSData *data = [parts.query dataUsingEncoding:NSUTF8StringEncoding];
    if (!data.length) {
        return nil;
    }
    id payload = [NSJSONSerialization JSONObjectWithData:data options:NSJSONReadingMutableContainers error:nil];
    if (![payload isKindOfClass:NSMutableDictionary.class] || ![payload[@"requestType"] isEqual:@"SafePay"] ||
        ![payload[@"fromAppUrlScheme"] isKindOfClass:NSString.class] ||
        ![payload[@"dataString"] isKindOfClass:NSString.class] || ![payload[@"dataString"] length]) {
        return nil;
    }
    payload[@"fromAppUrlScheme"] = returnScheme;
    NSData *rewritten = [NSJSONSerialization dataWithJSONObject:payload options:0 error:nil];
    if (!rewritten) {
        return nil;
    }
    NSString *query = [[NSString alloc] initWithData:rewritten encoding:NSUTF8StringEncoding];
    NSCharacterSet *allowed = [NSCharacterSet characterSetWithCharactersInString:
        @"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"];
    parts.percentEncodedQuery = [query stringByAddingPercentEncodingWithAllowedCharacters:allowed];
    return parts.URL;
}

@end
