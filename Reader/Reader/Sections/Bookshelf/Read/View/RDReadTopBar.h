//
//  RDReadTopBar.h
//  Reader
//
//  阅读页顶栏:返回 + AI 翻译 + 听书
//

#import <UIKit/UIKit.h>
#import "RDBookDetailModel.h"
NS_ASSUME_NONNULL_BEGIN

@protocol RDReadTopBarDelegate <NSObject>
-(void)backAction;
-(void)speechAction;
-(void)translateAction;
@end

@interface RDReadTopBar : UIView
@property (nonatomic,weak) id<RDReadTopBarDelegate>delegate;
//阅读进度
@property (nonatomic,strong) RDBookDetailModel *record;
@end

NS_ASSUME_NONNULL_END
