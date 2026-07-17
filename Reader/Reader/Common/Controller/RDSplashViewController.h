//
//  RDSplashViewController.h
//  Reader
//
//  启动页:视觉对齐 LaunchScreen,期间预加载书架
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface RDSplashViewController : UIViewController
@property (nonatomic, copy, nullable) void (^onFinished)(void);
@end

NS_ASSUME_NONNULL_END
