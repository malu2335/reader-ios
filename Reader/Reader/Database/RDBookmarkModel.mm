//
//  RDBookmarkModel.mm
//  Reader
//

#import "RDBookmarkModel+WCTTableCoding.h"
#import "RDBookmarkModel.h"
#import <WCDB/WCDB.h>

@implementation RDBookmarkModel

WCDB_IMPLEMENTATION(RDBookmarkModel)
WCDB_SYNTHESIZE_COLUMN(RDBookmarkModel, bookmarkId, "bookmarkId")
WCDB_SYNTHESIZE_COLUMN(RDBookmarkModel, bookId, "bookId")
WCDB_SYNTHESIZE_COLUMN(RDBookmarkModel, bookTitle, "bookTitle")
WCDB_SYNTHESIZE_COLUMN(RDBookmarkModel, charpterId, "charpterId")
WCDB_SYNTHESIZE_COLUMN(RDBookmarkModel, charpterName, "charpterName")
WCDB_SYNTHESIZE_COLUMN(RDBookmarkModel, page, "page")
WCDB_SYNTHESIZE_COLUMN(RDBookmarkModel, charOffset, "charOffset")
WCDB_SYNTHESIZE_COLUMN(RDBookmarkModel, snippet, "snippet")
WCDB_SYNTHESIZE_COLUMN(RDBookmarkModel, note, "note")
WCDB_SYNTHESIZE_COLUMN(RDBookmarkModel, createTime, "createTime")

WCDB_PRIMARY(RDBookmarkModel, bookmarkId)
WCDB_INDEX(RDBookmarkModel, "_bookId_index", bookId)

@end
