//
//  RDBookshelfCollectionController.h
//  Reader
//
//  合集目录:像漫画「话列表」一样展示成员书,可导入新书、移出、打开阅读。
//

#import "RDBaseViewController.h"
@class RDBookDetailModel;

NS_ASSUME_NONNULL_BEGIN

@interface RDBookshelfCollectionController : RDBaseViewController
@property (nonatomic, strong) RDBookDetailModel *collection; // 合集壳
@end

NS_ASSUME_NONNULL_END
