//
//  RDBookshelfNoneCell.m
//  Reader
//
//  Created by yuenov on 2019/10/24.
//  Copyright © 2019 yuenov. All rights reserved.
//

#import "RDBookshelfNoneCell.h"
#import "RDMainController.h"
#import "AppDelegate.h"
#import "RDMainController.h"
#import "RDLocalBookManager.h"
@interface RDBookshelfNoneCell ()
@property (nonatomic,strong) UILabel *tipLabel;
@property (nonatomic,strong) UIButton *importButton;
@end
@implementation RDBookshelfNoneCell
-(instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier
{
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (self) {

        [self.contentView addSubview:self.tipLabel];
        [self.contentView addSubview:self.importButton];
    }
    return self;
}
-(UILabel *)tipLabel
{
    if (!_tipLabel) {
        _tipLabel = [[UILabel alloc] init];
        _tipLabel.numberOfLines = 0;
        NSMutableParagraphStyle *paragraphStyle = [[NSMutableParagraphStyle alloc] init];
        paragraphStyle.lineSpacing = 10;
        paragraphStyle.alignment = NSTextAlignmentCenter;
        NSString *str = @"一日无书\n百事荒芜";
        NSMutableAttributedString *attributedString = [[NSMutableAttributedString alloc] initWithString:str];
        [attributedString addAttributes:@{NSParagraphStyleAttributeName:paragraphStyle,NSFontAttributeName:RDTitleFont17,NSForegroundColorAttributeName:RDGrayColor} range:NSMakeRange(0, str.length)];
        _tipLabel.attributedText = attributedString;
    }
    return _tipLabel;
}

-(UIButton *)importButton
{
    if (!_importButton) {
        _importButton = [[UIButton alloc] init];
        [_importButton setTitle:@"导入本地书籍" forState:UIControlStateNormal];
        [_importButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        _importButton.backgroundColor = RDAccentColor;
        _importButton.layer.cornerRadius = 22;
        _importButton.titleLabel.font = RDBoldFont16;
        [_importButton addTarget:self action:@selector(importClick) forControlEvents:UIControlEventTouchUpInside];
    }
    return _importButton;
}

-(void)importClick{
    [[NSNotificationCenter defaultCenter] postNotificationName:RDLocalBookImportRequestNotification object:nil];
}
-(void)layoutSubviews{
    [super layoutSubviews];
    self.importButton.frame = CGRectMake(0, 0, 240, 44);
    self.importButton.top = self.height/2;
    self.importButton.centerX = self.width/2;
    self.tipLabel.frame = CGRectMake(0, 0, self.width,[[self.tipLabel.attributedText mutableCopy] sizewithFont:RDTitleFont17 lineSpace:10 maxWidth:self.width].height);
    self.tipLabel.bottom = self.importButton.top-40;
}
@end
