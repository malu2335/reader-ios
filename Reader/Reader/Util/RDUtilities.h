//
//  RDUtilities.h
//  Reader
//
//  Created by yuenov on 2019/12/24.
//  Copyright © 2019 yuenov. All rights reserved.
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface RDUtilities : NSObject

/// 主窗口（基于 UIWindowScene，避免使用已弃用的 UIApplication.keyWindow / windows）
+ (UIWindow * _Nullable)applicationKeyWindow;

/// 优先返回 windowLevel 为 normal 的窗口（弹层等场景）
+ (UIWindow * _Nullable)applicationWindowForNormalLevelPresentation;

+ (UIViewController *_Nullable)getCurrentVC;

/// 构建静态文件URL

/// 判断是否是iPAD
+ (BOOL)iPad;

@end

NS_ASSUME_NONNULL_END
