//
//  RDDatabaseManager.m
//  Reader
//
//  Created by yuenov on 2019/12/29.
//  Copyright © 2019 yuenov. All rights reserved.
//

#import "RDDatabaseManager.h"
#import "RDCharpterModel.h"
#import "RDCharpterModel+WCTTableCoding.h"
#import "RDBookDetailModel.h"

static NSString * const kPrimaryIdMigratedKey = @"RDChapterPrimaryIdMigrated_v1";
static void *kRDBQueueSpecificKey = &kRDBQueueSpecificKey;

@interface RDDatabaseManager ()
@property (nonatomic, strong, readwrite) WCTDatabase *database;
@property (nonatomic, strong) dispatch_queue_t dbQueue;
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
        // 只做打开 + 建表,不做全表迁移/目录遍历,避免阻塞首屏
        sharedInstance.database = [[WCTDatabase alloc] initWithPath:dbPath];
        [sharedInstance.database createTableAndIndexesOfName:kCharpterTable withClass:RDCharpterModel.class];
        [sharedInstance.database createTableAndIndexesOfName:kReadRecordTable withClass:RDBookDetailModel.class];
        [sharedInstance.database createTableAndIndexesOfName:kHistoryRecordTable withClass:RDBookDetailModel.class];

        // DB 文件本身保护开销小
        NSDictionary *attrs = @{NSFileProtectionKey: NSFileProtectionCompleteUntilFirstUserAuthentication};
        [[NSFileManager defaultManager] setAttributes:attrs ofItemAtPath:dbPath error:nil];

        // 迁移与大目录保护放到后台,不挡启动
        dispatch_async(sharedInstance.dbQueue, ^{
            [sharedInstance p_migratePrimaryIdsIfNeeded];
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
        // 仅保护顶层文件,避免启动后仍长时间扫整棵 LocalBooks
        NSArray *children = [fm contentsOfDirectoryAtPath:path error:nil];
        for (NSString *rel in children) {
            NSString *full = [path stringByAppendingPathComponent:rel];
            [fm setAttributes:attrs ofItemAtPath:full error:nil];
        }
    }
}

/// 将旧 primaryId 迁移为 bookId_charpterId(后台执行,仅一次)
- (void)p_migratePrimaryIdsIfNeeded
{
    if ([[NSUserDefaults standardUserDefaults] boolForKey:kPrimaryIdMigratedKey]) {
        return;
    }
    // 已在 dbQueue 上
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
