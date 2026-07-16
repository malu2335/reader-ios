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
        sharedInstance.database = [[WCTDatabase alloc] initWithPath:dbPath];
        [sharedInstance.database createTableAndIndexesOfName:kCharpterTable withClass:RDCharpterModel.class];
        [sharedInstance.database createTableAndIndexesOfName:kReadRecordTable withClass:RDBookDetailModel.class];
        [sharedInstance.database createTableAndIndexesOfName:kHistoryRecordTable withClass:RDBookDetailModel.class];

        // 文件保护:未解锁设备时不可读
        [sharedInstance p_applyDataProtectionToPath:dbPath];
        NSString *localBooks = [PATH_DOCUMENT stringByAppendingPathComponent:@"LocalBooks"];
        [sharedInstance p_applyDataProtectionToPath:localBooks];
        NSString *aiDir = [PATH_DOCUMENT stringByAppendingPathComponent:@"AIConfig"];
        [sharedInstance p_applyDataProtectionToPath:aiDir];

        [sharedInstance p_migratePrimaryIdsIfNeeded];
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
    // 目录则尽量保护子项
    BOOL isDir = NO;
    if ([fm fileExistsAtPath:path isDirectory:&isDir] && isDir) {
        NSDirectoryEnumerator *en = [fm enumeratorAtPath:path];
        for (NSString *rel in en) {
            NSString *full = [path stringByAppendingPathComponent:rel];
            [fm setAttributes:attrs ofItemAtPath:full error:nil];
        }
    }
}

/// 将旧 primaryId(bookId 与 charpterId 数字拼接)迁移为 bookId_charpterId
- (void)p_migratePrimaryIdsIfNeeded
{
    if ([[NSUserDefaults standardUserDefaults] boolForKey:kPrimaryIdMigratedKey]) {
        return;
    }
    [self performSync:^(WCTDatabase *db) {
        NSArray <RDCharpterModel *>*all = [db getAllObjectsOfClass:RDCharpterModel.class fromTable:kCharpterTable];
        if (all.count == 0) {
            [[NSUserDefaults standardUserDefaults] setBool:YES forKey:kPrimaryIdMigratedKey];
            return;
        }
        [db runTransaction:^BOOL{
            for (RDCharpterModel *chapter in all) {
                NSString *desired = [NSString stringWithFormat:@"%@_%@", @(chapter.bookId), @(chapter.charpterId)];
                if ([chapter.primaryId isEqualToString:desired]) {
                    continue;
                }
                // 删旧主键行再插入新主键
                [db deleteObjectsFromTable:kCharpterTable where:RDCharpterModel.primaryId.is(chapter.primaryId)];
                chapter.primaryId = desired;
                [db insertOrReplaceObject:chapter into:kCharpterTable];
            }
            return YES;
        }];
        [[NSUserDefaults standardUserDefaults] setBool:YES forKey:kPrimaryIdMigratedKey];
    }];
}

@end
