//
//  RDAIConfig.m
//  Reader
//
//  API Key 存 Keychain(或测试目录旁路文件);磁盘 JSON / 备份 zip 不含明文 Key
//

#import "RDAIConfig.h"
#import <Security/Security.h>

NSString * const RDAIProviderTypeOpenAI = @"OpenAI";
NSString * const RDAIProviderTypeAnthropic = @"Anthropic";
NSString * const RDAIProviderTypeOpenAICompat = @"openai格式";
NSString * const RDAIProviderTypeAnthropicCompat = @"anthropic格式";
NSString * const RDAIProviderTypeGemini = @"Gemini";
NSString * const RDAIProviderTypeGeminiCompat = @"gemini格式";
NSString * const RDAIProviderTypeMiMo = @"MiMo";

NSString * const RDAIConfigBackupEntryName = @"ai_config.json";
NSString * const RDAITtsVoiceIdentifierPrefix = @"aiTts:";
NSString * const RDAIProfileRoleTranslate = @"translate";
NSString * const RDAIProfileRoleTTS = @"tts";

static NSString * const kStoreFileName = @"ai_config.json";
static NSString * const kStoreDirName = @"AIConfig";
static NSString * const kKeychainService = @"reader.ios.ai.apikey";
static NSString * const kTestKeysFileName = @"ai_keys_sidecar.json";
static NSString *s_storageOverride = nil;

#pragma mark - Key storage

static NSString *RDAIKeychainAccount(NSString *profileId) {
    return [NSString stringWithFormat:@"profile.%@", profileId ?: @""];
}

static NSMutableDictionary *RDAITestKeyMap(void) {
    static NSMutableDictionary *map;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        map = [NSMutableDictionary dictionary];
    });
    return map;
}

static NSString *RDAITestKeysPath(void) {
    if (s_storageOverride.length == 0) {
        return nil;
    }
    return [s_storageOverride stringByAppendingPathComponent:kTestKeysFileName];
}

static void RDAIPersistTestKeys(void) {
    NSString *path = RDAITestKeysPath();
    if (!path) {
        return;
    }
    NSData *data = [NSJSONSerialization dataWithJSONObject:RDAITestKeyMap() options:0 error:nil];
    [data writeToFile:path atomically:YES];
}

static void RDAILoadTestKeys(void) {
    NSString *path = RDAITestKeysPath();
    if (!path) {
        return;
    }
    NSData *data = [NSData dataWithContentsOfFile:path];
    id json = data.length ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
    [RDAITestKeyMap() removeAllObjects];
    if ([json isKindOfClass:NSDictionary.class]) {
        [RDAITestKeyMap() addEntriesFromDictionary:json];
    }
}

/// 优先 SecItemUpdate,不存在再 SecItemAdd;绝不先删后加。成功返回 YES。
static BOOL RDAISaveAPIKey(NSString *profileId, NSString *apiKey) {
    if (profileId.length == 0) {
        return NO;
    }
    if (s_storageOverride.length > 0) {
        if (apiKey.length > 0) {
            RDAITestKeyMap()[profileId] = apiKey;
        } else {
            [RDAITestKeyMap() removeObjectForKey:profileId];
        }
        RDAIPersistTestKeys();
        return YES;
    }
    NSString *account = RDAIKeychainAccount(profileId);
    NSDictionary *query = @{
        (__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
        (__bridge id)kSecAttrService: kKeychainService,
        (__bridge id)kSecAttrAccount: account,
    };
    if (apiKey.length == 0) {
        OSStatus del = SecItemDelete((__bridge CFDictionaryRef)query);
        return (del == errSecSuccess || del == errSecItemNotFound);
    }
    NSData *data = [apiKey dataUsingEncoding:NSUTF8StringEncoding];
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

static NSString *RDAILoadAPIKey(NSString *profileId) {
    if (profileId.length == 0) {
        return @"";
    }
    if (s_storageOverride.length > 0) {
        NSString *k = RDAITestKeyMap()[profileId];
        return [k isKindOfClass:NSString.class] ? k : @"";
    }
    NSDictionary *query = @{
        (__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
        (__bridge id)kSecAttrService: kKeychainService,
        (__bridge id)kSecAttrAccount: RDAIKeychainAccount(profileId),
        (__bridge id)kSecReturnData: @YES,
        (__bridge id)kSecMatchLimit: (__bridge id)kSecMatchLimitOne,
    };
    CFTypeRef result = NULL;
    OSStatus status = SecItemCopyMatching((__bridge CFDictionaryRef)query, &result);
    if (status != errSecSuccess || !result) {
        return @"";
    }
    NSData *data = CFBridgingRelease(result);
    return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] ?: @"";
}

static void RDAIDeleteAPIKey(NSString *profileId) {
    (void)RDAISaveAPIKey(profileId, @"");
}

/// 粗粒度 origin 归一化(去首尾空白、去掉末尾斜杠),仅用于备份恢复时的密钥重新绑定判断
static NSString *RDAINormalizedOrigin(NSString *baseURL) {
    NSString *url = [baseURL stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    while ([url hasSuffix:@"/"]) {
        url = [url substringToIndex:url.length - 1];
    }
    return url.lowercaseString;
}

@implementation RDAIConfigProfile

- (instancetype)init
{
    self = [super init];
    if (self) {
        _profileId = [[NSUUID UUID] UUIDString];
        _name = @"";
        _type = RDAIProviderTypeOpenAI;
        _apiKey = @"";
        _model = @"";
        _baseURL = @"";
        _pendingConfirm = NO;
        _role = RDAIProfileRoleTranslate;
        _ttsModel = @"tts-1";
        _ttsVoice = @"alloy";
    }
    return self;
}

- (id)copyWithZone:(NSZone *)zone
{
    RDAIConfigProfile *p = [[RDAIConfigProfile allocWithZone:zone] init];
    p.profileId = self.profileId;
    p.name = self.name;
    p.type = self.type;
    p.apiKey = self.apiKey;
    p.model = self.model;
    p.baseURL = self.baseURL;
    p.pendingConfirm = self.pendingConfirm;
    p.role = self.role.length ? self.role : RDAIProfileRoleTranslate;
    p.ttsModel = self.ttsModel;
    p.ttsVoice = self.ttsVoice;
    return p;
}

- (BOOL)isTTSRole
{
    return [self.role isEqualToString:RDAIProfileRoleTTS];
}

- (BOOL)isUsable
{
    // 朗读专用配置不参与翻译
    if (self.isTTSRole) {
        return NO;
    }
    if (self.pendingConfirm) {
        return NO;
    }
    if (self.apiKey.length == 0 || self.model.length == 0) {
        return NO;
    }
    BOOL needsBase = [self.type isEqualToString:RDAIProviderTypeOpenAICompat]
        || [self.type isEqualToString:RDAIProviderTypeAnthropicCompat]
        || [self.type isEqualToString:RDAIProviderTypeGeminiCompat];
    if (needsBase && self.baseURL.length == 0) {
        return NO;
    }
    return YES;
}

- (BOOL)isTTSUsable
{
    // 仅朗读分区配置;不要求 chat model / isUsable
    if (!self.isTTSRole) {
        return NO;
    }
    if (self.pendingConfirm) {
        return NO;
    }
    if (self.apiKey.length == 0) {
        return NO;
    }
    BOOL openaiFamily = [self.type isEqualToString:RDAIProviderTypeOpenAI]
        || [self.type isEqualToString:RDAIProviderTypeOpenAICompat];
    BOOL mimo = [self.type isEqualToString:RDAIProviderTypeMiMo];
    if (!openaiFamily && !mimo) {
        return NO;
    }
    if ([self.type isEqualToString:RDAIProviderTypeOpenAICompat] && self.baseURL.length == 0) {
        return NO;
    }
    return YES;
}

- (BOOL)usesMiMoSpeechAPI
{
    if ([self.type isEqualToString:RDAIProviderTypeMiMo]) {
        return YES;
    }
    // 原生 OpenAI 一律走 /v1/audio/speech,不看模型名
    if ([self.type isEqualToString:RDAIProviderTypeOpenAI]) {
        return NO;
    }
    // openai 格式:指向小米域名,或用户明确填了 mimo TTS 模型
    NSString *base = (self.baseURL ?: @"").lowercaseString;
    if ([base containsString:@"xiaomimimo.com"]) {
        return YES;
    }
    if ([self.type isEqualToString:RDAIProviderTypeOpenAICompat]) {
        NSString *tm = (self.ttsModel ?: @"").lowercaseString;
        if ([tm hasPrefix:@"mimo"] || [tm containsString:@"mimo-"]) {
            return YES;
        }
    }
    return NO;
}

- (NSString *)ttsVoiceIdentifier
{
    return [NSString stringWithFormat:@"%@%@", RDAITtsVoiceIdentifierPrefix, self.profileId ?: @""];
}

+ (NSArray<NSString *> *)commonTTSVoices
{
    return @[@"alloy", @"echo", @"fable", @"onyx", @"nova", @"shimmer", @"ash", @"coral", @"sage"];
}

+ (NSArray<NSString *> *)commonMiMoTTSVoices
{
    // 官方内置:mimo_default / 中文 冰糖·茉莉·苏打·白桦 / 英文 Mia·Chloe·Milo·Dean
    return @[@"mimo_default", @"冰糖", @"茉莉", @"苏打", @"白桦", @"Mia", @"Chloe", @"Milo", @"Dean"];
}

/// 磁盘/备份序列化:不含 apiKey 明文
- (NSDictionary *)toDictionary
{
    return @{
        @"profileId": self.profileId ?: @"",
        @"name": self.name ?: @"",
        @"type": self.type ?: @"",
        @"apiKey": @"", // 故意留空,密钥在 Keychain
        @"model": self.model ?: @"",
        @"baseURL": self.baseURL ?: @"",
        @"hasKeychainKey": @(self.apiKey.length > 0),
        @"pendingConfirm": @(self.pendingConfirm),
        @"role": self.role.length ? self.role : RDAIProfileRoleTranslate,
        @"ttsModel": self.ttsModel.length ? self.ttsModel : ([self.type isEqualToString:RDAIProviderTypeMiMo] ? @"mimo-v2.5-tts" : @"tts-1"),
        @"ttsVoice": self.ttsVoice.length ? self.ttsVoice : ([self.type isEqualToString:RDAIProviderTypeMiMo] ? @"mimo_default" : @"alloy"),
    };
}

+ (instancetype)profileFromDictionary:(NSDictionary *)dict
{
    if (![dict isKindOfClass:NSDictionary.class]) {
        return nil;
    }
    RDAIConfigProfile *p = [[RDAIConfigProfile alloc] init];
    NSString *pid = dict[@"profileId"];
    if ([pid isKindOfClass:NSString.class] && pid.length > 0) {
        p.profileId = pid;
    }
    p.name = [dict[@"name"] isKindOfClass:NSString.class] ? dict[@"name"] : @"";
    NSString *type = [dict[@"type"] isKindOfClass:NSString.class] ? dict[@"type"] : RDAIProviderTypeOpenAI;
    if ([type isEqualToString:@"authropic"] || [type isEqualToString:@"Authropic"]) {
        type = RDAIProviderTypeAnthropic;
    } else if ([type isEqualToString:@"authropic格式"]) {
        type = RDAIProviderTypeAnthropicCompat;
    }
    p.type = type;
    // 兼容旧版明文 JSON:若有 key 先读入内存,落盘时迁入 Keychain
    NSString *legacyKey = [dict[@"apiKey"] isKindOfClass:NSString.class] ? dict[@"apiKey"] : @"";
    p.apiKey = legacyKey;
    p.model = [dict[@"model"] isKindOfClass:NSString.class] ? dict[@"model"] : @"";
    p.baseURL = [dict[@"baseURL"] isKindOfClass:NSString.class] ? dict[@"baseURL"] : @"";
    // 旧磁盘 JSON 无此字段时默认 NO,保持已确认配置可用
    id pending = dict[@"pendingConfirm"];
    if ([pending isKindOfClass:NSNumber.class]) {
        p.pendingConfirm = [(NSNumber *)pending boolValue];
    } else {
        p.pendingConfirm = NO;
    }
    BOOL isMiMo = [p.type isEqualToString:RDAIProviderTypeMiMo];
    NSString *role = [dict[@"role"] isKindOfClass:NSString.class] ? dict[@"role"] : @"";
    if ([role isEqualToString:RDAIProfileRoleTTS]) {
        p.role = RDAIProfileRoleTTS;
    } else if ([role isEqualToString:RDAIProfileRoleTranslate]) {
        p.role = RDAIProfileRoleTranslate;
    } else {
        // 旧数据无 role:按名称识别朗读引擎,其余归翻译
        if ([p.name isEqualToString:@"MiMo 朗读"]
            || [p.name isEqualToString:@"OpenAI 朗读"]
            || [p.name isEqualToString:@"OpenAI 兼容朗读"]
            || [p.name isEqualToString:@"AI 朗读"]) {
            p.role = RDAIProfileRoleTTS;
        } else {
            p.role = RDAIProfileRoleTranslate;
        }
    }
    if ([dict[@"ttsModel"] isKindOfClass:NSString.class] && [dict[@"ttsModel"] length] > 0) {
        p.ttsModel = dict[@"ttsModel"];
    } else {
        p.ttsModel = isMiMo ? @"mimo-v2.5-tts" : @"tts-1";
    }
    if ([dict[@"ttsVoice"] isKindOfClass:NSString.class] && [dict[@"ttsVoice"] length] > 0) {
        p.ttsVoice = dict[@"ttsVoice"];
    } else {
        p.ttsVoice = isMiMo ? @"mimo_default" : @"alloy";
    }
    return p;
}

@end

@interface RDAIConfigStore ()
@property (nonatomic, strong) NSMutableArray <RDAIConfigProfile *>*mutableProfiles;
@property (nonatomic, copy, readwrite, nullable) NSString *activeProfileId;
@end

@implementation RDAIConfigStore

+ (instancetype)sharedInstance
{
    static RDAIConfigStore *store = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        store = [[RDAIConfigStore alloc] init];
        [store reloadFromDisk];
    });
    return store;
}

+ (void)setStorageDirectoryOverride:(NSString *)directory
{
    s_storageOverride = [directory copy];
    if (directory.length > 0) {
        RDAILoadTestKeys();
    }
    [[self sharedInstance] reloadFromDisk];
}

+ (NSArray <NSString *>*)allProviderTypes
{
    return @[
        RDAIProviderTypeOpenAI,
        RDAIProviderTypeAnthropic,
        RDAIProviderTypeOpenAICompat,
        RDAIProviderTypeAnthropicCompat,
        RDAIProviderTypeGemini,
        RDAIProviderTypeGeminiCompat,
        RDAIProviderTypeMiMo,
    ];
}

- (instancetype)init
{
    self = [super init];
    if (self) {
        _mutableProfiles = [NSMutableArray array];
    }
    return self;
}

// 备份恢复在后台线程写入,阅读页/设置页在主线程读;@synchronized(递归)统一保护 mutableProfiles
- (NSArray <RDAIConfigProfile *>*)profiles
{
    @synchronized (self) {
        return [self.mutableProfiles copy];
    }
}

- (NSString *)storageDirectory
{
    if (s_storageOverride.length > 0) {
        return s_storageOverride;
    }
    NSString *doc = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) lastObject];
    return [doc stringByAppendingPathComponent:kStoreDirName];
}

- (NSString *)storagePath
{
    return [[self storageDirectory] stringByAppendingPathComponent:kStoreFileName];
}

- (void)p_hydrateKeysFromSecureStore
{
    BOOL migratedLegacy = NO;
    for (RDAIConfigProfile *p in self.mutableProfiles) {
        NSString *fromSecure = RDAILoadAPIKey(p.profileId);
        if (fromSecure.length > 0) {
            p.apiKey = fromSecure;
        } else if (p.apiKey.length > 0) {
            // 旧版 JSON 明文迁移到 Keychain
            if (RDAISaveAPIKey(p.profileId, p.apiKey)) {
                migratedLegacy = YES;
            }
        }
    }
    if (migratedLegacy) {
        [self saveToDisk]; // 重写 JSON,去掉明文
    }
}

- (void)reloadFromDisk
{
    @synchronized (self) {
    [self.mutableProfiles removeAllObjects];
    _activeProfileId = nil;
    if (s_storageOverride.length > 0) {
        RDAILoadTestKeys();
    }
    NSData *data = [NSData dataWithContentsOfFile:[self storagePath]];
    if (data.length == 0) {
        return;
    }
    id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    if (![json isKindOfClass:NSDictionary.class]) {
        return;
    }
    NSDictionary *root = (NSDictionary *)json;
    NSArray *list = root[@"profiles"];
    if ([list isKindOfClass:NSArray.class]) {
        for (id item in list) {
            RDAIConfigProfile *p = [RDAIConfigProfile profileFromDictionary:item];
            if (p) {
                [self.mutableProfiles addObject:p];
            }
        }
    }
    NSString *active = root[@"activeProfileId"];
    if ([active isKindOfClass:NSString.class] && active.length > 0) {
        _activeProfileId = [active copy];
    }
    [self p_hydrateKeysFromSecureStore];
    }
}

- (BOOL)saveToDisk
{
    @synchronized (self) {
        NSString *dir = [self storageDirectory];
        NSFileManager *fm = [NSFileManager defaultManager];
        if (![fm fileExistsAtPath:dir]) {
            [fm createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
        }
        // 先把内存中的 key 写入安全存储;任一条失败则中止,避免 UI 误报成功而磁盘/Keychain 不一致
        for (RDAIConfigProfile *p in self.mutableProfiles) {
            if (!RDAISaveAPIKey(p.profileId, p.apiKey ?: @"")) {
                return NO;
            }
        }
        NSData *data = [self exportBackupData];
        if (!data) {
            return NO;
        }
        return [data writeToFile:[self storagePath] atomically:YES];
    }
}

- (NSData *)exportBackupData
{
    @synchronized (self) {
        // 备份/磁盘 JSON 均不含明文 apiKey
        NSMutableArray *arr = [NSMutableArray array];
        for (RDAIConfigProfile *p in self.mutableProfiles) {
            [arr addObject:[p toDictionary]];
        }
        NSDictionary *root = @{
            @"version": @2,
            @"keysInKeychain": @YES,
            @"activeProfileId": self.activeProfileId ?: @"",
            @"profiles": arr,
        };
        return [NSJSONSerialization dataWithJSONObject:root options:NSJSONWritingPrettyPrinted error:nil];
    }
}

- (BOOL)importBackupData:(NSData *)data error:(NSError **)error
{
    if (data.length == 0) {
        if (error) {
            *error = [NSError errorWithDomain:@"RDAIConfig" code:1 userInfo:@{NSLocalizedDescriptionKey: @"空的 AI 配置"}];
        }
        return NO;
    }
    id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:error];
    if (![json isKindOfClass:NSDictionary.class]) {
        if (error && !*error) {
            *error = [NSError errorWithDomain:@"RDAIConfig" code:2 userInfo:@{NSLocalizedDescriptionKey: @"AI 配置格式错误"}];
        }
        return NO;
    }
    @synchronized (self) {
        // 备份里的 profileId 不可信:如果直接沿用,一旦与本机现有 id 撞上(即便是恶意构造的
        // "同 id、换 baseURL" 备份),旧 Keychain 密钥会被原样保留,同时把请求目标换成攻击者
        // 服务器。这里先快照导入前(可信)的 profile 列表,随后一律重新生成 profileId,
        // 密钥只按 "provider 类型 + 规范化 baseURL" 内容匹配重新绑定,而不是按不可信的 id。
        NSMutableArray <RDAIConfigProfile *>*previousProfiles = [NSMutableArray arrayWithCapacity:self.mutableProfiles.count];
        for (RDAIConfigProfile *old in self.mutableProfiles) {
            [previousProfiles addObject:[old copy]];
        }
        NSString *previousActive = [self.activeProfileId copy];

        NSDictionary *root = (NSDictionary *)json;
        NSMutableArray <RDAIConfigProfile *>*imported = [NSMutableArray array];
        NSArray *list = root[@"profiles"];
        if ([list isKindOfClass:NSArray.class]) {
            for (id item in list) {
                RDAIConfigProfile *p = [RDAIConfigProfile profileFromDictionary:item];
                if (!p) {
                    continue;
                }
                p.profileId = [[NSUUID UUID] UUIDString];
                // 导入一律待确认:即便同源 rebind 或旧版明文 key 迁入,也不得自动 isUsable/出站
                p.pendingConfirm = YES;
                if (p.apiKey.length == 0) {
                    p.apiKey = [self p_matchingKeyForType:p.type baseURL:p.baseURL amongProfiles:previousProfiles] ?: @"";
                }
                // 明文 key / rebind 的 key 都在 saveToDisk 时写入 Keychain;失败则整体 import 失败并回滚
                [imported addObject:p];
            }
        }
        // 不沿用备份 activeProfileId,也不自动选中可用项;须用户在设置中「设为当前」后才可出站。
        self.mutableProfiles = imported;
        _activeProfileId = nil;
        if ([self saveToDisk]) {
            return YES;
        }
        // 磁盘/Keychain 失败:完整回滚内存,并尽力把密钥写回导入前快照,避免 UI/运行态半应用
        self.mutableProfiles = previousProfiles;
        _activeProfileId = previousActive;
        for (RDAIConfigProfile *p in self.mutableProfiles) {
            (void)RDAISaveAPIKey(p.profileId, p.apiKey ?: @"");
        }
        // 清理本次导入生成的新 profileId 在 Keychain 中可能残留的条目
        for (RDAIConfigProfile *p in imported) {
            RDAIDeleteAPIKey(p.profileId);
        }
        if (error) {
            *error = [NSError errorWithDomain:@"RDAIConfig" code:3
                                     userInfo:@{NSLocalizedDescriptionKey: @"AI 配置写入失败,已保持导入前状态"}];
        }
        return NO;
    }
}

/// 仅按 (provider 类型, 规范化 baseURL) 在导入前的本机 profile 中找同源密钥;找不到返回 nil。
- (nullable NSString *)p_matchingKeyForType:(NSString *)type
                                     baseURL:(NSString *)baseURL
                               amongProfiles:(NSArray <RDAIConfigProfile *>*)profiles
{
    NSString *incomingOrigin = RDAINormalizedOrigin(baseURL ?: @"");
    for (RDAIConfigProfile *old in profiles) {
        if (old.apiKey.length == 0 || ![old.type isEqualToString:type]) {
            continue;
        }
        if ([RDAINormalizedOrigin(old.baseURL ?: @"") isEqualToString:incomingOrigin]) {
            return old.apiKey;
        }
    }
    return nil;
}

- (RDAIConfigProfile *)activeProfile
{
    @synchronized (self) {
        if (self.activeProfileId.length == 0) {
            // active 为空时:不回退到「首个 profile / 不可用项」;
            // 仅 soft-fallback 到第一个 isUsable(已确认且字段齐全)的项,兼容历史未写 activeId 的磁盘状态。
            // 备份导入会强制 pendingConfirm=YES 且 active=nil,故导入后此处仍返回 nil,翻译保持阻断。
            for (RDAIConfigProfile *p in self.mutableProfiles) {
                if (p.isUsable) {
                    return p;
                }
            }
            return nil;
        }
        RDAIConfigProfile *found = nil;
        for (RDAIConfigProfile *p in self.mutableProfiles) {
            if ([p.profileId isEqualToString:self.activeProfileId]) {
                found = p;
                break;
            }
        }
        return found;
    }
}

- (RDAIConfigProfile *)profileWithId:(NSString *)profileId
{
    if (profileId.length == 0) {
        return nil;
    }
    @synchronized (self) {
        for (RDAIConfigProfile *p in self.mutableProfiles) {
            if ([p.profileId isEqualToString:profileId]) {
                return p;
            }
        }
        return nil;
    }
}

- (BOOL)upsertProfile:(RDAIConfigProfile *)profile
{
    if (!profile || profile.profileId.length == 0) {
        return NO;
    }
    @synchronized (self) {
        NSInteger idx = NSNotFound;
        for (NSInteger i = 0; i < (NSInteger)self.mutableProfiles.count; i++) {
            if ([self.mutableProfiles[i].profileId isEqualToString:profile.profileId]) {
                idx = i;
                break;
            }
        }
        RDAIConfigProfile *copy = [profile copy];
        // 用户在编辑页显式保存 = 确认,清除 pending
        copy.pendingConfirm = NO;

        // 快照以便 saveToDisk 失败时完整回滚内存与密钥
        NSMutableArray <RDAIConfigProfile *>*snapshot = [NSMutableArray arrayWithCapacity:self.mutableProfiles.count];
        for (RDAIConfigProfile *old in self.mutableProfiles) {
            [snapshot addObject:[old copy]];
        }
        NSString *snapActive = [self.activeProfileId copy];

        if (idx == NSNotFound) {
            [self.mutableProfiles addObject:copy];
        } else {
            self.mutableProfiles[idx] = copy;
        }
        if (self.activeProfileId.length == 0) {
            _activeProfileId = copy.profileId;
        }
        if ([self saveToDisk]) {
            return YES;
        }
        // 回滚内存,并尽力把 Keychain 恢复为快照(含更新失败时还原旧 Key)
        self.mutableProfiles = snapshot;
        _activeProfileId = snapActive;
        for (RDAIConfigProfile *p in self.mutableProfiles) {
            (void)RDAISaveAPIKey(p.profileId, p.apiKey ?: @"");
        }
        if (idx == NSNotFound) {
            RDAIDeleteAPIKey(copy.profileId);
        }
        return NO;
    }
}

- (void)removeProfileId:(NSString *)profileId
{
    if (profileId.length == 0) {
        return;
    }
    @synchronized (self) {
        RDAIDeleteAPIKey(profileId);
        NSMutableArray *survivors = [NSMutableArray array];
        for (RDAIConfigProfile *p in self.mutableProfiles) {
            if (![p.profileId isEqualToString:profileId]) {
                [survivors addObject:p];
            }
        }
        self.mutableProfiles = survivors;
        if ([self.activeProfileId isEqualToString:profileId]) {
            // 不自动落到 pending 导入项;优先选已确认且可用的 profile
            _activeProfileId = nil;
            for (RDAIConfigProfile *p in self.mutableProfiles) {
                if (!p.pendingConfirm && p.apiKey.length > 0) {
                    _activeProfileId = p.profileId;
                    break;
                }
            }
        }
        [self saveToDisk];
    }
}

- (BOOL)activateProfileId:(NSString *)profileId
{
    @synchronized (self) {
        NSString *snapActive = [self.activeProfileId copy];
        BOOL snapPending = NO;
        RDAIConfigProfile *target = nil;
        if (profileId.length > 0) {
            for (RDAIConfigProfile *p in self.mutableProfiles) {
                if ([p.profileId isEqualToString:profileId]) {
                    target = p;
                    snapPending = p.pendingConfirm;
                    break;
                }
            }
        }
        _activeProfileId = [profileId copy];
        // 「设为当前」即用户确认:清除 pending,允许出站
        if (target) {
            target.pendingConfirm = NO;
        }
        if ([self saveToDisk]) {
            return YES;
        }
        // 磁盘失败:回滚 active 与 pending,避免会话已可翻译而 JSON 仍为待确认
        _activeProfileId = snapActive;
        if (target) {
            target.pendingConfirm = snapPending;
        }
        return NO;
    }
}

- (void)clearAll
{
    @synchronized (self) {
        for (RDAIConfigProfile *p in self.mutableProfiles) {
            RDAIDeleteAPIKey(p.profileId);
        }
        [self.mutableProfiles removeAllObjects];
        _activeProfileId = nil;
        NSString *path = [self storagePath];
        if ([[NSFileManager defaultManager] fileExistsAtPath:path]) {
            [[NSFileManager defaultManager] removeItemAtPath:path error:nil];
        }
        NSString *keysPath = RDAITestKeysPath();
        if (keysPath.length && [[NSFileManager defaultManager] fileExistsAtPath:keysPath]) {
            [[NSFileManager defaultManager] removeItemAtPath:keysPath error:nil];
        }
        [RDAITestKeyMap() removeAllObjects];
    }
}

@end
