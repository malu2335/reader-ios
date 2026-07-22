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
    NSURL *url = [RDTestSupport makeTxtBookWithTitle:@"合法大文件" byteSize:2 * 1024 * 1024];
    NSString *message = nil;
    RDBookDetailModel *book = [RDTestSupport importBookAtURL:url message:&message isDuplicate:NULL];
    XCTAssertNotNil(book, @"2MB 的正常 TXT 应能导入,错误:%@", message);
}

/// 非法/损坏的 ZIP 不得让解析器崩溃
- (void)testCorruptedZipIsHandledGracefully
{
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

/// dataForEntry:maxUncompressedBytes: 必须在解压前拒绝超预算条目(P1-CHAIN-01)
- (void)testZipEntryBudgetRejectsOversizedDeclaredEntry
{
    // 构造最小合法 ZIP:一条 stored 条目,中央目录声明 uncompressedSize 远超 4MB
    // 实际 payload 很小——验证“声明大小预检”而不是真解压 200MB
    NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:@"budget-fake.zip"];
    [[NSFileManager defaultManager] removeItemAtPath:path error:nil];

    NSMutableData *zip = [NSMutableData data];
    NSData *nameData = [@"huge.xhtml" dataUsingEncoding:NSUTF8StringEncoding];
    NSData *payload = [@"tiny" dataUsingEncoding:NSUTF8StringEncoding];
    uint32_t declaredSize = (uint32_t)(10ull * 1024 * 1024); // 10MB 声明
    uint32_t crc = 0; // 不必真实 CRC:预算检查在 CRC 前

    // local file header
    uint8_t local[30] = {0};
    uint32_t sigLocal = 0x04034b50;
    memcpy(local, &sigLocal, 4);
    uint16_t nameLen = (uint16_t)nameData.length;
    uint32_t compSize = (uint32_t)payload.length;
    memcpy(local + 18, &compSize, 4);
    memcpy(local + 22, &declaredSize, 4);
    memcpy(local + 26, &nameLen, 2);
    [zip appendBytes:local length:30];
    [zip appendData:nameData];
    [zip appendData:payload];

    uint32_t localOffset = 0;
    uint32_t centralOffset = (uint32_t)zip.length;
    // central directory header
    uint8_t central[46] = {0};
    uint32_t sigCentral = 0x02014b50;
    memcpy(central, &sigCentral, 4);
    memcpy(central + 16, &crc, 4);
    memcpy(central + 20, &compSize, 4);
    memcpy(central + 24, &declaredSize, 4);
    memcpy(central + 28, &nameLen, 2);
    memcpy(central + 42, &localOffset, 4);
    [zip appendBytes:central length:46];
    [zip appendData:nameData];

    // EOCD
    uint8_t eocd[22] = {0};
    uint32_t sigEOCD = 0x06054b50;
    uint16_t total = 1;
    uint32_t centralSize = 46 + nameLen;
    memcpy(eocd, &sigEOCD, 4);
    memcpy(eocd + 8, &total, 2);
    memcpy(eocd + 10, &total, 2);
    memcpy(eocd + 12, &centralSize, 4);
    memcpy(eocd + 16, &centralOffset, 4);
    [zip appendBytes:eocd length:22];
    XCTAssertTrue([zip writeToFile:path atomically:YES]);

    RDZipArchive *archive = [[RDZipArchive alloc] initWithPath:path];
    XCTAssertNotNil(archive, @"最小 ZIP 应能打开");
    XCTAssertEqual([archive declaredUncompressedSizeForEntry:@"huge.xhtml"], (unsigned long long)declaredSize);
    // 调用方 4MB 预算:声明 10MB 必须在分配前拒绝
    NSData *data = [archive dataForEntry:@"huge.xhtml" maxUncompressedBytes:4ull * 1024 * 1024];
    XCTAssertNil(data, @"超调用方预算的条目不得解压返回");

    [[NSFileManager defaultManager] removeItemAtPath:path error:nil];
}

@end
