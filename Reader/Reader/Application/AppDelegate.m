//
//  AppDelegate.m
//  Reader
//
//  Created by yuenov on 2019/10/23.
//  Copyright © 2019 yuenov. All rights reserved.
//

#import "AppDelegate.h"
#import "RDMainController.h"
#import "SDWebImageWebPCoder.h"
#import "RDLocalBookManager.h"
#import "RDFontManager.h"
#import "RDBookDetailModel.h"

@interface AppDelegate ()
@property (nonatomic, strong, readwrite) RDMainController *mainController;
@end

@implementation AppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions
{
    // 仅进程级初始化;窗口由 SceneDelegate 创建
    SDImageWebPCoder *webPCoder = [SDImageWebPCoder sharedCoder];
    [[SDImageCodersManager sharedManager] addCoder:webPCoder];
    [[RDFontManager sharedInstance] registerCustomFontsAtLaunch];
    return YES;
}

#pragma mark - UISceneSession lifecycle

- (UISceneConfiguration *)application:(UIApplication *)application
configurationForConnectingSceneSession:(UISceneSession *)connectingSceneSession
                               options:(UISceneConnectionOptions *)options
{
    UISceneConfiguration *config = [[UISceneConfiguration alloc] initWithName:@"Default Configuration"
                                                                  sessionRole:connectingSceneSession.role];
    config.delegateClass = NSClassFromString(@"SceneDelegate");
    return config;
}

- (void)application:(UIApplication *)application didDiscardSceneSessions:(NSSet<UISceneSession *> *)sceneSessions
{
}

// 兼容旧路径 / 部分系统回调仍可能走到此处
- (BOOL)application:(UIApplication *)app openURL:(NSURL *)url options:(NSDictionary<UIApplicationOpenURLOptionsKey,id> *)options
{
    if (!url.isFileURL || ![RDLocalBookManager isSupportedFileURL:url]) {
        return NO;
    }
    [RDLocalBookManager importBookAtURL:url complete:^(RDBookDetailModel *book, NSString *errorMessage) {
        NSString *text = book ? [NSString stringWithFormat:@"《%@》已加入书架", book.title] : errorMessage;
        if (text.length > 0) {
            [RDToastView showText:text delay:1.5 inView:[RDUtilities applicationKeyWindow]];
        }
    }];
    return YES;
}

- (RDMainController *)mainController
{
    if (!_mainController) {
        _mainController = [[RDMainController alloc] init];
    }
    return _mainController;
}

- (void)reloadData
{
    // 纯本地阅读器:无需拉取配置或检查书籍更新
}

@end
