//
//  RDReadRecordManager+DBInternal.h
//  Reader
//
//  仅供 Objective-C++ (.mm) 数据库层内部使用,见 RDCharpterDataManager+DBInternal.h。
//

#import "RDReadRecordManager.h"
#import <WCDB/WCDB.h>

NS_ASSUME_NONNULL_BEGIN

@interface RDReadRecordManager (DBInternal)

/// 在调用方已开启的事务内写读记录;写失败返回 NO 由外层回滚
+(BOOL)db_insertOrReplaceModel:(RDBookDetailModel *)model
                 touchReadTime:(BOOL)touchReadTime
                    inDatabase:(WCTInterface *)db;

@end

NS_ASSUME_NONNULL_END
