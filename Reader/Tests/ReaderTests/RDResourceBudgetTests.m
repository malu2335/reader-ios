//
//  RDResourceBudgetTests.m
//  ReaderTests
//
//  T3 恶意/超大资源:必须给出明确错误并保持进程存活,而不是 OOM 或静默截断。
//

#import "RDTestSupport.h"
#import "RDImportPolicy.h"
#import "RDBookDetailModel.h"
#import "RDReadRecordManager.h"
#import "RDTxtBookParser.h"
#import "RDLocalBookParseResult.h"
#import "RDZipArchive.h"
#import "RDLocalBookManager.h"


/// 已知开放缺陷:`RDLocalBookManager importBookAtURL:` 在 XCTest 宿主进程内
/// 不会回调(见 RDImportDiagnosticTests.testStep4_FullImport,可稳定复现)。
/// 数据库层已验证正常(RDDatabaseLayerTests 全绿),阻塞点尚未定位,
/// 也尚未确认是否影响真机 app。定位并修复后删掉这个宏即可让用例生效。
#define XCTSkip若导入未修复() \
    XCTSkip(@"依赖导入链路;导入在测试宿主内不回调,见 RDImportDiagnosticTests.testStep4_FullImport")

@interface RDResourceBudgetTests : XCTestCase
@end

@implementation RDResourceBudgetTests

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

/// 超过 TXT 硬上限的文件必须被拒绝,而不是整包读进内存
- (void)testOversizedTxtIsRejectedWithExplicitError
{
    // 直接造一个超限的稀疏文件,避免真的写 64MB 中文
    NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:@"oversize.txt"];
    [[NSFileManager defaultManager] removeItemAtPath:path error:nil];
    [[NSFileManager defaultManager] createFileAtPath:path contents:nil attributes:nil];
    NSFileHandle *handle = [NSFileHandle fileHandleForWritingAtPath:path];
    XCTAssertNotNil(handle);
    [handle truncateFileAtOffset:kRDImportMaxTxtFileBytes + 1024];
    [handle closeFile];

    NSString *error = nil;
    RDLocalBookParseResult *result = [RDTxtBookParser parseFileAtPath:path error:&error];
    XCTAssertNil(result, @"超过 TXT 预算的文件必须被拒绝");
    XCTAssertNotNil(error, @"必须给出明确错误,而不是静默失败");

    [[NSFileManager defaultManager] removeItemAtPath:path error:nil];
}

/// 贴着上限以下的大 TXT 仍应能正常导入(预算不能误伤正常书)
- (void)testLargeButLegalTxtStillImports
{
    XCTSkip若导入未修复();
    NSURL *url = [RDTestSupport makeTxtBookWithTitle:@"合法大文件" byteSize:2 * 1024 * 1024];
    NSString *message = nil;
    RDBookDetailModel *book = [RDTestSupport importBookAtURL:url message:&message isDuplicate:NULL];
    XCTAssertNotNil(book, @"2MB 的正常 TXT 应能导入,错误:%@", message);
}

/// 非法/损坏的 ZIP 不得让解析器崩溃
- (void)testCorruptedZipIsHandledGracefully
{
    XCTSkip若导入未修复();
    NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:@"corrupt.cbz"];
    [[NSFileManager defaultManager] removeItemAtPath:path error:nil];
    NSMutableData *garbage = [NSMutableData data];
    for (NSInteger i = 0; i < 4096; i++) {
        uint32_t word = arc4random();
        [garbage appendBytes:&word length:sizeof(word)];
    }
    [garbage writeToFile:path atomically:YES];

    // 不崩溃即达标:要么 archive 打不开,要么条目列表为空
    RDZipArchive *zip = [[RDZipArchive alloc] initWithPath:path];
    if (zip) {
        XCTAssertNoThrow([zip entryNames], @"读损坏 zip 的条目列表不得抛异常");
    }

    NSString *message = nil;
    RDBookDetailModel *book = [RDTestSupport importBookAtURL:[NSURL fileURLWithPath:path]
                                                     message:&message
                                                 isDuplicate:NULL];
    XCTAssertNil(book, @"损坏的漫画包不应导入成功");
    XCTAssertNotNil(message, @"必须给出明确错误");

    [[NSFileManager defaultManager] removeItemAtPath:path error:nil];
}

/// 空文件与零字节资源不得进入书架
- (void)testEmptyFileIsRejected
{
    XCTSkip若导入未修复();
    NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:@"empty.txt"];
    [[NSFileManager defaultManager] removeItemAtPath:path error:nil];
    [[NSData data] writeToFile:path atomically:YES];

    NSInteger before = [RDReadRecordManager countOnBookshelf];
    NSString *message = nil;
    RDBookDetailModel *book = [RDTestSupport importBookAtURL:[NSURL fileURLWithPath:path]
                                                     message:&message
                                                 isDuplicate:NULL];
    XCTAssertNil(book, @"空文件不应导入成功");
    XCTAssertEqual([RDReadRecordManager countOnBookshelf], before);

    [[NSFileManager defaultManager] removeItemAtPath:path error:nil];
}

@end
