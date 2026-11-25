// SDK 自带页面容器；负责原生导航和 WebView，关闭时只断开页面连接并保留播放会话。
#import <UIKit/UIKit.h>
#import "XYBookAudioSDKManager.h"

#import "XYBookAudioLogger.h"
#import "XYBookAudioWindowRouting.h"

@interface XYBookAudioWebViewController : UIViewController

/// 根页完成从宿主导航栈移除时通知窗口路由。
@property (nonatomic, copy) dispatch_block_t didLeaveNavigation;

/// 创建听书窗口。根页和子页使用同一套可信范围。
/// @param SDK 当前播放会话的业务入口。
/// @param configuration 初始可信来源、路径和页面调试配置。
/// @param entryURL 当前窗口要加载的地址。
/// @param windowRouter 处理 SDK 子页的打开与关闭。
/// @param logger 当前 SDK 实例的日志出口。
- (instancetype)initWithSDK:(XYBookAudioSDKManager *)SDK
              configuration:(XYBookAudioConfiguration *)configuration
                   entryURL:(NSURL *)entryURL
               windowRouter:(id<XYBookAudioWindowRouting>)windowRouter
                     logger:(XYBookAudioLogger *)logger;
/// 页面出栈或整个容器关闭时撤销 Bridge、UA 读取和网页加载；不会改变播放状态。
- (void)invalidatePage;

@end
