//
//  RDHttpTTSClient.m
//  Reader
//

#import "RDHttpTTSClient.h"
#import "RDHttpTTS.h"

@interface RDHttpTTSClient ()
@property (nonatomic, strong) NSURLSession *session;
@property (nonatomic, strong, nullable) NSURLSessionDataTask *task;
@end

@implementation RDHttpTTSClient

+ (instancetype)sharedClient
{
    static RDHttpTTSClient *c;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        c = [[RDHttpTTSClient alloc] init];
    });
    return c;
}

- (instancetype)init
{
    self = [super init];
    if (self) {
        NSURLSessionConfiguration *cfg = [NSURLSessionConfiguration ephemeralSessionConfiguration];
        cfg.timeoutIntervalForRequest = 60;
        cfg.timeoutIntervalForResource = 120;
        cfg.waitsForConnectivity = YES;
        _session = [NSURLSession sessionWithConfiguration:cfg];
    }
    return self;
}

- (void)cancel
{
    [self.task cancel];
    self.task = nil;
}

+ (NSString *)resolveURLTemplate:(NSString *)template
                            text:(NSString *)text
                      speakSpeed:(NSInteger)speakSpeed
{
    if (template.length == 0) {
        return @"";
    }
    NSString *encoded = [text stringByAddingPercentEncodingWithAllowedCharacters:
                         [NSCharacterSet URLQueryAllowedCharacterSet]] ?: @"";
    // 去掉 query 里危险的 & 等已由 URLQueryAllowed 处理;再强制 encode 空格
    encoded = [encoded stringByReplacingOccurrencesOfString:@"+" withString:@"%2B"];
    NSString *speed = [NSString stringWithFormat:@"%ld", (long)speakSpeed];
    NSString *url = template;
    // legado 常见占位
    url = [url stringByReplacingOccurrencesOfString:@"{{speakText}}" withString:encoded];
    url = [url stringByReplacingOccurrencesOfString:@"{{speakSpeed}}" withString:speed];
    // 部分源使用 <%s> 或 {speakText}
    url = [url stringByReplacingOccurrencesOfString:@"{speakText}" withString:encoded];
    url = [url stringByReplacingOccurrencesOfString:@"{speakSpeed}" withString:speed];
    return url;
}

- (NSDictionary *)p_headersFromEngine:(RDHttpTTS *)engine
{
    if (engine.header.length == 0) {
        return @{};
    }
    NSData *data = [engine.header dataUsingEncoding:NSUTF8StringEncoding];
    id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    if (![json isKindOfClass:NSDictionary.class]) {
        return @{};
    }
    NSMutableDictionary *headers = [NSMutableDictionary dictionary];
    [json enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL *stop) {
        if ([key isKindOfClass:NSString.class] && [obj isKindOfClass:NSString.class]) {
            headers[key] = obj;
        } else if ([key isKindOfClass:NSString.class]) {
            headers[key] = [NSString stringWithFormat:@"%@", obj];
        }
    }];
    return headers;
}

- (void)fetchAudioForEngine:(RDHttpTTS *)engine
                       text:(NSString *)text
                 speakSpeed:(NSInteger)speakSpeed
                 completion:(void (^)(NSData *, NSError *))completion
{
    [self cancel];
    NSString *speak = [text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (speak.length == 0 || engine.url.length == 0) {
        if (completion) {
            completion(nil, [NSError errorWithDomain:@"RDHttpTTS" code:10 userInfo:@{NSLocalizedDescriptionKey: @"TTS 文本或引擎为空"}]);
        }
        return;
    }
    // 单段上限,避免超长 URL
    if (speak.length > 500) {
        speak = [speak substringToIndex:500];
    }
    NSString *urlString = [[self class] resolveURLTemplate:engine.url text:speak speakSpeed:speakSpeed];
    // 去掉 AnalyzeUrl 尾部的附加规则(legado 用 ,{"method":...});MVP 只取逗号前的 URL
    NSRange brace = [urlString rangeOfString:@",{"];
    if (brace.location != NSNotFound) {
        urlString = [urlString substringToIndex:brace.location];
    }
    NSURL *url = [NSURL URLWithString:urlString];
    if (!url) {
        if (completion) {
            completion(nil, [NSError errorWithDomain:@"RDHttpTTS" code:11 userInfo:@{NSLocalizedDescriptionKey: @"TTS URL 无效"}]);
        }
        return;
    }
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:url];
    req.HTTPMethod = @"GET";
    req.timeoutInterval = 60;
    NSDictionary *headers = [self p_headersFromEngine:engine];
    [headers enumerateKeysAndObjectsUsingBlock:^(NSString *key, NSString *obj, BOOL *stop) {
        [req setValue:obj forHTTPHeaderField:key];
    }];
    if (!headers[@"User-Agent"]) {
        [req setValue:@"PaperFeatherReader/1.0 (legado-compatible HttpTTS)" forHTTPHeaderField:@"User-Agent"];
    }

    __weak typeof(self) weakSelf = self;
    self.task = [self.session dataTaskWithRequest:req completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) {
            return;
        }
        self.task = nil;
        if (error) {
            if (error.code == NSURLErrorCancelled) {
                return;
            }
            if (completion) {
                dispatch_async(dispatch_get_main_queue(), ^{ completion(nil, error); });
            }
            return;
        }
        // 音频响应硬预算(P1-05):完整缓冲路径上的最后一道门
        static const NSUInteger kMaxHttpTTSAudioBytes = 8u * 1024u * 1024u;
        NSHTTPURLResponse *http = (NSHTTPURLResponse *)response;
        long long expected = http.expectedContentLength;
        if ((expected > 0 && expected > (long long)kMaxHttpTTSAudioBytes) || data.length > kMaxHttpTTSAudioBytes) {
            if (completion) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    completion(nil, [NSError errorWithDomain:@"RDHttpTTS" code:15 userInfo:@{NSLocalizedDescriptionKey: @"TTS 音频过大(超过 8MB),已取消"}]);
                });
            }
            return;
        }
        NSString *ct = http.allHeaderFields[@"Content-Type"] ?: http.allHeaderFields[@"content-type"] ?: @"";
        NSString *ctMain = [[ct componentsSeparatedByString:@";"].firstObject stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        if ([ctMain hasPrefix:@"text/"] || [ctMain isEqualToString:@"application/json"]) {
            NSString *msg = data.length ? [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] : @"TTS 返回了文本错误";
            if (completion) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    completion(nil, [NSError errorWithDomain:@"RDHttpTTS" code:12 userInfo:@{NSLocalizedDescriptionKey: msg ?: @"TTS 错误"}]);
                });
            }
            return;
        }
        if (engine.contentType.length > 0 && ctMain.length > 0) {
            NSRegularExpression *re = [NSRegularExpression regularExpressionWithPattern:engine.contentType options:0 error:nil];
            if (re) {
                NSRange r = [re rangeOfFirstMatchInString:ctMain options:0 range:NSMakeRange(0, ctMain.length)];
                if (r.location == NSNotFound) {
                    NSString *body = data.length < 400 ? [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] : @"";
                    NSString *msg = [NSString stringWithFormat:@"TTS Content-Type 不匹配: %@", ctMain];
                    if (body.length) {
                        msg = [msg stringByAppendingFormat:@" · %@", body];
                    }
                    if (completion) {
                        dispatch_async(dispatch_get_main_queue(), ^{
                            completion(nil, [NSError errorWithDomain:@"RDHttpTTS" code:13 userInfo:@{NSLocalizedDescriptionKey: msg}]);
                        });
                    }
                    return;
                }
            }
        }
        if (data.length < 32) {
            if (completion) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    completion(nil, [NSError errorWithDomain:@"RDHttpTTS" code:14 userInfo:@{NSLocalizedDescriptionKey: @"TTS 音频数据过短"}]);
                });
            }
            return;
        }
        if (completion) {
            dispatch_async(dispatch_get_main_queue(), ^{ completion(data, nil); });
        }
    }];
    [self.task resume];
}

@end
