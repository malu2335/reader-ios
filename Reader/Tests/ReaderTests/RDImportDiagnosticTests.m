//
//  RDImportDiagnosticTests.m
//  ReaderTests
//
//  临时诊断:逐步定位导入链路的阻塞点。定位完成后可删。
//

#import "RDTestSupport.h"
#import "RDBookDetailModel.h"
#import "RDLocalBookManager.h"
#import "RDReadRecordManager.h"
#import "RDCharpterDataManager.h"
#import "RDTxtBookParser.h"
#import "RDLocalBookParseResult.h"
#import "RDCharpterModel.h"
#import "RDLibraryTransaction.h"
#import "RDLibraryMutationCoordinator.h"

@interface RDImportDiagnosticTests : XCTestCase
@end

@implementation RDImportDiagnosticTests

- (void)testStep1_MakeFixture
{
    NSURL *url = [RDTestSupport makeTxtBookWithTitle:@"诊断1" chapters:3];
    NSLog(@"[DIAG] fixture=%@ exists=%d", url.path,
          [[NSFileManager defaultManager] fileExistsAtPath:url.path]);
    XCTAssertTrue([[NSFileManager defaultManager] fileExistsAtPath:url.path]);
}

- (void)testStep2_Parse
{
    NSURL *url = [RDTestSupport makeTxtBookWithTitle:@"诊断2" chapters:3];
    NSLog(@"[DIAG] parse begin");
    NSString *error = nil;
    RDLocalBookParseResult *result = [RDTxtBookParser parseFileAtPath:url.path error:&error];
    NSLog(@"[DIAG] parse done chapters=%lu error=%@", (unsigned long)result.chapters.count, error);
    XCTAssertNotNil(result);
}

- (void)testStep3_RendererOffMainThread
{
    // 导入在后台队列上用 UIGraphicsImageRenderer 画封面,这里单独验证它不会卡
    NSLog(@"[DIAG] renderer begin");
    __block BOOL ok = NO;
    BOOL finished = [RDTestSupport waitFor:^(dispatch_block_t done) {
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
            UIGraphicsImageRenderer *renderer =
                [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(300, 420)];
            UIImage *image = [renderer imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
                [[UIColor whiteColor] setFill];
                [ctx fillRect:CGRectMake(0, 0, 300, 420)];
                [@"诊断" drawAtPoint:CGPointMake(10, 10) withAttributes:nil];
            }];
            ok = image != nil;
            NSLog(@"[DIAG] renderer done ok=%d", ok);
            done();
        });
    } timeout:20];
    XCTAssertTrue(finished, @"后台线程画图不应卡住");
    XCTAssertTrue(ok);
}

- (void)testStep4a_CommitTransactionDirectly
{
    NSURL *url = [RDTestSupport makeTxtBookWithTitle:@"诊断4a" chapters:3];
    NSString *parseError = nil;
    RDLocalBookParseResult *result = [RDTxtBookParser parseFileAtPath:url.path error:&parseError];
    XCTAssertNotNil(result);

    RDBookDetailModel *book = [[RDBookDetailModel alloc] init];
    book.bookId = -987654321;
    book.title = @"诊断4a";
    book.author = @"测试";
    book.localPath = @"diag4a.txt";
    book.fileType = @"txt";
    book.onBookshelf = YES;
    for (RDCharpterModel *chapter in result.chapters) {
        chapter.bookId = book.bookId;
    }

    NSLog(@"[DIAG] commit begin");
    NSError *error = nil;
    BOOL ok = [RDLibraryTransaction commitBook:book chapters:result.chapters touchReadTime:YES error:&error];
    NSLog(@"[DIAG] commit done ok=%d error=%@", ok, error);
    XCTAssertTrue(ok, @"单事务提交不应卡住,错误:%@", error);

    // 两张表都要清:早先只删 read 行,章节留在库里成了孤儿数据
    [RDCharpterDataManager deleteAllCharpterWithBookId:book.bookId];
    [RDReadRecordManager removeBookFromBookShelfWithBookId:book.bookId];
}

- (void)testStep4b_DatabaseReadOnMutationQueue
{
    NSLog(@"[DIAG] db-on-queue begin");
    __block BOOL ok = NO;
    BOOL finished = [RDTestSupport waitFor:^(dispatch_block_t done) {
        [RDLibraryMutationCoordinator performAsync:^{
            RDBookDetailModel *record = [RDReadRecordManager getReadRecordWithBookId:-1];
            ok = (record == nil);
            NSLog(@"[DIAG] db-on-queue done");
            done();
        }];
    } timeout:20];
    XCTAssertTrue(finished, @"在变更队列上访问数据库不应卡住");
    XCTAssertTrue(ok);
}

- (void)testStep4_FullImport
{
    NSURL *url = [RDTestSupport makeTxtBookWithTitle:@"诊断4" chapters:3];
    NSLog(@"[DIAG] import begin");
    __block BOOL called = NO;
    BOOL finished = [RDTestSupport waitFor:^(dispatch_block_t done) {
        [RDLocalBookManager importBookAtURL:url complete:^(RDBookDetailModel *book,
                                                           NSString *message,
                                                           BOOL duplicate) {
            called = YES;
            NSLog(@"[DIAG] import callback book=%@ message=%@ dup=%d", @(book.bookId), message, duplicate);
            done();
        }];
    } timeout:30];
    NSLog(@"[DIAG] import wait finished=%d called=%d", finished, called);
    XCTAssertTrue(finished, @"导入回调应在 30 秒内到达");
}

@end
