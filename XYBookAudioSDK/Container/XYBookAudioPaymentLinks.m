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
    NSURLComponents *components = [NSURLComponents componentsWithURL:request.URL resolvingAgainstBaseURL:NO];
    NSArray<NSURLQueryItem *> *items = components.queryItems;
    BOOL usesSDKFlow = configuration.payment.removesWeChatRedirectURL;
    NSMutableURLRequest *reload =
        usesSDKFlow ? [request mutableCopy] : [NSMutableURLRequest requestWithURL:request.URL];
    if (!usesSDKFlow) {
        reload.allHTTPHeaderFields = request.allHTTPHeaderFields;
    }
    NSURL *rewrittenURL = [self wechatGatewayURLFromComponents:components queryItems:items configuration:configuration
                                                     returnURL:returnURL];
    if (rewrittenURL) {
        reload.URL = rewrittenURL;
    }
    NSString *referer = [self wechatRefererForQueryItems:items hasTrustedReturn:*returnURL != nil
                                                 payment:configuration.payment];
    [reload setValue:referer forHTTPHeaderField:@"Referer"];
    return reload;
}

+ (NSString *)wechatRefererForQueryItems:(NSArray<NSURLQueryItem *> *)items
                        hasTrustedReturn:(BOOL)hasTrustedReturn
                                 payment:(XYBookAudioPaymentConfiguration *)payment {
    BOOL usesSDKFlow = payment.removesWeChatRedirectURL;
    // feature-11 无法接管回跳时，会在 referer 之前尝试用 redirect_url 的主机名。
    NSArray<NSString *> *refererParameters = @[ @"appReferer", @"referer" ];
    if (!usesSDKFlow && !hasTrustedReturn) {
        refererParameters = @[ @"appReferer", @"redirect_url", @"referer" ];
    }
    for (NSString *name in refererParameters) {
        for (NSURLQueryItem *item in items) {
            if (![item.name isEqualToString:name]) {
                continue;
            }
            NSString *referer = usesSDKFlow ? item.value : [self wechatSchemeRefererFromValue:item.value];
            if ([self isUsableReferer:referer]) {
                return referer;
            }
        }
    }
    return [payment.wechatReturnScheme stringByAppendingString:@"://"];
}

+ (nullable NSURL *)wechatGatewayURLFromComponents:(NSURLComponents *)components
                                        queryItems:(NSArray<NSURLQueryItem *> *)items
                                     configuration:(XYBookAudioConfiguration *)configuration
                                         returnURL:(NSURL **)returnURL {
    *returnURL = nil;
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
    // 用解码后的参数定位，直接从原始查询移除，避免重新编码微信的签名参数。
    NSMutableArray<NSString *> *rawItems =
        [[components.percentEncodedQuery componentsSeparatedByString:@"&"] mutableCopy];
    [rawItems removeObjectAtIndex:redirectIndex];
    components.percentEncodedQuery = [rawItems componentsJoinedByString:@"&"];
    NSURL *rewritten = components.URL;
    if ([self typeForURL:rewritten] != XYBookAudioPaymentLinkTypeWeChatGateway) {
        return nil;
    }
    *returnURL = destination;
    return rewritten;
}

+ (nullable NSString *)wechatSchemeRefererFromValue:(nullable NSString *)value {
    if (!value.length) {
        return nil;
    }
    NSURLComponents *components = [NSURLComponents componentsWithString:value];
    if (!components.scheme.length) {
        // 部分收银台对 Referer 地址额外编码了一次。
        value = value.stringByRemovingPercentEncoding;
        components = value.length ? [NSURLComponents componentsWithString:value] : nil;
    }
    if (!components.scheme.length || ![self isUsableReferer:value]) {
        return nil;
    }

    NSString *host = components.host.lowercaseString;
    if (host.length) {
        NSString *referer = [host stringByAppendingString:@"://"];
        return [[NSURLComponents componentsWithString:referer].scheme isEqualToString:host] ? referer : nil;
    }
    NSString *scheme = components.scheme.lowercaseString;
    if ([scheme isEqualToString:@"http"] || [scheme isEqualToString:@"https"]) {
        return nil;
    }
    return [value isEqualToString:[components.scheme stringByAppendingString:@"://"]]
               ? [scheme stringByAppendingString:@"://"]
               : nil;
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
