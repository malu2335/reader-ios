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

@end

NS_ASSUME_NONNULL_END
