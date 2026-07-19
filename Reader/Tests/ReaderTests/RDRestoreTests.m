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

@end
