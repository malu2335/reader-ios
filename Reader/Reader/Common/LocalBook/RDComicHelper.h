//
//  RDComicHelper.h
//  Reader
//
//  漫画/图集辅助:识别图片、扫描目录、解析 ZIP/CBZ 页序、文件夹打包。
//

#import <Foundation/Foundation.h>
@class RDZipArchive;
@class UIImage;

NS_ASSUME_NONNULL_BEGIN

@interface RDComicHelper : NSObject

/// jpg/jpeg/png/gif/webp/bmp/heic 等常见图片扩展名
+ (NSArray <NSString *>*)imageExtensions;

+ (BOOL)isImageFileName:(NSString *)name;

/// 漫画类本地书 fileType:cbz / zip / comic
+ (BOOL)isComicFileType:(NSString *)fileType;

/// 目录内是否含至少一张图片(递归)
+ (BOOL)directoryHasImagesAtPath:(NSString *)path;

/// 目录内全部图片相对路径,自然排序
+ (NSArray <NSString *>*)sortedImageRelativePathsInDirectory:(NSString *)path;

/// ZIP/CBZ 内图片条目名,自然排序(跳过 __MACOSX / 隐藏文件)
+ (NSArray <NSString *>*)sortedImageEntriesInZip:(RDZipArchive *)zip;

/// 将目录内图片打包为 store 方式的 zip(写入 zipPath)
+ (BOOL)packImageDirectory:(NSString *)dirPath
                 toZipPath:(NSString *)zipPath
                     error:(NSString * _Nullable * _Nullable)errorMessage;

/// 解码图片数据(含 WebP,依赖已注册的 SDWebImage coder)
+ (nullable UIImage *)imageFromData:(NSData *)data;

/// 自然序比较(数字友好,忽略大小写)
+ (NSComparisonResult)comparePaths:(NSString *)a to:(NSString *)b;

@end

NS_ASSUME_NONNULL_END
