//
//  RDMainController.h
//  Reader
//
//  Created by yuenov on 2019/10/23.
//  Copyright © 2019 yuenov. All rights reserved.
//

#import "RDVTabBarController.h"

typedef NS_ENUM(NSInteger,RDMainBarItemType){
    RDMainBookShelf = 0,
    RDMainSetting
};

@interface RDMainController : RDVTabBarController <RDVTabBarControllerDelegate>

/// 启动后预加载设置页 view,避免首次点 Tab 卡顿
- (void)preloadSettingIfNeeded;

@end
