//
//  RDLibraryTransaction.mm
//  Reader
//

#import "RDLibraryTransaction.h"
#import "RDDatabaseManager.h"
#import "RDCharpterDataManager+DBInternal.h"
#import "RDReadRecordManager+DBInternal.h"
#import "RDBookDetailModel.h"

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

@end
