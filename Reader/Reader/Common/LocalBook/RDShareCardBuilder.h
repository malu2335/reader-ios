//
//  RDShareCardBuilder.h
//  Reader
//
//  金句卡片:按分享内容的意境自动选择背景(关键词 → 主题;无命中按文本哈希稳定散列)
//

#import <UIKit/UIKit.h>
@class RDBookDetailModel;

NS_ASSUME_NONNULL_BEGIN

/// 导出用像素尺寸(1x 逻辑像素 = 输出像素,scale 固定为 1)
FOUNDATION_EXPORT const CGSize RDShareCardExportPixelSize;
/// 面板预览用尺寸(约为导出一半,粒子与字号按比例缩放,拖拽选区时更轻)
FOUNDATION_EXPORT const CGSize RDShareCardPreviewPixelSize;

@interface RDShareCardBuilder : NSObject

/// 生成金句卡片(默认导出尺寸 1080×1440@1x):背景意境由 quote 内容决定,同句稳定、异句各异
+ (UIImage *)cardImageWithQuote:(NSString *)quote book:(nullable RDBookDetailModel *)book;

/// 可指定像素尺寸与已解码封面,避免预览反复读盘、全分辨率重绘
/// @param pixelSize 输出像素尺寸;宽高任一 ≤0 时回退到导出尺寸。内部以 1080 宽为设计基准等比缩放布局。
/// @param cover 可选;传 nil 时按 book 同步读封面(仅导出兜底路径需要)
+ (UIImage *)cardImageWithQuote:(NSString *)quote
                           book:(nullable RDBookDetailModel *)book
                      pixelSize:(CGSize)pixelSize
                          cover:(nullable UIImage *)cover;

/// 从正文截取金句:按句号/叹号/问号拆句,取足 maxLength 左右;截不出时返回 nil
+ (nullable NSString *)quoteFromText:(nullable NSString *)text
                       minSentenceLength:(NSInteger)minSentenceLength
                               maxLength:(NSInteger)maxLength;

@end

/// 阅读页内的选句分享面板:长按选中本页字句 → 卡片实时预览 → 仅以图片分享
@interface RDQuoteShareController : UIViewController
@property (nonatomic,strong) RDBookDetailModel *book;
@property (nonatomic,copy) NSString *pageText;
@end

NS_ASSUME_NONNULL_END
