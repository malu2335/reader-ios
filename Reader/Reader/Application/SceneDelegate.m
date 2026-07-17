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
#ifdef DEBUG
#import "RDLegalDocumentController.h"
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
    window.overrideUserInterfaceStyle = UIUserInterfaceStyleLight;

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
            // SIMCTL_CHILD_RD_SHOT=settings|privacy|opensource 用于 README 截图
            [self p_applyDebugScreenshotHookIfNeededWithMain:main navigation:nav];
#endif
        });
    }];
    window.backgroundColor = RDBackgroudColor;
    [RDDisplayBoost applyToWindow:window];
}

#ifdef DEBUG
/// 仅 Debug：由环境变量 RD_SHOT 跳到设置 / 隐私声明 / 开源声明，便于 simctl 截图。
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
    for (UIOpenURLContext *ctx in URLContexts) {
        NSURL *url = ctx.URL;
        if (!url.isFileURL || ![RDLocalBookManager isSupportedFileURL:url]) {
            continue;
        }
        [RDLocalBookManager importBookAtURL:url complete:^(RDBookDetailModel *book, NSString *errorMessage, BOOL isDuplicate) {
            [RDBookshelfPrefetch refreshAsync:nil];
            NSString *text = nil;
            if (isDuplicate) {
                text = errorMessage.length ? errorMessage : [NSString stringWithFormat:@"《%@》已在书架", book.title ?: @""];
            } else if (book) {
                text = [NSString stringWithFormat:@"《%@》已加入书架", book.title];
            } else {
                text = errorMessage;
            }
            if (text.length > 0) {
                [RDToastView showText:text delay:1.5 inView:[RDUtilities applicationKeyWindow]];
            }
        }];
    }
}

@end
