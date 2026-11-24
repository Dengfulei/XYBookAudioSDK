// 消息字段和协议值与 H5 及原生调用方约定一致。
#import "XYBookAudioMessageProtocol.h"
#import "XYBookAudioTypes.h"
#import <math.h>

#pragma mark - 消息结构

NSString *const XYBookAudioKeyActionName = @"actionName";
NSString *const XYBookAudioKeyCallbackActionName = @"callbackActionName";
NSString *const XYBookAudioKeyParameters = @"parameters";
NSString *const XYBookAudioKeyData = @"data";
NSString *const XYBookAudioKeyCode = @"code";
NSString *const XYBookAudioKeyMessage = @"message";
NSString *const XYBookAudioKeyName = @"name";
NSString *const XYBookAudioKeyURL = @"url";
NSString *const XYBookAudioKeyReason = @"reason";

#pragma mark - 队列与播放快照

NSString *const XYBookAudioKeyBookID = @"bookId";
NSString *const XYBookAudioKeyTitle = @"title";
NSString *const XYBookAudioKeyChapters = @"chapters";
NSString *const XYBookAudioKeyChapterID = @"chapterId";
NSString *const XYBookAudioKeyChapterTitle = @"chapterTitle";
NSString *const XYBookAudioKeyChapterIndex = @"chapterIndex";
NSString *const XYBookAudioKeyChapterCount = @"chapterCount";
NSString *const XYBookAudioKeyCoverURL = @"coverURL";
NSString *const XYBookAudioKeyAudioURL = @"audioURL";
NSString *const XYBookAudioKeyRequiresLogin = @"requiresLogin";
NSString *const XYBookAudioKeyItems = @"items";
NSString *const XYBookAudioKeyIndex = @"index";
NSString *const XYBookAudioKeyQueueVersion = @"queueVersion";
NSString *const XYBookAudioKeyState = @"state";
NSString *const XYBookAudioKeyPlaying = @"playing";
NSString *const XYBookAudioKeyPlayWhenReady = @"playWhenReady";
NSString *const XYBookAudioKeyPositionMs = @"positionMs";
NSString *const XYBookAudioKeyDurationMs = @"durationMs";
NSString *const XYBookAudioKeyRate = @"rate";

#pragma mark - 定时字段

NSString *const XYBookAudioKeySleepTimer = @"sleepTimer";
NSString *const XYBookAudioKeyTimer = @"timer";
NSString *const XYBookAudioKeyMode = @"mode";
NSString *const XYBookAudioKeyCount = @"count";
NSString *const XYBookAudioKeyTargetCount = @"targetCount";
NSString *const XYBookAudioKeyRemainingCount = @"remainingCount";
NSString *const XYBookAudioKeyRemainingMs = @"remainingMs";
NSString *const XYBookAudioKeyEstimatedRemainingMs = @"estimatedRemainingMs";
NSString *const XYBookAudioKeyDeadlineElapsedMs = @"deadlineElapsedMs";

#pragma mark - 宿主资料、分享与能力字段

NSString *const XYBookAudioKeyStatus = @"status";
NSString *const XYBookAudioKeyIdentity = @"identity";
NSString *const XYBookAudioKeyIsLoggedIn = @"isLoggedIn";
NSString *const XYBookAudioKeyUserID = @"userId";
NSString *const XYBookAudioKeyGoLogin = @"goLogin";
NSString *const XYBookAudioKeyUseTicket = @"useTicket";
NSString *const XYBookAudioKeyLink = @"link";
NSString *const XYBookAudioKeyDescription = @"desc";
NSString *const XYBookAudioKeyImageURL = @"imgUrl";
NSString *const XYBookAudioKeyActions = @"actions";
NSString *const XYBookAudioKeyRates = @"rates";
NSString *const XYBookAudioKeySleepModes = @"sleepModes";

#pragma mark - 原生播放状态

NSString *const XYBookAudioValueIdle = @"idle";
NSString *const XYBookAudioValueReady = @"ready";
NSString *const XYBookAudioValueBuffering = @"buffering";
NSString *const XYBookAudioValuePlaying = @"playing";
NSString *const XYBookAudioValuePaused = @"paused";
NSString *const XYBookAudioValueBlocked = @"blocked";
NSString *const XYBookAudioValueCompleted = @"completed";
NSString *const XYBookAudioValueStopped = @"stopped";
NSString *const XYBookAudioValueFailed = @"failed";

#pragma mark - 原生定时模式与播放原因

NSString *const XYBookAudioValueOff = @"off";
NSString *const XYBookAudioValueDuration = @"duration";
NSString *const XYBookAudioValueTrackCount = @"trackCount";
NSString *const XYBookAudioValueSleepDuration = @"sleepDuration";
NSString *const XYBookAudioValueSleepTrackCount = @"sleepTrackCount";
NSString *const XYBookAudioValueQueueEnded = @"queueEnded";
NSString *const XYBookAudioValueHostTakeover = @"hostTakeover";

#pragma mark - SNCK 定时模式

NSString *const XYBookAudioSnckTimerModeOff = @"OFF";
NSString *const XYBookAudioSnckTimerModeAfterItems = @"AFTER_ITEMS";
NSString *const XYBookAudioSnckTimerModeAfterDuration = @"AFTER_DURATION";

#pragma mark - 宿主回执状态

NSString *const XYBookAudioValueLoggedIn = @"loggedIn";
NSString *const XYBookAudioValueCancelled = @"cancelled";
NSString *const XYBookAudioValueAccepted = @"accepted";
NSString *const XYBookAudioValueUnsupported = @"unsupported";

#pragma mark - 播放命令

NSString *const XYBookAudioCommandSetQueue = @"SetQueue";
NSString *const XYBookAudioCommandGetQueue = @"GetQueue";
NSString *const XYBookAudioCommandPlay = @"Play";
NSString *const XYBookAudioCommandPlayAt = @"PlayAt";
NSString *const XYBookAudioCommandPause = @"Pause";
NSString *const XYBookAudioCommandStop = @"Stop";
NSString *const XYBookAudioCommandSeekTo = @"SeekTo";
NSString *const XYBookAudioCommandPrevious = @"Previous";
NSString *const XYBookAudioCommandNext = @"Next";
NSString *const XYBookAudioCommandSelectChapter = @"SelectChapter";
NSString *const XYBookAudioCommandSetRate = @"SetRate";
NSString *const XYBookAudioCommandSetSleepTimer = @"SetSleepTimer";
NSString *const XYBookAudioCommandCancelSleepTimer = @"CancelSleepTimer";
NSString *const XYBookAudioCommandToggle = @"Toggle";
NSString *const XYBookAudioCommandGetState = @"GetState";
NSString *const XYBookAudioCommandSetTimer = @"SetTimer";
NSString *const XYBookAudioCommandGetTimer = @"GetTimer";

#pragma mark - 旧版 H5 动作

NSString *const XYBookAudioActionCanIUse = @"xhCanIUse";
NSString *const XYBookAudioActionOpenWindow = @"xhOpenWindow";
NSString *const XYBookAudioActionCloseWindow = @"xhCloseWindow";
NSString *const XYBookAudioActionGoLogin = @"xhGoLogin";
NSString *const XYBookAudioActionGetSystemInfo = @"xhGetSystemInfo";
NSString *const XYBookAudioActionShowShareMenu = @"xhShowShareMenu";

#pragma mark - SNCK 宿主资料动作

NSString *const XYBookAudioActionSnckGetUserInfo = @"xhSnckGetUserInfo";

#pragma mark - 原生 SDK 事件

NSString *const XYBookAudioEventPlaybackChanged = @"onBookAudioPlaybackChange";
NSString *const XYBookAudioEventError = @"onBookAudioError";
NSString *const XYBookAudioEventUserIdentityChanged = @"onBookAudioUserIdentityChange";

#pragma mark - 播放能力

const NSTimeInterval XYBookAudioProgressInterval = 1;

NSArray<NSNumber *> *XYBookAudioSupportedPlaybackRates(void) {
    return @[ @0.75, @1, @1.25, @1.5, @1.75, @2 ];
}

#pragma mark - 输入校验

BOOL XYBookAudioIsNumberInRange(id value, double minimum, double maximum, BOOL requiresInteger) {
    if (![value isKindOfClass:NSNumber.class] || CFGetTypeID((__bridge CFTypeRef)value) == CFBooleanGetTypeID()) {
        return NO;
    }
    double number = [value doubleValue];
    return isfinite(number) && number >= minimum && number <= maximum && (!requiresInteger || floor(number) == number);
}

BOOL XYBookAudioIsNonEmptyString(id value) {
    return [value isKindOfClass:NSString.class] && [value length] > 0;
}

BOOL XYBookAudioIsHTTPSURLString(id value) {
    if (!XYBookAudioIsNonEmptyString(value)) {
        return NO;
    }
    NSURL *URL = [NSURL URLWithString:value];
    return [URL.scheme.lowercaseString isEqualToString:@"https"] && URL.host.length && !URL.user && !URL.password;
}

NSURL *XYBookAudioParseSnckURL(id value) {
    if (!XYBookAudioIsNonEmptyString(value) || [value length] > 8192 ||
        [value rangeOfCharacterFromSet:NSCharacterSet.whitespaceAndNewlineCharacterSet].location != NSNotFound) {
        return nil;
    }
    NSURL *URL = [NSURL URLWithString:value];
    NSString *scheme = URL.scheme.lowercaseString;
    return ([scheme isEqual:@"https"] || [scheme isEqual:@"http"]) && URL.host.length && !URL.user && !URL.password
               ? URL
               : nil;
}

#pragma mark - SNCK 错误

static NSErrorDomain const XYBookAudioSnckErrorDomain = @"com.xinhuamm.bookaudio.snck";

NSError *XYBookAudioMakeSnckError(NSInteger code, NSString *message) {
    return [NSError errorWithDomain:XYBookAudioSnckErrorDomain code:code
                           userInfo:@{NSLocalizedDescriptionKey : message}];
}

NSDictionary *XYBookAudioMakeSnckErrorPayload(NSError *error) {
    NSInteger code = -4;
    if ([error.domain isEqual:XYBookAudioSnckErrorDomain]) {
        code = error.code;
    } else if ([error.domain isEqual:NSURLErrorDomain] && error.code == NSURLErrorTimedOut) {
        code = 4105;
    } else if ([error.domain isEqual:NSURLErrorDomain] && error.code == NSURLErrorCancelled) {
        code = 4106;
    } else if ([error.domain isEqual:XYBookAudioErrorDomain]) {
        switch (error.code) {
            case XYBookAudioInvalidArgument:
            case XYBookAudioInvalidState:
                code = 4101;
                break;
            case XYBookAudioUntrustedSource:
                code = 4103;
                break;
            case XYBookAudioBusy:
            case XYBookAudioHostFailed:
                code = 4104;
                break;
            case XYBookAudioDisposed:
                code = 4106;
                break;
            case XYBookAudioUnsupported:
                code = 4107;
                break;
            case XYBookAudioPlaybackFailed:
            case XYBookAudioSourceNotReady:
                code = 4108;
                break;
        }
    }
    return @{XYBookAudioKeyCode : @(code), XYBookAudioKeyMessage : error.localizedDescription};
}
