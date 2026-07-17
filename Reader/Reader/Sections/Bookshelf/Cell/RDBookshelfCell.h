//
//  RDBookshelfCell.h
//  Reader
//
//  Created by yuenov on 2020/2/18.
//  Copyright © 2020 yuenov. All rights reserved.
//

#import "RDBookshelfBaseCell.h"
@class RDBookDetailModel;
NS_ASSUME_NONNULL_BEGIN

@interface RDBookshelfCell : RDBookshelfBaseCell
@property (nonatomic,strong) NSArray <RDBookDetailModel *>*books;
@property (nonatomic,copy) void (^needReload)(void);
@property (nonatomic,copy) void (^changeCover)(RDBookDetailModel *book);
@property (nonatomic,copy) void (^resetCover)(RDBookDetailModel *book);
+(CGFloat )cellHeight;
@end

NS_ASSUME_NONNULL_END
