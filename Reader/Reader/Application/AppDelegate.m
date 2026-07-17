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
#import "RDDatabaseLifecycle.h"
#import "RDBookshelfPrefetch.h"

/// 最终网络防线：无论遗留模块、图片加载器还是未来误接入，都不能发出 HTTP(S) 请求。
@interface RDOfflineURLProtocol : NSURLProtocol
@end

@implementation RDOfflineURLProtocol

+ (BOOL)canInitWithRequest:(NSURLRequest *)request
{
    NSString *scheme = request.URL.scheme.lowercaseString;
    return [scheme isEqualToString:@"http"] || [scheme isEqualToString:@"https"];
}

+ (NSURLRequest *)canonicalRequestForRequest:(NSURLRequest *)request
{
    return request;
}

- (void)startLoading
{
    NSError *error = [NSError errorWithDomain:NSURLErrorDomain
                                         code:NSURLErrorNotConnectedToInternet
                                     userInfo:@{NSLocalizedDescriptionKey: @"纸羽轻阅不支持外部网络请求"}];
    [self.client URLProtocol:self didFailWithError:error];
}

- (void)stopLoading
{
}

@end

@interface AppDelegate ()
@property (nonatomic, strong, readwrite) RDMainController *mainController;
@end

@implementation AppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions
{
    [NSURLProtocol registerClass:RDOfflineURLProtocol.class];
    // 启动关键路径尽量轻量:WebP 延后;字体改由启动页预加载阶段注册,避免与书架抢盘
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        SDImageWebPCoder *webPCoder = [SDImageWebPCoder sharedCoder];
        dispatch_async(dispatch_get_main_queue(), ^{
            [[SDImageCodersManager sharedManager] addCoder:webPCoder];
        });
    });
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
    [RDLocalBookManager importBookAtURL:url complete:^(RDBookDetailModel *book, NSString *errorMessage, BOOL isDuplicate) {
        // 与 SceneDelegate 一致:导入后刷新书架预取缓存,避免已入库但不显示
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

- (void)applicationDidEnterBackground:(UIApplication *)application
{
    // 截断 WAL,避免下次冷启动 recover 上百 frames
    [RDDatabaseLifecycle checkpointWALSync];
}

- (void)applicationWillTerminate:(UIApplication *)application
{
    [RDDatabaseLifecycle checkpointWALSync];
}

@end
