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

@implementation SceneDelegate

- (void)scene:(UIScene *)scene willConnectToSession:(UISceneSession *)session options:(UISceneConnectionOptions *)connectionOptions
{
    if (![scene isKindOfClass:UIWindowScene.class]) {
        return;
    }
    UIWindowScene *windowScene = (UIWindowScene *)scene;

    AppDelegate *appDelegate = (AppDelegate *)UIApplication.sharedApplication.delegate;
    UIWindow *window = [[UIWindow alloc] initWithWindowScene:windowScene];
    window.backgroundColor = RDBackgroudColor;
    window.overrideUserInterfaceStyle = UIUserInterfaceStyleLight;

    RDNavigationController *nav = [[RDNavigationController alloc] initWithRootViewController:appDelegate.mainController];
    window.rootViewController = nav;
    self.window = window;
    // 兼容旧代码 RDAppDelegate.window / RDUtilities 回退路径
    appDelegate.window = window;
    [window makeKeyAndVisible];
    // ProMotion / 高刷:对齐 contentsScale,配置滚动容器
    [RDDisplayBoost applyToWindow:window];

    // 冷启动「用其他应用打开」延后到首帧后,避免挡住 makeKeyAndVisible
    if (connectionOptions.URLContexts.count > 0) {
        NSSet *contexts = connectionOptions.URLContexts;
        dispatch_async(dispatch_get_main_queue(), ^{
            [self scene:scene openURLContexts:contexts];
        });
    }
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
