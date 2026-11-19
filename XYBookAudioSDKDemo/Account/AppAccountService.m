// 账号状态只有一个归属；登录、切换和退出都通过同一变更入口通知各业务模块，不反向调用 SDK。
#import "AppAccountService.h"

NSNotificationName const AppAccountDidChangeNotification = @"AppAccountDidChangeNotification";

@implementation AppAccountService

+ (instancetype)sharedInstance {
    static AppAccountService *service;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        service = [[self alloc] initPrivate];
    });
    return service;
}

- (instancetype)initPrivate {
    return [super init];
}

- (void)updateAuthenticatedUserId:(NSString *)userId {
    NSParameterAssert(NSThread.isMainThread);
    NSParameterAssert(userId.length > 0);
    [self applyUserId:userId];
}

- (void)logout {
    NSParameterAssert(NSThread.isMainThread);
    [self applyUserId:nil];
}

/// 通知不携带账号凭证；观察者收到通知后读取已提交的当前身份，避免先通知后更新造成旧身份回流。
- (void)applyUserId:(nullable NSString *)userId {
    if (_userId == userId || [_userId isEqualToString:userId]) {
        return;
    }
    _userId = [userId copy];
    [NSNotificationCenter.defaultCenter postNotificationName:AppAccountDidChangeNotification object:self];
}

@end
