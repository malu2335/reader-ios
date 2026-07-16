//
//  RDBookmarkManager.mm
//  Reader
//

#import "RDBookmarkManager.h"
#import "RDBookmarkModel.h"
#import "RDBookmarkModel+WCTTableCoding.h"
#import "RDDatabaseManager.h"
#import "RDBookDetailModel.h"
#import "RDCharpterModel.h"

NSString * const RDBookmarkChangedNotification = @"RDBookmarkChangedNotification";

@implementation RDBookmarkManager

+ (RDBookmarkModel *)addBookmarkForBook:(RDBookDetailModel *)book
                               chapter:(RDCharpterModel *)chapter
                                  page:(NSInteger)page
                            charOffset:(NSInteger)charOffset
                               snippet:(NSString *)snippet
{
    if (!book || !chapter) {
        return nil;
    }
    if ([self hasBookmarkNearBookId:book.bookId charpterId:chapter.charpterId charOffset:charOffset]) {
        // 返回已有
        __block RDBookmarkModel *existing = nil;
        [[RDDatabaseManager sharedInstance] performSync:^(WCTDatabase *db) {
            NSArray *list = [db getObjectsOfClass:RDBookmarkModel.class
                                        fromTable:kBookmarkTable
                                            where:RDBookmarkModel.bookId.is(book.bookId) && RDBookmarkModel.charpterId.is(chapter.charpterId)
                                          orderBy:RDBookmarkModel.createTime.order(WCTOrderedDescending)];
            for (RDBookmarkModel *m in list) {
                if (llabs(m.charOffset - charOffset) <= 40) {
                    existing = m;
                    break;
                }
            }
        }];
        return existing;
    }

    RDBookmarkModel *bm = [[RDBookmarkModel alloc] init];
    bm.bookmarkId = [[NSUUID UUID] UUIDString];
    bm.bookId = book.bookId;
    bm.bookTitle = book.title;
    bm.charpterId = chapter.charpterId;
    bm.charpterName = chapter.name;
    bm.page = page;
    bm.charOffset = MAX(0, charOffset);
    bm.snippet = snippet.length > 120 ? [[snippet substringToIndex:120] stringByAppendingString:@"…"] : snippet;
    bm.createTime = [NSDate date].timeIntervalSince1970;

    [[RDDatabaseManager sharedInstance] performSync:^(WCTDatabase *db) {
        [db insertOrReplaceObject:bm into:kBookmarkTable];
    }];
    [[NSNotificationCenter defaultCenter] postNotificationName:RDBookmarkChangedNotification object:@(book.bookId)];
    return bm;
}

+ (NSArray <RDBookmarkModel *>*)bookmarksForBookId:(NSInteger)bookId
{
    __block NSArray *result = nil;
    [[RDDatabaseManager sharedInstance] performSync:^(WCTDatabase *db) {
        result = [db getObjectsOfClass:RDBookmarkModel.class
                             fromTable:kBookmarkTable
                                 where:RDBookmarkModel.bookId.is(bookId)
                               orderBy:RDBookmarkModel.createTime.order(WCTOrderedDescending)];
    }];
    return result ?: @[];
}

+ (NSInteger)countForBookId:(NSInteger)bookId
{
    __block NSInteger count = 0;
    [[RDDatabaseManager sharedInstance] performSync:^(WCTDatabase *db) {
        count = [[db getOneValueOnResult:RDBookmarkModel.AnyProperty.count()
                               fromTable:kBookmarkTable
                                   where:RDBookmarkModel.bookId.is(bookId)] integerValue];
    }];
    return count;
}

+ (void)deleteBookmark:(RDBookmarkModel *)bookmark
{
    if (!bookmark.bookmarkId.length) {
        return;
    }
    NSInteger bookId = bookmark.bookId;
    [[RDDatabaseManager sharedInstance] performSync:^(WCTDatabase *db) {
        [db deleteObjectsFromTable:kBookmarkTable where:RDBookmarkModel.bookmarkId.is(bookmark.bookmarkId)];
    }];
    [[NSNotificationCenter defaultCenter] postNotificationName:RDBookmarkChangedNotification object:@(bookId)];
}

+ (void)deleteAllForBookId:(NSInteger)bookId
{
    [[RDDatabaseManager sharedInstance] performSync:^(WCTDatabase *db) {
        [db deleteObjectsFromTable:kBookmarkTable where:RDBookmarkModel.bookId.is(bookId)];
    }];
    [[NSNotificationCenter defaultCenter] postNotificationName:RDBookmarkChangedNotification object:@(bookId)];
}

+ (BOOL)hasBookmarkNearBookId:(NSInteger)bookId charpterId:(NSInteger)charpterId charOffset:(NSInteger)charOffset
{
    __block BOOL found = NO;
    [[RDDatabaseManager sharedInstance] performSync:^(WCTDatabase *db) {
        NSArray *list = [db getObjectsOfClass:RDBookmarkModel.class
                                    fromTable:kBookmarkTable
                                        where:RDBookmarkModel.bookId.is(bookId) && RDBookmarkModel.charpterId.is(charpterId)];
        for (RDBookmarkModel *m in list) {
            if (llabs(m.charOffset - charOffset) <= 40) {
                found = YES;
                break;
            }
        }
    }];
    return found;
}

@end
