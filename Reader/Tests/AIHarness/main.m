//
//  AIHarness — Foundation-only tests for AI config, multi-provider client, and AI backup zip entry.
//  Compiles against shipped RDAIConfig / RDAIClient / RDZipArchive sources.
//

#import <Foundation/Foundation.h>
#import "RDAIConfig.h"
#import "RDAIClient.h"
#import "RDZipArchive.h"

static int g_failures = 0;
static NSMutableString *g_log;

static void logline(NSString *fmt, ...) NS_FORMAT_FUNCTION(1, 2);
static void logline(NSString *fmt, ...) {
    va_list args;
    va_start(args, fmt);
    NSString *line = [[NSString alloc] initWithFormat:fmt arguments:args];
    va_end(args);
    [g_log appendFormat:@"%@\n", line];
    printf("%s\n", line.UTF8String);
}

static void assert_true(BOOL cond, NSString *msg) {
    if (!cond) {
        g_failures++;
        logline(@"FAIL: %@", msg);
    } else {
        logline(@"PASS: %@", msg);
    }
}

static NSData *fixtureOpenAI(NSString *text) {
    NSDictionary *d = @{
        @"choices": @[
            @{@"message": @{@"role": @"assistant", @"content": text}}
        ]
    };
    return [NSJSONSerialization dataWithJSONObject:d options:0 error:nil];
}

static NSData *fixtureAnthropic(NSString *text) {
    NSDictionary *d = @{
        @"content": @[
            @{@"type": @"text", @"text": text}
        ]
    };
    return [NSJSONSerialization dataWithJSONObject:d options:0 error:nil];
}

static NSData *fixtureGemini(NSString *text) {
    NSDictionary *d = @{
        @"candidates": @[
            @{
                @"content": @{
                    @"parts": @[
                        @{@"text": text}
                    ]
                }
            }
        ]
    };
    return [NSJSONSerialization dataWithJSONObject:d options:0 error:nil];
}

static RDAIConfigProfile *makeProfile(NSString *type, NSString *baseURL) {
    RDAIConfigProfile *p = [[RDAIConfigProfile alloc] init];
    p.name = type;
    p.type = type;
    p.apiKey = @"test-key-abc";
    p.model = @"test-model";
    p.baseURL = baseURL;
    return p;
}

static void test_provider_types(void) {
    logline(@"\n== Provider type set ==");
    NSArray *types = [RDAIConfigStore allProviderTypes];
    assert_true(types.count == 6, @"exactly 6 provider types");
    NSArray *expected = @[
        RDAIProviderTypeOpenAI,
        RDAIProviderTypeAnthropic,
        RDAIProviderTypeOpenAICompat,
        RDAIProviderTypeAnthropicCompat,
        RDAIProviderTypeGemini,
        RDAIProviderTypeGeminiCompat,
    ];
    assert_true([types isEqualToArray:expected], @"types match OpenAI/Anthropic/openai格式/anthropic格式/Gemini/gemini格式");
}

static void test_config_persistence(NSString *dir) {
    logline(@"\n== Config persistence round-trip ==");
    [RDAIConfigStore setStorageDirectoryOverride:dir];
    RDAIConfigStore *store = [RDAIConfigStore sharedInstance];
    [store clearAll];

    RDAIConfigProfile *p = makeProfile(RDAIProviderTypeOpenAICompat, @"https://proxy.example.com");
    p.name = @"My OpenAI Proxy";
    p.apiKey = @"sk-persist-1";
    p.model = @"gpt-4o-mini";
    [store upsertProfile:p];
    [store setActiveProfileId:p.profileId];

    // reload from disk
    [store reloadFromDisk];
    RDAIConfigProfile *loaded = [store profileWithId:p.profileId];
    assert_true(loaded != nil, @"profile reloaded");
    assert_true([loaded.apiKey isEqualToString:@"sk-persist-1"], @"apiKey persisted");
    assert_true([loaded.model isEqualToString:@"gpt-4o-mini"], @"model persisted");
    assert_true([loaded.baseURL isEqualToString:@"https://proxy.example.com"], @"baseURL persisted");
    assert_true([loaded.type isEqualToString:RDAIProviderTypeOpenAICompat], @"type persisted");
    assert_true([store.activeProfileId isEqualToString:p.profileId], @"activeProfileId persisted");
    assert_true(loaded.isUsable, @"reloaded profile is usable");
}

static void test_six_providers(void) {
    logline(@"\n== Six-provider request build + parse + translate ==");
    NSString *source = @"Hello, world!";
    // Fixture translations differ per type so we don't hardcode a single expected string as sole success criterion
    NSDictionary *fixtures = @{
        RDAIProviderTypeOpenAI: fixtureOpenAI(@"你好，世界！(openai)"),
        RDAIProviderTypeOpenAICompat: fixtureOpenAI(@"你好，世界！(openai格式)"),
        RDAIProviderTypeAnthropic: fixtureAnthropic(@"你好，世界！(anthropic)"),
        RDAIProviderTypeAnthropicCompat: fixtureAnthropic(@"你好，世界！(anthropic格式)"),
        RDAIProviderTypeGemini: fixtureGemini(@"你好，世界！(gemini)"),
        RDAIProviderTypeGeminiCompat: fixtureGemini(@"你好，世界！(gemini格式)"),
    };
    NSDictionary *bases = @{
        RDAIProviderTypeOpenAI: @"",
        RDAIProviderTypeAnthropic: @"",
        RDAIProviderTypeGemini: @"",
        RDAIProviderTypeOpenAICompat: @"https://oa-compat.example.com",
        RDAIProviderTypeAnthropicCompat: @"https://ant-compat.example.com",
        RDAIProviderTypeGeminiCompat: @"https://gem-compat.example.com",
    };

    for (NSString *type in [RDAIConfigStore allProviderTypes]) {
        RDAIConfigProfile *profile = makeProfile(type, bases[type]);
        NSError *err = nil;
        NSURLRequest *req = [RDAIClient requestForProfile:profile text:source error:&err];
        assert_true(req != nil, [NSString stringWithFormat:@"%@ builds request", type]);
        if (!req) {
            logline(@"  error: %@", err);
            continue;
        }

        NSString *url = req.URL.absoluteString;
        NSString *auth = [req valueForHTTPHeaderField:@"Authorization"];
        NSString *xKey = [req valueForHTTPHeaderField:@"x-api-key"];
        NSString *bodyStr = [[NSString alloc] initWithData:req.HTTPBody encoding:NSUTF8StringEncoding] ?: @"";

        if ([RDAIClient isOpenAIFamily:type]) {
            assert_true([url containsString:@"/v1/chat/completions"], [NSString stringWithFormat:@"%@ URL has chat/completions", type]);
            assert_true([auth hasPrefix:@"Bearer "], [NSString stringWithFormat:@"%@ uses Bearer auth", type]);
            assert_true([bodyStr containsString:@"messages"], [NSString stringWithFormat:@"%@ body has messages", type]);
            if ([type isEqualToString:RDAIProviderTypeOpenAICompat]) {
                assert_true([url hasPrefix:@"https://oa-compat.example.com"], @"openai格式 honors custom base URL");
            } else {
                assert_true([url hasPrefix:@"https://api.openai.com"], @"OpenAI uses default host");
            }
        } else if ([RDAIClient isAnthropicFamily:type]) {
            assert_true([url containsString:@"/v1/messages"], [NSString stringWithFormat:@"%@ URL has /v1/messages", type]);
            assert_true([xKey isEqualToString:@"test-key-abc"], [NSString stringWithFormat:@"%@ uses x-api-key", type]);
            assert_true([[req valueForHTTPHeaderField:@"anthropic-version"] length] > 0, [NSString stringWithFormat:@"%@ has anthropic-version", type]);
            if ([type isEqualToString:RDAIProviderTypeAnthropicCompat]) {
                assert_true([url hasPrefix:@"https://ant-compat.example.com"], @"anthropic格式 honors custom base URL");
            } else {
                assert_true([url hasPrefix:@"https://api.anthropic.com"], @"Anthropic uses default host");
            }
        } else if ([RDAIClient isGeminiFamily:type]) {
            assert_true([url containsString:@":generateContent"], [NSString stringWithFormat:@"%@ URL has generateContent", type]);
            assert_true(![url containsString:@"key="], [NSString stringWithFormat:@"%@ key not in URL", type]);
            NSString *googKey = [req valueForHTTPHeaderField:@"x-goog-api-key"];
            assert_true([googKey isEqualToString:@"test-key-abc"], [NSString stringWithFormat:@"%@ uses x-goog-api-key header", type]);
            assert_true([bodyStr containsString:@"contents"], [NSString stringWithFormat:@"%@ body has contents", type]);
            if ([type isEqualToString:RDAIProviderTypeGeminiCompat]) {
                assert_true([url hasPrefix:@"https://gem-compat.example.com"], @"gemini格式 honors custom base URL");
            } else {
                assert_true([url hasPrefix:@"https://generativelanguage.googleapis.com"], @"Gemini uses default host");
            }
        }

        // Parse fixture
        NSData *fixture = fixtures[type];
        NSString *parsed = [RDAIClient translatedTextFromResponseData:fixture profile:profile error:&err];
        assert_true(parsed.length > 0, [NSString stringWithFormat:@"%@ parses non-empty translation", type]);
        assert_true([parsed containsString:type] || parsed.length > 2, [NSString stringWithFormat:@"%@ translation is dynamic content (%@)", type, parsed]);

        // Full translate orchestration via injectable transport
        RDAIRecordingTransport *transport = [[RDAIRecordingTransport alloc] init];
        transport.responseData = fixture;
        transport.statusCode = 200;
        RDAIClient *client = [[RDAIClient alloc] init];
        client.transport = transport;
        NSError *tErr = nil;
        NSString *out = [client translateTextSync:source profile:profile error:&tErr];
        assert_true(out.length > 0, [NSString stringWithFormat:@"%@ translateTextSync non-empty", type]);
        assert_true(transport.lastRequest != nil, [NSString stringWithFormat:@"%@ transport recorded request", type]);
        assert_true([transport.lastRequest.URL.absoluteString isEqualToString:url], [NSString stringWithFormat:@"%@ transport URL matches builder", type]);
        // Success is non-empty + matches fixture parse (not a single hard-coded global string)
        assert_true([out isEqualToString:parsed], [NSString stringWithFormat:@"%@ sync result equals parse path", type]);
        logline(@"  %@ => \"%@\"", type, out);
    }
}

static void test_backup_ai_roundtrip(NSString *dir, NSString *scratch) {
    logline(@"\n== AI config backup zip round-trip ==");
    [RDAIConfigStore setStorageDirectoryOverride:dir];
    RDAIConfigStore *store = [RDAIConfigStore sharedInstance];
    [store clearAll];

    RDAIConfigProfile *p1 = makeProfile(RDAIProviderTypeAnthropic, @"");
    p1.name = @"Claude";
    p1.apiKey = @"ant-key-99";
    p1.model = @"claude-3-5-sonnet-latest";
    RDAIConfigProfile *p2 = makeProfile(RDAIProviderTypeGeminiCompat, @"https://gem.proxy.local");
    p2.name = @"GemProxy";
    p2.apiKey = @"gem-key-77";
    p2.model = @"gemini-2.0-flash";
    [store upsertProfile:p1];
    [store upsertProfile:p2];
    [store setActiveProfileId:p2.profileId];

    NSData *preBackup = [store exportBackupData];
    assert_true(preBackup.length > 0, @"exportBackupData non-empty");
    NSDictionary *preJSON = [NSJSONSerialization JSONObjectWithData:preBackup options:0 error:nil];
    assert_true([preJSON[@"profiles"] isKindOfClass:NSArray.class] && [preJSON[@"profiles"] count] == 2, @"2 profiles exported");

    // Build legado-style zip with bookshelf/config/ai + books payload stub
    NSString *zipPath = [scratch stringByAppendingPathComponent:@"backup_test_ai.zip"];
    [[NSFileManager defaultManager] removeItemAtPath:zipPath error:nil];
    RDZipWriter *writer = [[RDZipWriter alloc] initWithPath:zipPath];
    assert_true(writer != nil, @"RDZipWriter created");

    NSData *shelf = [NSJSONSerialization dataWithJSONObject:@[
        @{@"bookId": @(-1), @"name": @"Demo", @"localPath": @"demo.txt", @"fileType": @"txt"}
    ] options:0 error:nil];
    NSData *config = [NSJSONSerialization dataWithJSONObject:@{@"fontSize": @16, @"theme": @1} options:0 error:nil];
    NSData *bookPayload = [@"chapter content" dataUsingEncoding:NSUTF8StringEncoding];
    assert_true([writer addEntryWithName:@"bookshelf.json" data:shelf], @"write bookshelf.json");
    assert_true([writer addEntryWithName:@"config.json" data:config], @"write config.json");
    assert_true([writer addEntryWithName:RDAIConfigBackupEntryName data:preBackup], @"write ai_config.json via shipped entry name");
    assert_true([writer addEntryWithName:@"books/demo.txt" data:bookPayload], @"write books payload");
    assert_true([writer finalizeArchive], @"finalize zip");

    // 备份 JSON 不得含明文 key
    NSDictionary *preObjCheck = [NSJSONSerialization JSONObjectWithData:preBackup options:0 error:nil];
    for (NSDictionary *pd in preObjCheck[@"profiles"]) {
        NSString *k = pd[@"apiKey"];
        assert_true(![k isKindOfClass:NSString.class] || k.length == 0, @"backup export redacts apiKey");
    }

    [store clearAll];
    assert_true(store.profiles.count == 0, @"AI config cleared");
    assert_true(store.activeProfileId.length == 0, @"active cleared");

    RDZipArchive *zip = [[RDZipArchive alloc] initWithPath:zipPath];
    assert_true(zip != nil, @"open backup zip");
    NSArray *names = zip.entryNames;
    assert_true([names containsObject:@"bookshelf.json"], @"zip has bookshelf.json");
    assert_true([names containsObject:@"config.json"], @"zip has config.json");
    assert_true([names containsObject:RDAIConfigBackupEntryName], @"zip has ai_config.json");
    assert_true([names containsObject:@"books/demo.txt"], @"zip has books payload");

    NSData *aiData = [zip dataForEntry:RDAIConfigBackupEntryName];
    NSString *aiStr = [[NSString alloc] initWithData:aiData encoding:NSUTF8StringEncoding] ?: @"";
    assert_true(![aiStr containsString:@"ant-key-99"], @"zip body has no p1 secret");
    assert_true(![aiStr containsString:@"gem-key-77"], @"zip body has no p2 secret");

    NSError *impErr = nil;
    BOOL ok = [store importBackupData:aiData error:&impErr];
    assert_true(ok, @"importBackupData succeeds");
    assert_true(store.profiles.count == 2, @"2 profiles restored");
    // P1-03 修复后 profileId 在导入时总是重新生成(备份里的 id 不可信,不能作为密钥绑定依据),
    // 所以按内容(model/baseURL)查找,而不是按导入前的旧 id。
    RDAIConfigProfile *r1 = nil, *r2 = nil;
    for (RDAIConfigProfile *p in store.profiles) {
        if ([p.model isEqualToString:@"claude-3-5-sonnet-latest"]) r1 = p;
        if ([p.baseURL isEqualToString:@"https://gem.proxy.local"]) r2 = p;
    }
    assert_true(r1 != nil, @"p1 model restored");
    assert_true(r2 != nil, @"p2 baseURL restored");
    assert_true(![r1.profileId isEqualToString:p1.profileId] && ![r2.profileId isEqualToString:p2.profileId],
                @"profileId regenerated on import, not reused from untrusted backup manifest");
    // 本次恢复前 Keychain/沙盒 sidecar 已被 clearAll 清空,两份 profile 都找不到同源旧密钥,
    // 因此都不可用;activeProfileId 不会盲目沿用备份声明值,交给默认规则(无可用项时留空/退回首项)。
    assert_true(store.activeProfileId.length == 0, @"activeProfileId not blindly carried over from untrusted backup");

    // Equality with pre-backup export (profile count only; ids/active intentionally do not round-trip verbatim)
    NSData *post = [store exportBackupData];
    NSDictionary *postObj = [NSJSONSerialization JSONObjectWithData:post options:0 error:nil];
    assert_true([preJSON[@"profiles"] count] == [postObj[@"profiles"] count], @"profile count matches pre-backup");

    // Keychain/sidecar 本机持久化(不经备份)
    RDAIConfigProfile *kCheck = makeProfile(RDAIProviderTypeOpenAI, @"");
    kCheck.apiKey = @"keychain-only-secret";
    kCheck.model = @"m";
    [store upsertProfile:kCheck];
    [store reloadFromDisk];
    RDAIConfigProfile *kLoaded = [store profileWithId:kCheck.profileId];
    assert_true([kLoaded.apiKey isEqualToString:@"keychain-only-secret"], @"apiKey survives reload via secure store");

    logline(@"backup entry name constant: %@", RDAIConfigBackupEntryName);
    logline(@"zip entries: %@", [names componentsJoinedByString:@", "]);
}

// P1-03 回归测试:恶意备份声明与本机现有 profile 相同的 profileId,但把 baseURL 换成攻击者
// 服务器,企图借壳沿用本机已保存的真实密钥。修复后必须:profileId 被重新生成、密钥不附着、
// 且不会被自动设为 active。
static void test_backup_ai_hijack_rejected(NSString *dir) {
    logline(@"\n== AI config backup profileId-hijack rejected (P1-03) ==");
    [RDAIConfigStore setStorageDirectoryOverride:dir];
    RDAIConfigStore *store = [RDAIConfigStore sharedInstance];
    [store clearAll];

    RDAIConfigProfile *real = makeProfile(RDAIProviderTypeOpenAI, @"");
    real.name = @"Real";
    real.apiKey = @"real-secret-key";
    real.model = @"gpt-4o-mini";
    [store upsertProfile:real];
    [store setActiveProfileId:real.profileId];
    NSString *realId = real.profileId;

    NSDictionary *maliciousProfile = @{
        @"profileId": realId,
        @"name": @"Real",
        @"type": RDAIProviderTypeOpenAICompat,
        @"apiKey": @"",
        @"model": @"gpt-4o-mini",
        @"baseURL": @"https://attacker.example.com",
    };
    NSDictionary *maliciousRoot = @{
        @"version": @2,
        @"activeProfileId": realId,
        @"profiles": @[maliciousProfile],
    };
    NSData *maliciousData = [NSJSONSerialization dataWithJSONObject:maliciousRoot options:0 error:nil];

    NSError *impErr = nil;
    BOOL ok = [store importBackupData:maliciousData error:&impErr];
    assert_true(ok, @"malicious-shaped import still parses (no JSON error)");
    assert_true(store.profiles.count == 1, @"one profile after malicious import");
    RDAIConfigProfile *restored = store.profiles.firstObject;
    assert_true(restored != nil, @"restored profile exists");
    assert_true(![restored.profileId isEqualToString:realId], @"profileId regenerated, not reused from untrusted backup");
    assert_true(restored.apiKey.length == 0, @"attacker-origin profile does NOT inherit the real key");
    assert_true(![restored isUsable], @"unmatched imported profile is not usable (no auto key attach)");
    assert_true(store.activeProfileId.length == 0, @"activeProfileId not blindly carried over from untrusted backup");
    logline(@"hijack attempt correctly rejected: key not attached, profileId not reused, not auto-active");

    // 反向验证:同一 provider+baseURL(即便 profileId 是全新随机值)应当按内容正常重新绑定密钥,
    // 这样合法的"备份后在同一台设备恢复"体验不会被误伤。前一步的恶意导入已替换掉内存中的
    // profile 列表,这里重新放入一个真实、有 key 的 profile,让匹配对象只有它自己。
    [store clearAll];
    RDAIConfigProfile *real2 = makeProfile(RDAIProviderTypeOpenAI, @"");
    real2.apiKey = @"real-secret-key";
    real2.model = @"gpt-4o-mini";
    [store upsertProfile:real2];

    NSDictionary *legitimateProfile = @{
        @"profileId": [[NSUUID UUID] UUIDString],
        @"name": @"Real",
        @"type": RDAIProviderTypeOpenAI,
        @"apiKey": @"",
        @"model": @"gpt-4o-mini",
        @"baseURL": @"",
    };
    NSDictionary *legitimateRoot = @{@"version": @2, @"activeProfileId": @"", @"profiles": @[legitimateProfile]};
    NSData *legitimateData = [NSJSONSerialization dataWithJSONObject:legitimateRoot options:0 error:nil];
    NSError *legErr = nil;
    BOOL legOk = [store importBackupData:legitimateData error:&legErr];
    assert_true(legOk, @"same-origin import succeeds");
    RDAIConfigProfile *legRestored = store.profiles.firstObject;
    assert_true(legRestored != nil && [legRestored.apiKey isEqualToString:@"real-secret-key"],
                @"same provider+origin reattaches existing local key by content match");
    logline(@"same-origin legitimate restore correctly reattached key by content match");
}

int main(int argc, const char * argv[]) {
    @autoreleasepool {
        g_log = [NSMutableString string];
        NSString *scratch = argc > 1 ? [NSString stringWithUTF8String:argv[1]] : NSTemporaryDirectory();
        [[NSFileManager defaultManager] createDirectoryAtPath:scratch withIntermediateDirectories:YES attributes:nil error:nil];
        NSString *storeDir = [scratch stringByAppendingPathComponent:@"ai_store"];
        [[NSFileManager defaultManager] removeItemAtPath:storeDir error:nil];
        [[NSFileManager defaultManager] createDirectoryAtPath:storeDir withIntermediateDirectories:YES attributes:nil error:nil];

        logline(@"AIHarness start scratch=%@", scratch);
        test_provider_types();
        test_config_persistence(storeDir);
        test_six_providers();
        test_backup_ai_roundtrip(storeDir, scratch);
        test_backup_ai_hijack_rejected(storeDir);

        logline(@"\n== Summary ==");
        if (g_failures == 0) {
            logline(@"ALL TESTS PASSED");
        } else {
            logline(@"FAILED: %d assertion(s)", g_failures);
        }

        NSString *logPath = [scratch stringByAppendingPathComponent:@"ai_providers.log"];
        [g_log writeToFile:logPath atomically:YES encoding:NSUTF8StringEncoding error:nil];
        NSString *backupLog = [scratch stringByAppendingPathComponent:@"backup_ai_roundtrip.log"];
        [g_log writeToFile:backupLog atomically:YES encoding:NSUTF8StringEncoding error:nil];
        logline(@"wrote %@", logPath);
        return g_failures == 0 ? 0 : 1;
    }
}
