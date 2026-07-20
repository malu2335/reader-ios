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
#import "RDPaperAlert.h"

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

+ (void)p_presentConfigGuideFrom:(UIViewController *)host
{
    NSString *title = nil;
    NSString *content = nil;
    NSString *actionTitle = nil;
    NSString *symbol = nil;
    [self p_configGuideCopyWithTitle:&title content:&content actionTitle:&actionTitle symbolName:&symbol];
    __weak UIViewController *weakHost = host;
    [RDPaperAlert showAlertWithTitle:title
                             message:content
                          symbolName:symbol
                             actions:@[
        [RDPaperAlertAction actionWithTitle:@"稍后再说" style:RDPaperAlertActionStyleCancel handler:nil],
        [RDPaperAlertAction actionWithTitle:actionTitle ?: @"去设置" style:RDPaperAlertActionStylePrimary handler:^{
            [RDReadTranslateHelper p_openAISettingsFrom:weakHost];
        }],
    ]];
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
