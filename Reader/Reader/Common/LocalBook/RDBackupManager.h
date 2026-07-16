//
//  RDBackupManager.h
//  Reader
//
//  备份与恢复,结构对齐 legado:zip 内含 bookshelf.json(书架+进度)、
//  config.json(阅读配置);另附 books/ 目录存放本地书籍源文件,恢复时重新解析章节。
//  附加 ai_config.json(AI 翻译配置,与 legado 目录兼容的扩展项)。
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface RDBackupManager : NSObject

/// 生成备份 zip(后台执行,主线程回调),文件名 backupYYYY-MM-dd.zip
+ (void)createBackupWithComplete:(void(^)(NSString * _Nullable zipPath, NSString * _Nullable errorMessage))complete;

/// 从备份 zip 恢复(后台执行,主线程回调);同 bookId 的书会被覆盖
+ (void)restoreFromURL:(NSURL *)url complete:(void(^)(NSInteger bookCount, NSString * _Nullable errorMessage))complete;

/// AI 配置在 zip 中的条目名(与 RDAIConfigBackupEntryName 一致)
+ (NSString *)aiConfigEntryName;

/// 导出当前 AI 配置为备份 data(无配置时返回空 profiles 的合法 JSON)
+ (nullable NSData *)aiConfigBackupData;

/// 从备份 data 恢复 AI 配置
+ (BOOL)restoreAIConfigFromData:(nullable NSData *)data error:(NSError * _Nullable * _Nullable)error;

/// 纯逻辑:把 AI 配置写入已打开的 zip writer(备份路径共用,便于单测)
+ (BOOL)writeAIConfigToZipWriter:(id)writer;

/// 从已打开的 zip 读取并恢复 AI 配置(条目可缺省)
+ (void)restoreAIConfigFromZip:(id)zip;

@end

NS_ASSUME_NONNULL_END
