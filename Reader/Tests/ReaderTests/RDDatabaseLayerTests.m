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

    RDCharpterModel *chapter = [[RDCharpterModel alloc] init];
    chapter.bookId = book.bookId;
    chapter.charpterId = 1;
    chapter.name = @"第一章";
    chapter.content = @"正文";

    NSLog(@"[DBDIAG] transaction begin");
    NSError *error = nil;
    BOOL ok = [RDLibraryTransaction commitBook:book chapters:@[chapter] touchReadTime:YES error:&error];
    NSLog(@"[DBDIAG] transaction done ok=%d error=%@", ok, error);
    XCTAssertTrue(ok, @"跨表事务提交不应卡住或失败,错误:%@", error);

    XCTAssertNotNil([RDReadRecordManager getReadRecordWithBookId:book.bookId]);
    XCTAssertTrue([RDCharpterDataManager isExsitWithBookId:book.bookId]);

    [RDCharpterDataManager deleteAllCharpterWithBookId:book.bookId];
    [RDReadRecordManager removeBookFromBookShelfWithBookId:book.bookId];
}

@end
