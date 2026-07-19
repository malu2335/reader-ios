//
//  RDLibraryMutationCoordinator.h
//  Reader
//
//  书库变更的唯一串行入口:导入、删除、清空、恢复、章节重建都在同一条队列上跑,
//  避免"删除后立即重导""恢复期间并发导入"这类交叉写(Oracle P1-01)。
//  职责只有排队与统一发通知——解析、SQL、UI 都不属于这里。
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface RDLibraryMutationCoordinator : NSObject

/// 变更串行队列;需要自行 dispatch_async 的调用方用它
+ (dispatch_queue_t)queue;

/// 同步进入队列(已在队列上时直接执行,不会自死锁)
+ (void)performSync:(dispatch_block_t)block;

/// 异步进入队列
+ (void)performAsync:(dispatch_block_t)block;

/// 当前是否已经在变更队列上
+ (BOOL)isOnQueue;

/// 在主线程发一次书库刷新通知。只应在整个变更完整提交后调用。
+ (void)postLibraryChanged:(nullable id)object;

@end

NS_ASSUME_NONNULL_END
