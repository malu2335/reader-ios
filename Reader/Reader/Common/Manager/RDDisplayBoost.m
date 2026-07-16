//
//  RDDisplayBoost.m
//  Reader
//

#import "RDDisplayBoost.h"
#import <QuartzCore/QuartzCore.h>

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
    // 高刷下菜单进出更跟手;60Hz 保持 0.3
    return [self isHighRefreshDisplay] ? 0.22 : 0.30;
}

+ (void)applyToWindow:(UIWindow *)window
{
    if (!window) {
        return;
    }
    // 使用物理像素对齐,避免 3x/高刷下半像素模糊
    CGFloat scale = window.screen.nativeScale > 0 ? window.screen.nativeScale : window.screen.scale;
    window.layer.contentsScale = scale;
    window.layer.rasterizationScale = scale;
    // Core Animation 默认会随 ProMotion 升帧;确保不强制关动画
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

+ (void)p_configureViewTree:(UIView *)view depth:(NSInteger)depth
{
    // 限制深度,避免整树递归过重
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

    if ([view isKindOfClass:UIScrollView.class]) {
        UIScrollView *scroll = (UIScrollView *)view;
        // 高刷下更跟手的减速曲线
        if ([self isHighRefreshDisplay]) {
            scroll.decelerationRate = UIScrollViewDecelerationRateNormal;
        }
        // 分页/翻页手势更顺
        scroll.delaysContentTouches = NO;
        // iOS 15+ 允许滚动在高帧率下合成
        if (@available(iOS 15.0, *)) {
            // 无直接 API 绑 120Hz;依赖 Info.plist CADisableMinimumFrameDurationOnPhone
            // 这里开启预取,减少翻页时掉帧
            scroll.directionalLockEnabled = scroll.pagingEnabled ? YES : scroll.directionalLockEnabled;
        }
    }

    if ([view isKindOfClass:UITableView.class]) {
        UITableView *table = (UITableView *)view;
        // 预估高度关闭时滚动更稳;保持 estimated 已有逻辑
        table.prefetchingEnabled = YES;
    }

    for (UIView *sub in view.subviews) {
        [self p_configureViewTree:sub depth:depth + 1];
    }
}

@end
