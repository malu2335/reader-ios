//
//  RDLocalBookManager.m
//  Reader
//

#import "RDLocalBookManager.h"
#import <CommonCrypto/CommonDigest.h>
#import "RDBookDetailModel.h"
#import "RDCharpterModel.h"
#import "RDCharpterDataManager.h"
#import "RDReadRecordManager.h"
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

/// 导入专用串行队列:同内容文件并发导入时,去重检查与落盘天然互斥
+ (dispatch_queue_t)importQueue
{
    static dispatch_queue_t queue;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        queue = dispatch_queue_create("com.reader.localbook.import", DISPATCH_QUEUE_SERIAL);
    });
    return queue;
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
        book.total = [RDComicHelper isComicFileType:fileType] ? comicPageCount : result.chapters.count;

        if (result.chapters.count > 0) {
            for (RDCharpterModel *chapter in result.chapters) {
                chapter.bookId = bookId;
                chapter.bookName = book.title;
                chapter.author = book.author;
            }
            [RDCharpterDataManager insertObjectsWithCharpters:result.chapters];
            book.charpterModel = result.chapters.firstObject;
        }

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

        [RDReadRecordManager insertOrReplaceModel:book];
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

+ (UIImage *)coverForBook:(RDBookDetailModel *)book
{
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

+ (BOOL)rebuildChaptersForBook:(RDBookDetailModel *)book errorMessage:(NSString **)errorMessage
{
    if (!book.isLocalBook || [book.fileType isEqualToString:@"pdf"] || [RDComicHelper isComicFileType:book.fileType]) {
        return YES;   // PDF / 漫画图集无文字章节
    }
    NSString *path = [self absolutePathForBook:book];
    if (!path || ![[NSFileManager defaultManager] fileExistsAtPath:path]) {
        if (errorMessage) *errorMessage = @"书籍文件缺失";
        return NO;
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
        return NO;
    }
    for (RDCharpterModel *chapter in result.chapters) {
        chapter.bookId = book.bookId;
        chapter.bookName = book.title;
        chapter.author = book.author;
    }
    [RDCharpterDataManager deleteAllCharpterWithBookId:book.bookId];
    [RDCharpterDataManager insertObjectsWithCharpters:result.chapters];

    //恢复当前阅读章节引用(找不到时退回第一章)
    NSInteger charpterId = book.charpterModel.charpterId;
    RDCharpterModel *current = nil;
    if (charpterId > 0) {
        current = [RDCharpterDataManager getCharpterWithBookId:book.bookId charpterId:charpterId];
    }
    book.charpterModel = current ?: result.chapters.firstObject;
    return YES;
}

#pragma mark - 删除

+ (void)removeLocalBook:(RDBookDetailModel *)book
{
    if (!book.isLocalBook) {
        return;
    }
    NSString *filePath = [self absolutePathForBook:book];
    if (filePath) {
        [[NSFileManager defaultManager] removeItemAtPath:filePath error:nil];
    }
    if (book.coverImg.length > 0) {
        NSString *coverPath = [[self booksDirectory] stringByAppendingPathComponent:book.coverImg];
        [[NSFileManager defaultManager] removeItemAtPath:coverPath error:nil];
    }
    [RDReadRecordManager removeBookFromBookShelfWithBookId:book.bookId];
    [RDBookmarkManager deleteAllForBookId:book.bookId];
    [RDHistoryRecordManager deleteHistoryWithBookId:book.bookId];
    dispatch_async(dispatch_get_global_queue(0, 0), ^{
        [RDCharpterDataManager deleteAllCharpterWithBookId:book.bookId];
    });
}

@end
