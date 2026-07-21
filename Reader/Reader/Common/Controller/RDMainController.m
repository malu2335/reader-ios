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
#import "RDAppAppearance.h"


// RDVTabBar keeps tabBarItemWasSelected: private; declare for @selector use.
@interface RDVTabBar (RDPrivateSelector)
- (void)tabBarItemWasSelected:(id)sender;
@end

@interface RDMainController ()
@property (nonatomic, strong) UIView *tabSeparator;
@end

@implementation RDMainController

- (void)viewDidLoad {
    [super viewDidLoad];
    // Scroll-view safe-area: child tabs (bookshelf/settings) set contentInsetAdjustmentNever.
    self.navigationController.navigationBarHidden = YES;
    if (@available(iOS 11.0, *)) {
        CGFloat safeAreaBottom = [RDUtilities applicationKeyWindow].safeAreaInsets.bottom;
         self.tabBar.contentEdgeInsets = UIEdgeInsetsMake(0, 0,  safeAreaBottom / 1.5f, 0);
    }
    self.delegate = self;
    self.fd_prefersNavigationBarHidden = YES;
   [self initSetup];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(p_onAppAppearanceChanged)
                                                 name:RDAppAppearanceDidChangeNotification
                                               object:nil];
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
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
    self.tabSeparator = separatorView;
    [self.tabBar addSubview:separatorView];
}

- (void)p_onAppAppearanceChanged
{
    [self p_applyTabBarChrome];
    self.view.backgroundColor = RDBackgroudColor;
}

/// 用「有效深色」解析令牌,避免 window.overrideUserInterfaceStyle 已切深色
/// 但 self.traitCollection 尚未同步时 resolvedColor 仍吐出浅色(看起来像颜色反了)。
- (UITraitCollection *)p_appearanceTrait
{
    BOOL dark = [RDAppAppearance sharedInstance].isEffectiveDark;
    UIUserInterfaceStyle style = dark ? UIUserInterfaceStyleDark : UIUserInterfaceStyleLight;
    return [UITraitCollection traitCollectionWithUserInterfaceStyle:style];
}

- (void)p_applyTabBarChrome
{
    UITraitCollection *trait = [self p_appearanceTrait];
    // surface=面板(比页面底略抬起); 深色应为暖炭而非浅纸
    UIColor *surface = [RDSurfaceColor resolvedColorWithTraitCollection:trait];
    UIColor *accent = [RDAccentColor resolvedColorWithTraitCollection:trait];
    // 未选中用 secondary(深色下偏浅灰), tertiary 在深底上对比太弱
    UIColor *muted = [RDGrayColor resolvedColorWithTraitCollection:trait];
    UIColor *sep = [RDSeparatorColor resolvedColorWithTraitCollection:trait];

    UIImageSymbolConfiguration *symbolConfig = [UIImageSymbolConfiguration configurationWithPointSize:22 weight:UIImageSymbolWeightRegular];
    UIImage *gear = [UIImage systemImageNamed:@"gearshape" withConfiguration:symbolConfig];
    UIImage *gearFill = [UIImage systemImageNamed:@"gearshape.fill" withConfiguration:symbolConfig];
    NSArray *normalIcons = @[[UIImage imageNamed:@"tabbar_unselect"], gear];
    NSArray *selectedIcons = @[[UIImage imageNamed:@"tabbar_select"], gearFill];
    NSArray *titleArray = @[@"书架", @"设置"];

    // RDVTabBar 真正铺满底栏的是 backgroundView(默认写死 RGB 245 浅灰),
    // 只设 tabBar.backgroundColor / item.backgroundColor 挡不住它。
    self.tabBar.backgroundColor = surface;
    self.tabBar.backgroundView.backgroundColor = surface;
    self.tabSeparator.backgroundColor = sep;

    for (int i = 0; i < self.tabBar.items.count; ++i) {
        RDVTabBarItem *item = self.tabBar.items[i];
        item.backgroundColor = [UIColor clearColor];
        item.title = [titleArray objectAtIndexSafely:i];
        item.titlePositionAdjustment = UIOffsetMake(0, 4);
        item.selectedTitleAttributes = @{NSForegroundColorAttributeName: accent, NSFontAttributeName: [UIFont systemFontOfSize:11]};
        item.unselectedTitleAttributes = @{NSForegroundColorAttributeName: muted, NSFontAttributeName: [UIFont systemFontOfSize:11]};
        UIImage *selectedImage = [selectedIcons[i] imageWithTintColor:accent];
        UIImage *normalImage = [normalIcons[i] imageWithTintColor:muted];
        [item setFinishedSelectedImage:selectedImage withFinishedUnselectedImage:normalImage];
        [item removeTarget:self.tabBar action:@selector(tabBarItemWasSelected:) forControlEvents:UIControlEventTouchDown];
        [item addTarget:self.tabBar action:@selector(tabBarItemWasSelected:) forControlEvents:UIControlEventTouchUpInside];
        [item setNeedsDisplay];
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

@end
