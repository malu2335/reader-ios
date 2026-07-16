//
//  RDLocalBookParseResult.h
//  Reader
//
//  本地书籍解析结果:各格式解析器的统一产物
//

#import <Foundation/Foundation.h>
@class RDCharpterModel;

NS_ASSUME_NONNULL_BEGIN

@interface RDLocalBookParseResult : NSObject
@property (nonatomic,strong,nullable) NSString *title;
@property (nonatomic,strong,nullable) NSString *author;
@property (nonatomic,strong) NSArray <RDCharpterModel *>*chapters;   //bookId 由导入方回填
@property (nonatomic,strong,nullable) NSData *coverData;             //内嵌封面(epub/mobi)
@end

NS_ASSUME_NONNULL_END
