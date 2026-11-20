// 将 H5 队列原子映射为章节模型；这里只校验数据结构，登录与来源权限由播放会话判断。
#import "XYBookAudioQueue.h"
#import "XYBookAudioMessageProtocol.h"

@implementation XYBookAudioQueue

+ (instancetype)queueWithSnckParameters:(NSDictionary *)parameters error:(NSError **)error {
    NSArray *items = parameters[XYBookAudioKeyItems];
    if (![items isKindOfClass:NSArray.class] || items.count < 1 || items.count > 200) {
        if (error) {
            *error = XYBookAudioError(XYBookAudioInvalidArgument, @"items must contain 1–200 audio items.");
        }
        return nil;
    }
    NSMutableArray<NSDictionary *> *normalizedItems = [NSMutableArray arrayWithCapacity:items.count];
    NSMutableArray<XYBookAudioChapter *> *chapters = [NSMutableArray arrayWithCapacity:items.count];
    NSMutableSet<NSString *> *identifiers = [NSMutableSet setWithCapacity:items.count];
    for (id value in items) {
        NSDictionary *item = [value isKindOfClass:NSDictionary.class] ? value : @{};
        NSString *identifier = item[@"id"];
        NSString *title = item[@"title"];
        NSString *url = item[@"url"];
        NSString *cover = item[@"coverUrl"];
        NSString *author = item[@"author"];
        NSString *mimeType = item[@"mimeType"];
        BOOL validTitle =
            XYBookAudioIsNonEmptyString(title) &&
            [title stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet].length;
        BOOL validCover =
            !cover || ([cover isKindOfClass:NSString.class] && (!cover.length || XYBookAudioParseSnckURL(cover)));
        if (!XYBookAudioIsNonEmptyString(identifier) || [identifiers containsObject:identifier] || !validTitle ||
            !XYBookAudioParseSnckURL(url) || !validCover || (author && ![author isKindOfClass:NSString.class]) ||
            (mimeType && ![mimeType isKindOfClass:NSString.class])) {
            if (error) {
                *error = XYBookAudioError(XYBookAudioInvalidArgument, @"Invalid or duplicate audio item.");
            }
            return nil;
        }
        [identifiers addObject:identifier];
        NSMutableDictionary *entry = [@{@"id" : identifier, @"title" : title, @"url" : url} mutableCopy];
        entry[@"coverUrl"] = cover;
        entry[@"author"] = author;
        entry[@"mimeType"] = mimeType;
        [normalizedItems addObject:[entry copy]];
        XYBookAudioChapter *chapter = [XYBookAudioChapter new];
        chapter.chapterId = identifier;
        chapter.title = title;
        chapter.audioURL = url;
        [chapters addObject:chapter];
    }
    NSNumber *startIndex = parameters[@"startIndex"] ?: @0;
    NSNumber *autoPlay = parameters[@"autoPlay"] ?: @NO;
    BOOL validOptions = XYBookAudioIsNumberInRange(startIndex, 0, chapters.count - 1, YES) &&
                        CFGetTypeID((__bridge CFTypeRef)autoPlay) == CFBooleanGetTypeID();
    NSDictionary *queueParameters =
        @{XYBookAudioKeyItems : normalizedItems, @"startIndex" : startIndex, @"autoPlay" : autoPlay};
    NSData *encodedQueue = validOptions ? [NSJSONSerialization dataWithJSONObject:queueParameters
                                                                          options:NSJSONWritingWithoutEscapingSlashes
                                                                            error:nil]
                                        : nil;
    if (!encodedQueue || encodedQueue.length > 60 * 1024) {
        if (error) {
            *error = XYBookAudioError(XYBookAudioInvalidArgument, @"Invalid startIndex, autoPlay or queue size.");
        }
        return nil;
    }
    XYBookAudioQueue *queue = [self new];
    queue->_bookId = @"SNCK";
    queue->_title = chapters[startIndex.unsignedIntegerValue].title;
    queue->_chapters = [chapters copy];
    queue->_snckItems = [normalizedItems copy];
    return queue;
}

+ (BOOL)validChapter:(id)value {
    if (![value isKindOfClass:NSDictionary.class]) {
        return NO;
    }
    NSDictionary *chapter = value;
    if (!XYBookAudioIsNonEmptyString(chapter[XYBookAudioKeyChapterID]) ||
        !XYBookAudioIsNonEmptyString(chapter[XYBookAudioKeyTitle])) {
        return NO;
    }
    id requiresLogin = chapter[XYBookAudioKeyRequiresLogin];
    if (!requiresLogin || CFGetTypeID((__bridge CFTypeRef)requiresLogin) != CFBooleanGetTypeID()) {
        return NO;
    }
    if (chapter[XYBookAudioKeyAudioURL] && ![self validSource:chapter[XYBookAudioKeyAudioURL]]) {
        return NO;
    }
    return !chapter[XYBookAudioKeyDurationMs] ||
           XYBookAudioIsNumberInRange(chapter[XYBookAudioKeyDurationMs], 1, DBL_MAX, NO);
}

/// 此处只校验音源格式；替换会话前还必须按配置检查本地目录边界和当前身份。
+ (BOOL)validSource:(id)value {
    if (XYBookAudioIsHTTPSURLString(value)) {
        return YES;
    }
    return XYBookAudioIsNonEmptyString(value) && [NSURL URLWithString:value].isFileURL;
}

+ (instancetype)queueWithParameters:(NSDictionary *)parameters error:(NSError **)error {
    NSArray *chapters = parameters[XYBookAudioKeyChapters];
    BOOL valid = XYBookAudioIsNonEmptyString(parameters[XYBookAudioKeyBookID]) &&
                 XYBookAudioIsNonEmptyString(parameters[XYBookAudioKeyTitle]) &&
                 [chapters isKindOfClass:NSArray.class] && chapters.count > 0;
    if (parameters[XYBookAudioKeyCoverURL] && !XYBookAudioIsHTTPSURLString(parameters[XYBookAudioKeyCoverURL])) {
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
    NSMutableArray<XYBookAudioChapter *> *models = [NSMutableArray arrayWithCapacity:chapters.count];
    for (NSDictionary *entry in chapters) {
        if (![self validChapter:entry] || [identifiers containsObject:entry[XYBookAudioKeyChapterID]]) {
            if (error) {
                *error = XYBookAudioError(XYBookAudioInvalidArgument,
                                          @"Invalid or duplicate chapter; requiresLogin must be a JSON boolean.");
            }
            return nil;
        }
        XYBookAudioChapter *chapter = [XYBookAudioChapter new];
        chapter.chapterId = entry[XYBookAudioKeyChapterID];
        chapter.title = entry[XYBookAudioKeyTitle];
        chapter.requiresLogin = [entry[XYBookAudioKeyRequiresLogin] boolValue];
        chapter.audioURL = entry[XYBookAudioKeyAudioURL];
        chapter.durationMs = entry[XYBookAudioKeyDurationMs];
        [identifiers addObject:chapter.chapterId];
        [models addObject:chapter];
    }
    XYBookAudioQueue *queue = [self new];
    queue->_bookId = [parameters[XYBookAudioKeyBookID] copy];
    queue->_title = [parameters[XYBookAudioKeyTitle] copy];
    queue->_coverURL = [parameters[XYBookAudioKeyCoverURL] copy];
    queue->_chapters = [models copy];
    return queue;
}

@end
