//
//  RDHttpTTS.m
//  Reader
//

#import "RDHttpTTS.h"

NSString * const RDHttpTTSIdentifierPrefix = @"httpTts:";

static NSString * const kRDHttpTTSFileName = @"http_tts_engines.json";

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
        for (id item in list) {
            RDHttpTTS *e = [RDHttpTTS engineFromDictionary:item];
            if (e) {
                [self.mutableEngines addObject:e];
            }
        }
    });
}

- (BOOL)p_saveUnlocked
{
    NSMutableArray *arr = [NSMutableArray array];
    for (RDHttpTTS *e in self.mutableEngines) {
        [arr addObject:[e toDictionary]];
    }
    NSData *data = [NSJSONSerialization dataWithJSONObject:@{@"engines": arr} options:NSJSONWritingPrettyPrinted error:nil];
    if (!data) {
        return NO;
    }
    return [data writeToFile:[self p_path] atomically:YES];
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
