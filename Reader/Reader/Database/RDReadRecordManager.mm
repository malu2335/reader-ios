//
//  RDReadRecordManager.m
//  Reader
//

#import "RDReadRecordManager.h"
#import "RDBookDetailModel.h"
#import "RDBookDetailModel+WCTTableCoding.h"
#import "RDDatabaseManager.h"
#import "RDCharpterDataManager.h"
#import "RDCharpterModel.h"

@implementation RDReadRecordManager

+(void)insertOrReplaceModel:(RDBookDetailModel *)model
{
    model.readTime = [NSDate date].timeIntervalSince1970;
    [[RDDatabaseManager sharedInstance] performSync:^(WCTDatabase *db) {
        [db insertOrReplaceObject:model into:kReadRecordTable];
    }];
}

+(void)updateBookshelfState:(RDBookDetailModel *)model
{
    model.readTime = [NSDate date].timeIntervalSince1970;
    [[RDDatabaseManager sharedInstance] performSync:^(WCTDatabase *db) {
        [db updateRowsInTable:kReadRecordTable onProperties:{RDBookDetailModel.onBookshelf,RDBookDetailModel.readTime} withObject:model where:RDBookDetailModel.bookId.is(model.bookId)];
    }];
}

+(void)updateReadTime:(RDBookDetailModel *)model
{
    model.readTime = [NSDate date].timeIntervalSince1970;
    [[RDDatabaseManager sharedInstance] performSync:^(WCTDatabase *db) {
        [db updateRowsInTable:kReadRecordTable onProperties:RDBookDetailModel.readTime withObject:model where:RDBookDetailModel.bookId.is(model.bookId)];
    }];
}

+(RDBookDetailModel *)getReadRecordWithBookId:(NSInteger)bookid
{
    __block RDBookDetailModel *result = nil;
    [[RDDatabaseManager sharedInstance] performSync:^(WCTDatabase *db) {
        result = [db getOneObjectOfClass:RDBookDetailModel.class fromTable:kReadRecordTable where:RDBookDetailModel.bookId.is(bookid)];
    }];
    return result;
}

+(NSArray *)getAllOnBookshelf
{
    __block NSArray *result = nil;
    [[RDDatabaseManager sharedInstance] performSync:^(WCTDatabase *db) {
        result = [db getObjectsOfClass:RDBookDetailModel.class fromTable:kReadRecordTable where:RDBookDetailModel.onBookshelf.is(YES) orderBy:RDBookDetailModel.readTime.order(WCTOrderedDescending)];
    }];
    return result;
}

+(NSInteger)countOnBookshelf
{
    __block NSInteger count = 0;
    [[RDDatabaseManager sharedInstance] performSync:^(WCTDatabase *db) {
        // 只取 bookId,避免把 charpterModel 大字段全量反序列化
        NSArray *rows = [db getObjectsOnResults:{RDBookDetailModel.bookId}
                                      fromTable:kReadRecordTable
                                          where:RDBookDetailModel.onBookshelf.is(YES)];
        count = rows.count;
    }];
    return count;
}

+(NSArray *)getAllOnBookshelfPram
{
    __block NSArray *result = nil;
    [[RDDatabaseManager sharedInstance] performSync:^(WCTDatabase *db) {
        NSMutableArray *array = [NSMutableArray array];
        NSArray *books = [db getObjectsOfClass:RDBookDetailModel.class fromTable:kReadRecordTable where:RDBookDetailModel.onBookshelf.is(YES) orderBy:RDBookDetailModel.readTime.order(WCTOrderedDescending)];
        for (RDBookDetailModel *book in books) {
            if (book.isLocalBook) {
                continue;
            }
            RDCharpterModel *chapter = [RDCharpterDataManager getLastChapterWithBookId:book.bookId];
            if (!chapter || chapter.bookId==0) {
                continue;
            }
            [array addObjectSafely:chapter];
        }
        result = array.copy;
    }];
    return result;
}

+(void)removeBookFromBookShelfWithBookId:(NSInteger)bookid
{
    [[RDDatabaseManager sharedInstance] performSync:^(WCTDatabase *db) {
        [db deleteObjectsFromTable:kReadRecordTable where:RDBookDetailModel.bookId.is(bookid)];
    }];
}

+(void)updateOnBookselfUpdateWithBookId:(NSInteger)bookid update:(BOOL)update
{
    [[RDDatabaseManager sharedInstance] performSync:^(WCTDatabase *db) {
        [db updateRowsInTable:kReadRecordTable onProperty:RDBookDetailModel.bookUpdate withValue:@(update) where:RDBookDetailModel.bookId.is(bookid)];
    }];
}
@end
