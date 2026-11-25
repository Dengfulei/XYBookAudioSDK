// SDK 窗口导航边界：明确打开或关闭来源页面，不接收 H5 actionName，不持有播放和账号状态。
#import <UIKit/UIKit.h>

@protocol XYBookAudioWindowRouting <NSObject>

/// 在当前听书导航栈打开子页。
/// @param URL 新窗口地址，必须在 SDK 的可信范围内。
/// @param title 可选的原生页面标题。
/// @param page 发起请求的当前听书页面。
/// @return 导航已发起时返回 nil，参数或页面状态不满足时返回错误。
- (NSError *)openWindowWithURL:(NSURL *)URL title:(NSString *)title fromPage:(UIViewController *)page;

/// 关闭当前听书窗口，播放会话继续保留。
/// @param page 请求关闭的当前听书页。
/// @param beforeClose 可选回调。确认可关闭后、实际导航前调用，用于先发送 H5 回包。
/// @return 导航已发起时返回 nil，当前页面无法关闭时返回错误。
- (NSError *)closeWindowFromPage:(UIViewController *)page beforeClose:(dispatch_block_t)beforeClose;

@end
