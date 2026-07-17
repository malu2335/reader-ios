//
//  RDReplaceRule.m
//  Reader
//

#import "RDReplaceRule.h"

static NSString * const kStoreName = @"replace_rules.json";

@interface RDReplaceRule ()
@property (nonatomic, strong) NSRegularExpression *cachedRegex;
@property (nonatomic, copy) NSString *cachedRegexPattern;
@end

@implementation RDReplaceRule

- (instancetype)init
{
    self = [super init];
    if (self) {
        _ruleId = [[NSUUID UUID] UUIDString];
        _name = @"";
        _pattern = @"";
        _replacement = @"";
        _isRegex = YES;
        _isEnabled = YES;
        _order = 0;
    }
    return self;
}

- (id)copyWithZone:(NSZone *)zone
{
    RDReplaceRule *r = [[RDReplaceRule allocWithZone:zone] init];
    r.ruleId = self.ruleId;
    r.name = self.name;
    r.pattern = self.pattern;
    r.replacement = self.replacement;
    r.isRegex = self.isRegex;
    r.isEnabled = self.isEnabled;
    r.order = self.order;
    return r;
}

- (NSDictionary *)toDictionary
{
    return @{
        @"ruleId": self.ruleId ?: @"",
        @"name": self.name ?: @"",
        @"pattern": self.pattern ?: @"",
        @"replacement": self.replacement ?: @"",
        @"isRegex": @(self.isRegex),
        @"isEnabled": @(self.isEnabled),
        @"order": @(self.order),
    };
}

- (NSRegularExpression *)compiledRegex
{
    if (self.pattern.length == 0) {
        return nil;
    }
    if (self.cachedRegex && [self.cachedRegexPattern isEqualToString:self.pattern]) {
        return self.cachedRegex;
    }
    self.cachedRegex = [NSRegularExpression regularExpressionWithPattern:self.pattern
                                                                 options:NSRegularExpressionDotMatchesLineSeparators
                                                                   error:nil];
    self.cachedRegexPattern = self.pattern;
    return self.cachedRegex;
}

+ (instancetype)ruleFromDictionary:(NSDictionary *)dict
{
    if (![dict isKindOfClass:NSDictionary.class]) {
        return nil;
    }
    RDReplaceRule *r = [[RDReplaceRule alloc] init];
    NSString *rid = dict[@"ruleId"];
    if ([rid isKindOfClass:NSString.class] && rid.length) {
        r.ruleId = rid;
    }
    r.name = [dict[@"name"] isKindOfClass:NSString.class] ? dict[@"name"] : @"";
    r.pattern = [dict[@"pattern"] isKindOfClass:NSString.class] ? dict[@"pattern"] : @"";
    r.replacement = [dict[@"replacement"] isKindOfClass:NSString.class] ? dict[@"replacement"] : @"";
    r.isRegex = [dict[@"isRegex"] respondsToSelector:@selector(boolValue)] ? [dict[@"isRegex"] boolValue] : YES;
    r.isEnabled = [dict[@"isEnabled"] respondsToSelector:@selector(boolValue)] ? [dict[@"isEnabled"] boolValue] : YES;
    r.order = [dict[@"order"] respondsToSelector:@selector(integerValue)] ? [dict[@"order"] integerValue] : 0;
    return r;
}

@end

@interface RDReplaceRuleStore ()
@property (nonatomic, strong) NSMutableArray <RDReplaceRule *>*mutableRules;
@end

@implementation RDReplaceRuleStore

+ (instancetype)sharedInstance
{
    static RDReplaceRuleStore *store;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        store = [[RDReplaceRuleStore alloc] init];
        [store reload];
    });
    return store;
}

+ (NSArray <RDReplaceRule *>*)defaultRules
{
    NSArray *raw = @[
        @{@"name": @"去除网址", @"pattern": @"https?://\\S+", @"replacement": @"", @"isRegex": @YES},
        @{@"name": @"去除广告尾巴", @"pattern": @"(求收藏|求推荐|手机用户请到|请记住本站|本章未完|一秒记住)[^\\n]{0,40}", @"replacement": @"", @"isRegex": @YES},
        @{@"name": @"压缩空行", @"pattern": @"\\n{3,}", @"replacement": @"\n\n", @"isRegex": @YES},
        @{@"name": @"全角空格", @"pattern": @"　+", @"replacement": @"", @"isRegex": @YES},
    ];
    NSMutableArray *arr = [NSMutableArray array];
    NSInteger i = 0;
    for (NSDictionary *d in raw) {
        RDReplaceRule *r = [RDReplaceRule ruleFromDictionary:d];
        r.order = i++;
        r.isEnabled = YES;
        [arr addObject:r];
    }
    return arr;
}

- (instancetype)init
{
    self = [super init];
    if (self) {
        _mutableRules = [NSMutableArray array];
    }
    return self;
}

- (NSArray <RDReplaceRule *>*)rules
{
    return [self.mutableRules copy];
}

- (NSString *)storePath
{
    NSString *dir = [PATH_DOCUMENT stringByAppendingPathComponent:@"Rules"];
    if (![[NSFileManager defaultManager] fileExistsAtPath:dir]) {
        [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
    }
    return [dir stringByAppendingPathComponent:kStoreName];
}

- (void)reload
{
    [self.mutableRules removeAllObjects];
    NSData *data = [NSData dataWithContentsOfFile:[self storePath]];
    if (data.length == 0) {
        [self.mutableRules addObjectsFromArray:[RDReplaceRuleStore defaultRules]];
        [self save];
        return;
    }
    id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    NSArray *list = [json isKindOfClass:NSDictionary.class] ? json[@"rules"] : nil;
    if ([list isKindOfClass:NSArray.class]) {
        for (id item in list) {
            RDReplaceRule *r = [RDReplaceRule ruleFromDictionary:item];
            if (r.pattern.length) {
                [self.mutableRules addObject:r];
            }
        }
    }
    [self.mutableRules sortUsingComparator:^NSComparisonResult(RDReplaceRule *a, RDReplaceRule *b) {
        return a.order < b.order ? NSOrderedAscending : (a.order > b.order ? NSOrderedDescending : NSOrderedSame);
    }];
}

- (BOOL)save
{
    NSMutableArray *arr = [NSMutableArray array];
    NSInteger i = 0;
    for (RDReplaceRule *r in self.mutableRules) {
        r.order = i++;
        [arr addObject:[r toDictionary]];
    }
    NSDictionary *root = @{@"version": @1, @"rules": arr};
    NSData *data = [NSJSONSerialization dataWithJSONObject:root options:NSJSONWritingPrettyPrinted error:nil];
    return [data writeToFile:[self storePath] atomically:YES];
}

- (void)upsertRule:(RDReplaceRule *)rule
{
    if (!rule) {
        return;
    }
    NSInteger idx = NSNotFound;
    for (NSInteger i = 0; i < (NSInteger)self.mutableRules.count; i++) {
        if ([self.mutableRules[i].ruleId isEqualToString:rule.ruleId]) {
            idx = i;
            break;
        }
    }
    RDReplaceRule *copy = [rule copy];
    if (idx == NSNotFound) {
        [self.mutableRules addObject:copy];
    } else {
        self.mutableRules[idx] = copy;
    }
    [self save];
}

- (void)removeRuleId:(NSString *)ruleId
{
    NSMutableArray *next = [NSMutableArray array];
    for (RDReplaceRule *r in self.mutableRules) {
        if (![r.ruleId isEqualToString:ruleId]) {
            [next addObject:r];
        }
    }
    self.mutableRules = next;
    [self save];
}

- (void)replaceAllRules:(NSArray <RDReplaceRule *>*)rules
{
    self.mutableRules = [rules mutableCopy] ?: [NSMutableArray array];
    [self save];
}

- (NSString *)applyToText:(NSString *)text
{
    if (text.length == 0) {
        return text ?: @"";
    }
    NSString *result = text;
    for (RDReplaceRule *rule in self.mutableRules) {
        if (!rule.isEnabled || rule.pattern.length == 0) {
            continue;
        }
        if (rule.isRegex) {
            NSRegularExpression *re = [rule compiledRegex];
            if (!re) {
                continue;
            }
            result = [re stringByReplacingMatchesInString:result
                                                  options:0
                                                    range:NSMakeRange(0, result.length)
                                             withTemplate:rule.replacement ?: @""];
        } else {
            result = [result stringByReplacingOccurrencesOfString:rule.pattern withString:rule.replacement ?: @""];
        }
    }
    return result;
}

@end
