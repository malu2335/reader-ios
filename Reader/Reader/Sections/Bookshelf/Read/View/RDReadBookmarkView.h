//
//  RDReadBookmarkView.h
//  Reader
//
//  阅读中书签面板:添加当前页 + 列表跳转/删除
//

#import <UIKit/UIKit.h>
@class RDBookDetailModel;
@class RDBookmarkModel;

NS_ASSUME_NONNULL_BEGIN

@protocol RDReadBookmarkViewDelegate <NSObject>
@optional
- (void)bookmarkViewDidSelect:(RDBookmarkModel *)bookmark;
- (void)bookmarkViewDidAddCurrent;
@end

@interface RDReadBookmarkView : UIView
@property (nonatomic, weak, nullable) id<RDReadBookmarkViewDelegate> delegate;
@property (nonatomic, strong) RDBookDetailModel *book;
@property (nonatomic, copy, nullable) void (^clickBg)(void);

- (void)reloadData;
@end

NS_ASSUME_NONNULL_END
