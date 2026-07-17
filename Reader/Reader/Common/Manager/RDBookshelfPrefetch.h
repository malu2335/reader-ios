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

/// 失效缓存(导入/删除后)
+ (void)invalidate;

/// 同步用最新库刷新缓存(后台),complete 主线程
+ (void)refreshAsync:(nullable void(^)(void))complete;

/// 用已有 books 更新内存缓存(主线程/后台均可)
+ (void)updateCacheWithBooks:(NSArray <RDBookDetailModel *>*)books columns:(NSInteger)columns;

/// 按列数组装 dataSource / groups(columns 一般为 3 或 5)
+ (void)buildRowsFromBooks:(NSArray <RDBookDetailModel *>*)books
                   columns:(NSInteger)columns
                dataSource:(NSArray * _Nonnull * _Nonnull)outRows
                    groups:(NSArray * _Nonnull * _Nonnull)outGroups;

@end

NS_ASSUME_NONNULL_END
