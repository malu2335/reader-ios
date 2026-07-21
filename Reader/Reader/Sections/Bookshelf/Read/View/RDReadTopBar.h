//
//  RDReadTopBar.h
//  Reader
//
//  阅读页顶栏:返回 + 分享金句 + 听书
//

#import <UIKit/UIKit.h>
#import "RDBookDetailModel.h"
NS_ASSUME_NONNULL_BEGIN

@protocol RDReadTopBarDelegate <NSObject>
-(void)backAction;
-(void)speechAction;
-(void)shareQuoteAction;
@end

@interface RDReadTopBar : UIView
@property (nonatomic,weak) id<RDReadTopBarDelegate>delegate;
//阅读进度
@property (nonatomic,strong) RDBookDetailModel *record;
/// 跟随阅读主题(夜读时顶栏同步深色)
- (void)applyChromeTheme;
@end

NS_ASSUME_NONNULL_END
