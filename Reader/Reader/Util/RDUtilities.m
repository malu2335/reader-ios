//
//  RDUtilities.m
//  Reader
//
//  Created by yuenov on 2019/12/24.
//  Copyright © 2019 yuenov. All rights reserved.
//

#import "RDUtilities.h"
#import "AppDelegate.h"
#import "RDMainController.h"
#import "RDGlobalModel.h"


@implementation RDUtilities

+ (UIWindow *)applicationKeyWindow {
    UIApplication *app = [UIApplication sharedApplication];
    for (UIScene *scene in app.connectedScenes) {
        if (![scene isKindOfClass:[UIWindowScene class]]) {
            continue;
        }
        UIWindowScene *windowScene = (UIWindowScene *)scene;
        UIWindow *key = windowScene.keyWindow;
        if (key) {
            return key;
        }
    }
    for (UIScene *scene in app.connectedScenes) {
        if (![scene isKindOfClass:[UIWindowScene class]]) {
            continue;
        }
        for (UIWindow *window in ((UIWindowScene *)scene).windows) {
            if (window.isKeyWindow) {
                return window;
            }
        }
    }
    for (UIScene *scene in app.connectedScenes) {
        if (![scene isKindOfClass:[UIWindowScene class]]) {
            continue;
        }
        for (UIWindow *window in ((UIWindowScene *)scene).windows) {
            if (!window.hidden && window.alpha > 0) {
                return window;
            }
        }
    }
    AppDelegate *delegate = (AppDelegate *)app.delegate;
    if ([delegate isKindOfClass:[AppDelegate class]] && delegate.window) {
        return delegate.window;
    }
    return nil;
}

+ (UIWindow *)applicationWindowForNormalLevelPresentation {
    UIWindow *w = [self applicationKeyWindow];
    if (w && w.windowLevel == UIWindowLevelNormal) {
        return w;
    }
    UIApplication *app = [UIApplication sharedApplication];
    for (UIScene *scene in app.connectedScenes) {
        if (![scene isKindOfClass:[UIWindowScene class]]) {
            continue;
        }
        for (UIWindow *win in ((UIWindowScene *)scene).windows) {
            if (win.windowLevel == UIWindowLevelNormal && !win.hidden && win.alpha > 0) {
                return win;
            }
        }
    }
    return w;
}

+ (UIViewController *_Nullable)getCurrentVC
{
    UIViewController *result = nil;
    
    UIWindow *window = [self applicationWindowForNormalLevelPresentation];
    if (!window) {
        return nil;
    }

    UIView *frontView = [[window subviews] objectAtIndexSafely:0];
    id nextResponder = [frontView nextResponder];


    if ([nextResponder isKindOfClass:[UIViewController class]])
        result = nextResponder;
    else
        result = window.rootViewController;
    UIViewController *vc = [self currentVCWithVC:result];
    if ([vc isKindOfClass:[RDMainController class]]) {
        return [(RDMainController *) vc selectedViewController] ?: vc;
    }
    return vc;
}
+ (UIViewController *)currentVCWithVC:(UIViewController *)vc {
    if ([vc isKindOfClass:[UITabBarController class]]) {
        return [self currentVCWithVC:((UITabBarController *) vc).selectedViewController];
    }

    if ([vc isKindOfClass:[UINavigationController class]]) {
        return [self currentVCWithVC:((UINavigationController *) vc).visibleViewController];
    }

    return vc;
}

+ (NSString *)buildPicUrlWithPath:(NSString *)path
{
    return [NSString stringWithFormat:@"%@%@",[RDGlobalModel sharedInstance].picBaseUrl,path];
}

+ (BOOL)iPad
{
    // 启动/列表热路径避免 GBDeviceInfo 解析设备树
    return UIDevice.currentDevice.userInterfaceIdiom == UIUserInterfaceIdiomPad;
}
@end
