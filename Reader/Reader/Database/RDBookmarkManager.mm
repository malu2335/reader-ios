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
    // 查重 + 插入同一 performSync 块,避免 check-then-act 竞态(P2-03 / Phase 3)
    __block RDBookmarkModel *result = nil;
    __block BOOL inserted = NO;
    [[RDDatabaseManager sharedInstance] performSync:^(WCTDatabase *db) {
        // 附近 offset 下推 SQL,避免单章海量书签全表反序列化(P2-DB-04)
        NSInteger lo = MAX(0, charOffset - 40);
        NSInteger hi = charOffset + 40;
        RDBookmarkModel *near = [db getOneObjectOfClass:RDBookmarkModel.class
                                              fromTable:kBookmarkTable
                                                  where:RDBookmarkModel.bookId.is(book.bookId)
                                                        && RDBookmarkModel.charpterId.is(chapter.charpterId)
                                                        && RDBookmarkModel.charOffset.between(lo, hi)];
        if (near) {
            result = near;
            return;
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
        if ([db insertOrReplaceObject:bm into:kBookmarkTable]) {
            result = bm;
            inserted = YES;
        }
    }];
    if (inserted && result) {
        [[NSNotificationCenter defaultCenter] postNotificationName:RDBookmarkChangedNotification object:@(book.bookId)];
    }
    return result;
}

+ (BOOL)insertOrReplaceBookmark:(RDBookmarkModel *)bookmark
{
    if (bookmark.bookmarkId.length == 0 || bookmark.bookId == 0) {
        return NO;
    }
    __block BOOL ok = NO;
    [[RDDatabaseManager sharedInstance] performSync:^(WCTDatabase *db) {
        ok = [db insertOrReplaceObject:bookmark into:kBookmarkTable];
    }];
    return ok;
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

+ (BOOL)deleteBookmark:(RDBookmarkModel *)bookmark
{
    if (!bookmark.bookmarkId.length) {
        return NO;
    }
    NSInteger bookId = bookmark.bookId;
    __block BOOL ok = NO;
    [[RDDatabaseManager sharedInstance] performSync:^(WCTDatabase *db) {
        ok = [db deleteObjectsFromTable:kBookmarkTable where:RDBookmarkModel.bookmarkId.is(bookmark.bookmarkId)];
    }];
    if (ok) {
        [[NSNotificationCenter defaultCenter] postNotificationName:RDBookmarkChangedNotification object:@(bookId)];
    }
    return ok;
}

+ (BOOL)deleteAllForBookId:(NSInteger)bookId
{
    __block BOOL ok = NO;
    [[RDDatabaseManager sharedInstance] performSync:^(WCTDatabase *db) {
        ok = [db deleteObjectsFromTable:kBookmarkTable where:RDBookmarkModel.bookId.is(bookId)];
    }];
    if (ok) {
        [[NSNotificationCenter defaultCenter] postNotificationName:RDBookmarkChangedNotification object:@(bookId)];
    }
    return ok;
}

+ (BOOL)hasBookmarkNearBookId:(NSInteger)bookId charpterId:(NSInteger)charpterId charOffset:(NSInteger)charOffset
{
    __block BOOL found = NO;
    [[RDDatabaseManager sharedInstance] performSync:^(WCTDatabase *db) {
        NSInteger lo = MAX(0, charOffset - 40);
        NSInteger hi = charOffset + 40;
        RDBookmarkModel *near = [db getOneObjectOfClass:RDBookmarkModel.class
                                              fromTable:kBookmarkTable
                                                  where:RDBookmarkModel.bookId.is(bookId)
                                                        && RDBookmarkModel.charpterId.is(charpterId)
                                                        && RDBookmarkModel.charOffset.between(lo, hi)];
        found = (near != nil);
    }];
    return found;
}

@end
