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
@end

@implementation RDQuoteShareController

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.view.backgroundColor = RDSurfaceColor;

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
    self.hintLabel.text = @"长按下方文字选句,上方卡片实时更新;不选则用本页首句";
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

    //初始预览:自动摘句卡片
    [self p_refreshPreview];
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
        return;
    }
    RDShareCardGenre genre = [RDShareCardBuilder genreForBook:self.book];
    self.previewView.image = [RDShareCardBuilder cardImageWithQuote:quote book:self.book genre:genre];
}

- (void)textViewDidChangeSelection:(UITextView *)textView
{
    //选中变化即重绘预览(1080×1440 绘制在真机 <10ms,可直绘)
    [self p_refreshPreview];
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
    //上半卡片预览(3:4),下半文字选择
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

- (void)p_share
{
    [self p_refreshPreview];
    UIImage *card = self.previewView.image;
    if (!card) {
        [RDToastView showText:@"本页没有可分享的文字" delay:1.2 inView:self.view];
        return;
    }
    //落成 png 文件后以 fileURL 分享:预览带缩略图,微信等目标按图片接收
    NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:@"quote_card.png"];
    NSData *png = UIImagePNGRepresentation(card);
    if (!png || ![png writeToFile:path atomically:YES]) {
        [RDToastView showText:@"卡片生成失败" delay:1.2 inView:self.view];
        return;
    }
    NSURL *fileURL = [NSURL fileURLWithPath:path];
    UIActivityViewController *avc = [[UIActivityViewController alloc] initWithActivityItems:@[fileURL] applicationActivities:nil];
    avc.popoverPresentationController.sourceView = self.shareButton;
    avc.popoverPresentationController.sourceRect = self.shareButton.bounds;
    [self presentViewController:avc animated:YES completion:nil];
}

@end
