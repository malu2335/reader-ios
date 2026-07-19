//
//  RDReadRecordManager.m
//  Reader
//

#import "RDReadRecordManager.h"
#import "RDReadRecordManager+DBInternal.h"
#import "RDBookDetailModel.h"
#import "RDBookDetailModel+WCTTableCoding.h"
#import "RDDatabaseManager.h"
#import "RDCharpterDataManager.h"
#import "RDCharpterModel.h"

@implementation RDReadRecordManager

+(void)insertOrReplaceModel:(RDBookDetailModel *)model
{
    [self insertOrReplaceModel:model touchReadTime:YES];
}

+(void)insertOrReplaceModel:(RDBookDetailModel *)model touchReadTime:(BOOL)touchReadTime
{
    [[RDDatabaseManager sharedInstance] performSync:^(WCTDatabase *db) {
        [self db_insertOrReplaceModel:model touchReadTime:touchReadTime inDatabase:db];
    }];
}

+(BOOL)db_insertOrReplaceModel:(RDBookDetailModel *)model
                 touchReadTime:(BOOL)touchReadTime
                    inDatabase:(WCTInterface *)db
{
    if (touchReadTime || model.readTime <= 0) {
        model.readTime = [NSDate date].timeIntervalSince1970;
    }
    // 同步书架轻量章节名
    if (model.charpterModel.name.length) {
        model.readChapterName = model.charpterModel.name;
    }
    // 章节正文以章节表为准,记录表只存引用,避免整章正文随进度反复落盘
    RDCharpterModel *original = model.charpterModel;
    RDCharpterModel *light = [self p_lightCharpter:original];
    if (light) {
        model.charpterModel = light;
    }
    BOOL success = [db insertOrReplaceObject:model into:kReadRecordTable];
    if (light) {
        model.charpterModel = original;
    }
    return success;
}

/// 去掉 content 的章节引用副本;无需剥离时返回 nil
+(RDCharpterModel *)p_lightCharpter:(RDCharpterModel *)charpter
{
    if (!charpter || charpter.content.length == 0) {
        return nil;
    }
    RDCharpterModel *light = [[RDCharpterModel alloc] init];
    light.bookId = charpter.bookId;
    light.charpterId = charpter.charpterId;
    light.name = charpter.name;
    light.bookName = charpter.bookName;
    light.author = charpter.author;
    return light;
}

+(void)updateProgressWithModel:(RDBookDetailModel *)model
{
    if (model.bookId == 0) {
        return;
    }
    RDCharpterModel *original = model.charpterModel;
    RDCharpterModel *light = [self p_lightCharpter:original];
    if (light) {
        model.charpterModel = light;
    }
    model.readTime = [NSDate date].timeIntervalSince1970;
    if (model.charpterModel.name.length) {
        model.readChapterName = model.charpterModel.name;
    }
    __block BOOL exists = NO;
    [[RDDatabaseManager sharedInstance] performSync:^(WCTDatabase *db) {
        RDBookDetailModel *row = [db getOneObjectOnResults:{RDBookDetailModel.bookId}
                                                 fromTable:kReadRecordTable
                                                     where:RDBookDetailModel.bookId.is(model.bookId)];
        exists = row != nil;
        if (exists) {
            [db updateRowsInTable:kReadRecordTable
                     onProperties:{RDBookDetailModel.charpterModel,
                                   RDBookDetailModel.page,
                                   RDBookDetailModel.charOffset,
                                   RDBookDetailModel.readChapterName,
                                   RDBookDetailModel.readTime}
                       withObject:model
                            where:RDBookDetailModel.bookId.is(model.bookId)];
        }
        else {
            [db insertOrReplaceObject:model into:kReadRecordTable];
        }
    }];
    if (light) {
        model.charpterModel = original;
    }
}

+(void)updateTitle:(NSString *)title author:(NSString *)author forBookId:(NSInteger)bookId
{
    if (bookId == 0 || title.length == 0) {
        return;
    }
    RDBookDetailModel *patch = [[RDBookDetailModel alloc] init];
    patch.title = title;
    patch.author = author ?: @"";
    [[RDDatabaseManager sharedInstance] performSync:^(WCTDatabase *db) {
        [db updateRowsInTable:kReadRecordTable
                 onProperties:{RDBookDetailModel.title, RDBookDetailModel.author}
                   withObject:patch
                        where:RDBookDetailModel.bookId.is(bookId)];
    }];
}

+(BOOL)updateCoverImg:(NSString *)coverImg forBookId:(NSInteger)bookId
{
    if (bookId == 0 || coverImg.length == 0) {
        return NO;
    }
    RDBookDetailModel *patch = [[RDBookDetailModel alloc] init];
    patch.coverImg = coverImg;
    __block BOOL success = NO;
    [[RDDatabaseManager sharedInstance] performSync:^(WCTDatabase *db) {
        success = [db updateRowsInTable:kReadRecordTable
                           onProperties:RDBookDetailModel.coverImg
                             withObject:patch
                                  where:RDBookDetailModel.bookId.is(bookId)];
    }];
    return success;
}

+(void)asyncUpdatePage:(NSInteger)page forBookId:(NSInteger)bookId
{
    if (bookId == 0) {
        return;
    }
    RDBookDetailModel *patch = [[RDBookDetailModel alloc] init];
    patch.page = page;
    patch.readTime = [NSDate date].timeIntervalSince1970;
    [[RDDatabaseManager sharedInstance] performAsync:^(WCTDatabase *db) {
        [db updateRowsInTable:kReadRecordTable
                 onProperties:{RDBookDetailModel.page, RDBookDetailModel.readTime}
                   withObject:patch
                        where:RDBookDetailModel.bookId.is(bookId)];
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
        result = [db getObjectsOfClass:RDBookDetailModel.class
                             fromTable:kReadRecordTable
                                 where:RDBookDetailModel.onBookshelf.is(YES) && RDBookDetailModel.bookId < 0
                               orderBy:RDBookDetailModel.readTime.order(WCTOrderedDescending)];
    }];
    return result;
}

+(NSArray <RDBookDetailModel *>*)getAllRecordsForDestructiveClear
{
    __block NSArray *result = nil;
    [[RDDatabaseManager sharedInstance] performSync:^(WCTDatabase *db) {
        // 清空必须覆盖全部记录行,包括历史遗留的正 bookId 与已下架的行,
        // 否则"清空书架"与实际残留不符(P2-18)。只取清理所需的轻量列。
        result = [db getAllObjectsOnResults:{
            RDBookDetailModel.bookId,
            RDBookDetailModel.coverImg,
            RDBookDetailModel.localPath,
            RDBookDetailModel.fileType,
        } fromTable:kReadRecordTable];
    }];
    return result ?: @[];
}

+(NSInteger)countOnBookshelf
{
    __block NSInteger count = 0;
    [[RDDatabaseManager sharedInstance] performSync:^(WCTDatabase *db) {
        count = [[db getOneValueOnResult:RDBookDetailModel.AnyProperty.count()
                               fromTable:kReadRecordTable
                                   where:RDBookDetailModel.onBookshelf.is(YES) && RDBookDetailModel.bookId < 0] integerValue];
    }];
    return count;
}

+(NSArray <RDBookDetailModel *>*)getBookshelfDisplayList
{
    __block NSArray *result = nil;
    [[RDDatabaseManager sharedInstance] performSync:^(WCTDatabase *db) {
        // 故意不取 charpterModel:章节正文可能极大,拖垮启动/书架首帧
        result = [db getObjectsOnResults:{
            RDBookDetailModel.bookId,
            RDBookDetailModel.coverImg,
            RDBookDetailModel.title,
            RDBookDetailModel.author,
            RDBookDetailModel.desc,
            RDBookDetailModel.bookUpdate,
            RDBookDetailModel.page,
            RDBookDetailModel.charOffset,
            RDBookDetailModel.readChapterName,
            RDBookDetailModel.readTime,
            RDBookDetailModel.onBookshelf,
            RDBookDetailModel.localPath,
            RDBookDetailModel.fileType,
        } fromTable:kReadRecordTable
             where:RDBookDetailModel.onBookshelf.is(YES) && RDBookDetailModel.bookId < 0
           orderBy:RDBookDetailModel.readTime.order(WCTOrderedDescending)];
    }];
    return result ?: @[];
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
