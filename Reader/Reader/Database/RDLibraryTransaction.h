//
//  RDLibraryTransaction.h
//  Reader
//
//  书库级原子写入:把"章节表 + 读记录表"这类跨表提交收进单次数据库事务,
//  任一步失败整体回滚,调用方据返回值决定是否报成功、是否发通知(Oracle P1-02)。
//

#import <Foundation/Foundation.h>

@class RDBookDetailModel;

NS_ASSUME_NONNULL_BEGIN

@interface RDLibraryTransaction : NSObject

/// 提交一本书的导入/恢复:同一事务内替换该书全部章节并写入读记录。
/// @param book 读记录行(bookId 必须已赋值)
/// @param chapters 完整章节数组;PDF/漫画传空数组
/// @param touchReadTime NO 时保留 book.readTime(恢复备份用,不顶到书架最前)
+ (BOOL)commitBook:(RDBookDetailModel *)book
          chapters:(nullable NSArray *)chapters
     touchReadTime:(BOOL)touchReadTime
             error:(NSError **)error;

/// 单书四表(read/chapter/bookmark/history)同事务删除;失败整体回滚(P1-BE-02)
+ (BOOL)deleteAllRecordsForBookId:(NSInteger)bookId error:(NSError * _Nullable * _Nullable)error;

@end

NS_ASSUME_NONNULL_END
