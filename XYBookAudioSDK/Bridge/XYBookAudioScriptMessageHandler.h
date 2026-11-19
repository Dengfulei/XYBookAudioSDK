// H5 对象适配层：只暴露 JSCallNative:，通过弱捕获的回调连接业务管理类，避免 WebKit 循环持有页面。
#import <WebKit/WebKit.h>

@interface XYBookAudioScriptMessageHandler : NSObject <WKScriptMessageHandler>

/// 管理类检查可信主文档与页面有效期；未通过检查的消息不得进入 JSCallNative:。
@property (nonatomic, copy) BOOL (^messageValidator)(WKScriptMessage *message);
/// EasyJS 格式或 URI 解码错误交由管理类记录和报告，不输出原始消息。
@property (nonatomic, copy) void (^invalidMessageHandler)(NSString *reason);
/// 与原项目一致，传递 EasyJS 解码后的完整 JSON 字符串，业务层负责解析 actionName 和 parameters。
@property (nonatomic, copy) void (^JSCallNativeBlock)(NSString *object);

/// 原项目同名入口；仅转交经过来源和类型校验的 JSON 字符串，不执行业务动作。
- (void)JSCallNative:(NSString *)object;

@end
