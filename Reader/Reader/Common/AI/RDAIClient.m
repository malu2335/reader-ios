//
//  RDAIClient.m
//  Reader
//

#import "RDAIClient.h"

static NSString * const kRDAIErrorDomain = @"RDAIClient";

@implementation RDAIURLSessionTransport

- (id)sendRequest:(NSURLRequest *)request completion:(RDAITransportCompletion)completion
{
    NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        NSHTTPURLResponse *http = [response isKindOfClass:NSHTTPURLResponse.class] ? (NSHTTPURLResponse *)response : nil;
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
@property (nonatomic, assign, readwrite) BOOL isTranslating;
@property (nonatomic, assign) NSUInteger translateGeneration;
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
    return [type isEqualToString:RDAIProviderTypeOpenAI] || [type isEqualToString:RDAIProviderTypeOpenAICompat];
}

+ (BOOL)isAnthropicFamily:(NSString *)type
{
    return [type isEqualToString:RDAIProviderTypeAnthropic] || [type isEqualToString:RDAIProviderTypeAnthropicCompat];
}

+ (BOOL)isGeminiFamily:(NSString *)type
{
    return [type isEqualToString:RDAIProviderTypeGemini] || [type isEqualToString:RDAIProviderTypeGeminiCompat];
}

+ (NSString *)defaultBaseURLForType:(NSString *)type
{
    if ([self isOpenAIFamily:type]) {
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
    NSString *prompt = [self translatePromptForText:text];

    if ([self isOpenAIFamily:type]) {
        // 支持 base=https://api.openai.com 或 http://host:port/v1
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
        [req setValue:[NSString stringWithFormat:@"Bearer %@", profile.apiKey] forHTTPHeaderField:@"Authorization"];
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
    // 取消上一次,避免连点乱序
    [self cancelInFlightTranslate];
    NSError *buildError = nil;
    NSURLRequest *request = [[self class] requestForProfile:profile text:text error:&buildError];
    if (!request) {
        if (completion) {
            completion(nil, buildError);
        }
        return;
    }
    id<RDAIHTTPTransport> transport = self.transport ?: [[RDAIURLSessionTransport alloc] init];
    NSUInteger generation = self.translateGeneration;
    self.isTranslating = YES;
    __weak typeof(self) weakSelf = self;
    id token = [transport sendRequest:request completion:^(NSData *data, NSHTTPURLResponse *response, NSError *error) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self || generation != self.translateGeneration) {
            return; // 已取消/被替换
        }
        self.inFlightToken = nil;
        self.isTranslating = NO;
        if (error) {
            if ([error.domain isEqualToString:NSURLErrorDomain] && error.code == NSURLErrorCancelled) {
                // 取消时也回调,便于 UI 关掉 loading
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
                // 不把超长 body 抛给 UI
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
    self.inFlightToken = token;
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

@end
