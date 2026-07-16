//
//  RDDatabaseManager.h
//  Reader
//
//  Created by yuenov on 2019/12/29.
//  Copyright © 2019 yuenov. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <WCDB/WCDB.h>
#define kBookDatabase @"book"
#define kCharpterTable @"chapter"
#define kReadRecordTable @"read"
#define kHistoryRecordTable @"history"

NS_ASSUME_NONNULL_BEGIN

@interface RDDatabaseManager : NSObject
@property (nonatomic, strong, readonly) WCTDatabase *database;

+ (RDDatabaseManager *)sharedInstance;

/// 在串行队列同步执行 DB 操作(避免导入/恢复/UI 并发写)
- (void)performSync:(void (^)(WCTDatabase *db))block;
/// 在串行队列异步执行
- (void)performAsync:(void (^)(WCTDatabase *db))block;

/// 将 WAL 合并进主库并尽量截断 -wal(后台调用,减少下次启动 recover frames)
- (void)checkpointWALAsync;

/// 进入后台/退出前尽量同步 checkpoint
- (void)checkpointWALSync;

@end

NS_ASSUME_NONNULL_END
