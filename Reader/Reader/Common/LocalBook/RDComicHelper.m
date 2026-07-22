//
//  RDComicHelper.m
//  Reader
//

#import "RDComicHelper.h"
#import "RDZipArchive.h"
#import "RDImportPolicy.h"
#import <UIKit/UIKit.h>
#import <ImageIO/ImageIO.h>
#import <SDWebImage/SDImageCodersManager.h>
#import <SDWebImage/SDImageCoder.h>

@implementation RDComicHelper

+ (NSArray <NSString *>*)imageExtensions
{
    return @[@"jpg", @"jpeg", @"png", @"gif", @"webp", @"bmp", @"heic", @"heif", @"tif", @"tiff"];
}

+ (BOOL)isImageFileName:(NSString *)name
{
    if (name.length == 0) {
        return NO;
    }
    NSString *base = name.lastPathComponent;
    if ([base hasPrefix:@"."]) {
        return NO;
    }
    NSString *ext = base.pathExtension.lowercaseString;
    return [[self imageExtensions] containsObject:ext];
}

+ (BOOL)isComicFileType:(NSString *)fileType
{
    NSString *t = fileType.lowercaseString;
    return [t isEqualToString:@"cbz"] || [t isEqualToString:@"zip"] || [t isEqualToString:@"comic"];
}

/// 尽量把 zip 路径里的乱码文件夹名解成可读标题;失败则回退 第N话
+ (NSString *)p_displayTitleForFolderName:(NSString *)folder indexHint:(NSInteger)indexHint
{
    if (folder.length == 0) {
        return [NSString stringWithFormat:@"第%ld话", (long)MAX(1, indexHint)];
    }
    NSString *decoded = folder;
    // 常见: CP437 误读的 UTF-8 / EUC-KR
    NSStringEncoding cp437 = CFStringConvertEncodingToNSStringEncoding(kCFStringEncodingDOSLatinUS);
    if (cp437 != kCFStringEncodingInvalidId) {
        NSData *raw = [folder dataUsingEncoding:cp437];
        if (raw.length) {
            for (NSNumber *encNum in @[
                @(NSUTF8StringEncoding),
                @(CFStringConvertEncodingToNSStringEncoding(kCFStringEncodingEUC_KR)),
                @(CFStringConvertEncodingToNSStringEncoding(kCFStringEncodingGB_18030_2000)),
                @(NSShiftJISStringEncoding),
            ]) {
                NSStringEncoding enc = encNum.unsignedIntegerValue;
                if (enc == kCFStringEncodingInvalidId || enc == 0) { continue; }
                NSString *try = [[NSString alloc] initWithData:raw encoding:enc];
                if (try.length > 0) {
                    decoded = try;
                    break;
                }
            }
        }
    }
    // 001_1화 / 001_1话 / 001
    NSRegularExpression *re = [NSRegularExpression regularExpressionWithPattern:@"^0*(\\d+)[_\\-\\s]*(.*)$" options:0 error:nil];
    NSTextCheckingResult *m = [re firstMatchInString:decoded options:0 range:NSMakeRange(0, decoded.length)];
    if (m && m.numberOfRanges >= 3) {
        NSInteger num = [[decoded substringWithRange:[m rangeAtIndex:1]] integerValue];
        NSString *rest = [[decoded substringWithRange:[m rangeAtIndex:2]] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (rest.length == 0) {
            return [NSString stringWithFormat:@"第%ld话", (long)MAX(1, num)];
        }
        NSRegularExpression *re2 = [NSRegularExpression regularExpressionWithPattern:@"^0*(\\d+)\\s*(화|话|話|章|回)?$" options:0 error:nil];
        NSTextCheckingResult *m2 = [re2 firstMatchInString:rest options:0 range:NSMakeRange(0, rest.length)];
        if (m2) {
            NSInteger n2 = [[rest substringWithRange:[m2 rangeAtIndex:1]] integerValue];
            return [NSString stringWithFormat:@"第%ld话", (long)MAX(1, n2)];
        }
        // 保留可读后缀
        return rest;
    }
    NSRegularExpression *numRe = [NSRegularExpression regularExpressionWithPattern:@"(\\d+)" options:0 error:nil];
    NSTextCheckingResult *nm = [numRe firstMatchInString:decoded options:0 range:NSMakeRange(0, decoded.length)];
    if (nm) {
        NSInteger num = [[decoded substringWithRange:nm.range] integerValue];
        return [NSString stringWithFormat:@"第%ld话", (long)MAX(1, num)];
    }
    return decoded;
}

+ (NSArray <NSDictionary *>*)chapterInfosFromZipEntries:(NSArray <NSString *>*)imageEntries
{
    if (imageEntries.count < 2) {
        return @[];
    }
    // parent -> entries
    NSMutableDictionary <NSString *, NSMutableArray <NSString *>*>*byParent = [NSMutableDictionary dictionary];
    for (NSString *entry in imageEntries) {
        if (entry.length == 0) { continue; }
        NSString *parent = entry.stringByDeletingLastPathComponent;
        if (parent.length == 0) {
            parent = @".";
        }
        NSMutableArray *list = byParent[parent];
        if (!list) {
            list = [NSMutableArray array];
            byParent[parent] = list;
        }
        [list addObject:entry];
    }
    if (byParent.count < 2) {
        return @[]; // 单目录/扁平图集,不拆话
    }
    // 要求多数 parent 共享同一 grandparent,避免误拆
    NSMutableDictionary <NSString *, NSNumber *>*grandCounts = [NSMutableDictionary dictionary];
    for (NSString *parent in byParent) {
        NSString *grand = parent.stringByDeletingLastPathComponent;
        if (grand.length == 0) { grand = @"."; }
        grandCounts[grand] = @((grandCounts[grand] ?: @0).integerValue + 1);
    }
    NSString *bestGrand = nil;
    NSInteger bestCount = 0;
    for (NSString *g in grandCounts) {
        NSInteger c = grandCounts[g].integerValue;
        if (c > bestCount) {
            bestCount = c;
            bestGrand = g;
        }
    }
    if (bestCount < 2) {
        return @[];
    }
    NSMutableArray <NSString *>*chapterParents = [NSMutableArray array];
    for (NSString *parent in byParent) {
        NSString *grand = parent.stringByDeletingLastPathComponent;
        if (grand.length == 0) { grand = @"."; }
        if ([grand isEqualToString:bestGrand] && byParent[parent].count > 0) {
            [chapterParents addObject:parent];
        }
    }
    if (chapterParents.count < 2) {
        return @[];
    }
    [chapterParents sortUsingComparator:^NSComparisonResult(NSString *a, NSString *b) {
        return [self comparePaths:a.lastPathComponent to:b.lastPathComponent];
    }];

    NSMutableArray <NSDictionary *>*infos = [NSMutableArray arrayWithCapacity:chapterParents.count];
    NSInteger fallbackIndex = 1;
    for (NSString *parent in chapterParents) {
        NSArray <NSString *>*entries = [byParent[parent] sortedArrayUsingComparator:^NSComparisonResult(NSString *a, NSString *b) {
            return [self comparePaths:a.lastPathComponent to:b.lastPathComponent];
        }];
        NSString *folder = parent.lastPathComponent;
        // charpterId: 优先文件夹名前导数字
        NSInteger cid = fallbackIndex;
        NSRegularExpression *re = [NSRegularExpression regularExpressionWithPattern:@"(\\d+)" options:0 error:nil];
        NSTextCheckingResult *m = [re firstMatchInString:folder options:0 range:NSMakeRange(0, folder.length)];
        if (m) {
            cid = [[folder substringWithRange:m.range] integerValue];
            if (cid <= 0) { cid = fallbackIndex; }
        }
        NSString *name = [self p_displayTitleForFolderName:folder indexHint:cid];
        NSString *prefix = [parent hasSuffix:@"/"] ? parent : [parent stringByAppendingString:@"/"];
        if ([parent isEqualToString:@"."]) {
            prefix = @"";
        }
        [infos addObject:@{
            @"charpterId": @(cid),
            @"name": name ?: [NSString stringWithFormat:@"第%ld话", (long)cid],
            @"prefix": prefix,
            @"pageCount": @(entries.count),
        }];
        fallbackIndex++;
    }
    // charpterId 去重:若碰撞则按顺序重编号
    NSMutableSet *used = [NSMutableSet set];
    BOOL collision = NO;
    for (NSDictionary *info in infos) {
        NSNumber *cid = info[@"charpterId"];
        if ([used containsObject:cid]) { collision = YES; break; }
        [used addObject:cid];
    }
    if (collision) {
        NSInteger i = 1;
        NSMutableArray *fixed = [NSMutableArray arrayWithCapacity:infos.count];
        for (NSDictionary *info in infos) {
            NSMutableDictionary *m = [info mutableCopy];
            m[@"charpterId"] = @(i);
            if (![m[@"name"] isKindOfClass:NSString.class] || [m[@"name"] length] == 0) {
                m[@"name"] = [NSString stringWithFormat:@"第%ld话", (long)i];
            }
            [fixed addObject:m];
            i++;
        }
        return fixed;
    }
    return infos.copy;
}

+ (NSString *)comicChapterContentWithPrefix:(NSString *)prefix pageCount:(NSInteger)pageCount
{
    NSDictionary *dict = @{
        @"v": @1,
        @"comicPrefix": prefix ?: @"",
        @"pageCount": @(MAX(0, pageCount)),
    };
    NSData *data = [NSJSONSerialization dataWithJSONObject:dict options:0 error:nil];
    if (!data) { return @""; }
    return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] ?: @"";
}

+ (NSDictionary *)comicChapterInfoFromContent:(NSString *)content
{
    if (content.length == 0) { return nil; }
    NSData *data = [content dataUsingEncoding:NSUTF8StringEncoding];
    if (!data) { return nil; }
    id obj = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    if (![obj isKindOfClass:NSDictionary.class]) { return nil; }
    NSDictionary *dict = obj;
    if (![dict[@"comicPrefix"] isKindOfClass:NSString.class] && dict[@"prefix"] == nil) {
        // 兼容:纯 prefix 字符串(非 JSON)也可
        return nil;
    }
    NSString *prefix = dict[@"comicPrefix"] ?: dict[@"prefix"] ?: @"";
    NSInteger count = [dict[@"pageCount"] integerValue];
    return @{ @"prefix": prefix, @"pageCount": @(count) };
}

+ (NSArray <NSString *>*)imageEntries:(NSArray <NSString *>*)entries withPrefix:(NSString *)prefix
{
    if (prefix.length == 0) {
        return entries ?: @[];
    }
    NSMutableArray *out = [NSMutableArray array];
    for (NSString *e in entries) {
        if ([e hasPrefix:prefix]) {
            [out addObject:e];
        }
    }
    return out.copy;
}

static NSString * const kRDComicDefaultReadModeKey = @"RDComicDefaultReadMode";
static NSString *RDComicBookModeKey(NSInteger bookId) {
    return [NSString stringWithFormat:@"RDComicBookReadMode.%ld", (long)bookId];
}

+ (RDComicReadMode)p_sanitizedMode:(NSInteger)raw
{
    if (raw == RDComicReadModePageRTL || raw == RDComicReadModeWebtoon) {
        return (RDComicReadMode)raw;
    }
    return RDComicReadModePageLTR;
}

+ (RDComicReadMode)defaultReadMode
{
    NSNumber *n = [[NSUserDefaults standardUserDefaults] objectForKey:kRDComicDefaultReadModeKey];
    if (!n) {
        return RDComicReadModePageLTR;
    }
    return [self p_sanitizedMode:n.integerValue];
}

+ (void)setDefaultReadMode:(RDComicReadMode)mode
{
    mode = [self p_sanitizedMode:mode];
    [[NSUserDefaults standardUserDefaults] setInteger:mode forKey:kRDComicDefaultReadModeKey];
}

+ (RDComicReadMode)readModeForBookId:(NSInteger)bookId
{
    NSString *key = RDComicBookModeKey(bookId);
    id obj = [[NSUserDefaults standardUserDefaults] objectForKey:key];
    if (obj) {
        return [self p_sanitizedMode:[obj integerValue]];
    }
    return [self defaultReadMode];
}

+ (void)setReadMode:(RDComicReadMode)mode forBookId:(NSInteger)bookId
{
    mode = [self p_sanitizedMode:mode];
    [[NSUserDefaults standardUserDefaults] setInteger:mode forKey:RDComicBookModeKey(bookId)];
}

+ (NSString *)displayNameForReadMode:(RDComicReadMode)mode
{
    switch ([self p_sanitizedMode:mode]) {
        case RDComicReadModePageRTL: return @"日漫";
        case RDComicReadModeWebtoon: return @"条漫";
        case RDComicReadModePageLTR:
        default: return @"默认";
    }
}

+ (NSString *)detailForReadMode:(RDComicReadMode)mode
{
    switch ([self p_sanitizedMode:mode]) {
        case RDComicReadModePageRTL: return @"右→左翻页 · 适合日漫";
        case RDComicReadModeWebtoon: return @"竖向连续 · 适合条漫";
        case RDComicReadModePageLTR:
        default: return @"左→右翻页 · 适合图集/美漫";
    }
}

+ (BOOL)p_shouldSkipPathComponent:(NSString *)component
{
    if (component.length == 0) {
        return YES;
    }
    if ([component hasPrefix:@"."]) {
        return YES;
    }
    if ([component isEqualToString:@"__MACOSX"]) {
        return YES;
    }
    return NO;
}

+ (BOOL)p_shouldSkipEntryName:(NSString *)name
{
    if (name.length == 0 || [name hasSuffix:@"/"]) {
        return YES;
    }
    NSArray <NSString *>*parts = [name componentsSeparatedByString:@"/"];
    for (NSString *part in parts) {
        if ([self p_shouldSkipPathComponent:part]) {
            return YES;
        }
    }
    return ![self isImageFileName:name];
}

+ (NSComparisonResult)comparePaths:(NSString *)a to:(NSString *)b
{
    return [a compare:b options:(NSCaseInsensitiveSearch | NSNumericSearch | NSWidthInsensitiveSearch | NSForcedOrderingSearch)];
}

+ (void)p_collectImagesAtPath:(NSString *)path
                 relativeBase:(NSString *)base
                       into:(NSMutableArray <NSString *>*)out
{
    NSFileManager *fm = [NSFileManager defaultManager];
    NSArray <NSString *>*children = [fm contentsOfDirectoryAtPath:path error:nil];
    if (children.count == 0) {
        return;
    }
    children = [children sortedArrayUsingComparator:^NSComparisonResult(NSString *x, NSString *y) {
        return [self comparePaths:x to:y];
    }];
    for (NSString *name in children) {
        if ([self p_shouldSkipPathComponent:name]) {
            continue;
        }
        NSString *full = [path stringByAppendingPathComponent:name];
        NSString *rel = base.length > 0 ? [base stringByAppendingPathComponent:name] : name;
        BOOL isDir = NO;
        if (![fm fileExistsAtPath:full isDirectory:&isDir]) {
            continue;
        }
        if (isDir) {
            [self p_collectImagesAtPath:full relativeBase:rel into:out];
        } else if ([self isImageFileName:name]) {
            [out addObject:rel];
        }
    }
}

+ (NSArray <NSString *>*)sortedImageRelativePathsInDirectory:(NSString *)path
{
    NSMutableArray *list = [NSMutableArray array];
    [self p_collectImagesAtPath:path relativeBase:@"" into:list];
    [list sortUsingComparator:^NSComparisonResult(NSString *a, NSString *b) {
        return [self comparePaths:a to:b];
    }];
    return list.copy;
}

+ (BOOL)directoryHasImagesAtPath:(NSString *)path
{
    return [self sortedImageRelativePathsInDirectory:path].count > 0;
}

+ (NSArray <NSString *>*)sortedImageEntriesInZip:(RDZipArchive *)zip
{
    return [self sortedImageEntriesInZip:zip prefix:nil];
}

+ (NSArray <NSString *>*)sortedImageEntriesInZip:(RDZipArchive *)zip prefix:(NSString *)prefix
{
    if (!zip) {
        return @[];
    }
    NSMutableArray *list = [NSMutableArray array];
    BOOL hasPrefix = prefix.length > 0;
    for (NSString *name in zip.entryNames) {
        if (hasPrefix && ![name hasPrefix:prefix]) {
            continue;
        }
        if ([self p_shouldSkipEntryName:name]) {
            continue;
        }
        [list addObject:name];
    }
    [list sortUsingComparator:^NSComparisonResult(NSString *a, NSString *b) {
        // 同目录内按文件名比即可,比全路径自然序更快
        if (hasPrefix) {
            return [self comparePaths:a.lastPathComponent to:b.lastPathComponent];
        }
        return [self comparePaths:a to:b];
    }];
    return list.copy;
}

+ (BOOL)packImageDirectory:(NSString *)dirPath
                 toZipPath:(NSString *)zipPath
                     error:(NSString **)errorMessage
{
    NSArray <NSString *>*images = [self sortedImageRelativePathsInDirectory:dirPath];
    if (images.count == 0) {
        if (errorMessage) {
            *errorMessage = @"文件夹中没有可导入的图片";
        }
        return NO;
    }
    RDZipWriter *writer = [[RDZipWriter alloc] initWithPath:zipPath];
    if (!writer) {
        if (errorMessage) {
            *errorMessage = @"创建压缩包失败";
        }
        return NO;
    }
    for (NSString *rel in images) {
        NSString *full = [dirPath stringByAppendingPathComponent:rel];
        NSData *data = [NSData dataWithContentsOfFile:full options:NSDataReadingMappedIfSafe error:nil];
        if (data.length == 0) {
            continue;
        }
        // ZIP 条目统一用 / 分隔,避免 Windows 反斜杠
        NSString *entry = [[rel stringByReplacingOccurrencesOfString:@"\\" withString:@"/"]
                           stringByReplacingOccurrencesOfString:@":" withString:@"_"];
        if (![writer addEntryWithName:entry data:data]) {
            if (errorMessage) {
                *errorMessage = @"写入图片到压缩包失败";
            }
            return NO;
        }
    }
    if (![writer finalizeArchive]) {
        if (errorMessage) {
            *errorMessage = @"完成压缩包失败";
        }
        return NO;
    }
    // 至少应有内容
    NSDictionary *attrs = [[NSFileManager defaultManager] attributesOfItemAtPath:zipPath error:nil];
    if ([attrs fileSize] == 0) {
        if (errorMessage) {
            *errorMessage = @"文件夹中没有可读图片";
        }
        return NO;
    }
    return YES;
}

+ (UIImage *)imageFromData:(NSData *)data
{
    return [self imageFromData:data maxPixelSize:kRDImportMaxComicMaxPixelSize];
}

+ (UIImage *)imageFromData:(NSData *)data maxPixelSize:(NSUInteger)maxPixelSize
{
    if (data.length == 0) {
        return nil;
    }
    // 压缩后字节硬上限,避免超大条目进解码器
    if ((unsigned long long)data.length > kRDImportMaxComicImageBytes) {
        return nil;
    }

    NSUInteger maxEdge = maxPixelSize > 0 ? MIN(maxPixelSize, kRDImportMaxComicMaxPixelSize) : kRDImportMaxComicMaxPixelSize;

    // 优先 ImageIO thumbnail:按最长边/像素总数下采样,避免主线程全分辨率解码与像素炸弹
    CGImageSourceRef source = CGImageSourceCreateWithData((__bridge CFDataRef)data, NULL);
    if (source) {
        CFDictionaryRef props = CGImageSourceCopyPropertiesAtIndex(source, 0, NULL);
        NSUInteger pixelW = 0, pixelH = 0;
        if (props) {
            NSNumber *w = (__bridge NSNumber *)CFDictionaryGetValue(props, kCGImagePropertyPixelWidth);
            NSNumber *h = (__bridge NSNumber *)CFDictionaryGetValue(props, kCGImagePropertyPixelHeight);
            pixelW = w.unsignedIntegerValue;
            pixelH = h.unsignedIntegerValue;
            CFRelease(props);
        }
        if (pixelW > 0 && pixelH > 0) {
            unsigned long long pixels = (unsigned long long)pixelW * (unsigned long long)pixelH;
            if (pixels > kRDImportMaxComicPixelCount * 64ull) {
                // 声明尺寸极端离谱(如 100000×100000)直接拒绝,连 thumbnail 也不尝试
                CFRelease(source);
                return nil;
            }
            if (pixels > kRDImportMaxComicPixelCount) {
                // 等比缩到像素总数上限内
                double scale = sqrt((double)kRDImportMaxComicPixelCount / (double)pixels);
                NSUInteger scaledEdge = (NSUInteger)(MAX(pixelW, pixelH) * scale);
                if (scaledEdge > 0 && scaledEdge < maxEdge) {
                    maxEdge = scaledEdge;
                }
            }
        }
        NSDictionary *options = @{
            (id)kCGImageSourceCreateThumbnailFromImageAlways: @YES,
            (id)kCGImageSourceCreateThumbnailWithTransform: @YES,
            (id)kCGImageSourceThumbnailMaxPixelSize: @(maxEdge),
            (id)kCGImageSourceShouldCacheImmediately: @YES,
        };
        CGImageRef thumb = CGImageSourceCreateThumbnailAtIndex(source, 0, (__bridge CFDictionaryRef)options);
        CFRelease(source);
        if (thumb) {
            UIImage *image = [UIImage imageWithCGImage:thumb scale:1.0 orientation:UIImageOrientationUp];
            CGImageRelease(thumb);
            if (image) {
                return image;
            }
        }
    }

    // WebP 等 ImageIO 可能不支持:用 SDWebImage thumbnail 选项下采样,禁止全分辨率解码后再拒绝
    CGFloat thumbEdge = (CGFloat)maxEdge;
    NSDictionary *sdOptions = @{
        SDImageCoderDecodeThumbnailPixelSize: [NSValue valueWithCGSize:CGSizeMake(thumbEdge, thumbEdge)],
        SDImageCoderDecodePreserveAspectRatio: @YES,
        SDImageCoderDecodeFirstFrameOnly: @YES,
    };
    UIImage *image = [[SDImageCodersManager sharedManager] decodedImageWithData:data options:sdOptions];
    if (image) {
        // 用整数像素乘积再比上限,避免 CGFloat 先乘后截断/非有限值
        NSUInteger pxW = (NSUInteger)llround(image.size.width * image.scale);
        NSUInteger pxH = (NSUInteger)llround(image.size.height * image.scale);
        if (pxW > 0 && pxH > 0) {
            unsigned long long pixels = (unsigned long long)pxW * (unsigned long long)pxH;
            if (pixels > kRDImportMaxComicPixelCount) {
                return nil;
            }
        }
        return image;
    }
    return nil;
}

@end
