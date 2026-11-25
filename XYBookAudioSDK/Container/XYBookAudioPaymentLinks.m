#import "XYBookAudioPaymentLinks.h"

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
