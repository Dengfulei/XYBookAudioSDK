// 集成测试使用真实 AVPlayer、WKWebView、存储及 SDK 公开入口，仅模拟宿主账号与音频交接。
#import <XCTest/XCTest.h>
#import <XYBookAudioSDK/XYBookAudioSDK.h>
#import <WebKit/WebKit.h>
#import <AVFoundation/AVFoundation.h>
#import "../XYBookAudioSDK/Storage/XYBookAudioCheckpointStore.h"

@interface XYBookAudioCheckpointStore (TestFileAccess)
- (NSURL *)fileForBook:(NSString *)book identity:(NSString *)identity;
@end

@interface XYBookAudioTestHost : NSObject <XYBookAudioHost>

@property (nonatomic, strong) XYBookAudioIdentity *identity;
@property (nonatomic, copy) void (^pendingAcquire)(NSError *);
@property (nonatomic) BOOL delayAcquire;
@property (nonatomic) NSUInteger acquisitionCount;
@property (nonatomic) NSUInteger releaseCount;

@end

@implementation XYBookAudioTestHost

- (XYBookAudioIdentity *)bookAudioUserIdentity {
    return self.identity;
}

- (void)bookAudioAcquirePlayback:(void (^)(NSError *))completion {
    self.acquisitionCount++;
    if (self.delayAcquire) {
        self.pendingAcquire = completion;
    } else {
        completion(nil);
    }
}

- (void)bookAudioDidReleasePlayback {
    self.releaseCount++;
}

- (void)bookAudioRequestLoginFrom:(UIViewController *)controller
                       completion:(void (^)(XYBookAudioLoginResult, NSError *))completion {
    self.identity = [[XYBookAudioIdentity alloc] initWithUserId:@"test-user"];
    completion(XYBookAudioLoginLoggedIn, nil);
    completion(XYBookAudioLoginFailed, nil);
}

/// 测试宿主返回自己的资料格式，验证桥接不会将其裁剪为简化身份或添加包装。
- (void)bookAudioUserInfoUsingTicket:(BOOL)usingTicket completion:(void (^)(NSDictionary *, NSError *))completion {
    completion(@{@"id" : self.identity.userId, @"info" : @{@"id" : self.identity.userId, @"name" : @"测试用户"}}, nil);
}

- (void)bookAudioShare:(NSDictionary *)request
                  from:(UIViewController *)controller
            completion:(void (^)(XYBookAudioShareResult, NSError *))completion {
    completion(XYBookAudioShareAccepted, nil);
}

@end

@interface XYBookAudioIntegrationTests : XCTestCase

@property (nonatomic, strong) XYBookAudioSDKManager *SDK;
@property (nonatomic, strong) XYBookAudioTestHost *host;
@property (nonatomic, strong) XYBookAudioConfiguration *configuration;

@end

@implementation XYBookAudioIntegrationTests

- (void)setUp {
    [super setUp];
    self.host = [XYBookAudioTestHost new];
    self.host.identity = [[XYBookAudioIdentity alloc] initWithUserId:nil];
    NSURL *entry = [[NSBundle bundleForClass:self.class] URLForResource:@"index" withExtension:@"html"
                                                           subdirectory:@"Fixture"];
    XCTAssertNotNil(entry);
    self.configuration = [[XYBookAudioConfiguration alloc] initWithHostIdentifier:NSUUID.UUID.UUIDString
                                                                         entryURL:entry];
    self.configuration.environment = @"test";
    NSError *error;
    self.SDK = [[XYBookAudioSDKManager alloc] initWithConfiguration:self.configuration host:self.host error:&error];
    XCTAssertNil(error);
}

- (void)tearDown {
    [self.SDK dispose];
    self.SDK = nil;
    [super tearDown];
}

- (NSDictionary *)queue:(BOOL)paid {
    NSMutableArray *chapters = [NSMutableArray array];
    for (NSInteger index = 1; index <= 3; index++) {
        NSString *identifier = [NSString stringWithFormat:@"chapter-%ld", (long)index];
        NSURL *URL = [self.configuration.localResourceDirectory
            URLByAppendingPathComponent:[identifier stringByAppendingPathExtension:@"wav"]];
        [chapters addObject:@{
            @"chapterId" : identifier,
            @"title" : identifier,
            @"requiresLogin" : paid && index > 1 ? @YES : @NO,
            @"audioURL" : URL.absoluteString,
            @"durationMs" : @4000
        }];
    }
    return @{@"bookId" : @"book", @"title" : @"Book", @"chapters" : chapters, @"positionMs" : @0};
}

- (NSDictionary *)command:(NSString *)command parameters:(NSDictionary *)parameters error:(NSError **)error {
    return [self command:command parameters:parameters SDK:self.SDK error:error];
}

- (NSDictionary *)command:(NSString *)command
               parameters:(NSDictionary *)parameters
                      SDK:(XYBookAudioSDKManager *)SDK
                    error:(NSError **)error {
    XCTestExpectation *done = [self expectationWithDescription:command];
    __block NSDictionary *output;
    __block NSError *failure;
    [SDK executeAction:[@"xhBookAudio" stringByAppendingString:command] parameters:parameters
            completion:^(NSDictionary *result, NSError *resultError) {
                output = result;
                failure = resultError;
                [done fulfill];
            }];
    [self waitForExpectations:@[ done ] timeout:12];
    if (error) {
        *error = failure;
    } else {
        XCTAssertNil(failure);
    }
    return output;
}

- (void)waitUntil:(BOOL (^)(NSDictionary *))predicate {
    XCTNSPredicateExpectation *condition = [[XCTNSPredicateExpectation alloc]
        initWithPredicate:[NSPredicate predicateWithBlock:^BOOL(id object, NSDictionary *bindings) {
            return predicate([self.SDK getSnapshot]);
        }]
                   object:nil];
    XCTAssertEqual([XCTWaiter waitForExpectations:@[ condition ] timeout:12], XCTWaiterResultCompleted);
}

/// 通过公开配置捕获实例日志，不依赖内部 logger 的方法或输出实现。
- (XYBookAudioSDKManager *)SDKWithLogLevel:(XYBookAudioLogLevel)level records:(NSMutableArray *)records {
    XYBookAudioConfiguration *configuration = [self.configuration copy];
    configuration.logLevel = level;
    configuration.logHandler = ^(XYBookAudioLogLevel severity, NSString *component, NSString *message) {
        XCTAssertTrue(NSThread.isMainThread);
        [records addObject:@{@"level" : @(severity), @"component" : component, @"message" : message}];
    };
    NSError *error = nil;
    XYBookAudioSDKManager *SDK = [[XYBookAudioSDKManager alloc] initWithConfiguration:configuration host:self.host
                                                                                error:&error];
    XCTAssertNil(error);
    XCTAssertNotNil(SDK);
    return SDK;
}

/// 窗口动作依赖来源网页；原生命令入口明确拒绝，不能误截取动作前缀或改变会话状态。
- (void)testNativeCommandsRejectPageScopedWindowActions {
    NSDictionary *snapshot = [self.SDK getSnapshot];
    for (NSString *action in @[ @"xhOpenWindow", @"xhCloseWindow", @"xhGoLogin" ]) {
        XCTestExpectation *done = [self expectationWithDescription:action];
        [self.SDK executeAction:action parameters:@{@"url" : self.configuration.entryURL.absoluteString}
                     completion:^(NSDictionary *result, NSError *error) {
                         XCTAssertNil(result);
                         XCTAssertEqualObjects(error.domain, XYBookAudioErrorDomain);
                         XCTAssertEqual(error.code, XYBookAudioInvalidArgument);
                         [done fulfill];
                     }];
        [self waitForExpectations:@[ done ] timeout:2];
    }
    XCTAssertEqualObjects([self.SDK getSnapshot], snapshot);
}

/// 测试 bundle 实现的 xhTestEcho 只属于 H5；原生入口不能把短名称误截取为播放命令。
- (void)testNativeCommandsRejectH5OnlyMethodWithoutPlaybackPrefix {
    NSDictionary *snapshot = [self.SDK getSnapshot];
    XCTestExpectation *done = [self expectationWithDescription:@"拒绝没有播放命令实现的 H5 方法"];
    [self.SDK executeAction:@"xhTestEcho" parameters:@{} completion:^(NSDictionary *result, NSError *error) {
        XCTAssertNil(result);
        XCTAssertEqualObjects(error.domain, XYBookAudioErrorDomain);
        XCTAssertEqual(error.code, XYBookAudioUnsupported);
        [done fulfill];
    }];
    [self waitForExpectations:@[ done ] timeout:2];
    XCTAssertEqualObjects([self.SDK getSnapshot], snapshot);
}

- (void)testLoggingDefaultsOffAndRejectsInvalidLevel {
    XCTAssertEqual(self.configuration.logLevel, XYBookAudioLogLevelOff);
    NSMutableArray *records = [NSMutableArray array];
    XYBookAudioSDKManager *SDK = [self SDKWithLogLevel:XYBookAudioLogLevelOff records:records];
    [SDK executeAction:@"xhBookAudioMissing" parameters:@{} completion:^(NSDictionary *result, NSError *error) {
        XCTAssertEqual(error.code, XYBookAudioUnsupported);
    }];
    [SDK dispose];
    XCTAssertEqual(records.count, 0u);
    self.configuration.logLevel = (XYBookAudioLogLevel)(XYBookAudioLogLevelDebug + 1);
    NSError *error = nil;
    XCTAssertNil([[XYBookAudioSDKManager alloc] initWithConfiguration:self.configuration host:self.host error:&error]);
    XCTAssertEqual(error.code, XYBookAudioInvalidArgument);
}

- (void)testLoggingFiltersEverySeverityWithoutChangingCommandResults {
    for (NSInteger threshold = XYBookAudioLogLevelError; threshold <= XYBookAudioLogLevelDebug; threshold++) {
        NSMutableArray *records = [NSMutableArray array];
        XYBookAudioSDKManager *SDK = [self SDKWithLogLevel:(XYBookAudioLogLevel)threshold records:records];
        [SDK executeAction:@"xhBookAudioGetSnapshot" parameters:@{} completion:^(NSDictionary *result, NSError *error) {
            XCTAssertNil(error);
            XCTAssertEqualObjects(result[@"state"], @"idle");
        }];
        [SDK executeAction:@"xhBookAudioMissing" parameters:@{} completion:^(NSDictionary *result, NSError *error) {
            XCTAssertEqual(error.code, XYBookAudioUnsupported);
        }];
        [SDK executeAction:@"xhBookAudioPlay" parameters:@{} completion:^(NSDictionary *result, NSError *error) {
            XCTAssertEqual(error.code, XYBookAudioInvalidState);
        }];
        [SDK dispose];
        NSMutableSet *actual = [NSMutableSet set];
        for (NSDictionary *record in records) {
            XCTAssertLessThanOrEqual([record[@"level"] integerValue], threshold);
            [actual addObject:record[@"level"]];
        }
        NSMutableSet *expected = [NSMutableSet set];
        for (NSInteger severity = XYBookAudioLogLevelError; severity <= threshold; severity++) {
            [expected addObject:@(severity)];
        }
        XCTAssertEqualObjects(actual, expected);
    }
}

- (void)testLogConfigurationCopyAndInstanceIsolation {
    NSMutableArray *first = [NSMutableArray array];
    NSMutableArray *second = [NSMutableArray array];
    self.configuration.logLevel = XYBookAudioLogLevelDebug;
    self.configuration.logHandler = ^(XYBookAudioLogLevel level, NSString *component, NSString *message) {
        [first addObject:message];
    };
    XYBookAudioSDKManager *SDK = [[XYBookAudioSDKManager alloc] initWithConfiguration:self.configuration host:self.host
                                                                                error:nil];
    self.configuration.logLevel = XYBookAudioLogLevelOff;
    self.configuration.logHandler = ^(XYBookAudioLogLevel level, NSString *component, NSString *message) {
        [second addObject:message];
    };
    XYBookAudioSDKManager *silent = [[XYBookAudioSDKManager alloc] initWithConfiguration:self.configuration
                                                                                    host:self.host
                                                                                   error:nil];
    [first removeAllObjects];
    [SDK executeAction:@"xhBookAudioGetSnapshot" parameters:@{} completion:^(NSDictionary *result, NSError *error){
    }];
    [silent executeAction:@"xhBookAudioGetSnapshot" parameters:@{} completion:^(NSDictionary *result, NSError *error){
    }];
    XCTAssertGreaterThan(first.count, 0u);
    XCTAssertEqual(second.count, 0u);
    [SDK dispose];
    [silent dispose];
}

- (void)testLogsExcludePayloadIdentityURLAndExternalErrorText {
    NSString *secret = @"private-user-token-book-payload";
    self.host.identity = [[XYBookAudioIdentity alloc] initWithUserId:secret];
    NSMutableArray *records = [NSMutableArray array];
    XYBookAudioSDKManager *SDK = [self SDKWithLogLevel:XYBookAudioLogLevelDebug records:records];
    NSMutableDictionary *queue = [[self queue:NO] mutableCopy];
    queue[@"bookId"] = secret;
    queue[@"title"] = secret;
    [SDK executeAction:@"xhBookAudioSetQueue" parameters:queue completion:^(NSDictionary *result, NSError *error) {
        XCTAssertNil(error);
    }];
    [SDK executeAction:secret parameters:@{@"token" : secret} completion:^(NSDictionary *result, NSError *error) {
        XCTAssertEqual(error.code, XYBookAudioUnsupported);
    }];
    self.host.delayAcquire = YES;
    XCTestExpectation *failed = [self expectationWithDescription:@"host error remains visible to caller"];
    [SDK executeAction:@"xhBookAudioPlay" parameters:@{} completion:^(NSDictionary *result, NSError *error) {
        XCTAssertEqualObjects(error.domain, secret);
        [failed fulfill];
    }];
    self.host.pendingAcquire([NSError errorWithDomain:secret code:123 userInfo:@{NSLocalizedDescriptionKey : secret}]);
    [self waitForExpectations:@[ failed ] timeout:3];
    // 直接检查回调文本，避免 JSON 对斜杠转义后掩盖 URL／路径泄漏。
    NSString *output = [[records valueForKey:@"message"] componentsJoinedByString:@"\n"];
    XCTAssertGreaterThan(records.count, 0u);
    XCTAssertFalse([output containsString:secret]);
    XCTAssertFalse([output containsString:self.configuration.localResourceDirectory.path]);
    XCTAssertFalse([output containsString:@"audioURL"]);
    [SDK dispose];
}

- (void)testLogHandlerCannotRecursivelyDeliverLogs {
    __block NSUInteger depth = 0, maximumDepth = 0, nestedCompletions = 0;
    __block __weak XYBookAudioSDKManager *callbackSDK = nil;
    self.configuration.logLevel = XYBookAudioLogLevelDebug;
    self.configuration.logHandler = ^(XYBookAudioLogLevel level, NSString *component, NSString *message) {
        depth++;
        maximumDepth = MAX(maximumDepth, depth);
        if (depth == 1 && callbackSDK) {
            [callbackSDK executeAction:@"xhBookAudioGetSnapshot" parameters:@{}
                            completion:^(NSDictionary *result, NSError *error) {
                                XCTAssertNil(error);
                                nestedCompletions++;
                            }];
        }
        depth--;
    };
    XYBookAudioSDKManager *SDK = [[XYBookAudioSDKManager alloc] initWithConfiguration:self.configuration host:self.host
                                                                                error:nil];
    callbackSDK = SDK;
    [SDK executeAction:@"xhBookAudioGetSnapshot" parameters:@{} completion:^(NSDictionary *result, NSError *error){
    }];
    XCTAssertGreaterThan(nestedCompletions, 0u);
    XCTAssertEqual(maximumDepth, 1u);
    callbackSDK = nil;
    [SDK dispose];
}

- (void)testAtomicQueueAndPaidGate {
    [self command:@"SetQueue" parameters:[self queue:YES] error:nil];
    NSError *error;
    [self command:@"SetQueue" parameters:@{@"bookId" : @"invalid"} error:&error];
    XCTAssertEqual(error.code, XYBookAudioInvalidArgument);
    XCTAssertEqualObjects([self.SDK getSnapshot][@"bookId"], @"book");
    [self command:@"SelectChapter" parameters:@{@"chapterId" : @"chapter-2"} error:&error];
    XCTAssertEqual(error.code, XYBookAudioLoginRequired);
    XCTAssertEqualObjects([self.SDK getSnapshot][@"chapterId"], @"chapter-2");
    self.host.identity = [[XYBookAudioIdentity alloc] initWithUserId:@"new-user"];
    [self.SDK refreshHostIdentity];
    [self command:@"Play" parameters:@{} error:&error];
    XCTAssertEqual(error.code, XYBookAudioSourceNotReady);
}

- (void)testLocalSourcesCannotEscapeEntryDirectoryOrBeUsedByRemotePage {
    XCTAssertFalse([self.configuration allowsMediaURL:[NSURL fileURLWithPath:@"/etc/hosts"]]);
    XYBookAudioConfiguration *remote =
        [[XYBookAudioConfiguration alloc] initWithHostIdentifier:@"remote"
                                                        entryURL:[NSURL URLWithString:@"https://example.com/books"]];
    XCTAssertFalse([remote allowsMediaURL:self.configuration.entryURL]);
    XCTAssertFalse([remote allowsURL:[NSURL URLWithString:@"https://example.com/books-evil"]]);
    XCTAssertFalse([remote allowsURL:[NSURL URLWithString:@"https://example.com.evil/books"]]);
    XCTAssertFalse([remote allowsURL:[NSURL URLWithString:@"https://example.com/books/%2e%2e/private"]]);
    XCTAssertTrue([remote allowsURL:[NSURL URLWithString:@"https://example.com/books/one"]]);
}

- (void)testCountOneStopsAtCurrentEndWithoutAdvancing {
    [self command:@"SetQueue" parameters:[self queue:NO] error:nil];
    [self command:@"Play" parameters:@{} error:nil];
    [self waitUntil:^BOOL(NSDictionary *snapshot) {
        return [snapshot[@"state"] isEqual:@"playing"];
    }];
    [self command:@"SetSleepTimer" parameters:@{@"mode" : @"trackCount", @"count" : @1} error:nil];
    [self waitUntil:^BOOL(NSDictionary *snapshot) {
        return [snapshot[@"reason"] isEqual:@"sleepTrackCount"];
    }];
    NSDictionary *snapshot = [self.SDK getSnapshot];
    XCTAssertEqualObjects(snapshot[@"chapterId"], @"chapter-1");
    XCTAssertEqualObjects(snapshot[@"sleepTimer"][@"mode"], @"off");
    XCTAssertGreaterThan([snapshot[@"positionMs"] doubleValue], 3900);
}

- (void)testManualSeekToEndDoesNotConsumeCount {
    [self command:@"SetQueue" parameters:[self queue:NO] error:nil];
    [self command:@"Play" parameters:@{} error:nil];
    [self waitUntil:^BOOL(NSDictionary *snapshot) {
        return [snapshot[@"state"] isEqual:@"playing"];
    }];
    [self command:@"SetSleepTimer" parameters:@{@"mode" : @"trackCount", @"count" : @2} error:nil];
    [self command:@"SeekTo" parameters:@{@"positionMs" : @4000} error:nil];
    [self waitUntil:^BOOL(NSDictionary *snapshot) {
        return [snapshot[@"chapterId"] isEqual:@"chapter-2"];
    }];
    XCTAssertEqualObjects([self.SDK getSnapshot][@"sleepTimer"][@"remainingCount"], @2);
}

- (void)testDurationExpiresWhilePausedAndInvalidReplacementPreservesTimer {
    [self command:@"SetQueue" parameters:[self queue:NO] error:nil];
    [self command:@"SetSleepTimer" parameters:@{@"mode" : @"duration", @"durationMs" : @250} error:nil];
    NSError *error;
    [self command:@"SetSleepTimer" parameters:@{@"mode" : @"duration", @"durationMs" : @NO} error:&error];
    XCTAssertNotNil(error);
    XCTAssertEqualObjects([self.SDK getSnapshot][@"sleepTimer"][@"mode"], @"duration");
    [self waitUntil:^BOOL(NSDictionary *snapshot) {
        return [snapshot[@"reason"] isEqual:@"sleepDuration"];
    }];
    XCTAssertEqualObjects([self.SDK getSnapshot][@"state"], @"paused");
}

/// 读取宿主身份失败时，必须阻止沿用上一位用户的播放权限。
- (void)testUnavailableIdentityRejectsPlayback {
    [self command:@"SetQueue" parameters:[self queue:NO] error:nil];
    [self command:@"Play" parameters:@{} error:nil];
    [self waitUntil:^BOOL(NSDictionary *snapshot) {
        return [snapshot[@"state"] isEqual:@"playing"];
    }];
    [self command:@"Pause" parameters:@{} error:nil];
    self.host.identity = nil;
    NSError *error;
    [self command:@"Play" parameters:@{} error:&error];
    XCTAssertEqual(error.code, XYBookAudioHostFailed);
    XCTAssertNotEqualObjects([self.SDK getSnapshot][@"state"], @"playing");
}

- (void)testHostTakeoverCancelsPendingPlayback {
    [self command:@"SetQueue" parameters:[self queue:NO] error:nil];
    self.host.delayAcquire = YES;
    XCTestExpectation *done = [self expectationWithDescription:@"superseded playback"];
    [self.SDK executeAction:@"xhBookAudioPlay" parameters:@{} completion:^(NSDictionary *result, NSError *error) {
        XCTAssertEqual(error.code, XYBookAudioInvalidState);
        [done fulfill];
    }];
    [self.SDK yieldPlayback];
    self.host.pendingAcquire(nil);
    self.host.pendingAcquire(nil);
    [self waitForExpectations:@[ done ] timeout:3];
    XCTAssertNotEqualObjects([self.SDK getSnapshot][@"state"], @"playing");
    XCTAssertEqual(self.host.releaseCount, 1);
}

- (void)testOneSDKInstanceOwnsAudioFromHandoffThroughRelease {
    XYBookAudioTestHost *otherHost = [XYBookAudioTestHost new];
    otherHost.identity = self.host.identity;
    XYBookAudioSDKManager *otherSDK = [[XYBookAudioSDKManager alloc] initWithConfiguration:self.configuration
                                                                                      host:otherHost
                                                                                     error:nil];
    XCTAssertNotNil(otherSDK);
    [self command:@"SetQueue" parameters:[self queue:NO] error:nil];
    [self command:@"SetQueue" parameters:[self queue:NO] SDK:otherSDK error:nil];

    self.host.delayAcquire = YES;
    XCTestExpectation *playing = [self expectationWithDescription:@"First SDK received audio control"];
    [self.SDK executeAction:@"xhBookAudioPlay" parameters:@{} completion:^(NSDictionary *result, NSError *error) {
        XCTAssertNil(error);
        [playing fulfill];
    }];
    NSError *error = nil;
    [self command:@"Play" parameters:@{} SDK:otherSDK error:&error];
    XCTAssertEqual(error.code, XYBookAudioBusy);
    XCTAssertEqual(otherHost.acquisitionCount, 0);

    self.host.pendingAcquire(nil);
    [self waitForExpectations:@[ playing ] timeout:3];
    [otherSDK yieldPlayback];
    [self command:@"Play" parameters:@{} SDK:otherSDK error:&error];
    XCTAssertEqual(error.code, XYBookAudioBusy);
    XCTAssertEqual(self.host.releaseCount, 0);
    XCTAssertEqual(otherHost.releaseCount, 0);

    [self.SDK yieldPlayback];
    XCTAssertEqual(self.host.releaseCount, 1);
    [self command:@"Play" parameters:@{} SDK:otherSDK error:nil];
    XCTAssertEqual(otherHost.acquisitionCount, 1);
    [otherSDK dispose];
    XCTAssertEqual(otherHost.releaseCount, 1);
}

- (void)testExpiredSleepTimerCannotResumeAfterInterruption {
    [self command:@"SetQueue" parameters:[self queue:NO] error:nil];
    [self command:@"Play" parameters:@{} error:nil];
    [self waitUntil:^BOOL(NSDictionary *snapshot) {
        return [snapshot[@"state"] isEqual:@"playing"];
    }];
    [self command:@"SetSleepTimer" parameters:@{@"mode" : @"duration", @"durationMs" : @250} error:nil];
    [NSNotificationCenter.defaultCenter
        postNotificationName:AVAudioSessionInterruptionNotification
                      object:AVAudioSession.sharedInstance
                    userInfo:@{AVAudioSessionInterruptionTypeKey : @(AVAudioSessionInterruptionTypeBegan)}];
    [self waitUntil:^BOOL(NSDictionary *snapshot) {
        return [snapshot[@"reason"] isEqual:@"sleepDuration"];
    }];
    [NSNotificationCenter.defaultCenter
        postNotificationName:AVAudioSessionInterruptionNotification
                      object:AVAudioSession.sharedInstance
                    userInfo:@{
                        AVAudioSessionInterruptionTypeKey : @(AVAudioSessionInterruptionTypeEnded),
                        AVAudioSessionInterruptionOptionKey : @(AVAudioSessionInterruptionOptionShouldResume)
                    }];
    XCTAssertEqualObjects([self.SDK getSnapshot][@"state"], @"paused");
}

- (void)testLatestSeekWinsAndCheckpointRestoresAfterReinitializing {
    [self command:@"SetQueue" parameters:[self queue:NO] error:nil];
    [self command:@"Play" parameters:@{} error:nil];
    [self waitUntil:^BOOL(NSDictionary *snapshot) {
        return [snapshot[@"state"] isEqual:@"playing"];
    }];
    [self command:@"Pause" parameters:@{} error:nil];
    NSMutableArray *expectations = [NSMutableArray array];
    for (NSNumber *target in @[ @500, @1000, @2200 ]) {
        XCTestExpectation *seek = [self expectationWithDescription:@"seek settles"];
        [expectations addObject:seek];
        [self.SDK executeAction:@"xhBookAudioSeekTo" parameters:@{@"positionMs" : target}
                     completion:^(NSDictionary *result, NSError *error) {
                         if ([target isEqual:@2200]) {
                             XCTAssertNil(error);
                         }
                         [seek fulfill];
                     }];
    }
    [self waitForExpectations:expectations timeout:4];
    XCTAssertEqualWithAccuracy([[self.SDK getSnapshot][@"positionMs"] doubleValue], 2200, 50);
    [self.SDK dispose];
    self.SDK = [[XYBookAudioSDKManager alloc] initWithConfiguration:self.configuration host:self.host error:nil];
    NSMutableDictionary *queue = [[self queue:NO] mutableCopy];
    [queue removeObjectForKey:@"positionMs"];
    [self command:@"SetQueue" parameters:queue error:nil];
    XCTAssertEqualWithAccuracy([[self.SDK getSnapshot][@"positionMs"] doubleValue], 2200, 50);
}

- (void)testCountBeyondQueueEndsWithoutLoopingAndSnapshotNeverLeaksSource {
    [self command:@"SetQueue" parameters:[self queue:NO] error:nil];
    [self command:@"SelectChapter" parameters:@{@"chapterId" : @"chapter-3"} error:nil];
    [self waitUntil:^BOOL(NSDictionary *snapshot) {
        return [snapshot[@"state"] isEqual:@"playing"];
    }];
    [self command:@"SetRate" parameters:@{@"rate" : @2} error:nil];
    [self command:@"SetSleepTimer" parameters:@{@"mode" : @"trackCount", @"count" : @3} error:nil];
    [self waitUntil:^BOOL(NSDictionary *snapshot) {
        return [snapshot[@"reason"] isEqual:@"queueEnded"];
    }];
    XCTAssertEqualObjects([self.SDK getSnapshot][@"sleepTimer"][@"mode"], @"off");
    NSData *data = [NSJSONSerialization dataWithJSONObject:[self.SDK getSnapshot] options:0 error:nil];
    XCTAssertFalse([[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] containsString:@"audioURL"]);
}

- (void)testCheckpointStaysWithOriginalIdentityUntilNewQueue {
    [self command:@"SetQueue" parameters:[self queue:NO] error:nil];
    [self command:@"SeekTo" parameters:@{@"positionMs" : @1500} error:nil];
    self.host.identity = [[XYBookAudioIdentity alloc] initWithUserId:@"other"];
    [self.SDK refreshHostIdentity];
    [self.SDK stop];
    NSMutableDictionary *queue = [[self queue:NO] mutableCopy];
    [queue removeObjectForKey:@"positionMs"];
    [self command:@"SetQueue" parameters:queue error:nil];
    XCTAssertEqualObjects([self.SDK getSnapshot][@"positionMs"], @0);
    self.host.identity = [[XYBookAudioIdentity alloc] initWithUserId:nil];
    [self.SDK refreshHostIdentity];
    [self command:@"SetQueue" parameters:queue error:nil];
    XCTAssertEqualObjects([self.SDK getSnapshot][@"positionMs"], @1500);
}

- (void)testCorruptCheckpointIsIsolatedAndDoesNotBlockQueue {
    NSMutableDictionary *queue = [[self queue:NO] mutableCopy];
    [self command:@"SetQueue" parameters:queue error:nil];
    [self command:@"SeekTo" parameters:@{@"positionMs" : @1500} error:nil];
    [self.SDK dispose];
    self.SDK = [[XYBookAudioSDKManager alloc] initWithConfiguration:self.configuration host:self.host error:nil];

    XYBookAudioCheckpointStore *store =
        [[XYBookAudioCheckpointStore alloc] initWithHost:self.configuration.hostIdentifier
                                             environment:self.configuration.environment];
    NSURL *file = [store fileForBook:@"book" identity:self.host.identity.userId];
    NSData *corrupt = [@"{invalid JSON" dataUsingEncoding:NSUTF8StringEncoding];
    XCTAssertTrue([corrupt writeToURL:file options:NSDataWritingAtomic error:nil]);
    NSMutableArray<NSString *> *errors = [NSMutableArray array];
    NSUUID *subscription = [self.SDK subscribe:^(NSString *event, NSDictionary *parameters) {
        if ([event isEqualToString:@"onBookAudioError"]) {
            [errors addObject:parameters[@"code"]];
        }
    }];

    queue[@"positionMs"] = @800;
    NSDictionary *snapshot = [self command:@"SetQueue" parameters:queue error:nil];
    XCTAssertEqualObjects(snapshot[@"positionMs"], @800);
    XCTAssertEqualObjects(errors, (@[ @"STORAGE_FAILED" ]));
    XCTAssertFalse([NSFileManager.defaultManager fileExistsAtPath:file.path]);
    NSURL *quarantine = [file URLByAppendingPathExtension:@"corrupt"];
    XCTAssertEqualObjects([NSData dataWithContentsOfURL:quarantine], corrupt);

    [self command:@"SeekTo" parameters:@{@"positionMs" : @1200} error:nil];
    [queue removeObjectForKey:@"positionMs"];
    snapshot = [self command:@"SetQueue" parameters:queue error:nil];
    XCTAssertEqualObjects(snapshot[@"positionMs"], @1200);
    XCTAssertEqual(errors.count, 1);
    [self.SDK unsubscribe:subscription];
}

/// 测试通过遍历 UIKit 视图树定位页面，避免为测试在 SDK 公开接口中暴露 WebView。
- (WKWebView *)findWebView:(UIView *)view {
    if ([view isKindOfClass:WKWebView.class]) {
        return (WKWebView *)view;
    }
    for (UIView *child in view.subviews) {
        WKWebView *found = [self findWebView:child];
        if (found) {
            return found;
        }
    }
    return nil;
}

/// 页面就绪必须包含通过相对路径加载的测试脚本，不能仅以原生页面展示完成为准。
- (BOOL)waitForFixturePage:(WKWebView *)web {
    __block BOOL ready = NO;
    XCTNSPredicateExpectation *loaded = [[XCTNSPredicateExpectation alloc]
        initWithPredicate:[NSPredicate predicateWithBlock:^BOOL(id object, NSDictionary *bindings) {
            [web evaluateJavaScript:@"typeof call === 'function'" completionHandler:^(id result, NSError *error) {
                ready = [result boolValue];
            }];
            return ready;
        }]
                   object:nil];
    XCTWaiterResult result = [XCTWaiter waitForExpectations:@[ loaded ] timeout:12];
    XCTAssertEqual(result, XCTWaiterResultCompleted, @"A valid local entry must load its HTML and relative scripts.");
    return result == XCTWaiterResultCompleted;
}

/// 本地入口别名解析后的目录必须与 WebKit 获得读取权限的目录一致。
- (void)testLocalEntryThroughSymbolicLinkLoadsHTMLAndBridge {
    NSFileManager *files = NSFileManager.defaultManager;
    NSURL *temporaryDirectory = [NSURL fileURLWithPath:NSTemporaryDirectory() isDirectory:YES];
    NSURL *alias = [temporaryDirectory URLByAppendingPathComponent:NSUUID.UUID.UUIDString isDirectory:YES];
    NSError *error = nil;
    XCTAssertTrue([files createSymbolicLinkAtURL:alias withDestinationURL:self.configuration.localResourceDirectory
                                           error:&error]);
    XCTAssertNil(error);
    self.configuration.entryURL = [alias URLByAppendingPathComponent:@"index.html"];
    XCTAssertNotEqualObjects(self.configuration.entryURL.path,
                             self.configuration.entryURL.URLByResolvingSymlinksInPath.path);
    [self.SDK dispose];
    self.SDK = [[XYBookAudioSDKManager alloc] initWithConfiguration:self.configuration host:self.host error:&error];
    XCTAssertNil(error);
    UIViewController *presenter = UIApplication.sharedApplication.delegate.window.rootViewController;
    XCTestExpectation *opened = [self expectationWithDescription:@"open aliased local entry"];
    [self.SDK openFromViewController:presenter completion:^(NSError *failure) {
        XCTAssertNil(failure);
        [opened fulfill];
    }];
    [self waitForExpectations:@[ opened ] timeout:4];
    WKWebView *web = [self findWebView:presenter.presentedViewController.view];
    XCTAssertNotNil(web);
    if ([self waitForFixturePage:web]) {
        XCTestExpectation *bridge = [self expectationWithDescription:@"bridge through aliased entry"];
        [web callAsyncJavaScript:@"return await call('xhBookAudioGetCapabilities');" arguments:@{} inFrame:nil
                  inContentWorld:WKContentWorld.pageWorld completionHandler:^(NSDictionary *result, NSError *failure) {
                      XCTAssertNil(failure);
                      XCTAssertNil(result[@"protocolVersion"]);
                      XCTAssertTrue([result[@"actions"] containsObject:@"xhBookAudioGetSnapshot"]);
                      [bridge fulfill];
                  }];
        [self waitForExpectations:@[ bridge ] timeout:4];
    }
    XCTestExpectation *closed = [self expectationWithDescription:@"close aliased entry"];
    [presenter dismissViewControllerAnimated:NO completion:^{
        [closed fulfill];
    }];
    [self waitForExpectations:@[ closed ] timeout:3];
    XCTAssertTrue([files removeItemAtURL:alias error:&error]);
    XCTAssertNil(error);
}

- (void)testBuiltInPageBridgeDuplicateOpenCloseAndReopen {
    UIViewController *presenter = UIApplication.sharedApplication.delegate.window.rootViewController;
    XCTestExpectation *opened = [self expectationWithDescription:@"open"];
    [self.SDK openFromViewController:presenter completion:^(NSError *error) {
        XCTAssertNil(error);
        [opened fulfill];
    }];
    [self waitForExpectations:@[ opened ] timeout:4];
    UINavigationController *navigation = (UINavigationController *)presenter.presentedViewController;
    UIViewController *hostLogin = [UIViewController new];
    [navigation pushViewController:hostLogin animated:NO];
    XCTNSPredicateExpectation *loginVisible = [[XCTNSPredicateExpectation alloc]
        initWithPredicate:[NSPredicate predicateWithBlock:^BOOL(id object, NSDictionary *bindings) {
            return hostLogin.viewIfLoaded.window != nil && navigation.visibleViewController == hostLogin;
        }]
                   object:nil];
    XCTAssertEqual([XCTWaiter waitForExpectations:@[ loginVisible ] timeout:4], XCTWaiterResultCompleted);
    [navigation setNavigationBarHidden:YES animated:NO];
    [navigation popViewControllerAnimated:NO];
    XCTNSPredicateExpectation *navigationRestored = [[XCTNSPredicateExpectation alloc]
        initWithPredicate:[NSPredicate predicateWithBlock:^BOOL(id object, NSDictionary *bindings) {
            return !navigation.navigationBarHidden;
        }]
                   object:nil];
    XCTAssertEqual([XCTWaiter waitForExpectations:@[ navigationRestored ] timeout:4], XCTWaiterResultCompleted);
    [self.SDK openFromViewController:presenter completion:^(NSError *error) {
        XCTAssertEqual(error.code, XYBookAudioBusy);
    }];
    WKWebView *web = [self findWebView:presenter.presentedViewController.view];
    XCTAssertNotNil(web);
    [self waitForFixturePage:web];
    XCTestExpectation *bridge = [self expectationWithDescription:@"real bridge"];
    NSString *script = @"const capability=await call('xhBookAudioGetCapabilities');"
                        "const snapshot=await call('xhBookAudioGetSnapshot');"
                        "const canUse=await call('xhCanIUse',{name:'xhBookAudioPlay'});"
                        "const profile=await call('xhGetUserInfo',{goLogin:true,useTicket:false});"
                        "const share=await call('xhShowShareMenu',{title:'test',link:'https://example.com/book'});"
                        "await loadQueue(false);await call('xhBookAudioPlay');"
                        "return {capability,snapshot,canUse,profile,share};";
    [web callAsyncJavaScript:script arguments:@{} inFrame:nil inContentWorld:WKContentWorld.pageWorld
           completionHandler:^(NSDictionary *result, NSError *error) {
               XCTAssertNil(error);
               XCTAssertNil(result[@"capability"][@"protocolVersion"]);
               XCTAssertEqualObjects(result[@"snapshot"][@"state"], @"idle");
               XCTAssertEqualObjects(result[@"canUse"][@"data"], @1);
               XCTAssertEqualObjects(result[@"profile"][@"info"][@"name"], @"测试用户");
               XCTAssertEqualObjects(result[@"share"], @{});
               [bridge fulfill];
           }];
    [self waitForExpectations:@[ bridge ] timeout:8];
    XCTestExpectation *closed = [self expectationWithDescription:@"closed"];
    [presenter dismissViewControllerAnimated:NO completion:^{
        [closed fulfill];
    }];
    [self waitForExpectations:@[ closed ] timeout:3];
    [self waitUntil:^BOOL(NSDictionary *snapshot) {
        return [snapshot[@"state"] isEqual:@"playing"];
    }];
    XCTestExpectation *reopened = [self expectationWithDescription:@"reopen"];
    [self.SDK openFromViewController:presenter completion:^(NSError *error) {
        XCTAssertNil(error);
        [reopened fulfill];
    }];
    [self waitForExpectations:@[ reopened ] timeout:4];
    XCTAssertEqualObjects([self.SDK getSnapshot][@"bookId"], @"local-free");
    XCTestExpectation *finallyClosed = [self expectationWithDescription:@"reopened page closed"];
    [presenter dismissViewControllerAnimated:NO completion:^{
        [finallyClosed fulfill];
    }];
    [self waitForExpectations:@[ finallyClosed ] timeout:3];
}

@end
