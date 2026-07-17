//
//  RDMainController.m
//  Reader
//
//  Created by yuenov on 2019/10/23.
//  Copyright © 2019 yuenov. All rights reserved.
//

#import "RDMainController.h"
#import "RDUtilities.h"
#import "UIView+rd_dispalyInfo.h"
#import "RDBookshelfController.h"
#import "RDSettingController.h"
#import "RDVTabBarItem.h"
#import "UIColor+rd_wid.h"
#import "NSArray+rd_wid.h"
#import "UIView+rd_wid.h"
#import "UINavigationController+FDFullscreenPopGesture.h"



@interface RDMainController ()

@end

@implementation RDMainController

- (void)viewDidLoad {
    [super viewDidLoad];
    if ([self respondsToSelector:@selector(setAutomaticallyAdjustsScrollViewInsets:)]) {
        self.automaticallyAdjustsScrollViewInsets = NO;
    }
    self.navigationController.navigationBarHidden = YES;
    if (@available(iOS 11.0, *)) {
        CGFloat safeAreaBottom = [RDUtilities applicationKeyWindow].safeAreaInsets.bottom;
         self.tabBar.contentEdgeInsets = UIEdgeInsetsMake(0, 0,  safeAreaBottom / 1.5f, 0);
    }
    self.delegate = self;
    self.fd_prefersNavigationBarHidden = YES;
   [self initSetup];

}

-(void)initSetup{
    // 设置页与书架一并创建,避免首次点 Tab 时替换 VC + 重建 tab 栏导致卡顿
    RDBookshelfController *bookshelfController = [[RDBookshelfController alloc] init];
    RDSettingController *settingController = [[RDSettingController alloc] init];
    self.viewControllers = @[bookshelfController, settingController];
    [self p_applyTabBarChrome];

    UIView *separatorView = [[UIView alloc] initWithFrame:CGRectMake(0, -1 / [UIScreen mainScreen].scale, self.tabBar.width, 1 / [UIScreen mainScreen].scale)];
    separatorView.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    separatorView.backgroundColor = RDSeparatorColor;
    [self.tabBar addSubview:separatorView];
}

- (void)p_applyTabBarChrome
{
    UIImageSymbolConfiguration *symbolConfig = [UIImageSymbolConfiguration configurationWithPointSize:22 weight:UIImageSymbolWeightRegular];
    UIImage *gear = [UIImage systemImageNamed:@"gearshape" withConfiguration:symbolConfig];
    UIImage *gearFill = [UIImage systemImageNamed:@"gearshape.fill" withConfiguration:symbolConfig];
    NSArray *normalIcons = @[[UIImage imageNamed:@"tabbar_unselect"], gear];
    NSArray *selectedIcons = @[[UIImage imageNamed:@"tabbar_select"], gearFill];
    NSArray *titleArray = @[@"书架", @"设置"];
    for (int i = 0; i < self.tabBar.items.count; ++i) {
        RDVTabBarItem *item = self.tabBar.items[i];
        item.backgroundColor = RDSurfaceColor;
        item.title = [titleArray objectAtIndexSafely:i];
        item.titlePositionAdjustment = UIOffsetMake(0, 4);
        item.selectedTitleAttributes = @{NSForegroundColorAttributeName: RDAccentColor, NSFontAttributeName: [UIFont systemFontOfSize:11]};
        item.unselectedTitleAttributes = @{NSForegroundColorAttributeName: RDLightGrayColor, NSFontAttributeName: [UIFont systemFontOfSize:11]};
        UIImage *selectedImage = [selectedIcons[i] imageWithTintColor:RDAccentColor];
        UIImage *normalImage = [normalIcons[i] imageWithTintColor:RDLightGrayColor];
        [item setFinishedSelectedImage:selectedImage withFinishedUnselectedImage:normalImage];
        [item removeTarget:self.tabBar action:@selector(tabBarItemWasSelected:) forControlEvents:UIControlEventTouchDown];
        [item addTarget:self.tabBar action:@selector(tabBarItemWasSelected:) forControlEvents:UIControlEventTouchUpInside];
    }
}

/// 启动后预加载设置页 view,首次点 Tab 只做切换不创建
- (void)preloadSettingIfNeeded
{
    if (self.viewControllers.count < 2) {
        return;
    }
    UIViewController *setting = self.viewControllers[1];
    if (![setting isKindOfClass:RDSettingController.class]) {
        return;
    }
    if (setting.isViewLoaded) {
        return;
    }
    // 触发 viewDidLoad / 表布局,但不切 Tab
    (void)setting.view;
}


/*
#pragma mark - Navigation

// In a storyboard-based application, you will often want to do a little preparation before navigation
- (void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender {
    // Get the new view controller using [segue destinationViewController].
    // Pass the selected object to the new view controller.
}
*/

@end
