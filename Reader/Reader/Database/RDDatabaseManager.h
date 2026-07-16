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

@end

NS_ASSUME_NONNULL_END
