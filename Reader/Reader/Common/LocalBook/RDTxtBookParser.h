//
//  RDTxtBookParser.h
//  Reader
//
//  TXT 导入:编码探测 + 中文章节标题切分
//

#import <Foundation/Foundation.h>
#import "RDLocalBookParseResult.h"

NS_ASSUME_NONNULL_BEGIN

@interface RDTxtBookParser : NSObject

+ (nullable RDLocalBookParseResult *)parseFileAtPath:(NSString *)path error:(NSString * _Nullable * _Nullable)errorMessage;

@end

NS_ASSUME_NONNULL_END
