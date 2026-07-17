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
#import "AppDelegate.h"
#import "RDMainController.h"

@implementation RDReadTranslateHelper

+ (void)cancel
{
    [[RDAIClient sharedClient] cancelInFlightTranslate];
}

+ (void)p_toast:(NSString *)text on:(UIViewController *)host
{
    UIView *v = host.view ?: [RDUtilities applicationKeyWindow];
    if (v) {
        [RDToastView showText:text delay:2.0 inView:v];
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
    // 阅读页若无导航栈,切到设置 Tab 并推入
    AppDelegate *app = (AppDelegate *)UIApplication.sharedApplication.delegate;
    if ([app.mainController isKindOfClass:RDMainController.class]) {
        [app.mainController setSelectedIndex:RDMainSetting];
        UIViewController *setting = app.mainController.viewControllers.count > 1 ? app.mainController.viewControllers[1] : nil;
        if (setting.navigationController) {
            [setting.navigationController pushViewController:ai animated:YES];
        } else {
            UINavigationController *wrap = [[UINavigationController alloc] initWithRootViewController:ai];
            wrap.modalPresentationStyle = UIModalPresentationFullScreen;
            [host presentViewController:wrap animated:YES completion:nil];
        }
    } else {
        [host presentViewController:ai animated:YES completion:nil];
    }
}

+ (void)translateFromHost:(UIViewController *)host
                 pageText:(NSString *)pageText
              chapterText:(NSString *)chapterText
               rawContent:(NSString *)rawContent
{
    if (!host) {
        return;
    }
    if ([RDAIClient sharedClient].isTranslating) {
        [self p_toast:@"正在翻译,请稍候" on:host];
        return;
    }

    RDAIConfigProfile *profile = [[RDAIConfigStore sharedInstance] activeProfile];
    if (!profile.isUsable) {
        [LEEAlert alert].config
        .LeeTitle(@"未配置 AI")
        .LeeContent(@"请先在设置中添加 AI 翻译配置(OpenAI / Anthropic / Gemini 及兼容格式),并填写 API Key、模型与 Base URL。")
        .LeeAddAction(^(LEEAction *action) {
            action.type = LEEActionTypeCancel;
            action.title = @"取消";
            action.titleColor = RDGrayColor;
        })
        .LeeAddAction(^(LEEAction *action) {
            action.title = @"去设置";
            action.titleColor = [UIColor systemBlueColor];
            action.clickBlock = ^{
                [RDReadTranslateHelper p_openAISettingsFrom:host];
            };
        })
        .LeeShow();
        return;
    }

    NSString *text = pageText.length ? pageText : (chapterText.length ? chapterText : rawContent);
    text = [text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    BOOL truncated = NO;
    if (text.length > 4000) {
        text = [text substringToIndex:4000];
        truncated = YES;
    }
    if (text.length == 0) {
        [self p_toast:@"当前没有可翻译的文本" on:host];
        return;
    }
    if (truncated) {
        [self p_toast:@"文本较长,仅翻译前 4000 字" on:host];
    }

    RDBaseViewController *base = [host isKindOfClass:RDBaseViewController.class] ? (RDBaseViewController *)host : nil;
    if (base) {
        [base showLoading:@"正在翻译..." cancel:^{
            [[RDAIClient sharedClient] cancelInFlightTranslate];
            [base hideLoading];
            [RDToastView showText:@"已取消" delay:1.0 inView:host.view];
        }];
    } else {
        [self p_toast:@"正在翻译..." on:host];
    }

    NSString *endpointHint = profile.baseURL.length ? profile.baseURL : profile.type;
    [[RDAIClient sharedClient] translateText:text profile:profile completion:^(NSString *translated, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (base) {
                [base hideLoading];
            }
            if (!translated) {
                if (error && [error.domain isEqualToString:NSURLErrorDomain] && error.code == NSURLErrorCancelled) {
                    return;
                }
                NSString *msg = error.localizedDescription.length ? error.localizedDescription : @"翻译失败";
                // 结果用 Alert,失败也用 Alert,避免「无响应」
                [LEEAlert alert].config
                .LeeTitle(@"翻译失败")
                .LeeContent([NSString stringWithFormat:@"%@\n\n接口: %@ · %@", msg, profile.type ?: @"", endpointHint ?: @""])
                .LeeAddAction(^(LEEAction *action) {
                    action.title = @"去检查配置";
                    action.clickBlock = ^{
                        [RDReadTranslateHelper p_openAISettingsFrom:host];
                    };
                })
                .LeeAddAction(^(LEEAction *action) {
                    action.type = LEEActionTypeCancel;
                    action.title = @"关闭";
                })
                .LeeShow();
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
