// 按宿主、环境、身份和书籍隔离断点；只保存标识和位置，不保存音源 URL、凭证或购买权益。
#import <Foundation/Foundation.h>

@interface XYBookAudioCheckpointStore : NSObject

/// 创建存储命名空间。
/// @param host 宿主标识，通常取自 SDK 配置的 `hostIdentifier`。
/// @param environment 业务环境，参与断点隔离。
- (instancetype)initWithHost:(NSString *)host environment:(NSString *)environment;

/// 读取指定账号和书籍的断点。
/// @param book 书籍标识。
/// @param identity 保存时对应的账号标识，游客使用空字符串。
/// @param error 可选的读取错误输出地址。没有断点记录时不写错误。
/// @return 书籍、章节和位置字典，没有记录或读取失败时返回 nil。
- (NSDictionary *)readBook:(NSString *)book identity:(NSString *)identity error:(NSError **)error;

/// 原子替换指定账号和书籍的断点记录。
/// @param book 书籍标识。
/// @param chapter 当前章节标识。
/// @param position 当前章节内的播放位置，单位为毫秒。
/// @param identity 队列装载时的账号标识，游客使用空字符串。
/// @param error 可选的写入错误输出地址。
/// @return 写入成功时返回 YES。
- (BOOL)saveBook:(NSString *)book
         chapter:(NSString *)chapter
        position:(double)position
        identity:(NSString *)identity
           error:(NSError **)error;

@end
