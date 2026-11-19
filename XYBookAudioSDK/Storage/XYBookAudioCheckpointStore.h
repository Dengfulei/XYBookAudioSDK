// 按宿主、环境、身份和书籍隔离断点；只保存标识和位置，不保存音源 URL、凭证或购买权益。
#import <Foundation/Foundation.h>

@interface XYBookAudioCheckpointStore : NSObject

- (instancetype)initWithHost:(NSString *)host environment:(NSString *)environment;
- (NSDictionary *)readBook:(NSString *)book identity:(NSString *)identity error:(NSError **)error;
- (BOOL)saveBook:(NSString *)book
         chapter:(NSString *)chapter
        position:(double)position
        identity:(NSString *)identity
           error:(NSError **)error;

@end
