//
//  RDAITranslationTests.m
//  ReaderTests
//
//  T6 AI 恢复与取消。重点是 Phase C 新加的后台请求取消语义:
//  停止之后,在途请求必须被取消,且旧结果不得再回调给调用方去写缓存。
//

#import "RDTestSupport.h"
#import "RDAIClient.h"
#import "RDAIConfig.h"

#pragma mark - 可控延迟的假 transport

@interface RDDeferredTransport : NSObject <RDAIHTTPTransport>
@property (nonatomic, assign) NSInteger sendCount;
@property (nonatomic, assign) NSInteger cancelCount;
@property (nonatomic, strong) NSMutableArray *pendingCompletions;
@property (nonatomic, strong) NSMutableSet *cancelledTokens;
@end

@implementation RDDeferredTransport

- (instancetype)init
{
    if (self = [super init]) {
        _pendingCompletions = [NSMutableArray array];
        _cancelledTokens = [NSMutableSet set];
    }
    return self;
}

- (id)sendRequest:(NSURLRequest *)request completion:(RDAITransportCompletion)completion
{
    self.sendCount += 1;
    NSString *token = [NSString stringWithFormat:@"token-%ld", (long)self.sendCount];
    // 不立刻回调:把 completion 挂起,由用例决定何时"到货"
    [self.pendingCompletions addObject:@[token, [completion copy]]];
    return token;
}

- (void)cancelToken:(id)token
{
    self.cancelCount += 1;
    if (token) {
        [self.cancelledTokens addObject:token];
    }
}

/// 让所有挂起的请求返回一份成功响应
- (void)deliverAllWithBody:(NSString *)body
{
    NSArray *pending = [self.pendingCompletions copy];
    [self.pendingCompletions removeAllObjects];
    for (NSArray *pair in pending) {
        RDAITransportCompletion completion = pair[1];
        NSData *data = [body dataUsingEncoding:NSUTF8StringEncoding];
        NSHTTPURLResponse *response = [[NSHTTPURLResponse alloc] initWithURL:[NSURL URLWithString:@"https://example.com"]
                                                                  statusCode:200
                                                                 HTTPVersion:@"HTTP/1.1"
                                                                headerFields:nil];
        completion(data, response, nil);
    }
}

@end

#pragma mark -

@interface RDAITranslationTests : XCTestCase
@property (nonatomic, strong) id<RDAIHTTPTransport> originalTransport;
@property (nonatomic, strong) RDDeferredTransport *transport;
@end

@implementation RDAITranslationTests

- (void)setUp
{
    [super setUp];
    self.originalTransport = [RDAIClient sharedClient].transport;
    self.transport = [[RDDeferredTransport alloc] init];
    [RDAIClient sharedClient].transport = self.transport;
}

- (void)tearDown
{
    [[RDAIClient sharedClient] cancelBackgroundTranslations];
    [RDAIClient sharedClient].transport = self.originalTransport;
    [super tearDown];
}

- (RDAIConfigProfile *)p_profile
{
    RDAIConfigProfile *profile = [[RDAIConfigProfile alloc] init];
    profile.profileId = @"test-profile";
    profile.name = @"测试";
    profile.type = RDAIProviderTypeOpenAI;
    profile.apiKey = @"sk-test-key";
    profile.model = @"gpt-4o-mini";
    profile.baseURL = @"https://api.example.com";
    return profile;
}

/// 停止后台翻译:在途请求必须被 cancel,且计数归零
- (void)testCancelBackgroundTranslationsCancelsInFlightRequests
{
    RDAIConfigProfile *profile = [self p_profile];
    RDAIClient *client = [RDAIClient sharedClient];

    for (NSInteger i = 0; i < 3; i++) {
        [client translateText:[NSString stringWithFormat:@"第 %ld 段", (long)i]
                      profile:profile
                   concurrent:YES
                   completion:^(NSString *translated, NSError *error) {}];
    }
    XCTAssertEqual(self.transport.sendCount, 3, @"三次后台翻译应都已发出");
    XCTAssertEqual(client.backgroundTaskCount, 3, @"在途后台请求应被登记");

    [client cancelBackgroundTranslations];

    XCTAssertEqual(self.transport.cancelCount, 3, @"停止时必须真正 cancel 每个在途请求(P2-07)");
    XCTAssertEqual(client.backgroundTaskCount, 0, @"停止后在途计数必须归零");
}

/// 停止之后才到货的旧响应,不得再回调给调用方(否则会继续写缓存)
- (void)testResultsArrivingAfterCancelAreDropped
{
    RDAIConfigProfile *profile = [self p_profile];
    RDAIClient *client = [RDAIClient sharedClient];

    __block NSInteger callbackCount = 0;
    [client translateText:@"停止前发出的请求"
                  profile:profile
               concurrent:YES
               completion:^(NSString *translated, NSError *error) {
        callbackCount += 1;
    }];
    XCTAssertEqual(self.transport.sendCount, 1);

    [client cancelBackgroundTranslations];

    // 网络层此时才把结果送回来:代次已变,必须被丢弃
    [self.transport deliverAllWithBody:@"{\"choices\":[{\"message\":{\"content\":\"迟到的译文\"}}]}"];

    XCTAssertEqual(callbackCount, 0, @"停止后到货的旧结果不得回调,否则会继续写缓存(P2-07)");
}

/// 停止只影响已发出的那批;之后重新开启仍能正常工作
- (void)testTranslationWorksAgainAfterCancel
{
    RDAIConfigProfile *profile = [self p_profile];
    RDAIClient *client = [RDAIClient sharedClient];

    [client translateText:@"第一批" profile:profile concurrent:YES completion:^(NSString *t, NSError *e) {}];
    [client cancelBackgroundTranslations];

    __block NSString *got = nil;
    [client translateText:@"第二批"
                  profile:profile
               concurrent:YES
               completion:^(NSString *translated, NSError *error) {
        got = translated;
    }];
    XCTAssertEqual(client.backgroundTaskCount, 1, @"新一批请求应正常登记");

    [self.transport deliverAllWithBody:@"{\"choices\":[{\"message\":{\"content\":\"新译文\"}}]}"];
    XCTAssertEqualObjects(got, @"新译文", @"停止后重新开启的翻译应正常回调");
    XCTAssertEqual(client.backgroundTaskCount, 0, @"完成后应从在途集合中摘除");
}

/// 备份恢复来的 AI profile 必须是待确认状态,不能自动生效对外发请求
- (void)testRestoredProfilesArePendingConfirm
{
    RDAIConfigStore *store = [RDAIConfigStore sharedInstance];
    NSString *json = @"{\"profiles\":[{\"profileId\":\"attacker\",\"name\":\"恶意\",\"type\":\"openai\","
                      "\"model\":\"gpt-4o\",\"baseURL\":\"https://evil.example.com\",\"apiKey\":\"sk-leak\"}],"
                      "\"activeProfileId\":\"attacker\"}";
    NSError *error = nil;
    BOOL ok = [store importBackupData:[json dataUsingEncoding:NSUTF8StringEncoding] error:&error];
    XCTAssertTrue(ok, @"导入应被接受但需标记待确认,错误:%@", error);

    RDAIConfigProfile *active = [store activeProfile];
    if (active) {
        XCTAssertFalse([active.baseURL containsString:@"evil.example.com"],
                       @"备份声明的 active 不得被盲目沿用");
    }
    for (RDAIConfigProfile *profile in store.profiles) {
        if ([profile.baseURL containsString:@"evil.example.com"]) {
            XCTAssertTrue(profile.pendingConfirm, @"恢复来的 profile 必须待用户确认后才可用");
        }
    }
}

@end
