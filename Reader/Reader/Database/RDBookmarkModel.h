//
//  RDBookmarkModel.h
//  Reader
//
//  书签:记录章节 + 页码 + 字符偏移,支持随时跳转
//

#import "RDModel.h"

NS_ASSUME_NONNULL_BEGIN

@interface RDBookmarkModel : RDModel
@property (nonatomic, copy) NSString *bookmarkId;       // UUID 主键
@property (nonatomic, assign) NSInteger bookId;
@property (nonatomic, copy, nullable) NSString *bookTitle;
@property (nonatomic, assign) NSInteger charpterId;
@property (nonatomic, copy, nullable) NSString *charpterName;
@property (nonatomic, assign) NSInteger page;           // 保存时的页码(参考)
@property (nonatomic, assign) NSInteger charOffset;     // 章节内字符偏移(字体变化后恢复用)
@property (nonatomic, copy, nullable) NSString *snippet;// 摘录
@property (nonatomic, copy, nullable) NSString *note;   // 可选备注
@property (nonatomic, assign) NSTimeInterval createTime;
@end

NS_ASSUME_NONNULL_END
