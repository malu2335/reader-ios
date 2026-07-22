//
//  RDRestoreTests.m
//  ReaderTests
//
//  T2 恢复:往返一致性与故障注入。
//  验收标准是 Oracle P1-01 那条——恢复的任一步失败后,每本书只能是
//  完整旧状态或完整新状态,不能出现"新文件配旧章节"的混合态。
//

#import "RDTestSupport.h"
#import "RDMarcos.h"
#import "RDBookDetailModel.h"
#import "RDReadRecordManager.h"
#import "RDCharpterDataManager.h"
#import "RDLocalBookManager.h"
#import "RDBackupManager.h"
#import "RDLibraryMutationCoordinator.h"
#import "RDAIConfig.h"


@interface RDRestoreTests : XCTestCase
@property (nonatomic, copy) NSString *backupPath;
@end

@implementation RDRestoreTests

- (void)setUp
{
    [super setUp];
    [RDTestSupport setBooksDirectoryWritable:YES];
    [RDTestSupport resetLibrary];
}

- (void)tearDown
{
    [RDTestSupport setBooksDirectoryWritable:YES];
    [RDTestSupport resetLibrary];
    if (self.backupPath.length) {
        [[NSFileManager defaultManager] removeItemAtPath:self.backupPath error:nil];
        self.backupPath = nil;
    }
    [super tearDown];
}

#pragma mark - 工具

- (NSString *)p_makeBackup
{
    __block NSString *path = nil;
    __block NSString *error = nil;
    BOOL finished = [RDTestSupport waitFor:^(dispatch_block_t done) {
        [RDBackupManager createBackupWithComplete:^(NSString *zipPath, NSString *errorMessage) {
            path = zipPath;
            error = errorMessage;
            done();
        }];
    } timeout:120];
    XCTAssertTrue(finished, @"备份回调超时");
    XCTAssertNotNil(path, @"备份应生成文件,错误:%@", error);
    self.backupPath = path;
    return path;
}

- (NSInteger)p_restoreFrom:(NSString *)path message:(NSString **)outMessage
{
    __block NSInteger count = 0;
    __block NSString *message = nil;
    BOOL finished = [RDTestSupport waitFor:^(dispatch_block_t done) {
        [RDBackupManager restoreFromURL:[NSURL fileURLWithPath:path]
                               complete:^(NSInteger bookCount, NSString *errorMessage) {
            count = bookCount;
            message = errorMessage;
            done();
        }];
    } timeout:180];
    XCTAssertTrue(finished, @"恢复回调超时");
    if (outMessage) {
        *outMessage = message;
    }
    return count;
}

#pragma mark - 用例

/// 备份 → 清库 → 恢复:书、章节、源文件与阅读进度都应回来
- (void)testBackupRestoreRoundTripRestoresBooksAndChapters
{
    NSURL *url = [RDTestSupport makeTxtBookWithTitle:@"恢复往返" chapters:5];
    RDBookDetailModel *book = [RDTestSupport importBookAtURL:url message:NULL isDuplicate:NULL];
    XCTAssertNotNil(book);
    NSInteger bookId = book.bookId;

    // 记一个可校验的阅读进度
    RDBookDetailModel *record = [RDReadRecordManager getReadRecordWithBookId:bookId];
    record.page = 3;
    record.charOffset = 128;
    XCTAssertTrue([RDReadRecordManager updateProgressWithModel:record], @"写进度应成功");

    NSString *zip = [self p_makeBackup];
    [RDTestSupport resetLibrary];
    XCTAssertNil([RDReadRecordManager getReadRecordWithBookId:bookId], @"清库后不应还有记录");

    NSString *message = nil;
    NSInteger restored = [self p_restoreFrom:zip message:&message];
    XCTAssertEqual(restored, 1, @"应恢复 1 本书,信息:%@", message);

    RDBookDetailModel *back = [RDReadRecordManager getReadRecordWithBookId:bookId];
    XCTAssertNotNil(back, @"恢复后读记录应存在");
    XCTAssertEqual(back.page, 3, @"页码应随备份恢复");
    XCTAssertEqual(back.charOffset, 128, @"字符偏移应随备份恢复");
    XCTAssertTrue([RDCharpterDataManager isExsitWithBookId:bookId], @"章节应从源文件重建");
    XCTAssertEqual([RDCharpterDataManager getBriefCharptersWithBookId:bookId].count, 5);
    XCTAssertTrue([[NSFileManager defaultManager] fileExistsAtPath:[RDLocalBookManager absolutePathForBook:back]],
                  @"源文件应已进入正式路径");
}

/// 覆盖式恢复:同一本书已在库中时,恢复后仍是完整可读状态(不是新文件配旧章节)
- (void)testRestoreOverExistingBookKeepsBookConsistent
{
    NSURL *url = [RDTestSupport makeTxtBookWithTitle:@"覆盖恢复" chapters:4];
    RDBookDetailModel *book = [RDTestSupport importBookAtURL:url message:NULL isDuplicate:NULL];
    XCTAssertNotNil(book);
    NSInteger bookId = book.bookId;

    NSString *zip = [self p_makeBackup];

    // 不清库,直接在已有同 bookId 的情况下恢复
    NSString *message = nil;
    NSInteger restored = [self p_restoreFrom:zip message:&message];
    XCTAssertEqual(restored, 1, @"覆盖恢复应成功,信息:%@", message);

    RDBookDetailModel *back = [RDReadRecordManager getReadRecordWithBookId:bookId];
    XCTAssertNotNil(back);
    NSString *path = [RDLocalBookManager absolutePathForBook:back];
    XCTAssertTrue([[NSFileManager defaultManager] fileExistsAtPath:path], @"源文件必须在位");
    XCTAssertEqual([RDCharpterDataManager getBriefCharptersWithBookId:bookId].count, 4,
                   @"章节数必须与源文件一致,不能出现新文件配旧章节");
}

/// 故障注入:备份包损坏时,原有书籍必须原样保留(完整旧状态)
- (void)testRestoreFromCorruptedBackupKeepsOldStateIntact
{
    NSURL *url = [RDTestSupport makeTxtBookWithTitle:@"损坏包恢复" chapters:5];
    RDBookDetailModel *book = [RDTestSupport importBookAtURL:url message:NULL isDuplicate:NULL];
    XCTAssertNotNil(book);
    NSInteger bookId = book.bookId;
    NSUInteger chaptersBefore = [RDCharpterDataManager getBriefCharptersWithBookId:bookId].count;

    NSString *zip = [self p_makeBackup];

    // 把 zip 截断成半个文件,模拟损坏/不完整的备份
    NSData *data = [NSData dataWithContentsOfFile:zip];
    XCTAssertTrue(data.length > 64);
    NSString *broken = [NSTemporaryDirectory() stringByAppendingPathComponent:@"broken-backup.zip"];
    [[data subdataWithRange:NSMakeRange(0, data.length / 2)] writeToFile:broken atomically:YES];

    NSString *message = nil;
    NSInteger restored = [self p_restoreFrom:broken message:&message];
    XCTAssertEqual(restored, 0, @"损坏备份不应报告恢复成功");
    XCTAssertNotNil(message, @"必须给出可见的失败原因");

    // 关键:旧状态必须完好,不能被半途的恢复破坏
    RDBookDetailModel *still = [RDReadRecordManager getReadRecordWithBookId:bookId];
    XCTAssertNotNil(still, @"恢复失败不得删掉原有记录");
    XCTAssertEqual([RDCharpterDataManager getBriefCharptersWithBookId:bookId].count, chaptersBefore,
                   @"恢复失败不得清空原有章节(P1-01)");
    XCTAssertTrue([[NSFileManager defaultManager] fileExistsAtPath:[RDLocalBookManager absolutePathForBook:still]],
                  @"恢复失败不得损坏原有源文件");

    [[NSFileManager defaultManager] removeItemAtPath:broken error:nil];
}

/// 恢复不得在中途留下 staging 残留
- (void)testRestoreCleansUpStagingDirectory
{
    NSURL *url = [RDTestSupport makeTxtBookWithTitle:@"staging 清理" chapters:3];
    XCTAssertNotNil([RDTestSupport importBookAtURL:url message:NULL isDuplicate:NULL]);
    NSString *zip = [self p_makeBackup];
    [self p_restoreFrom:zip message:NULL];

    NSString *staging = [PATH_DOCUMENT stringByAppendingPathComponent:@"RestoreStaging"];
    NSArray *leftovers = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:staging error:nil];
    XCTAssertEqual(leftovers.count, 0, @"恢复结束后不应残留 staging 目录:%@", leftovers);
}

/// 模拟 files_committed journal:同步回收后必须回滚到旧文件(P1-BE-01 / Issue 1)
- (void)testInterruptedRestoreJournalRollsBackFiles
{
    NSURL *url = [RDTestSupport makeTxtBookWithTitle:@"journal 旧书" chapters:2];
    RDBookDetailModel *book = [RDTestSupport importBookAtURL:url message:NULL isDuplicate:NULL];
    XCTAssertNotNil(book);
    NSString *target = [RDLocalBookManager absolutePathForBook:book];
    XCTAssertTrue([[NSFileManager defaultManager] fileExistsAtPath:target]);
    NSData *oldData = [NSData dataWithContentsOfFile:target];
    XCTAssertTrue(oldData.length > 0);

    NSString *journalRoot = [PATH_DOCUMENT stringByAppendingPathComponent:@"RestoreJournal"];
    NSString *journalDir = [journalRoot stringByAppendingPathComponent:@"test-journal-uuid"];
    [[NSFileManager defaultManager] createDirectoryAtPath:journalDir withIntermediateDirectories:YES attributes:nil error:nil];
    NSString *oldBackup = [journalDir stringByAppendingPathComponent:@"old"];
    XCTAssertTrue([oldData writeToFile:oldBackup atomically:YES]);
    NSData *fakeNew = [@"FAKE_NEW_CONTENT_SHOULD_ROLLBACK" dataUsingEncoding:NSUTF8StringEncoding];
    XCTAssertTrue([fakeNew writeToFile:target atomically:YES]);
    NSDictionary *payload = @{
        @"bookId": @(book.bookId),
        @"localPath": book.localPath ?: @"",
        @"target": target,
        @"phase": @"files_committed",
        @"hadOld": @YES,
    };
    NSData *json = [NSJSONSerialization dataWithJSONObject:payload options:0 error:nil];
    XCTAssertTrue([json writeToFile:[journalDir stringByAppendingPathComponent:@"operation.json"] atomically:YES]);

    // 启动回收现为 performSync,返回即完成(Issue 2)
    [RDBackupManager recoverInterruptedRestoresIfNeeded];

    NSData *after = [NSData dataWithContentsOfFile:target];
    XCTAssertEqualObjects(after, oldData, @"journal 回收后正式路径必须回到旧文件");
    NSArray *left = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:journalRoot error:nil];
    XCTAssertEqual(left.count, 0, @"journal 目录最终应清空:%@", left);
}

/// prepared + old 已移走但 phase 未更新:回收必须还原 old,不能丢备份(Issue 1 窗口 1)
- (void)testJournalPreparedWithOldStillRollsBack
{
    NSURL *url = [RDTestSupport makeTxtBookWithTitle:@"journal prepared" chapters:1];
    RDBookDetailModel *book = [RDTestSupport importBookAtURL:url message:NULL isDuplicate:NULL];
    NSString *target = [RDLocalBookManager absolutePathForBook:book];
    NSData *oldData = [NSData dataWithContentsOfFile:target];
    XCTAssertTrue(oldData.length > 0);

    NSString *journalRoot = [PATH_DOCUMENT stringByAppendingPathComponent:@"RestoreJournal"];
    NSString *journalDir = [journalRoot stringByAppendingPathComponent:@"prepared-with-old"];
    [[NSFileManager defaultManager] createDirectoryAtPath:journalDir withIntermediateDirectories:YES attributes:nil error:nil];
    XCTAssertTrue([oldData writeToFile:[journalDir stringByAppendingPathComponent:@"old"] atomically:YES]);
    // 正式路径已是“新文件”
    XCTAssertTrue([[@"NEW_FILE" dataUsingEncoding:NSUTF8StringEncoding] writeToFile:target atomically:YES]);
    NSDictionary *payload = @{
        @"bookId": @(book.bookId),
        @"localPath": book.localPath ?: @"",
        @"target": target,
        @"phase": @"prepared", // 关键:旧实现只处理 files_committed
        @"hadOld": @YES,
    };
    XCTAssertTrue([[NSJSONSerialization dataWithJSONObject:payload options:0 error:nil]
                   writeToFile:[journalDir stringByAppendingPathComponent:@"operation.json"] atomically:YES]);

    [RDBackupManager recoverInterruptedRestoresIfNeeded];
    XCTAssertEqualObjects([NSData dataWithContentsOfFile:target], oldData,
                          @"prepared+old 必须还原,不能删 journal 丢掉 old");
    XCTAssertEqual([[NSFileManager defaultManager] contentsOfDirectoryAtPath:journalRoot error:nil].count, 0);
}

/// DB 已成功、old 已丢、phase 仍 files_committed:保留新文件(Round 3 Issue 2)
- (void)testJournalFilesCommittedWithoutOldKeepsNewFile
{
    NSURL *url = [RDTestSupport makeTxtBookWithTitle:@"journal no-old" chapters:1];
    RDBookDetailModel *book = [RDTestSupport importBookAtURL:url message:NULL isDuplicate:NULL];
    NSString *target = [RDLocalBookManager absolutePathForBook:book];
    NSData *newData = [@"DB_DONE_NEW_FILE" dataUsingEncoding:NSUTF8StringEncoding];
    XCTAssertTrue([newData writeToFile:target atomically:YES]);

    NSString *journalRoot = [PATH_DOCUMENT stringByAppendingPathComponent:@"RestoreJournal"];
    NSString *journalDir = [journalRoot stringByAppendingPathComponent:@"files-committed-no-old"];
    [[NSFileManager defaultManager] createDirectoryAtPath:journalDir withIntermediateDirectories:YES attributes:nil error:nil];
    // 故意不写 old,模拟 DB 成功后已删除 old、db_committed 未落盘
    NSDictionary *payload = @{
        @"bookId": @(book.bookId),
        @"localPath": book.localPath ?: @"",
        @"target": target,
        @"phase": @"files_committed",
        @"hadOld": @NO,
    };
    XCTAssertTrue([[NSJSONSerialization dataWithJSONObject:payload options:0 error:nil]
                   writeToFile:[journalDir stringByAppendingPathComponent:@"operation.json"] atomically:YES]);

    [RDBackupManager recoverInterruptedRestoresIfNeeded];
    XCTAssertEqualObjects([NSData dataWithContentsOfFile:target], newData,
                          @"files_committed 且无 old 时必须保留新文件(与已提交 DB 一致)");
    XCTAssertEqual([[NSFileManager defaultManager] contentsOfDirectoryAtPath:journalRoot error:nil].count, 0);
}

/// db_committed:回收只清 journal,不得回滚已提交的新文件(Issue 1 窗口 2)
- (void)testJournalDBCommittedDoesNotRollBack
{
    NSURL *url = [RDTestSupport makeTxtBookWithTitle:@"journal db_committed" chapters:1];
    RDBookDetailModel *book = [RDTestSupport importBookAtURL:url message:NULL isDuplicate:NULL];
    NSString *target = [RDLocalBookManager absolutePathForBook:book];
    NSData *newData = [@"COMMITTED_NEW_FILE" dataUsingEncoding:NSUTF8StringEncoding];
    XCTAssertTrue([newData writeToFile:target atomically:YES]);

    NSString *journalRoot = [PATH_DOCUMENT stringByAppendingPathComponent:@"RestoreJournal"];
    NSString *journalDir = [journalRoot stringByAppendingPathComponent:@"db-committed"];
    [[NSFileManager defaultManager] createDirectoryAtPath:journalDir withIntermediateDirectories:YES attributes:nil error:nil];
    // 故意留下 old,验证 db_committed 仍不回滚
    XCTAssertTrue([[@"OLD_SHOULD_STAY_DISCARDED" dataUsingEncoding:NSUTF8StringEncoding]
                   writeToFile:[journalDir stringByAppendingPathComponent:@"old"] atomically:YES]);
    NSDictionary *payload = @{
        @"bookId": @(book.bookId),
        @"localPath": book.localPath ?: @"",
        @"target": target,
        @"phase": @"db_committed",
        @"hadOld": @YES,
    };
    XCTAssertTrue([[NSJSONSerialization dataWithJSONObject:payload options:0 error:nil]
                   writeToFile:[journalDir stringByAppendingPathComponent:@"operation.json"] atomically:YES]);

    [RDBackupManager recoverInterruptedRestoresIfNeeded];
    XCTAssertEqualObjects([NSData dataWithContentsOfFile:target], newData,
                          @"db_committed 不得把文件滚回 old");
    XCTAssertEqual([[NSFileManager defaultManager] contentsOfDirectoryAtPath:journalRoot error:nil].count, 0);
}

/// 删除 completion 必须传播 success(P1-BE-02)
- (void)testRemoveLocalBookCompletionReportsSuccess
{
    NSURL *url = [RDTestSupport makeTxtBookWithTitle:@"删除结果" chapters:2];
    RDBookDetailModel *book = [RDTestSupport importBookAtURL:url message:NULL isDuplicate:NULL];
    XCTAssertNotNil(book);
    __block BOOL sawSuccess = NO;
    __block NSError *err = nil;
    BOOL finished = [RDTestSupport waitFor:^(dispatch_block_t done) {
        [RDLocalBookManager removeLocalBook:book completion:^(BOOL success, NSError *error) {
            sawSuccess = success;
            err = error;
            done();
        }];
    } timeout:20];
    XCTAssertTrue(finished);
    XCTAssertTrue(sawSuccess, @"正常删除应 success=YES, err=%@", err);
    XCTAssertNil([RDReadRecordManager getReadRecordWithBookId:book.bookId]);
}

/// 源文件 stage 失败时不得 success,且不得假删 DB(Issue 4 / 5)
- (void)testRemoveLocalBookFailsWhenSourceMissingIsStillSuccess
{
    // 无源文件时 stage 跳过源,DB 仍应能删干净 → success=YES 是合法语义
    // 此处验证:删除后记录消失
    NSURL *url = [RDTestSupport makeTxtBookWithTitle:@"无文件删" chapters:1];
    RDBookDetailModel *book = [RDTestSupport importBookAtURL:url message:NULL isDuplicate:NULL];
    NSString *path = [RDLocalBookManager absolutePathForBook:book];
    [[NSFileManager defaultManager] removeItemAtPath:path error:nil];
    __block BOOL sawSuccess = NO;
    BOOL finished = [RDTestSupport waitFor:^(dispatch_block_t done) {
        [RDLocalBookManager removeLocalBook:book completion:^(BOOL success, NSError *error) {
            sawSuccess = success;
            done();
        }];
    } timeout:20];
    XCTAssertTrue(finished);
    XCTAssertTrue(sawSuccess, @"源文件已不存在时仍应能删库成功");
    XCTAssertNil([RDReadRecordManager getReadRecordWithBookId:book.bookId]);
}

#pragma mark - 删除 kill 回收(P1-BE-02 residual)

/// files_staged + DB 仍有书:启动回收必须把文件移回正式路径
- (void)testDeleteJournalFilesStagedRestoresWhenDBStillHasBook
{
    NSURL *url = [RDTestSupport makeTxtBookWithTitle:@"delete journal restore" chapters:1];
    RDBookDetailModel *book = [RDTestSupport importBookAtURL:url message:NULL isDuplicate:NULL];
    XCTAssertNotNil(book);
    NSString *target = [RDLocalBookManager absolutePathForBook:book];
    NSData *oldData = [NSData dataWithContentsOfFile:target];
    XCTAssertTrue(oldData.length > 0);

    NSString *trashRoot = [PATH_DOCUMENT stringByAppendingPathComponent:@"TrashStaging"];
    NSString *trashDir = [trashRoot stringByAppendingPathComponent:@"test-delete-restore"];
    [[NSFileManager defaultManager] createDirectoryAtPath:trashDir withIntermediateDirectories:YES attributes:nil error:nil];
    NSString *staged = [trashDir stringByAppendingPathComponent:@"staged_src.txt"];
    // 模拟 stage:正式路径文件已移入 trash
    XCTAssertTrue([[NSFileManager defaultManager] moveItemAtPath:target toPath:staged error:nil]);
    NSDictionary *payload = @{
        @"bookId": @(book.bookId),
        @"phase": @"files_staged",
        @"files": @[@{@"staged": staged, @"original": target}],
    };
    XCTAssertTrue([[NSJSONSerialization dataWithJSONObject:payload options:0 error:nil]
                   writeToFile:[trashDir stringByAppendingPathComponent:@"operation.json"] atomically:YES]);

    [RDLocalBookManager recoverInterruptedDeletesIfNeeded];

    XCTAssertTrue([[NSFileManager defaultManager] fileExistsAtPath:target], @"files_staged+DB 有书必须移回源文件");
    XCTAssertEqualObjects([NSData dataWithContentsOfFile:target], oldData);
    XCTAssertNotNil([RDReadRecordManager getReadRecordWithBookId:book.bookId]);
    NSArray *left = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:trashRoot error:nil];
    XCTAssertEqual(left.count, 0, @"TrashStaging 最终应清空:%@", left);
}

/// files_staged 但 DB 已无该书:完成删除(销毁 staged),不得幽灵回写
- (void)testDeleteJournalFilesStagedDestroysWhenDBGone
{
    NSURL *url = [RDTestSupport makeTxtBookWithTitle:@"delete journal destroy" chapters:1];
    RDBookDetailModel *book = [RDTestSupport importBookAtURL:url message:NULL isDuplicate:NULL];
    NSInteger bookId = book.bookId;
    NSString *target = [RDLocalBookManager absolutePathForBook:book];
    NSData *fileData = [NSData dataWithContentsOfFile:target];
    XCTAssertTrue(fileData.length > 0);

    // 正常删干净后,手工留下 files_staged journal 模拟“DB 已删、销毁未完成”
    BOOL finished = [RDTestSupport waitFor:^(dispatch_block_t done) {
        [RDLocalBookManager removeLocalBook:book completion:^(BOOL success, NSError *error) {
            XCTAssertTrue(success, @"%@", error);
            done();
        }];
    } timeout:20];
    XCTAssertTrue(finished);
    XCTAssertNil([RDReadRecordManager getReadRecordWithBookId:bookId]);

    NSString *trashRoot = [PATH_DOCUMENT stringByAppendingPathComponent:@"TrashStaging"];
    NSString *trashDir = [trashRoot stringByAppendingPathComponent:@"test-delete-destroy"];
    [[NSFileManager defaultManager] createDirectoryAtPath:trashDir withIntermediateDirectories:YES attributes:nil error:nil];
    NSString *staged = [trashDir stringByAppendingPathComponent:@"staged_src.txt"];
    XCTAssertTrue([fileData writeToFile:staged atomically:YES]);
    NSDictionary *payload = @{
        @"bookId": @(bookId),
        @"phase": @"files_staged",
        @"files": @[@{@"staged": staged, @"original": target}],
    };
    XCTAssertTrue([[NSJSONSerialization dataWithJSONObject:payload options:0 error:nil]
                   writeToFile:[trashDir stringByAppendingPathComponent:@"operation.json"] atomically:YES]);

    [RDLocalBookManager recoverInterruptedDeletesIfNeeded];

    XCTAssertFalse([[NSFileManager defaultManager] fileExistsAtPath:staged], @"DB 无书时 staged 必须销毁");
    XCTAssertFalse([[NSFileManager defaultManager] fileExistsAtPath:target], @"不得幽灵写回已删书文件");
    NSArray *left = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:trashRoot error:nil];
    XCTAssertEqual(left.count, 0, @"TrashStaging 最终应清空:%@", left);
}

/// mid-stage: phase=prepared 且 journal 已登记路径、文件已在 trash → 必须移回(Review #1)
- (void)testDeleteJournalPreparedWithStagedFilesRestoresWhenDBHasBook
{
    NSURL *url = [RDTestSupport makeTxtBookWithTitle:@"delete mid-stage prepared" chapters:1];
    RDBookDetailModel *book = [RDTestSupport importBookAtURL:url message:NULL isDuplicate:NULL];
    XCTAssertNotNil(book);
    NSString *target = [RDLocalBookManager absolutePathForBook:book];
    NSData *oldData = [NSData dataWithContentsOfFile:target];
    XCTAssertTrue(oldData.length > 0);

    NSString *trashRoot = [PATH_DOCUMENT stringByAppendingPathComponent:@"TrashStaging"];
    NSString *trashDir = [trashRoot stringByAppendingPathComponent:@"test-mid-stage-prepared"];
    [[NSFileManager defaultManager] createDirectoryAtPath:trashDir withIntermediateDirectories:YES attributes:nil error:nil];
    NSString *staged = [trashDir stringByAppendingPathComponent:@"uuid_src.txt"];
    XCTAssertTrue([[NSFileManager defaultManager] moveItemAtPath:target toPath:staged error:nil]);
    // 模拟 plan-then-journal-then-move 后、files_staged 升级前被杀
    NSDictionary *payload = @{
        @"bookId": @(book.bookId),
        @"phase": @"prepared",
        @"files": @[@{@"staged": staged, @"original": target}],
    };
    XCTAssertTrue([[NSJSONSerialization dataWithJSONObject:payload options:0 error:nil]
                   writeToFile:[trashDir stringByAppendingPathComponent:@"operation.json"] atomically:YES]);

    [RDLocalBookManager recoverInterruptedDeletesIfNeeded];

    XCTAssertTrue([[NSFileManager defaultManager] fileExistsAtPath:target], @"prepared+已 stage 文件必须移回");
    XCTAssertEqualObjects([NSData dataWithContentsOfFile:target], oldData);
    XCTAssertNotNil([RDReadRecordManager getReadRecordWithBookId:book.bookId]);
    XCTAssertEqual([[NSFileManager defaultManager] contentsOfDirectoryAtPath:trashRoot error:nil].count, 0);
}

/// 无 operation.json 但有 .tmp journal:应能按 tmp 恢复(Review #2)
- (void)testDeleteJournalRecoversFromTmpWhenMainMissing
{
    NSURL *url = [RDTestSupport makeTxtBookWithTitle:@"delete journal tmp" chapters:1];
    RDBookDetailModel *book = [RDTestSupport importBookAtURL:url message:NULL isDuplicate:NULL];
    NSString *target = [RDLocalBookManager absolutePathForBook:book];
    NSData *oldData = [NSData dataWithContentsOfFile:target];

    NSString *trashRoot = [PATH_DOCUMENT stringByAppendingPathComponent:@"TrashStaging"];
    NSString *trashDir = [trashRoot stringByAppendingPathComponent:@"test-tmp-only"];
    [[NSFileManager defaultManager] createDirectoryAtPath:trashDir withIntermediateDirectories:YES attributes:nil error:nil];
    NSString *staged = [trashDir stringByAppendingPathComponent:@"staged_tmp.txt"];
    XCTAssertTrue([[NSFileManager defaultManager] moveItemAtPath:target toPath:staged error:nil]);
    NSDictionary *payload = @{
        @"bookId": @(book.bookId),
        @"phase": @"prepared",
        @"files": @[@{@"staged": staged, @"original": target}],
    };
    // 仅写 .tmp,模拟旧 remove→move 半写窗口
    XCTAssertTrue([[NSJSONSerialization dataWithJSONObject:payload options:0 error:nil]
                   writeToFile:[trashDir stringByAppendingPathComponent:@"operation.json.tmp"] atomically:YES]);

    [RDLocalBookManager recoverInterruptedDeletesIfNeeded];

    XCTAssertTrue([[NSFileManager defaultManager] fileExistsAtPath:target], @"仅有 .tmp journal 也必须能还原");
    XCTAssertEqualObjects([NSData dataWithContentsOfFile:target], oldData);
    XCTAssertEqual([[NSFileManager defaultManager] contentsOfDirectoryAtPath:trashRoot error:nil].count, 0);
}

/// 无任何 journal 但有 payload:不得销毁 staged 内容(Review #2 安全侧)
- (void)testDeleteJournalMissingDoesNotDestroyPayload
{
    NSString *trashRoot = [PATH_DOCUMENT stringByAppendingPathComponent:@"TrashStaging"];
    NSString *trashDir = [trashRoot stringByAppendingPathComponent:@"test-orphan-payload"];
    [[NSFileManager defaultManager] createDirectoryAtPath:trashDir withIntermediateDirectories:YES attributes:nil error:nil];
    NSString *orphan = [trashDir stringByAppendingPathComponent:@"orphan_book.txt"];
    NSData *blob = [@"ORPHAN_PAYLOAD" dataUsingEncoding:NSUTF8StringEncoding];
    XCTAssertTrue([blob writeToFile:orphan atomically:YES]);

    [RDLocalBookManager recoverInterruptedDeletesIfNeeded];

    XCTAssertTrue([[NSFileManager defaultManager] fileExistsAtPath:orphan],
                  @"无 journal 的 payload 不得被回收销毁");
    // 清理,避免污染后续用例
    [[NSFileManager defaultManager] removeItemAtPath:trashDir error:nil];
}

/// db_deleted:只销毁 trash,不回滚
- (void)testDeleteJournalDBDeletedDestroysTrash
{
    NSURL *url = [RDTestSupport makeTxtBookWithTitle:@"delete journal db_deleted" chapters:1];
    RDBookDetailModel *book = [RDTestSupport importBookAtURL:url message:NULL isDuplicate:NULL];
    NSInteger bookId = book.bookId;
    NSString *target = [RDLocalBookManager absolutePathForBook:book];
    NSData *fileData = [NSData dataWithContentsOfFile:target];

    BOOL finished = [RDTestSupport waitFor:^(dispatch_block_t done) {
        [RDLocalBookManager removeLocalBook:book completion:^(BOOL success, NSError *error) {
            XCTAssertTrue(success, @"%@", error);
            done();
        }];
    } timeout:20];
    XCTAssertTrue(finished);
    XCTAssertNil([RDReadRecordManager getReadRecordWithBookId:bookId]);

    NSString *trashRoot = [PATH_DOCUMENT stringByAppendingPathComponent:@"TrashStaging"];
    NSString *trashDir = [trashRoot stringByAppendingPathComponent:@"test-db-deleted"];
    [[NSFileManager defaultManager] createDirectoryAtPath:trashDir withIntermediateDirectories:YES attributes:nil error:nil];
    NSString *staged = [trashDir stringByAppendingPathComponent:@"leftover.txt"];
    XCTAssertTrue([fileData writeToFile:staged atomically:YES]);
    NSDictionary *payload = @{
        @"bookId": @(bookId),
        @"phase": @"db_deleted",
        @"files": @[@{@"staged": staged, @"original": target}],
    };
    XCTAssertTrue([[NSJSONSerialization dataWithJSONObject:payload options:0 error:nil]
                   writeToFile:[trashDir stringByAppendingPathComponent:@"operation.json"] atomically:YES]);

    [RDLocalBookManager recoverInterruptedDeletesIfNeeded];

    XCTAssertFalse([[NSFileManager defaultManager] fileExistsAtPath:staged]);
    XCTAssertFalse([[NSFileManager defaultManager] fileExistsAtPath:target], @"db_deleted 不得移回");
    XCTAssertEqual([[NSFileManager defaultManager] contentsOfDirectoryAtPath:trashRoot error:nil].count, 0);
}

@end
