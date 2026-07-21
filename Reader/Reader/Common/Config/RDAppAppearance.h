//
//  RDAppAppearance.h
//  Reader
//
//  全局深色模式:设置开关 OR 阅读夜读主题 → window 强制 Dark,设计令牌走动态色。
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/// 有效深色状态变化(设置开关 / 阅读主题 任一变化)
FOUNDATION_EXPORT NSString * const RDAppAppearanceDidChangeNotification;

@interface RDAppAppearance : NSObject

+ (instancetype)sharedInstance;

/// 设置页「黑暗模式」开关(UserDefaults 持久化)
@property (nonatomic, assign) BOOL darkModeEnabled;

/// 当前是否应对外层 UI 使用深色(开关开,或阅读主题为夜读)
- (BOOL)isEffectiveDark;

/// 将有效深色应用到所有 window(overrideUserInterfaceStyle)
- (void)applyToWindows;

/// 启动时调用一次
- (void)bootstrap;

@end

NS_ASSUME_NONNULL_END
