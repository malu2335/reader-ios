//
//  RDShareCardBuilder.h
//  Reader
//
//  金句卡片:按分享内容的意境自动选择背景(关键词 → 主题;无命中按文本哈希稳定散列)
//

#import <UIKit/UIKit.h>
@class RDBookDetailModel;

NS_ASSUME_NONNULL_BEGIN

@interface RDShareCardBuilder : NSObject

/// 生成金句卡片(1080×1440@1x):背景意境由 quote 内容决定,同句稳定、异句各异
+ (UIImage *)cardImageWithQuote:(NSString *)quote book:(RDBookDetailModel *)book;

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
