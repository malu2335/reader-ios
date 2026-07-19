//
//  RDReadTranslateHelper.m
//  Reader
//

#import "RDReadTranslateHelper.h"
#import "RDAIConfig.h"
#import "RDAIClient.h"
#import "RDAIConfigController.h"
#import "RDBaseViewController.h"
#import "AppDelegate.h"
#import "RDMainController.h"
#import "RDReadConfigManager.h"
#import "RDFontManager.h"
#import <objc/runtime.h>

/// 纸感翻译配置引导遮罩(与设置/空书架同一套令牌,不走系统蓝 LEEAlert)
static const NSInteger kRDTranslateConfigGuideTag = 0x52444347; // 'RDCG'

@implementation RDTranslatePair
@end

@implementation RDReadTranslateHelper

+ (void)cancel
{
    [[RDAIClient sharedClient] cancelInFlightTranslate];
}

+ (BOOL)hasUsableAIConfig
{
    return [[RDAIConfigStore sharedInstance] activeProfile].isUsable;
}

+ (void)p_toast:(NSString *)text on:(UIViewController *)host
{
    UIView *v = host.view ?: [RDUtilities applicationKeyWindow];
    if (v) {
        [RDToastView showText:text delay:1.8 inView:v];
    }
}

+ (void)p_openAISettingsFrom:(UIViewController *)host
{
    RDAIConfigController *ai = [[RDAIConfigController alloc] init];
    UINavigationController *nav = host.navigationController;
    if (nav) {
        [nav pushViewController:ai animated:YES];
        return;
    }
    // 阅读页通常无 nav:先切到设置 Tab,再全屏推 AI 配置
    AppDelegate *app = (AppDelegate *)UIApplication.sharedApplication.delegate;
    if ([app.mainController isKindOfClass:RDMainController.class]) {
        [app.mainController setSelectedIndex:RDMainSetting];
    }
    UINavigationController *wrap = [[UINavigationController alloc] initWithRootViewController:ai];
    wrap.modalPresentationStyle = UIModalPresentationFullScreen;
    UIViewController *presenter = host;
    if (!presenter) {
        presenter = [RDUtilities applicationKeyWindow].rootViewController;
        while (presenter.presentedViewController) {
            presenter = presenter.presentedViewController;
        }
    }
    [presenter presentViewController:wrap animated:YES completion:nil];
}

/// 场景文案 + 图标符号(SF Symbol)
+ (void)p_configGuideCopyWithTitle:(NSString * _Nonnull * _Nonnull)outTitle
                           content:(NSString * _Nonnull * _Nonnull)outContent
                       actionTitle:(NSString * _Nonnull * _Nonnull)outAction
                        symbolName:(NSString * _Nonnull * _Nonnull)outSymbol
{
    RDAIConfigStore *store = [RDAIConfigStore sharedInstance];
    NSArray <RDAIConfigProfile *>*profiles = store.profiles;
    RDAIConfigProfile *selected = nil;
    if (store.activeProfileId.length > 0) {
        selected = [store profileWithId:store.activeProfileId];
    }

    if (profiles.count == 0) {
        *outTitle = @"还没设置翻译";
        *outContent = @"阅读页的「译」需要先添加 AI 服务。支持 OpenAI、Anthropic、Gemini 及兼容接口（可填自定义地址，例如本地 Ollama）。";
        *outAction = @"去添加";
        *outSymbol = @"globe";
        return;
    }

    if (selected.pendingConfirm) {
        *outTitle = @"配置待确认";
        *outContent = @"当前配置来自备份恢复。为避免误用密钥，请到「AI 配置」里对该项点「设为当前」确认后，再开始翻译。";
        *outAction = @"去确认";
        *outSymbol = @"checkmark.shield";
        return;
    }

    if (selected && !selected.isUsable) {
        *outTitle = @"配置不完整";
        *outContent = @"当前选中的配置还缺少必要项：至少需要 API Key 与模型；兼容接口还需填写 Base URL。补全后即可翻译。";
        *outAction = @"去完善";
        *outSymbol = @"slider.horizontal.3";
        return;
    }

    BOOL anyPending = NO;
    for (RDAIConfigProfile *p in profiles) {
        if (p.pendingConfirm) {
            anyPending = YES;
            break;
        }
    }
    if (anyPending) {
        *outTitle = @"配置待确认";
        *outContent = @"备份恢复的 AI 配置尚未确认。请到「AI 配置」选择一项并点「设为当前」后，再开始翻译。";
        *outAction = @"去确认";
        *outSymbol = @"checkmark.shield";
        return;
    }

    *outTitle = @"请选择可用配置";
    *outContent = @"已有 AI 配置，但还没有可用的当前项。请到「AI 配置」选择一个并点「设为当前」。";
    *outAction = @"去设置";
    *outSymbol = @"list.bullet.rectangle";
}

+ (void)p_dismissConfigGuideAnimated:(BOOL)animated completion:(void (^)(void))completion
{
    UIWindow *window = [RDUtilities applicationKeyWindow];
    UIView *scrim = [window viewWithTag:kRDTranslateConfigGuideTag];
    if (!scrim) {
        if (completion) {
            completion();
        }
        return;
    }
    UIView *card = scrim.subviews.firstObject;
    void (^finish)(void) = ^{
        [scrim removeFromSuperview];
        if (completion) {
            completion();
        }
    };
    if (!animated) {
        finish();
        return;
    }
    [UIView animateWithDuration:0.2
                          delay:0
                        options:UIViewAnimationOptionCurveEaseIn
                     animations:^{
        scrim.alpha = 0;
        card.transform = CGAffineTransformMakeScale(0.94, 0.94);
        card.alpha = 0;
    } completion:^(BOOL finished) {
        finish();
    }];
}

+ (void)p_guideSecondaryTapped
{
    [self p_dismissConfigGuideAnimated:YES completion:nil];
}

+ (void)p_guidePrimaryTapped:(UIButton *)sender
{
    UIViewController *host = objc_getAssociatedObject(sender, @selector(p_guidePrimaryTapped:));
    [self p_dismissConfigGuideAnimated:YES completion:^{
        [RDReadTranslateHelper p_openAISettingsFrom:host];
    }];
}

+ (void)p_guideScrimTapped:(UITapGestureRecognizer *)gr
{
    // 只点遮罩空白处关闭,点卡片不关
    CGPoint p = [gr locationInView:gr.view];
    UIView *card = gr.view.subviews.firstObject;
    if (card && CGRectContainsPoint(card.frame, p)) {
        return;
    }
    [self p_dismissConfigGuideAnimated:YES completion:nil];
}

/// 纸感引导卡:表面色 + 衬线标题 + 赭褐主按钮,与空书架/分享页同系
+ (UIView *)p_buildGuideCardWidth:(CGFloat)width
                            title:(NSString *)title
                          content:(NSString *)content
                      actionTitle:(NSString *)actionTitle
                       symbolName:(NSString *)symbolName
                             host:(UIViewController *)host
{
    UIView *card = [[UIView alloc] init];
    card.backgroundColor = RDSurfaceColor;
    card.layer.cornerRadius = 18;
    card.layer.masksToBounds = NO;
    card.layer.shadowColor = [UIColor colorWithHexValue:0x2C2620].CGColor;
    card.layer.shadowOpacity = 0.14;
    card.layer.shadowRadius = 22;
    card.layer.shadowOffset = CGSizeMake(0, 10);

    // 轻微内描边,接近设置页卡片边缘
    UIView *border = [[UIView alloc] init];
    border.userInteractionEnabled = NO;
    border.layer.cornerRadius = 18;
    border.layer.borderWidth = 1.0 / UIScreen.mainScreen.scale;
    border.layer.borderColor = RDSeparatorColor.CGColor;
    border.translatesAutoresizingMaskIntoConstraints = NO;
    [card addSubview:border];

    UIView *iconWell = [[UIView alloc] init];
    iconWell.backgroundColor = RDAccentSoftColor;
    iconWell.layer.cornerRadius = 28;
    iconWell.translatesAutoresizingMaskIntoConstraints = NO;
    [card addSubview:iconWell];

    UIImageSymbolConfiguration *symCfg = [UIImageSymbolConfiguration configurationWithPointSize:24 weight:UIImageSymbolWeightMedium];
    UIImage *sym = [[UIImage systemImageNamed:symbolName ?: @"globe" withConfiguration:symCfg]
                    imageWithTintColor:RDAccentColor renderingMode:UIImageRenderingModeAlwaysOriginal];
    UIImageView *iconView = [[UIImageView alloc] initWithImage:sym];
    iconView.contentMode = UIViewContentModeScaleAspectFit;
    iconView.translatesAutoresizingMaskIntoConstraints = NO;
    [iconWell addSubview:iconView];

    UILabel *titleLabel = [[UILabel alloc] init];
    titleLabel.text = title;
    titleLabel.font = RDTitleFont19;
    titleLabel.textColor = RDBlackColor;
    titleLabel.textAlignment = NSTextAlignmentCenter;
    titleLabel.numberOfLines = 0;
    titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [card addSubview:titleLabel];

    UILabel *bodyLabel = [[UILabel alloc] init];
    NSMutableParagraphStyle *ps = [[NSMutableParagraphStyle alloc] init];
    ps.lineSpacing = 5;
    ps.alignment = NSTextAlignmentCenter;
    bodyLabel.attributedText = [[NSAttributedString alloc] initWithString:content ?: @""
                                                               attributes:@{
        NSFontAttributeName: RDFont14,
        NSForegroundColorAttributeName: RDGrayColor,
        NSParagraphStyleAttributeName: ps,
    }];
    bodyLabel.numberOfLines = 0;
    bodyLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [card addSubview:bodyLabel];

    UIButton *primary = [UIButton buttonWithType:UIButtonTypeSystem];
    [primary setTitle:actionTitle forState:UIControlStateNormal];
    [primary setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    primary.titleLabel.font = RDBoldFont16;
    primary.backgroundColor = RDAccentColor;
    primary.layer.cornerRadius = 23;
    primary.translatesAutoresizingMaskIntoConstraints = NO;
    [primary addTarget:self action:@selector(p_guidePrimaryTapped:) forControlEvents:UIControlEventTouchUpInside];
    objc_setAssociatedObject(primary, @selector(p_guidePrimaryTapped:), host, OBJC_ASSOCIATION_ASSIGN);
    [card addSubview:primary];

    UIButton *secondary = [UIButton buttonWithType:UIButtonTypeSystem];
    [secondary setTitle:@"稍后再说" forState:UIControlStateNormal];
    [secondary setTitleColor:RDLightGrayColor forState:UIControlStateNormal];
    secondary.titleLabel.font = RDFont15;
    secondary.translatesAutoresizingMaskIntoConstraints = NO;
    [secondary addTarget:self action:@selector(p_guideSecondaryTapped) forControlEvents:UIControlEventTouchUpInside];
    [card addSubview:secondary];

    CGFloat side = 24;
    [NSLayoutConstraint activateConstraints:@[
        [border.topAnchor constraintEqualToAnchor:card.topAnchor],
        [border.leadingAnchor constraintEqualToAnchor:card.leadingAnchor],
        [border.trailingAnchor constraintEqualToAnchor:card.trailingAnchor],
        [border.bottomAnchor constraintEqualToAnchor:card.bottomAnchor],

        [iconWell.topAnchor constraintEqualToAnchor:card.topAnchor constant:28],
        [iconWell.centerXAnchor constraintEqualToAnchor:card.centerXAnchor],
        [iconWell.widthAnchor constraintEqualToConstant:56],
        [iconWell.heightAnchor constraintEqualToConstant:56],

        [iconView.centerXAnchor constraintEqualToAnchor:iconWell.centerXAnchor],
        [iconView.centerYAnchor constraintEqualToAnchor:iconWell.centerYAnchor],
        [iconView.widthAnchor constraintEqualToConstant:28],
        [iconView.heightAnchor constraintEqualToConstant:28],

        [titleLabel.topAnchor constraintEqualToAnchor:iconWell.bottomAnchor constant:18],
        [titleLabel.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:side],
        [titleLabel.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-side],

        [bodyLabel.topAnchor constraintEqualToAnchor:titleLabel.bottomAnchor constant:10],
        [bodyLabel.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:side],
        [bodyLabel.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-side],

        [primary.topAnchor constraintEqualToAnchor:bodyLabel.bottomAnchor constant:24],
        [primary.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:side],
        [primary.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-side],
        [primary.heightAnchor constraintEqualToConstant:46],

        [secondary.topAnchor constraintEqualToAnchor:primary.bottomAnchor constant:6],
        [secondary.centerXAnchor constraintEqualToAnchor:card.centerXAnchor],
        [secondary.heightAnchor constraintEqualToConstant:40],
        [secondary.bottomAnchor constraintEqualToAnchor:card.bottomAnchor constant:-16],
        [secondary.leadingAnchor constraintGreaterThanOrEqualToAnchor:card.leadingAnchor constant:side],
        [secondary.trailingAnchor constraintLessThanOrEqualToAnchor:card.trailingAnchor constant:-side],

        [card.widthAnchor constraintEqualToConstant:width],
    ]];

    // 先布局再量高,供外层居中
    CGSize fitted = [card systemLayoutSizeFittingSize:CGSizeMake(width, UILayoutFittingCompressedSize.height)
                        withHorizontalFittingPriority:UILayoutPriorityRequired
                              verticalFittingPriority:UILayoutPriorityFittingSizeLevel];
    card.bounds = CGRectMake(0, 0, width, ceil(fitted.height));
    return card;
}

+ (void)p_presentConfigGuideFrom:(UIViewController *)host
{
    UIWindow *window = host.view.window ?: [RDUtilities applicationKeyWindow];
    if (!window) {
        return;
    }
    // 防重复叠两层
    [self p_dismissConfigGuideAnimated:NO completion:nil];

    NSString *title = nil;
    NSString *content = nil;
    NSString *actionTitle = nil;
    NSString *symbol = nil;
    [self p_configGuideCopyWithTitle:&title content:&content actionTitle:&actionTitle symbolName:&symbol];

    CGFloat cardW = MIN(312, window.bounds.size.width - 48);
    UIView *card = [self p_buildGuideCardWidth:cardW
                                         title:title
                                       content:content
                                   actionTitle:actionTitle
                                    symbolName:symbol
                                          host:host];

    UIView *scrim = [[UIView alloc] initWithFrame:window.bounds];
    scrim.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    scrim.backgroundColor = [[UIColor colorWithHexValue:0x2C2620] colorWithAlphaComponent:0.40];
    scrim.tag = kRDTranslateConfigGuideTag;
    scrim.alpha = 0;
    scrim.accessibilityViewIsModal = YES;

    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(p_guideScrimTapped:)];
    [scrim addGestureRecognizer:tap];

    card.center = CGPointMake(CGRectGetMidX(scrim.bounds), CGRectGetMidY(scrim.bounds));
    card.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin
        | UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleBottomMargin;
    card.transform = CGAffineTransformMakeScale(0.92, 0.92);
    card.alpha = 0;
    [scrim addSubview:card];
    [window addSubview:scrim];

    [UIView animateWithDuration:0.32
                          delay:0
         usingSpringWithDamping:0.86
          initialSpringVelocity:0.4
                        options:UIViewAnimationOptionCurveEaseOut
                     animations:^{
        scrim.alpha = 1;
        card.transform = CGAffineTransformIdentity;
        card.alpha = 1;
    } completion:nil];
}

+ (BOOL)ensureUsableAIConfigFromHost:(UIViewController *)host quiet:(BOOL)quiet
{
    if ([self hasUsableAIConfig]) {
        return YES;
    }
    if (!quiet) {
        [self p_presentConfigGuideFrom:host];
    }
    return NO;
}

+ (void)translateFromHost:(UIViewController *)host
                 pageText:(NSString *)pageText
              chapterText:(NSString *)chapterText
               rawContent:(NSString *)rawContent
{
    [self translateFromHost:host pageText:pageText chapterText:chapterText rawContent:rawContent quiet:NO completion:nil];
}

+ (void)translateFromHost:(UIViewController *)host
                 pageText:(NSString *)pageText
              chapterText:(NSString *)chapterText
               rawContent:(NSString *)rawContent
               completion:(void (^)(NSArray<RDTranslatePair *> *, NSString *, NSError *))completion
{
    [self translateFromHost:host pageText:pageText chapterText:chapterText rawContent:rawContent quiet:NO completion:completion];
}

+ (void)translateFromHost:(UIViewController *)host
                 pageText:(NSString *)pageText
              chapterText:(NSString *)chapterText
               rawContent:(NSString *)rawContent
                    quiet:(BOOL)quiet
               completion:(void (^)(NSArray<RDTranslatePair *> *, NSString *, NSError *))completion
{
    if (!host && !quiet) {
        return;
    }

    if (![self ensureUsableAIConfigFromHost:host quiet:quiet]) {
        if (completion) {
            completion(nil, nil, [NSError errorWithDomain:@"RDTranslate" code:10 userInfo:@{NSLocalizedDescriptionKey: @"未配置可用 AI"}]);
        }
        return;
    }
    RDAIConfigProfile *profile = [[RDAIConfigStore sharedInstance] activeProfile];

    NSString *text = pageText.length ? pageText : (chapterText.length ? chapterText : rawContent);
    text = [text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (text.length > 3500) {
        text = [text substringToIndex:3500];
        if (!quiet) {
            [self p_toast:@"本页较长,仅翻译前半部分" on:host];
        }
    }
    if (text.length == 0) {
        if (!quiet) {
            [self p_toast:@"当前没有可翻译的文本" on:host];
        }
        if (completion) {
            completion(nil, nil, [NSError errorWithDomain:@"RDTranslate" code:11 userInfo:@{NSLocalizedDescriptionKey: @"无文本"}]);
        }
        return;
    }

    // quiet=后台:不挡 UI、不 cancel 其他预取; 非 quiet=手动:可显示 loading
    RDBaseViewController *base = (!quiet && [host isKindOfClass:RDBaseViewController.class]) ? (RDBaseViewController *)host : nil;
    if (base) {
        [base showLoading:@"正在翻译..." cancel:^{
            [[RDAIClient sharedClient] cancelInFlightTranslate];
            [base hideLoading];
            [RDToastView showText:@"已取消" delay:1.0 inView:host.view];
        }];
    }

    NSString *prompt = [NSString stringWithFormat:
                        @"你是小说阅读翻译助手。将下面正文按句拆分翻译。"
                        @"若原文主要是中文则译成英文;若主要是英文/其他语言则译成简体中文。"
                        @"严格按以下格式输出,不要编号、不要解释、不要多余空行以外的标记:\n"
                        @"[S]\n原文句子\n[T]\n译文句子\n"
                        @"下一句继续 [S] ... [T] ...\n"
                        @"保持句序与原文一致。\n\n正文:\n%@", text];

    BOOL concurrent = quiet; // 后台并发,不取消其它页
    [[RDAIClient sharedClient] translateText:prompt profile:profile concurrent:concurrent completion:^(NSString *translated, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (base) {
                [base hideLoading];
            }
            if (!translated) {
                if (error && [error.domain isEqualToString:NSURLErrorDomain] && error.code == NSURLErrorCancelled) {
                    if (completion) {
                        completion(nil, nil, error);
                    }
                    return;
                }
                NSString *msg = error.localizedDescription.length ? error.localizedDescription : @"翻译失败";
                if (!quiet) {
                    [self p_toast:msg on:host];
                }
                if (completion) {
                    completion(nil, nil, error ?: [NSError errorWithDomain:@"RDTranslate" code:1 userInfo:@{NSLocalizedDescriptionKey: msg}]);
                }
                return;
            }
            NSArray <RDTranslatePair *>*pairs = [self parsePairsFromModelOutput:translated];
            if (completion) {
                completion(pairs, translated, nil);
            }
        });
    }];
}

#pragma mark - Parse

+ (NSArray <RDTranslatePair *>*)parsePairsFromModelOutput:(NSString *)output
{
    if (output.length == 0) {
        return nil;
    }
    NSMutableArray <RDTranslatePair *>*pairs = [NSMutableArray array];
    // 规范换行
    NSString *text = [[output stringByReplacingOccurrencesOfString:@"\r\n" withString:@"\n"]
                      stringByReplacingOccurrencesOfString:@"\r" withString:@"\n"];

    // 主格式: [S] ... [T] ...
    NSRegularExpression *re = [NSRegularExpression regularExpressionWithPattern:@"\\[S\\]\\s*\\n([\\s\\S]*?)\\n\\[T\\]\\s*\\n([\\s\\S]*?)(?=\\n\\[S\\]|$)"
                                                                        options:0
                                                                          error:nil];
    NSArray *matches = [re matchesInString:text options:0 range:NSMakeRange(0, text.length)];
    for (NSTextCheckingResult *m in matches) {
        if (m.numberOfRanges < 3) {
            continue;
        }
        NSString *s = [[text substringWithRange:[m rangeAtIndex:1]] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        NSString *t = [[text substringWithRange:[m rangeAtIndex:2]] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (s.length == 0 && t.length == 0) {
            continue;
        }
        RDTranslatePair *p = [[RDTranslatePair alloc] init];
        p.source = s;
        p.translated = t;
        [pairs addObject:p];
    }
    if (pairs.count > 0) {
        return pairs;
    }

    // 兜底:按中英文句号拆原文块 — 若模型用「原文\n译文\n\n」交替
    NSArray *blocks = [text componentsSeparatedByString:@"\n\n"];
    for (NSString *block in blocks) {
        NSString *b = [block stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (b.length == 0) {
            continue;
        }
        NSRange r = [b rangeOfString:@"\n"];
        if (r.location == NSNotFound) {
            continue;
        }
        NSString *s = [[b substringToIndex:r.location] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        NSString *t = [[b substringFromIndex:r.location + 1] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (s.length && t.length) {
            RDTranslatePair *p = [[RDTranslatePair alloc] init];
            p.source = s;
            p.translated = t;
            [pairs addObject:p];
        }
    }
    return pairs.count > 0 ? pairs : nil;
}

#pragma mark - Attributed display

+ (NSAttributedString *)attributedStringForPairs:(NSArray <RDTranslatePair *>*)pairs
                                   fallbackSource:(NSString *)source
                               fallbackTranslation:(NSString *)translation
{
    RDReadConfigManager *cfg = [RDReadConfigManager sharedInstance];
    UIFont *srcFont = [RDFontManager readFontWithName:cfg.fontName size:cfg.fontSize];
    UIFont *trFont = [RDFontManager readFontWithName:cfg.fontName size:MAX(12, cfg.fontSize - 2)];
    UIColor *srcColor = cfg.fontColor ?: RDBlackColor;
    UIColor *trColor = [cfg.fontColor colorWithAlphaComponent:0.55] ?: RDGrayColor;
    if (!trColor) {
        trColor = RDGrayColor;
    }

    NSMutableParagraphStyle *srcPS = [[NSMutableParagraphStyle alloc] init];
    srcPS.lineSpacing = MAX(4, cfg.lineSpace * 0.6);
    srcPS.paragraphSpacing = 2;
    srcPS.firstLineHeadIndent = 0;
    srcPS.headIndent = 0;

    NSMutableParagraphStyle *trPS = [[NSMutableParagraphStyle alloc] init];
    trPS.lineSpacing = 3;
    trPS.paragraphSpacing = 10;
    trPS.firstLineHeadIndent = 12;
    trPS.headIndent = 12;

    NSDictionary *srcAttr = @{
        NSFontAttributeName: srcFont,
        NSForegroundColorAttributeName: srcColor,
        NSParagraphStyleAttributeName: srcPS,
    };
    NSDictionary *trAttr = @{
        NSFontAttributeName: trFont,
        NSForegroundColorAttributeName: trColor,
        NSParagraphStyleAttributeName: trPS,
    };

    NSMutableAttributedString *out = [[NSMutableAttributedString alloc] init];

    if (pairs.count > 0) {
        for (NSInteger i = 0; i < (NSInteger)pairs.count; i++) {
            RDTranslatePair *p = pairs[i];
            if (p.source.length) {
                [out appendAttributedString:[[NSAttributedString alloc] initWithString:[p.source stringByAppendingString:@"\n"] attributes:srcAttr]];
            }
            if (p.translated.length) {
                NSString *line = (i == (NSInteger)pairs.count - 1) ? p.translated : [p.translated stringByAppendingString:@"\n\n"];
                [out appendAttributedString:[[NSAttributedString alloc] initWithString:line attributes:trAttr]];
            }
        }
        return out;
    }

    // 整段兜底:原文 + 下方全文译文
    if (source.length) {
        [out appendAttributedString:[[NSAttributedString alloc] initWithString:[source stringByAppendingString:@"\n\n"] attributes:srcAttr]];
    }
    if (translation.length) {
        [out appendAttributedString:[[NSAttributedString alloc] initWithString:translation attributes:trAttr]];
    }
    return out;
}

@end
