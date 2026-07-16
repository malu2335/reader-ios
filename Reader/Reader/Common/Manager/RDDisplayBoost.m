//
//  RDDisplayBoost.m
//  Reader
//
//  ProMotion 适配要点:
//  1. Info.plist CADisableMinimumFrameDurationOnPhone=YES (系统允许 <1/60 帧间隔)
//  2. UIPageViewController 的「仿真卷页」底层多为固定 ~60Hz,高刷上应优先「滑动翻页」
//  3. 滑动模式下配置内嵌 UIScrollView,减少主线程卡顿使 120Hz 可感知
//

#import "RDDisplayBoost.h"
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>

@implementation RDDisplayBoost

+ (UIScreen *)p_activeScreen
{
    UIWindow *key = [RDUtilities applicationKeyWindow];
    if (key.windowScene.screen) {
        return key.windowScene.screen;
    }
    return UIScreen.mainScreen;
}

+ (NSInteger)maximumFramesPerSecond
{
    return [self p_activeScreen].maximumFramesPerSecond;
}

+ (BOOL)isHighRefreshDisplay
{
    return [self maximumFramesPerSecond] > 61;
}

+ (NSTimeInterval)panelAnimationDuration
{
    return [self isHighRefreshDisplay] ? 0.22 : 0.30;
}

/// 高刷屏上推荐的翻页样式:滑动可跑满 120Hz;仿真卷页系统层常锁 60Hz
+ (RDPageType)preferredPageTypeForDisplay
{
    if ([self isHighRefreshDisplay]) {
        return RDSliderPage;
    }
    return RDRealTypePage;
}

+ (void)applyToWindow:(UIWindow *)window
{
    if (!window) {
        return;
    }
    CGFloat scale = window.screen.nativeScale > 0 ? window.screen.nativeScale : window.screen.scale;
    window.layer.contentsScale = scale;
    window.layer.rasterizationScale = scale;
    [CATransaction setDisableActions:NO];
    [self applyToView:window];
}

+ (void)applyToView:(UIView *)view
{
    if (!view) {
        return;
    }
    [self p_configureViewTree:view depth:0];
}

+ (void)applyToPageViewController:(UIPageViewController *)pageVC
{
    if (!pageVC) {
        return;
    }
    pageVC.view.layer.allowsGroupOpacity = NO;
    pageVC.view.layer.shouldRasterize = NO;
    CGFloat scale = pageVC.view.window.screen.nativeScale ?: UIScreen.mainScreen.nativeScale;
    pageVC.view.layer.contentsScale = scale;
    [self applyToView:pageVC.view];

    // 找到内嵌翻页 ScrollView,做高刷友好配置
    for (UIView *sub in pageVC.view.subviews) {
        if (![sub isKindOfClass:UIScrollView.class]) {
            continue;
        }
        UIScrollView *scroll = (UIScrollView *)sub;
        scroll.delaysContentTouches = NO;
        scroll.canCancelContentTouches = YES;
        // 高刷下关闭 bouncing 的额外 compositing 负担(可选保留默认)
        if ([self isHighRefreshDisplay]) {
            scroll.decelerationRate = UIScrollViewDecelerationRateFast;
            // iOS 15+: 降低内容 insets 动画对帧率影响
            scroll.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentNever;
        }
        // 确保不栅格化整页(栅格化会把卷页/滑动锁在较低合成率)
        scroll.layer.shouldRasterize = NO;
        scroll.layer.allowsGroupOpacity = NO;
        scroll.layer.contentsScale = scale;
    }
}

+ (void)p_configureViewTree:(UIView *)view depth:(NSInteger)depth
{
    if (depth > 8) {
        return;
    }
    CGFloat scale = view.window.screen.nativeScale;
    if (scale <= 0) {
        scale = UIScreen.mainScreen.nativeScale;
    }
    if (view.layer.contentsScale < scale - 0.01) {
        view.layer.contentsScale = scale;
    }
    // 禁止栅格化整棵子树,否则高刷动画常被锁 60
    if (view.layer.shouldRasterize) {
        view.layer.shouldRasterize = NO;
    }

    if ([view isKindOfClass:UIScrollView.class]) {
        UIScrollView *scroll = (UIScrollView *)view;
        scroll.delaysContentTouches = NO;
        if ([self isHighRefreshDisplay]) {
            scroll.decelerationRate = UIScrollViewDecelerationRateNormal;
        }
    }

    if ([view isKindOfClass:UITableView.class]) {
        ((UITableView *)view).prefetchingEnabled = YES;
    }

    for (UIView *sub in view.subviews) {
        [self p_configureViewTree:sub depth:depth + 1];
    }
}

@end
