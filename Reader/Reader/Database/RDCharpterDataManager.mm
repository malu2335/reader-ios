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

+(void)updateCharpterContentWithModel:(RDCharpterModel *)model
{
    [[RDDatabaseManager sharedInstance] performSync:^(WCTDatabase *db) {
        [db updateRowsInTable:kCharpterTable onProperty:RDCharpterModel.content withObject:model where:RDCharpterModel.bookId.is(model.bookId)&&RDCharpterModel.charpterId.is(model.charpterId)];
    }];
}

+(void)insertObjectWithCharpters:(RDCharpterModel *)charpter
{
    [[RDDatabaseManager sharedInstance] performSync:^(WCTDatabase *db) {
        charpter.primaryId = [NSString stringWithFormat:@"%@_%@", @(charpter.bookId), @(charpter.charpterId)];
        [db insertOrReplaceObject:charpter into:kCharpterTable];
    }];
}

+(void)insertObjectsWithCharpters:(NSArray *)charpters
{
    if (charpters.count == 0) {
        return;
    }
    NSInteger bookId = [charpters.firstObject bookId];
    [[RDDatabaseManager sharedInstance] performSync:^(WCTDatabase *db) {
        NSArray *existing = [db getObjectsOnResults:{RDCharpterModel.charpterId, RDCharpterModel.primaryId} fromTable:kCharpterTable where:RDCharpterModel.bookId.is(bookId)];
        NSMutableSet *existingIds = [NSMutableSet set];
        for (RDCharpterModel *m in existing) {
            [existingIds addObject:@(m.charpterId)];
        }
        [db runTransaction:^BOOL{
            NSMutableArray *toInsert = [NSMutableArray array];
            for (RDCharpterModel *charpterModel in charpters) {
                charpterModel.primaryId = [NSString stringWithFormat:@"%@_%@", @(charpterModel.bookId), @(charpterModel.charpterId)];
                if ([existingIds containsObject:@(charpterModel.charpterId)]) {
                    if (charpterModel.content.length > 0) {
                        [db updateRowsInTable:kCharpterTable onProperty:RDCharpterModel.content withObject:charpterModel where:RDCharpterModel.bookId.is(charpterModel.bookId)&&RDCharpterModel.charpterId.is(charpterModel.charpterId)];
                    }
                } else {
                    [toInsert addObject:charpterModel];
                    [existingIds addObject:@(charpterModel.charpterId)];
                }
            }
            if (toInsert.count > 0) {
                [db insertOrReplaceObjects:toInsert into:kCharpterTable];
            }
            return YES;
        }];
    }];
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
    for (RDCharpterModel *chapter in chapters) {
        chapter.bookId = bookId;
        chapter.primaryId = [NSString stringWithFormat:@"%@_%@", @(chapter.bookId), @(chapter.charpterId)];
    }
    return [db insertOrReplaceObjects:chapters into:kCharpterTable];
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

+(void)deleteAllCharpterWithBookId:(NSInteger)bookid
{
    [[RDDatabaseManager sharedInstance] performSync:^(WCTDatabase *db) {
        [db deleteObjectsFromTable:kCharpterTable where:RDCharpterModel.bookId.is(bookid)];
    }];
}
@end
