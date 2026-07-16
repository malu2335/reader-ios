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
#import <sqlite3.h>

static NSString * const kPrimaryIdMigratedKey = @"RDChapterPrimaryIdMigrated_v1";
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

- (void)p_migratePrimaryIdsIfNeeded
{
    if ([[NSUserDefaults standardUserDefaults] boolForKey:kPrimaryIdMigratedKey]) {
        return;
    }
    NSArray <RDCharpterModel *>*all = [self.database getAllObjectsOfClass:RDCharpterModel.class fromTable:kCharpterTable];
    if (all.count == 0) {
        [[NSUserDefaults standardUserDefaults] setBool:YES forKey:kPrimaryIdMigratedKey];
        return;
    }
    [self.database runTransaction:^BOOL{
        for (RDCharpterModel *chapter in all) {
            NSString *desired = [NSString stringWithFormat:@"%@_%@", @(chapter.bookId), @(chapter.charpterId)];
            if ([chapter.primaryId isEqualToString:desired]) {
                continue;
            }
            [self.database deleteObjectsFromTable:kCharpterTable where:RDCharpterModel.primaryId.is(chapter.primaryId)];
            chapter.primaryId = desired;
            [self.database insertOrReplaceObject:chapter into:kCharpterTable];
        }
        return YES;
    }];
    [[NSUserDefaults standardUserDefaults] setBool:YES forKey:kPrimaryIdMigratedKey];
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

