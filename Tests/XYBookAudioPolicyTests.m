// 使用可控的连续时钟，验证队列输入的严格校验与定时关闭语义。
#import <XCTest/XCTest.h>
#import "XYBookAudioQueue.h"
#import "XYBookAudioSleepTimer.h"

@interface XYBookAudioPolicyTests : XCTestCase

@end

@implementation XYBookAudioPolicyTests

- (void)testCountIncludesCurrentChapterAndDeduplicatesCompletion {
    XYBookAudioSleepTimer *timer = [[XYBookAudioSleepTimer alloc] initWithClock:^{
        return 0.0;
    }];
    XCTAssertTrue(([timer configure:@{@"mode" : @"trackCount", @"count" : @2} hasCurrentChapter:YES error:nil]));
    XCTAssertEqual(timer.lastChange, XYBookAudioTimerChangeSet);
    NSUUID *first = NSUUID.UUID;
    XCTAssertFalse(([timer consumeNaturalCompletion:first]));
    XCTAssertFalse(([timer consumeNaturalCompletion:first]));
    XCTAssertEqualObjects([timer snapshot][@"remainingCount"], @1);
    XCTAssertEqual(timer.lastChange, XYBookAudioTimerChangeItemCompleted);
    XCTAssertTrue(([timer consumeNaturalCompletion:NSUUID.UUID]));
    XCTAssertEqualObjects([timer snapshot][@"mode"], @"off");
    XCTAssertFalse(([timer consumeNaturalCompletion:NSUUID.UUID]));
    XCTAssertEqual(timer.lastChange, XYBookAudioTimerChangeExpired);
}

- (void)testInvalidReplacementPreservesActiveTimer {
    XYBookAudioSleepTimer *timer = [[XYBookAudioSleepTimer alloc] initWithClock:^{
        return 0.0;
    }];
    XCTAssertTrue(([timer configure:@{@"mode" : @"trackCount", @"count" : @3} hasCurrentChapter:YES error:nil]));
    for (id value in @[ @0, @(-1), @1.5, @YES, @"3", NSNull.null ]) {
        NSError *error;
        XCTAssertFalse(([timer configure:@{@"mode" : @"trackCount", @"count" : value} hasCurrentChapter:YES
                                   error:&error]));
        XCTAssertNotNil(error);
        XCTAssertEqualObjects([timer snapshot][@"remainingCount"], @3);
    }
}

- (void)testDurationCountsSuspendedTimeAndExpiresOnlyOnce {
    __block NSTimeInterval now = 100;
    XYBookAudioSleepTimer *timer = [[XYBookAudioSleepTimer alloc] initWithClock:^{
        return now;
    }];
    XCTAssertTrue(([timer configure:@{@"mode" : @"duration", @"durationMs" : @900000} hasCurrentChapter:NO error:nil]));
    now += 899;
    XCTAssertFalse(([timer consumeDeadline]));
    XCTAssertEqualObjects([timer snapshot][@"remainingMs"], @1000);
    now += 61;
    XCTAssertTrue(([timer consumeDeadline]));
    XCTAssertFalse(([timer consumeDeadline]));
    XCTAssertEqual(timer.lastChange, XYBookAudioTimerChangeExpired);
    XCTAssertTrue(([timer configure:@{@"mode" : @"trackCount", @"count" : @2} hasCurrentChapter:YES error:nil]));
    XCTAssertEqual(timer.lastChange, XYBookAudioTimerChangeSet);
    [timer queueDidEnd];
    XCTAssertEqualObjects([timer snapshot][@"mode"], @"off");
    XCTAssertEqual(timer.lastChange, XYBookAudioTimerChangeQueueEnded);
}

- (void)testQueueRejectsDuplicateIdentifiersAndMissingLoginFlag {
    NSDictionary *chapter = @{@"chapterId" : @"one", @"title" : @"First", @"requiresLogin" : @NO};
    NSError *error;
    XCTAssertNil(([XYBookAudioQueue
        queueWithParameters:@{@"bookId" : @"book", @"title" : @"Book", @"chapters" : @[ chapter, chapter ]}
                      error:&error]));
    XCTAssertNotNil(error);
    XCTAssertNil(([XYBookAudioQueue queueWithParameters:@{
        @"bookId" : @"book",
        @"title" : @"Book",
        @"chapters" : @[ @{@"chapterId" : @"one", @"title" : @"First"} ]
    }
                                                  error:&error]));
}

- (void)testExplicitLocalSampleQueueCanDescribeBundledAudio {
    NSDictionary *chapter = @{
        @"chapterId" : @"one",
        @"title" : @"First",
        @"requiresLogin" : @YES,
        @"audioURL" : @"file:///fixture/tone.wav",
        @"durationMs" : @4000.25
    };
    NSError *error = nil;
    XYBookAudioQueue *queue =
        [XYBookAudioQueue queueWithParameters:@{@"bookId" : @"book", @"title" : @"Book", @"chapters" : @[ chapter ]}
                                        error:&error];
    XCTAssertNil(error);
    XCTAssertEqual(queue.chapters.count, 1u);
    XYBookAudioChapter *model = queue.chapters.firstObject;
    XCTAssertEqualObjects(model.chapterId, @"one");
    XCTAssertEqualObjects(model.title, @"First");
    XCTAssertTrue(model.requiresLogin);
    XCTAssertEqualObjects(model.audioURL, @"file:///fixture/tone.wav");
    XCTAssertEqualObjects(model.durationMs, @4000.25);
}

@end
