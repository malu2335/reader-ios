//
//  RDCharpterDataManager.m
//  Reader
//

#import "RDCharpterDataManager.h"
#import "RDCharpterDataManager+DBInternal.h"
#import "RDDatabaseManager.h"
#import "RDCharpterModel.h"
#import "RDCharpterModel+WCTTableCoding.h"

@implementation RDCharpterDataManager

+(NSArray *)getBriefCharptersWithBookId:(NSInteger)bookid{
    __block NSArray *result = nil;
    [[RDDatabaseManager sharedInstance] performSync:^(WCTDatabase *db) {
        result = [db getObjectsOnResults:{RDCharpterModel.charpterId,RDCharpterModel.name,RDCharpterModel.bookId} fromTable:kCharpterTable where:RDCharpterModel.bookId.is(bookid) orderBy:RDCharpterModel.charpterId.order(WCTOrderedAscending)];
    }];
    return result;
}

+(NSArray *)getComicChapterRowsWithBookId:(NSInteger)bookid
{
    __block NSArray *result = nil;
    [[RDDatabaseManager sharedInstance] performSync:^(WCTDatabase *db) {
        result = [db getObjectsOnResults:{RDCharpterModel.charpterId,
                                          RDCharpterModel.name,
                                          RDCharpterModel.content,
                                          RDCharpterModel.bookId}
                               fromTable:kCharpterTable
                                   where:RDCharpterModel.bookId.is(bookid)
                                 orderBy:RDCharpterModel.charpterId.order(WCTOrderedAscending)];
    }];
    return result;
}

+(NSSet<NSNumber *> *)charpterIdsWithContentForBookId:(NSInteger)bookid
{
    NSMutableSet <NSNumber *>*ids = [NSMutableSet set];
    [[RDDatabaseManager sharedInstance] performSync:^(WCTDatabase *db) {
        NSArray *rows = [db getObjectsOnResults:{RDCharpterModel.charpterId}
                                      fromTable:kCharpterTable
                                          where:RDCharpterModel.bookId.is(bookid)
                                                && !RDCharpterModel.content.isNull()
                                                && RDCharpterModel.content.length() > 0];
        for (RDCharpterModel *row in rows) {
            [ids addObject:@(row.charpterId)];
        }
    }];
    return ids;
}

+(BOOL)isExsitWithBookId:(NSInteger)bookid
{
    __block BOOL exist = NO;
    [[RDDatabaseManager sharedInstance] performSync:^(WCTDatabase *db) {
        RDCharpterModel *model = [db getOneObjectOnResults:{RDCharpterModel.primaryId} fromTable:kCharpterTable where:RDCharpterModel.bookId.is(bookid)];
        exist = model != nil;
    }];
    return exist;
}

+(BOOL)isExsitWithBookId:(NSInteger)bookid charpterId:(NSInteger)charpterId
{
    __block BOOL exist = NO;
    [[RDDatabaseManager sharedInstance] performSync:^(WCTDatabase *db) {
        RDCharpterModel *model = [db getOneObjectOnResults:{RDCharpterModel.primaryId} fromTable:kCharpterTable where:RDCharpterModel.bookId.is(bookid)&&RDCharpterModel.charpterId.is(charpterId)];
        exist = model != nil;
    }];
    return exist;
}

+(RDCharpterModel *)getCharpterWithBookId:(NSInteger)bookId charpterId:(NSInteger)charpterId
{
    __block RDCharpterModel *result = nil;
    [[RDDatabaseManager sharedInstance] performSync:^(WCTDatabase *db) {
        result = [db getOneObjectOfClass:RDCharpterModel.class fromTable:kCharpterTable where:RDCharpterModel.bookId.is(bookId)&&RDCharpterModel.charpterId.is(charpterId)];
    }];
    return result;
}

+(NSInteger)getFirstCharpterIdWirhBookId:(NSInteger)bookId
{
    __block NSInteger cid = 0;
    [[RDDatabaseManager sharedInstance] performSync:^(WCTDatabase *db) {
        cid = [[db getOneValueOnResult:RDCharpterModel.charpterId.min() fromTable:kCharpterTable where:RDCharpterModel.bookId.is(bookId)] integerValue];
    }];
    return cid;
}

+(BOOL)updateCharpterContentWithModel:(RDCharpterModel *)model
{
    __block BOOL success = NO;
    [[RDDatabaseManager sharedInstance] performSync:^(WCTDatabase *db) {
        success = [db updateRowsInTable:kCharpterTable onProperty:RDCharpterModel.content withObject:model where:RDCharpterModel.bookId.is(model.bookId)&&RDCharpterModel.charpterId.is(model.charpterId)];
    }];
    return success;
}

+(BOOL)insertObjectWithCharpters:(RDCharpterModel *)charpter
{
    __block BOOL success = NO;
    [[RDDatabaseManager sharedInstance] performSync:^(WCTDatabase *db) {
        charpter.primaryId = [NSString stringWithFormat:@"%@_%@", @(charpter.bookId), @(charpter.charpterId)];
        success = [db insertOrReplaceObject:charpter into:kCharpterTable];
    }];
    return success;
}

+(BOOL)db_replaceChaptersForBookId:(NSInteger)bookId
                          chapters:(NSArray *)chapters
                        inDatabase:(WCTInterface *)db
{
    if (![db deleteObjectsFromTable:kCharpterTable where:RDCharpterModel.bookId.is(bookId)]) {
        return NO;
    }
    if (chapters.count == 0) {
        return YES;
    }
    // 必须逐条 insertOrReplaceObject。禁止事务内 plural 批量 insert:
    // WCDB 1.0.7 的 WCTInsert 在 objects.count > 1 时会走 runEmbeddedTransaction,
    // 而 WCDB::Transaction::runEmbeddedTransaction 持有 m_mutex 的同时执行 block,
    // block 内的 prepare() 又要锁同一个非递归 mutex —— 在已开启的事务句柄上必然自死锁。
    // (真机复现:导入 8 章的 txt 时整条 dbQueue 卡死,文件已落盘但两张表都没写入。)
    for (RDCharpterModel *chapter in chapters) {
        chapter.bookId = bookId;
        chapter.primaryId = [NSString stringWithFormat:@"%@_%@", @(chapter.bookId), @(chapter.charpterId)];
        if (![db insertOrReplaceObject:chapter into:kCharpterTable]) {
            return NO;
        }
    }
    return YES;
}

+(BOOL)replaceChaptersForBookId:(NSInteger)bookId
                       chapters:(NSArray *)chapters
                          error:(NSError **)error
{
    return [[RDDatabaseManager sharedInstance] performTransactionSync:^BOOL(WCTInterface *db) {
        return [self db_replaceChaptersForBookId:bookId chapters:chapters inDatabase:db];
    } error:error];
}

+(NSArray *)getAllNoContentCharpterWithBookId:(NSInteger)bookid
{
    __block NSArray *result = nil;
    [[RDDatabaseManager sharedInstance] performSync:^(WCTDatabase *db) {
        result = [db getObjectsOfClass:RDCharpterModel.class fromTable:kCharpterTable where:RDCharpterModel.bookId.is(bookid)&&RDCharpterModel.content.isNull()];
    }];
    return result;
}

+(RDCharpterModel *)getLastChapterWithBookId:(NSInteger)bookId
{
    __block RDCharpterModel *result = nil;
    [[RDDatabaseManager sharedInstance] performSync:^(WCTDatabase *db) {
        result = [db getOneObjectOnResults:{RDCharpterModel.charpterId.max(),RDCharpterModel.bookId} fromTable:kCharpterTable where:RDCharpterModel.bookId.is(bookId)];
    }];
    return result;
}

+(BOOL)deleteAllCharpterWithBookId:(NSInteger)bookid
{
    __block BOOL success = NO;
    [[RDDatabaseManager sharedInstance] performSync:^(WCTDatabase *db) {
        success = [db deleteObjectsFromTable:kCharpterTable where:RDCharpterModel.bookId.is(bookid)];
    }];
    return success;
}
@end
