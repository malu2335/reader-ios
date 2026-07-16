//
//  RDPdfReadController.h
//  Reader
//
//  本地 PDF 阅读器:PDFKit 渲染、翻页进度记忆
//

#import "RDBaseViewController.h"
@class RDBookDetailModel;

NS_ASSUME_NONNULL_BEGIN

@interface RDPdfReadController : RDBaseViewController

@property (nonatomic,strong) RDBookDetailModel *bookDetail;

@end

NS_ASSUME_NONNULL_END
