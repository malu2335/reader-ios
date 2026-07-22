//
//  RDDatabaseLifecycle.h
//  Reader
//
//  纯 ObjC 可引用的 DB 生命周期接口(不暴露 WCDB/C++ 头,避免 .m 编译失败)
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface RDDatabaseLifecycle : NSObject

/// 后台截断 WAL,降低下次启动 recover frames
+ (void)checkpointWALAsync;

/// 进后台/退出时尽量同步 checkpoint(有超时)
+ (void)checkpointWALSync;

/// 建表/迁移失败时非空;书架错误态用(P2-DB-01 / Issue 8)。不暴露 WCDB 头。
+ (nullable NSError *)databaseInitializationError;

@end

NS_ASSUME_NONNULL_END
