#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSUInteger, XYBookAudioPaymentLinkType) {
    XYBookAudioPaymentLinkTypeNone,
    XYBookAudioPaymentLinkTypeWeChatGateway,
    XYBookAudioPaymentLinkTypeWeChatApp,
    XYBookAudioPaymentLinkTypeAlipayApp,
};

@interface XYBookAudioPaymentLinks : NSObject

- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;

+ (XYBookAudioPaymentLinkType)typeForURL:(nullable NSURL *)URL;
+ (BOOL)checkoutURL:(nullable NSURL *)URL matchesEntryURL:(NSURL *)entryURL;
+ (nullable NSURL *)alipayURLFromURL:(nullable NSURL *)URL withReturnScheme:(NSString *)returnScheme;

@end

NS_ASSUME_NONNULL_END
