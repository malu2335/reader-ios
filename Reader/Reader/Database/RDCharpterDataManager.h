//
//  RDCharpterDataManager.h
//  Reader
//
//  Created by yuenov on 2019/12/29.
//  Copyright © 2019 yuenov. All rights reserved.
//

#import <Foundation/Foundation.h>
@class RDCharpterModel;
NS_ASSUME_NONNULL_BEGIN

@interface RDCharpterDataManager : NSObject

/// 不包含章节内容的章节信息
+(NSArray *)getBriefCharptersWithBookId:(NSInteger)bookid;

/// 漫画话列表:id/name/content(小 JSON),一次查出,避免 N 次 getCharpter
+(NSArray *)getComicChapterRowsWithBookId:(NSInteger)bookid;

/// 有正文的章节 id 集合。只读 charpterId 列,不反序列化 content,
/// 供目录一次性判定"已下载"状态,避免每个可见 cell 各查一次全文(P2-03)。
+(NSSet<NSNumber *> *)charpterIdsWithContentForBookId:(NSInteger)bookid;

+(BOOL)isExsitWithBookId:(NSInteger)bookid;

+(BOOL)isExsitWithBookId:(NSInteger)bookid charpterId:(NSInteger)charpterId;

/// 获取章节信息
/// @param bookId bookid
/// @param charpterId charpterid
+(RDCharpterModel *)getCharpterWithBookId:(NSInteger)bookId charpterId:(NSInteger)charpterId;

/// 获取书籍的第一章Id
/// @param bookId 书籍Id
+(NSInteger)getFirstCharpterIdWirhBookId:(NSInteger)bookId;

/// 原子替换整本书的章节:同一事务内先删旧再插新。
/// 任一写失败即整体回滚,旧章节保持不变(P1-02)。
/// 注意:事务内必须逐条 insertOrReplaceObject:,禁止 insertOrReplaceObjects: 批量接口(WCDB 1.0.7 自死锁)。
+(BOOL)replaceChaptersForBookId:(NSInteger)bookId
                       chapters:(NSArray *)chapters
                          error:(NSError **)error;


/// 获取书籍的最后一章
/// @param bookId 书籍Id
+(RDCharpterModel *)getLastChapterWithBookId:(NSInteger)bookId;


/// 获取所有没有内容的章节
/// @param bookid 书籍Id
+(NSArray *)getAllNoContentCharpterWithBookId:(NSInteger)bookid;


/// 删除本地记录书籍
/// @param bookid 书籍Id
+(BOOL)deleteAllCharpterWithBookId:(NSInteger)bookid;
@end

NS_ASSUME_NONNULL_END
