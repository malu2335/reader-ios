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
    if (!zip) {
        return @[];
    }
    NSMutableArray *list = [NSMutableArray array];
    for (NSString *name in zip.entryNames) {
        if ([self p_shouldSkipEntryName:name]) {
            continue;
        }
        [list addObject:name];
    }
    [list sortUsingComparator:^NSComparisonResult(NSString *a, NSString *b) {
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
    if (data.length == 0) {
        return nil;
    }
    // 压缩后字节硬上限,避免超大条目进解码器
    if ((unsigned long long)data.length > kRDImportMaxComicImageBytes) {
        return nil;
    }

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
        }
        NSUInteger maxEdge = kRDImportMaxComicMaxPixelSize;
        if (pixelW > 0 && pixelH > 0) {
            unsigned long long pixels = (unsigned long long)pixelW * (unsigned long long)pixelH;
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

    // WebP 等 ImageIO 可能不支持:走 SDWebImage,仍受字节上限约束
    UIImage *image = [[SDImageCodersManager sharedManager] decodedImageWithData:data options:nil];
    if (image) {
        CGFloat w = image.size.width * image.scale;
        CGFloat h = image.size.height * image.scale;
        if (w > 0 && h > 0 && (unsigned long long)(w * h) > kRDImportMaxComicPixelCount) {
            // 超像素仍返回原图会 OOM;这里简单拒绝(常见 WebP 封面/页应能走 ImageIO 路径)
            return nil;
        }
        return image;
    }
    return nil;
}

@end
