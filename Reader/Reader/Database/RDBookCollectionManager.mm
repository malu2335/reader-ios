//
//  RDBookCollectionManager.m
//  Reader
//

#import "RDBookCollectionManager.h"
#import "RDBookDetailModel.h"
#import "RDBookDetailModel+WCTTableCoding.h"
#import "RDReadRecordManager.h"
#import "RDDatabaseManager.h"
#import <WCDB/WCDB.h>

NSString * const RDBookCollectionDidChangeNotification = @"RDBookCollectionDidChangeNotification";

@implementation RDBookCollectionManager

+ (void)p_notify:(RDBookDetailModel *)hub
{
    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter] postNotificationName:RDBookCollectionDidChangeNotification
                                                            object:hub];
    });
}

+ (NSInteger)newCollectionBookId
{
    // 与内容 MD5 本地书区分:使用时间+随机高位负 id
    for (int i = 0; i < 8; i++) {
        uint64_t v = ((uint64_t)[[NSDate date] timeIntervalSince1970] << 20)
            ^ ((uint64_t)arc4random() << 1)
            ^ (uint64_t)i;
        NSInteger candidate = -((NSInteger)(v & 0x7FFFFFFFFFFFFFLL));
        if (candidate >= 0) {
            candidate = -candidate - 1;
        }
        if (candidate == 0) {
            continue;
        }
        if (![RDReadRecordManager getReadRecordWithBookId:candidate]) {
            return candidate;
        }
    }
    return -((NSInteger)(arc4random() | 0x10000000));
}

#pragma mark - 书名智能排序

/// 中文数字 → 整数(支持 1–99: 十二/二十/二十一/两)
+ (NSInteger)p_integerFromChineseNumeral:(NSString *)cn
{
    if (cn.length == 0) {
        return NSNotFound;
    }
    // 纯阿拉伯
    NSCharacterSet *nonDigit = [[NSCharacterSet decimalDigitCharacterSet] invertedSet];
    if ([cn rangeOfCharacterFromSet:nonDigit].location == NSNotFound) {
        return cn.integerValue;
    }
    static NSDictionary <NSString *, NSNumber *>*map;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        map = @{
            @"零": @0, @"〇": @0, @"○": @0,
            @"一": @1, @"壹": @1,
            @"二": @2, @"贰": @2, @"两": @2,
            @"三": @3, @"叁": @3,
            @"四": @4, @"肆": @4,
            @"五": @5, @"伍": @5,
            @"六": @6, @"陆": @6,
            @"七": @7, @"柒": @7,
            @"八": @8, @"捌": @8,
            @"九": @9, @"玖": @9,
            @"十": @10, @"拾": @10,
        };
    });
    // 十 / 十一 / 二十 / 二十一
    if ([cn isEqualToString:@"十"] || [cn isEqualToString:@"拾"]) {
        return 10;
    }
    NSRange shi = [cn rangeOfString:@"十"];
    if (shi.location == NSNotFound) {
        shi = [cn rangeOfString:@"拾"];
    }
    if (shi.location != NSNotFound) {
        NSInteger tens = 1;
        NSInteger ones = 0;
        if (shi.location > 0) {
            NSString *t = [cn substringToIndex:shi.location];
            NSNumber *tn = map[t];
            if (!tn) { return NSNotFound; }
            tens = tn.integerValue;
        }
        if (NSMaxRange(shi) < cn.length) {
            NSString *o = [cn substringFromIndex:NSMaxRange(shi)];
            NSNumber *on = map[o];
            if (!on) { return NSNotFound; }
            ones = on.integerValue;
        }
        return tens * 10 + ones;
    }
    NSNumber *single = map[cn];
    return single ? single.integerValue : NSNotFound;
}

/// 去站点尾巴、书名号、多余空白
+ (NSString *)p_cleanTitle:(NSString *)title
{
    if (title.length == 0) {
        return @"";
    }
    NSString *s = title;
    NSRegularExpression *paren = [NSRegularExpression regularExpressionWithPattern:@"[\\(（][^\\)）]{0,40}[\\)）]\\s*$"
                                                                           options:0 error:nil];
    s = [paren stringByReplacingMatchesInString:s options:0 range:NSMakeRange(0, s.length) withTemplate:@""];
    s = [s stringByReplacingOccurrencesOfString:@"《" withString:@""];
    s = [s stringByReplacingOccurrencesOfString:@"》" withString:@""];
    s = [s stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    while ([s containsString:@"  "]) {
        s = [s stringByReplacingOccurrencesOfString:@"  " withString:@" "];
    }
    return s;
}

/// 系列「核心」:去修饰词/同义替换,用于模糊同系列判定(皇子变体书名)
+ (NSString *)p_seriesCoreFromTitle:(NSString *)title
{
    NSString *s = [self p_seriesBaseFromTitle:title];
    if (s.length == 0) {
        return @"";
    }
    // 同义归一
    NSArray <NSArray <NSString *>*>*repls = @[
        @[@"欧米伽", @"omega"], @[@"歐米伽", @"omega"], @[@"Ω", @"omega"],
        @[@"Omega", @"omega"], @[@"OMEGA", @"omega"], @[@"omega", @"omega"],
        @[@"Enigma", @"enigma"], @[@"ENIGMA", @"enigma"],
        @[@"身份", @""], @[@"事实", @""], @[@"的事", @""], @[@"之事", @""],
        @[@"自己是", @""], @[@"自己", @""], @[@"隐藏", @""], @[@"隱藏", @""],
        @[@"纨绔", @""], @[@"浪荡", @""], @[@"混账", @""], @[@"暴戾", @""],
        @[@"是", @""], @[@"的", @""],
    ];
    NSString *out = s;
    for (NSArray *pair in repls) {
        out = [out stringByReplacingOccurrencesOfString:pair[0] withString:pair[1]
                                                options:NSCaseInsensitiveSearch
                                                  range:NSMakeRange(0, out.length)];
    }
    // 去空白与常见连接符
    NSCharacterSet *drop = [NSCharacterSet characterSetWithCharactersInString:@" 　\t-_·•."];
    out = [[out componentsSeparatedByCharactersInSet:drop] componentsJoinedByString:@""];
    return out.lowercaseString;
}

/// 去掉卷/册/话/外传序号后的「系列基底名」
+ (NSString *)p_seriesBaseFromTitle:(NSString *)title
{
    NSString *raw = title ?: @"";
    NSRegularExpression *paren = [NSRegularExpression regularExpressionWithPattern:@"\\s*[\\(（][^\\)）]{0,40}[\\)）]\\s*$"
                                                                           options:0 error:nil];
    NSString *s = [paren stringByReplacingMatchesInString:raw options:0 range:NSMakeRange(0, raw.length) withTemplate:@""];
    s = [self p_cleanTitle:s];
    if (s.length == 0) {
        s = [self p_cleanTitle:title];
    }
    // 阿拉伯 + 汉字卷序
    NSString *cnClass = @"一二三四五六七八九十百两零〇壹贰叁肆伍陆柒捌玖拾两";
    NSArray <NSString *>*patterns = @[
        [NSString stringWithFormat:@"\\s*[第]?\\s*(?:\\d+|[%@]+)\\s*[卷册话回章部集]\\s*$", cnClass],
        @"\\s*[Vv][Oo][Ll]\\.?\\s*\\d+\\s*$",
        @"\\s*[Vv]\\.\\s*\\d+\\s*$",
        @"\\s*(外传|番外|续|完结|上|中|下)\\s*(?:\\d+|[一二三四五六七八九十]*)?\\s*$",
        @"\\s*[-_·•.]\\s*\\d+\\s*$",
        @"\\s+\\d+\\s*$",
        @"\\s*\\d+\\s*$",
    ];
    BOOL changed = YES;
    NSInteger guard = 0;
    while (changed && guard++ < 6) {
        changed = NO;
        for (NSString *pat in patterns) {
            NSRegularExpression *re = [NSRegularExpression regularExpressionWithPattern:pat options:0 error:nil];
            NSRange full = NSMakeRange(0, s.length);
            NSTextCheckingResult *m = [re firstMatchInString:s options:0 range:full];
            if (m && m.range.location != NSNotFound && m.range.length > 0
                && NSMaxRange(m.range) == s.length && m.range.location > 0) {
                s = [[s substringToIndex:m.range.location]
                     stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
                changed = YES;
                break;
            }
        }
    }
    return s.length ? s : [self p_cleanTitle:title];
}

/// 把捕获的卷序 token 转成整数
+ (NSInteger)p_volumeTokenToInteger:(NSString *)token
{
    if (token.length == 0) {
        return NSNotFound;
    }
    NSCharacterSet *nonDigit = [[NSCharacterSet decimalDigitCharacterSet] invertedSet];
    if ([token rangeOfCharacterFromSet:nonDigit].location == NSNotFound) {
        return token.integerValue;
    }
    return [self p_integerFromChineseNumeral:token];
}

/// 解析卷序:*vol 主卷号; *isSide 外传/番外支线(主卷排完再排)
+ (void)p_parseVolumeFromTitle:(NSString *)title volume:(NSInteger *)outVol isSideStory:(BOOL *)outSide
{
    if (outVol) { *outVol = NSNotFound; }
    if (outSide) { *outSide = NO; }
    NSString *raw = title ?: @"";
    if (raw.length == 0) {
        return;
    }
    NSString *cnClass = @"一二三四五六七八九十百两零〇壹贰叁肆伍陆柒捌玖拾两";

    // 1) 「第?N卷/册…」含汉字: 第二卷 / 第1卷 / 3卷
    {
        NSString *pat = [NSString stringWithFormat:@"[第]?\\s*(\\d+|[%@]+)\\s*[卷册话回章部集]", cnClass];
        NSRegularExpression *re = [NSRegularExpression regularExpressionWithPattern:pat options:0 error:nil];
        NSTextCheckingResult *m = [re firstMatchInString:raw options:0 range:NSMakeRange(0, raw.length)];
        if (m && m.numberOfRanges >= 2) {
            NSInteger v = [self p_volumeTokenToInteger:[raw substringWithRange:[m rangeAtIndex:1]]];
            if (v != NSNotFound) {
                if (outVol) { *outVol = v; }
                if (outSide) { *outSide = NO; }
                return;
            }
        }
    }

    // 2) vol.N / V.N
    {
        NSRegularExpression *re = [NSRegularExpression regularExpressionWithPattern:@"[Vv][Oo][Ll]\\.?\\s*(\\d+)|[Vv]\\.\\s*(\\d+)"
                                                                           options:0 error:nil];
        NSTextCheckingResult *m = [re firstMatchInString:raw options:0 range:NSMakeRange(0, raw.length)];
        if (m) {
            for (NSUInteger i = 1; i < m.numberOfRanges; i++) {
                NSRange r = [m rangeAtIndex:i];
                if (r.location != NSNotFound) {
                    if (outVol) { *outVol = [[raw substringWithRange:r] integerValue]; }
                    if (outSide) { *outSide = NO; }
                    return;
                }
            }
        }
    }

    // 3) 外传/番外(+数字/汉字),含 (外传2)
    {
        NSString *pat = [NSString stringWithFormat:@"(?:外传|番外)\\s*(\\d+|[%@]+)?", cnClass];
        NSRegularExpression *re = [NSRegularExpression regularExpressionWithPattern:pat options:0 error:nil];
        NSTextCheckingResult *m = [re firstMatchInString:raw options:0 range:NSMakeRange(0, raw.length)];
        if (m) {
            if (outSide) { *outSide = YES; }
            if (outVol) {
                NSRange r = (m.numberOfRanges >= 2) ? [m rangeAtIndex:1] : NSMakeRange(NSNotFound, 0);
                if (r.location != NSNotFound && r.length > 0) {
                    NSInteger v = [self p_volumeTokenToInteger:[raw substringWithRange:r]];
                    *outVol = (v == NSNotFound) ? 0 : v;
                } else {
                    *outVol = 0;
                }
            }
            return;
        }
    }

    // 4) 末尾独立数字(空格/符号分隔)
    NSString *s = [self p_cleanTitle:raw];
    NSRegularExpression *tail = [NSRegularExpression regularExpressionWithPattern:@"(?:[-_·•.\\s])(\\d+)\\s*$"
                                                                         options:0 error:nil];
    NSTextCheckingResult *tm = [tail firstMatchInString:s options:0 range:NSMakeRange(0, s.length)];
    if (tm && tm.numberOfRanges >= 2) {
        if (outVol) { *outVol = [[s substringWithRange:[tm rangeAtIndex:1]] integerValue]; }
        if (outSide) { *outSide = NO; }
    }
}

/// 是否同一系列:基底名大部分相同
+ (BOOL)p_isSameSeriesBase:(NSString *)baseA other:(NSString *)baseB
{
    if (baseA.length == 0 || baseB.length == 0) {
        return NO;
    }
    NSString *a = baseA.lowercaseString;
    NSString *b = baseB.lowercaseString;
    if ([a isEqualToString:b]) {
        return YES;
    }
    NSString *a2 = [[a componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceCharacterSet]] componentsJoinedByString:@""];
    NSString *b2 = [[b componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceCharacterSet]] componentsJoinedByString:@""];
    if ([a2 isEqualToString:b2]) {
        return YES;
    }
    NSString *shorter = a2.length <= b2.length ? a2 : b2;
    NSString *longer = a2.length <= b2.length ? b2 : a2;
    if (shorter.length >= 4 && [longer hasPrefix:shorter]) {
        return (CGFloat)shorter.length / (CGFloat)longer.length >= 0.6;
    }
    NSInteger common = 0;
    NSInteger limit = MIN((NSInteger)a2.length, (NSInteger)b2.length);
    for (NSInteger i = 0; i < limit; i++) {
        if ([a2 characterAtIndex:i] == [b2 characterAtIndex:i]) {
            common++;
        } else {
            break;
        }
    }
    if (common >= 4) {
        CGFloat ratio = (CGFloat)common / (CGFloat)MAX(a2.length, b2.length);
        return ratio >= 0.55;
    }
    return NO;
}

/// 模糊同系列:核心串相同/包含,或汉字集合 Jaccard 较高(纨绔/浪荡皇子变体)
+ (BOOL)p_isLooselyRelatedTitle:(NSString *)titleA to:(NSString *)titleB
{
    NSString *cA = [self p_seriesCoreFromTitle:titleA];
    NSString *cB = [self p_seriesCoreFromTitle:titleB];
    if (cA.length >= 2 && cB.length >= 2) {
        if ([cA isEqualToString:cB]) {
            return YES;
        }
        NSString *sh = cA.length <= cB.length ? cA : cB;
        NSString *lg = cA.length <= cB.length ? cB : cA;
        if (sh.length >= 3 && [lg containsString:sh]) {
            return (CGFloat)sh.length / (CGFloat)lg.length >= 0.5;
        }
    }
    // 汉字集合重叠
    NSMutableSet *setA = [NSMutableSet set];
    NSMutableSet *setB = [NSMutableSet set];
    NSString *rawA = [self p_seriesBaseFromTitle:titleA];
    NSString *rawB = [self p_seriesBaseFromTitle:titleB];
    for (NSUInteger i = 0; i < rawA.length; i++) {
        unichar c = [rawA characterAtIndex:i];
        if (c >= 0x4E00 && c <= 0x9FFF) {
            [setA addObject:[NSString stringWithFormat:@"%C", c]];
        }
    }
    for (NSUInteger i = 0; i < rawB.length; i++) {
        unichar c = [rawB characterAtIndex:i];
        if (c >= 0x4E00 && c <= 0x9FFF) {
            [setB addObject:[NSString stringWithFormat:@"%C", c]];
        }
    }
    if (setA.count < 2 || setB.count < 2) {
        return NO;
    }
    NSMutableSet *inter = [setA mutableCopy];
    [inter intersectSet:setB];
    NSMutableSet *uni = [setA mutableCopy];
    [uni unionSet:setB];
    CGFloat jaccard = (CGFloat)inter.count / (CGFloat)MAX(1, (NSInteger)uni.count);
    // 至少共 3 个汉字且 Jaccard≥0.35,或共 4 个汉字
    if (inter.count >= 4) {
        return YES;
    }
    return inter.count >= 3 && jaccard >= 0.35;
}

/// 首拼/首字母排序键
+ (NSString *)p_letterSortKeyFromTitle:(NSString *)title
{
    NSString *s = [self p_seriesBaseFromTitle:title];
    if (s.length == 0) {
        s = [self p_cleanTitle:title];
    }
    if (s.length == 0) {
        return @"~";
    }
    unichar first = 0;
    for (NSUInteger i = 0; i < s.length; i++) {
        unichar c = [s characterAtIndex:i];
        if ([[NSCharacterSet whitespaceAndNewlineCharacterSet] characterIsMember:c]) {
            continue;
        }
        if ([[NSCharacterSet punctuationCharacterSet] characterIsMember:c]
            || [[NSCharacterSet symbolCharacterSet] characterIsMember:c]) {
            continue;
        }
        first = c;
        break;
    }
    if (first == 0) {
        return @"~";
    }
    if (first >= '0' && first <= '9') {
        return [NSString stringWithFormat:@"0%c", (char)first];
    }
    if ((first >= 'A' && first <= 'Z') || (first >= 'a' && first <= 'z')) {
        unichar lower = (first >= 'A' && first <= 'Z') ? (unichar)(first - 'A' + 'a') : first;
        return [NSString stringWithFormat:@"1%c", (char)lower];
    }
    NSMutableString *latinBuf = [[s substringToIndex:1] mutableCopy];
    CFStringTransform((__bridge CFMutableStringRef)latinBuf, NULL, kCFStringTransformToLatin, false);
    CFStringTransform((__bridge CFMutableStringRef)latinBuf, NULL, kCFStringTransformStripDiacritics, false);
    NSString *latin = latinBuf.lowercaseString;
    for (NSUInteger i = 0; i < latin.length; i++) {
        unichar c = [latin characterAtIndex:i];
        if (c >= 'a' && c <= 'z') {
            return [NSString stringWithFormat:@"1%c", (char)c];
        }
        if (c >= '0' && c <= '9') {
            return [NSString stringWithFormat:@"0%c", (char)c];
        }
    }
    return @"~";
}

+ (NSComparisonResult)p_compareByVolumeSide:(NSString *)a to:(NSString *)b
{
    NSInteger va = NSNotFound, vb = NSNotFound;
    BOOL sideA = NO, sideB = NO;
    [self p_parseVolumeFromTitle:a volume:&va isSideStory:&sideA];
    [self p_parseVolumeFromTitle:b volume:&vb isSideStory:&sideB];
    if (sideA != sideB) {
        return sideA ? NSOrderedDescending : NSOrderedAscending;
    }
    NSInteger na = (va == NSNotFound) ? NSIntegerMax : va;
    NSInteger nb = (vb == NSNotFound) ? NSIntegerMax : vb;
    if (na != nb) {
        return na < nb ? NSOrderedAscending : NSOrderedDescending;
    }
    return [a compare:b options:(NSCaseInsensitiveSearch | NSNumericSearch | NSWidthInsensitiveSearch)];
}

+ (NSComparisonResult)compareBookTitles:(NSString *)titleA to:(NSString *)titleB
{
    NSString *a = titleA ?: @"";
    NSString *b = titleB ?: @"";
    NSString *baseA = [self p_seriesBaseFromTitle:a];
    NSString *baseB = [self p_seriesBaseFromTitle:b];
    BOOL same = [self p_isSameSeriesBase:baseA other:baseB];
    BOOL loose = [self p_isLooselyRelatedTitle:a to:b];

    // 同系列(严格或模糊,如皇子变体书名) → 按卷序:主线 1·2·3,外传/番外靠后
    if (same || loose) {
        return [self p_compareByVolumeSide:a to:b];
    }

    // 不同书:首拼/首字母
    NSString *ka = [self p_letterSortKeyFromTitle:a];
    NSString *kb = [self p_letterSortKeyFromTitle:b];
    NSComparisonResult r = [ka compare:kb];
    if (r != NSOrderedSame) {
        return r;
    }
    NSMutableString *pa = [baseA mutableCopy] ?: [NSMutableString string];
    NSMutableString *pb = [baseB mutableCopy] ?: [NSMutableString string];
    CFStringTransform((__bridge CFMutableStringRef)pa, NULL, kCFStringTransformToLatin, false);
    CFStringTransform((__bridge CFMutableStringRef)pb, NULL, kCFStringTransformToLatin, false);
    CFStringTransform((__bridge CFMutableStringRef)pa, NULL, kCFStringTransformStripDiacritics, false);
    CFStringTransform((__bridge CFMutableStringRef)pb, NULL, kCFStringTransformStripDiacritics, false);
    r = [pa compare:pb options:(NSCaseInsensitiveSearch | NSNumericSearch | NSWidthInsensitiveSearch)];
    if (r != NSOrderedSame) {
        return r;
    }
    return [a compare:b options:(NSCaseInsensitiveSearch | NSNumericSearch | NSWidthInsensitiveSearch)];
}

+ (NSArray <RDBookDetailModel *>*)p_sortedMembers:(NSArray <RDBookDetailModel *>*)members
{
    if (members.count <= 1) {
        return members ?: @[];
    }
    return [members sortedArrayUsingComparator:^NSComparisonResult(RDBookDetailModel *x, RDBookDetailModel *y) {
        return [self compareBookTitles:x.title to:y.title];
    }];
}

/// 按智能排序写回 collectionOrder(0..n-1)
+ (void)p_rewriteOrdersForMembers:(NSArray <RDBookDetailModel *>*)sorted collectionId:(NSInteger)collectionId
{
    NSInteger i = 0;
    for (RDBookDetailModel *m in sorted) {
        [self p_setBookId:m.bookId collectionId:collectionId order:i++];
    }
}

+ (NSArray <RDBookDetailModel *>*)membersOfCollectionId:(NSInteger)collectionId
{
    if (collectionId == 0) {
        return @[];
    }
    __block NSArray *result = nil;
    [[RDDatabaseManager sharedInstance] performSync:^(WCTDatabase *db) {
        result = [db getObjectsOnResults:{
            RDBookDetailModel.bookId,
            RDBookDetailModel.coverImg,
            RDBookDetailModel.title,
            RDBookDetailModel.author,
            RDBookDetailModel.desc,
            RDBookDetailModel.bookUpdate,
            RDBookDetailModel.page,
            RDBookDetailModel.charOffset,
            RDBookDetailModel.readChapterName,
            RDBookDetailModel.readTime,
            RDBookDetailModel.onBookshelf,
            RDBookDetailModel.localPath,
            RDBookDetailModel.fileType,
            RDBookDetailModel.collectionId,
            RDBookDetailModel.collectionOrder,
        } fromTable:kReadRecordTable
             where:RDBookDetailModel.collectionId.is(collectionId)
                   && RDBookDetailModel.bookId < 0
                   && !RDBookDetailModel.fileType.is("collection")];
    }];
    NSArray <RDBookDetailModel *>*sorted = [self p_sortedMembers:result ?: @[]];
    // 若库内 order 与智能序不一致,写回(修复历史错序合集)
    BOOL needRewrite = NO;
    for (NSInteger i = 0; i < (NSInteger)sorted.count; i++) {
        RDBookDetailModel *m = sorted[i];
        if (m.collectionOrder != i) {
            needRewrite = YES;
            break;
        }
    }
    if (needRewrite && sorted.count > 0) {
        [self p_rewriteOrdersForMembers:sorted collectionId:collectionId];
    }
    return sorted;
}

+ (NSArray <RDBookDetailModel *>*)allCollections
{
    __block NSArray *result = nil;
    [[RDDatabaseManager sharedInstance] performSync:^(WCTDatabase *db) {
        result = [db getObjectsOnResults:{
            RDBookDetailModel.bookId,
            RDBookDetailModel.coverImg,
            RDBookDetailModel.title,
            RDBookDetailModel.author,
            RDBookDetailModel.readTime,
            RDBookDetailModel.onBookshelf,
            RDBookDetailModel.fileType,
            RDBookDetailModel.collectionId,
        } fromTable:kReadRecordTable
             where:RDBookDetailModel.onBookshelf.is(YES)
                   && RDBookDetailModel.fileType.is("collection")
                   && RDBookDetailModel.bookId < 0
           orderBy:RDBookDetailModel.readTime.order(WCTOrderedDescending)];
    }];
    return result ?: @[];
}

+ (void)refreshCollectionSummary:(NSInteger)collectionId
{
    if (collectionId == 0) {
        return;
    }
    NSArray <RDBookDetailModel *>*members = [self membersOfCollectionId:collectionId];
    RDBookDetailModel *hub = [RDReadRecordManager getReadRecordWithBookId:collectionId];
    if (!hub || !hub.isCollection) {
        return;
    }
    hub.author = [NSString stringWithFormat:@"合集 · %ld 本", (long)members.count];
    // 封面取排序第一本
    RDBookDetailModel *first = members.firstObject;
    if (first.coverImg.length > 0) {
        hub.coverImg = first.coverImg;
    }
    // 读到:最近阅读成员
    RDBookDetailModel *latest = nil;
    for (RDBookDetailModel *m in members) {
        if (!latest || m.readTime > latest.readTime) {
            latest = m;
        }
    }
    if (latest.title.length > 0) {
        hub.readChapterName = latest.title;
    }
    if (latest && latest.readTime > hub.readTime) {
        hub.readTime = latest.readTime;
    }
    [RDReadRecordManager insertOrReplaceModel:hub touchReadTime:NO];
}

+ (nullable RDBookDetailModel *)createCollectionWithTitle:(NSString *)title
                                                    books:(NSArray <RDBookDetailModel *>*)books
                                             errorMessage:(NSString **)errorMessage
{
    NSMutableArray <RDBookDetailModel *>*valid = [NSMutableArray array];
    for (RDBookDetailModel *b in books) {
        if (!b || b.bookId >= 0 || b.isCollection) {
            continue;
        }
        // 已在其他合集的也允许拉过来
        [valid addObject:b];
    }
    // 允许 1 本起建合集,之后可在合集内继续导入;顶层只显示合集壳
    if (valid.count < 1) {
        if (errorMessage) {
            *errorMessage = @"至少选择两本独立书籍";
        }
        return nil;
    }
    NSString *name = [title stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (name.length == 0) {
        name = valid.firstObject.title.length ? valid.firstObject.title : @"未命名合集";
    }

    NSInteger hubId = [self newCollectionBookId];
    RDBookDetailModel *hub = [[RDBookDetailModel alloc] init];
    hub.bookId = hubId;
    hub.title = name;
    hub.author = [NSString stringWithFormat:@"合集 · %ld 本", (long)valid.count];
    hub.fileType = @"collection";
    hub.onBookshelf = YES;
    hub.collectionId = 0;
    hub.collectionOrder = 0;
    hub.end = YES;
    NSArray <RDBookDetailModel *>*sorted = [self p_sortedMembers:valid];
    hub.coverImg = sorted.firstObject.coverImg;
    hub.readChapterName = sorted.firstObject.title;
    hub.readTime = [NSDate date].timeIntervalSince1970;

    if (![RDReadRecordManager insertOrReplaceModel:hub touchReadTime:YES]) {
        if (errorMessage) {
            *errorMessage = @"创建合集失败";
        }
        return nil;
    }

    [self p_rewriteOrdersForMembers:sorted collectionId:hubId];
    [self refreshCollectionSummary:hubId];
    RDBookDetailModel *fresh = [RDReadRecordManager getReadRecordWithBookId:hubId];
    [self p_notify:fresh];
    return fresh;
}

+ (BOOL)p_setBookId:(NSInteger)bookId collectionId:(NSInteger)collectionId order:(NSInteger)order
{
    if (bookId == 0) {
        return NO;
    }
    RDBookDetailModel *patch = [[RDBookDetailModel alloc] init];
    patch.collectionId = collectionId;
    patch.collectionOrder = order;
    __block BOOL success = NO;
    [[RDDatabaseManager sharedInstance] performSync:^(WCTDatabase *db) {
        success = [db updateRowsInTable:kReadRecordTable
                           onProperties:{RDBookDetailModel.collectionId, RDBookDetailModel.collectionOrder}
                             withObject:patch
                                  where:RDBookDetailModel.bookId.is(bookId)];
    }];
    return success;
}

+ (BOOL)addBookId:(NSInteger)bookId
 toCollectionId:(NSInteger)collectionId
   errorMessage:(NSString **)errorMessage
{
    if (bookId == 0 || collectionId == 0 || bookId == collectionId) {
        if (errorMessage) {
            *errorMessage = @"参数无效";
        }
        return NO;
    }
    RDBookDetailModel *book = [RDReadRecordManager getReadRecordWithBookId:bookId];
    RDBookDetailModel *hub = [RDReadRecordManager getReadRecordWithBookId:collectionId];
    if (!book || book.isCollection) {
        if (errorMessage) {
            *errorMessage = @"只能把普通书籍加入合集";
        }
        return NO;
    }
    if (!hub.isCollection) {
        if (errorMessage) {
            *errorMessage = @"目标不是合集";
        }
        return NO;
    }
    if (book.collectionId == collectionId) {
        return YES;
    }
    // 从旧合集移出
    NSInteger oldCid = book.collectionId;
    // 先挂上合集,再整体智能重排
    if (![self p_setBookId:bookId collectionId:collectionId order:9999]) {
        if (errorMessage) {
            *errorMessage = @"加入合集失败";
        }
        return NO;
    }
    NSArray *all = [self membersOfCollectionId:collectionId]; // 已含智能排序
    [self p_rewriteOrdersForMembers:all collectionId:collectionId];
    if (oldCid != 0 && oldCid != collectionId) {
        [self refreshCollectionSummary:oldCid];
        // 旧合集若不足 2 本则解散
        if ([self membersOfCollectionId:oldCid].count < 2) {
            [self dissolveCollectionId:oldCid];
        }
    }
    [self refreshCollectionSummary:collectionId];
    [self p_notify:[RDReadRecordManager getReadRecordWithBookId:collectionId]];
    return YES;
}

+ (BOOL)removeBookId:(NSInteger)bookId fromCollection:(NSInteger)collectionId
{
    if (bookId == 0) {
        return NO;
    }
    RDBookDetailModel *book = [RDReadRecordManager getReadRecordWithBookId:bookId];
    if (!book || book.collectionId == 0) {
        return YES;
    }
    NSInteger cid = collectionId != 0 ? collectionId : book.collectionId;
    if (![self p_setBookId:bookId collectionId:0 order:0]) {
        return NO;
    }
    // 确保仍在书架
    if (!book.onBookshelf) {
        book.onBookshelf = YES;
        [RDReadRecordManager updateBookshelfState:book];
    }
    [self refreshCollectionSummary:cid];
    NSArray *left = [self membersOfCollectionId:cid]; // 智能排序后的剩余成员
    if (left.count < 2) {
        [self dissolveCollectionId:cid];
    } else {
        [self p_rewriteOrdersForMembers:left collectionId:cid];
        [self p_notify:[RDReadRecordManager getReadRecordWithBookId:cid]];
    }
    return YES;
}

+ (BOOL)dissolveCollectionId:(NSInteger)collectionId
{
    if (collectionId == 0) {
        return NO;
    }
    NSArray <RDBookDetailModel *>*members = [self membersOfCollectionId:collectionId];
    for (RDBookDetailModel *m in members) {
        [self p_setBookId:m.bookId collectionId:0 order:0];
        if (!m.onBookshelf) {
            m.onBookshelf = YES;
            [RDReadRecordManager updateBookshelfState:m];
        }
    }
    [RDReadRecordManager removeBookFromBookShelfWithBookId:collectionId];
    [self p_notify:nil];
    return YES;
}

+ (BOOL)renameCollectionId:(NSInteger)collectionId title:(NSString *)title
{
    NSString *name = [title stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (collectionId == 0 || name.length == 0) {
        return NO;
    }
    RDBookDetailModel *hub = [RDReadRecordManager getReadRecordWithBookId:collectionId];
    if (!hub.isCollection) {
        return NO;
    }
    return [RDReadRecordManager updateTitle:name author:hub.author ?: @"" forBookId:collectionId];
}

@end
