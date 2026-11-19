// SDK 自带页面容器；负责原生导航和 WebView，关闭时只断开页面连接并保留播放会话。
#import <UIKit/UIKit.h>
#import "XYBookAudioSDKManager.h"

#import "XYBookAudioLogger.h"
#import "XYBookAudioWindowRouting.h"

@interface XYBookAudioWebViewController : UIViewController

/// entryURL 仅指定当前窗口入口，可信范围始终由初始 configuration 决定。
- (instancetype)initWithSDK:(XYBookAudioSDKManager *)SDK
              configuration:(XYBookAudioConfiguration *)configuration
                   entryURL:(NSURL *)entryURL
               windowRouter:(id<XYBookAudioWindowRouting>)windowRouter
                     logger:(XYBookAudioLogger *)logger;
/// 页面出栈或整个容器关闭时撤销 Bridge、UA 读取和网页加载；不会改变播放状态。
- (void)invalidatePage;

@end
