//
//  RDReadCatalogCell.h
//  Reader
//
//  Created by yuenov on 2019/11/20.
//  Copyright © 2019 yuenov. All rights reserved.
//

#import <UIKit/UIKit.h>
#import "RDCharpterModel.h"
NS_ASSUME_NONNULL_BEGIN

@protocol RDReadCatalogCellDelegate <NSObject>
-(void)didSelectCharpter:(RDCharpterModel *)charpter;
@end

@interface RDReadCatalogCell : UITableViewCell
@property (nonatomic,strong) RDCharpterModel *model;
/// 该章是否已有正文。由列表统一算好后下发,cell 自己不查库(P2-03)。
/// 必须在 model 之前设置。
@property (nonatomic,assign) BOOL hasContent;
@property (nonatomic,weak) id<RDReadCatalogCellDelegate>delegate;
@end

NS_ASSUME_NONNULL_END
