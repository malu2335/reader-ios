//
//  RDHttpTTS.m
//  Reader
//

#import "RDHttpTTS.h"
#import <Security/Security.h>

NSString * const RDHttpTTSIdentifierPrefix = @"httpTts:";

static NSString * const kRDHttpTTSFileName = @"http_tts_engines.json";
static NSString * const kRDHttpTTSKeychainService = @"reader.ios.httptts.header";

/// 敏感 Header 名(大小写不敏感比较)
static BOOL RDHttpTTSIsSensitiveHeaderKey(NSString *key)
{
    if (key.length == 0) {
        return NO;
    }
    static NSSet *s;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        s = [NSSet setWithArray:@[
            @"authorization", @"proxy-authorization", @"cookie",
            @"x-api-key", @"x-auth-token", @"api-key", @"apikey",
        ]];
    });
    return [s containsObject:key.lowercaseString];
}

static NSString *RDHttpTTSKeychainAccount(long long engineId)
{
    return [NSString stringWithFormat:@"engine.%lld", engineId];
}

static BOOL RDHttpTTSSaveSecrets(long long engineId, NSDictionary *secrets)
{
    NSString *account = RDHttpTTSKeychainAccount(engineId);
    NSDictionary *query = @{
        (__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
        (__bridge id)kSecAttrService: kRDHttpTTSKeychainService,
        (__bridge id)kSecAttrAccount: account,
    };
    if (secrets.count == 0) {
        OSStatus del = SecItemDelete((__bridge CFDictionaryRef)query);
        return (del == errSecSuccess || del == errSecItemNotFound);
    }
    NSData *data = [NSJSONSerialization dataWithJSONObject:secrets options:0 error:nil];
    if (!data) {
        return NO;
    }
    NSDictionary *attrs = @{
        (__bridge id)kSecValueData: data,
        (__bridge id)kSecAttrAccessible: (__bridge id)kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
    };
    OSStatus status = SecItemUpdate((__bridge CFDictionaryRef)query, (__bridge CFDictionaryRef)attrs);
    if (status == errSecSuccess) {
        return YES;
    }
    if (status == errSecItemNotFound) {
        NSMutableDictionary *add = [query mutableCopy];
        [add addEntriesFromDictionary:attrs];
        status = SecItemAdd((__bridge CFDictionaryRef)add, NULL);
        return status == errSecSuccess;
    }
    return NO;
}

static NSDictionary *RDHttpTTSLoadSecrets(long long engineId)
{
    NSDictionary *query = @{
        (__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
        (__bridge id)kSecAttrService: kRDHttpTTSKeychainService,
        (__bridge id)kSecAttrAccount: RDHttpTTSKeychainAccount(engineId),
        (__bridge id)kSecReturnData: @YES,
        (__bridge id)kSecMatchLimit: (__bridge id)kSecMatchLimitOne,
    };
    CFTypeRef result = NULL;
    OSStatus status = SecItemCopyMatching((__bridge CFDictionaryRef)query, &result);
    if (status != errSecSuccess || !result) {
        return @{};
    }
    NSData *data = CFBridgingRelease(result);
    id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    return [json isKindOfClass:NSDictionary.class] ? json : @{};
}

/// 拆分公开 Header 与敏感 Header;sensitive 写入 Keychain,返回仅公开字段的 JSON 字符串
static NSString *RDHttpTTSSplitAndStoreHeader(long long engineId, NSString *headerJSON, BOOL *outOk)
{
    if (outOk) {
        *outOk = YES;
    }
    if (headerJSON.length == 0) {
        RDHttpTTSSaveSecrets(engineId, @{});
        return nil;
    }
    NSData *data = [headerJSON dataUsingEncoding:NSUTF8StringEncoding];
    id json = data.length ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
    if (![json isKindOfClass:NSDictionary.class]) {
        // 非 JSON 头:整体当敏感块存 Keychain,磁盘不留
        if (outOk) {
            *outOk = RDHttpTTSSaveSecrets(engineId, @{@"_raw": headerJSON});
        } else {
            RDHttpTTSSaveSecrets(engineId, @{@"_raw": headerJSON});
        }
        return nil;
    }
    NSMutableDictionary *pub = [NSMutableDictionary dictionary];
    NSMutableDictionary *sec = [NSMutableDictionary dictionary];
    [(NSDictionary *)json enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL *stop) {
        if (![key isKindOfClass:NSString.class]) {
            return;
        }
        NSString *val = [obj isKindOfClass:NSString.class] ? obj : [NSString stringWithFormat:@"%@", obj];
        if (RDHttpTTSIsSensitiveHeaderKey(key)) {
            sec[key] = val;
        } else {
            pub[key] = val;
        }
    }];
    BOOL ok = RDHttpTTSSaveSecrets(engineId, sec);
    if (outOk) {
        *outOk = ok;
    }
    if (pub.count == 0) {
        return nil;
    }
    NSData *out = [NSJSONSerialization dataWithJSONObject:pub options:0 error:nil];
    return out ? [[NSString alloc] initWithData:out encoding:NSUTF8StringEncoding] : nil;
}

static NSString *RDHttpTTSMergeHeaderForUse(long long engineId, NSString *publicHeaderJSON)
{
    NSMutableDictionary *merged = [NSMutableDictionary dictionary];
    if (publicHeaderJSON.length) {
        NSData *data = [publicHeaderJSON dataUsingEncoding:NSUTF8StringEncoding];
        id json = data.length ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
        if ([json isKindOfClass:NSDictionary.class]) {
            [merged addEntriesFromDictionary:json];
        }
    }
    NSDictionary *sec = RDHttpTTSLoadSecrets(engineId);
    if ([sec[@"_raw"] isKindOfClass:NSString.class] && merged.count == 0) {
        return sec[@"_raw"];
    }
    [sec enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL *stop) {
        if ([key isEqual:@"_raw"]) {
            return;
        }
        merged[key] = obj;
    }];
    if (merged.count == 0) {
        return publicHeaderJSON;
    }
    NSData *out = [NSJSONSerialization dataWithJSONObject:merged options:0 error:nil];
    return out ? [[NSString alloc] initWithData:out encoding:NSUTF8StringEncoding] : publicHeaderJSON;
}

@implementation RDHttpTTS

- (instancetype)init
{
    self = [super init];
    if (self) {
        _engineId = (long long)([[NSDate date] timeIntervalSince1970] * 1000);
        _name = @"";
        _url = @"";
        _lastUpdateTime = [[NSDate date] timeIntervalSince1970];
    }
    return self;
}

- (id)copyWithZone:(NSZone *)zone
{
    RDHttpTTS *e = [[RDHttpTTS allocWithZone:zone] init];
    e.engineId = self.engineId;
    e.name = self.name;
    e.url = self.url;
    e.contentType = self.contentType;
    e.header = self.header;
    e.concurrentRate = self.concurrentRate;
    e.lastUpdateTime = self.lastUpdateTime;
    return e;
}

- (NSString *)voiceIdentifier
{
    return [NSString stringWithFormat:@"%@%lld", RDHttpTTSIdentifierPrefix, self.engineId];
}

- (NSDictionary *)toDictionary
{
    NSMutableDictionary *d = [@{
        @"id": @(self.engineId),
        @"name": self.name ?: @"",
        @"url": self.url ?: @"",
        @"lastUpdateTime": @((long long)(self.lastUpdateTime * 1000)),
    } mutableCopy];
    if (self.contentType.length) d[@"contentType"] = self.contentType;
    if (self.header.length) d[@"header"] = self.header;
    if (self.concurrentRate.length) d[@"concurrentRate"] = self.concurrentRate;
    return d;
}

/// 解析 TTS URL 模板的 scheme/host(去掉 legado 附加与占位)
+ (NSURLComponents *)p_componentsForTTSURLTemplate:(NSString *)template
{
    if (template.length == 0) {
        return nil;
    }
    NSString *probe = template;
    NSRange brace = [probe rangeOfString:@",{"];
    if (brace.location != NSNotFound) {
        probe = [probe substringToIndex:brace.location];
    }
    for (NSString *token in @[@"{{speakText}}", @"{{speakSpeed}}", @"{speakText}", @"{speakSpeed}"]) {
        probe = [probe stringByReplacingOccurrencesOfString:token withString:@"x"];
    }
    return [NSURLComponents componentsWithString:probe];
}

/// 与 RDAIClient validateBaseURLString 同源策略:HTTPS 任意 host;HTTP 仅 loopback/LAN/.local
+ (BOOL)p_isAllowedTTSURLTemplate:(NSString *)template
{
    NSURLComponents *components = [self p_componentsForTTSURLTemplate:template];
    if (!components || components.scheme.length == 0 || components.host.length == 0) {
        return NO;
    }
    NSString *scheme = components.scheme.lowercaseString;
    NSString *host = components.host.lowercaseString;
    if ([scheme isEqualToString:@"https"]) {
        return YES;
    }
    if (![scheme isEqualToString:@"http"]) {
        return NO;
    }
    return [self p_isLANOrLoopbackHost:host];
}

+ (BOOL)p_isLANOrLoopbackHost:(NSString *)host
{
    if (host.length == 0) {
        return NO;
    }
    if ([host isEqualToString:@"localhost"] || [host isEqualToString:@"127.0.0.1"] || [host isEqualToString:@"::1"]) {
        return YES;
    }
    if ([host hasSuffix:@".local"]) {
        return YES;
    }
    NSArray <NSString *>*parts = [host componentsSeparatedByString:@"."];
    if (parts.count == 4) {
        int a = parts[0].intValue, b = parts[1].intValue;
        if (a == 10) return YES;
        if (a == 172 && b >= 16 && b <= 31) return YES;
        if (a == 192 && b == 168) return YES;
        if (a == 169 && b == 254) return YES;
    }
    return NO;
}

/// 是否为允许的 HTTP(LAN) 模板(非 HTTPS);用于出站提示(Issue 10)
+ (BOOL)isLANHTTPURLTemplate:(NSString *)template
{
    NSURLComponents *c = [self p_componentsForTTSURLTemplate:template];
    if (!c) {
        return NO;
    }
    return [c.scheme.lowercaseString isEqualToString:@"http"] && [self p_isLANOrLoopbackHost:c.host.lowercaseString];
}

/// 朗读/导入共用策略校验;拒绝公网 HTTP 与非法 scheme(含历史引擎)
+ (BOOL)validateURLTemplate:(NSString *)template error:(NSError **)error
{
    if ([self p_isAllowedTTSURLTemplate:template]) {
        return YES;
    }
    if (error) {
        *error = [NSError errorWithDomain:@"RDHttpTTS" code:20
                                userInfo:@{NSLocalizedDescriptionKey:
                                               @"HttpTTS 地址仅允许 HTTPS,或本机/局域网 HTTP(127.0.0.1、192.168.x、.local)"}];
    }
    return NO;
}

+ (instancetype)engineFromDictionary:(NSDictionary *)dict
{
    if (![dict isKindOfClass:NSDictionary.class]) {
        return nil;
    }
    NSString *name = dict[@"name"];
    NSString *url = dict[@"url"];
    if (![name isKindOfClass:NSString.class] || name.length == 0) {
        return nil;
    }
    if (![url isKindOfClass:NSString.class] || url.length == 0) {
        return nil;
    }
    // URL 策略与 AI Base 对齐:公网仅 HTTPS,LAN/loopback 允许 HTTP(P2-BE-04)
    if (![self p_isAllowedTTSURLTemplate:url]) {
        return nil;
    }
    RDHttpTTS *e = [[RDHttpTTS alloc] init];
    id idVal = dict[@"id"];
    if ([idVal isKindOfClass:NSNumber.class]) {
        e.engineId = [idVal longLongValue];
    } else if ([idVal isKindOfClass:NSString.class] && [idVal longLongValue] != 0) {
        e.engineId = [idVal longLongValue];
    }
    e.name = name;
    e.url = url;
    if ([dict[@"contentType"] isKindOfClass:NSString.class]) {
        e.contentType = dict[@"contentType"];
    }
    // header 可能是对象或字符串
    id header = dict[@"header"];
    if ([header isKindOfClass:NSString.class]) {
        e.header = header;
    } else if ([header isKindOfClass:NSDictionary.class]) {
        NSData *hd = [NSJSONSerialization dataWithJSONObject:header options:0 error:nil];
        if (hd) {
            e.header = [[NSString alloc] initWithData:hd encoding:NSUTF8StringEncoding];
        }
    }
    if ([dict[@"concurrentRate"] isKindOfClass:NSString.class]) {
        e.concurrentRate = dict[@"concurrentRate"];
    } else if ([dict[@"concurrentRate"] isKindOfClass:NSNumber.class]) {
        e.concurrentRate = [dict[@"concurrentRate"] stringValue];
    }
    id lut = dict[@"lastUpdateTime"];
    if ([lut isKindOfClass:NSNumber.class]) {
        long long ms = [lut longLongValue];
        e.lastUpdateTime = ms > 1000000000000LL ? (ms / 1000.0) : (NSTimeInterval)ms;
    }
    return e;
}

+ (NSArray<RDHttpTTS *> *)enginesFromJSONData:(NSData *)data error:(NSError **)error
{
    if (data.length == 0) {
        if (error) {
            *error = [NSError errorWithDomain:@"RDHttpTTS" code:1 userInfo:@{NSLocalizedDescriptionKey: @"空的 TTS 配置"}];
        }
        return nil;
    }
    id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:error];
    if (!json) {
        return nil;
    }
    NSMutableArray *out = [NSMutableArray array];
    if ([json isKindOfClass:NSArray.class]) {
        for (id item in (NSArray *)json) {
            RDHttpTTS *e = [self engineFromDictionary:item];
            if (e) {
                [out addObject:e];
            }
        }
    } else if ([json isKindOfClass:NSDictionary.class]) {
        // legado 单条 或 包装 { "data": [...] }
        NSDictionary *dict = (NSDictionary *)json;
        if ([dict[@"url"] isKindOfClass:NSString.class] && [dict[@"name"] isKindOfClass:NSString.class]) {
            RDHttpTTS *e = [self engineFromDictionary:dict];
            if (e) {
                [out addObject:e];
            }
        } else if ([dict[@"data"] isKindOfClass:NSArray.class]) {
            for (id item in dict[@"data"]) {
                RDHttpTTS *e = [self engineFromDictionary:item];
                if (e) {
                    [out addObject:e];
                }
            }
        }
    }
    if (out.count == 0) {
        if (error) {
            *error = [NSError errorWithDomain:@"RDHttpTTS" code:2 userInfo:@{NSLocalizedDescriptionKey: @"无法识别为阅读 HttpTTS 格式(需要 name 与 url 字段)"}];
        }
        return nil;
    }
    return out;
}

@end

#pragma mark - Store

@interface RDHttpTTSStore ()
@property (nonatomic, strong) NSMutableArray <RDHttpTTS *>*mutableEngines;
@property (nonatomic, strong) dispatch_queue_t queue;
@end

@implementation RDHttpTTSStore

+ (instancetype)sharedInstance
{
    static RDHttpTTSStore *s;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        s = [[RDHttpTTSStore alloc] init];
    });
    return s;
}

- (instancetype)init
{
    self = [super init];
    if (self) {
        _mutableEngines = [NSMutableArray array];
        _queue = dispatch_queue_create("xyz.malu2335.reader.http-tts-store", DISPATCH_QUEUE_SERIAL);
        [self reloadFromDisk];
    }
    return self;
}

- (NSString *)p_path
{
    NSString *dir = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
    return [dir stringByAppendingPathComponent:kRDHttpTTSFileName];
}

- (NSArray<RDHttpTTS *> *)engines
{
    __block NSArray *copy;
    dispatch_sync(self.queue, ^{
        copy = [self.mutableEngines copy];
    });
    return copy;
}

- (RDHttpTTS *)engineWithId:(long long)engineId
{
    __block RDHttpTTS *found = nil;
    dispatch_sync(self.queue, ^{
        for (RDHttpTTS *e in self.mutableEngines) {
            if (e.engineId == engineId) {
                found = e;
                break;
            }
        }
    });
    return found;
}

- (RDHttpTTS *)engineWithVoiceIdentifier:(NSString *)identifier
{
    if (![identifier hasPrefix:RDHttpTTSIdentifierPrefix]) {
        return nil;
    }
    long long eid = [[identifier substringFromIndex:RDHttpTTSIdentifierPrefix.length] longLongValue];
    return [self engineWithId:eid];
}

- (void)reloadFromDisk
{
    dispatch_sync(self.queue, ^{
        [self.mutableEngines removeAllObjects];
        NSData *data = [NSData dataWithContentsOfFile:[self p_path]];
        if (data.length == 0) {
            return;
        }
        id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
        NSArray *list = nil;
        if ([json isKindOfClass:NSArray.class]) {
            list = json;
        } else if ([json isKindOfClass:NSDictionary.class] && [json[@"engines"] isKindOfClass:NSArray.class]) {
            list = json[@"engines"];
        }
        BOOL needRewrite = NO;
        for (id item in list) {
            RDHttpTTS *e = [RDHttpTTS engineFromDictionary:item];
            if (!e) {
                continue;
            }
            // 迁移:磁盘上若仍含敏感 Header,拆入 Keychain 并标记重写
            if (e.header.length) {
                NSData *hd = [e.header dataUsingEncoding:NSUTF8StringEncoding];
                id hj = hd.length ? [NSJSONSerialization JSONObjectWithData:hd options:0 error:nil] : nil;
                BOOL hasSensitive = NO;
                if ([hj isKindOfClass:NSDictionary.class]) {
                    for (NSString *k in [(NSDictionary *)hj allKeys]) {
                        if (RDHttpTTSIsSensitiveHeaderKey(k)) {
                            hasSensitive = YES;
                            break;
                        }
                    }
                } else {
                    // 非 JSON 头也当敏感迁移
                    hasSensitive = YES;
                }
                if (hasSensitive) {
                    BOOL ok = YES;
                    NSString *pub = RDHttpTTSSplitAndStoreHeader(e.engineId, e.header, &ok);
                    if (ok) {
                        e.header = RDHttpTTSMergeHeaderForUse(e.engineId, pub);
                        needRewrite = YES;
                    }
                } else {
                    e.header = RDHttpTTSMergeHeaderForUse(e.engineId, e.header);
                }
            } else {
                e.header = RDHttpTTSMergeHeaderForUse(e.engineId, nil);
            }
            [self.mutableEngines addObject:e];
        }
        if (needRewrite) {
            [self p_saveUnlocked];
        }
    });
}

- (BOOL)p_saveUnlocked
{
    NSMutableArray *arr = [NSMutableArray array];
    for (RDHttpTTS *e in self.mutableEngines) {
        NSMutableDictionary *d = [[e toDictionary] mutableCopy];
        // 磁盘只存非敏感 Header;敏感值已进 Keychain
        BOOL ok = YES;
        NSString *pub = RDHttpTTSSplitAndStoreHeader(e.engineId, e.header, &ok);
        if (!ok) {
            return NO;
        }
        if (pub.length) {
            d[@"header"] = pub;
        } else {
            [d removeObjectForKey:@"header"];
        }
        [arr addObject:d];
    }
    NSData *data = [NSJSONSerialization dataWithJSONObject:@{@"engines": arr} options:NSJSONWritingPrettyPrinted error:nil];
    if (!data) {
        return NO;
    }
    BOOL wrote = [data writeToFile:[self p_path] atomically:YES];
    if (wrote) {
        // 排除 iCloud/系统备份
        [[NSURL fileURLWithPath:[self p_path]] setResourceValue:@(YES) forKey:NSURLIsExcludedFromBackupKey error:nil];
    }
    return wrote;
}

- (BOOL)upsertEngine:(RDHttpTTS *)engine
{
    if (!engine || engine.name.length == 0 || engine.url.length == 0) {
        return NO;
    }
    __block BOOL ok = NO;
    dispatch_sync(self.queue, ^{
        NSInteger idx = NSNotFound;
        for (NSInteger i = 0; i < (NSInteger)self.mutableEngines.count; i++) {
            if (self.mutableEngines[i].engineId == engine.engineId) {
                idx = i;
                break;
            }
        }
        RDHttpTTS *copy = [engine copy];
        copy.lastUpdateTime = [[NSDate date] timeIntervalSince1970];
        if (idx != NSNotFound) {
            self.mutableEngines[idx] = copy;
        } else {
            [self.mutableEngines addObject:copy];
        }
        ok = [self p_saveUnlocked];
    });
    return ok;
}

- (void)removeEngineId:(long long)engineId
{
    dispatch_sync(self.queue, ^{
        NSMutableArray *keep = [NSMutableArray array];
        for (RDHttpTTS *e in self.mutableEngines) {
            if (e.engineId != engineId) {
                [keep addObject:e];
            }
        }
        self.mutableEngines = keep;
        RDHttpTTSSaveSecrets(engineId, @{});
        [self p_saveUnlocked];
    });
}

- (NSInteger)importJSONData:(NSData *)data error:(NSError **)error
{
    NSArray <RDHttpTTS *>*list = [RDHttpTTS enginesFromJSONData:data error:error];
    if (list.count == 0) {
        return 0;
    }
    NSInteger n = 0;
    for (RDHttpTTS *e in list) {
        if ([self upsertEngine:e]) {
            n++;
        }
    }
    return n;
}

@end
