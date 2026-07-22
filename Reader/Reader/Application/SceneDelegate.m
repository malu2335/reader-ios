//
//  SceneDelegate.m
//  Reader
//

#import "SceneDelegate.h"
#import "AppDelegate.h"
#import "RDMainController.h"
#import "RDNavigationController.h"
#import "RDLocalBookManager.h"
#import "RDBookDetailModel.h"
#import "RDDisplayBoost.h"
#import "RDDatabaseLifecycle.h"
#import "RDSplashViewController.h"
#import "RDBookshelfPrefetch.h"
#import "RDAppAppearance.h"
#ifdef DEBUG
#import "RDLegalDocumentController.h"
#import "RDVoicePickerController.h"
#endif

@interface SceneDelegate ()
/// 冷启动时系统传入的待导入文件;主界面呈现后消费一次,避免预加载通知竞态。
@property (nonatomic, copy) NSSet<UIOpenURLContext *> *pendingOpenURLContexts;
@end

@implementation SceneDelegate

- (void)scene:(UIScene *)scene willConnectToSession:(UISceneSession *)session options:(UISceneConnectionOptions *)connectionOptions
{
    if (![scene isKindOfClass:UIWindowScene.class]) {
        return;
    }
    UIWindowScene *windowScene = (UIWindowScene *)scene;

    AppDelegate *appDelegate = (AppDelegate *)UIApplication.sharedApplication.delegate;
    UIWindow *window = [[UIWindow alloc] initWithWindowScene:windowScene];
    window.backgroundColor = [UIColor whiteColor];
    // 启动页保持浅色;主界面呈现后再按设置/夜读切换全局深色

    // 冷启动「用其他应用打开」:先缓存,等启动页结束后再导入,保证只消费一次
    if (connectionOptions.URLContexts.count > 0) {
        self.pendingOpenURLContexts = [connectionOptions.URLContexts copy];
    }

    // 先挂启动页:视觉对齐 LaunchScreen,期间预加载书架 DB
    RDSplashViewController *splash = [[RDSplashViewController alloc] init];
    __weak typeof(self) weakSelf = self;
    __weak AppDelegate *weakApp = appDelegate;
    __weak UIScene *weakScene = scene;
    splash.onFinished = ^{
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) {
            return;
        }
        [self p_presentMainWithAppDelegate:weakApp];
        [self p_importPendingURLsForScene:weakScene];
    };
    window.rootViewController = splash;
    self.window = window;
    appDelegate.window = window;
    [window makeKeyAndVisible];
    [RDDisplayBoost applyToWindow:window];
}

- (void)p_importPendingURLsForScene:(UIScene *)scene
{
    NSSet<UIOpenURLContext *> *contexts = self.pendingOpenURLContexts;
    self.pendingOpenURLContexts = nil;
    if (contexts.count > 0) {
        [self scene:scene openURLContexts:contexts];
    }
}

- (void)p_presentMainWithAppDelegate:(AppDelegate *)appDelegate
{
    if (!appDelegate) {
        appDelegate = (AppDelegate *)UIApplication.sharedApplication.delegate;
    }
    RDMainController *main = appDelegate.mainController;
    RDNavigationController *nav = [[RDNavigationController alloc] initWithRootViewController:main];
    UIWindow *window = self.window;
    // 淡入主界面,避免硬切
    [UIView transitionWithView:window
                      duration:0.28
                       options:UIViewAnimationOptionTransitionCrossDissolve
                    animations:^{
        window.rootViewController = nav;
    } completion:^(BOOL finished) {
        // 主界面出来后空闲预热设置页,首次点 Tab 不再创建 view
        dispatch_async(dispatch_get_main_queue(), ^{
            [main preloadSettingIfNeeded];
#ifdef DEBUG
            // SIMCTL_CHILD_RD_SHOT=settings|privacy|opensource|voiceimport 用于截图/验收
            [self p_applyDebugScreenshotHookIfNeededWithMain:main navigation:nav];
#endif
        });
    }];
    // 按设置「黑暗模式」或阅读夜读,切换全局深色
    [[RDAppAppearance sharedInstance] applyToWindows];
    window.backgroundColor = RDBackgroudColor;
    [RDDisplayBoost applyToWindow:window];
}

#ifdef DEBUG
/// 仅 Debug：由环境变量 RD_SHOT 跳到设置 / 隐私声明 / 开源声明 / 朗读导入面板，便于 simctl 截图。
- (void)p_applyDebugScreenshotHookIfNeededWithMain:(RDMainController *)main
                                        navigation:(UINavigationController *)nav
{
    NSString *shot = [NSProcessInfo processInfo].environment[@"RD_SHOT"];
    if (shot.length == 0 || !main || !nav) {
        return;
    }
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.55 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [main setSelectedIndex:RDMainSetting];
        // 滚到「关于」分组，露出隐私 / 开源 / 版本
        UIViewController *settingVC = (main.viewControllers.count > 1) ? main.viewControllers[1] : nil;
        [settingVC.view layoutIfNeeded];
        for (UIView *sub in settingVC.view.subviews) {
            if (![sub isKindOfClass:UITableView.class]) {
                continue;
            }
            UITableView *table = (UITableView *)sub;
            NSInteger sections = [table numberOfSections];
            if (sections <= 0) {
                break;
            }
            NSInteger lastSection = sections - 1;
            NSInteger rows = [table numberOfRowsInSection:lastSection];
            if (rows <= 0) {
                break;
            }
            NSIndexPath *bottom = [NSIndexPath indexPathForRow:rows - 1 inSection:lastSection];
            [table scrollToRowAtIndexPath:bottom atScrollPosition:UITableViewScrollPositionBottom animated:NO];
            [table layoutIfNeeded];
            break;
        }

        if ([shot isEqualToString:@"settings"]) {
            return;
        }

        if ([shot isEqualToString:@"voiceimport"]) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.35 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                RDVoicePickerController *voice = [[RDVoicePickerController alloc] init];
                [nav pushViewController:voice animated:NO];
                // 等 push 落地后弹出「导入与管理」操作表
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.8 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                    [voice showImportMenu];
                });
            });
            return;
        }

        NSString *title = nil;
        NSString *resource = nil;
        if ([shot isEqualToString:@"privacy"]) {
            title = @"隐私声明";
            resource = @"PrivacyPolicy.zh-Hans";
        } else if ([shot isEqualToString:@"opensource"]) {
            title = @"开源软件使用声明";
            resource = @"OpenSourceLicenses";
        } else {
            return;
        }

        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.35 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            RDLegalDocumentController *vc = [[RDLegalDocumentController alloc] initWithTitle:title resourceName:resource];
            [nav pushViewController:vc animated:NO];
        });
    });
}
#endif

- (void)sceneWillEnterForeground:(UIScene *)scene
{
    AppDelegate *appDelegate = (AppDelegate *)UIApplication.sharedApplication.delegate;
    if ([appDelegate respondsToSelector:@selector(reloadData)]) {
        [appDelegate reloadData];
    }
}

- (void)sceneDidEnterBackground:(UIScene *)scene
{
    [RDDatabaseLifecycle checkpointWALAsync];
}

- (void)sceneDidDisconnect:(UIScene *)scene
{
    [RDDatabaseLifecycle checkpointWALAsync];
}

- (void)scene:(UIScene *)scene openURLContexts:(NSSet<UIOpenURLContext *> *)URLContexts
{
    // 其它 App「分享 / 拷贝到 / 用…打开」:批量导入到书架
    NSMutableArray <NSURL *>*urls = [NSMutableArray array];
    for (UIOpenURLContext *ctx in URLContexts) {
        NSURL *url = ctx.URL;
        if (!url.isFileURL) {
            continue;
        }
        if ([RDLocalBookManager isSupportedFileURL:url]) {
            [urls addObject:url];
        }
    }
    if (urls.count == 0) {
        if (URLContexts.count > 0) {
            [RDToastView showText:@"暂不支持该文件格式" delay:1.5 inView:[RDUtilities applicationKeyWindow]];
        }
        return;
    }
    // 切到书架,便于用户立刻看到新书
    AppDelegate *app = (AppDelegate *)UIApplication.sharedApplication.delegate;
    if ([app.mainController respondsToSelector:@selector(setSelectedIndex:)]) {
        [app.mainController setSelectedIndex:RDMainBookShelf];
    }
    __block NSInteger pending = urls.count;
    __block NSInteger succeed = 0;
    __block NSInteger duplicated = 0;
    __block NSString *lastTitle = nil;
    __block NSString *lastError = nil;
    __block NSString *lastDupMsg = nil;
    for (NSURL *url in urls) {
        [RDLocalBookManager importBookAtURL:url complete:^(RDBookDetailModel *book, NSString *errorMessage, BOOL isDuplicate) {
            if (isDuplicate) {
                duplicated++;
                lastTitle = book.title;
                lastDupMsg = errorMessage;
            } else if (book) {
                succeed++;
                lastTitle = book.title;
            } else if (errorMessage.length) {
                lastError = errorMessage;
            }
            pending--;
            if (pending > 0) {
                return;
            }
            [RDBookshelfPrefetch refreshAsync:nil];
            [[NSNotificationCenter defaultCenter] postNotificationName:RDLocalBookImportedNotification object:book];
            NSString *text = nil;
            if (urls.count == 1) {
                if (duplicated > 0) {
                    text = lastDupMsg.length ? lastDupMsg : [NSString stringWithFormat:@"《%@》已在书架", lastTitle ?: @""];
                } else if (succeed > 0) {
                    text = [NSString stringWithFormat:@"《%@》已加入书架", lastTitle ?: @""];
                } else {
                    text = lastError ?: @"导入失败";
                }
            } else {
                NSMutableString *msg = [NSMutableString string];
                if (succeed > 0) {
                    [msg appendFormat:@"新导入 %ld 本", (long)succeed];
                }
                if (duplicated > 0) {
                    if (msg.length) { [msg appendString:@"，"]; }
                    [msg appendFormat:@"重复 %ld 本", (long)duplicated];
                }
                if (lastError.length && succeed == 0 && duplicated == 0) {
                    [msg appendString:lastError];
                }
                text = msg.length ? msg : @"导入完成";
            }
            if (text.length > 0) {
                [RDToastView showText:text delay:1.8 inView:[RDUtilities applicationKeyWindow]];
            }
        }];
    }
}

@end
