//
//  RDEpubBookParser.h
//  Reader
//
//  EPUB 导入:container.xml → OPF(manifest/spine/metadata)→ 章节 HTML 转纯文本
//

#import <Foundation/Foundation.h>
#import "RDLocalBookParseResult.h"

NS_ASSUME_NONNULL_BEGIN

@interface RDEpubBookParser : NSObject

+ (nullable RDLocalBookParseResult *)parseFileAtPath:(NSString *)path error:(NSString * _Nullable * _Nullable)errorMessage;

@end

NS_ASSUME_NONNULL_END
