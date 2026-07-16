//
//  RDBookmarkManager.h
//  Reader
//

#import <Foundation/Foundation.h>
@class RDBookmarkModel;
@class RDBookDetailModel;
@class RDCharpterModel;

NS_ASSUME_NONNULL_BEGIN

extern NSString * const RDBookmarkChangedNotification;

@interface RDBookmarkManager : NSObject

/// 添加书签;同一位置(章节+偏移±20)不重复
+ (RDBookmarkModel *)addBookmarkForBook:(RDBookDetailModel *)book
                               chapter:(RDCharpterModel *)chapter
                                  page:(NSInteger)page
                            charOffset:(NSInteger)charOffset
                               snippet:(nullable NSString *)snippet;

+ (NSArray <RDBookmarkModel *>*)bookmarksForBookId:(NSInteger)bookId;
+ (NSInteger)countForBookId:(NSInteger)bookId;

+ (void)deleteBookmark:(RDBookmarkModel *)bookmark;
+ (void)deleteAllForBookId:(NSInteger)bookId;

/// 是否已在当前位置附近存在书签
+ (BOOL)hasBookmarkNearBookId:(NSInteger)bookId
                   charpterId:(NSInteger)charpterId
                   charOffset:(NSInteger)charOffset;

@end

NS_ASSUME_NONNULL_END
