//
//  RDImportTransactionTests.m
//  ReaderTests
//
//  T1 导入事务 / T5 删除与清空。
//  这两组正是前几轮只有静态断言、没有运行时验证的部分。
//

#import "RDTestSupport.h"
#import "RDBookDetailModel.h"
#import "RDReadRecordManager.h"
#import "RDCharpterDataManager.h"
#import "RDBookmarkManager.h"
#import "RDBookmarkModel.h"
#import "RDLocalBookManager.h"


@interface RDImportTransactionTests : XCTestCase
@end

@implementation RDImportTransactionTests

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
    [super tearDown];
}

#pragma mark - T1 导入事务

/// 导入成功后:读记录行、章节、源文件三者必须同时存在
- (void)testImportCommitsRecordChaptersAndFileTogether
{
    NSURL *url = [RDTestSupport makeTxtBookWithTitle:@"导入事务" chapters:5];
    NSString *message = nil;
    RDBookDetailModel *book = [RDTestSupport importBookAtURL:url message:&message isDuplicate:NULL];

    XCTAssertNotNil(book, @"导入应成功,错误:%@", message);
    XCTAssertNil(message);
    XCTAssertTrue(book.bookId < 0, @"本地书 bookId 必须为负");

    RDBookDetailModel *record = [RDReadRecordManager getReadRecordWithBookId:book.bookId];
    XCTAssertNotNil(record, @"读记录行必须存在");

    XCTAssertTrue([RDCharpterDataManager isExsitWithBookId:book.bookId], @"章节必须已入库");
    NSArray *chapters = [RDCharpterDataManager getBriefCharptersWithBookId:book.bookId];
    XCTAssertEqual(chapters.count, 5, @"章节数应与解析结果一致");

    NSString *path = [RDLocalBookManager absolutePathForBook:record];
    XCTAssertTrue([[NSFileManager defaultManager] fileExistsAtPath:path], @"源文件必须已落盘");
}

/// 同一本书重复导入:不新增记录,且被明确标记为重复
- (void)testReimportSameBookIsReportedAsDuplicate
{
    NSURL *url = [RDTestSupport makeTxtBookWithTitle:@"重复导入" chapters:3];
    RDBookDetailModel *first = [RDTestSupport importBookAtURL:url message:NULL isDuplicate:NULL];
    XCTAssertNotNil(first);
    NSInteger countAfterFirst = [RDReadRecordManager countOnBookshelf];

    BOOL duplicate = NO;
    RDBookDetailModel *second = [RDTestSupport importBookAtURL:url message:NULL isDuplicate:&duplicate];
    XCTAssertTrue(duplicate, @"同内容再次导入应判定为重复");
    XCTAssertEqual(second.bookId, first.bookId, @"bookId 由内容派生,必须稳定");
    XCTAssertEqual([RDReadRecordManager countOnBookshelf], countAfterFirst, @"重复导入不得新增书架条目");
}

/// 故障注入:源文件无法落盘时,必须报失败,且不留下任何半成品
- (void)testImportFailureLeavesNoPartialState
{
    NSURL *url = [RDTestSupport makeTxtBookWithTitle:@"落盘失败" chapters:4];
    NSInteger before = [RDReadRecordManager countOnBookshelf];

    XCTAssertTrue([RDTestSupport setBooksDirectoryWritable:NO], @"需要能改目录权限才能做本用例");
    NSString *message = nil;
    RDBookDetailModel *book = [RDTestSupport importBookAtURL:url message:&message isDuplicate:NULL];
    [RDTestSupport setBooksDirectoryWritable:YES];

    XCTAssertNil(book, @"落盘失败时不得返回成功");
    XCTAssertNotNil(message, @"必须给出可见的失败原因");
    XCTAssertEqual([RDReadRecordManager countOnBookshelf], before, @"失败的导入不得留下书架条目");
}

#pragma mark - T5 删除 / 清空

/// 删除的 completion 触发时,读记录、章节、书签必须都已清干净
- (void)testRemoveCompletionMeansEverythingIsGone
{
    NSURL *url = [RDTestSupport makeTxtBookWithTitle:@"删除完整性" chapters:6];
    RDBookDetailModel *book = [RDTestSupport importBookAtURL:url message:NULL isDuplicate:NULL];
    XCTAssertNotNil(book);
    NSInteger bookId = book.bookId;

    RDBookmarkModel *bookmark = [[RDBookmarkModel alloc] init];
    bookmark.bookmarkId = [NSString stringWithFormat:@"%@_bm", @(bookId)];
    bookmark.bookId = bookId;
    bookmark.charpterId = 1;
    bookmark.createTime = [NSDate date].timeIntervalSince1970;
    [RDBookmarkManager insertOrReplaceBookmark:bookmark];
    XCTAssertEqual([RDBookmarkManager countForBookId:bookId], 1);

    RDBookDetailModel *record = [RDReadRecordManager getReadRecordWithBookId:bookId];
    NSString *path = [RDLocalBookManager absolutePathForBook:record];

    __block BOOL completed = NO;
    BOOL finished = [RDTestSupport waitFor:^(dispatch_block_t done) {
        [RDLocalBookManager removeLocalBook:record completion:^{
            completed = YES;
            done();
        }];
    } timeout:30];
    XCTAssertTrue(finished, @"删除 completion 必须触发");
    XCTAssertTrue(completed);

    // completion 的契约是"所有文件与表都清理完成",此刻立刻查必须已经是干净的
    XCTAssertNil([RDReadRecordManager getReadRecordWithBookId:bookId], @"读记录应已删除");
    XCTAssertFalse([RDCharpterDataManager isExsitWithBookId:bookId], @"章节应已删除(P2-17)");
    XCTAssertEqual([RDBookmarkManager countForBookId:bookId], 0, @"书签应已删除");
    XCTAssertFalse([[NSFileManager defaultManager] fileExistsAtPath:path], @"源文件应已删除");
}

/// 删除后立刻重导:章节不能被迟到的删除清空(曾经的竞态)
- (void)testDeleteThenReimportKeepsNewChapters
{
    for (NSInteger round = 0; round < 5; round++) {
        NSURL *url = [RDTestSupport makeTxtBookWithTitle:@"删后重导" chapters:4];
        NSString *importError = nil;
        RDBookDetailModel *book = [RDTestSupport importBookAtURL:url message:&importError isDuplicate:NULL];
        XCTAssertNotNil(book, @"第 %ld 轮导入应成功,错误:%@", (long)round, importError);

        RDBookDetailModel *record = [RDReadRecordManager getReadRecordWithBookId:book.bookId];
        [RDLocalBookManager removeLocalBook:record];

        // 不等删除收尾就立刻重导,复现"迟到的章节删除跑到新导入之后"
        RDBookDetailModel *again = [RDTestSupport importBookAtURL:url message:NULL isDuplicate:NULL];
        XCTAssertNotNil(again, @"第 %ld 轮重导应成功", (long)round);
        [RDTestSupport waitForLibraryQueue];

        XCTAssertTrue([RDCharpterDataManager isExsitWithBookId:again.bookId],
                      @"第 %ld 轮:重导后的章节不得被迟到的删除清空", (long)round);

        RDBookDetailModel *cleanup = [RDReadRecordManager getReadRecordWithBookId:again.bookId];
        [RDLocalBookManager removeLocalBook:cleanup];
        [RDTestSupport waitForLibraryQueue];
    }
}

@end
