// 集中定义已确认的交互字段与动作；数值校验明确排除 NSNumber 布尔值，避免计数和位置误判。
#import "XYBookAudioMessageProtocol.h"
#import <math.h>
NSTimeInterval const XYBookAudioProgressInterval = 1;
NSTimeInterval const XYBookAudioCheckpointInterval = 5;
NSString *const XYBookAudioPlaybackEvent = @"onBookAudioPlaybackChange";
NSString *const XYBookAudioErrorEvent = @"onBookAudioError";
NSString *const XYBookAudioIdentityEvent = @"onBookAudioUserIdentityChange";

NSArray<NSNumber *> *XYBookAudioRates(void) {
    return @[ @0.75, @1, @1.25, @1.5, @1.75, @2 ];
}

BOOL XYBookAudioNumber(id value, double minimum, double maximum, BOOL integer) {
    if (![value isKindOfClass:NSNumber.class] || CFGetTypeID((__bridge CFTypeRef)value) == CFBooleanGetTypeID()) {
        return NO;
    }
    double number = [value doubleValue];
    return isfinite(number) && number >= minimum && number <= maximum && (!integer || floor(number) == number);
}

BOOL XYBookAudioString(id value) {
    return [value isKindOfClass:NSString.class] && [value length] > 0;
}

BOOL XYBookAudioHTTPS(id value) {
    if (!XYBookAudioString(value)) {
        return NO;
    }
    NSURL *URL = [NSURL URLWithString:value];
    return [URL.scheme.lowercaseString isEqualToString:@"https"] && URL.host.length && !URL.user && !URL.password;
}

NSURL *XYBookAudioSnckURL(id value) {
    if (!XYBookAudioString(value) || [value length] > 8192 ||
        [value rangeOfCharacterFromSet:NSCharacterSet.whitespaceAndNewlineCharacterSet].location != NSNotFound) {
        return nil;
    }
    NSURL *URL = [NSURL URLWithString:value];
    NSString *scheme = URL.scheme.lowercaseString;
    return ([scheme isEqual:@"https"] || [scheme isEqual:@"http"]) && URL.host.length && !URL.user && !URL.password
               ? URL
               : nil;
}

static NSErrorDomain const XYBookAudioSnckErrorDomain = @"com.xinhuamm.bookaudio.snck";

NSError *XYBookAudioSnckError(NSInteger code, NSString *message) {
    return [NSError errorWithDomain:XYBookAudioSnckErrorDomain code:code
                           userInfo:@{NSLocalizedDescriptionKey : message}];
}

NSDictionary *XYBookAudioSnckErrorPayload(NSError *error) {
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
    return @{@"code" : @(code), @"message" : error.localizedDescription};
}

NSString *const XYBookAudioKeyActionName = @"actionName";
NSString *const XYBookAudioKeyParameters = @"parameters";
NSString *const XYBookAudioKeyCallbackActionName = @"callbackActionName";
NSString *const XYBookAudioKeyData = @"data";
NSString *const XYBookAudioKeyCode = @"code";
NSString *const XYBookAudioKeyMessage = @"message";
NSString *const XYBookAudioKeyName = @"name";
NSString *const XYBookAudioKeyBookId = @"bookId";
NSString *const XYBookAudioKeyTitle = @"title";
NSString *const XYBookAudioKeyChapters = @"chapters";
NSString *const XYBookAudioKeyChapterId = @"chapterId";
NSString *const XYBookAudioKeyChapterTitle = @"chapterTitle";
NSString *const XYBookAudioKeyChapterIndex = @"chapterIndex";
NSString *const XYBookAudioKeyChapterCount = @"chapterCount";
NSString *const XYBookAudioKeyCoverURL = @"coverURL";
NSString *const XYBookAudioKeyAudioURL = @"audioURL";
NSString *const XYBookAudioKeyRequiresLogin = @"requiresLogin";
NSString *const XYBookAudioKeyDurationMs = @"durationMs";
NSString *const XYBookAudioKeyPositionMs = @"positionMs";
NSString *const XYBookAudioKeyRate = @"rate";
NSString *const XYBookAudioKeyState = @"state";
NSString *const XYBookAudioKeySleepTimer = @"sleepTimer";
NSString *const XYBookAudioKeyMode = @"mode";
NSString *const XYBookAudioKeyCount = @"count";
NSString *const XYBookAudioKeyRemainingMs = @"remainingMs";
NSString *const XYBookAudioKeyTargetCount = @"targetCount";
NSString *const XYBookAudioKeyRemainingCount = @"remainingCount";
NSString *const XYBookAudioKeyEstimatedRemainingMs = @"estimatedRemainingMs";
NSString *const XYBookAudioKeyIsLoggedIn = @"isLoggedIn";
NSString *const XYBookAudioKeyUserId = @"userId";
NSString *const XYBookAudioKeyStatus = @"status";
NSString *const XYBookAudioKeyIdentity = @"identity";
NSString *const XYBookAudioKeyLink = @"link";
NSString *const XYBookAudioKeyDesc = @"desc";
NSString *const XYBookAudioKeyImageURL = @"imgUrl";
NSString *const XYBookAudioKeySubscribed = @"subscribed";
NSString *const XYBookAudioKeyActions = @"actions";
NSString *const XYBookAudioKeyRates = @"rates";
NSString *const XYBookAudioKeySleepModes = @"sleepModes";
NSString *const XYBookAudioKeyReason = @"reason";
NSString *const XYBookAudioValueIdle = @"idle";
NSString *const XYBookAudioValueReady = @"ready";
NSString *const XYBookAudioValueBuffering = @"buffering";
NSString *const XYBookAudioValuePlaying = @"playing";
NSString *const XYBookAudioValuePaused = @"paused";
NSString *const XYBookAudioValueBlocked = @"blocked";
NSString *const XYBookAudioValueCompleted = @"completed";
NSString *const XYBookAudioValueStopped = @"stopped";
NSString *const XYBookAudioValueFailed = @"failed";
NSString *const XYBookAudioValueOff = @"off";
NSString *const XYBookAudioValueDuration = @"duration";
NSString *const XYBookAudioValueTrackCount = @"trackCount";
NSString *const XYBookAudioValueSleepDuration = @"sleepDuration";
NSString *const XYBookAudioValueSleepTrackCount = @"sleepTrackCount";
NSString *const XYBookAudioValueQueueEnded = @"queueEnded";
NSString *const XYBookAudioValueHostTakeover = @"hostTakeover";
NSString *const XYBookAudioValueLoggedIn = @"loggedIn";
NSString *const XYBookAudioValueCancelled = @"cancelled";
NSString *const XYBookAudioValueAccepted = @"accepted";
NSString *const XYBookAudioValueUnsupported = @"unsupported";
NSString *const XYBookAudioCommandGetCapabilities = @"GetCapabilities";
NSString *const XYBookAudioCommandGetSnapshot = @"GetSnapshot";
NSString *const XYBookAudioCommandSubscribe = @"Subscribe";
NSString *const XYBookAudioCommandUnsubscribe = @"Unsubscribe";
NSString *const XYBookAudioCommandSetQueue = @"SetQueue";
NSString *const XYBookAudioCommandPlay = @"Play";
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
NSString *const XYBookAudioPlaybackActionPrefix = @"xhBookAudio";
NSString *const XYBookAudioActionCanIUse = @"xhCanIUse";
NSString *const XYBookAudioActionOpenWindow = @"xhOpenWindow";
NSString *const XYBookAudioActionCloseWindow = @"xhCloseWindow";
NSString *const XYBookAudioActionGoLogin = @"xhGoLogin";
NSString *const XYBookAudioKeyURL = @"url";
NSString *const XYBookAudioActionSubscribe = @"xhBookAudioSubscribe";
NSString *const XYBookAudioActionUnsubscribe = @"xhBookAudioUnsubscribe";

NSString *const XYBookAudioActionGetSystemInfo = @"xhGetSystemInfo";
NSString *const XYBookAudioActionGetUserInfo = @"xhGetUserInfo";
NSString *const XYBookAudioActionShowShareMenu = @"xhShowShareMenu";
NSString *const XYBookAudioKeyGoLogin = @"goLogin";
NSString *const XYBookAudioKeyUseTicket = @"useTicket";

NSString *const XYBookAudioActionSetQueue = @"xhBookAudioSetQueue";
NSString *const XYBookAudioActionPlay = @"xhBookAudioPlay";
NSString *const XYBookAudioActionPause = @"xhBookAudioPause";
NSString *const XYBookAudioActionStop = @"xhBookAudioStop";
NSString *const XYBookAudioActionSeekTo = @"xhBookAudioSeekTo";
NSString *const XYBookAudioActionPrevious = @"xhBookAudioPrevious";
NSString *const XYBookAudioActionNext = @"xhBookAudioNext";
NSString *const XYBookAudioActionSelectChapter = @"xhBookAudioSelectChapter";
NSString *const XYBookAudioActionSetRate = @"xhBookAudioSetRate";
NSString *const XYBookAudioActionSetSleepTimer = @"xhBookAudioSetSleepTimer";
NSString *const XYBookAudioActionCancelSleepTimer = @"xhBookAudioCancelSleepTimer";
