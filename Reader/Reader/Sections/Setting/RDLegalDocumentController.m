//
//  RDLegalDocumentController.m
//  Reader
//
//  本地只读声明页：纸色背景 + 宋体标题 + 墨色正文，对齐项目安静纸质阅读感。
//

#import "RDLegalDocumentController.h"

@interface RDLegalDocumentController ()
@property (nonatomic, copy) NSString *documentTitle;
@property (nonatomic, copy) NSString *resourceName;
@property (nonatomic, strong) UITextView *textView;
@end

@implementation RDLegalDocumentController

- (instancetype)initWithTitle:(NSString *)title resourceName:(NSString *)resourceName
{
    self = [super init];
    if (self) {
        _documentTitle = [title copy] ?: @"";
        _resourceName = [resourceName copy] ?: @"";
    }
    return self;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.view.backgroundColor = RDBackgroudColor;
    self.topView.titleLabel.text = self.documentTitle.length ? self.documentTitle : @"声明";
    self.topView.titleLabel.font = RDTitleFont19;
    [self.view addSubview:self.topView];
    [self.view addSubview:self.textView];
    [self p_loadDocument];
}

- (void)viewDidLayoutSubviews
{
    [super viewDidLayoutSubviews];
    CGFloat top = self.topView.bottom;
    self.textView.frame = CGRectMake(0, top, self.view.width, self.view.height - top);
}

- (UITextView *)textView
{
    if (!_textView) {
        _textView = [[UITextView alloc] initWithFrame:CGRectZero];
        _textView.editable = NO;
        _textView.selectable = YES;
        _textView.backgroundColor = RDBackgroudColor;
        _textView.textColor = RDBlackColor;
        _textView.font = RDFont15;
        _textView.adjustsFontForContentSizeCategory = YES;
        // 阅读边距：左右略宽，接近书页留白
        _textView.textContainerInset = UIEdgeInsetsMake(20, 20, 36, 20);
        _textView.textContainer.lineFragmentPadding = 0;
        _textView.alwaysBounceVertical = YES;
        _textView.showsVerticalScrollIndicator = YES;
        _textView.indicatorStyle = UIScrollViewIndicatorStyleBlack;
        _textView.dataDetectorTypes = UIDataDetectorTypeNone;
        _textView.linkTextAttributes = @{
            NSForegroundColorAttributeName: RDAccentColor,
            NSUnderlineStyleAttributeName: @(NSUnderlineStyleSingle),
        };
    }
    return _textView;
}

#pragma mark - Load

- (void)p_loadDocument
{
    if (self.resourceName.length == 0) {
        [self p_showError:@"无法加载声明：未指定文档资源。"];
        return;
    }

    NSString *path = [[NSBundle mainBundle] pathForResource:self.resourceName ofType:@"txt"];
    if (path.length == 0) {
        path = [[NSBundle mainBundle] pathForResource:self.resourceName ofType:nil];
    }
    if (path.length == 0) {
        [self p_showError:[NSString stringWithFormat:@"无法加载声明：找不到资源「%@」。", self.resourceName]];
        return;
    }

    NSError *error = nil;
    NSString *text = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:&error];
    if (text.length == 0) {
        [self p_showError:[NSString stringWithFormat:@"无法读取声明内容：%@", error.localizedDescription ?: @"文件为空"]];
        return;
    }

    self.textView.attributedText = [self p_attributedDocumentFromText:text];
    self.textView.accessibilityLabel = self.documentTitle;
    self.textView.contentOffset = CGPointZero;
}

- (void)p_showError:(NSString *)message
{
    NSMutableParagraphStyle *style = [[NSMutableParagraphStyle alloc] init];
    style.lineSpacing = 6;
    self.textView.attributedText = [[NSAttributedString alloc] initWithString:message ?: @""
                                                                   attributes:@{
        NSFontAttributeName: RDFont15,
        NSForegroundColorAttributeName: RDGrayColor,
        NSParagraphStyleAttributeName: style,
    }];
}

#pragma mark - Typography

/// 轻量 markup：
///   #  文档大标题（宋体）
///   ## 章节标题
///   ### 小节标题
///   >  引导/说明段（次级墨色）
///   -  列表项
///   --- 分隔
///   其他为正文；英文许可正文自动用稍小字号
- (NSAttributedString *)p_attributedDocumentFromText:(NSString *)raw
{
    NSArray<NSString *> *lines = [raw componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]];
    NSMutableAttributedString *out = [[NSMutableAttributedString alloc] init];

    NSMutableParagraphStyle *bodyStyle = [[NSMutableParagraphStyle alloc] init];
    bodyStyle.lineSpacing = 7;
    bodyStyle.paragraphSpacing = 10;
    bodyStyle.alignment = NSTextAlignmentJustified;
    bodyStyle.lineBreakMode = NSLineBreakByWordWrapping;

    NSMutableParagraphStyle *titleStyle = [[NSMutableParagraphStyle alloc] init];
    titleStyle.lineSpacing = 4;
    titleStyle.paragraphSpacing = 14;
    titleStyle.alignment = NSTextAlignmentLeft;

    NSMutableParagraphStyle *sectionStyle = [[NSMutableParagraphStyle alloc] init];
    sectionStyle.lineSpacing = 4;
    sectionStyle.paragraphSpacingBefore = 18;
    sectionStyle.paragraphSpacing = 10;
    sectionStyle.alignment = NSTextAlignmentLeft;

    NSMutableParagraphStyle *leadStyle = [[NSMutableParagraphStyle alloc] init];
    leadStyle.lineSpacing = 6;
    leadStyle.paragraphSpacing = 14;
    leadStyle.headIndent = 0;
    leadStyle.firstLineHeadIndent = 0;

    NSMutableParagraphStyle *listStyle = [[NSMutableParagraphStyle alloc] init];
    listStyle.lineSpacing = 5;
    listStyle.paragraphSpacing = 6;
    listStyle.headIndent = 18;
    listStyle.firstLineHeadIndent = 0;

    NSMutableParagraphStyle *metaStyle = [[NSMutableParagraphStyle alloc] init];
    metaStyle.lineSpacing = 4;
    metaStyle.paragraphSpacing = 4;

    NSMutableParagraphStyle *sepStyle = [[NSMutableParagraphStyle alloc] init];
    sepStyle.paragraphSpacingBefore = 8;
    sepStyle.paragraphSpacing = 8;

    BOOL inMetaBlock = NO;
    BOOL sawTitle = NO;

    for (NSString *rawLine in lines) {
        NSString *line = rawLine;
        // 去掉行尾空白
        while (line.length > 0 && [[NSCharacterSet whitespaceCharacterSet] characterIsMember:[line characterAtIndex:line.length - 1]]) {
            line = [line substringToIndex:line.length - 1];
        }

        if (line.length == 0) {
            // 保留段间呼吸，但不堆叠过多空行
            if (out.length > 0 && ![[out.string substringFromIndex:MAX((NSInteger)out.length - 1, 0)] isEqualToString:@"\n"]) {
                [out appendAttributedString:[[NSAttributedString alloc] initWithString:@"\n"]];
            }
            inMetaBlock = NO;
            continue;
        }

        // 纯装饰分隔线
        if ([self p_isSeparatorLine:line]) {
            NSAttributedString *sep = [[NSAttributedString alloc] initWithString:@"\n"
                                                                     attributes:@{
                NSFontAttributeName: RDFont10,
                NSParagraphStyleAttributeName: sepStyle,
            }];
            [out appendAttributedString:sep];
            continue;
        }

        if ([line hasPrefix:@"# "]) {
            NSString *title = [line substringFromIndex:2];
            sawTitle = YES;
            inMetaBlock = YES; // 标题后紧跟的键值行视为元信息
            [out appendAttributedString:[[NSAttributedString alloc] initWithString:[title stringByAppendingString:@"\n"]
                                                                        attributes:@{
                NSFontAttributeName: RDTitleFont21,
                NSForegroundColorAttributeName: RDBlackColor,
                NSParagraphStyleAttributeName: titleStyle,
            }]];
            continue;
        }

        if ([line hasPrefix:@"## "]) {
            inMetaBlock = NO;
            NSString *section = [line substringFromIndex:3];
            [out appendAttributedString:[[NSAttributedString alloc] initWithString:[section stringByAppendingString:@"\n"]
                                                                        attributes:@{
                NSFontAttributeName: RDTitleFont17,
                NSForegroundColorAttributeName: RDBlackColor,
                NSParagraphStyleAttributeName: sectionStyle,
            }]];
            continue;
        }

        if ([line hasPrefix:@"### "]) {
            inMetaBlock = NO;
            NSString *sub = [line substringFromIndex:4];
            NSMutableParagraphStyle *subStyle = [sectionStyle mutableCopy];
            subStyle.paragraphSpacingBefore = 14;
            [out appendAttributedString:[[NSAttributedString alloc] initWithString:[sub stringByAppendingString:@"\n"]
                                                                        attributes:@{
                NSFontAttributeName: RDBoldFont15,
                NSForegroundColorAttributeName: RDBlackColor,
                NSParagraphStyleAttributeName: subStyle,
            }]];
            continue;
        }

        if ([line hasPrefix:@"> "]) {
            inMetaBlock = NO;
            NSString *lead = [line substringFromIndex:2];
            [out appendAttributedString:[[NSAttributedString alloc] initWithString:[lead stringByAppendingString:@"\n"]
                                                                        attributes:@{
                NSFontAttributeName: RDFont14,
                NSForegroundColorAttributeName: RDGrayColor,
                NSParagraphStyleAttributeName: leadStyle,
            }]];
            continue;
        }

        if ([line hasPrefix:@"- "] || [line hasPrefix:@"* "]) {
            inMetaBlock = NO;
            NSString *item = [line substringFromIndex:2];
            NSString *bullet = [NSString stringWithFormat:@"·  %@\n", item];
            [out appendAttributedString:[[NSAttributedString alloc] initWithString:bullet
                                                                        attributes:@{
                NSFontAttributeName: RDFont15,
                NSForegroundColorAttributeName: RDBlackColor,
                NSParagraphStyleAttributeName: listStyle,
            }]];
            continue;
        }

        // 标题后的「键：值」元信息行
        if ((inMetaBlock || !sawTitle) && [self p_isMetaLine:line]) {
            [out appendAttributedString:[[NSAttributedString alloc] initWithString:[line stringByAppendingString:@"\n"]
                                                                        attributes:@{
                NSFontAttributeName: RDFont13,
                NSForegroundColorAttributeName: RDLightGrayColor,
                NSParagraphStyleAttributeName: metaStyle,
            }]];
            continue;
        }

        inMetaBlock = NO;

        // 许可正文等偏英文/代码块感的长行：略缩小字号，保持可读可复制
        BOOL licenseLike = [self p_looksLikeLicenseBody:line];
        UIFont *font = licenseLike ? RDFont12 : RDFont15;
        UIColor *color = licenseLike ? RDGrayColor : RDBlackColor;
        NSParagraphStyle *style = licenseLike ? ({
            NSMutableParagraphStyle *s = [bodyStyle mutableCopy];
            s.alignment = NSTextAlignmentLeft;
            s.lineSpacing = 4;
            s.paragraphSpacing = 4;
            s;
        }) : bodyStyle;

        [out appendAttributedString:[[NSAttributedString alloc] initWithString:[line stringByAppendingString:@"\n"]
                                                                    attributes:@{
            NSFontAttributeName: font,
            NSForegroundColorAttributeName: color,
            NSParagraphStyleAttributeName: style,
        }]];
    }

    // 去掉末尾多余换行导致的大片空白
    while (out.length > 0) {
        unichar c = [out.string characterAtIndex:out.length - 1];
        if (c == '\n' || c == ' ' || c == '\t') {
            [out deleteCharactersInRange:NSMakeRange(out.length - 1, 1)];
        } else {
            break;
        }
    }

    return out;
}

- (BOOL)p_isSeparatorLine:(NSString *)line
{
    if (line.length < 3) {
        return NO;
    }
    static NSCharacterSet *sepChars;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        sepChars = [NSCharacterSet characterSetWithCharactersInString:@"-=_─—~"];
    });
    for (NSUInteger i = 0; i < line.length; i++) {
        if (![sepChars characterIsMember:[line characterAtIndex:i]]) {
            return NO;
        }
    }
    return YES;
}

- (BOOL)p_isMetaLine:(NSString *)line
{
    // 生效日期：… / App：… / 联系邮箱：… 等
    NSRange colon = [line rangeOfString:@"："];
    if (colon.location == NSNotFound || colon.location == 0 || colon.location > 12) {
        colon = [line rangeOfString:@":"];
    }
    if (colon.location == NSNotFound || colon.location == 0 || colon.location > 16) {
        return NO;
    }
    NSString *key = [line substringToIndex:colon.location];
    static NSArray *keys;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        keys = @[@"生效日期", @"适用版本", @"版本", @"App", @"App 名称", @"开发者", @"联系邮箱", @"邮箱", @"Bundle"];
    });
    for (NSString *k in keys) {
        if ([key isEqualToString:k] || [key hasPrefix:k]) {
            return YES;
        }
    }
    return NO;
}

- (BOOL)p_looksLikeLicenseBody:(NSString *)line
{
    // 典型许可证英文行 / SPDX 风格，避免把中文正文缩小
    if (line.length < 24) {
        return NO;
    }
    NSUInteger ascii = 0;
    for (NSUInteger i = 0; i < line.length; i++) {
        unichar c = [line characterAtIndex:i];
        if (c < 128) {
            ascii++;
        }
    }
    CGFloat ratio = (CGFloat)ascii / (CGFloat)line.length;
    if (ratio < 0.85) {
        return NO;
    }
    NSString *lower = line.lowercaseString;
    if ([lower containsString:@"permission"] ||
        [lower containsString:@"copyright"] ||
        [lower containsString:@"redistribution"] ||
        [lower containsString:@"warranty"] ||
        [lower containsString:@"liable"] ||
        [lower containsString:@"apache license"] ||
        [lower containsString:@"mit license"] ||
        [lower containsString:@"bsd"] ||
        [lower containsString:@"software"] ||
        [lower containsString:@"license"]) {
        return YES;
    }
    // 连续英文长行（缩进条款）
    return ratio > 0.92 && line.length > 48;
}

@end
