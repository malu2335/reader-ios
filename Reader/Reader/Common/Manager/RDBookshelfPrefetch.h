//
//  RDBookshelfPrefetch.h
//  Reader
//
//  启动阶段预加载书架数据,首屏直接出列表
//

#import <Foundation/Foundation.h>
@class RDBookDetailModel;

NS_ASSUME_NONNULL_BEGIN

extern NSString * const RDBookshelfPrefetchDidFinishNotification;

@interface RDBookshelfPrefetch : NSObject

/// 是否已完成至少一次预加载
@property (class, nonatomic, readonly) BOOL ready;
/// 轻量书籍列表(无章节正文)
@property (class, nonatomic, readonly, nullable) NSArray <RDBookDetailModel *>*books;
/// table 数据源行(空书架为 @"RDBookshelfNoneCell",否则为 NSArray 分组)
@property (class, nonatomic, readonly, nullable) NSArray *dataSourceRows;
/// 宫格分组
@property (class, nonatomic, readonly, nullable) NSArray <NSArray <RDBookDetailModel *>*>*bookGroups;

/// 在后台打开数据库 + 拉书架;complete 在主线程
+ (void)runWithComplete:(nullable void(^)(void))complete;

/// 失效缓存(导入/删除后);同时推进代次,尚在进行中的旧快照之后不能再提交覆盖
+ (void)invalidate;

/// 同步用最新库刷新缓存(后台),complete 主线程
+ (void)refreshAsync:(nullable void(^)(void))complete;

/// 领取一个刷新代次;必须在发起真正的慢读(DB 查询/PDF 封面回填)之前调用。
/// 多个调用方(controller 自身的 p_reload、prefetch 的后台刷新)各自独立发起刷新时,
/// 用代次保证"更晚开始的一次"最终生效,较慢完成的旧一轮不会在之后覆盖新结果。
+ (NSUInteger)beginRefreshGeneration;

/// 尝试用给定代次提交 books 快照;仅当该代次仍是最新时才真正写入缓存并返回 YES,
/// 否则说明已有更新的刷新在此期间开始,本次结果作废,返回 NO(调用方仍可放心读取
/// dataSourceRows/bookGroups 拿到最新已提交的快照)。
+ (BOOL)commitBooks:(NSArray <RDBookDetailModel *>*)books
            columns:(NSInteger)columns
         generation:(NSUInteger)generation;

/// 按列数组装 dataSource / groups(columns 一般为 3 或 5)
+ (void)buildRowsFromBooks:(NSArray <RDBookDetailModel *>*)books
                   columns:(NSInteger)columns
                dataSource:(NSArray * _Nonnull * _Nonnull)outRows
                    groups:(NSArray * _Nonnull * _Nonnull)outGroups;

@end

NS_ASSUME_NONNULL_END
