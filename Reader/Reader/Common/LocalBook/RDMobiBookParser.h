//
//  RDMobiBookParser.h
//  Reader
//
//  MOBI 导入:PalmDB 容器 + PalmDOC(LZ77)解压,支持无 DRM 的标准 mobi;
//  加密文件与 HUFF/CDIC 压缩会返回明确的错误信息
//

#import <Foundation/Foundation.h>
#import "RDLocalBookParseResult.h"

NS_ASSUME_NONNULL_BEGIN

@interface RDMobiBookParser : NSObject

+ (nullable RDLocalBookParseResult *)parseFileAtPath:(NSString *)path error:(NSString * _Nullable * _Nullable)errorMessage;

@end

NS_ASSUME_NONNULL_END
