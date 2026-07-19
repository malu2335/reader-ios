//
//  RDCharpterDataManager+DBInternal.h
//  Reader
//
//  仅供 Objective-C++ (.mm) 数据库层内部使用:暴露可嵌进外层事务的写操作,
//  这样导入/恢复能把章节和读记录合并进同一次事务(见 RDLibraryTransaction)。
//

#import "RDCharpterDataManager.h"
#import <WCDB/WCDB.h>

NS_ASSUME_NONNULL_BEGIN

@interface RDCharpterDataManager (DBInternal)

/// 在调用方已开启的事务内替换整本书的章节;任一写失败返回 NO 由外层回滚
+(BOOL)db_replaceChaptersForBookId:(NSInteger)bookId
                          chapters:(NSArray *)chapters
                        inDatabase:(WCTInterface *)db;

@end

NS_ASSUME_NONNULL_END
