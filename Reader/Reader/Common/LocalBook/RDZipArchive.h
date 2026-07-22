//
//  RDZipArchive.h
//  Reader
//
//  只读最小 ZIP 解析(stored / deflate),用于 EPUB,避免引入第三方解压库
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface RDZipArchive : NSObject

- (nullable instancetype)initWithPath:(NSString *)path;

@property (nonatomic,copy,readonly) NSArray <NSString *>*entryNames;

/// 精确名读取条目数据,失败返回 nil。
/// 默认单条目上限 200MB(通用硬上限)。
- (nullable NSData *)dataForEntry:(NSString *)name;

/// 同上,但在分配/inflate 前强制调用方预算(EPUB 单章 4MB、漫画 25MB 等)。
/// maxUncompressedBytes 为 0 时回退到通用硬上限。
- (nullable NSData *)dataForEntry:(NSString *)name maxUncompressedBytes:(unsigned long long)maxUncompressedBytes;

/// 中央目录声明的未压缩大小;条目不存在返回 0。可用于解压前预算预检。
- (unsigned long long)declaredUncompressedSizeForEntry:(NSString *)name;

/// 忽略大小写按名字查条目,找不到返回 nil
- (nullable NSString *)entryMatchingName:(NSString *)name;

/// 条目直接落盘(store 条目分块拷贝,不整包驻留内存;deflate 条目回退内存解压)
- (BOOL)writeEntry:(NSString *)name toFile:(NSString *)path;

@end

/// 只写 ZIP 生成器(store 不压缩),用于备份导出
@interface RDZipWriter : NSObject

- (nullable instancetype)initWithPath:(NSString *)path;

- (BOOL)addEntryWithName:(NSString *)name data:(NSData *)data;

/// 从磁盘文件流式添加条目(两遍分块读:先算 crc 再拷贝),大文件不整包进内存
- (BOOL)addEntryWithName:(NSString *)name fileAtPath:(NSString *)path;

/// 写中央目录并关闭文件,之后不可再添加条目
- (BOOL)finalizeArchive;

@end

NS_ASSUME_NONNULL_END
