//
//  RDDatabaseManager.m
//  Reader
//
//  Created by yuenov on 2019/12/29.
//  Copyright © 2019 yuenov. All rights reserved.
//

#import "RDDatabaseManager.h"
#import "RDDatabaseLifecycle.h"
#import "RDCharpterModel.h"
#import "RDCharpterModel+WCTTableCoding.h"
#import "RDBookDetailModel.h"
#import "RDBookmarkModel.h"
#import <sqlite3.h>

NSString * const RDDatabaseErrorDomain = @"RDDatabaseErrorDomain";

/// 旧版本把迁移完成标志写在 NSUserDefaults,与数据库文件生命周期脱钩
/// (删库重建后标志还在,迁移被永久跳过)。现改用 PRAGMA user_version,
/// 该键只用于一次性把旧标志接过来。
static NSString * const kLegacyPrimaryIdMigratedKey = @"RDChapterPrimaryIdMigrated_v1";

/// schema 版本:1 = chapter.primaryId 已统一为 bookId_charpterId
static const int kRDSchemaVersionPrimaryId = 1;

/// 独立 sqlite 连接的等锁超时(毫秒)。WCDB 同时持有这个文件,
/// 不设超时会在写锁竞争时无限期挂起整条数据库队列。
static const int kRDSQLiteBusyTimeoutMs = 5000;
static void *kRDBQueueSpecificKey = &kRDBQueueSpecificKey;

@interface RDDatabaseManager ()
@property (nonatomic, strong, readwrite) WCTDatabase *database;
@property (nonatomic, strong) dispatch_queue_t dbQueue;
@property (nonatomic, copy) NSString *dbPath;
@end

@implementation RDDatabaseManager

+ (RDDatabaseManager *)sharedInstance
{
    static RDDatabaseManager *sharedInstance = nil;
    static dispatch_once_t onceToken;

    dispatch_once(&onceToken, ^{
        sharedInstance = [[self alloc] init];
        sharedInstance.dbQueue = dispatch_queue_create("com.reader.wcdb", DISPATCH_QUEUE_SERIAL);
        dispatch_queue_set_specific(sharedInstance.dbQueue, kRDBQueueSpecificKey, kRDBQueueSpecificKey, NULL);

        NSString *dbPath = [PATH_DOCUMENT stringByAppendingPathComponent:kBookDatabase];
        sharedInstance.dbPath = dbPath;
        sharedInstance.database = [[WCTDatabase alloc] initWithPath:dbPath];
        [sharedInstance.database createTableAndIndexesOfName:kCharpterTable withClass:RDCharpterModel.class];
        [sharedInstance.database createTableAndIndexesOfName:kReadRecordTable withClass:RDBookDetailModel.class];
        [sharedInstance.database createTableAndIndexesOfName:kHistoryRecordTable withClass:RDBookDetailModel.class];
        [sharedInstance.database createTableAndIndexesOfName:kBookmarkTable withClass:RDBookmarkModel.class];
        // 兼容旧库:补阅读记忆 / 书架轻量字段
        [sharedInstance p_ensureColumn:@"charOffset" table:kReadRecordTable type:@"INTEGER"];
        [sharedInstance p_ensureColumn:@"charOffset" table:kHistoryRecordTable type:@"INTEGER"];
        [sharedInstance p_ensureColumn:@"readChapterName" table:kReadRecordTable type:@"TEXT"];
        [sharedInstance p_ensureColumn:@"readChapterName" table:kHistoryRecordTable type:@"TEXT"];

        NSDictionary *attrs = @{NSFileProtectionKey: NSFileProtectionCompleteUntilFirstUserAuthentication};
        [[NSFileManager defaultManager] setAttributes:attrs ofItemAtPath:dbPath error:nil];

        // 打开后尽快 checkpoint,减少下次启动 recovered frames
        dispatch_async(sharedInstance.dbQueue, ^{
            [sharedInstance p_checkpointWAL];
            [sharedInstance p_migratePrimaryIdsIfNeeded];
            [sharedInstance p_checkpointWAL];
            [sharedInstance p_applyDataProtectionToPath:[PATH_DOCUMENT stringByAppendingPathComponent:@"LocalBooks"]];
            [sharedInstance p_applyDataProtectionToPath:[PATH_DOCUMENT stringByAppendingPathComponent:@"AIConfig"]];
        });
    });

    return sharedInstance;
}

- (void)performSync:(void (^)(WCTDatabase *db))block
{
    if (!block) {
        return;
    }
    if (dispatch_get_specific(kRDBQueueSpecificKey) == kRDBQueueSpecificKey) {
        block(self.database);
        return;
    }
    dispatch_sync(self.dbQueue, ^{
        block(self.database);
    });
}

- (void)performAsync:(void (^)(WCTDatabase *db))block
{
    if (!block) {
        return;
    }
    dispatch_async(self.dbQueue, ^{
        block(self.database);
    });
}

- (BOOL)performTransactionSync:(BOOL (^)(WCTInterface *db))block error:(NSError **)error
{
    if (!block) {
        return NO;
    }
    __block BOOL committed = NO;
    __block WCTError *dbError = nil;
    void (^work)(void) = ^{
        WCTTransaction *transaction = [self.database getTransaction];
        if (!transaction) {
            return;
        }
        committed = [transaction runTransaction:^BOOL{
            return block(transaction);
        }];
        if (!committed) {
            dbError = [transaction error];
        }
    };
    if (dispatch_get_specific(kRDBQueueSpecificKey) == kRDBQueueSpecificKey) {
        work();
    }
    else {
        dispatch_sync(self.dbQueue, work);
    }
    if (!committed && error) {
        NSString *message = [dbError isKindOfClass:WCTError.class] ? [dbError infoForKey:WCTErrorKeyMessage] : nil;
        if (![message isKindOfClass:NSString.class] || message.length == 0) {
            message = @"数据库写入失败";
        }
        *error = [NSError errorWithDomain:RDDatabaseErrorDomain
                                     code:dbError ? dbError.code : -1
                                 userInfo:@{NSLocalizedDescriptionKey: message}];
    }
    return committed;
}

- (void)checkpointWALAsync
{
    dispatch_async(self.dbQueue, ^{
        [self p_checkpointWAL];
    });
}

- (void)checkpointWALSync
{
    if (dispatch_get_specific(kRDBQueueSpecificKey) == kRDBQueueSpecificKey) {
        [self p_checkpointWAL];
        return;
    }
    dispatch_semaphore_t sema = dispatch_semaphore_create(0);
    dispatch_async(self.dbQueue, ^{
        [self p_checkpointWAL];
        dispatch_semaphore_signal(sema);
    });
    dispatch_semaphore_wait(sema, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2 * NSEC_PER_SEC)));
}

/// 使用独立 sqlite 连接做 TRUNCATE checkpoint,避免依赖 WINQ C++ API
- (void)p_checkpointWAL
{
    if (self.dbPath.length == 0) {
        return;
    }
    sqlite3 *db = NULL;
    // 只读写打开同一文件做 checkpoint;与 WCDB 多连接模型兼容
    int rc = sqlite3_open_v2(self.dbPath.fileSystemRepresentation, &db,
                             SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX, NULL);
    if (rc != SQLITE_OK || !db) {
        if (db) {
            sqlite3_close(db);
        }
        return;
    }
    // WCDB 正持有同一个文件;不设超时的话这条独立连接可能无限期等写锁
    sqlite3_busy_timeout(db, kRDSQLiteBusyTimeoutMs);
    // 更积极的自动 checkpoint 阈值
    sqlite3_exec(db, "PRAGMA wal_autocheckpoint=100;", NULL, NULL, NULL);
    // TRUNCATE:合并并尽量清空 -wal,下次启动 recovered frames 接近 0
    sqlite3_exec(db, "PRAGMA wal_checkpoint(TRUNCATE);", NULL, NULL, NULL);
    sqlite3_close(db);
}

- (void)p_applyDataProtectionToPath:(NSString *)path
{
    if (path.length == 0) {
        return;
    }
    NSFileManager *fm = [NSFileManager defaultManager];
    if (![fm fileExistsAtPath:path]) {
        return;
    }
    NSDictionary *attrs = @{NSFileProtectionKey: NSFileProtectionCompleteUntilFirstUserAuthentication};
    [fm setAttributes:attrs ofItemAtPath:path error:nil];
    BOOL isDir = NO;
    if ([fm fileExistsAtPath:path isDirectory:&isDir] && isDir) {
        NSArray *children = [fm contentsOfDirectoryAtPath:path error:nil];
        for (NSString *rel in children) {
            NSString *full = [path stringByAppendingPathComponent:rel];
            [fm setAttributes:attrs ofItemAtPath:full error:nil];
        }
    }
}

/// 读数据库自身的 schema 版本(PRAGMA user_version)
- (int)p_schemaVersion
{
    if (self.dbPath.length == 0) {
        return 0;
    }
    sqlite3 *db = NULL;
    if (sqlite3_open_v2(self.dbPath.fileSystemRepresentation, &db,
                        SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX, NULL) != SQLITE_OK || !db) {
        if (db) {
            sqlite3_close(db);
        }
        return -1;   // 打不开:当作未知,不要据此跳过迁移
    }
    sqlite3_busy_timeout(db, kRDSQLiteBusyTimeoutMs);
    int version = 0;
    sqlite3_stmt *stmt = NULL;
    if (sqlite3_prepare_v2(db, "PRAGMA user_version;", -1, &stmt, NULL) == SQLITE_OK) {
        if (sqlite3_step(stmt) == SQLITE_ROW) {
            version = sqlite3_column_int(stmt, 0);
        }
        sqlite3_finalize(stmt);
    }
    sqlite3_close(db);
    return version;
}

- (BOOL)p_setSchemaVersion:(int)version
{
    if (self.dbPath.length == 0) {
        return NO;
    }
    sqlite3 *db = NULL;
    if (sqlite3_open_v2(self.dbPath.fileSystemRepresentation, &db,
                        SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX, NULL) != SQLITE_OK || !db) {
        if (db) {
            sqlite3_close(db);
        }
        return NO;
    }
    // user_version 是一次真实写入,必须能超时失败而不是死等 WCDB 的写锁;
    // 写不进去也没关系——迁移是幂等的,下次启动会重跑。
    sqlite3_busy_timeout(db, kRDSQLiteBusyTimeoutMs);
    NSString *sql = [NSString stringWithFormat:@"PRAGMA user_version = %d;", version];
    BOOL ok = sqlite3_exec(db, sql.UTF8String, NULL, NULL, NULL) == SQLITE_OK;
    sqlite3_close(db);
    return ok;
}

- (void)p_migratePrimaryIdsIfNeeded
{
    // 一次性接管旧的 NSUserDefaults 标志:老用户已迁移过的库直接补写 user_version
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    if ([defaults boolForKey:kLegacyPrimaryIdMigratedKey]) {
        if ([self p_schemaVersion] < kRDSchemaVersionPrimaryId) {
            [self p_setSchemaVersion:kRDSchemaVersionPrimaryId];
        }
        [defaults removeObjectForKey:kLegacyPrimaryIdMigratedKey];
        return;
    }
    if ([self p_schemaVersion] >= kRDSchemaVersionPrimaryId) {
        return;
    }
    // 只取键列(绝不把章节正文整表载入内存),大书库首启不再有 OOM 风险
    NSArray <RDCharpterModel *>*rows = [self.database getAllObjectsOnResults:{RDCharpterModel.primaryId,
                                                                              RDCharpterModel.bookId,
                                                                              RDCharpterModel.charpterId}
                                                                   fromTable:kCharpterTable];
    NSMutableArray <NSArray *>*pending = [NSMutableArray array]; // @[old, desired]
    for (RDCharpterModel *chapter in rows) {
        NSString *desired = [NSString stringWithFormat:@"%@_%@", @(chapter.bookId), @(chapter.charpterId)];
        // 直接读 ivar 值需经 getter,getter 会伪造 desired;这里 fetch 出来的对象 _primaryId 即库值
        NSString *old = chapter.primaryId;
        if ([old isEqualToString:desired]) {
            continue;
        }
        [pending addObject:@[old ?: @"", desired]];
    }
    if (pending.count == 0) {
        [self p_setSchemaVersion:kRDSchemaVersionPrimaryId];
        return;
    }
    // 分批小事务,中途被杀也可幂等续跑(按主键更新,不搬 content)
    const NSUInteger batchSize = 500;
    BOOL allBatchesCommitted = YES;
    for (NSUInteger start = 0; start < pending.count; start += batchSize) {
        NSUInteger end = MIN(start + batchSize, pending.count);
        BOOL committed = [self.database runTransaction:^BOOL{
            for (NSUInteger i = start; i < end; i++) {
                NSString *old = pending[i][0];
                NSString *desired = pending[i][1];
                if (old.length == 0) {
                    continue;
                }
                // 目标主键已存在(重复数据)则删旧行,否则原地改主键
                RDCharpterModel *conflict = [self.database getOneObjectOnResults:{RDCharpterModel.primaryId}
                                                                       fromTable:kCharpterTable
                                                                           where:RDCharpterModel.primaryId.is(desired)];
                if (conflict) {
                    [self.database deleteObjectsFromTable:kCharpterTable where:RDCharpterModel.primaryId.is(old)];
                }
                else {
                    RDCharpterModel *patch = [[RDCharpterModel alloc] init];
                    patch.primaryId = desired;
                    if (![self.database updateRowsInTable:kCharpterTable
                                               onProperty:RDCharpterModel.primaryId
                                               withObject:patch
                                                    where:RDCharpterModel.primaryId.is(old)]) {
                        return NO;
                    }
                }
            }
            return YES;
        }];
        if (!committed) {
            allBatchesCommitted = NO;
            break;
        }
    }
    // 只有全部批次提交、且复查确实没有残留异常主键时才落完成标志;
    // 否则下次启动继续跑(迁移幂等),不能永久跳过(P1-03)。
    if (!allBatchesCommitted || ![self p_primaryIdMigrationIsComplete]) {
        return;
    }
    [self p_setSchemaVersion:kRDSchemaVersionPrimaryId];
}

/// 复查:全表已不存在 primaryId 与 bookId_charpterId 不一致的行
- (BOOL)p_primaryIdMigrationIsComplete
{
    NSArray <RDCharpterModel *>*rows = [self.database getAllObjectsOnResults:{RDCharpterModel.primaryId,
                                                                              RDCharpterModel.bookId,
                                                                              RDCharpterModel.charpterId}
                                                                   fromTable:kCharpterTable];
    if (!rows) {
        return NO;   // 查询失败与"表为空"必须区分开,失败时不落完成标志
    }
    for (RDCharpterModel *chapter in rows) {
        NSString *desired = [NSString stringWithFormat:@"%@_%@", @(chapter.bookId), @(chapter.charpterId)];
        if (![chapter.primaryId isEqualToString:desired]) {
            return NO;
        }
    }
    return YES;
}

/// 旧库缺列时 ALTER TABLE 补齐(幂等)
- (void)p_ensureColumn:(NSString *)column table:(NSString *)table type:(NSString *)type
{
    if (column.length == 0 || table.length == 0 || self.dbPath.length == 0) {
        return;
    }
    sqlite3 *db = NULL;
    int rc = sqlite3_open_v2(self.dbPath.fileSystemRepresentation, &db,
                             SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX, NULL);
    if (rc != SQLITE_OK || !db) {
        if (db) {
            sqlite3_close(db);
        }
        return;
    }
    sqlite3_busy_timeout(db, kRDSQLiteBusyTimeoutMs);
    BOOL exists = NO;
    NSString *pragma = [NSString stringWithFormat:@"PRAGMA table_info(%@);", table];
    sqlite3_stmt *stmt = NULL;
    if (sqlite3_prepare_v2(db, pragma.UTF8String, -1, &stmt, NULL) == SQLITE_OK) {
        while (sqlite3_step(stmt) == SQLITE_ROW) {
            const char *name = (const char *)sqlite3_column_text(stmt, 1);
            if (name && [[NSString stringWithUTF8String:name] isEqualToString:column]) {
                exists = YES;
                break;
            }
        }
        sqlite3_finalize(stmt);
    }
    if (!exists) {
        NSString *sql = [NSString stringWithFormat:@"ALTER TABLE %@ ADD COLUMN %@ %@;", table, column, type ?: @"INTEGER"];
        sqlite3_exec(db, sql.UTF8String, NULL, NULL, NULL);
    }
    sqlite3_close(db);
}

@end

@implementation RDDatabaseLifecycle

+ (void)checkpointWALAsync
{
    [[RDDatabaseManager sharedInstance] checkpointWALAsync];
}

+ (void)checkpointWALSync
{
    [[RDDatabaseManager sharedInstance] checkpointWALSync];
}

@end

