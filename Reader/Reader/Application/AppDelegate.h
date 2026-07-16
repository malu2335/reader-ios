//
//  AppDelegate.h
//  Reader
//
//  Created by yuenov on 2019/10/23.
//  Copyright © 2019 yuenov. All rights reserved.
//

#import <UIKit/UIKit.h>
@class RDMainController;

@interface AppDelegate : UIResponder <UIApplicationDelegate>
@property (nonatomic, strong, nullable) UIWindow *window;
@property (nonatomic, strong, readonly) RDMainController *mainController;

/// Scene 进入前台时调用(本地模式为空实现)
- (void)reloadData;

#define RDAppDelegate ((AppDelegate *)[[UIApplication sharedApplication] delegate])
@end


