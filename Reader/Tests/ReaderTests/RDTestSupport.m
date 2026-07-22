//
//  RDTestSupport.m
//  ReaderTests
//

#import "RDTestSupport.h"
#import "RDMarcos.h"
#import "RDBookDetailModel.h"
#import "RDReadRecordManager.h"
#import "RDCharpterDataManager.h"
#import "RDBookmarkManager.h"
#import "RDHistoryRecordManager.h"
#import "RDLocalBookManager.h"
#import "RDLibraryMutationCoordinator.h"

@implementation RDTestSupport

+ (void)resetLibrary
{
    NSArray<RDBookDetailModel *> *books = [RDReadRecordManager getAllRecordsForDestructiveClear];
    for (RDBookDetailModel *book in books) {
        if (book.isLocalBook) {
            [RDLocalBookManager removeLocalBook:book];
        }
        else {
            [RDReadRecordManager removeBookFromBookShelfWithBookId:book.bookId];
            [RDBookmarkManager deleteAllForBookId:book.bookId];
            [RDCharpterDataManager deleteAllCharpterWithBookId:book.bookId];
        }
    }
    [RDHistoryRecordManager deleteAllHistory];
    [self waitForLibraryQueue];

    // 兜底:清掉 LocalBooks 下的残留文件(故障注入用例可能留下半成品)
    NSString *dir = [RDLocalBookManager booksDirectory];
    NSFileManager *fm = [NSFileManager defaultManager];
    for (NSString *name in [fm contentsOfDirectoryAtPath:dir error:nil]) {
        [fm removeItemAtPath:[dir stringByAppendingPathComponent:name] error:nil];
    }
    // 删除 kill/journal 用例可能留下 TrashStaging 子目录;必须清干净避免后续 empty 断言 flaky
    NSString *trash = [PATH_DOCUMENT stringByAppendingPathComponent:@"TrashStaging"];
    if ([fm fileExistsAtPath:trash]) {
        for (NSString *name in [fm contentsOfDirectoryAtPath:trash error:nil]) {
            [fm removeItemAtPath:[trash stringByAppendingPathComponent:name] error:nil];
        }
    }
    // RestoreJournal 同理(恢复 kill 注入残留)
    NSString *restoreJournal = [PATH_DOCUMENT stringByAppendingPathComponent:@"RestoreJournal"];
    if ([fm fileExistsAtPath:restoreJournal]) {
        for (NSString *name in [fm contentsOfDirectoryAtPath:restoreJournal error:nil]) {
            [fm removeItemAtPath:[restoreJournal stringByAppendingPathComponent:name] error:nil];
        }
    }
}

+ (void)waitForLibraryQueue
{
    // 变更队列是串行的:排一个空块进去,它跑完就说明前面的都跑完了。
    // removeLocalBook 的章节清理是 dispatch_async 到同一条队列,因此这里能等到。
    dispatch_semaphore_t sema = dispatch_semaphore_create(0);
    [RDLibraryMutationCoordinator performAsync:^{
        dispatch_semaphore_signal(sema);
    }];
    dispatch_semaphore_wait(sema, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(20 * NSEC_PER_SEC)));
}

+ (NSString *)p_scratchDirectory
{
    NSString *dir = [NSTemporaryDirectory() stringByAppendingPathComponent:@"RDTestFixtures"];
    [[NSFileManager defaultManager] createDirectoryAtPath:dir
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:nil];
    return dir;
}

+ (NSURL *)p_writeText:(NSString *)text title:(NSString *)title
{
    NSString *name = [NSString stringWithFormat:@"%@.txt", title];
    NSString *path = [[self p_scratchDirectory] stringByAppendingPathComponent:name];
    [[NSFileManager defaultManager] removeItemAtPath:path error:nil];
    NSError *error = nil;
    [text writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:&error];
    NSAssert(error == nil, @"写 fixture 失败: %@", error);
    return [NSURL fileURLWithPath:path];
}

+ (NSURL *)makeTxtBookWithTitle:(NSString *)title chapters:(NSInteger)chapterCount
{
    // 内容带唯一后缀:bookId 由文件内容 MD5 派生,保证不同用例的书互不冲突
    NSString *salt = [[NSUUID UUID] UUIDString];
    NSMutableString *text = [NSMutableString string];
    for (NSInteger i = 1; i <= chapterCount; i++) {
        [text appendFormat:@"第%ld章 测试章节%ld\n", (long)i, (long)i];
        for (NSInteger line = 0; line < 20; line++) {
            [text appendFormat:@"这是第%ld章的正文第%ld行,用于校验分章与入库。%@\n",
                               (long)i, (long)line, salt];
        }
    }
    return [self p_writeText:text title:title];
}

+ (NSURL *)makeTxtBookWithTitle:(NSString *)title byteSize:(NSUInteger)byteSize
{
    NSString *unit = @"第一章 超大文本\n";
    NSMutableString *text = [NSMutableString stringWithString:unit];
    NSString *filler = [@"" stringByPaddingToLength:1024 withString:@"漫" startingAtIndex:0];
    while ([text lengthOfBytesUsingEncoding:NSUTF8StringEncoding] < byteSize) {
        [text appendString:filler];
    }
    return [self p_writeText:text title:title];
}

+ (RDBookDetailModel *)importBookAtURL:(NSURL *)url
                               message:(NSString **)message
                           isDuplicate:(BOOL *)isDuplicate
{
    __block RDBookDetailModel *result = nil;
    __block NSString *outMessage = nil;
    __block BOOL outDuplicate = NO;
    BOOL finished = [self waitFor:^(dispatch_block_t done) {
        [RDLocalBookManager importBookAtURL:url complete:^(RDBookDetailModel *book,
                                                           NSString *errorMessage,
                                                           BOOL duplicate) {
            result = book;
            outMessage = errorMessage;
            outDuplicate = duplicate;
            done();
        }];
    } timeout:60];
    if (!finished) {
        outMessage = @"导入回调超时";
        result = nil;
    }
    if (message) {
        *message = outMessage;
    }
    if (isDuplicate) {
        *isDuplicate = outDuplicate;
    }
    return result;
}

+ (BOOL)setBooksDirectoryWritable:(BOOL)writable
{
    NSString *dir = [RDLocalBookManager booksDirectory];
    NSDictionary *attrs = @{NSFilePosixPermissions: writable ? @(0755) : @(0555)};
    return [[NSFileManager defaultManager] setAttributes:attrs ofItemAtPath:dir error:nil];
}

+ (BOOL)waitFor:(void (^)(dispatch_block_t))block timeout:(NSTimeInterval)timeout
{
    __block BOOL done = NO;
    dispatch_semaphore_t sema = dispatch_semaphore_create(0);
    block(^{
        done = YES;
        dispatch_semaphore_signal(sema);
    });
    // 回调多数派发回主线程,这里不能干等信号量,否则主线程被自己堵死
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:timeout];
    while (!done && [deadline timeIntervalSinceNow] > 0) {
        if (dispatch_semaphore_wait(sema, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.01 * NSEC_PER_SEC))) == 0) {
            done = YES;
            break;
        }
        [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
    }
    return done;
}

@end
