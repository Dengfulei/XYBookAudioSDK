// SDK 窗口导航边界：明确打开或关闭来源页面，不接收 H5 actionName，不持有播放和账号状态。
#import <UIKit/UIKit.h>

@protocol XYBookAudioWindowRouting <NSObject>

/// 打开新窗口；导航接受返回 nil，地址不可信或来源页面不可操作时返回错误。
- (NSError *)openWindowWithURL:(NSURL *)URL fromPage:(UIViewController *)page;
/// 关闭当前窗口：子页出栈，根页关闭整个 SDK 容器；不停止播放。
- (NSError *)closeWindowFromPage:(UIViewController *)page;

@end
