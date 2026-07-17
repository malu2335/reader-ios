//
//  RDShareCardBuilder.h
//  Reader
//
//  按小说类型生成分享金句卡片
//

#import <UIKit/UIKit.h>
@class RDBookDetailModel;

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, RDShareCardGenre) {
    RDShareCardGenreDefault = 0,
    RDShareCardGenreXuanhuan,   // 玄幻
    RDShareCardGenreDushi,     // 都市
    RDShareCardGenreYanqing,   // 言情
    RDShareCardGenreWuxia,     // 武侠
    RDShareCardGenreLishi,     // 历史
    RDShareCardGenreKehuan,    // 科幻
    RDShareCardGenreXuanyi,    // 悬疑
};

@interface RDShareCardBuilder : NSObject

/// 根据书名/分类推断类型
+ (RDShareCardGenre)genreForBook:(RDBookDetailModel *)book;

/// 生成分享卡片图(宽约 1080pt 风格,按屏密度输出)
+ (UIImage *)cardImageWithQuote:(NSString *)quote
                           book:(RDBookDetailModel *)book
                          genre:(RDShareCardGenre)genre;

/// 分享文案
+ (NSString *)shareTextWithQuote:(NSString *)quote book:(RDBookDetailModel *)book;

/// 从正文截取金句:按句号/叹号/问号拆句,取足 maxLength 左右;截不出时返回 nil
+ (nullable NSString *)quoteFromText:(nullable NSString *)text
                       minSentenceLength:(NSInteger)minSentenceLength
                               maxLength:(NSInteger)maxLength;

@end

NS_ASSUME_NONNULL_END
