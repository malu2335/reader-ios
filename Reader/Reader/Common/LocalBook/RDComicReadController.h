//
//  RDComicReadController.h
//  Reader
//
//  本地漫画/图集阅读器:ZIP·CBZ·打包后的图片集,分页与进度记忆
//

#import "RDBaseViewController.h"
@class RDBookDetailModel;

NS_ASSUME_NONNULL_BEGIN

@interface RDComicReadController : RDBaseViewController

@property (nonatomic,strong) RDBookDetailModel *bookDetail;

@end

NS_ASSUME_NONNULL_END
