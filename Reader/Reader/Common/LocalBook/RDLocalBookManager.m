//
//  RDLocalBookManager.m
//  Reader
//

#import "RDLocalBookManager.h"
#import <CommonCrypto/CommonDigest.h>
#import <PDFKit/PDFKit.h>
#import <math.h>
#import "RDBookDetailModel.h"
#import "RDCharpterModel.h"
#import "RDCharpterDataManager.h"
#import "RDReadRecordManager.h"
#import "RDLibraryTransaction.h"
#import "RDLibraryMutationCoordinator.h"
#import "RDBookmarkManager.h"
#import "RDHistoryRecordManager.h"
#import "RDLocalBookParseResult.h"
#import "RDTxtBookParser.h"
#import "RDEpubBookParser.h"
#import "RDMobiBookParser.h"
#import "RDZipArchive.h"
#import "RDComicHelper.h"

NSString * const RDLocalBookImportedNotification = @"RDLocalBookImportedNotification";
NSString * const RDLocalBookImportRequestNotification = @"RDLocalBookImportRequestNotification";

static NSString * const kLocalBooksDirName = @"LocalBooks";
static NSString * const kPDFAutoCoverVersion = @"v1";
static NSString * const kCustomCoverVersion = @"v1";
static const CGSize kBookCoverPixelSize = {600.0, 840.0};
static void *kRDCustomCoverQueueKey = &kRDCustomCoverQueueKey;

@interface RDLocalBookManager ()

+ (void)p_performSyncOnImportQueue:(dispatch_block_t)block;
+ (dispatch_queue_t)p_customCoverQueue;
+ (void)p_performSyncOnCustomCoverQueue:(dispatch_block_t)block;
+ (NSMutableDictionary <NSNumber *, NSNumber *>*)p_customCoverRequestVersions;
+ (NSUInteger)p_advanceCustomCoverRequestForBookId:(NSInteger)bookId;
+ (BOOL)p_isCustomCoverRequestCurrent:(NSUInteger)requestVersion bookId:(NSInteger)bookId;
+ (nullable NSString *)p_pdfAutoCoverNameForBookId:(NSInteger)bookId;
+ (nullable UIImage *)p_renderFirstPageForPDFAtPath:(NSString *)path pageCount:(NSInteger * _Nullable)pageCount;
+ (BOOL)p_writeJPEGImage:(UIImage *)image
                  toPath:(NSString *)path
                 quality:(CGFloat)quality
                   error:(NSError * _Nullable * _Nullable)error;
+ (void)p_preparePDFAutoCoverForBook:(RDBookDetailModel *)book;

@end

@implementation RDLocalBookManager

+ (NSArray <NSString *>*)supportedExtensions
{
    return @[@"txt", @"epub", @"mobi", @"pdf", @"azw", @"zip", @"cbz"];
}

+ (BOOL)isSupportedFileURL:(NSURL *)url
{
    if (!url) {
        return NO;
    }
    BOOL isDir = NO;
    if ([[NSFileManager defaultManager] fileExistsAtPath:url.path isDirectory:&isDir] && isDir) {
        return [RDComicHelper directoryHasImagesAtPath:url.path];
    }
    return [[self supportedExtensions] containsObject:url.pathExtension.lowercaseString];
}

+ (NSString *)booksDirectory
{
    NSString *dir = [PATH_DOCUMENT stringByAppendingPathComponent:kLocalBooksDirName];
    if (![[NSFileManager defaultManager] fileExistsAtPath:dir]) {
        [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
    }
    return dir;
}

+ (NSString *)absolutePathForBook:(RDBookDetailModel *)book
{
    if (book.localPath.length == 0) {
        return nil;
    }
    return [[self booksDirectory] stringByAppendingPathComponent:book.localPath];
}

#pragma mark - 导入

/// 书库变更串行队列:导入/删除/清空/恢复共用同一条,
/// 同内容文件并发导入时去重检查与落盘天然互斥(见 RDLibraryMutationCoordinator)
+ (dispatch_queue_t)importQueue
{
    return [RDLibraryMutationCoordinator queue];
}

+ (void)p_performSyncOnImportQueue:(dispatch_block_t)block
{
    [RDLibraryMutationCoordinator performSync:block];
}

+ (dispatch_queue_t)p_customCoverQueue
{
    static dispatch_queue_t queue;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        queue = dispatch_queue_create("com.reader.localbook.custom-cover", DISPATCH_QUEUE_SERIAL);
        dispatch_queue_set_specific(queue,
                                    kRDCustomCoverQueueKey,
                                    kRDCustomCoverQueueKey,
                                    NULL);
    });
    return queue;
}

+ (void)p_performSyncOnCustomCoverQueue:(dispatch_block_t)block
{
    if (!block) {
        return;
    }
    if (dispatch_get_specific(kRDCustomCoverQueueKey)) {
        block();
    }
    else {
        dispatch_sync([self p_customCoverQueue], block);
    }
}

+ (NSMutableDictionary<NSNumber *,NSNumber *> *)p_customCoverRequestVersions
{
    static NSMutableDictionary <NSNumber *, NSNumber *>*versions;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        versions = [NSMutableDictionary dictionary];
    });
    return versions;
}

/// 仅在 customCoverQueue 内调用。
+ (NSUInteger)p_advanceCustomCoverRequestForBookId:(NSInteger)bookId
{
    NSNumber *key = @(bookId);
    NSUInteger version = [[self p_customCoverRequestVersions][key] unsignedIntegerValue] + 1;
    [self p_customCoverRequestVersions][key] = @(version);
    return version;
}

/// 仅在 customCoverQueue 内调用。
+ (BOOL)p_isCustomCoverRequestCurrent:(NSUInteger)requestVersion bookId:(NSInteger)bookId
{
    if (bookId == 0 || requestVersion == 0) {
        return NO;
    }
    return [[self p_customCoverRequestVersions][@(bookId)] unsignedIntegerValue] == requestVersion;
}

+ (nullable NSString *)p_pdfAutoCoverNameForBookId:(NSInteger)bookId
{
    if (bookId == 0) {
        return nil;
    }
    unsigned long long absoluteId = bookId < 0
        ? (unsigned long long)(-(bookId + 1)) + 1
        : (unsigned long long)bookId;
    return [NSString stringWithFormat:@"%llu_pdf_cover_%@.jpg", absoluteId, kPDFAutoCoverVersion];
}

+ (nullable UIImage *)p_renderFirstPageForPDFAtPath:(NSString *)path pageCount:(NSInteger *)pageCount
{
    if (pageCount) {
        *pageCount = 0;
    }
    if (path.length == 0) {
        return nil;
    }
    PDFDocument *document = [[PDFDocument alloc] initWithURL:[NSURL fileURLWithPath:path]];
    if (!document) {
        return nil;
    }
    if (document.isLocked && ![document unlockWithPassword:@""]) {
        return nil;
    }
    NSInteger count = document.pageCount;
    if (pageCount) {
        *pageCount = count;
    }
    if (count <= 0) {
        return nil;
    }
    PDFPage *page = [document pageAtIndex:0];
    if (!page) {
        return nil;
    }

    PDFDisplayBox displayBox = kPDFDisplayBoxCropBox;
    CGRect pageBounds = [page boundsForBox:displayBox];
    if (CGRectIsEmpty(pageBounds) || !isfinite(pageBounds.size.width) || !isfinite(pageBounds.size.height)) {
        displayBox = kPDFDisplayBoxMediaBox;
        pageBounds = [page boundsForBox:displayBox];
    }
    CGFloat pageWidth = fabs(pageBounds.size.width);
    CGFloat pageHeight = fabs(pageBounds.size.height);
    if (pageWidth <= 0 || pageHeight <= 0 || !isfinite(pageWidth) || !isfinite(pageHeight)) {
        return nil;
    }

    CGFloat thumbnailScale = MIN(kBookCoverPixelSize.width / pageWidth,
                                 kBookCoverPixelSize.height / pageHeight);
    CGSize thumbnailSize = CGSizeMake(MAX(1.0, floor(pageWidth * thumbnailScale)),
                                      MAX(1.0, floor(pageHeight * thumbnailScale)));
    UIImage *thumbnail = [page thumbnailOfSize:thumbnailSize forBox:displayBox];
    if (!thumbnail || thumbnail.size.width <= 0 || thumbnail.size.height <= 0) {
        return nil;
    }

    CGFloat fitScale = MIN(kBookCoverPixelSize.width / thumbnail.size.width,
                           kBookCoverPixelSize.height / thumbnail.size.height);
    CGSize drawSize = CGSizeMake(thumbnail.size.width * fitScale,
                                 thumbnail.size.height * fitScale);
    CGRect drawRect = CGRectMake((kBookCoverPixelSize.width - drawSize.width) * 0.5,
                                 (kBookCoverPixelSize.height - drawSize.height) * 0.5,
                                 drawSize.width,
                                 drawSize.height);
    UIGraphicsImageRendererFormat *format = [UIGraphicsImageRendererFormat defaultFormat];
    format.scale = 1.0;
    format.opaque = YES;
    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:kBookCoverPixelSize
                                                                                format:format];
    return [renderer imageWithActions:^(UIGraphicsImageRendererContext *context) {
        [[UIColor whiteColor] setFill];
        [context fillRect:CGRectMake(0, 0, kBookCoverPixelSize.width, kBookCoverPixelSize.height)];
        [thumbnail drawInRect:drawRect];
    }];
}

+ (BOOL)p_writeJPEGImage:(UIImage *)image
                  toPath:(NSString *)path
                 quality:(CGFloat)quality
                   error:(NSError **)error
{
    if (!image || path.length == 0) {
        return NO;
    }
    NSData *data = UIImageJPEGRepresentation(image, quality);
    if (data.length == 0) {
        return NO;
    }
    return [data writeToFile:path options:NSDataWritingAtomic error:error];
}

+ (void)p_preparePDFAutoCoverForBook:(RDBookDetailModel *)book
{
    if (!book.isLocalBook ||
        !([book.fileType.lowercaseString isEqualToString:@"pdf"] ||
          [book.localPath.pathExtension.lowercaseString isEqualToString:@"pdf"])) {
        return;
    }
    NSString *pdfPath = [self absolutePathForBook:book];
    if (pdfPath.length == 0 || ![[NSFileManager defaultManager] fileExistsAtPath:pdfPath]) {
        return;
    }
    NSString *coverName = [self p_pdfAutoCoverNameForBookId:book.bookId];
    if (coverName.length == 0) {
        return;
    }
    NSString *coverPath = [[self booksDirectory] stringByAppendingPathComponent:coverName];
    UIImage *cover = [UIImage imageWithContentsOfFile:coverPath];
    BOOL createdCover = NO;
    if (!cover) {
        cover = [self p_renderFirstPageForPDFAtPath:pdfPath pageCount:NULL];
        if (!cover || ![self p_writeJPEGImage:cover toPath:coverPath quality:0.88 error:nil]) {
            return;
        }
        createdCover = YES;
    }
    if (![book.coverImg isEqualToString:coverName]) {
        NSString *oldCoverName = book.coverImg;
        if (![RDReadRecordManager updateCoverImg:coverName forBookId:book.bookId]) {
            // 数据库仍指向旧封面时必须保留旧文件；本次新产物也不要留下孤儿。
            if (createdCover) {
                [[NSFileManager defaultManager] removeItemAtPath:coverPath error:nil];
            }
            return;
        }
        book.coverImg = coverName;

        // 只清理旧版 PDF 文字自动封面;不删除任意路径或独立手动封面。
        unsigned long long absoluteId = book.bookId < 0
            ? (unsigned long long)(-(book.bookId + 1)) + 1
            : (unsigned long long)book.bookId;
        NSString *legacyAutoCoverName = [NSString stringWithFormat:@"%llu_cover.png", absoluteId];
        if ([oldCoverName isEqualToString:legacyAutoCoverName]) {
            NSString *legacyPath = [[self booksDirectory] stringByAppendingPathComponent:legacyAutoCoverName];
            [[NSFileManager defaultManager] removeItemAtPath:legacyPath error:nil];
        }
    }
}

+ (void)preparePDFCoversForBooks:(NSArray<RDBookDetailModel *> *)books
{
    if (books.count == 0) {
        return;
    }
    [self p_performSyncOnImportQueue:^{
        @autoreleasepool {
            for (RDBookDetailModel *book in books) {
                [self p_preparePDFAutoCoverForBook:book];
            }
        }
    }];
}

+ (void)importBookAtURL:(NSURL *)url complete:(RDLocalBookImportCompletion)complete
{
    void (^finish)(RDBookDetailModel *, NSString *, BOOL) = ^(RDBookDetailModel *book, NSString *message, BOOL isDuplicate) {
        dispatch_async(dispatch_get_main_queue(), ^{
            // 成功(含重复重新上架)都刷书架
            if (book) {
                [[NSNotificationCenter defaultCenter] postNotificationName:RDLocalBookImportedNotification object:book];
            }
            if (complete) {
                complete(book, message, isDuplicate);
            }
        });
    };

    dispatch_async([self importQueue], ^{
        BOOL scoped = [url startAccessingSecurityScopedResource];
        BOOL isDir = NO;
        [[NSFileManager defaultManager] fileExistsAtPath:url.path isDirectory:&isDir];
        if (![self isSupportedFileURL:url]) {
            if (scoped) {
                [url stopAccessingSecurityScopedResource];
            }
            finish(nil, isDir ? @"文件夹中没有可导入的图片" : @"暂不支持该文件格式", NO);
            return;
        }

        NSString *displayName = isDir
            ? url.lastPathComponent
            : url.lastPathComponent.stringByDeletingPathExtension;
        NSString *ext = isDir ? @"cbz" : url.pathExtension.lowercaseString;

        // 流式 MD5 → 稳定 bookId(目录则按图片内容哈希)
        NSInteger bookId = isDir ? [self bookIdForImageDirectoryURL:url] : [self bookIdForFileURL:url];
        if (bookId == 0) {
            if (scoped) {
                [url stopAccessingSecurityScopedResource];
            }
            finish(nil, isDir ? @"文件夹为空或无法读取" : @"文件为空或无法读取", NO);
            return;
        }
        RDBookDetailModel *existing = [RDReadRecordManager getReadRecordWithBookId:bookId];
        if (existing && existing.localPath.length > 0 &&
            [[NSFileManager defaultManager] fileExistsAtPath:[self absolutePathForBook:existing]]) {
            // 旧 PDF 重复导入时也尝试修复首页封面;队列特定值避免同队列 dispatch_sync 死锁。
            [self preparePDFCoversForBooks:@[existing]];
            if (scoped) {
                [url stopAccessingSecurityScopedResource];
            }
            BOOL reAdded = NO;
            if (!existing.onBookshelf) {
                existing.onBookshelf = YES;
                [RDReadRecordManager updateBookshelfState:existing];
                reAdded = YES;
            }
            NSString *dupMsg = reAdded
                ? [NSString stringWithFormat:@"《%@》已重新加入书架", existing.title ?: displayName]
                : [NSString stringWithFormat:@"《%@》已在书架,跳过重复导入", existing.title ?: displayName];
            finish(existing, dupMsg, YES);
            return;
        }

        // 落盘:文件 copy;图片文件夹打包为 cbz(与备份单文件模型一致)
        NSString *storeExt = ext;
        if ([storeExt isEqualToString:@"zip"] || [storeExt isEqualToString:@"cbz"] || isDir) {
            storeExt = @"cbz";
        }
        NSString *fileName = [NSString stringWithFormat:@"%@.%@", @(-bookId), storeExt];
        NSString *filePath = [[self booksDirectory] stringByAppendingPathComponent:fileName];
        [[NSFileManager defaultManager] removeItemAtPath:filePath error:nil];

        if (isDir) {
            NSString *packError = nil;
            BOOL packed = [RDComicHelper packImageDirectory:url.path toZipPath:filePath error:&packError];
            if (scoped) {
                [url stopAccessingSecurityScopedResource];
            }
            if (!packed) {
                [[NSFileManager defaultManager] removeItemAtPath:filePath error:nil];
                finish(nil, packError ?: @"打包图片文件夹失败", NO);
                return;
            }
        } else {
            NSError *copyError = nil;
            BOOL copied = [[NSFileManager defaultManager] copyItemAtURL:url toURL:[NSURL fileURLWithPath:filePath] error:&copyError];
            if (!copied) {
                NSData *fileData = [NSData dataWithContentsOfURL:url options:NSDataReadingMappedIfSafe error:nil];
                if (fileData.length == 0 || ![fileData writeToFile:filePath atomically:YES]) {
                    if (scoped) {
                        [url stopAccessingSecurityScopedResource];
                    }
                    finish(nil, @"保存文件失败", NO);
                    return;
                }
            }
            if (scoped) {
                [url stopAccessingSecurityScopedResource];
            }
        }

        NSString *fileType = [ext isEqualToString:@"azw"] ? @"mobi" : ext;
        if (isDir || [fileType isEqualToString:@"zip"]) {
            fileType = @"cbz";
        }
        NSString *parseError = nil;
        RDLocalBookParseResult *result = nil;
        NSInteger comicPageCount = 0;
        NSInteger pdfPageCount = 0;
        UIImage *pdfCover = nil;
        if ([fileType isEqualToString:@"txt"]) {
            result = [RDTxtBookParser parseFileAtPath:filePath error:&parseError];
        }
        else if ([fileType isEqualToString:@"epub"]) {
            result = [RDEpubBookParser parseFileAtPath:filePath error:&parseError];
        }
        else if ([fileType isEqualToString:@"mobi"]) {
            result = [RDMobiBookParser parseFileAtPath:filePath error:&parseError];
        }
        else if ([fileType isEqualToString:@"pdf"]) {
            // PDF 不做章节抽取,由 PDF 阅读器直接渲染
            result = [[RDLocalBookParseResult alloc] init];
            result.chapters = @[];
            pdfCover = [self p_renderFirstPageForPDFAtPath:filePath pageCount:&pdfPageCount];
        }
        else if ([RDComicHelper isComicFileType:fileType]) {
            RDZipArchive *zip = [[RDZipArchive alloc] initWithPath:filePath];
            NSArray <NSString *>*pages = [RDComicHelper sortedImageEntriesInZip:zip];
            if (pages.count == 0) {
                [[NSFileManager defaultManager] removeItemAtPath:filePath error:nil];
                finish(nil, @"压缩包内未找到图片(需要 jpg/png/webp 等)", NO);
                return;
            }
            result = [[RDLocalBookParseResult alloc] init];
            result.chapters = @[];
            result.title = displayName;
            comicPageCount = pages.count;
            NSData *first = [zip dataForEntry:pages.firstObject];
            if (first.length > 0) {
                result.coverData = first;
            }
            result.author = isDir ? @"图片文件夹" : @"本地图集";
        }

        if (!result) {
            [[NSFileManager defaultManager] removeItemAtPath:filePath error:nil];
            finish(nil, parseError ?: @"解析失败", NO);
            return;
        }

        RDBookDetailModel *book = [[RDBookDetailModel alloc] init];
        book.bookId = bookId;
        book.title = result.title.length > 0 ? result.title : displayName;
        book.author = result.author.length > 0 ? result.author : @"本地导入";
        book.localPath = fileName;
        book.fileType = fileType;
        book.onBookshelf = YES;
        book.end = YES;
        if ([fileType isEqualToString:@"pdf"]) {
            book.total = pdfPageCount;
        }
        else if ([RDComicHelper isComicFileType:fileType]) {
            book.total = comicPageCount;
        }
        else {
            book.total = result.chapters.count;
        }

        if (result.chapters.count > 0) {
            for (RDCharpterModel *chapter in result.chapters) {
                chapter.bookId = bookId;
                chapter.bookName = book.title;
                chapter.author = book.author;
            }
            book.charpterModel = result.chapters.firstObject;
        }

        BOOL savedPDFCover = NO;
        if ([fileType isEqualToString:@"pdf"] && pdfCover) {
            NSString *pdfCoverName = [self p_pdfAutoCoverNameForBookId:bookId];
            NSString *pdfCoverPath = [[self booksDirectory] stringByAppendingPathComponent:pdfCoverName];
            if ([self p_writeJPEGImage:pdfCover toPath:pdfCoverPath quality:0.88 error:nil]) {
                book.coverImg = pdfCoverName;
                savedPDFCover = YES;
            }
        }

        // PDF 不可渲染/落盘失败时也走原有文字封面,不影响导入。
        if (!savedPDFCover) {
            NSString *coverName = [NSString stringWithFormat:@"%@_cover.png", @(-bookId)];
            NSString *coverPath = [[self booksDirectory] stringByAppendingPathComponent:coverName];
            UIImage *embedded = nil;
            if (result.coverData.length > 0) {
                embedded = [RDComicHelper imageFromData:result.coverData] ?: [UIImage imageWithData:result.coverData];
            }
            UIImage *cover = embedded ?: [self generateCoverWithTitle:book.title fileType:fileType];
            if (cover) {
                // 漫画封面可能很大,缩到合理宽度再落盘
                if ([RDComicHelper isComicFileType:fileType] && cover.size.width > 600) {
                    UIImage *source = cover;
                    CGFloat scale = 600.0 / source.size.width;
                    CGSize size = CGSizeMake(600, source.size.height * scale);
                    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:size];
                    cover = [renderer imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
                        [source drawInRect:CGRectMake(0, 0, size.width, size.height)];
                    }];
                }
                if ([UIImagePNGRepresentation(cover) writeToFile:coverPath atomically:YES]) {
                    book.coverImg = coverName;
                }
            }
        }

        // 章节与读记录合并进单次事务:写失败即整体回滚,不能出现"报成功但书架无此书"
        // 或"有孤儿章节"的混合状态(P1-02/P1-03)。
        NSError *commitError = nil;
        if (![RDLibraryTransaction commitBook:book
                                     chapters:result.chapters
                                touchReadTime:YES
                                        error:&commitError]) {
            [[NSFileManager defaultManager] removeItemAtPath:filePath error:nil];
            if (book.coverImg.length > 0) {
                NSString *coverPath = [[self booksDirectory] stringByAppendingPathComponent:book.coverImg];
                [[NSFileManager defaultManager] removeItemAtPath:coverPath error:nil];
            }
            finish(nil, commitError.localizedDescription ?: @"保存书籍失败", NO);
            return;
        }
        finish(book, nil, NO);
    });
}

+ (NSInteger)bookIdFromDigest:(unsigned char *)digest
{
    uint64_t value = 0;
    for (int i = 0; i < 8; i++) {
        value = (value << 8) | digest[i];
    }
    // 压到正数范围再取负,保证 bookId < 0 且稳定
    NSInteger positive = (NSInteger)(value & 0x7FFFFFFFFFFFFF);
    if (positive == 0) {
        positive = 1;
    }
    return -positive;
}

+ (NSInteger)bookIdForData:(NSData *)data
{
    if (data.length == 0) {
        return 0;
    }
    unsigned char digest[CC_MD5_DIGEST_LENGTH];
    CC_MD5(data.bytes, (CC_LONG)data.length, digest);
    return [self bookIdFromDigest:digest];
}

/// 流式哈希,大文件不整包加载
+ (NSInteger)bookIdForFileURL:(NSURL *)url
{
    NSInputStream *stream = [NSInputStream inputStreamWithURL:url];
    if (!stream) {
        return 0;
    }
    [stream open];
    if (stream.streamStatus == NSStreamStatusError) {
        [stream close];
        return 0;
    }
    CC_MD5_CTX ctx;
    CC_MD5_Init(&ctx);
    uint8_t buffer[64 * 1024];
    NSInteger total = 0;
    while (stream.hasBytesAvailable) {
        NSInteger n = [stream read:buffer maxLength:sizeof(buffer)];
        if (n < 0) {
            [stream close];
            return 0;
        }
        if (n == 0) {
            break;
        }
        total += n;
        CC_MD5_Update(&ctx, buffer, (CC_LONG)n);
    }
    [stream close];
    if (total == 0) {
        return 0;
    }
    unsigned char digest[CC_MD5_DIGEST_LENGTH];
    CC_MD5_Final(digest, &ctx);
    return [self bookIdFromDigest:digest];
}

/// 图片文件夹:按相对路径顺序流式哈希,顺序变化也会得到不同 id
+ (NSInteger)bookIdForImageDirectoryURL:(NSURL *)url
{
    NSArray <NSString *>*images = [RDComicHelper sortedImageRelativePathsInDirectory:url.path];
    if (images.count == 0) {
        return 0;
    }
    CC_MD5_CTX ctx;
    CC_MD5_Init(&ctx);
    NSInteger total = 0;
    uint8_t buffer[64 * 1024];
    for (NSString *rel in images) {
        NSData *nameData = [rel dataUsingEncoding:NSUTF8StringEncoding];
        if (nameData.length > 0) {
            CC_MD5_Update(&ctx, nameData.bytes, (CC_LONG)nameData.length);
        }
        NSString *full = [url.path stringByAppendingPathComponent:rel];
        NSInputStream *stream = [NSInputStream inputStreamWithFileAtPath:full];
        [stream open];
        while (stream.hasBytesAvailable) {
            NSInteger n = [stream read:buffer maxLength:sizeof(buffer)];
            if (n < 0) {
                [stream close];
                return 0;
            }
            if (n == 0) {
                break;
            }
            total += n;
            CC_MD5_Update(&ctx, buffer, (CC_LONG)n);
        }
        [stream close];
    }
    if (total == 0) {
        return 0;
    }
    unsigned char digest[CC_MD5_DIGEST_LENGTH];
    CC_MD5_Final(digest, &ctx);
    return [self bookIdFromDigest:digest];
}

#pragma mark - 封面

+ (nullable NSString *)customCoverPathForBook:(RDBookDetailModel *)book
{
    if (!book || book.bookId == 0) {
        return nil;
    }
    // 保留正负号,避免在线书 id 与本地书 id 绝对值相同时冲突。
    NSString *fileName = [NSString stringWithFormat:@"book_%lld_custom_cover_%@.jpg",
                          (long long)book.bookId,
                          kCustomCoverVersion];
    return [[self booksDirectory] stringByAppendingPathComponent:fileName];
}

+ (nullable UIImage *)customCoverForBook:(RDBookDetailModel *)book
{
    NSString *path = [self customCoverPathForBook:book];
    return path.length > 0 ? [UIImage imageWithContentsOfFile:path] : nil;
}

+ (NSUInteger)beginCustomCoverRequestForBook:(RDBookDetailModel *)book
{
    if (!book || book.bookId == 0) {
        return 0;
    }
    __block NSUInteger version = 0;
    [self p_performSyncOnCustomCoverQueue:^{
        version = [self p_advanceCustomCoverRequestForBookId:book.bookId];
    }];
    return version;
}

+ (BOOL)isCustomCoverRequestCurrent:(NSUInteger)requestVersion
                            forBook:(RDBookDetailModel *)book
{
    if (!book || book.bookId == 0 || requestVersion == 0) {
        return NO;
    }
    __block BOOL current = NO;
    [self p_performSyncOnCustomCoverQueue:^{
        current = [self p_isCustomCoverRequestCurrent:requestVersion bookId:book.bookId];
    }];
    return current;
}

+ (BOOL)saveCustomCover:(UIImage *)cover
                forBook:(RDBookDetailModel *)book
         requestVersion:(NSUInteger)requestVersion
           errorMessage:(NSString **)errorMessage
{
    if (errorMessage) {
        *errorMessage = nil;
    }
    if (!book || book.bookId == 0) {
        if (errorMessage) *errorMessage = @"书籍信息无效";
        return NO;
    }
    if (!cover || cover.size.width <= 0 || cover.size.height <= 0 ||
        !isfinite(cover.size.width) || !isfinite(cover.size.height)) {
        if (errorMessage) *errorMessage = @"无法读取所选图片";
        return NO;
    }

    // 重绘会同时展平 UIImage.imageOrientation,并以居中裁剪填满统一书封比例。
    CGFloat fillScale = MAX(kBookCoverPixelSize.width / cover.size.width,
                            kBookCoverPixelSize.height / cover.size.height);
    CGSize drawSize = CGSizeMake(cover.size.width * fillScale,
                                 cover.size.height * fillScale);
    CGRect drawRect = CGRectMake((kBookCoverPixelSize.width - drawSize.width) * 0.5,
                                 (kBookCoverPixelSize.height - drawSize.height) * 0.5,
                                 drawSize.width,
                                 drawSize.height);
    UIGraphicsImageRendererFormat *format = [UIGraphicsImageRendererFormat defaultFormat];
    format.scale = 1.0;
    format.opaque = YES;
    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:kBookCoverPixelSize
                                                                                format:format];
    UIImage *normalized = [renderer imageWithActions:^(UIGraphicsImageRendererContext *context) {
        [[UIColor whiteColor] setFill];
        [context fillRect:CGRectMake(0, 0, kBookCoverPixelSize.width, kBookCoverPixelSize.height)];
        [cover drawInRect:drawRect];
    }];

    NSString *path = [self customCoverPathForBook:book];
    __block BOOL success = NO;
    __block NSString *failureMessage = nil;
    [self p_performSyncOnCustomCoverQueue:^{
        // 代次校验、书架校验与写文件在同一临界区，迟到回调不能越过删除/新请求。
        if (![self p_isCustomCoverRequestCurrent:requestVersion bookId:book.bookId]) {
            failureMessage = @"封面请求已失效";
            return;
        }
        RDBookDetailModel *record = [RDReadRecordManager getReadRecordWithBookId:book.bookId];
        if (!record || !record.onBookshelf) {
            failureMessage = @"书籍已不在书架";
            return;
        }
        NSError *writeError = nil;
        success = [self p_writeJPEGImage:normalized toPath:path quality:0.88 error:&writeError];
        if (!success) {
            failureMessage = writeError.localizedDescription.length > 0
                ? [NSString stringWithFormat:@"保存封面失败:%@", writeError.localizedDescription]
                : @"保存封面失败";
        }
    }];
    if (!success && errorMessage) {
        *errorMessage = failureMessage ?: @"保存封面失败";
    }
    return success;
}

+ (nullable NSData *)customCoverDataForBook:(RDBookDetailModel *)book
{
    NSString *path = [self customCoverPathForBook:book];
    if (path.length == 0) {
        return nil;
    }
    __block NSData *data = nil;
    [self p_performSyncOnCustomCoverQueue:^{
        data = [NSData dataWithContentsOfFile:path options:NSDataReadingMappedIfSafe error:nil];
    }];
    return data;
}

+ (BOOL)restoreCustomCoverData:(NSData *)data forBook:(RDBookDetailModel *)book
{
    NSString *path = [self customCoverPathForBook:book];
    if (path.length == 0) {
        return NO;
    }
    __block BOOL success = NO;
    [self p_performSyncOnCustomCoverQueue:^{
        [self p_advanceCustomCoverRequestForBookId:book.bookId];
        [[NSFileManager defaultManager] removeItemAtPath:path error:nil];
        if (data.length == 0 || ![UIImage imageWithData:data]) {
            return;
        }
        success = [data writeToFile:path options:NSDataWritingAtomic error:nil];
    }];
    return success;
}

+ (void)removeCustomCoverForBook:(RDBookDetailModel *)book
{
    NSString *path = [self customCoverPathForBook:book];
    if (path.length > 0) {
        [self p_performSyncOnCustomCoverQueue:^{
            [self p_advanceCustomCoverRequestForBookId:book.bookId];
            [[NSFileManager defaultManager] removeItemAtPath:path error:nil];
        }];
    }
}

+ (UIImage *)coverForBook:(RDBookDetailModel *)book
{
    UIImage *customCover = [self customCoverForBook:book];
    if (customCover) {
        return customCover;
    }
    if (!book.isLocalBook) {
        return nil;
    }
    if (book.coverImg.length > 0) {
        NSString *path = [[self booksDirectory] stringByAppendingPathComponent:book.coverImg];
        UIImage *image = [UIImage imageWithContentsOfFile:path];
        if (image) {
            return image;
        }
    }
    return [self generateCoverWithTitle:book.title fileType:book.fileType];
}

//生成纸质风格封面:纸色底、细边框、竖排风格书名与格式角标
+ (UIImage *)generateCoverWithTitle:(NSString *)title fileType:(NSString *)fileType
{
    CGSize size = CGSizeMake(300, 420);
    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:size];
    return [renderer imageWithActions:^(UIGraphicsImageRendererContext *context) {
        //纸面
        [[UIColor colorWithHexValue:0xF3EDDF] setFill];
        [context fillRect:CGRectMake(0, 0, size.width, size.height)];
        //书脊阴影
        [[UIColor colorWithHexValue:0xE2D8C3] setFill];
        [context fillRect:CGRectMake(0, 0, 10, size.height)];
        //内边框
        [[UIColor colorWithHexValue:0xC9BCA0] setStroke];
        UIBezierPath *border = [UIBezierPath bezierPathWithRect:CGRectMake(24, 24, size.width - 48, size.height - 48)];
        border.lineWidth = 1.5;
        [border stroke];

        //书名(最多三行,衬线)
        NSMutableParagraphStyle *style = [[NSMutableParagraphStyle alloc] init];
        style.alignment = NSTextAlignmentCenter;
        style.lineSpacing = 8;
        style.lineBreakMode = NSLineBreakByTruncatingTail;
        NSDictionary *titleAttr = @{
            NSFontAttributeName: RDSerifBoldFont(30),
            NSForegroundColorAttributeName: [UIColor colorWithHexValue:0x3A322A],
            NSParagraphStyleAttributeName: style,
        };
        //书名居中偏上;格式信息由书架角标展示,封面不重复绘制
        NSString *name = title.length > 0 ? title : @"未命名";
        CGRect titleRect = CGRectMake(44, 110, size.width - 88, 200);
        [name drawWithRect:titleRect options:NSStringDrawingUsesLineFragmentOrigin attributes:titleAttr context:nil];
    }];
}

#pragma mark - 恢复备份

+ (NSArray *)parseChaptersForBook:(RDBookDetailModel *)book errorMessage:(NSString **)errorMessage
{
    return [self parseChaptersForBook:book atPath:[self absolutePathForBook:book] errorMessage:errorMessage];
}

+ (NSArray *)parseChaptersForBook:(RDBookDetailModel *)book
                           atPath:(NSString *)path
                     errorMessage:(NSString **)errorMessage
{
    if (!book.isLocalBook || [book.fileType isEqualToString:@"pdf"] || [RDComicHelper isComicFileType:book.fileType]) {
        return @[];   // PDF / 漫画图集无文字章节
    }
    if (!path || ![[NSFileManager defaultManager] fileExistsAtPath:path]) {
        if (errorMessage) *errorMessage = @"书籍文件缺失";
        return nil;
    }
    NSString *parseError = nil;
    RDLocalBookParseResult *result = nil;
    if ([book.fileType isEqualToString:@"txt"]) {
        result = [RDTxtBookParser parseFileAtPath:path error:&parseError];
    }
    else if ([book.fileType isEqualToString:@"epub"]) {
        result = [RDEpubBookParser parseFileAtPath:path error:&parseError];
    }
    else if ([book.fileType isEqualToString:@"mobi"]) {
        result = [RDMobiBookParser parseFileAtPath:path error:&parseError];
    }
    if (!result || result.chapters.count == 0) {
        if (errorMessage) *errorMessage = parseError ?: @"解析失败";
        return nil;
    }
    for (RDCharpterModel *chapter in result.chapters) {
        chapter.bookId = book.bookId;
        chapter.bookName = book.title;
        chapter.author = book.author;
    }
    //恢复当前阅读章节引用(找不到时退回第一章)。此时章节尚未落库,
    //只能在解析结果里查,写库统一交给 RDLibraryTransaction 一次提交。
    NSInteger charpterId = book.charpterModel.charpterId;
    RDCharpterModel *current = nil;
    if (charpterId > 0) {
        for (RDCharpterModel *chapter in result.chapters) {
            if (chapter.charpterId == charpterId) {
                current = chapter;
                break;
            }
        }
    }
    book.charpterModel = current ?: result.chapters.firstObject;
    return result.chapters;
}

#pragma mark - 删除

+ (void)removeLocalBook:(RDBookDetailModel *)book
{
    if (!book.isLocalBook) {
        return;
    }
    [self p_performSyncOnImportQueue:^{
        // 先删记录，迟到的相册任务会在保存前校验失败；整个文件生命周期与 PDF 回填串行。
        [RDReadRecordManager removeBookFromBookShelfWithBookId:book.bookId];

        NSString *filePath = [self absolutePathForBook:book];
        if (filePath) {
            [[NSFileManager defaultManager] removeItemAtPath:filePath error:nil];
        }
        if (book.coverImg.length > 0) {
            NSString *coverPath = [[self booksDirectory] stringByAppendingPathComponent:book.coverImg];
            [[NSFileManager defaultManager] removeItemAtPath:coverPath error:nil];
        }
        // 轻量书架对象可能仍指向旧封面名，额外清理确定性的新版 PDF 自动封面。
        if ([book.fileType.lowercaseString isEqualToString:@"pdf"] ||
            [book.localPath.pathExtension.lowercaseString isEqualToString:@"pdf"]) {
            NSString *pdfCoverName = [self p_pdfAutoCoverNameForBookId:book.bookId];
            NSString *pdfCoverPath = [[self booksDirectory] stringByAppendingPathComponent:pdfCoverName];
            [[NSFileManager defaultManager] removeItemAtPath:pdfCoverPath error:nil];
        }
        [self removeCustomCoverForBook:book];
        [RDBookmarkManager deleteAllForBookId:book.bookId];
        [RDHistoryRecordManager deleteHistoryWithBookId:book.bookId];
    }];
    // 章节表体积大、删除较慢，异步执行；但必须留在 import 串行队列内，
    // 否则"删除后立即重导"时,迟到的删除会跑到新导入之后,把刚插入的新章节清空。
    dispatch_async([self importQueue], ^{
        [RDCharpterDataManager deleteAllCharpterWithBookId:book.bookId];
    });
}

@end
