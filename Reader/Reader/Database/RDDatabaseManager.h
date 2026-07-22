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
#define kBookmarkTable @"bookmark"

NS_ASSUME_NONNULL_BEGIN

/// 数据库层统一错误域;code 直接透传 WCDB/SQLite 的错误码
extern NSString * const RDDatabaseErrorDomain;

@interface RDDatabaseManager : NSObject
@property (nonatomic, strong, readonly) WCTDatabase *database;
/// 建表/补列失败时非空;书架可据此展示可重试错误而非空列表(P2-DB-01)
@property (nonatomic, strong, readonly, nullable) NSError *initializationError;

+ (RDDatabaseManager *)sharedInstance;

/// 在串行队列同步执行 DB 操作(避免导入/恢复/UI 并发写)
- (void)performSync:(void (^)(WCTDatabase *db))block;
/// 在串行队列异步执行
- (void)performAsync:(void (^)(WCTDatabase *db))block;

/// 在串行队列内跑一次数据库事务。block 返回 NO 或内部写失败即整体回滚,
/// 并把 WCDB 的错误转成 NSError 输出(P1-03:写失败不得被吞成"成功")。
/// block 收到的是本次事务句柄(WCTTransaction),所有写必须走它才在事务内。
- (BOOL)performTransactionSync:(BOOL (^)(WCTInterface *db))block error:(NSError **)error;

/// 将 WAL 合并进主库并尽量截断 -wal(后台调用,减少下次启动 recover frames)
- (void)checkpointWALAsync;

/// 进入后台/退出前尽量同步 checkpoint
- (void)checkpointWALSync;

@end

NS_ASSUME_NONNULL_END
