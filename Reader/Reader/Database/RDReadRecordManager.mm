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

+(BOOL)insertOrReplaceModel:(RDBookDetailModel *)model
{
    return [self insertOrReplaceModel:model touchReadTime:YES];
}

+(BOOL)insertOrReplaceModel:(RDBookDetailModel *)model touchReadTime:(BOOL)touchReadTime
{
    __block BOOL success = NO;
    [[RDDatabaseManager sharedInstance] performSync:^(WCTDatabase *db) {
        success = [self db_insertOrReplaceModel:model touchReadTime:touchReadTime inDatabase:db];
    }];
    return success;
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

+(BOOL)updateProgressWithModel:(RDBookDetailModel *)model
{
    if (model.bookId == 0) {
        return NO;
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
    __block BOOL success = NO;
    void (^attempt)(void) = ^{
        [[RDDatabaseManager sharedInstance] performSync:^(WCTDatabase *db) {
            RDBookDetailModel *row = [db getOneObjectOnResults:{RDBookDetailModel.bookId}
                                                     fromTable:kReadRecordTable
                                                         where:RDBookDetailModel.bookId.is(model.bookId)];
            exists = row != nil;
            if (exists) {
                success = [db updateRowsInTable:kReadRecordTable
                         onProperties:{RDBookDetailModel.charpterModel,
                                       RDBookDetailModel.page,
                                       RDBookDetailModel.charOffset,
                                       RDBookDetailModel.readChapterName,
                                       RDBookDetailModel.readTime}
                           withObject:model
                                where:RDBookDetailModel.bookId.is(model.bookId)];
            }
            else {
                success = [db insertOrReplaceObject:model into:kReadRecordTable];
            }
        }];
    };
    // 次级写路径:失败重试一次,避免 busy 瞬时导致进度静默丢失(P2-DB-03)
    attempt();
    if (!success) {
        attempt();
    }
    if (light) {
        model.charpterModel = original;
    }
    return success;
}

+(BOOL)updateTitle:(NSString *)title author:(NSString *)author forBookId:(NSInteger)bookId
{
    if (bookId == 0 || title.length == 0) {
        return NO;
    }
    RDBookDetailModel *patch = [[RDBookDetailModel alloc] init];
    patch.title = title;
    patch.author = author ?: @"";
    __block BOOL success = NO;
    [[RDDatabaseManager sharedInstance] performSync:^(WCTDatabase *db) {
        success = [db updateRowsInTable:kReadRecordTable
                           onProperties:{RDBookDetailModel.title, RDBookDetailModel.author}
                             withObject:patch
                                  where:RDBookDetailModel.bookId.is(bookId)];
    }];
    return success;
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
        BOOL ok = [db updateRowsInTable:kReadRecordTable
                           onProperties:{RDBookDetailModel.page, RDBookDetailModel.readTime}
                             withObject:patch
                                  where:RDBookDetailModel.bookId.is(bookId)];
        // 异步路径也重试一次;仍失败则下一次翻页/离开页会再写(P2-DB-03)
        if (!ok) {
            [db updateRowsInTable:kReadRecordTable
                     onProperties:{RDBookDetailModel.page, RDBookDetailModel.readTime}
                       withObject:patch
                            where:RDBookDetailModel.bookId.is(bookId)];
        }
    }];
}

+(BOOL)updateBookshelfState:(RDBookDetailModel *)model
{
    model.readTime = [NSDate date].timeIntervalSince1970;
    __block BOOL success = NO;
    [[RDDatabaseManager sharedInstance] performSync:^(WCTDatabase *db) {
        success = [db updateRowsInTable:kReadRecordTable onProperties:{RDBookDetailModel.onBookshelf,RDBookDetailModel.readTime} withObject:model where:RDBookDetailModel.bookId.is(model.bookId)];
    }];
    return success;
}

+(BOOL)updateReadTime:(RDBookDetailModel *)model
{
    model.readTime = [NSDate date].timeIntervalSince1970;
    __block BOOL success = NO;
    [[RDDatabaseManager sharedInstance] performSync:^(WCTDatabase *db) {
        success = [db updateRowsInTable:kReadRecordTable onProperties:RDBookDetailModel.readTime withObject:model where:RDBookDetailModel.bookId.is(model.bookId)];
    }];
    return success;
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
    // 同 getBookshelfDisplayList:失败返回 nil,清空流程据此报错,
    // 不能把"查不出来"当成"没有东西要删"然后提示已清空。
    return result;
}

+(NSInteger)countOnBookshelf
{
    __block NSInteger count = 0;
    [[RDDatabaseManager sharedInstance] performSync:^(WCTDatabase *db) {
        // 与展示列表一致:不含合集成员(collectionId!=0)
        count = [[db getOneValueOnResult:RDBookDetailModel.AnyProperty.count()
                               fromTable:kReadRecordTable
                                   where:RDBookDetailModel.onBookshelf.is(YES)
                                         && RDBookDetailModel.bookId < 0
                                         && RDBookDetailModel.collectionId == 0] integerValue];
    }];
    return count;
}

+(NSArray <RDBookDetailModel *>*)getBookshelfDisplayList
{
    __block NSArray *result = nil;
    [[RDDatabaseManager sharedInstance] performSync:^(WCTDatabase *db) {
        // 故意不取 charpterModel:章节正文可能极大,拖垮启动/书架首帧
        // 合集成员(collectionId!=0)不展示在顶层,只显示合集壳与独立书
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
            RDBookDetailModel.collectionId,
            RDBookDetailModel.collectionOrder,
        } fromTable:kReadRecordTable
             where:RDBookDetailModel.onBookshelf.is(YES)
                   && RDBookDetailModel.bookId < 0
                   && RDBookDetailModel.collectionId == 0
           orderBy:RDBookDetailModel.readTime.order(WCTOrderedDescending)];
    }];
    // 查询失败返回 nil,与"确实没有书"的空数组区分开:
    // 调用方必须据此显示错误态,而不是提交一份空快照(P1-07)。
    return result;
}

+(BOOL)removeBookFromBookShelfWithBookId:(NSInteger)bookid
{
    __block BOOL success = NO;
    [[RDDatabaseManager sharedInstance] performSync:^(WCTDatabase *db) {
        success = [db deleteObjectsFromTable:kReadRecordTable where:RDBookDetailModel.bookId.is(bookid)];
    }];
    return success;
}

+(BOOL)updateOnBookselfUpdateWithBookId:(NSInteger)bookid update:(BOOL)update
{
    __block BOOL success = NO;
    [[RDDatabaseManager sharedInstance] performSync:^(WCTDatabase *db) {
        success = [db updateRowsInTable:kReadRecordTable onProperty:RDBookDetailModel.bookUpdate withValue:@(update) where:RDBookDetailModel.bookId.is(bookid)];
    }];
    return success;
}
@end
