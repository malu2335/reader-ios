//
//  RDReadCatalogCell.m
//  Reader
//
//  Created by yuenov on 2019/11/20.
//  Copyright © 2019 yuenov. All rights reserved.
//

#import "RDReadCatalogCell.h"
#import "RDReadConfigManager.h"
@interface RDReadCatalogCell ()
@property (nonatomic,strong) UILabel *chapterLabel;
@property (nonatomic,strong) UIView *separate;
@end

@implementation RDReadCatalogCell
- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier
{
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (self) {
        [self.contentView addSubview:self.chapterLabel];
        [self.contentView addSubview:self.separate];
        self.backgroundColor = [UIColor clearColor];
        [self.contentView setBackgroundColor:[UIColor clearColor]];
        [self.contentView addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(tap)]];
    }
    return self;
}

-(void)setModel:(RDCharpterModel *)model
{
    _model = model;
    self.chapterLabel.text = model.name;
    // 已下载状态由列表一次性算好(hasContent),不再逐 cell 读整章正文
    RDReadConfigManager *cfg = [RDReadConfigManager sharedInstance];
    UIColor *fg = [cfg chromeForegroundColor];
    UIColor *sec = [cfg chromeSecondaryColor];
    _chapterLabel.textColor = self.hasContent ? fg : sec;
    self.separate.backgroundColor = [cfg chromeSeparatorColor];
}

-(UILabel *)chapterLabel
{
    if (!_chapterLabel) {
        _chapterLabel = [[UILabel alloc] init];
        _chapterLabel.font = RDFont15;
        _chapterLabel.textColor = RDLightGrayColor;
    }
    return _chapterLabel;
}

-(UIView *)separate
{
    if (!_separate) {
        _separate = [[UIView alloc] init];
        _separate.backgroundColor = RDLightSeparatorColor;
    }
    return _separate;
}

-(void)tap
{
    if ([self.delegate respondsToSelector:@selector(didSelectCharpter:)]) {
        [self.delegate didSelectCharpter:self.model];
    }
}

-(void)layoutSubviews
{
    [super layoutSubviews];
    self.chapterLabel.frame = CGRectMake(20, 0, self.width-40, RDFont15.lineHeight);
    self.chapterLabel.centerY = self.height/2;
    self.separate.frame = CGRectMake(20, 0, self.width-40, MinPixel);
    self.separate.bottom = self.height;
}

@end
