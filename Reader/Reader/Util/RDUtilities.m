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
#import "RDToastView.h"


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
    return @"";
}

+ (BOOL)iPad
{
    // 启动/列表热路径避免 GBDeviceInfo 解析设备树
    return UIDevice.currentDevice.userInterfaceIdiom == UIUserInterfaceIdiomPad;
}

+ (void)presentDictionaryLookupFrom:(UIViewController *)host initialTerm:(NSString *)initialTerm
{
    if (!host) {
        return;
    }
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"查词典"
                                                                   message:@"输入词语,调用系统词典(需已下载词典包)"
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *tf) {
        tf.placeholder = @"词语 / 单词";
        tf.clearButtonMode = UITextFieldViewModeWhileEditing;
        if (initialTerm.length > 0 && initialTerm.length <= 8) {
            tf.text = initialTerm;
        }
    }];
    __weak UIViewController *weakHost = host;
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"查询" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        NSString *word = [alert.textFields.firstObject.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (word.length == 0 || !weakHost) {
            return;
        }
        if (![UIReferenceLibraryViewController dictionaryHasDefinitionForTerm:word]) {
            [RDToastView showText:@"词典中未找到,可到系统「设置-通用-词典」下载" delay:2 inView:weakHost.view];
            return;
        }
        UIReferenceLibraryViewController *dict = [[UIReferenceLibraryViewController alloc] initWithTerm:word];
        [weakHost presentViewController:dict animated:YES completion:nil];
    }]];
    [host presentViewController:alert animated:YES completion:nil];
}
@end
