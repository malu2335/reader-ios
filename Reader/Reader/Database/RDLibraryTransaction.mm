//
//  RDLibraryTransaction.mm
//  Reader
//

#import "RDLibraryTransaction.h"
#import "RDDatabaseManager.h"
#import "RDCharpterDataManager+DBInternal.h"
#import "RDReadRecordManager+DBInternal.h"
#import "RDBookDetailModel.h"
#import "RDBookDetailModel+WCTTableCoding.h"
#import "RDCharpterModel.h"
#import "RDCharpterModel+WCTTableCoding.h"
#import "RDBookmarkModel.h"
#import "RDBookmarkModel+WCTTableCoding.h"

@implementation RDLibraryTransaction

+ (BOOL)commitBook:(RDBookDetailModel *)book
          chapters:(NSArray *)chapters
     touchReadTime:(BOOL)touchReadTime
             error:(NSError **)error
{
    if (!book || book.bookId == 0) {
        if (error) {
            *error = [NSError errorWithDomain:RDDatabaseErrorDomain
                                         code:-1
                                     userInfo:@{NSLocalizedDescriptionKey: @"书籍记录无效"}];
        }
        return NO;
    }
    NSInteger bookId = book.bookId;
    return [[RDDatabaseManager sharedInstance] performTransactionSync:^BOOL(WCTInterface *db) {
        // PDF/漫画没有文字章节,传空数组时不去动章节表(避免恢复时误删)
        if (chapters.count > 0 &&
            ![RDCharpterDataManager db_replaceChaptersForBookId:bookId chapters:chapters inDatabase:db]) {
            return NO;
        }
        return [RDReadRecordManager db_insertOrReplaceModel:book touchReadTime:touchReadTime inDatabase:db];
    } error:error];
}

+ (BOOL)deleteAllRecordsForBookId:(NSInteger)bookId error:(NSError **)error
{
    if (bookId == 0) {
        if (error) {
            *error = [NSError errorWithDomain:RDDatabaseErrorDomain
                                         code:-1
                                     userInfo:@{NSLocalizedDescriptionKey: @"书籍 ID 无效"}];
        }
        return NO;
    }
    return [[RDDatabaseManager sharedInstance] performTransactionSync:^BOOL(WCTInterface *db) {
        if (![db deleteObjectsFromTable:kReadRecordTable where:RDBookDetailModel.bookId.is(bookId)]) {
            return NO;
        }
        if (![db deleteObjectsFromTable:kCharpterTable where:RDCharpterModel.bookId.is(bookId)]) {
            return NO;
        }
        if (![db deleteObjectsFromTable:kBookmarkTable where:RDBookmarkModel.bookId.is(bookId)]) {
            return NO;
        }
        if (![db deleteObjectsFromTable:kHistoryRecordTable where:RDBookDetailModel.bookId.is(bookId)]) {
            return NO;
        }
        return YES;
    } error:error];
}

@end
