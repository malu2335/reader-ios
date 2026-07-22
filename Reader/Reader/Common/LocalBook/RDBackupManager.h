//
//  RDBackupManager.h
//  Reader
//
//  备份与恢复,结构对齐 legado:zip 内含 bookshelf.json(书架+进度)、
//  config.json(阅读配置);另附 books/ 目录存放本地书籍源文件,恢复时重新解析章节。
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface RDBackupManager : NSObject

/// 生成备份 zip(后台执行,主线程回调),文件名 backupYYYY-MM-dd.zip
+ (void)createBackupWithComplete:(void(^)(NSString * _Nullable zipPath, NSString * _Nullable errorMessage))complete;

/// 从备份 zip 恢复(后台执行,主线程回调);同 bookId 的书会被覆盖
+ (void)restoreFromURL:(NSURL *)url complete:(void(^)(NSInteger bookCount, NSString * _Nullable errorMessage))complete;


/// 启动时回收中断的恢复:按持久化 journal 回滚「新文件已就位、DB 未提交」的书(P1-BE-01)
+ (void)recoverInterruptedRestoresIfNeeded;

@end

NS_ASSUME_NONNULL_END
