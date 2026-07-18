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

    // 先挂启动页:视觉对齐 LaunchScreen,期间预加载书架 DB
    RDSplashViewController *splash = [[RDSplashViewController alloc] init];
    __weak typeof(self) weakSelf = self;
    __weak AppDelegate *weakApp = appDelegate;
    splash.onFinished = ^{
        [weakSelf p_presentMainWithAppDelegate:weakApp];
    };
    window.rootViewController = splash;
    self.window = window;
    appDelegate.window = window;
    [window makeKeyAndVisible];
    [RDDisplayBoost applyToWindow:window];

    // 冷启动「用其他应用打开」等主界面就绪后再导入
    if (connectionOptions.URLContexts.count > 0) {
        NSSet *contexts = [connectionOptions.URLContexts copy];
        __block id token = nil;
        token = [[NSNotificationCenter defaultCenter] addObserverForName:RDBookshelfPrefetchDidFinishNotification
                                                                  object:nil
                                                                   queue:[NSOperationQueue mainQueue]
                                                              usingBlock:^(NSNotification *note) {
            if (token) {
                [[NSNotificationCenter defaultCenter] removeObserver:token];
                token = nil;
            }
            [self scene:scene openURLContexts:contexts];
        }];
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
        });
    }];
    window.backgroundColor = RDBackgroudColor;
    [RDDisplayBoost applyToWindow:window];
}

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
