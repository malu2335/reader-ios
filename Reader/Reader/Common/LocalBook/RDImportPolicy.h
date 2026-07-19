//
//  RDImportPolicy.h
//  Reader
//
//  导入/解析硬预算:按格式限制文件体积、解压后文本量、单章大小与图片像素,
//  防止超大或恶意构造文件导致 OOM / jetsam。数值以移动端可用内存为先。
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// TXT 整文件读取前的最大字节数(64MB)
static const unsigned long long kRDImportMaxTxtFileBytes = 64ull * 1024 * 1024;

/// MOBI 容器文件读取前的最大字节数(256MB;封面等使容器可大于正文上限)
static const unsigned long long kRDImportMaxMobiFileBytes = 256ull * 1024 * 1024;

/// MOBI 解压后正文累计硬上限(64MB);每次 append 前检查,非 capacity hint
static const unsigned long long kRDImportMaxMobiTextBytes = 64ull * 1024 * 1024;

/// EPUB 容器(ZIP)文件读取前的最大字节数(512MB)
static const unsigned long long kRDImportMaxEpubFileBytes = 512ull * 1024 * 1024;

/// EPUB 全部章节纯文本累计上限(64MB,UTF-16 字符按 2 字节粗估用 length 比较前先转字节)
static const unsigned long long kRDImportMaxEpubTotalTextBytes = 64ull * 1024 * 1024;

/// EPUB 单章节源(XHTML)解压后字节上限(4MB)
static const unsigned long long kRDImportMaxEpubChapterBytes = 4ull * 1024 * 1024;

/// 漫画单页压缩后/解压后数据上限(25MB);超过则拒绝解码
static const unsigned long long kRDImportMaxComicImageBytes = 25ull * 1024 * 1024;

/// 漫画解码后最长边像素上限(ImageIO thumbnail);约 4K 屏足够阅读
static const NSUInteger kRDImportMaxComicMaxPixelSize = 4096;

/// 漫画解码后宽×高像素总数硬上限(约 16MP)
static const unsigned long long kRDImportMaxComicPixelCount = 4096ull * 4096ull;

NS_ASSUME_NONNULL_END
