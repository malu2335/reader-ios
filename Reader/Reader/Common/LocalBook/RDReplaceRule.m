//
//  RDReplaceRule.m
//  Reader
//

#import "RDReplaceRule.h"

NSString * const RDReplaceRuleImportDidChangeNotification = @"RDReplaceRuleImportDidChangeNotification";

static NSString * const kStoreName = @"replace_rules.json";
static NSString * const kErrorDomain = @"RDReplaceRule";

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
        _legadoId = 0;
        _name = @"";
        _groupName = @"";
        _pattern = @"";
        _replacement = @"";
        _isRegex = YES;
        _isEnabled = YES;
        _order = 0;
        _scopeTitle = NO;
        _scopeContent = YES;
    }
    return self;
}

- (id)copyWithZone:(NSZone *)zone
{
    RDReplaceRule *r = [[RDReplaceRule allocWithZone:zone] init];
    r.ruleId = self.ruleId;
    r.legadoId = self.legadoId;
    r.name = self.name;
    r.groupName = self.groupName;
    r.pattern = self.pattern;
    r.replacement = self.replacement;
    r.isRegex = self.isRegex;
    r.isEnabled = self.isEnabled;
    r.order = self.order;
    r.scopeTitle = self.scopeTitle;
    r.scopeContent = self.scopeContent;
    return r;
}

- (BOOL)isJavaScriptReplacement
{
    NSString *rep = [self.replacement stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    return [rep.lowercaseString hasPrefix:@"@js:"];
}

- (NSDictionary *)toDictionary
{
    return @{
        @"ruleId": self.ruleId ?: @"",
        @"id": @(self.legadoId),
        @"name": self.name ?: @"",
        @"group": self.groupName ?: @"",
        @"pattern": self.pattern ?: @"",
        @"replacement": self.replacement ?: @"",
        @"isRegex": @(self.isRegex),
        @"isEnabled": @(self.isEnabled),
        @"order": @(self.order),
        @"scopeTitle": @(self.scopeTitle),
        @"scopeContent": @(self.scopeContent),
    };
}

- (NSDictionary *)toLegadoDictionary
{
    // 与阅读/legado 导出字段对齐
    NSMutableDictionary *d = [@{
        @"id": self.legadoId != 0 ? @(self.legadoId) : @((long long)([[NSDate date] timeIntervalSince1970] * 1000) + (arc4random_uniform(1000))),
        @"name": self.name ?: @"",
        @"group": self.groupName ?: @"",
        @"pattern": self.pattern ?: @"",
        @"replacement": self.replacement ?: @"",
        @"isRegex": @(self.isRegex),
        @"isEnabled": @(self.isEnabled),
        @"order": @(self.order),
        @"scopeTitle": @(self.scopeTitle),
        @"scopeContent": @(self.scopeContent),
    } mutableCopy];
    return d;
}

- (NSRegularExpression *)compiledRegex
{
    if (self.pattern.length == 0) {
        return nil;
    }
    if (self.cachedRegex && [self.cachedRegexPattern isEqualToString:self.pattern]) {
        return self.cachedRegex;
    }
    // 阅读默认 . 匹配换行;并容忍部分不规范正则
    NSRegularExpressionOptions opts = NSRegularExpressionDotMatchesLineSeparators | NSRegularExpressionAnchorsMatchLines;
    NSError *err = nil;
    NSRegularExpression *re = [NSRegularExpression regularExpressionWithPattern:self.pattern options:opts error:&err];
    if (!re && err) {
        // 尝试去掉 (?i) 等内联 flag 的简化回退:仍失败则 nil
        re = [NSRegularExpression regularExpressionWithPattern:self.pattern options:NSRegularExpressionCaseInsensitive | opts error:nil];
    }
    self.cachedRegex = re;
    self.cachedRegexPattern = self.pattern;
    return self.cachedRegex;
}

+ (instancetype)ruleFromDictionary:(NSDictionary *)dict
{
    if (![dict isKindOfClass:NSDictionary.class]) {
        return nil;
    }
    // 至少要有 pattern
    NSString *pattern = nil;
    if ([dict[@"pattern"] isKindOfClass:NSString.class]) {
        pattern = dict[@"pattern"];
    } else if ([dict[@"regex"] isKindOfClass:NSString.class]) {
        pattern = dict[@"regex"]; // 个别源字段别名
    }
    if (pattern.length == 0) {
        return nil;
    }

    RDReplaceRule *r = [[RDReplaceRule alloc] init];

    // id:legado 数字 / 本 App ruleId 字符串
    id idVal = dict[@"id"];
    if ([idVal isKindOfClass:NSNumber.class]) {
        r.legadoId = [idVal longLongValue];
        r.ruleId = [NSString stringWithFormat:@"legado-%lld", r.legadoId];
    } else if ([idVal isKindOfClass:NSString.class] && [(NSString *)idVal length]) {
        NSString *s = (NSString *)idVal;
        if (s.longLongValue != 0 || [s isEqualToString:@"0"]) {
            r.legadoId = s.longLongValue;
        }
        r.ruleId = s;
    }
    NSString *rid = dict[@"ruleId"];
    if ([rid isKindOfClass:NSString.class] && rid.length) {
        r.ruleId = rid;
    }

    r.name = [dict[@"name"] isKindOfClass:NSString.class] ? dict[@"name"] : @"";
    // group / groupName
    if ([dict[@"group"] isKindOfClass:NSString.class]) {
        r.groupName = dict[@"group"];
    } else if ([dict[@"groupName"] isKindOfClass:NSString.class]) {
        r.groupName = dict[@"groupName"];
    } else {
        r.groupName = @"";
    }
    r.pattern = pattern;
    r.replacement = [dict[@"replacement"] isKindOfClass:NSString.class] ? dict[@"replacement"] : @"";
    if (dict[@"isRegex"] != nil) {
        r.isRegex = [dict[@"isRegex"] respondsToSelector:@selector(boolValue)] ? [dict[@"isRegex"] boolValue] : YES;
    } else if (dict[@"regex"] != nil && ![dict[@"regex"] isKindOfClass:NSString.class]) {
        r.isRegex = [dict[@"regex"] boolValue];
    } else {
        r.isRegex = YES;
    }
    if (dict[@"isEnabled"] != nil) {
        r.isEnabled = [dict[@"isEnabled"] respondsToSelector:@selector(boolValue)] ? [dict[@"isEnabled"] boolValue] : YES;
    } else if (dict[@"enable"] != nil) {
        r.isEnabled = [dict[@"enable"] boolValue];
    } else {
        r.isEnabled = YES;
    }
    r.order = [dict[@"order"] respondsToSelector:@selector(integerValue)] ? [dict[@"order"] integerValue] : 0;

    // 作用域:legado 默认标题否、正文是;若两字段都缺省则正文生效
    if (dict[@"scopeTitle"] != nil) {
        r.scopeTitle = [dict[@"scopeTitle"] boolValue];
    } else {
        r.scopeTitle = NO;
    }
    if (dict[@"scopeContent"] != nil) {
        r.scopeContent = [dict[@"scopeContent"] boolValue];
    } else {
        r.scopeContent = YES;
    }
    // 两者都 false 时仍用于正文,避免导入后全部失效
    if (!r.scopeTitle && !r.scopeContent) {
        r.scopeContent = YES;
    }
    return r;
}

@end

#pragma mark - Store

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
        @{@"name": @"去除网址", @"group": @"默认", @"pattern": @"https?://\\S+", @"replacement": @"", @"isRegex": @YES, @"scopeContent": @YES},
        @{@"name": @"去除广告尾巴", @"group": @"默认", @"pattern": @"(求收藏|求推荐|手机用户请到|请记住本站|本章未完|一秒记住)[^\\n]{0,40}", @"replacement": @"", @"isRegex": @YES, @"scopeContent": @YES},
        @{@"name": @"压缩空行", @"group": @"默认", @"pattern": @"\\n{3,}", @"replacement": @"\n\n", @"isRegex": @YES, @"scopeContent": @YES},
        @{@"name": @"全角空格", @"group": @"默认", @"pattern": @"　+", @"replacement": @"", @"isRegex": @YES, @"scopeContent": @YES},
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
    @synchronized (self) {
        return [self.mutableRules copy];
    }
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
    @synchronized (self) {
        [self.mutableRules removeAllObjects];
        NSData *data = [NSData dataWithContentsOfFile:[self storePath]];
        if (data.length == 0) {
            [self.mutableRules addObjectsFromArray:[RDReplaceRuleStore defaultRules]];
            [self save];
            return;
        }
        id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
        NSArray *list = nil;
        if ([json isKindOfClass:NSDictionary.class]) {
            list = json[@"rules"];
        } else if ([json isKindOfClass:NSArray.class]) {
            list = (NSArray *)json;
        }
        if ([list isKindOfClass:NSArray.class]) {
            for (id item in list) {
                RDReplaceRule *r = [RDReplaceRule ruleFromDictionary:item];
                if (r.pattern.length) {
                    [self.mutableRules addObject:r];
                }
            }
        }
        if (self.mutableRules.count == 0) {
            [self.mutableRules addObjectsFromArray:[RDReplaceRuleStore defaultRules]];
            [self save];
            return;
        }
        [self p_sortRules];
    }
}

- (void)p_sortRules
{
    [self.mutableRules sortUsingComparator:^NSComparisonResult(RDReplaceRule *a, RDReplaceRule *b) {
        if (a.order < b.order) return NSOrderedAscending;
        if (a.order > b.order) return NSOrderedDescending;
        return [a.name compare:b.name ?: @""];
    }];
}

- (BOOL)save
{
    @synchronized (self) {
        NSMutableArray *arr = [NSMutableArray array];
        NSInteger i = 0;
        for (RDReplaceRule *r in self.mutableRules) {
            r.order = i++;
            [arr addObject:[r toDictionary]];
        }
        NSDictionary *root = @{@"version": @2, @"rules": arr};
        NSData *data = [NSJSONSerialization dataWithJSONObject:root options:NSJSONWritingPrettyPrinted error:nil];
        return [data writeToFile:[self storePath] atomically:YES];
    }
}

- (void)upsertRule:(RDReplaceRule *)rule
{
    if (!rule) {
        return;
    }
    @synchronized (self) {
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
    [[NSNotificationCenter defaultCenter] postNotificationName:RDReplaceRuleImportDidChangeNotification object:nil];
}

- (void)removeRuleId:(NSString *)ruleId
{
    @synchronized (self) {
        NSMutableArray *next = [NSMutableArray array];
        for (RDReplaceRule *r in self.mutableRules) {
            if (![r.ruleId isEqualToString:ruleId]) {
                [next addObject:r];
            }
        }
        self.mutableRules = next;
        [self save];
    }
    [[NSNotificationCenter defaultCenter] postNotificationName:RDReplaceRuleImportDidChangeNotification object:nil];
}

- (void)replaceAllRules:(NSArray <RDReplaceRule *>*)rules
{
    @synchronized (self) {
        self.mutableRules = [rules mutableCopy] ?: [NSMutableArray array];
        [self p_sortRules];
        [self save];
    }
    [[NSNotificationCenter defaultCenter] postNotificationName:RDReplaceRuleImportDidChangeNotification object:nil];
}

/// 带截止时间的正则替换;超时则返回原串并 *timedOut=YES,避免灾难性回溯卡死主线程(P1-04)
static NSString *RDReplaceRegexWithDeadline(NSRegularExpression *re,
                                            NSString *input,
                                            NSString *template,
                                            NSTimeInterval budget,
                                            BOOL *timedOut)
{
    if (timedOut) {
        *timedOut = NO;
    }
    if (!re || input.length == 0) {
        return input;
    }
    NSMutableString *out = [NSMutableString stringWithCapacity:input.length];
    __block NSUInteger last = 0;
    __block BOOL hitTimeout = NO;
    CFAbsoluteTime deadline = CFAbsoluteTimeGetCurrent() + MAX(0.01, budget);
    NSString *tpl = template ?: @"";
    [re enumerateMatchesInString:input
                         options:0
                           range:NSMakeRange(0, input.length)
                      usingBlock:^(NSTextCheckingResult *match, NSMatchingFlags flags, BOOL *stop) {
        if (CFAbsoluteTimeGetCurrent() > deadline) {
            hitTimeout = YES;
            *stop = YES;
            return;
        }
        NSRange r = match.range;
        if (r.location == NSNotFound) {
            return;
        }
        if (r.location > last) {
            [out appendString:[input substringWithRange:NSMakeRange(last, r.location - last)]];
        }
        NSString *rep = [re replacementStringForResult:match inString:input offset:0 template:tpl];
        [out appendString:rep ?: @""];
        last = r.location + r.length;
    }];
    if (hitTimeout) {
        if (timedOut) {
            *timedOut = YES;
        }
        return input;
    }
    if (last < input.length) {
        [out appendString:[input substringFromIndex:last]];
    }
    return out;
}

- (NSString *)p_applyRulesToText:(NSString *)text contentScope:(BOOL)content titleScope:(BOOL)title
{
    if (text.length == 0) {
        return text ?: @"";
    }
    NSArray <RDReplaceRule *>*snapshot = self.rules;
    NSString *result = text;
    // 总预算 / 单规则预算:净化跑在阅读分页路径上,必须可打断
    CFAbsoluteTime allDeadline = CFAbsoluteTimeGetCurrent() + 0.35;
    const NSTimeInterval kPerRuleBudget = 0.08;
    // 超长正文:仅对前缀做正则,后缀原样拼接,避免整章灾难回溯;字面量替换仍可全量
    static const NSUInteger kMaxRegexApplyChars = 250000;
    for (RDReplaceRule *rule in snapshot) {
        if (CFAbsoluteTimeGetCurrent() > allDeadline) {
            break;
        }
        if (!rule.isEnabled || rule.pattern.length == 0) {
            continue;
        }
        if (content && !rule.scopeContent) {
            continue;
        }
        if (title && !rule.scopeTitle) {
            continue;
        }
        // 不执行 @js 替换,避免未沙箱脚本;规则仍可保留/展示
        if (rule.isJavaScriptReplacement) {
            continue;
        }
        @try {
            if (rule.isRegex) {
                NSRegularExpression *re = [rule compiledRegex];
                if (!re) {
                    continue;
                }
                NSString *tpl = rule.replacement ?: @"";
                if (result.length > kMaxRegexApplyChars) {
                    NSRange safe = [result rangeOfComposedCharacterSequencesForRange:NSMakeRange(0, kMaxRegexApplyChars)];
                    NSString *head = [result substringWithRange:safe];
                    NSString *tail = [result substringFromIndex:safe.length];
                    BOOL timedOut = NO;
                    NSString *newHead = RDReplaceRegexWithDeadline(re, head, tpl, kPerRuleBudget, &timedOut);
                    if (!timedOut) {
                        result = [newHead stringByAppendingString:tail];
                    }
                    // 超时则跳过本条
                } else {
                    BOOL timedOut = NO;
                    NSString *next = RDReplaceRegexWithDeadline(re, result, tpl, kPerRuleBudget, &timedOut);
                    if (!timedOut) {
                        result = next;
                    }
                }
            } else {
                result = [result stringByReplacingOccurrencesOfString:rule.pattern withString:rule.replacement ?: @""];
            }
        } @catch (__unused NSException *ex) {
            // 单条规则失败不影响后续
            continue;
        }
    }
    return result;
}

- (NSString *)applyToText:(NSString *)text
{
    return [self p_applyRulesToText:text contentScope:YES titleScope:NO];
}

- (NSString *)applyToTitle:(NSString *)title
{
    return [self p_applyRulesToText:title contentScope:NO titleScope:YES];
}

#pragma mark - Import / Export

+ (NSArray <RDReplaceRule *>*)rulesFromJSONData:(NSData *)data error:(NSError **)error
{
    if (data.length == 0) {
        if (error) {
            *error = [NSError errorWithDomain:kErrorDomain code:1 userInfo:@{NSLocalizedDescriptionKey: @"空的净化规则数据"}];
        }
        return nil;
    }
    // 去掉可能的 UTF-8 BOM
    if (data.length >= 3) {
        const uint8_t *b = data.bytes;
        if (b[0] == 0xEF && b[1] == 0xBB && b[2] == 0xBF) {
            data = [data subdataWithRange:NSMakeRange(3, data.length - 3)];
        }
    }
    id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:error];
    if (!json) {
        if (error && !*error) {
            *error = [NSError errorWithDomain:kErrorDomain code:2 userInfo:@{NSLocalizedDescriptionKey: @"不是合法 JSON"}];
        }
        return nil;
    }
    NSMutableArray *out = [NSMutableArray array];
    void (^addItem)(id) = ^(id item) {
        RDReplaceRule *r = [RDReplaceRule ruleFromDictionary:item];
        if (r) {
            [out addObject:r];
        }
    };
    if ([json isKindOfClass:NSArray.class]) {
        for (id item in (NSArray *)json) {
            addItem(item);
        }
    } else if ([json isKindOfClass:NSDictionary.class]) {
        NSDictionary *root = (NSDictionary *)json;
        NSArray *list = root[@"rules"] ?: root[@"data"] ?: root[@"replaceRules"];
        if ([list isKindOfClass:NSArray.class]) {
            for (id item in list) {
                addItem(item);
            }
        } else if (root[@"pattern"] || root[@"name"]) {
            // 单条规则对象
            addItem(root);
        }
    }
    if (out.count == 0) {
        if (error) {
            *error = [NSError errorWithDomain:kErrorDomain code:3 userInfo:@{NSLocalizedDescriptionKey: @"未解析到任何净化规则(需要 name/pattern 等 legado 字段)"}];
        }
        return nil;
    }
    return out;
}

- (NSInteger)importRules:(NSArray <RDReplaceRule *>*)incoming merge:(BOOL)merge
{
    if (incoming.count == 0) {
        return 0;
    }
    NSInteger changed = 0;
    @synchronized (self) {
        if (!merge) {
            // 覆盖:清空后写入
            [self.mutableRules removeAllObjects];
            NSInteger i = 0;
            for (RDReplaceRule *r in incoming) {
                RDReplaceRule *c = [r copy];
                c.order = i++;
                [self.mutableRules addObject:c];
                changed++;
            }
        } else {
            for (RDReplaceRule *inc in incoming) {
                NSInteger idx = NSNotFound;
                for (NSInteger i = 0; i < (NSInteger)self.mutableRules.count; i++) {
                    RDReplaceRule *old = self.mutableRules[i];
                    if (inc.legadoId != 0 && old.legadoId == inc.legadoId) {
                        idx = i;
                        break;
                    }
                    if ([old.ruleId isEqualToString:inc.ruleId]) {
                        idx = i;
                        break;
                    }
                    if (old.name.length && [old.name isEqualToString:inc.name]
                        && [old.pattern isEqualToString:inc.pattern]) {
                        idx = i;
                        break;
                    }
                }
                RDReplaceRule *c = [inc copy];
                if (idx == NSNotFound) {
                    c.order = (NSInteger)self.mutableRules.count;
                    [self.mutableRules addObject:c];
                } else {
                    // 保留本地 ruleId,更新内容
                    c.ruleId = self.mutableRules[idx].ruleId;
                    c.order = self.mutableRules[idx].order;
                    self.mutableRules[idx] = c;
                }
                changed++;
            }
            [self p_sortRules];
        }
        [self save];
    }
    if (changed > 0) {
        [[NSNotificationCenter defaultCenter] postNotificationName:RDReplaceRuleImportDidChangeNotification object:nil];
    }
    return changed;
}

- (NSData *)exportLegadoJSONData
{
    NSArray *snapshot = self.rules;
    NSMutableArray *arr = [NSMutableArray arrayWithCapacity:snapshot.count];
    for (RDReplaceRule *r in snapshot) {
        [arr addObject:[r toLegadoDictionary]];
    }
    return [NSJSONSerialization dataWithJSONObject:arr options:NSJSONWritingPrettyPrinted error:nil];
}

@end
