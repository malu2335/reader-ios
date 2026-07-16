//
//  RDDisplayBoost.h
//  Reader
//
//  高刷屏(ProMotion 120Hz)适配:开启系统允许的最短帧间隔,并给关键视图开启平滑滚动
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface RDDisplayBoost : NSObject

/// 当前屏幕最大刷新率(如 60 / 120)
+ (NSInteger)maximumFramesPerSecond;

/// 是否为高刷屏(>60)
+ (BOOL)isHighRefreshDisplay;

/// 启动时调用:配置 window 与根视图树
+ (void)applyToWindow:(UIWindow *)window;

/// 对阅读/列表等交互容器再次应用(新建 PageVC 后调用)
+ (void)applyToView:(UIView *)view;

/// 推荐的菜单/面板动画时长:高刷下略短,观感更跟手
+ (NSTimeInterval)panelAnimationDuration;

@end

NS_ASSUME_NONNULL_END
