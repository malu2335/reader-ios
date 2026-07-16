//
//  RDBookmarkModel+WCTTableCoding.h
//  Reader
//

#import "RDBookmarkModel.h"
#import <WCDB/WCDB.h>

@interface RDBookmarkModel (WCTTableCoding) <WCTTableCoding>

WCDB_PROPERTY(bookmarkId)
WCDB_PROPERTY(bookId)
WCDB_PROPERTY(bookTitle)
WCDB_PROPERTY(charpterId)
WCDB_PROPERTY(charpterName)
WCDB_PROPERTY(page)
WCDB_PROPERTY(charOffset)
WCDB_PROPERTY(snippet)
WCDB_PROPERTY(note)
WCDB_PROPERTY(createTime)

@end
