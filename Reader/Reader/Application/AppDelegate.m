//
//  AppDelegate.m
//  Reader
//
//  Created by yuenov on 2019/10/23.
//  Copyright © 2019 yuenov. All rights reserved.
//

#import "AppDelegate.h"
#import "RDMainController.h"
#import "UIView+rd_dispalyInfo.h"
#import "RDNavigationController.h"

#import "SDWebImageWebPCoder.h"
#import "RDLocalBookManager.h"
#import "RDFontManager.h"
#import "RDBookDetailModel.h"


@interface AppDelegate ()

@property(nonatomic, strong) RDMainController *mainController;
@end

@implementation AppDelegate


- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {

    SDImageWebPCoder *webPCoder = [SDImageWebPCoder sharedCoder];
    [[SDImageCodersManager sharedManager] addCoder:webPCoder];

    //注册用户导入的阅读字体(进程级,需每次启动重注册)
    [[RDFontManager sharedInstance] registerCustomFontsAtLaunch];

    UIWindowScene *windowScene = nil;
    for (UIScene *scene in application.connectedScenes) {
        if ([scene isKindOfClass:[UIWindowScene class]]) {
            windowScene = (UIWindowScene *)scene;
            break;
        }
    }
    if (windowScene) {
        self.window = [[UIWindow alloc] initWithWindowScene:windowScene];
    } else {
        self.window = [[UIWindow alloc] initWithFrame:[[UIScreen mainScreen] bounds]];
    }
    self.window.backgroundColor = RDBackgroudColor;
    if (@available(iOS 13.0, *)) {
        //禁用dark model
        self.window.overrideUserInterfaceStyle = UIUserInterfaceStyleLight;
    }
    
    RDNavigationController *navigationController = [[RDNavigationController alloc] initWithRootViewController:self.mainController];
    self.window.rootViewController = navigationController;
    [self.window makeKeyAndVisible];
    
    
    return YES;
}
- (void)applicationWillEnterForeground:(UIApplication *)application {

    [self reloadData];

}

//「用其他应用打开」导入本地书籍
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


- (RDMainController *)mainController {
    if (!_mainController) {
        _mainController = [[RDMainController alloc] init];


    }
    return _mainController;
}

-(void)reloadData{
    //纯本地阅读器:无需拉取配置或检查书籍更新
}
@end
