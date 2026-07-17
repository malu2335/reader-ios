//
//  RDBookshelfSearchCell.m
//  Reader
//
//  Created by yuenov on 2019/10/24.
//  Copyright © 2019 yuenov. All rights reserved.
//

#import "RDBookshelfSearchCell.h"
#import "RDSearchView.h"
@interface RDBookshelfSearchCell () <RDSearchViewDelegate>
@property (nonatomic,strong) RDSearchView *searchView;
@end
@implementation RDBookshelfSearchCell

-(instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier
{
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (self) {
        [self.contentView addSubview:self.searchView];
    }
    return self;
}
-(RDSearchView *)searchView
{
    if (!_searchView) {
        _searchView = [[RDSearchView alloc] init];
        _searchView.delegate = self;
        
    }
    return _searchView;
}

-(void)searchViewDidSelect
{
    [RDToastView showText:@"请先导入书籍" delay:1.5 inView:[RDUtilities applicationKeyWindow]];
}

-(void)layoutSubviews
{
    [super layoutSubviews];
    _searchView.frame = CGRectMake(10, 10, self.width-20, 35);
}
@end
