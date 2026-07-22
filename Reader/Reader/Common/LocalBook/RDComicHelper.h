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

/// 漫画阅读方式
typedef NS_ENUM(NSInteger, RDComicReadMode) {
    RDComicReadModePageLTR = 0,  // 默认:横向翻页,左←右(点/滑左缘上一页)
    RDComicReadModePageRTL = 1,  // 日漫:横向翻页,右→左(点/滑右缘上一页,下一页在左侧)
    RDComicReadModeWebtoon = 2,  // 条漫:竖向连续滚动
};

@interface RDComicHelper : NSObject

/// jpg/jpeg/png/gif/webp/bmp/heic 等常见图片扩展名
+ (NSArray <NSString *>*)imageExtensions;

+ (BOOL)isImageFileName:(NSString *)name;

/// 漫画类本地书 fileType:cbz / zip / comic
+ (BOOL)isComicFileType:(NSString *)fileType;

/// 从 ZIP 条目中识别「多话」结构。
/// 每项: @{ @"charpterId": NSNumber, @"name": NSString, @"prefix": NSString, @"pageCount": NSNumber }
/// 不足 2 话时返回空数组(按整本图集处理)。
+ (NSArray <NSDictionary *>*)chapterInfosFromZipEntries:(NSArray <NSString *>*)imageEntries;

/// 章节 content 字段: comic 话元数据 JSON
+ (NSString *)comicChapterContentWithPrefix:(NSString *)prefix pageCount:(NSInteger)pageCount;
+ (nullable NSDictionary *)comicChapterInfoFromContent:(NSString *)content;
/// 按 prefix 过滤图片条目(保持原序)
+ (NSArray <NSString *>*)imageEntries:(NSArray <NSString *>*)entries withPrefix:(NSString *)prefix;

/// 全局默认漫画阅读方式(设置页)
+ (RDComicReadMode)defaultReadMode;
+ (void)setDefaultReadMode:(RDComicReadMode)mode;
/// 打开某书时使用的方式:该书若选过则用该书,否则用全局默认
+ (RDComicReadMode)readModeForBookId:(NSInteger)bookId;
/// 阅读中切换:写入该书记忆
+ (void)setReadMode:(RDComicReadMode)mode forBookId:(NSInteger)bookId;
+ (NSString *)displayNameForReadMode:(RDComicReadMode)mode;
+ (NSString *)detailForReadMode:(RDComicReadMode)mode;

/// 目录内是否含至少一张图片(递归)
+ (BOOL)directoryHasImagesAtPath:(NSString *)path;

/// 目录内全部图片相对路径,自然排序
+ (NSArray <NSString *>*)sortedImageRelativePathsInDirectory:(NSString *)path;

/// ZIP/CBZ 内图片条目名,自然排序(跳过 __MACOSX / 隐藏文件)
+ (NSArray <NSString *>*)sortedImageEntriesInZip:(RDZipArchive *)zip;
/// 仅收集 prefix 下的图片再排序(多话打开加速,避免对整包 3k+ 条目排序)
+ (NSArray <NSString *>*)sortedImageEntriesInZip:(RDZipArchive *)zip prefix:(nullable NSString *)prefix;

/// 将目录内图片打包为 store 方式的 zip(写入 zipPath)
+ (BOOL)packImageDirectory:(NSString *)dirPath
                 toZipPath:(NSString *)zipPath
                     error:(NSString * _Nullable * _Nullable)errorMessage;

/// 解码图片数据(含 WebP);优先 ImageIO 下采样 thumbnail,限制字节/像素预算,避免全分辨率主线程解码
+ (nullable UIImage *)imageFromData:(NSData *)data;
/// 按最长边上限解码(阅读页用屏宽×scale 即可,避免 4K 图拖垮主线程)
+ (nullable UIImage *)imageFromData:(NSData *)data maxPixelSize:(NSUInteger)maxPixelSize;

/// 自然序比较(数字友好,忽略大小写)
+ (NSComparisonResult)comparePaths:(NSString *)a to:(NSString *)b;

@end

NS_ASSUME_NONNULL_END
