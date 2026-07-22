//
//  RDDatabaseLayerTests.m
//  ReaderTests
//
//  数据库层最小用例:先证明 performSync / performTransactionSync 本身不卡,
//  再谈上层链路。Phase B 引入的事务封装是整条导入/恢复链路的地基。
//

#import "RDTestSupport.h"
#import "RDBookDetailModel.h"
#import "RDReadRecordManager.h"
#import "RDCharpterDataManager.h"
#import "RDCharpterModel.h"
#import "RDLibraryTransaction.h"
#import "RDHistoryRecordManager.h"

@interface RDDatabaseLayerTests : XCTestCase
@end

@implementation RDDatabaseLayerTests

/// 最基础的一步:同步读一次数据库
- (void)testA_SyncReadDoesNotBlock
{
    NSLog(@"[DBDIAG] sync read begin");
    RDBookDetailModel *record = [RDReadRecordManager getReadRecordWithBookId:-424242];
    NSLog(@"[DBDIAG] sync read done record=%@", record);
    XCTAssertNil(record);
}

/// 单表写
- (void)testB_SingleTableWriteDoesNotBlock
{
    NSLog(@"[DBDIAG] single write begin");
    BOOL ok = [RDCharpterDataManager deleteAllCharpterWithBookId:-424242];
    NSLog(@"[DBDIAG] single write done ok=%d", ok);
    XCTAssertTrue(ok);
}

/// Phase B 的跨表事务:这是导入/恢复共用的提交点
- (void)testC_CrossTableTransactionDoesNotBlock
{
    RDBookDetailModel *book = [[RDBookDetailModel alloc] init];
    book.bookId = -424243;
    book.title = @"事务用例";
    book.author = @"测试";
    book.localPath = @"txn.txt";
    book.fileType = @"txt";
    book.onBookshelf = YES;

    // 必须用**多章**。WCDB 的批量插入只在 count > 1 时才走 runEmbeddedTransaction,
    // 单章会绕开那条路径 —— 早先这条用例只塞 1 章,于是漏掉了真机上的事务自死锁。
    NSMutableArray<RDCharpterModel *> *chapters = [NSMutableArray array];
    for (NSInteger i = 1; i <= 8; i++) {
        RDCharpterModel *chapter = [[RDCharpterModel alloc] init];
        chapter.bookId = book.bookId;
        chapter.charpterId = i;
        chapter.name = [NSString stringWithFormat:@"第%ld章", (long)i];
        chapter.content = [NSString stringWithFormat:@"第%ld章正文", (long)i];
        [chapters addObject:chapter];
    }

    NSLog(@"[DBDIAG] transaction begin");
    NSError *error = nil;
    BOOL ok = [RDLibraryTransaction commitBook:book chapters:chapters touchReadTime:YES error:&error];
    NSLog(@"[DBDIAG] transaction done ok=%d error=%@", ok, error);
    XCTAssertTrue(ok, @"跨表事务提交不应卡住或失败,错误:%@", error);

    XCTAssertNotNil([RDReadRecordManager getReadRecordWithBookId:book.bookId]);
    XCTAssertEqual([RDCharpterDataManager getBriefCharptersWithBookId:book.bookId].count, 8,
                   @"8 章必须全部写入同一个事务");

    [RDCharpterDataManager deleteAllCharpterWithBookId:book.bookId];
    [RDReadRecordManager removeBookFromBookShelfWithBookId:book.bookId];
}

/// history 插入/删除返回 BOOL,调用方可感知失败(P2-DB-03)
- (void)testHistoryInsertDeleteReturnBOOL
{
    RDBookDetailModel *row = [[RDBookDetailModel alloc] init];
    row.bookId = -909001;
    row.title = @"history BOOL";
    row.onBookshelf = NO;
    row.readTime = [NSDate date].timeIntervalSince1970;

    XCTAssertTrue([RDHistoryRecordManager insertOrReplaceModel:row], @"history 插入应成功");
    XCTAssertGreaterThanOrEqual([RDHistoryRecordManager getHisoryCount], 1);
    XCTAssertTrue([RDHistoryRecordManager deleteHistoryWithBookId:row.bookId], @"history 按书删除应成功");
    XCTAssertFalse([RDHistoryRecordManager insertOrReplaceModel:nil], @"空 model 应返回 NO");
    XCTAssertFalse([RDHistoryRecordManager deleteHistoryWithBookId:0], @"bookId=0 应返回 NO");
}

/// 进度写失败重试后成功路径(正常 DB 至少一次成功)
- (void)testProgressUpdateReturnsBOOL
{
    RDBookDetailModel *book = [[RDBookDetailModel alloc] init];
    book.bookId = -909002;
    book.title = @"progress BOOL";
    book.localPath = @"progress.txt";
    book.fileType = @"txt";
    book.onBookshelf = YES;
    book.page = 0;
    NSError *error = nil;
    XCTAssertTrue([RDLibraryTransaction commitBook:book chapters:@[] touchReadTime:YES error:&error], @"%@", error);
    book.page = 3;
    book.charOffset = 12;
    XCTAssertTrue([RDReadRecordManager updateProgressWithModel:book], @"进度更新应返回 YES");
    RDBookDetailModel *back = [RDReadRecordManager getReadRecordWithBookId:book.bookId];
    XCTAssertEqual(back.page, 3);
    [RDReadRecordManager removeBookFromBookShelfWithBookId:book.bookId];
}

@end
