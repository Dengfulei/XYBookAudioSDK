// 通过原子 JSON 文件持久化断点；目录名使用摘要隔离业务标识，资源地址和临时授权不得落盘。
#import "XYBookAudioCheckpointStore.h"
#import "XYBookAudioMessageProtocol.h"
#import <CommonCrypto/CommonDigest.h>
#import <stdio.h>

static NSString *XYBookAudioStorageKey(NSString *value) {
    NSData *data = [value dataUsingEncoding:NSUTF8StringEncoding];
    unsigned char digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(data.bytes, (CC_LONG)data.length, digest);
    NSMutableString *result = [NSMutableString string];
    for (NSUInteger index = 0; index < sizeof(digest); index++) {
        [result appendFormat:@"%02x", digest[index]];
    }
    return result;
}

@interface XYBookAudioCheckpointStore ()

@property (nonatomic, strong) NSURL *root;

@end

@implementation XYBookAudioCheckpointStore

/// 用宿主标识和环境形成独立目录；摘要用于命名隔离，不是对断点内容的加密。
- (instancetype)initWithHost:(NSString *)host environment:(NSString *)environment {
    if ((self = [super init])) {
        NSURL *support = [NSFileManager.defaultManager URLsForDirectory:NSApplicationSupportDirectory
                                                              inDomains:NSUserDomainMask]
                             .firstObject;
        NSData *namespace = [NSJSONSerialization dataWithJSONObject:@[ host, environment ] options:0 error:nil];
        NSString *key = XYBookAudioStorageKey([namespace base64EncodedStringWithOptions:0]);
        _root = [[support URLByAppendingPathComponent:@"XYBookAudioSDK/v1"
                                          isDirectory:YES] URLByAppendingPathComponent:key isDirectory:YES];
    }
    return self;
}

- (NSURL *)fileForBook:(NSString *)book identity:(NSString *)identity {
    return [[self.root URLByAppendingPathComponent:XYBookAudioStorageKey(identity) isDirectory:YES]
        URLByAppendingPathComponent:[XYBookAudioStorageKey(book) stringByAppendingPathExtension:@"json"]];
}

/// 无断点返回 nil；存储读取错误仍保留诊断，损坏的内容移到同目录下固定的 .corrupt 文件。
- (NSDictionary *)readBook:(NSString *)book identity:(NSString *)identity error:(NSError **)error {
    NSURL *file = [self fileForBook:book identity:identity];
    NSError *readError = nil;
    NSData *data = [NSData dataWithContentsOfURL:file options:0 error:&readError];
    if (!data) {
        BOOL missing = [readError.domain isEqualToString:NSCocoaErrorDomain] &&
                       (readError.code == NSFileReadNoSuchFileError || readError.code == NSFileNoSuchFileError);
        if (!missing && error) {
            *error = readError;
        }
        return nil;
    }
    id result = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    if ([result isKindOfClass:NSDictionary.class] && [result[XYBookAudioKeyBookId] isEqual:book] &&
        XYBookAudioString(result[XYBookAudioKeyChapterId]) &&
        XYBookAudioNumber(result[XYBookAudioKeyPositionMs], 0, DBL_MAX, NO)) {
        return result;
    }
    NSURL *quarantine = [file URLByAppendingPathExtension:@"corrupt"];
    // POSIX rename 原子替换上一个坏副本，同一个断点最多保留一个坏文件。
    BOOL isolated = rename(file.fileSystemRepresentation, quarantine.fileSystemRepresentation) == 0;
    if (error) {
        *error =
            XYBookAudioError(XYBookAudioStorageFailed, isolated ? @"The invalid checkpoint was isolated."
                                                                : @"The invalid checkpoint could not be isolated.");
    }
    return nil;
}

/// 仅持久化书籍、章节标识和毫秒位置；原子替换文件，失败原样返回以便会话上报。
- (BOOL)saveBook:(NSString *)book
         chapter:(NSString *)chapter
        position:(double)position
        identity:(NSString *)identity
           error:(NSError **)error {
    NSURL *file = [self fileForBook:book identity:identity];
    if (![NSFileManager.defaultManager createDirectoryAtURL:file.URLByDeletingLastPathComponent
                                withIntermediateDirectories:YES
                                                 attributes:nil
                                                      error:error]) {
        return NO;
    }
    NSData *data = [NSJSONSerialization dataWithJSONObject:@{
        XYBookAudioKeyBookId : book,
        XYBookAudioKeyChapterId : chapter,
        XYBookAudioKeyPositionMs : @(position)
    }
                                                   options:0
                                                     error:error];
    return data && [data writeToURL:file options:NSDataWritingAtomic error:error];
}

@end
