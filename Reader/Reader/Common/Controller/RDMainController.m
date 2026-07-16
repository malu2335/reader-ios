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
    // 首屏只创建书架,设置页延后到首次点 Tab 时再实例化(见 tabBarController:shouldSelectViewController:)
    RDBookshelfController *bookshelfController = [[RDBookshelfController alloc] init];
    UIViewController *settingsPlaceholder = [[UIViewController alloc] init];
    settingsPlaceholder.view.backgroundColor = RDBackgroudColor;
    self.viewControllers = @[bookshelfController, settingsPlaceholder];

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
        NSDictionary *tabBarTitleUnselectedDic = @{NSForegroundColorAttributeName: RDLightGrayColor, NSFontAttributeName: [UIFont systemFontOfSize:11]};
        NSDictionary *tabBarTitleSelectedDic = @{NSForegroundColorAttributeName: RDAccentColor, NSFontAttributeName: [UIFont systemFontOfSize:11]};
        item.selectedTitleAttributes = tabBarTitleSelectedDic;
        item.unselectedTitleAttributes = tabBarTitleUnselectedDic;
        UIImage *selectedImage = [selectedIcons[i] imageWithTintColor:RDAccentColor];
        UIImage *normalImage = [normalIcons[i] imageWithTintColor:RDLightGrayColor];
        [item setFinishedSelectedImage:selectedImage withFinishedUnselectedImage:normalImage];
        [item removeTarget:self.tabBar action:@selector(tabBarItemWasSelected:) forControlEvents:UIControlEventTouchDown];
        [item addTarget:self.tabBar action:@selector(tabBarItemWasSelected:) forControlEvents:UIControlEventTouchUpInside];
    }
    UIView *separatorView = [[UIView alloc] initWithFrame:CGRectMake(0, -1 / [UIScreen mainScreen].scale, self.tabBar.width, 1 / [UIScreen mainScreen].scale)];
    separatorView.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    separatorView.backgroundColor = RDSeparatorColor;
    [self.tabBar addSubview:separatorView];
}

- (BOOL)tabBarController:(RDVTabBarController *)tabBarController shouldSelectViewController:(UIViewController *)viewController
{
    // 首次点「设置」时替换占位 VC
    NSArray *vcs = self.viewControllers;
    if (vcs.count >= 2 && viewController == vcs[1] && ![viewController isKindOfClass:RDSettingController.class]) {
        RDSettingController *setting = [[RDSettingController alloc] init];
        NSMutableArray *next = [vcs mutableCopy];
        next[1] = setting;
        self.viewControllers = next;
        // 重新套用 tab 标题/图标(viewControllers 重置会刷 item)
        [self p_reapplyTabBarChrome];
        dispatch_async(dispatch_get_main_queue(), ^{
            [self setSelectedIndex:RDMainSetting];
        });
        return NO;
    }
    return YES;
}

- (void)p_reapplyTabBarChrome
{
    UIImageSymbolConfiguration *symbolConfig = [UIImageSymbolConfiguration configurationWithPointSize:22 weight:UIImageSymbolWeightRegular];
    UIImage *gear = [UIImage systemImageNamed:@"gearshape" withConfiguration:symbolConfig];
    UIImage *gearFill = [UIImage systemImageNamed:@"gearshape.fill" withConfiguration:symbolConfig];
    NSArray *normalIcons = @[[UIImage imageNamed:@"tabbar_unselect"], gear];
    NSArray *selectedIcons = @[[UIImage imageNamed:@"tabbar_select"], gearFill];
    NSArray *titleArray = @[@"书架", @"设置"];
    for (int i = 0; i < self.tabBar.items.count; ++i) {
        RDVTabBarItem *item = self.tabBar.items[i];
        item.title = [titleArray objectAtIndexSafely:i];
        item.selectedTitleAttributes = @{NSForegroundColorAttributeName: RDAccentColor, NSFontAttributeName: [UIFont systemFontOfSize:11]};
        item.unselectedTitleAttributes = @{NSForegroundColorAttributeName: RDLightGrayColor, NSFontAttributeName: [UIFont systemFontOfSize:11]};
        [item setFinishedSelectedImage:[selectedIcons[i] imageWithTintColor:RDAccentColor]
           withFinishedUnselectedImage:[normalIcons[i] imageWithTintColor:RDLightGrayColor]];
    }
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
