//
//  RDShareCardBuilder.m
//  Reader
//

#import "RDShareCardBuilder.h"
#import "RDBookDetailModel.h"
#import "RDLocalBookManager.h"

const CGSize RDShareCardExportPixelSize = {1080, 1440};
const CGSize RDShareCardPreviewPixelSize = {540, 720};

#pragma mark - 意境主题

typedef NS_ENUM(NSInteger, RDCardMood) {
    RDCardMoodPaper = 0,   //纸墨(默认,契合 app 纸质风)
    RDCardMoodNight,       //星夜
    RDCardMoodRain,        //雨声
    RDCardMoodBlade,       //锋芒
    RDCardMoodBloom,       //花信
    RDCardMoodMountain,    //山远
    RDCardMoodSnow,        //霜雪
    RDCardMoodSea,         //海阔
    RDCardMoodEmber,       //炽焰
    RDCardMoodDusk,        //暮色
};
static const NSInteger kRDCardMoodCount = 10;
/// 布局设计基准宽(与导出尺寸一致);所有坐标/字号 × scale
static const CGFloat kRDCardDesignWidth = 1080.0;

//可复现的轻量伪随机:同一句话每次生成完全相同的画面
static uint32_t RDCardRandNext(uint32_t *state) {
    *state = (*state * 1664525u) + 1013904223u;
    return *state;
}
static CGFloat RDCardRand01(uint32_t *state) {
    return (CGFloat)((RDCardRandNext(state) >> 8) & 0xFFFFFF) / (CGFloat)0xFFFFFF;
}

static uint32_t RDCardHash(NSString *text) {
    uint32_t hash = 5381;
    for (NSUInteger i = 0; i < text.length; i++) {
        hash = ((hash << 5) + hash) ^ [text characterAtIndex:i];
    }
    return hash;
}

/// 将大图缩到目标框内再画,避免把原封全分辨率塞进 160×220 槽
static UIImage *RDCardDownsampledCover(UIImage *cover, CGSize targetPoints) {
    if (!cover || cover.size.width <= 0 || cover.size.height <= 0) {
        return cover;
    }
    CGFloat maxSide = MAX(targetPoints.width, targetPoints.height) * 2.0; // 略超目标,圆角裁切仍清晰
    CGFloat srcMax = MAX(cover.size.width, cover.size.height);
    if (srcMax <= maxSide) {
        return cover;
    }
    CGFloat scale = maxSide / srcMax;
    CGSize out = CGSizeMake(ceil(cover.size.width * scale), ceil(cover.size.height * scale));
    UIGraphicsImageRendererFormat *fmt = [UIGraphicsImageRendererFormat preferredFormat];
    fmt.scale = 1;
    fmt.opaque = NO;
    UIGraphicsImageRenderer *r = [[UIGraphicsImageRenderer alloc] initWithSize:out format:fmt];
    return [r imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
        [cover drawInRect:CGRectMake(0, 0, out.width, out.height)];
    }];
}

@implementation RDShareCardBuilder

/// 内容意境分析:各主题关键词计分,最高者胜;零命中按哈希稳定散列
+ (RDCardMood)p_moodForQuote:(NSString *)quote
{
    if (quote.length == 0) {
        return RDCardMoodPaper;
    }
    // 静态表,避免每次选区刷新都重建字典
    static NSDictionary <NSNumber *, NSArray <NSString *>*>*keywords;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        keywords = @{
            @(RDCardMoodNight):    @[@"夜", @"月", @"星", @"灯火", @"黑暗", @"梦乡"],
            @(RDCardMoodRain):     @[@"雨", @"泪", @"哭", @"伤", @"离别", @"愁", @"湿"],
            @(RDCardMoodBlade):    @[@"剑", @"刀", @"血", @"战", @"杀", @"敌", @"锋", @"枪"],
            @(RDCardMoodBloom):    @[@"花", @"春", @"暖", @"笑", @"爱", @"甜", @"吻", @"喜欢"],
            @(RDCardMoodMountain): @[@"山", @"云", @"风", @"江", @"湖", @"林", @"远方", @"路"],
            @(RDCardMoodSnow):     @[@"雪", @"冬", @"寒", @"冰", @"霜", @"冷"],
            @(RDCardMoodSea):      @[@"海", @"浪", @"波", @"舟", @"帆", @"潮"],
            @(RDCardMoodEmber):    @[@"火", @"焰", @"燃", @"烈", @"怒", @"灼", @"光芒"],
            @(RDCardMoodDusk):     @[@"梦", @"忆", @"时光", @"黄昏", @"岁月", @"从前", @"往事"],
        };
    });
    RDCardMood best = RDCardMoodPaper;
    NSInteger bestScore = 0;
    for (NSNumber *mood in keywords) {
        NSInteger score = 0;
        for (NSString *word in keywords[mood]) {
            if ([quote containsString:word]) {
                score++;
            }
        }
        if (score > bestScore) {
            bestScore = score;
            best = (RDCardMood)mood.integerValue;
        }
    }
    if (bestScore > 0) {
        return best;
    }
    return (RDCardMood)(RDCardHash(quote) % kRDCardMoodCount);
}

+ (NSString *)p_moodTitle:(RDCardMood)mood
{
    switch (mood) {
        case RDCardMoodNight:    return @"星夜 · 摘句";
        case RDCardMoodRain:     return @"雨声 · 摘句";
        case RDCardMoodBlade:    return @"锋芒 · 摘句";
        case RDCardMoodBloom:    return @"花信 · 摘句";
        case RDCardMoodMountain: return @"山远 · 摘句";
        case RDCardMoodSnow:     return @"霜雪 · 摘句";
        case RDCardMoodSea:      return @"海阔 · 摘句";
        case RDCardMoodEmber:    return @"炽焰 · 摘句";
        case RDCardMoodDusk:     return @"暮色 · 摘句";
        default:                 return @"纸墨 · 摘句";
    }
}

//主题配色:top/bottom 渐变、accent 点缀、isLight 表示浅底(正文用深色)
+ (void)p_mood:(RDCardMood)mood top:(UIColor **)top bottom:(UIColor **)bottom accent:(UIColor **)accent isLight:(BOOL *)isLight
{
    BOOL light = NO;
    switch (mood) {
        case RDCardMoodNight:
            *top = [UIColor colorWithRed:0.05 green:0.06 blue:0.16 alpha:1];
            *bottom = [UIColor colorWithRed:0.16 green:0.18 blue:0.35 alpha:1];
            *accent = [UIColor colorWithRed:0.95 green:0.88 blue:0.60 alpha:1];
            break;
        case RDCardMoodRain:
            *top = [UIColor colorWithRed:0.16 green:0.22 blue:0.28 alpha:1];
            *bottom = [UIColor colorWithRed:0.30 green:0.38 blue:0.44 alpha:1];
            *accent = [UIColor colorWithRed:0.70 green:0.82 blue:0.90 alpha:1];
            break;
        case RDCardMoodBlade:
            *top = [UIColor colorWithRed:0.10 green:0.07 blue:0.09 alpha:1];
            *bottom = [UIColor colorWithRed:0.28 green:0.12 blue:0.15 alpha:1];
            *accent = [UIColor colorWithRed:0.90 green:0.55 blue:0.45 alpha:1];
            break;
        case RDCardMoodBloom:
            *top = [UIColor colorWithRed:1.00 green:0.94 blue:0.93 alpha:1];
            *bottom = [UIColor colorWithRed:0.97 green:0.80 blue:0.80 alpha:1];
            *accent = [UIColor colorWithRed:0.72 green:0.32 blue:0.40 alpha:1];
            light = YES;
            break;
        case RDCardMoodMountain:
            *top = [UIColor colorWithRed:0.91 green:0.94 blue:0.91 alpha:1];
            *bottom = [UIColor colorWithRed:0.76 green:0.83 blue:0.78 alpha:1];
            *accent = [UIColor colorWithRed:0.28 green:0.40 blue:0.34 alpha:1];
            light = YES;
            break;
        case RDCardMoodSnow:
            *top = [UIColor colorWithRed:0.93 green:0.96 blue:0.98 alpha:1];
            *bottom = [UIColor colorWithRed:0.78 green:0.86 blue:0.92 alpha:1];
            *accent = [UIColor colorWithRed:0.30 green:0.45 blue:0.58 alpha:1];
            light = YES;
            break;
        case RDCardMoodSea:
            *top = [UIColor colorWithRed:0.04 green:0.22 blue:0.30 alpha:1];
            *bottom = [UIColor colorWithRed:0.09 green:0.40 blue:0.48 alpha:1];
            *accent = [UIColor colorWithRed:0.60 green:0.90 blue:0.90 alpha:1];
            break;
        case RDCardMoodEmber:
            *top = [UIColor colorWithRed:0.12 green:0.06 blue:0.05 alpha:1];
            *bottom = [UIColor colorWithRed:0.38 green:0.14 blue:0.07 alpha:1];
            *accent = [UIColor colorWithRed:1.00 green:0.70 blue:0.35 alpha:1];
            break;
        case RDCardMoodDusk:
            *top = [UIColor colorWithRed:0.22 green:0.16 blue:0.33 alpha:1];
            *bottom = [UIColor colorWithRed:0.48 green:0.30 blue:0.48 alpha:1];
            *accent = [UIColor colorWithRed:0.98 green:0.80 blue:0.60 alpha:1];
            break;
        default: //纸墨
            *top = [UIColor colorWithRed:0.96 green:0.94 blue:0.89 alpha:1];
            *bottom = [UIColor colorWithRed:0.91 green:0.87 blue:0.79 alpha:1];
            *accent = [UIColor colorWithRed:0.56 green:0.36 blue:0.23 alpha:1];
            light = YES;
            break;
    }
    if (isLight) {
        *isLight = light;
    }
}

//主题装饰:纯 CoreGraphics 程序化绘制,seed 保证同句同画;scale 同步缩粒子数与线宽
+ (void)p_drawMotif:(RDCardMood)mood context:(CGContextRef)c size:(CGSize)size accent:(UIColor *)accent seed:(uint32_t)seed scale:(CGFloat)s
{
    uint32_t state = seed ?: 1;
    // 预览尺寸下减少粒子,保持视觉密度近似、降低 CPU
    CGFloat density = MAX(0.45, MIN(1.0, s));
    switch (mood) {
        case RDCardMoodNight: {
            int n = (int)lround(46 * density);
            for (int i = 0; i < n; i++) {
                CGFloat x = RDCardRand01(&state) * size.width;
                CGFloat y = RDCardRand01(&state) * size.height * 0.7;
                CGFloat r = (1.5 + RDCardRand01(&state) * 3.5) * s;
                CGFloat a = 0.25 + RDCardRand01(&state) * 0.6;
                CGContextSetFillColorWithColor(c, [accent colorWithAlphaComponent:a].CGColor);
                CGContextFillEllipseInRect(c, CGRectMake(x, y, r, r));
            }
            CGFloat mx = size.width - (240 + RDCardRand01(&state) * 120) * s;
            CGFloat moon = 120 * s;
            CGContextSetFillColorWithColor(c, [accent colorWithAlphaComponent:0.85].CGColor);
            CGContextFillEllipseInRect(c, CGRectMake(mx, 120 * s, moon, moon));
            CGContextSetFillColorWithColor(c, [[UIColor colorWithRed:0.05 green:0.06 blue:0.16 alpha:1] colorWithAlphaComponent:0.92].CGColor);
            CGContextFillEllipseInRect(c, CGRectMake(mx - 34 * s, 108 * s, moon, moon));
            break;
        }
        case RDCardMoodRain: {
            CGContextSetLineCap(c, kCGLineCapRound);
            int n = (int)lround(36 * density);
            for (int i = 0; i < n; i++) {
                CGFloat x = RDCardRand01(&state) * size.width;
                CGFloat y = RDCardRand01(&state) * size.height;
                CGFloat len = (40 + RDCardRand01(&state) * 90) * s;
                CGFloat a = 0.10 + RDCardRand01(&state) * 0.22;
                CGContextSetStrokeColorWithColor(c, [accent colorWithAlphaComponent:a].CGColor);
                CGContextSetLineWidth(c, (2 + RDCardRand01(&state) * 2) * s);
                CGContextMoveToPoint(c, x, y);
                CGContextAddLineToPoint(c, x - len * 0.35, y + len);
                CGContextStrokePath(c);
            }
            break;
        }
        case RDCardMoodBlade: {
            for (int i = 0; i < 2; i++) {
                CGFloat y0 = size.height * (0.18 + 0.5 * i) + RDCardRand01(&state) * 60 * s;
                CGContextSetStrokeColorWithColor(c, [accent colorWithAlphaComponent:0.30].CGColor);
                CGContextSetLineWidth(c, 5 * s);
                CGContextMoveToPoint(c, -50 * s, y0 + 180 * s);
                CGContextAddLineToPoint(c, size.width + 50 * s, y0 - 180 * s);
                CGContextStrokePath(c);
            }
            int n = (int)lround(18 * density);
            for (int i = 0; i < n; i++) {
                CGFloat x = RDCardRand01(&state) * size.width;
                CGFloat y = RDCardRand01(&state) * size.height;
                CGFloat r = (1.5 + RDCardRand01(&state) * 3) * s;
                CGContextSetFillColorWithColor(c, [accent colorWithAlphaComponent:0.20 + RDCardRand01(&state) * 0.35].CGColor);
                CGContextFillEllipseInRect(c, CGRectMake(x, y, r, r));
            }
            break;
        }
        case RDCardMoodBloom: {
            int n = (int)lround(22 * density);
            for (int i = 0; i < n; i++) {
                CGFloat x = RDCardRand01(&state) * size.width;
                CGFloat y = RDCardRand01(&state) * size.height;
                CGFloat r = (8 + RDCardRand01(&state) * 26) * s;
                CGFloat a = 0.08 + RDCardRand01(&state) * 0.18;
                CGContextSetFillColorWithColor(c, [accent colorWithAlphaComponent:a].CGColor);
                CGContextFillEllipseInRect(c, CGRectMake(x, y, r, r * (0.55 + RDCardRand01(&state) * 0.45)));
            }
            break;
        }
        case RDCardMoodMountain: {
            for (int layer = 0; layer < 3; layer++) {
                CGFloat base = size.height * (0.72 + 0.09 * layer);
                CGFloat alpha = 0.10 + 0.08 * layer;
                CGMutablePathRef path = CGPathCreateMutable();
                CGPathMoveToPoint(path, NULL, 0, size.height);
                CGPathAddLineToPoint(path, NULL, 0, base);
                CGFloat x = 0;
                while (x < size.width) {
                    CGFloat peakW = (180 + RDCardRand01(&state) * 240) * s;
                    CGFloat peakH = (60 + RDCardRand01(&state) * 140) * s;
                    CGPathAddQuadCurveToPoint(path, NULL, x + peakW / 2, base - peakH, x + peakW, base);
                    x += peakW;
                }
                CGPathAddLineToPoint(path, NULL, size.width, size.height);
                CGPathCloseSubpath(path);
                CGContextAddPath(c, path);
                CGContextSetFillColorWithColor(c, [accent colorWithAlphaComponent:alpha].CGColor);
                CGContextFillPath(c);
                CGPathRelease(path);
            }
            break;
        }
        case RDCardMoodSnow: {
            int n = (int)lround(42 * density);
            for (int i = 0; i < n; i++) {
                CGFloat x = RDCardRand01(&state) * size.width;
                CGFloat y = RDCardRand01(&state) * size.height;
                CGFloat r = (2 + RDCardRand01(&state) * 6) * s;
                CGFloat a = 0.20 + RDCardRand01(&state) * 0.45;
                CGContextSetFillColorWithColor(c, [[UIColor whiteColor] colorWithAlphaComponent:a].CGColor);
                CGContextFillEllipseInRect(c, CGRectMake(x, y, r, r));
            }
            break;
        }
        case RDCardMoodSea: {
            CGContextSetLineWidth(c, 4 * s);
            for (int row = 0; row < 5; row++) {
                CGFloat y = size.height * (0.62 + row * 0.08);
                CGFloat a = 0.12 + row * 0.06;
                CGContextSetStrokeColorWithColor(c, [accent colorWithAlphaComponent:a].CGColor);
                CGFloat x = -40 * s + RDCardRand01(&state) * 60 * s;
                while (x < size.width + 40 * s) {
                    CGFloat w = (140 + RDCardRand01(&state) * 60) * s;
                    CGContextMoveToPoint(c, x, y);
                    CGContextAddQuadCurveToPoint(c, x + w / 2, y - 34 * s, x + w, y);
                    CGContextStrokePath(c);
                    x += w;
                }
            }
            break;
        }
        case RDCardMoodEmber: {
            int n = (int)lround(34 * density);
            for (int i = 0; i < n; i++) {
                CGFloat x = RDCardRand01(&state) * size.width;
                CGFloat y = size.height * 0.3 + RDCardRand01(&state) * size.height * 0.7;
                CGFloat r = (2 + RDCardRand01(&state) * 5) * s;
                CGFloat a = 0.20 + RDCardRand01(&state) * 0.55;
                CGContextSetFillColorWithColor(c, [accent colorWithAlphaComponent:a].CGColor);
                CGContextFillEllipseInRect(c, CGRectMake(x, y, r, r));
            }
            break;
        }
        case RDCardMoodDusk: {
            for (int i = 0; i < 4; i++) {
                CGFloat r = (160 + RDCardRand01(&state) * 260) * s;
                CGFloat x = RDCardRand01(&state) * size.width - r / 2;
                CGFloat y = RDCardRand01(&state) * size.height * 0.5 - r / 2;
                CGContextSetFillColorWithColor(c, [accent colorWithAlphaComponent:0.06 + RDCardRand01(&state) * 0.08].CGColor);
                CGContextFillEllipseInRect(c, CGRectMake(x, y, r, r));
            }
            CGContextSetStrokeColorWithColor(c, [accent colorWithAlphaComponent:0.35].CGColor);
            CGContextSetLineWidth(c, 3 * s);
            CGContextMoveToPoint(c, 0, size.height * 0.78);
            CGContextAddLineToPoint(c, size.width, size.height * 0.78);
            CGContextStrokePath(c);
            break;
        }
        default: {
            CGContextSetStrokeColorWithColor(c, [accent colorWithAlphaComponent:0.45].CGColor);
            CGContextSetLineWidth(c, 3 * s);
            CGContextStrokeRect(c, CGRectMake(46 * s, 46 * s, size.width - 92 * s, size.height - 92 * s));
            CGContextSetLineWidth(c, 1.5 * s);
            CGContextStrokeRect(c, CGRectMake(62 * s, 62 * s, size.width - 124 * s, size.height - 124 * s));
            CGContextSetFillColorWithColor(c, [[UIColor colorWithRed:0.72 green:0.25 blue:0.20 alpha:1] colorWithAlphaComponent:0.85].CGColor);
            UIBezierPath *seal = [UIBezierPath bezierPathWithRoundedRect:CGRectMake(size.width - 170 * s, 108 * s, 64 * s, 64 * s) cornerRadius:8 * s];
            CGContextAddPath(c, seal.CGPath);
            CGContextFillPath(c);
            break;
        }
    }
}

+ (UIImage *)cardImageWithQuote:(NSString *)quote book:(RDBookDetailModel *)book
{
    return [self cardImageWithQuote:quote book:book pixelSize:RDShareCardExportPixelSize cover:nil];
}

+ (UIImage *)cardImageWithQuote:(NSString *)quote
                           book:(RDBookDetailModel *)book
                      pixelSize:(CGSize)pixelSize
                          cover:(UIImage *)cover
{
    CGSize size = pixelSize;
    if (size.width < 32 || size.height < 32 || !isfinite(size.width) || !isfinite(size.height)) {
        size = RDShareCardExportPixelSize;
    }
    CGFloat s = size.width / kRDCardDesignWidth;
    if (s <= 0 || !isfinite(s)) {
        s = 1;
        size = RDShareCardExportPixelSize;
    }

    NSString *body = [quote stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (body.length > 180) {
        body = [[body substringToIndex:180] stringByAppendingString:@"…"];
    }
    if (body.length == 0) {
        body = @"好书值得分享。";
    }

    RDCardMood mood = [self p_moodForQuote:body];
    uint32_t seed = RDCardHash(body);
    UIColor *top = nil, *bottom = nil, *accent = nil;
    BOOL isLight = NO;
    [self p_mood:mood top:&top bottom:&bottom accent:&accent isLight:&isLight];
    UIColor *bodyColor = isLight ? [UIColor colorWithRed:0.18 green:0.15 blue:0.12 alpha:1] : [UIColor whiteColor];
    UIColor *metaColor = isLight ? [bodyColor colorWithAlphaComponent:0.75] : [UIColor colorWithWhite:1 alpha:0.85];
    UIColor *footColor = isLight ? [bodyColor colorWithAlphaComponent:0.45] : [UIColor colorWithWhite:1 alpha:0.55];

    // 封面:优先用调用方缓存;否则仅导出路径同步读盘
    UIImage *coverImage = cover;
    if (!coverImage && book.isLocalBook) {
        coverImage = [RDLocalBookManager coverForBook:book];
    }
    CGSize coverSlot = CGSizeMake(160 * s, 220 * s);
    if (coverImage) {
        coverImage = RDCardDownsampledCover(coverImage, coverSlot);
    }

    // 固定 scale=1:pixelSize 即输出像素;避免 3x 机型渲出 9 倍像素
    UIGraphicsImageRendererFormat *format = [UIGraphicsImageRendererFormat preferredFormat];
    format.scale = 1;
    format.opaque = YES;
    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:size format:format];
    return [renderer imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
        CGContextRef c = ctx.CGContext;
        CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
        NSArray *colors = @[(__bridge id)top.CGColor, (__bridge id)bottom.CGColor];
        CGFloat locs[] = {0, 1};
        CGGradientRef grad = CGGradientCreateWithColors(space, (__bridge CFArrayRef)colors, locs);
        CGContextDrawLinearGradient(c, grad, CGPointMake(0, 0), CGPointMake(size.width * 0.35, size.height), 0);
        CGGradientRelease(grad);
        CGColorSpaceRelease(space);

        [self p_drawMotif:mood context:c size:size accent:accent seed:seed scale:s];

        NSString *tag = [self p_moodTitle:mood];
        NSDictionary *tagAttr = @{
            NSFontAttributeName: [UIFont systemFontOfSize:36 * s weight:UIFontWeightSemibold],
            NSForegroundColorAttributeName: accent,
        };
        [tag drawAtPoint:CGPointMake(80 * s, 100 * s) withAttributes:tagAttr];

        NSDictionary *qAttr = @{
            NSFontAttributeName: [UIFont systemFontOfSize:160 * s weight:UIFontWeightUltraLight],
            NSForegroundColorAttributeName: [accent colorWithAlphaComponent:0.35],
        };
        [@"“" drawAtPoint:CGPointMake(60 * s, 220 * s) withAttributes:qAttr];

        NSMutableParagraphStyle *ps = [[NSMutableParagraphStyle alloc] init];
        ps.lineSpacing = 18 * s;
        ps.alignment = NSTextAlignmentLeft;
        NSDictionary *bodyAttr = @{
            NSFontAttributeName: [UIFont systemFontOfSize:52 * s weight:UIFontWeightMedium],
            NSForegroundColorAttributeName: bodyColor,
            NSParagraphStyleAttributeName: ps,
        };
        CGRect bodyRect = CGRectMake(100 * s, 380 * s, size.width - 200 * s, 620 * s);
        [body drawInRect:bodyRect withAttributes:bodyAttr];

        NSString *meta = [NSString stringWithFormat:@"—— 《%@》%@", book.title ?: @"未知", book.author.length ? [NSString stringWithFormat:@" · %@", book.author] : @""];
        NSDictionary *metaAttr = @{
            NSFontAttributeName: [UIFont systemFontOfSize:34 * s weight:UIFontWeightRegular],
            NSForegroundColorAttributeName: metaColor,
        };
        [meta drawInRect:CGRectMake(100 * s, size.height - 220 * s, size.width - 200 * s, 80 * s) withAttributes:metaAttr];

        if (coverImage) {
            CGContextSaveGState(c);
            CGRect coverRect = CGRectMake(size.width - 260 * s, size.height - 340 * s, coverSlot.width, coverSlot.height);
            UIBezierPath *path = [UIBezierPath bezierPathWithRoundedRect:coverRect cornerRadius:12 * s];
            [path addClip];
            // aspect fill into slot
            CGFloat fill = MAX(coverRect.size.width / coverImage.size.width,
                               coverRect.size.height / coverImage.size.height);
            CGSize draw = CGSizeMake(coverImage.size.width * fill, coverImage.size.height * fill);
            CGRect drawRect = CGRectMake(CGRectGetMidX(coverRect) - draw.width / 2,
                                         CGRectGetMidY(coverRect) - draw.height / 2,
                                         draw.width, draw.height);
            [coverImage drawInRect:drawRect];
            CGContextRestoreGState(c);
        }

        NSDictionary *footAttr = @{
            NSFontAttributeName: [UIFont systemFontOfSize:28 * s weight:UIFontWeightLight],
            NSForegroundColorAttributeName: footColor,
        };
        [@"纸羽轻阅 · 轻装每一页" drawAtPoint:CGPointMake(100 * s, size.height - 100 * s) withAttributes:footAttr];
    }];
}

+ (NSString *)quoteFromText:(NSString *)text
          minSentenceLength:(NSInteger)minSentenceLength
                  maxLength:(NSInteger)maxLength
{
    NSString *source = [text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (source.length == 0) {
        return nil;
    }
    NSArray *parts = [source componentsSeparatedByCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"。！？\n"]];
    NSMutableString *picked = [NSMutableString string];
    for (NSString *p in parts) {
        NSString *t = [p stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if ((NSInteger)t.length < minSentenceLength) {
            continue;
        }
        if (picked.length) {
            [picked appendString:@"。"];
        }
        [picked appendString:t];
        if ((NSInteger)picked.length > maxLength) {
            break;
        }
    }
    if (picked.length) {
        return [picked stringByAppendingString:@"。"];
    }
    if ((NSInteger)source.length > maxLength * 2) {
        return [[source substringToIndex:maxLength * 2] stringByAppendingString:@"…"];
    }
    return source;
}

@end

#pragma mark - 选句分享面板

@interface RDQuoteShareController () <UITextViewDelegate>
@property (nonatomic,strong) UILabel *titleLabel;
@property (nonatomic,strong) UILabel *hintLabel;
@property (nonatomic,strong) UIImageView *previewView;
@property (nonatomic,strong) UITextView *textView;
@property (nonatomic,strong) UIButton *shareButton;
@property (nonatomic,strong) UIButton *closeButton;
/// 每次发起重绘时递增;渲染在后台完成后仅当仍是最新一次才应用
@property (nonatomic,assign) NSUInteger previewGeneration;
/// 选区变化去抖用的独立计数
@property (nonatomic,assign) NSUInteger selectionDebounceToken;
/// 会话内缓存封面,避免每次预览读盘解码
@property (nonatomic,strong,nullable) UIImage *cachedCover;
@property (nonatomic,assign) BOOL coverLoadStarted;
/// 预览缓存:同句不再半分辨率重渲
@property (nonatomic,copy,nullable) NSString *cachedPreviewQuote;
@property (nonatomic,strong,nullable) UIImage *cachedPreviewImage;
/// 导出缓存:分享时若与当前句相同则直接用全分辨率结果
@property (nonatomic,copy,nullable) NSString *cachedExportQuote;
@property (nonatomic,strong,nullable) UIImage *cachedExportImage;
/// 串行渲染队列:选区连发时排队,配合 generation 丢弃过期结果
@property (nonatomic,strong) dispatch_queue_t renderQueue;
@end

@implementation RDQuoteShareController

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.view.backgroundColor = RDSurfaceColor;
    self.renderQueue = dispatch_queue_create("xyz.malu2335.reader.quote-card-render", DISPATCH_QUEUE_SERIAL);

    self.titleLabel = [[UILabel alloc] init];
    self.titleLabel.text = @"分享金句";
    self.titleLabel.font = RDTitleFont19;
    self.titleLabel.textColor = RDBlackColor;
    [self.view addSubview:self.titleLabel];

    self.closeButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.closeButton setTitle:@"关闭" forState:UIControlStateNormal];
    self.closeButton.titleLabel.font = RDFont16;
    [self.closeButton setTitleColor:RDGrayColor forState:UIControlStateNormal];
    [self.closeButton addTarget:self action:@selector(p_close) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.closeButton];

    self.hintLabel = [[UILabel alloc] init];
    self.hintLabel.text = @"长按下方文字选句,背景随内容意境变化;不选则用本页首句";
    self.hintLabel.font = RDFont13;
    self.hintLabel.textColor = RDLightGrayColor;
    self.hintLabel.numberOfLines = 2;
    [self.view addSubview:self.hintLabel];

    self.previewView = [[UIImageView alloc] init];
    self.previewView.contentMode = UIViewContentModeScaleAspectFit;
    self.previewView.layer.cornerRadius = 10;
    self.previewView.clipsToBounds = YES;
    [self.view addSubview:self.previewView];

    self.textView = [[UITextView alloc] init];
    self.textView.editable = NO;
    self.textView.selectable = YES;
    self.textView.delegate = self;
    self.textView.backgroundColor = RDBackgroudColor;
    self.textView.layer.cornerRadius = 12;
    self.textView.textContainerInset = UIEdgeInsetsMake(14, 12, 14, 12);
    NSMutableParagraphStyle *ps = [[NSMutableParagraphStyle alloc] init];
    ps.lineSpacing = 8;
    self.textView.attributedText = [[NSAttributedString alloc] initWithString:self.pageText ?: @""
                                                                   attributes:@{
        NSFontAttributeName: RDFont16,
        NSForegroundColorAttributeName: RDBlackColor,
        NSParagraphStyleAttributeName: ps,
    }];
    [self.view addSubview:self.textView];

    self.shareButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.shareButton setTitle:@"生成卡片并分享" forState:UIControlStateNormal];
    self.shareButton.titleLabel.font = RDBoldFont17;
    [self.shareButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    self.shareButton.backgroundColor = RDAccentColor;
    self.shareButton.layer.cornerRadius = 24;
    [self.shareButton addTarget:self action:@selector(p_share) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.shareButton];

    [self p_preloadCoverIfNeeded];
    [self p_refreshPreview];
}

- (void)p_preloadCoverIfNeeded
{
    if (self.coverLoadStarted || !self.book.isLocalBook) {
        return;
    }
    self.coverLoadStarted = YES;
    RDBookDetailModel *book = self.book;
    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        UIImage *cover = [RDLocalBookManager coverForBook:book];
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) self = weakSelf;
            if (!self) {
                return;
            }
            self.cachedCover = cover;
            // 封面到位后若预览已出且无封面,用同句再渲一次预览(轻量尺寸)
            if (cover && self.cachedPreviewQuote.length > 0) {
                self.cachedPreviewQuote = nil;
                self.cachedPreviewImage = nil;
                self.cachedExportQuote = nil;
                self.cachedExportImage = nil;
                [self p_refreshPreview];
            }
        });
    });
}

- (NSString *)p_currentQuote
{
    NSRange sel = self.textView.selectedRange;
    if (sel.length > 0 && NSMaxRange(sel) <= self.textView.text.length) {
        NSString *picked = [[self.textView.text substringWithRange:sel] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (picked.length > 0) {
            return picked;
        }
    }
    return [RDShareCardBuilder quoteFromText:self.pageText minSentenceLength:4 maxLength:60];
}

- (void)p_refreshPreview
{
    NSString *quote = [self p_currentQuote];
    if (quote.length == 0) {
        self.previewView.image = nil;
        self.cachedPreviewQuote = nil;
        self.cachedPreviewImage = nil;
        return;
    }
    // 同句命中预览缓存:选区抖动回同一句时零渲染
    if ([quote isEqualToString:self.cachedPreviewQuote] && self.cachedPreviewImage) {
        self.previewView.image = self.cachedPreviewImage;
        return;
    }

    NSUInteger generation = ++self.previewGeneration;
    RDBookDetailModel *book = self.book;
    UIImage *cover = self.cachedCover;
    __weak typeof(self) weakSelf = self;
    dispatch_async(self.renderQueue, ^{
        // 预览用半分辨率 + 比例缩放布局,选区拖拽时明显更轻
        UIImage *card = [RDShareCardBuilder cardImageWithQuote:quote
                                                          book:book
                                                     pixelSize:RDShareCardPreviewPixelSize
                                                         cover:cover];
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) self = weakSelf;
            if (!self || generation != self.previewGeneration) {
                return;
            }
            self.cachedPreviewQuote = quote;
            self.cachedPreviewImage = card;
            self.previewView.image = card;
        });
    });
}

- (void)textViewDidChangeSelection:(UITextView *)textView
{
    // 拖拽选区手柄时连续触发;去抖到停顿后再渲染。
    // dispatch_after 在 common modes 下也会排队,tracking 时不像
    // performSelector:afterDelay: 那样被饿死。
    NSUInteger token = ++self.selectionDebounceToken;
    __weak typeof(self) weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.12 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        __strong typeof(weakSelf) self = weakSelf;
        if (!self || self.selectionDebounceToken != token) {
            return;
        }
        [self p_refreshPreview];
    });
}

- (void)viewDidLayoutSubviews
{
    [super viewDidLayoutSubviews];
    CGFloat width = self.view.bounds.size.width;
    CGFloat top = 18;
    self.titleLabel.frame = CGRectMake(20, top, width - 100, 28);
    self.closeButton.frame = CGRectMake(width - 76, top, 56, 28);
    self.hintLabel.frame = CGRectMake(20, CGRectGetMaxY(self.titleLabel.frame) + 6, width - 40, 36);
    CGFloat bottomSafe = self.view.safeAreaInsets.bottom;
    CGFloat buttonHeight = 48;
    self.shareButton.frame = CGRectMake(20, self.view.bounds.size.height - bottomSafe - buttonHeight - 14, width - 40, buttonHeight);
    CGFloat previewTop = CGRectGetMaxY(self.hintLabel.frame) + 10;
    CGFloat available = CGRectGetMinY(self.shareButton.frame) - previewTop - 24;
    CGFloat previewHeight = MIN(available * 0.45, (width - 40) * 4.0 / 3.0);
    self.previewView.frame = CGRectMake(20, previewTop, width - 40, previewHeight);
    CGFloat textTop = CGRectGetMaxY(self.previewView.frame) + 12;
    self.textView.frame = CGRectMake(20, textTop, width - 40, CGRectGetMinY(self.shareButton.frame) - textTop - 12);
}

- (void)p_close
{
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (UIImage *)p_exportCardForQuote:(NSString *)quote
{
    if (quote.length == 0) {
        return nil;
    }
    if ([quote isEqualToString:self.cachedExportQuote] && self.cachedExportImage) {
        return self.cachedExportImage;
    }
    // 分享必须全分辨率;不复用预览半尺寸图
    UIImage *card = [RDShareCardBuilder cardImageWithQuote:quote
                                                      book:self.book
                                                 pixelSize:RDShareCardExportPixelSize
                                                     cover:self.cachedCover];
    self.cachedExportQuote = quote;
    self.cachedExportImage = card;
    return card;
}

- (void)p_share
{
    NSString *quote = [self p_currentQuote];
    if (quote.length == 0) {
        [RDToastView showText:@"本页没有可分享的文字" delay:1.2 inView:self.view];
        return;
    }

    // 若导出已缓存则主线程秒开;否则后台渲全尺寸再 present,避免卡住分享按钮
    if ([quote isEqualToString:self.cachedExportQuote] && self.cachedExportImage) {
        [self p_presentShareWithImage:self.cachedExportImage];
        return;
    }

    self.shareButton.enabled = NO;
    [self.shareButton setTitle:@"生成中…" forState:UIControlStateNormal];
    RDBookDetailModel *book = self.book;
    UIImage *cover = self.cachedCover;
    __weak typeof(self) weakSelf = self;
    dispatch_async(self.renderQueue, ^{
        UIImage *card = [RDShareCardBuilder cardImageWithQuote:quote
                                                          book:book
                                                     pixelSize:RDShareCardExportPixelSize
                                                         cover:cover];
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) self = weakSelf;
            if (!self) {
                return;
            }
            self.shareButton.enabled = YES;
            [self.shareButton setTitle:@"生成卡片并分享" forState:UIControlStateNormal];
            if (!card) {
                [RDToastView showText:@"卡片生成失败" delay:1.2 inView:self.view];
                return;
            }
            self.cachedExportQuote = quote;
            self.cachedExportImage = card;
            [self p_presentShareWithImage:card];
        });
    });
}

- (void)p_presentShareWithImage:(UIImage *)card
{
    // 落 jpg:渐变卡 PNG 体积大一个量级;0.88 质量肉眼无差
    NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:
                      [NSString stringWithFormat:@"quote_card_%u.jpg", arc4random()]];
    NSData *jpg = UIImageJPEGRepresentation(card, 0.88);
    if (!jpg || ![jpg writeToFile:path atomically:YES]) {
        [RDToastView showText:@"卡片生成失败" delay:1.2 inView:self.view];
        return;
    }
    NSURL *fileURL = [NSURL fileURLWithPath:path];
    UIActivityViewController *avc = [[UIActivityViewController alloc] initWithActivityItems:@[fileURL] applicationActivities:nil];
    avc.popoverPresentationController.sourceView = self.shareButton;
    avc.popoverPresentationController.sourceRect = self.shareButton.bounds;
    // 分享结束后清临时文件
    avc.completionWithItemsHandler = ^(UIActivityType activityType, BOOL completed, NSArray *returnedItems, NSError *activityError) {
        [[NSFileManager defaultManager] removeItemAtPath:path error:nil];
    };
    [self presentViewController:avc animated:YES completion:nil];
}

@end
