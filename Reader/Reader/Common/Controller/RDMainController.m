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
    self.viewControllers = @[({
        RDBookshelfController *bookshelfController = [[RDBookshelfController alloc] init];
        bookshelfController;
    }),({
        RDSettingController *settingController = [[RDSettingController alloc] init];
        settingController;
    })];

    //设置 tab 使用系统齿轮图标,与书架切图统一按主题着色
    UIImageSymbolConfiguration *symbolConfig = [UIImageSymbolConfiguration configurationWithPointSize:22 weight:UIImageSymbolWeightRegular];
    UIImage *gear = [UIImage systemImageNamed:@"gearshape" withConfiguration:symbolConfig];
    UIImage *gearFill = [UIImage systemImageNamed:@"gearshape.fill" withConfiguration:symbolConfig];

    NSArray *normalIcons = @[[UIImage imageNamed:@"tabbar_unselect"], gear];
    NSArray *selectedIcons = @[[UIImage imageNamed:@"tabbar_select"], gearFill];
    NSArray *titleArray = @[@"书架",@"设置"];
    for (int i = 0; i < self.tabBar.items.count; ++i) {
        RDVTabBarItem *item = self.tabBar.items[i];
        item.backgroundColor = RDSurfaceColor;
        item.title = [titleArray objectAtIndexSafely:i];
        item.titlePositionAdjustment = UIOffsetMake(0, 4);
        NSDictionary *tabBarTitleUnselectedDic = @{NSForegroundColorAttributeName: RDLightGrayColor, NSFontAttributeName: [UIFont systemFontOfSize:11]};
        NSDictionary *tabBarTitleSelectedDic = @{NSForegroundColorAttributeName: RDAccentColor, NSFontAttributeName: [UIFont systemFontOfSize:11]};
        item.selectedTitleAttributes = tabBarTitleSelectedDic;
        item.unselectedTitleAttributes = tabBarTitleUnselectedDic;
        //旧图标是绿色/冷灰切图,按纸质主题重新着色
        UIImage *selectedImage = [selectedIcons[i] imageWithTintColor:RDAccentColor];
        UIImage *normalImage = [normalIcons[i] imageWithTintColor:RDLightGrayColor];
        [item setFinishedSelectedImage:selectedImage withFinishedUnselectedImage:normalImage];
        [item removeTarget:self.tabBar action:@selector(tabBarItemWasSelected:) forControlEvents:UIControlEventTouchDown];
        [item addTarget:self.tabBar action:@selector(tabBarItemWasSelected:) forControlEvents:UIControlEventTouchUpInside];
        
        
    }
    //添加分割线
    UIView *separatorView = [[UIView alloc] initWithFrame:CGRectMake(0, -1 / [UIScreen mainScreen].scale, self.tabBar.width, 1 / [UIScreen mainScreen].scale)];
    separatorView.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    separatorView.backgroundColor = RDSeparatorColor;
    [self.tabBar addSubview:separatorView];
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
