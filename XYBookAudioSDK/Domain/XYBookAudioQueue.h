// 队列输入的校验边界；内部使用 YYModel 映射，只有整个队列合法时才允许替换现有状态。
#import "XYBookAudioTypes.h"

@interface XYBookAudioQueue : NSObject

@property (nonatomic, copy, readonly) NSString *bookId;
@property (nonatomic, copy, readonly) NSString *title;
@property (nonatomic, copy, readonly) NSString *coverURL;
@property (nonatomic, copy, readonly) NSArray<XYBookAudioChapter *> *chapters;

/// 完整校验成功才返回新队列；失败返回错误，调用方旧队列保持不变。
+ (instancetype)queueWithParameters:(NSDictionary *)parameters error:(NSError **)error;

@end
