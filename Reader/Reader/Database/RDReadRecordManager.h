//
//  RDReadRecordManager.h
//  Reader
//
//  Created by yuenov on 2020/1/31.
//  Copyright © 2020 yuenov. All rights reserved.
//

#import <Foundation/Foundation.h>

@class RDBookDetailModel;
NS_ASSUME_NONNULL_BEGIN

@interface RDReadRecordManager : NSObject

+(void)insertOrReplaceModel:(RDBookDetailModel *)model;

/// touchReadTime=NO 时保留 model.readTime(备份恢复等场景,不顶到书架最前)
+(void)insertOrReplaceModel:(RDBookDetailModel *)model touchReadTime:(BOOL)touchReadTime;

/// 阅读进度按列更新(章节引用/页码/字符偏移/章节名/阅读时间),不动其余列。
/// 行不存在时回退整行插入。翻页高频调用,禁止走整行 insertOrReplace。
+(void)updateProgressWithModel:(RDBookDetailModel *)model;

/// 仅改书名/作者,不触碰进度与 readTime(书架长按改名用)
+(void)updateTitle:(NSString *)title author:(NSString *)author forBookId:(NSInteger)bookId;

/// 仅改封面字段,不触碰进度、书名与 readTime(PDF 自动封面回填用)
+(BOOL)updateCoverImg:(NSString *)coverImg forBookId:(NSInteger)bookId;

/// PDF/漫画进度:仅 page+readTime,异步写(高频翻页不阻塞主线程)
+(void)asyncUpdatePage:(NSInteger)page forBookId:(NSInteger)bookId;

+(RDBookDetailModel *)getReadRecordWithBookId:(NSInteger)bookid;


+(void)updateReadTime:(RDBookDetailModel *)model;

+(void)updateBookshelfState:(RDBookDetailModel *)model;

+(void)removeBookFromBookShelfWithBookId:(NSInteger)bookid;

/// 获取所有书架上的书籍(含 charpterModel,较重)
+(NSArray *)getAllOnBookshelf;

/// 书架展示用轻量列表(不读 charpterModel 大字段,优先 readChapterName)
+(NSArray <RDBookDetailModel *>*)getBookshelfDisplayList;

/// 仅统计书架本数(不反序列化章节内容,设置页用)
+(NSInteger)countOnBookshelf;

/// 书架上的书籍是否有更新的章节
/// @param bookid
/// @param update 是否有更新的章节
+(void)updateOnBookselfUpdateWithBookId:(NSInteger)bookid update:(BOOL)update;

@end

NS_ASSUME_NONNULL_END
