// SDK 内部共用的消息字段、协议值和输入校验。
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

#pragma mark - 消息结构

FOUNDATION_EXPORT NSString *const XYBookAudioKeyActionName;
FOUNDATION_EXPORT NSString *const XYBookAudioKeyCallbackActionName;
FOUNDATION_EXPORT NSString *const XYBookAudioKeyParameters;
FOUNDATION_EXPORT NSString *const XYBookAudioKeyData;
FOUNDATION_EXPORT NSString *const XYBookAudioKeyCode;
FOUNDATION_EXPORT NSString *const XYBookAudioKeyMessage;
FOUNDATION_EXPORT NSString *const XYBookAudioKeyName;
FOUNDATION_EXPORT NSString *const XYBookAudioKeyURL;
FOUNDATION_EXPORT NSString *const XYBookAudioKeyReason;

#pragma mark - 队列与播放快照

FOUNDATION_EXPORT NSString *const XYBookAudioKeyBookID;
FOUNDATION_EXPORT NSString *const XYBookAudioKeyTitle;
FOUNDATION_EXPORT NSString *const XYBookAudioKeyChapters;
FOUNDATION_EXPORT NSString *const XYBookAudioKeyChapterID;
FOUNDATION_EXPORT NSString *const XYBookAudioKeyChapterTitle;
FOUNDATION_EXPORT NSString *const XYBookAudioKeyChapterIndex;
FOUNDATION_EXPORT NSString *const XYBookAudioKeyChapterCount;
FOUNDATION_EXPORT NSString *const XYBookAudioKeyCoverURL;
FOUNDATION_EXPORT NSString *const XYBookAudioKeyAudioURL;
FOUNDATION_EXPORT NSString *const XYBookAudioKeyRequiresLogin;
FOUNDATION_EXPORT NSString *const XYBookAudioKeyItems;
FOUNDATION_EXPORT NSString *const XYBookAudioKeyIndex;
FOUNDATION_EXPORT NSString *const XYBookAudioKeyQueueVersion;
FOUNDATION_EXPORT NSString *const XYBookAudioKeyState;
FOUNDATION_EXPORT NSString *const XYBookAudioKeyPlaying;
FOUNDATION_EXPORT NSString *const XYBookAudioKeyPlayWhenReady;
FOUNDATION_EXPORT NSString *const XYBookAudioKeyPositionMs;
FOUNDATION_EXPORT NSString *const XYBookAudioKeyDurationMs;
FOUNDATION_EXPORT NSString *const XYBookAudioKeyRate;

#pragma mark - 定时字段

FOUNDATION_EXPORT NSString *const XYBookAudioKeySleepTimer;
FOUNDATION_EXPORT NSString *const XYBookAudioKeyTimer;
FOUNDATION_EXPORT NSString *const XYBookAudioKeyMode;
FOUNDATION_EXPORT NSString *const XYBookAudioKeyCount;
FOUNDATION_EXPORT NSString *const XYBookAudioKeyTargetCount;
FOUNDATION_EXPORT NSString *const XYBookAudioKeyRemainingCount;
FOUNDATION_EXPORT NSString *const XYBookAudioKeyRemainingMs;
FOUNDATION_EXPORT NSString *const XYBookAudioKeyEstimatedRemainingMs;
FOUNDATION_EXPORT NSString *const XYBookAudioKeyDeadlineElapsedMs;

#pragma mark - 宿主资料、分享与能力字段

FOUNDATION_EXPORT NSString *const XYBookAudioKeyStatus;
FOUNDATION_EXPORT NSString *const XYBookAudioKeyIdentity;
FOUNDATION_EXPORT NSString *const XYBookAudioKeyIsLoggedIn;
FOUNDATION_EXPORT NSString *const XYBookAudioKeyUserID;
FOUNDATION_EXPORT NSString *const XYBookAudioKeyGoLogin;
FOUNDATION_EXPORT NSString *const XYBookAudioKeyUseTicket;
FOUNDATION_EXPORT NSString *const XYBookAudioKeyLink;
FOUNDATION_EXPORT NSString *const XYBookAudioKeyDescription;
FOUNDATION_EXPORT NSString *const XYBookAudioKeyImageURL;
FOUNDATION_EXPORT NSString *const XYBookAudioKeyActions;
FOUNDATION_EXPORT NSString *const XYBookAudioKeyRates;
FOUNDATION_EXPORT NSString *const XYBookAudioKeySleepModes;

#pragma mark - 原生播放状态

FOUNDATION_EXPORT NSString *const XYBookAudioValueIdle;
FOUNDATION_EXPORT NSString *const XYBookAudioValueReady;
FOUNDATION_EXPORT NSString *const XYBookAudioValueBuffering;
FOUNDATION_EXPORT NSString *const XYBookAudioValuePlaying;
FOUNDATION_EXPORT NSString *const XYBookAudioValuePaused;
FOUNDATION_EXPORT NSString *const XYBookAudioValueBlocked;
FOUNDATION_EXPORT NSString *const XYBookAudioValueCompleted;
FOUNDATION_EXPORT NSString *const XYBookAudioValueStopped;
FOUNDATION_EXPORT NSString *const XYBookAudioValueFailed;

#pragma mark - 原生定时模式与播放原因

FOUNDATION_EXPORT NSString *const XYBookAudioValueOff;
FOUNDATION_EXPORT NSString *const XYBookAudioValueDuration;
FOUNDATION_EXPORT NSString *const XYBookAudioValueTrackCount;
FOUNDATION_EXPORT NSString *const XYBookAudioValueSleepDuration;
FOUNDATION_EXPORT NSString *const XYBookAudioValueSleepTrackCount;
FOUNDATION_EXPORT NSString *const XYBookAudioValueQueueEnded;
FOUNDATION_EXPORT NSString *const XYBookAudioValueHostTakeover;

#pragma mark - SNCK 定时模式

FOUNDATION_EXPORT NSString *const XYBookAudioSnckTimerModeOff;
FOUNDATION_EXPORT NSString *const XYBookAudioSnckTimerModeAfterItems;
FOUNDATION_EXPORT NSString *const XYBookAudioSnckTimerModeAfterDuration;

#pragma mark - 宿主回执状态

FOUNDATION_EXPORT NSString *const XYBookAudioValueLoggedIn;
FOUNDATION_EXPORT NSString *const XYBookAudioValueCancelled;
FOUNDATION_EXPORT NSString *const XYBookAudioValueAccepted;
FOUNDATION_EXPORT NSString *const XYBookAudioValueUnsupported;

#pragma mark - 播放命令

FOUNDATION_EXPORT NSString *const XYBookAudioCommandSetQueue;
FOUNDATION_EXPORT NSString *const XYBookAudioCommandGetQueue;
FOUNDATION_EXPORT NSString *const XYBookAudioCommandPlay;
FOUNDATION_EXPORT NSString *const XYBookAudioCommandPlayAt;
FOUNDATION_EXPORT NSString *const XYBookAudioCommandPause;
FOUNDATION_EXPORT NSString *const XYBookAudioCommandStop;
FOUNDATION_EXPORT NSString *const XYBookAudioCommandSeekTo;
FOUNDATION_EXPORT NSString *const XYBookAudioCommandPrevious;
FOUNDATION_EXPORT NSString *const XYBookAudioCommandNext;
FOUNDATION_EXPORT NSString *const XYBookAudioCommandSelectChapter;
FOUNDATION_EXPORT NSString *const XYBookAudioCommandSetRate;
FOUNDATION_EXPORT NSString *const XYBookAudioCommandSetSleepTimer;
FOUNDATION_EXPORT NSString *const XYBookAudioCommandCancelSleepTimer;
FOUNDATION_EXPORT NSString *const XYBookAudioCommandToggle;
FOUNDATION_EXPORT NSString *const XYBookAudioCommandGetState;
FOUNDATION_EXPORT NSString *const XYBookAudioCommandSetTimer;
FOUNDATION_EXPORT NSString *const XYBookAudioCommandGetTimer;

#pragma mark - 旧版 H5 动作

FOUNDATION_EXPORT NSString *const XYBookAudioActionCanIUse;
FOUNDATION_EXPORT NSString *const XYBookAudioActionOpenWindow;
FOUNDATION_EXPORT NSString *const XYBookAudioActionCloseWindow;
FOUNDATION_EXPORT NSString *const XYBookAudioActionGoLogin;
FOUNDATION_EXPORT NSString *const XYBookAudioActionGetSystemInfo;
FOUNDATION_EXPORT NSString *const XYBookAudioActionShowShareMenu;

#pragma mark - SNCK 宿主资料动作

FOUNDATION_EXPORT NSString *const XYBookAudioActionSnckGetUserInfo;

#pragma mark - 原生 SDK 事件

FOUNDATION_EXPORT NSString *const XYBookAudioEventPlaybackChanged;
FOUNDATION_EXPORT NSString *const XYBookAudioEventError;
FOUNDATION_EXPORT NSString *const XYBookAudioEventUserIdentityChanged;

#pragma mark - 定时变化与播放能力

typedef NS_ENUM(NSUInteger, XYBookAudioTimerChange) {
    XYBookAudioTimerChangeSet,
    XYBookAudioTimerChangeItemCompleted,
    XYBookAudioTimerChangeQueueEnded,
    XYBookAudioTimerChangeExpired
};

FOUNDATION_EXPORT const NSTimeInterval XYBookAudioProgressInterval;

/// @return 支持的播放倍速，按从低到高排列。
FOUNDATION_EXPORT NSArray<NSNumber *> *XYBookAudioSupportedPlaybackRates(void);

#pragma mark - 输入校验

/// 仅接受范围内的有限 NSNumber，布尔值始终无效。
/// @param value 待校验的输入值。
/// @param minimum 允许的最小值，包含边界。
/// @param maximum 允许的最大值，包含边界。
/// @param requiresInteger 为 YES 时要求输入没有小数部分。
/// @return 输入满足数值类型、范围及整数要求时返回 YES。
FOUNDATION_EXPORT BOOL XYBookAudioIsNumberInRange(id _Nullable value, double minimum, double maximum,
                                                  BOOL requiresInteger);

/// @param value 待校验的输入值。
/// @return `value` 为长度大于零的 NSString 时返回 YES。
FOUNDATION_EXPORT BOOL XYBookAudioIsNonEmptyString(id _Nullable value);

/// HTTPS 地址须包含主机，且不得携带用户名或密码。
/// @param value 待校验的地址字符串。
/// @return 输入符合 HTTPS 地址约束时返回 YES。
FOUNDATION_EXPORT BOOL XYBookAudioIsHTTPSURLString(id _Nullable value);

/// 解析 SNCK 的 HTTP(S) 地址并校验长度、空白字符和凭证。
/// @param value 待解析的地址字符串。
/// @return 合法的 HTTP(S) URL，输入无效时返回 nil。
FOUNDATION_EXPORT NSURL *_Nullable XYBookAudioParseSnckURL(id _Nullable value);

#pragma mark - SNCK 错误

/// 创建使用 SNCK 错误域的错误对象。
/// @param code H5 协议的数值错误码。
/// @param message 回传给 H5 的错误说明。
/// @return 可交给桥接回包流程的 NSError。
FOUNDATION_EXPORT NSError *XYBookAudioMakeSnckError(NSInteger code, NSString *message);

/// 将原生或 SNCK 错误转换为 H5 回包格式。
/// @param error 需要回传的错误。
/// @return 含数值 `code` 和字符串 `message` 的字典。
FOUNDATION_EXPORT NSDictionary *XYBookAudioMakeSnckErrorPayload(NSError *error);

NS_ASSUME_NONNULL_END
