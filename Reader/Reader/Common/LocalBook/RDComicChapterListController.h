//
//  RDComicChapterListController.h
//  Reader
//
//  多话漫画目录:点击书架后按「话」列表展示,再进入阅读器
//

#import "RDBaseViewController.h"
@class RDBookDetailModel;

NS_ASSUME_NONNULL_BEGIN

@interface RDComicChapterListController : RDBaseViewController
@property (nonatomic, strong) RDBookDetailModel *bookDetail;
@end

NS_ASSUME_NONNULL_END
