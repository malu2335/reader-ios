//
//  RDBookTextUtil.h
//  Reader
//
//  本地书籍解析共用的文本工具:编码识别、HTML 转纯文本
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface RDBookTextUtil : NSObject

/// 按 BOM / UTF-8 / GB18030 / Big5 / Latin-1 顺序探测解码文本数据
+ (nullable NSString *)stringFromData:(NSData *)data;

/// 指定编码解码,失败时回退到自动探测
+ (nullable NSString *)stringFromData:(NSData *)data encoding:(NSStringEncoding)encoding;

/// HTML 转纯文本:去 script/style、块级标签转换行、解实体、折叠空行
+ (NSString *)plainTextFromHTML:(NSString *)html;

/// 抽取 HTML 中第一个 h1-h4 或 title 的文本,找不到返回 nil
+ (nullable NSString *)headingFromHTML:(NSString *)html;

/// 统一换行符并去掉行尾空白
+ (NSString *)normalizeLineBreaks:(NSString *)text;

@end

NS_ASSUME_NONNULL_END
