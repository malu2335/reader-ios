//
//  RDComicReadController.h
//  Reader
//
//  本地漫画/图集:ZIP·CBZ;支持默认(左→右)/日漫(右→左)/条漫(竖滑)
//

#import "RDBaseViewController.h"
@class RDBookDetailModel;
@class RDCharpterModel;

NS_ASSUME_NONNULL_BEGIN

@interface RDComicReadController : RDBaseViewController

@property (nonatomic,strong) RDBookDetailModel *bookDetail;
/// 多话漫画:当前话(content 含 comicPrefix);扁平图集为 nil
@property (nonatomic,strong,nullable) RDCharpterModel *chapter;

@end

NS_ASSUME_NONNULL_END
