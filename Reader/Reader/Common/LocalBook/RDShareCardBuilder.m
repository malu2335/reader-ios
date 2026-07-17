//
//  RDShareCardBuilder.m
//  Reader
//

#import "RDShareCardBuilder.h"
#import "RDBookDetailModel.h"
#import "RDLocalBookManager.h"

@implementation RDShareCardBuilder

+ (RDShareCardGenre)genreForBook:(RDBookDetailModel *)book
{
    NSString *blob = [NSString stringWithFormat:@"%@ %@", book.category ?: @"", book.title ?: @""].lowercaseString;
    // 中文关键字
    if ([blob containsString:@"玄幻"] || [blob containsString:@"修仙"] || [blob containsString:@"仙侠"] || [blob containsString:@"异界"]) {
        return RDShareCardGenreXuanhuan;
    }
    if ([blob containsString:@"都市"] || [blob containsString:@"职场"] || [blob containsString:@"重生"]) {
        return RDShareCardGenreDushi;
    }
    if ([blob containsString:@"言情"] || [blob containsString:@"甜宠"] || [blob containsString:@"恋爱"] || [blob containsString:@"总裁"]) {
        return RDShareCardGenreYanqing;
    }
    if ([blob containsString:@"武侠"] || [blob containsString:@"江湖"] || [blob containsString:@"侠客"]) {
        return RDShareCardGenreWuxia;
    }
    if ([blob containsString:@"历史"] || [blob containsString:@"穿越"] || [blob containsString:@"王朝"]) {
        return RDShareCardGenreLishi;
    }
    if ([blob containsString:@"科幻"] || [blob containsString:@"星际"] || [blob containsString:@"末世"] || [blob containsString:@"机甲"]) {
        return RDShareCardGenreKehuan;
    }
    if ([blob containsString:@"悬疑"] || [blob containsString:@"推理"] || [blob containsString:@"惊悚"] || [blob containsString:@"犯罪"]) {
        return RDShareCardGenreXuanyi;
    }
    return RDShareCardGenreDefault;
}

+ (void)p_colorsForGenre:(RDShareCardGenre)genre top:(UIColor **)top bottom:(UIColor **)bottom accent:(UIColor **)accent
{
    switch (genre) {
        case RDShareCardGenreXuanhuan:
            *top = [UIColor colorWithRed:0.18 green:0.12 blue:0.38 alpha:1];
            *bottom = [UIColor colorWithRed:0.45 green:0.22 blue:0.55 alpha:1];
            *accent = [UIColor colorWithRed:0.95 green:0.78 blue:0.35 alpha:1];
            break;
        case RDShareCardGenreDushi:
            *top = [UIColor colorWithRed:0.12 green:0.18 blue:0.28 alpha:1];
            *bottom = [UIColor colorWithRed:0.25 green:0.38 blue:0.48 alpha:1];
            *accent = [UIColor colorWithRed:0.45 green:0.75 blue:0.95 alpha:1];
            break;
        case RDShareCardGenreYanqing:
            *top = [UIColor colorWithRed:0.42 green:0.18 blue:0.28 alpha:1];
            *bottom = [UIColor colorWithRed:0.85 green:0.45 blue:0.55 alpha:1];
            *accent = [UIColor colorWithRed:1.0 green:0.88 blue:0.90 alpha:1];
            break;
        case RDShareCardGenreWuxia:
            *top = [UIColor colorWithRed:0.15 green:0.18 blue:0.15 alpha:1];
            *bottom = [UIColor colorWithRed:0.35 green:0.40 blue:0.32 alpha:1];
            *accent = [UIColor colorWithRed:0.85 green:0.75 blue:0.45 alpha:1];
            break;
        case RDShareCardGenreLishi:
            *top = [UIColor colorWithRed:0.28 green:0.18 blue:0.10 alpha:1];
            *bottom = [UIColor colorWithRed:0.55 green:0.38 blue:0.22 alpha:1];
            *accent = [UIColor colorWithRed:0.92 green:0.82 blue:0.55 alpha:1];
            break;
        case RDShareCardGenreKehuan:
            *top = [UIColor colorWithRed:0.05 green:0.08 blue:0.18 alpha:1];
            *bottom = [UIColor colorWithRed:0.10 green:0.25 blue:0.40 alpha:1];
            *accent = [UIColor colorWithRed:0.35 green:0.90 blue:0.95 alpha:1];
            break;
        case RDShareCardGenreXuanyi:
            *top = [UIColor colorWithRed:0.08 green:0.08 blue:0.12 alpha:1];
            *bottom = [UIColor colorWithRed:0.25 green:0.12 blue:0.18 alpha:1];
            *accent = [UIColor colorWithRed:0.90 green:0.35 blue:0.40 alpha:1];
            break;
        default:
            *top = [UIColor colorWithRed:0.22 green:0.20 blue:0.18 alpha:1];
            *bottom = [UIColor colorWithRed:0.42 green:0.36 blue:0.30 alpha:1];
            *accent = [UIColor colorWithRed:0.95 green:0.90 blue:0.80 alpha:1];
            break;
    }
}

+ (NSString *)p_genreTitle:(RDShareCardGenre)genre
{
    switch (genre) {
        case RDShareCardGenreXuanhuan: return @"玄幻 · 一念成神";
        case RDShareCardGenreDushi: return @"都市 · 人间烟火";
        case RDShareCardGenreYanqing: return @"言情 · 心跳片段";
        case RDShareCardGenreWuxia: return @"武侠 · 刀光剑影";
        case RDShareCardGenreLishi: return @"历史 · 长河落日";
        case RDShareCardGenreKehuan: return @"科幻 · 星际回响";
        case RDShareCardGenreXuanyi: return @"悬疑 · 真相一角";
        default: return @"阅读 · 摘句";
    }
}

+ (UIImage *)cardImageWithQuote:(NSString *)quote book:(RDBookDetailModel *)book genre:(RDShareCardGenre)genre
{
    CGSize size = CGSizeMake(1080, 1440);
    UIColor *top = nil, *bottom = nil, *accent = nil;
    [self p_colorsForGenre:genre top:&top bottom:&bottom accent:&accent];

    NSString *body = [quote stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (body.length > 180) {
        body = [[body substringToIndex:180] stringByAppendingString:@"…"];
    }
    if (body.length == 0) {
        body = @"好书值得分享。";
    }

    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:size];
    return [renderer imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
        CGContextRef c = ctx.CGContext;
        // 渐变背景
        CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
        NSArray *colors = @[(__bridge id)top.CGColor, (__bridge id)bottom.CGColor];
        CGFloat locs[] = {0, 1};
        CGGradientRef grad = CGGradientCreateWithColors(space, (__bridge CFArrayRef)colors, locs);
        CGContextDrawLinearGradient(c, grad, CGPointMake(0, 0), CGPointMake(size.width, size.height), 0);
        CGGradientRelease(grad);
        CGColorSpaceRelease(space);

        // 装饰圆环
        CGContextSetStrokeColorWithColor(c, [accent colorWithAlphaComponent:0.25].CGColor);
        CGContextSetLineWidth(c, 6);
        CGContextStrokeEllipseInRect(c, CGRectMake(size.width - 420, -120, 520, 520));
        CGContextStrokeEllipseInRect(c, CGRectMake(-180, size.height - 380, 420, 420));

        // 类型标签
        NSString *tag = [self p_genreTitle:genre];
        NSDictionary *tagAttr = @{
            NSFontAttributeName: [UIFont systemFontOfSize:36 weight:UIFontWeightSemibold],
            NSForegroundColorAttributeName: accent,
        };
        [tag drawAtPoint:CGPointMake(80, 100) withAttributes:tagAttr];

        // 引号
        NSDictionary *qAttr = @{
            NSFontAttributeName: [UIFont systemFontOfSize:160 weight:UIFontWeightUltraLight],
            NSForegroundColorAttributeName: [accent colorWithAlphaComponent:0.35],
        };
        [@"“" drawAtPoint:CGPointMake(60, 220) withAttributes:qAttr];

        // 正文
        NSMutableParagraphStyle *ps = [[NSMutableParagraphStyle alloc] init];
        ps.lineSpacing = 18;
        ps.alignment = NSTextAlignmentLeft;
        NSDictionary *bodyAttr = @{
            NSFontAttributeName: [UIFont systemFontOfSize:52 weight:UIFontWeightMedium],
            NSForegroundColorAttributeName: [UIColor whiteColor],
            NSParagraphStyleAttributeName: ps,
        };
        CGRect bodyRect = CGRectMake(100, 380, size.width - 200, 620);
        [body drawInRect:bodyRect withAttributes:bodyAttr];

        // 底部书名作者
        NSString *meta = [NSString stringWithFormat:@"—— 《%@》%@", book.title ?: @"未知", book.author.length ? [NSString stringWithFormat:@" · %@", book.author] : @""];
        NSDictionary *metaAttr = @{
            NSFontAttributeName: [UIFont systemFontOfSize:34 weight:UIFontWeightRegular],
            NSForegroundColorAttributeName: [UIColor colorWithWhite:1 alpha:0.85],
        };
        [meta drawInRect:CGRectMake(100, size.height - 220, size.width - 200, 80) withAttributes:metaAttr];

        // 小封面
        UIImage *cover = nil;
        if (book.isLocalBook) {
            cover = [RDLocalBookManager coverForBook:book];
        }
        if (cover) {
            CGRect coverRect = CGRectMake(size.width - 260, size.height - 340, 160, 220);
            UIBezierPath *path = [UIBezierPath bezierPathWithRoundedRect:coverRect cornerRadius:12];
            [path addClip];
            [cover drawInRect:coverRect];
        }

        // 品牌脚注
        NSDictionary *footAttr = @{
            NSFontAttributeName: [UIFont systemFontOfSize:28 weight:UIFontWeightLight],
            NSForegroundColorAttributeName: [UIColor colorWithWhite:1 alpha:0.55],
        };
        [@"轻阅 · 本地阅读" drawAtPoint:CGPointMake(100, size.height - 100) withAttributes:footAttr];
    }];
}

+ (NSString *)shareTextWithQuote:(NSString *)quote book:(RDBookDetailModel *)book
{
    NSString *q = [quote stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (q.length > 200) {
        q = [[q substringToIndex:200] stringByAppendingString:@"…"];
    }
    return [NSString stringWithFormat:@"「%@」\n——《%@》%@\n#轻阅 #读书摘句",
            q.length ? q : @"好书值得一读",
            book.title ?: @"未知",
            book.author.length ? [NSString stringWithFormat:@" · %@", book.author] : @""];
}

@end
