//
//  RDReadTranslateHelper.m
//  Reader
//

#import "RDReadTranslateHelper.h"
#import "RDAIConfig.h"
#import "RDAIClient.h"
#import "RDAIConfigController.h"
#import "LEEAlert.h"
#import "RDBaseViewController.h"

@implementation RDReadTranslateHelper

+ (void)cancel
{
    [[RDAIClient sharedClient] cancelInFlightTranslate];
}

+ (void)translateFromHost:(UIViewController *)host
                 pageText:(NSString *)pageText
              chapterText:(NSString *)chapterText
               rawContent:(NSString *)rawContent
{
    if ([RDAIClient sharedClient].isTranslating) {
        if ([host isKindOfClass:RDBaseViewController.class]) {
            [(RDBaseViewController *)host showText:@"正在翻译,请稍候"];
        }
        return;
    }

    RDAIConfigProfile *profile = [[RDAIConfigStore sharedInstance] activeProfile];
    if (!profile.isUsable) {
        [LEEAlert alert].config
        .LeeTitle(@"未配置 AI")
        .LeeContent(@"请先在设置中添加 AI 翻译配置(OpenAI / Anthropic / Gemini 及兼容格式)。")
        .LeeAddAction(^(LEEAction *action) {
            action.type = LEEActionTypeCancel;
            action.title = @"取消";
            action.titleColor = RDGrayColor;
        })
        .LeeAddAction(^(LEEAction *action) {
            action.title = @"去设置";
            action.titleColor = [UIColor systemBlueColor];
            action.clickBlock = ^{
                RDAIConfigController *ai = [[RDAIConfigController alloc] init];
                [host.navigationController pushViewController:ai animated:YES];
            };
        })
        .LeeShow();
        return;
    }

    NSString *text = pageText.length ? pageText : (chapterText.length ? chapterText : rawContent);
    BOOL truncated = NO;
    if (text.length > 4000) {
        text = [text substringToIndex:4000];
        truncated = YES;
    }
    if (text.length == 0) {
        if ([host isKindOfClass:RDBaseViewController.class]) {
            [(RDBaseViewController *)host showText:@"当前没有可翻译的文本"];
        }
        return;
    }
    if (truncated) {
        [RDToastView showText:@"文本较长,仅翻译前 4000 字" delay:1.2 inView:host.view];
    }

    RDBaseViewController *base = [host isKindOfClass:RDBaseViewController.class] ? (RDBaseViewController *)host : nil;
    [base showLoading:@"正在翻译..." cancel:^{
        [[RDAIClient sharedClient] cancelInFlightTranslate];
        [base hideLoading];
    }];

    [[RDAIClient sharedClient] translateText:text profile:profile completion:^(NSString *translated, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [base hideLoading];
            if (!translated) {
                if (error && [error.domain isEqualToString:NSURLErrorDomain] && error.code == NSURLErrorCancelled) {
                    return;
                }
                if (base) {
                    [base showText:error.localizedDescription ?: @"翻译失败"];
                }
                return;
            }
            [LEEAlert alert].config
            .LeeTitle(@"翻译结果")
            .LeeContent(translated)
            .LeeAddAction(^(LEEAction *action) {
                action.title = @"复制";
                action.clickBlock = ^{
                    [UIPasteboard generalPasteboard].string = translated;
                    [RDToastView showText:@"已复制" delay:1.0 inView:host.view];
                };
            })
            .LeeAddAction(^(LEEAction *action) {
                action.type = LEEActionTypeCancel;
                action.title = @"关闭";
            })
            .LeeShow();
        });
    }];
}

@end
