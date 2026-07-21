//
//  RDAIClient.m
//  Reader
//

#import "RDAIClient.h"

static NSString * const kRDAIErrorDomain = @"RDAIClient";

@implementation RDAIURLSessionTransport

- (id)sendRequest:(NSURLRequest *)request completion:(RDAITransportCompletion)completion
{
    // 统一响应体预算(P1-05):翻译 JSON / TTS 音频均不应无限缓冲
    static const NSUInteger kMaxAIResponseBytes = 12u * 1024u * 1024u;
    NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        NSHTTPURLResponse *http = [response isKindOfClass:NSHTTPURLResponse.class] ? (NSHTTPURLResponse *)response : nil;
        if (!error) {
            long long expected = http.expectedContentLength;
            if ((expected > 0 && expected > (long long)kMaxAIResponseBytes) || data.length > kMaxAIResponseBytes) {
                error = [NSError errorWithDomain:kRDAIErrorDomain code:46 userInfo:@{NSLocalizedDescriptionKey: @"AI 响应过大,已拒绝处理"}];
                data = nil;
            }
        }
        if (completion) {
            completion(data, http, error);
        }
    }];
    [task resume];
    return task;
}

- (void)cancelToken:(id)token
{
    if ([token isKindOfClass:NSURLSessionTask.class]) {
        [(NSURLSessionTask *)token cancel];
    }
}

@end

@implementation RDAIRecordingTransport

- (instancetype)init
{
    self = [super init];
    if (self) {
        _statusCode = 200;
    }
    return self;
}

- (id)sendRequest:(NSURLRequest *)request completion:(RDAITransportCompletion)completion
{
    self.sendCount += 1;
    self.lastRequest = request;
    if (self.errorToReturn) {
        if (completion) {
            completion(nil, nil, self.errorToReturn);
        }
        return @"rec";
    }
    NSHTTPURLResponse *resp = [[NSHTTPURLResponse alloc] initWithURL:request.URL
                                                          statusCode:self.statusCode
                                                         HTTPVersion:@"HTTP/1.1"
                                                        headerFields:@{@"Content-Type": @"application/json"}];
    if (completion) {
        completion(self.responseData, resp, nil);
    }
    return @"rec";
}

- (void)cancelToken:(id)token
{
    // no-op for fixture transport
}

@end

@interface RDAIClient ()
@property (nonatomic, strong, nullable) id inFlightToken;
@property (nonatomic, strong, nullable) id speechToken;
@property (nonatomic, strong, nullable) id modelsToken;
@property (nonatomic, assign, readwrite) BOOL isTranslating;
@property (nonatomic, assign) NSUInteger translateGeneration;
/// 后台(concurrent)请求的 token 集合与代次;两者都在 @synchronized(self) 下访问
@property (nonatomic, strong) NSMutableSet *backgroundTokens;
@property (nonatomic, assign) NSUInteger backgroundGeneration;
@end

@implementation RDAIClient

+ (instancetype)sharedClient
{
    static RDAIClient *client = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        client = [[RDAIClient alloc] init];
        client.transport = [[RDAIURLSessionTransport alloc] init];
    });
    return client;
}

- (NSMutableSet *)backgroundTokens
{
    @synchronized (self) {
        if (!_backgroundTokens) {
            _backgroundTokens = [NSMutableSet set];
        }
        return _backgroundTokens;
    }
}

- (NSUInteger)backgroundTaskCount
{
    @synchronized (self) {
        return self.backgroundTokens.count;
    }
}

- (void)cancelBackgroundTranslations
{
    NSArray *tokens = nil;
    @synchronized (self) {
        tokens = [self.backgroundTokens allObjects];
        [self.backgroundTokens removeAllObjects];
        // 代次递增:已在途的回调回来时会发现代次变了,直接丢弃,不写缓存
        self.backgroundGeneration += 1;
    }
    id<RDAIHTTPTransport> transport = self.transport;
    if (![transport respondsToSelector:@selector(cancelToken:)]) {
        return;
    }
    for (id token in tokens) {
        [transport cancelToken:token];
    }
}

- (void)cancelInFlightTranslate
{
    id token = self.inFlightToken;
    self.inFlightToken = nil;
    self.isTranslating = NO;
    self.translateGeneration += 1;
    id<RDAIHTTPTransport> transport = self.transport;
    if (token && [transport respondsToSelector:@selector(cancelToken:)]) {
        [transport cancelToken:token];
    }
}

+ (BOOL)isOpenAIFamily:(NSString *)type
{
    // MiMo 翻译走 OpenAI chat completions 协议
    return [type isEqualToString:RDAIProviderTypeOpenAI]
        || [type isEqualToString:RDAIProviderTypeOpenAICompat]
        || [type isEqualToString:RDAIProviderTypeMiMo];
}

+ (BOOL)isAnthropicFamily:(NSString *)type
{
    return [type isEqualToString:RDAIProviderTypeAnthropic] || [type isEqualToString:RDAIProviderTypeAnthropicCompat];
}

+ (BOOL)isGeminiFamily:(NSString *)type
{
    return [type isEqualToString:RDAIProviderTypeGemini] || [type isEqualToString:RDAIProviderTypeGeminiCompat];
}

+ (BOOL)isMiMoType:(NSString *)type
{
    return [type isEqualToString:RDAIProviderTypeMiMo];
}

+ (NSString *)defaultBaseURLForType:(NSString *)type
{
    if ([self isMiMoType:type]) {
        return @"https://api.xiaomimimo.com/v1";
    }
    if ([type isEqualToString:RDAIProviderTypeOpenAI] || [type isEqualToString:RDAIProviderTypeOpenAICompat]) {
        return @"https://api.openai.com";
    }
    if ([self isAnthropicFamily:type]) {
        return @"https://api.anthropic.com";
    }
    if ([self isGeminiFamily:type]) {
        return @"https://generativelanguage.googleapis.com";
    }
    return @"";
}

+ (NSString *)normalizedBaseURL:(NSString *)base
{
    NSString *url = [base stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    while ([url hasSuffix:@"/"]) {
        url = [url substringToIndex:url.length - 1];
    }
    return url;
}

/// 判断 host 是否为 loopback / RFC1918 / 链路本地 / IPv6 ULA / mDNS `.local`
+ (BOOL)p_isLoopbackOrLANHost:(NSString *)host
{
    if (host.length == 0 || host.length > 253) {
        return NO;
    }
    NSString *h = host.lowercaseString;
    if ([h isEqualToString:@"localhost"] || [h isEqualToString:@"127.0.0.1"] || [h isEqualToString:@"::1"]
        || [h isEqualToString:@"0:0:0:0:0:0:0:1"]) {
        return YES;
    }
    // 去掉 IPv6 方括号
    if ([h hasPrefix:@"["] && [h hasSuffix:@"]"] && h.length > 2) {
        h = [h substringWithRange:NSMakeRange(1, h.length - 2)];
    }
    if ([h isEqualToString:@"::1"]) {
        return YES;
    }
    // IPv6 link-local fe80::/10 与 ULA fc00::/7 (含 fd00::/8)
    if ([h containsString:@":"]) {
        if ([h hasPrefix:@"fe80:"] || [h hasPrefix:@"fe8"] || [h hasPrefix:@"fe9"]
            || [h hasPrefix:@"fea"] || [h hasPrefix:@"feb"]) {
            return YES;
        }
        if ([h hasPrefix:@"fc"] || [h hasPrefix:@"fd"]) {
            // ULA: 前 7 bit 为 1111110 → fc00::/7,即以 fc 或 fd 开头的十六进制地址
            if (h.length >= 2) {
                unichar c0 = [h characterAtIndex:0];
                unichar c1 = [h characterAtIndex:1];
                if (c0 == 'f' && (c1 == 'c' || c1 == 'd')) {
                    return YES;
                }
            }
        }
        return NO;
    }
    // mDNS / Bonjour 主机名,如 ollama.local(仅限单层 .local 后缀,限制长度与字符)
    if ([h hasSuffix:@".local"] && h.length > 6) {
        NSString *label = [h substringToIndex:h.length - 6]; // strip ".local"
        if (label.length == 0 || label.length > 63 || [label containsString:@"."]) {
            return NO;
        }
        for (NSUInteger i = 0; i < label.length; i++) {
            unichar ch = [label characterAtIndex:i];
            BOOL ok = (ch >= 'a' && ch <= 'z') || (ch >= '0' && ch <= '9') || ch == '-' || ch == '_';
            if (!ok) {
                return NO;
            }
        }
        return YES;
    }
    NSArray <NSString *>*parts = [h componentsSeparatedByString:@"."];
    if (parts.count != 4) {
        return NO;
    }
    int a = parts[0].intValue, b = parts[1].intValue, c = parts[2].intValue, d = parts[3].intValue;
    // 粗校验每段是否像数字
    for (NSString *p in parts) {
        if (p.length == 0 || p.length > 3) {
            return NO;
        }
        for (NSUInteger i = 0; i < p.length; i++) {
            unichar ch = [p characterAtIndex:i];
            if (ch < '0' || ch > '9') {
                return NO;
            }
        }
    }
    if (a < 0 || a > 255 || b < 0 || b > 255 || c < 0 || c > 255 || d < 0 || d > 255) {
        return NO;
    }
    // 127.0.0.0/8
    if (a == 127) {
        return YES;
    }
    // 10.0.0.0/8
    if (a == 10) {
        return YES;
    }
    // 172.16.0.0/12
    if (a == 172 && b >= 16 && b <= 31) {
        return YES;
    }
    // 192.168.0.0/16
    if (a == 192 && b == 168) {
        return YES;
    }
    // 169.254.0.0/16 link-local
    if (a == 169 && b == 254) {
        return YES;
    }
    return NO;
}

+ (BOOL)validateBaseURLString:(NSString *)baseURL error:(NSError **)error
{
    NSString *raw = [self normalizedBaseURL:baseURL];
    if (raw.length == 0) {
        if (error) {
            *error = [NSError errorWithDomain:kRDAIErrorDomain code:15
                                     userInfo:@{NSLocalizedDescriptionKey: @"Base URL 为空"}];
        }
        return NO;
    }
    // scheme 必填(https 或 http);不自动补全
    NSURLComponents *components = [NSURLComponents componentsWithString:raw];
    if (!components || components.scheme.length == 0) {
        if (error) {
            *error = [NSError errorWithDomain:kRDAIErrorDomain code:15
                                     userInfo:@{NSLocalizedDescriptionKey: @"Base URL 须包含 https:// 或 http:// 前缀"}];
        }
        return NO;
    }
    NSString *scheme = components.scheme.lowercaseString;
    NSString *host = components.host;
    if (host.length == 0) {
        if (error) {
            *error = [NSError errorWithDomain:kRDAIErrorDomain code:15
                                     userInfo:@{NSLocalizedDescriptionKey: @"Base URL 缺少主机名"}];
        }
        return NO;
    }
    if ([scheme isEqualToString:@"https"]) {
        return YES;
    }
    if ([scheme isEqualToString:@"http"]) {
        if ([self p_isLoopbackOrLANHost:host]) {
            return YES;
        }
        if (error) {
            *error = [NSError errorWithDomain:kRDAIErrorDomain code:16
                                     userInfo:@{NSLocalizedDescriptionKey: @"公网地址仅允许 HTTPS;HTTP 仅限本机(127.0.0.1/localhost)或局域网(用于 Ollama 等本地服务)"}];
        }
        return NO;
    }
    if (error) {
        *error = [NSError errorWithDomain:kRDAIErrorDomain code:15
                                 userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"不支持的 URL 协议: %@", scheme]}];
    }
    return NO;
}

/// 避免 Base 已含 /v1 时再拼出 /v1/v1/...
+ (NSString *)p_joinBase:(NSString *)base absolutePath:(NSString *)path
{
    base = [self normalizedBaseURL:base];
    NSString *p = path ?: @"";
    if (![p hasPrefix:@"/"]) {
        p = [@"/" stringByAppendingString:p];
    }
    // base 已以 /v1 结尾,且 path 以 /v1/ 开头 → 去掉 path 的 /v1 前缀
    NSString *lowerBase = base.lowercaseString;
    NSString *lowerPath = p.lowercaseString;
    if ([lowerBase hasSuffix:@"/v1"] && [lowerPath hasPrefix:@"/v1/"]) {
        p = [p substringFromIndex:3]; // 去掉 "/v1"
    } else if ([lowerBase hasSuffix:@"/v1beta"] && [lowerPath hasPrefix:@"/v1beta/"]) {
        p = [p substringFromIndex:7];
    }
    // base 已是完整 completions/messages 路径
    if ([lowerBase hasSuffix:@"/chat/completions"] || [lowerBase hasSuffix:@"/messages"] || [lowerBase containsString:@":generatecontent"]) {
        return base;
    }
    return [base stringByAppendingString:p];
}

+ (NSString *)translatePromptForText:(NSString *)text
{
    // 默认整段翻译;句级格式由 RDReadTranslateHelper 在 prompt 中自行约定
    return text ?: @"";
}

+ (NSURLRequest *)requestForProfile:(RDAIConfigProfile *)profile text:(NSString *)text error:(NSError **)error
{
    if (!profile.isUsable) {
        if (error) {
            *error = [NSError errorWithDomain:kRDAIErrorDomain code:10 userInfo:@{NSLocalizedDescriptionKey: @"AI 配置不完整,请先在设置中填写 API Key 与模型"}];
        }
        return nil;
    }
    if (text.length == 0) {
        if (error) {
            *error = [NSError errorWithDomain:kRDAIErrorDomain code:11 userInfo:@{NSLocalizedDescriptionKey: @"没有可翻译的文本"}];
        }
        return nil;
    }

    NSString *type = profile.type;
    BOOL isCompat = [type isEqualToString:RDAIProviderTypeOpenAICompat]
        || [type isEqualToString:RDAIProviderTypeAnthropicCompat]
        || [type isEqualToString:RDAIProviderTypeGeminiCompat];

    NSString *base = profile.baseURL.length > 0 ? profile.baseURL : [self defaultBaseURLForType:type];
    if (isCompat && profile.baseURL.length == 0) {
        if (error) {
            *error = [NSError errorWithDomain:kRDAIErrorDomain code:12 userInfo:@{NSLocalizedDescriptionKey: @"兼容格式需要填写 Base URL"}];
        }
        return nil;
    }
    base = [self normalizedBaseURL:base];
    if (![self validateBaseURLString:base error:error]) {
        return nil;
    }
    NSString *prompt = [self translatePromptForText:text];

    if ([self isOpenAIFamily:type]) {
        // 支持 base=https://api.openai.com 或 http://127.0.0.1:11434/v1 (本地 Ollama)
        NSString *urlString = [self p_joinBase:base absolutePath:@"/v1/chat/completions"];
        NSURL *url = [NSURL URLWithString:urlString];
        if (!url) {
            if (error) {
                *error = [NSError errorWithDomain:kRDAIErrorDomain code:13 userInfo:@{NSLocalizedDescriptionKey: @"无效的 Base URL"}];
            }
            return nil;
        }
        NSDictionary *body = @{
            @"model": profile.model,
            @"messages": @[
                @{@"role": @"user", @"content": prompt}
            ],
            @"temperature": @0.2,
        };
        NSData *bodyData = [NSJSONSerialization dataWithJSONObject:body options:0 error:error];
        if (!bodyData) {
            return nil;
        }
        NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:url];
        req.HTTPMethod = @"POST";
        req.HTTPBody = bodyData;
        req.timeoutInterval = 60;
        [req setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
        if ([self isMiMoType:type] || [base.lowercaseString containsString:@"xiaomimimo.com"]) {
            [self p_applyAPIKeyHeaders:req apiKey:profile.apiKey];
        } else {
            [req setValue:[NSString stringWithFormat:@"Bearer %@", profile.apiKey] forHTTPHeaderField:@"Authorization"];
        }
        return req;
    }

    if ([self isAnthropicFamily:type]) {
        NSString *urlString = [self p_joinBase:base absolutePath:@"/v1/messages"];
        NSURL *url = [NSURL URLWithString:urlString];
        if (!url) {
            if (error) {
                *error = [NSError errorWithDomain:kRDAIErrorDomain code:13 userInfo:@{NSLocalizedDescriptionKey: @"无效的 Base URL"}];
            }
            return nil;
        }
        NSDictionary *body = @{
            @"model": profile.model,
            @"max_tokens": @4096,
            @"messages": @[
                @{@"role": @"user", @"content": prompt}
            ],
        };
        NSData *bodyData = [NSJSONSerialization dataWithJSONObject:body options:0 error:error];
        if (!bodyData) {
            return nil;
        }
        NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:url];
        req.HTTPMethod = @"POST";
        req.HTTPBody = bodyData;
        req.timeoutInterval = 60;
        [req setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
        [req setValue:profile.apiKey forHTTPHeaderField:@"x-api-key"];
        [req setValue:@"2023-06-01" forHTTPHeaderField:@"anthropic-version"];
        return req;
    }

    if ([self isGeminiFamily:type]) {
        // generateContent; API Key 走 header,避免出现在 URL/代理日志
        NSString *encodedModel = [profile.model stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLPathAllowedCharacterSet]] ?: profile.model;
        NSString *path = [NSString stringWithFormat:@"/v1beta/models/%@:generateContent", encodedModel];
        NSString *urlString = [self p_joinBase:base absolutePath:path];
        NSURL *url = [NSURL URLWithString:urlString];
        if (!url) {
            if (error) {
                *error = [NSError errorWithDomain:kRDAIErrorDomain code:13 userInfo:@{NSLocalizedDescriptionKey: @"无效的 Base URL 或模型名"}];
            }
            return nil;
        }
        NSDictionary *body = @{
            @"contents": @[
                @{
                    @"parts": @[
                        @{@"text": prompt}
                    ]
                }
            ]
        };
        NSData *bodyData = [NSJSONSerialization dataWithJSONObject:body options:0 error:error];
        if (!bodyData) {
            return nil;
        }
        NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:url];
        req.HTTPMethod = @"POST";
        req.HTTPBody = bodyData;
        req.timeoutInterval = 60;
        [req setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
        [req setValue:profile.apiKey forHTTPHeaderField:@"x-goog-api-key"];
        return req;
    }

    if (error) {
        *error = [NSError errorWithDomain:kRDAIErrorDomain code:14 userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"未知的 AI 类型: %@", type]}];
    }
    return nil;
}

+ (NSString *)translatedTextFromResponseData:(NSData *)data profile:(RDAIConfigProfile *)profile error:(NSError **)error
{
    if (data.length == 0) {
        if (error) {
            *error = [NSError errorWithDomain:kRDAIErrorDomain code:20 userInfo:@{NSLocalizedDescriptionKey: @"空响应"}];
        }
        return nil;
    }
    id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:error];
    if (![json isKindOfClass:NSDictionary.class]) {
        if (error && !*error) {
            *error = [NSError errorWithDomain:kRDAIErrorDomain code:21 userInfo:@{NSLocalizedDescriptionKey: @"响应不是 JSON"}];
        }
        return nil;
    }
    NSDictionary *root = (NSDictionary *)json;
    NSString *type = profile.type;

    if ([self isOpenAIFamily:type]) {
        // choices[0].message.content
        NSArray *choices = root[@"choices"];
        if ([choices isKindOfClass:NSArray.class] && choices.count > 0) {
            NSDictionary *first = choices.firstObject;
            if ([first isKindOfClass:NSDictionary.class]) {
                NSDictionary *message = first[@"message"];
                if ([message isKindOfClass:NSDictionary.class]) {
                    id content = message[@"content"];
                    if ([content isKindOfClass:NSString.class] && [(NSString *)content length] > 0) {
                        return [(NSString *)content stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
                    }
                }
                // 部分兼容接口用 text 字段
                id text = first[@"text"];
                if ([text isKindOfClass:NSString.class] && [(NSString *)text length] > 0) {
                    return [(NSString *)text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
                }
            }
        }
        // error message from API
        NSDictionary *apiErr = root[@"error"];
        if ([apiErr isKindOfClass:NSDictionary.class]) {
            NSString *msg = apiErr[@"message"];
            if ([msg isKindOfClass:NSString.class]) {
                if (error) {
                    *error = [NSError errorWithDomain:kRDAIErrorDomain code:22 userInfo:@{NSLocalizedDescriptionKey: msg}];
                }
                return nil;
            }
        }
    }

    if ([self isAnthropicFamily:type]) {
        // content[0].text
        NSArray *content = root[@"content"];
        if ([content isKindOfClass:NSArray.class]) {
            for (id part in content) {
                if (![part isKindOfClass:NSDictionary.class]) {
                    continue;
                }
                NSString *partType = part[@"type"];
                id text = part[@"text"];
                if ((![partType isKindOfClass:NSString.class] || [partType isEqualToString:@"text"])
                    && [text isKindOfClass:NSString.class] && [(NSString *)text length] > 0) {
                    return [(NSString *)text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
                }
            }
        }
        NSDictionary *apiErr = root[@"error"];
        if ([apiErr isKindOfClass:NSDictionary.class]) {
            NSString *msg = apiErr[@"message"];
            if ([msg isKindOfClass:NSString.class]) {
                if (error) {
                    *error = [NSError errorWithDomain:kRDAIErrorDomain code:22 userInfo:@{NSLocalizedDescriptionKey: msg}];
                }
                return nil;
            }
        }
    }

    if ([self isGeminiFamily:type]) {
        // candidates[0].content.parts[0].text
        NSArray *candidates = root[@"candidates"];
        if ([candidates isKindOfClass:NSArray.class] && candidates.count > 0) {
            NSDictionary *cand = candidates.firstObject;
            if ([cand isKindOfClass:NSDictionary.class]) {
                NSDictionary *content = cand[@"content"];
                if ([content isKindOfClass:NSDictionary.class]) {
                    NSArray *parts = content[@"parts"];
                    if ([parts isKindOfClass:NSArray.class]) {
                        for (id part in parts) {
                            if (![part isKindOfClass:NSDictionary.class]) {
                                continue;
                            }
                            id text = part[@"text"];
                            if ([text isKindOfClass:NSString.class] && [(NSString *)text length] > 0) {
                                return [(NSString *)text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
                            }
                        }
                    }
                }
            }
        }
        NSDictionary *apiErr = root[@"error"];
        if ([apiErr isKindOfClass:NSDictionary.class]) {
            NSString *msg = apiErr[@"message"];
            if ([msg isKindOfClass:NSString.class]) {
                if (error) {
                    *error = [NSError errorWithDomain:kRDAIErrorDomain code:22 userInfo:@{NSLocalizedDescriptionKey: msg}];
                }
                return nil;
            }
        }
    }

    if (error) {
        *error = [NSError errorWithDomain:kRDAIErrorDomain code:23 userInfo:@{NSLocalizedDescriptionKey: @"无法从响应中解析译文"}];
    }
    return nil;
}

- (void)translateText:(NSString *)text
              profile:(RDAIConfigProfile *)profile
           completion:(void (^)(NSString * _Nullable, NSError * _Nullable))completion
{
    [self translateText:text profile:profile concurrent:NO completion:completion];
}

- (void)translateText:(NSString *)text
              profile:(RDAIConfigProfile *)profile
           concurrent:(BOOL)concurrent
           completion:(void (^)(NSString * _Nullable, NSError * _Nullable))completion
{
    if (!concurrent) {
        // 前台/手动:取消上一次,避免连点乱序
        [self cancelInFlightTranslate];
    }
    NSError *buildError = nil;
    NSURLRequest *request = [[self class] requestForProfile:profile text:text error:&buildError];
    if (!request) {
        if (completion) {
            completion(nil, buildError);
        }
        return;
    }
    id<RDAIHTTPTransport> transport = self.transport ?: [[RDAIURLSessionTransport alloc] init];
    NSUInteger generation = concurrent ? 0 : self.translateGeneration;
    __block NSUInteger bgGeneration = 0;
    if (concurrent) {
        @synchronized (self) {
            bgGeneration = self.backgroundGeneration;
        }
    }
    else {
        self.isTranslating = YES;
    }
    __block id sentToken = nil;
    __block BOOL completedInline = NO;
    __weak typeof(self) weakSelf = self;
    id token = [transport sendRequest:request completion:^(NSData *data, NSHTTPURLResponse *response, NSError *error) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!concurrent) {
            if (!self || generation != self.translateGeneration) {
                return; // 已取消/被替换
            }
            self.inFlightToken = nil;
            self.isTranslating = NO;
        } else {
            if (!self) {
                return;
            }
            // 后台请求:先摘掉自己的 token,再确认代次没被 cancelBackgroundTranslations 顶掉
            @synchronized (self) {
                if (sentToken) {
                    [self.backgroundTokens removeObject:sentToken];
                }
                else {
                    // 同步 transport:回调跑在 sendRequest 内部,此时还没拿到 token,
                    // 标记一下,避免事后又把一个已完成的 token 登记进集合
                    completedInline = YES;
                }
                if (bgGeneration != self.backgroundGeneration) {
                    return; // 已停止,不回调、不写缓存(P2-07)
                }
            }
        }
        if (error) {
            if ([error.domain isEqualToString:NSURLErrorDomain] && error.code == NSURLErrorCancelled) {
                if (completion) {
                    completion(nil, error);
                }
                return;
            }
            NSError *friendly = error;
            if ([error.domain isEqualToString:NSURLErrorDomain]) {
                NSString *msg = nil;
                if (error.code == NSURLErrorAppTransportSecurityRequiresSecureConnection) {
                    msg = @"网络被系统安全策略拦截:HTTP 需在 Info.plist 允许,或改用 HTTPS";
                } else if (error.code == NSURLErrorTimedOut) {
                    msg = @"翻译超时,请检查网络或 API 地址";
                } else if (error.code == NSURLErrorCannotConnectToHost || error.code == NSURLErrorNetworkConnectionLost) {
                    msg = [NSString stringWithFormat:@"无法连接翻译服务(%@)", error.localizedDescription ?: @"网络错误"];
                } else if (error.code == NSURLErrorNotConnectedToInternet) {
                    msg = @"当前无网络连接";
                }
                if (msg) {
                    friendly = [NSError errorWithDomain:kRDAIErrorDomain code:error.code userInfo:@{NSLocalizedDescriptionKey: msg}];
                }
            }
            if (completion) {
                completion(nil, friendly);
            }
            return;
        }
        if (response && response.statusCode >= 400) {
            NSError *parseErr = nil;
            (void)[[self class] translatedTextFromResponseData:data profile:profile error:&parseErr];
            NSError *httpErr = parseErr;
            if (!httpErr) {
                NSString *bodyHint = @"";
                if (data.length > 0 && data.length < 400) {
                    NSString *raw = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
                    if (raw.length) {
                        bodyHint = [NSString stringWithFormat:@": %@", raw];
                    }
                }
                httpErr = [NSError errorWithDomain:kRDAIErrorDomain
                                              code:response.statusCode
                                          userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"翻译服务返回错误(%ld)%@", (long)response.statusCode, bodyHint]}];
            }
            if (completion) {
                completion(nil, httpErr);
            }
            return;
        }
        NSError *parseError = nil;
        NSString *result = [[self class] translatedTextFromResponseData:data profile:profile error:&parseError];
        if (completion) {
            completion(result, result ? nil : parseError);
        }
    }];
    if (!concurrent) {
        self.inFlightToken = token;
        return;
    }
    sentToken = token;
    if (!token || completedInline) {
        return;
    }
    @synchronized (self) {
        if (bgGeneration == self.backgroundGeneration) {
            [self.backgroundTokens addObject:token];
        }
    }
}

- (NSString *)translateTextSync:(NSString *)text profile:(RDAIConfigProfile *)profile error:(NSError **)error
{
    __block NSString *result = nil;
    __block NSError *outError = nil;
    dispatch_semaphore_t sema = dispatch_semaphore_create(0);
    [self translateText:text profile:profile completion:^(NSString *translated, NSError *err) {
        result = translated;
        outError = err;
        dispatch_semaphore_signal(sema);
    }];
    // 夹具 transport 同步回调;真实网络给合理超时
    long wait = dispatch_semaphore_wait(sema, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(60 * NSEC_PER_SEC)));
    if (wait != 0) {
        if (error) {
            *error = [NSError errorWithDomain:kRDAIErrorDomain code:30 userInfo:@{NSLocalizedDescriptionKey: @"翻译超时"}];
        }
        return nil;
    }
    if (error) {
        *error = outError;
    }
    return result;
}

#pragma mark - List models / Test

/// 为 MiMo 等端点同时附带 Bearer 与 api-key,兼容两种鉴权
+ (void)p_applyAPIKeyHeaders:(NSMutableURLRequest *)req apiKey:(NSString *)apiKey
{
    if (apiKey.length == 0) {
        return;
    }
    [req setValue:[NSString stringWithFormat:@"Bearer %@", apiKey] forHTTPHeaderField:@"Authorization"];
    [req setValue:apiKey forHTTPHeaderField:@"api-key"];
}

+ (NSString *)p_resolvedBaseForProfile:(RDAIConfigProfile *)profile error:(NSError **)error
{
    NSString *type = profile.type;
    BOOL isCompat = [type isEqualToString:RDAIProviderTypeOpenAICompat]
        || [type isEqualToString:RDAIProviderTypeAnthropicCompat]
        || [type isEqualToString:RDAIProviderTypeGeminiCompat];
    NSString *base = profile.baseURL.length > 0 ? profile.baseURL : [self defaultBaseURLForType:type];
    if (isCompat && profile.baseURL.length == 0) {
        if (error) {
            *error = [NSError errorWithDomain:kRDAIErrorDomain code:12 userInfo:@{NSLocalizedDescriptionKey: @"兼容格式需要填写 Base URL"}];
        }
        return nil;
    }
    base = [self normalizedBaseURL:base];
    if (![self validateBaseURLString:base error:error]) {
        return nil;
    }
    return base;
}

+ (NSURLRequest *)listModelsRequestForProfile:(RDAIConfigProfile *)profile error:(NSError **)error
{
    if (profile.apiKey.length == 0) {
        if (error) {
            *error = [NSError errorWithDomain:kRDAIErrorDomain code:50 userInfo:@{NSLocalizedDescriptionKey: @"请先填写 API Key"}];
        }
        return nil;
    }
    NSString *base = [self p_resolvedBaseForProfile:profile error:error];
    if (!base) {
        return nil;
    }
    NSString *type = profile.type;
    NSString *urlString = nil;
    NSMutableURLRequest *req = nil;

    if ([self isOpenAIFamily:type] || [self isMiMoType:type]) {
        urlString = [self p_joinBase:base absolutePath:@"/v1/models"];
        NSURL *url = [NSURL URLWithString:urlString];
        if (!url) {
            if (error) {
                *error = [NSError errorWithDomain:kRDAIErrorDomain code:13 userInfo:@{NSLocalizedDescriptionKey: @"无效的 Base URL"}];
            }
            return nil;
        }
        req = [NSMutableURLRequest requestWithURL:url];
        req.HTTPMethod = @"GET";
        req.timeoutInterval = 30;
        if ([self isMiMoType:type] || [base.lowercaseString containsString:@"xiaomimimo.com"]) {
            [self p_applyAPIKeyHeaders:req apiKey:profile.apiKey];
        } else {
            [req setValue:[NSString stringWithFormat:@"Bearer %@", profile.apiKey] forHTTPHeaderField:@"Authorization"];
        }
        return req;
    }

    if ([self isAnthropicFamily:type]) {
        urlString = [self p_joinBase:base absolutePath:@"/v1/models"];
        NSURL *url = [NSURL URLWithString:urlString];
        if (!url) {
            if (error) {
                *error = [NSError errorWithDomain:kRDAIErrorDomain code:13 userInfo:@{NSLocalizedDescriptionKey: @"无效的 Base URL"}];
            }
            return nil;
        }
        req = [NSMutableURLRequest requestWithURL:url];
        req.HTTPMethod = @"GET";
        req.timeoutInterval = 30;
        [req setValue:profile.apiKey forHTTPHeaderField:@"x-api-key"];
        [req setValue:@"2023-06-01" forHTTPHeaderField:@"anthropic-version"];
        return req;
    }

    if ([self isGeminiFamily:type]) {
        urlString = [self p_joinBase:base absolutePath:@"/v1beta/models"];
        NSURL *url = [NSURL URLWithString:urlString];
        if (!url) {
            if (error) {
                *error = [NSError errorWithDomain:kRDAIErrorDomain code:13 userInfo:@{NSLocalizedDescriptionKey: @"无效的 Base URL"}];
            }
            return nil;
        }
        req = [NSMutableURLRequest requestWithURL:url];
        req.HTTPMethod = @"GET";
        req.timeoutInterval = 30;
        [req setValue:profile.apiKey forHTTPHeaderField:@"x-goog-api-key"];
        return req;
    }

    if (error) {
        *error = [NSError errorWithDomain:kRDAIErrorDomain code:14 userInfo:@{NSLocalizedDescriptionKey: @"当前类型不支持探测模型列表"}];
    }
    return nil;
}

+ (NSArray <NSString *>*)modelIdsFromListResponseData:(NSData *)data
                                              profile:(RDAIConfigProfile *)profile
                                                error:(NSError **)error
{
    if (data.length == 0) {
        if (error) {
            *error = [NSError errorWithDomain:kRDAIErrorDomain code:51 userInfo:@{NSLocalizedDescriptionKey: @"模型列表为空"}];
        }
        return nil;
    }
    id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    if (![json isKindOfClass:NSDictionary.class] && ![json isKindOfClass:NSArray.class]) {
        if (error) {
            *error = [NSError errorWithDomain:kRDAIErrorDomain code:51 userInfo:@{NSLocalizedDescriptionKey: @"模型列表响应不是 JSON"}];
        }
        return nil;
    }
    NSMutableArray <NSString *>*ids = [NSMutableArray array];
    void (^addId)(NSString *) = ^(NSString *mid) {
        if (![mid isKindOfClass:NSString.class] || mid.length == 0) {
            return;
        }
        // Gemini 返回 models/xxx
        if ([mid hasPrefix:@"models/"]) {
            mid = [mid substringFromIndex:7];
        }
        if (![ids containsObject:mid]) {
            [ids addObject:mid];
        }
    };

    if ([json isKindOfClass:NSDictionary.class]) {
        NSDictionary *root = (NSDictionary *)json;
        if (root[@"error"]) {
            NSString *msg = nil;
            id err = root[@"error"];
            if ([err isKindOfClass:NSDictionary.class]) {
                msg = err[@"message"] ?: err[@"status"];
            } else if ([err isKindOfClass:NSString.class]) {
                msg = err;
            }
            if (error) {
                *error = [NSError errorWithDomain:kRDAIErrorDomain code:52 userInfo:@{NSLocalizedDescriptionKey: msg.length ? msg : @"探测模型失败"}];
            }
            return nil;
        }
        // OpenAI / MiMo / Anthropic: { data: [ { id: } ] }
        NSArray *dataArr = root[@"data"];
        if ([dataArr isKindOfClass:NSArray.class]) {
            for (id item in dataArr) {
                if ([item isKindOfClass:NSDictionary.class]) {
                    addId(item[@"id"] ?: item[@"name"]);
                } else if ([item isKindOfClass:NSString.class]) {
                    addId(item);
                }
            }
        }
        // Gemini: { models: [ { name: "models/xxx" } ] }
        NSArray *models = root[@"models"];
        if ([models isKindOfClass:NSArray.class]) {
            for (id item in models) {
                if ([item isKindOfClass:NSDictionary.class]) {
                    addId(item[@"name"] ?: item[@"id"] ?: item[@"displayName"]);
                }
            }
        }
    } else if ([json isKindOfClass:NSArray.class]) {
        for (id item in (NSArray *)json) {
            if ([item isKindOfClass:NSDictionary.class]) {
                addId(item[@"id"] ?: item[@"name"]);
            } else if ([item isKindOfClass:NSString.class]) {
                addId(item);
            }
        }
    }

    if (ids.count == 0) {
        if (error) {
            *error = [NSError errorWithDomain:kRDAIErrorDomain code:51 userInfo:@{NSLocalizedDescriptionKey: @"未解析到任何模型 id"}];
        }
        return nil;
    }
    [ids sortUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
    return ids;
}

- (void)listModelsForProfile:(RDAIConfigProfile *)profile
                  completion:(void (^)(NSArray<NSString *> *, NSError *))completion
{
    @synchronized (self) {
        if (self.modelsToken) {
            [self.transport cancelToken:self.modelsToken];
            self.modelsToken = nil;
        }
    }
    NSError *reqErr = nil;
    NSURLRequest *req = [[self class] listModelsRequestForProfile:profile error:&reqErr];
    if (!req) {
        if (completion) {
            completion(nil, reqErr);
        }
        return;
    }
    __weak typeof(self) weakSelf = self;
    id token = [self.transport sendRequest:req completion:^(NSData *data, NSHTTPURLResponse *response, NSError *error) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) {
            return;
        }
        @synchronized (self) {
            if (self.modelsToken == token) {
                self.modelsToken = nil;
            }
        }
        if (error) {
            if (error.code == NSURLErrorCancelled) {
                return;
            }
            if (completion) {
                dispatch_async(dispatch_get_main_queue(), ^{ completion(nil, error); });
            }
            return;
        }
        NSInteger code = response.statusCode;
        if (code < 200 || code >= 300) {
            NSString *msg = data.length ? [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] : [NSString stringWithFormat:@"HTTP %ld", (long)code];
            id json = data.length ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
            if ([json isKindOfClass:NSDictionary.class]) {
                id err = json[@"error"];
                if ([err isKindOfClass:NSDictionary.class] && [err[@"message"] isKindOfClass:NSString.class]) {
                    msg = err[@"message"];
                }
            }
            if (completion) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    completion(nil, [NSError errorWithDomain:kRDAIErrorDomain code:code userInfo:@{NSLocalizedDescriptionKey: msg ?: @"探测失败"}]);
                });
            }
            return;
        }
        NSError *parseErr = nil;
        NSArray *models = [[self class] modelIdsFromListResponseData:data profile:profile error:&parseErr];
        if (completion) {
            dispatch_async(dispatch_get_main_queue(), ^{ completion(models, models ? nil : parseErr); });
        }
    }];
    @synchronized (self) {
        self.modelsToken = token;
    }
}

- (void)testProfile:(RDAIConfigProfile *)profile
         completion:(void (^)(NSString *, NSError *))completion
{
    // 构造可请求的临时 profile(忽略 pending,仅校验字段)
    RDAIConfigProfile *p = [profile copy];
    p.pendingConfirm = NO;
    if (p.isTTSRole) {
        if (completion) {
            completion(nil, [NSError errorWithDomain:kRDAIErrorDomain code:53 userInfo:@{NSLocalizedDescriptionKey: @"朗读配置请用试听验证,翻译测试仅用于翻译服务"}]);
        }
        return;
    }
    if (p.apiKey.length == 0 || p.model.length == 0) {
        if (completion) {
            completion(nil, [NSError errorWithDomain:kRDAIErrorDomain code:10 userInfo:@{NSLocalizedDescriptionKey: @"请先填写 API Key 与模型名"}]);
        }
        return;
    }
    // 短句探测:要求返回非空
    NSString *sample = @"请只回复两个字:成功";
    [self translateText:sample profile:p concurrent:YES completion:^(NSString *translated, NSError *error) {
        if (error) {
            if (completion) {
                completion(nil, error);
            }
            return;
        }
        if (translated.length == 0) {
            if (completion) {
                completion(nil, [NSError errorWithDomain:kRDAIErrorDomain code:54 userInfo:@{NSLocalizedDescriptionKey: @"服务返回空内容"}]);
            }
            return;
        }
        if (completion) {
            completion(translated, nil);
        }
    }];
}

#pragma mark - AI TTS


+ (NSURLRequest *)speechRequestForProfile:(RDAIConfigProfile *)profile text:(NSString *)text error:(NSError **)error
{
    if (!profile.isTTSUsable) {
        if (error) {
            *error = [NSError errorWithDomain:kRDAIErrorDomain code:40 userInfo:@{NSLocalizedDescriptionKey: @"当前 AI 配置不可用于朗读(需可用的 OpenAI/兼容或 MiMo 配置)"}];
        }
        return nil;
    }
    NSString *speak = [text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (speak.length == 0) {
        if (error) {
            *error = [NSError errorWithDomain:kRDAIErrorDomain code:41 userInfo:@{NSLocalizedDescriptionKey: @"没有可朗读的文本"}];
        }
        return nil;
    }
    if (speak.length > 4000) {
        speak = [speak substringToIndex:4000];
    }
    NSString *base = profile.baseURL.length > 0 ? profile.baseURL : [self defaultBaseURLForType:profile.type];
    base = [self normalizedBaseURL:base];
    if (![self validateBaseURLString:base error:error]) {
        return nil;
    }

    if (profile.usesMiMoSpeechAPI) {
        // 小米 MiMo-V2.5-TTS:POST /v1/chat/completions
        // 合成文本必须放在 role=assistant;可选 user 指令控制风格
        NSString *urlString = [self p_joinBase:base absolutePath:@"/v1/chat/completions"];
        NSURL *url = [NSURL URLWithString:urlString];
        if (!url) {
            if (error) {
                *error = [NSError errorWithDomain:kRDAIErrorDomain code:13 userInfo:@{NSLocalizedDescriptionKey: @"无效的 Base URL"}];
            }
            return nil;
        }
        NSString *ttsModel = profile.ttsModel.length ? profile.ttsModel : @"mimo-v2.5-tts";
        NSString *ttsVoice = profile.ttsVoice.length ? profile.ttsVoice : @"mimo_default";
        NSDictionary *body = @{
            @"model": ttsModel,
            @"messages": @[
                @{@"role": @"assistant", @"content": speak},
            ],
            @"audio": @{
                @"format": @"mp3",
                @"voice": ttsVoice,
            },
            @"stream": @NO,
        };
        NSData *bodyData = [NSJSONSerialization dataWithJSONObject:body options:0 error:error];
        if (!bodyData) {
            return nil;
        }
        NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:url];
        req.HTTPMethod = @"POST";
        req.HTTPBody = bodyData;
        req.timeoutInterval = 120;
        [req setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
        [self p_applyAPIKeyHeaders:req apiKey:profile.apiKey];
        return req;
    }

    // OpenAI 兼容 /v1/audio/speech
    NSString *urlString = [self p_joinBase:base absolutePath:@"/v1/audio/speech"];
    NSURL *url = [NSURL URLWithString:urlString];
    if (!url) {
        if (error) {
            *error = [NSError errorWithDomain:kRDAIErrorDomain code:13 userInfo:@{NSLocalizedDescriptionKey: @"无效的 Base URL"}];
        }
        return nil;
    }
    NSString *ttsModel = profile.ttsModel.length ? profile.ttsModel : @"tts-1";
    NSString *ttsVoice = profile.ttsVoice.length ? profile.ttsVoice : @"alloy";
    NSDictionary *body = @{
        @"model": ttsModel,
        @"input": speak,
        @"voice": ttsVoice,
        @"response_format": @"mp3",
    };
    NSData *bodyData = [NSJSONSerialization dataWithJSONObject:body options:0 error:error];
    if (!bodyData) {
        return nil;
    }
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:url];
    req.HTTPMethod = @"POST";
    req.HTTPBody = bodyData;
    req.timeoutInterval = 90;
    [req setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    [req setValue:[NSString stringWithFormat:@"Bearer %@", profile.apiKey] forHTTPHeaderField:@"Authorization"];
    return req;
}

+ (NSData *)audioDataFromChatSpeechResponse:(NSData *)data error:(NSError **)error
{
    if (data.length == 0) {
        if (error) {
            *error = [NSError errorWithDomain:kRDAIErrorDomain code:45 userInfo:@{NSLocalizedDescriptionKey: @"TTS 响应为空"}];
        }
        return nil;
    }
    // base64 音频 JSON 体积上限(解码前)
    static const NSUInteger kMaxChatSpeechJSONBytes = 10u * 1024u * 1024u;
    if (data.length > kMaxChatSpeechJSONBytes) {
        if (error) {
            *error = [NSError errorWithDomain:kRDAIErrorDomain code:46 userInfo:@{NSLocalizedDescriptionKey: @"TTS JSON 过大"}];
        }
        return nil;
    }
    id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    if (![json isKindOfClass:NSDictionary.class]) {
        if (error) {
            *error = [NSError errorWithDomain:kRDAIErrorDomain code:45 userInfo:@{NSLocalizedDescriptionKey: @"TTS 响应不是 JSON"}];
        }
        return nil;
    }
    NSDictionary *root = (NSDictionary *)json;
    // 错误体
    id errObj = root[@"error"];
    if (errObj) {
        NSString *msg = nil;
        if ([errObj isKindOfClass:NSDictionary.class]) {
            msg = errObj[@"message"] ?: errObj[@"code"];
        } else if ([errObj isKindOfClass:NSString.class]) {
            msg = (NSString *)errObj;
        }
        if (error) {
            *error = [NSError errorWithDomain:kRDAIErrorDomain code:42 userInfo:@{NSLocalizedDescriptionKey: msg.length ? msg : @"TTS 服务返回错误"}];
        }
        return nil;
    }
    NSArray *choices = root[@"choices"];
    if (![choices isKindOfClass:NSArray.class] || choices.count == 0) {
        if (error) {
            *error = [NSError errorWithDomain:kRDAIErrorDomain code:45 userInfo:@{NSLocalizedDescriptionKey: @"TTS 响应缺少 choices"}];
        }
        return nil;
    }
    NSDictionary *choice0 = choices.firstObject;
    if (![choice0 isKindOfClass:NSDictionary.class]) {
        if (error) {
            *error = [NSError errorWithDomain:kRDAIErrorDomain code:45 userInfo:@{NSLocalizedDescriptionKey: @"TTS choices 格式错误"}];
        }
        return nil;
    }
    NSDictionary *message = choice0[@"message"];
    if (![message isKindOfClass:NSDictionary.class]) {
        if (error) {
            *error = [NSError errorWithDomain:kRDAIErrorDomain code:45 userInfo:@{NSLocalizedDescriptionKey: @"TTS 响应缺少 message"}];
        }
        return nil;
    }
    NSDictionary *audio = message[@"audio"];
    NSString *b64 = nil;
    if ([audio isKindOfClass:NSDictionary.class]) {
        id d = audio[@"data"];
        if ([d isKindOfClass:NSString.class]) {
            b64 = (NSString *)d;
        }
    }
    // 兼容少数实现把 audio 直接当 base64 字符串
    if (b64.length == 0 && [audio isKindOfClass:NSString.class]) {
        b64 = (NSString *)audio;
    }
    if (b64.length == 0) {
        if (error) {
            *error = [NSError errorWithDomain:kRDAIErrorDomain code:45 userInfo:@{NSLocalizedDescriptionKey: @"TTS 响应缺少 audio.data"}];
        }
        return nil;
    }
    // 去掉可能的 data:audio/...;base64, 前缀
    NSRange comma = [b64 rangeOfString:@","];
    if ([b64 hasPrefix:@"data:"] && comma.location != NSNotFound) {
        b64 = [b64 substringFromIndex:comma.location + 1];
    }
    NSData *audioData = [[NSData alloc] initWithBase64EncodedString:b64 options:NSDataBase64DecodingIgnoreUnknownCharacters];
    if (audioData.length < 32) {
        if (error) {
            *error = [NSError errorWithDomain:kRDAIErrorDomain code:44 userInfo:@{NSLocalizedDescriptionKey: @"TTS 音频解码失败或过短"}];
        }
        return nil;
    }
    return audioData;
}

- (void)cancelInFlightSpeech
{
    id token = nil;
    @synchronized (self) {
        token = self.speechToken;
        self.speechToken = nil;
    }
    if (token) {
        [self.transport cancelToken:token];
    }
}

- (void)synthesizeSpeechText:(NSString *)text
                     profile:(RDAIConfigProfile *)profile
                  completion:(void (^)(NSData *, NSError *))completion
{
    [self cancelInFlightSpeech];
    NSError *reqErr = nil;
    NSURLRequest *req = [[self class] speechRequestForProfile:profile text:text error:&reqErr];
    if (!req) {
        if (completion) {
            completion(nil, reqErr);
        }
        return;
    }
    BOOL mimoPath = profile.usesMiMoSpeechAPI;
    __weak typeof(self) weakSelf = self;
    __block id token = nil;
    token = [self.transport sendRequest:req completion:^(NSData *data, NSHTTPURLResponse *response, NSError *error) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) {
            return;
        }
        @synchronized (self) {
            if (self.speechToken == token) {
                self.speechToken = nil;
            }
        }
        if (error) {
            if (error.code == NSURLErrorCancelled) {
                return;
            }
            if (completion) {
                dispatch_async(dispatch_get_main_queue(), ^{ completion(nil, error); });
            }
            return;
        }
        NSInteger code = response.statusCode;
        NSString *ct = [NSString stringWithFormat:@"%@", response.allHeaderFields[@"Content-Type"] ?: @""].lowercaseString;
        if (code < 200 || code >= 300) {
            NSString *msg = data.length ? [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] : [NSString stringWithFormat:@"TTS HTTP %ld", (long)code];
            // 尝试从 JSON error 里抠 message
            if (data.length) {
                id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
                if ([json isKindOfClass:NSDictionary.class]) {
                    id errObj = json[@"error"];
                    if ([errObj isKindOfClass:NSDictionary.class] && [errObj[@"message"] isKindOfClass:NSString.class]) {
                        msg = errObj[@"message"];
                    }
                }
            }
            if (completion) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    completion(nil, [NSError errorWithDomain:kRDAIErrorDomain code:42 userInfo:@{NSLocalizedDescriptionKey: msg ?: @"TTS 请求失败"}]);
                });
            }
            return;
        }
        // MiMo:JSON + base64;OpenAI speech:原始音频字节(也可能被网关包成 JSON)
        if (mimoPath || [ct containsString:@"application/json"]) {
            NSError *parseErr = nil;
            NSData *audio = [[self class] audioDataFromChatSpeechResponse:data error:&parseErr];
            if (audio) {
                if (completion) {
                    dispatch_async(dispatch_get_main_queue(), ^{ completion(audio, nil); });
                }
                return;
            }
            // 非 MiMo 且 JSON 解析失败:当作错误文本
            if (!mimoPath) {
                NSString *msg = data.length ? [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] : @"TTS 返回了非音频数据";
                if (completion) {
                    dispatch_async(dispatch_get_main_queue(), ^{
                        completion(nil, [NSError errorWithDomain:kRDAIErrorDomain code:43 userInfo:@{NSLocalizedDescriptionKey: msg ?: @"TTS 错误"}]);
                    });
                }
                return;
            }
            if (completion) {
                dispatch_async(dispatch_get_main_queue(), ^{ completion(nil, parseErr); });
            }
            return;
        }
        if ([ct hasPrefix:@"text/"]) {
            NSString *msg = data.length ? [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] : @"TTS 返回了非音频数据";
            if (completion) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    completion(nil, [NSError errorWithDomain:kRDAIErrorDomain code:43 userInfo:@{NSLocalizedDescriptionKey: msg ?: @"TTS 错误"}]);
                });
            }
            return;
        }
        if (data.length < 32) {
            if (completion) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    completion(nil, [NSError errorWithDomain:kRDAIErrorDomain code:44 userInfo:@{NSLocalizedDescriptionKey: @"TTS 音频过短"}]);
                });
            }
            return;
        }
        if (completion) {
            dispatch_async(dispatch_get_main_queue(), ^{ completion(data, nil); });
        }
    }];
    @synchronized (self) {
        self.speechToken = token;
    }
}

@end
