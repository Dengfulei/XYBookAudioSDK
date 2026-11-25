// 校验并构建播放队列，只有整个队列合法时才允许替换现有状态。
#import "XYBookAudioTypes.h"

@interface XYBookAudioQueue : NSObject

@property (nonatomic, copy, readonly) NSString *bookId;
@property (nonatomic, copy, readonly) NSString *title;
@property (nonatomic, copy, readonly) NSString *coverURL;
@property (nonatomic, copy, readonly) NSArray<XYBookAudioChapter *> *chapters;
@property (nonatomic, copy, readonly) NSArray<NSDictionary *> *snckItems;

/// 校验并构建原生播放队列。
/// @param parameters 必填 `bookId`、`title` 和非空 `chapters`，可含 `coverURL`。
/// @param error 可选的参数错误输出地址。
/// @return 完整合法的队列，校验失败时返回 nil。
+ (instancetype)queueWithParameters:(NSDictionary *)parameters error:(NSError **)error;

/// 校验并构建 SNCK v1 播放队列。
/// @param parameters 包含 `items`，并可指定零基的 `startIndex` 与布尔值 `autoPlay`。
/// @param error 可选的参数错误输出地址。
/// @return 完整合法的队列，校验失败时返回 nil。
+ (instancetype)queueWithSnckParameters:(NSDictionary *)parameters error:(NSError **)error;

@end
