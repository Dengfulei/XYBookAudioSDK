#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class XYBookAudioConfiguration;

/// WebView 导航中识别的支付链接类型。
typedef NS_ENUM(NSUInteger, XYBookAudioPaymentLinkType) {
    /// 地址为空或未匹配 SDK 支持的支付链接。
    XYBookAudioPaymentLinkTypeNone,
    /// 微信 H5 支付的 HTTPS 中转链接，路径为 `/cgi-bin/mmpayweb-bin/checkmweb`。
    XYBookAudioPaymentLinkTypeWeChatGateway,
    /// 拉起微信 App 的支付链接 `weixin://wap/pay`。
    XYBookAudioPaymentLinkTypeWeChatApp,
    /// 拉起支付宝 App 的链接 `alipay://alipayclient/`。
    XYBookAudioPaymentLinkTypeAlipayApp,
};

/// 用于识别支付链接、校验发起页面和改写回跳 Scheme 的工具类。
@interface XYBookAudioPaymentLinks : NSObject

- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;

/// 识别微信 H5 中转链接、微信唤起链接或支付宝唤起链接。
/// @param URL 待识别的导航地址，可传 `nil`。
/// @return 匹配的类型。地址为空或未匹配时返回 `XYBookAudioPaymentLinkTypeNone`。
+ (XYBookAudioPaymentLinkType)typeForURL:(nullable NSURL *)URL;

/// 按 HTTPS 主机、端口和路径校验发起支付的页面，忽略查询参数和片段。
/// @param URL 待校验的收银台页面地址，可传 `nil`。
/// @param entryURL SDK 配置的可信 HTTPS 入口地址。
/// @return 页面匹配时返回 `YES`，地址为空或未匹配时返回 `NO`。
+ (BOOL)checkoutURL:(nullable NSURL *)URL matchesEntryURL:(NSURL *)entryURL;

/// 构造原收银台流程的微信中转请求，仅移除末尾指回入口页的 `redirect_url`。
+ (NSURLRequest *)legacyWeChatGatewayRequestFromRequest:(NSURLRequest *)request
                                          configuration:(XYBookAudioConfiguration *)configuration;

/// 构造支持回跳页的微信中转请求，提取并移除唯一可信的 `redirect_url`。
/// @param request 原始微信 H5 支付中转请求。
/// @param configuration SDK 的可信来源、路径和支付配置。
/// @param returnURL 输出完整的可信 HTTPS 回跳地址，缺失或无效时为 `nil`。
+ (NSURLRequest *)wechatGatewayRequestFromRequest:(NSURLRequest *)request
                                    configuration:(XYBookAudioConfiguration *)configuration
                                        returnURL:(NSURL *_Nullable *_Nonnull)returnURL;

/// 替换支付宝 SafePay 数据中的 `fromAppUrlScheme`，保留原支付数据。
/// @param URL 原始支付宝唤起链接，可传 `nil`。
/// @param returnScheme 宿主注册的支付宝回跳 Scheme，不带 `://`。
/// @return 改写后的唤起链接。原链接为空或无法处理时返回 `nil`。
+ (nullable NSURL *)alipayURLFromURL:(nullable NSURL *)URL withReturnScheme:(NSString *)returnScheme;

@end

NS_ASSUME_NONNULL_END
