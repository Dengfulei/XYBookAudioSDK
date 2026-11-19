// 将 H5 队列原子映射为章节模型；这里只校验数据结构，登录与来源权限由播放会话判断。
#import "XYBookAudioQueue.h"
#import "XYBookAudioMessageProtocol.h"
#import <YYModel/YYModel.h>

@implementation XYBookAudioQueue

+ (BOOL)validChapter:(id)value {
    if (![value isKindOfClass:NSDictionary.class]) {
        return NO;
    }
    NSDictionary *chapter = value;
    if (!XYBookAudioString(chapter[XYBookAudioKeyChapterId]) || !XYBookAudioString(chapter[XYBookAudioKeyTitle])) {
        return NO;
    }
    id requiresLogin = chapter[XYBookAudioKeyRequiresLogin];
    if (!requiresLogin || CFGetTypeID((__bridge CFTypeRef)requiresLogin) != CFBooleanGetTypeID()) {
        return NO;
    }
    if (chapter[XYBookAudioKeyAudioURL] && ![self validSource:chapter[XYBookAudioKeyAudioURL]]) {
        return NO;
    }
    return !chapter[XYBookAudioKeyDurationMs] || XYBookAudioNumber(chapter[XYBookAudioKeyDurationMs], 1, DBL_MAX, NO);
}

/// 此处只校验音源格式；替换会话前还必须按配置检查本地目录边界和当前身份。
+ (BOOL)validSource:(id)value {
    if (XYBookAudioHTTPS(value)) {
        return YES;
    }
    return XYBookAudioString(value) && [NSURL URLWithString:value].isFileURL;
}

+ (instancetype)queueWithParameters:(NSDictionary *)parameters error:(NSError **)error {
    NSArray *chapters = parameters[XYBookAudioKeyChapters];
    BOOL valid = XYBookAudioString(parameters[XYBookAudioKeyBookId]) &&
                 XYBookAudioString(parameters[XYBookAudioKeyTitle]) && [chapters isKindOfClass:NSArray.class] &&
                 chapters.count > 0;
    if (parameters[XYBookAudioKeyCoverURL] && !XYBookAudioHTTPS(parameters[XYBookAudioKeyCoverURL])) {
        valid = NO;
    }
    if (!valid) {
        if (error) {
            *error = XYBookAudioError(XYBookAudioInvalidArgument,
                                      @"bookId, title and a nonempty chapters array are required; URLs must be HTTPS.");
        }
        return nil;
    }
    NSMutableSet *identifiers = [NSMutableSet set];
    NSMutableArray *models = [NSMutableArray array];
    for (id chapter in chapters) {
        if (![self validChapter:chapter] || [identifiers containsObject:chapter[XYBookAudioKeyChapterId]]) {
            if (error) {
                *error = XYBookAudioError(XYBookAudioInvalidArgument,
                                          @"Invalid or duplicate chapter; requiresLogin must be a JSON boolean.");
            }
            return nil;
        }
        [identifiers addObject:chapter[XYBookAudioKeyChapterId]];
        [models addObject:[XYBookAudioChapter yy_modelWithDictionary:chapter]];
    }
    XYBookAudioQueue *queue = [self new];
    queue->_bookId = [parameters[XYBookAudioKeyBookId] copy];
    queue->_title = [parameters[XYBookAudioKeyTitle] copy];
    queue->_coverURL = [parameters[XYBookAudioKeyCoverURL] copy];
    queue->_chapters = [models copy];
    return queue;
}

@end
