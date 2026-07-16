//
//  RDReadSetView.m
//  Reader
//
//  Created by yuenov on 2019/11/14.
//  Copyright © 2019 yuenov. All rights reserved.
//

#import "RDReadSetView.h"
#import "StepSlider.h"
#import "RDReadToolPageView.h"
#import "RDReadConfigManager.h"
#import "RDFontManager.h"
@interface RDReadSetView ()
@property (nonatomic,strong) UIImageView *bigWord;
@property (nonatomic,strong) UIImageView *smallWord;
@property (nonatomic,strong) StepSlider *stepSlider;
@property (nonatomic,strong) RDReadToolPageView *pageView;
@property (nonatomic,strong) UIScrollView *fontScroll;
@property (nonatomic,strong) NSArray <RDFontOption *>*fontOptions;
@end

@implementation RDReadSetView

- (instancetype)initWithFrame:(CGRect)frame
{
    self = [super initWithFrame:frame];
    if (self) {
        [self addSubview:self.bigWord];
        [self addSubview:self.smallWord];
        [self addSubview:self.stepSlider];
        [self addSubview:self.fontScroll];
        [self addSubview:self.pageView];
        [self reloadFontChips];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(reloadFontChips)
                                                     name:RDFontListChangedNotification object:nil];
    }
    return self;
}

-(void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

#pragma mark - 字体选择

-(UIScrollView *)fontScroll
{
    if (!_fontScroll) {
        _fontScroll = [[UIScrollView alloc] init];
        _fontScroll.showsHorizontalScrollIndicator = NO;
        _fontScroll.backgroundColor = [UIColor clearColor];
    }
    return _fontScroll;
}

-(void)reloadFontChips
{
    [self.fontScroll.subviews makeObjectsPerformSelector:@selector(removeFromSuperview)];
    self.fontOptions = [[RDFontManager sharedInstance] allOptions];
    NSString *currentName = [RDReadConfigManager sharedInstance].fontName;

    CGFloat x = 25;
    for (NSInteger i = 0; i < self.fontOptions.count; i++) {
        RDFontOption *option = self.fontOptions[i];
        UIButton *chip = [[UIButton alloc] init];
        chip.tag = i;
        [chip setTitle:option.displayName forState:UIControlStateNormal];
        chip.titleLabel.font = [RDFontManager readFontWithName:option.fontName size:14];
        chip.layer.cornerRadius = 15;
        chip.layer.borderWidth = 1;
        chip.contentEdgeInsets = UIEdgeInsetsMake(0, 14, 0, 14);
        BOOL selected = (option.fontName == nil && currentName.length == 0) ||
                        (option.fontName && [option.fontName isEqualToString:currentName]);
        [chip setTitleColor:selected ? RDAccentColor : RDGrayColor forState:UIControlStateNormal];
        chip.layer.borderColor = selected ? RDAccentColor.CGColor : RDSeparatorColor.CGColor;
        [chip addTarget:self action:@selector(chipClick:) forControlEvents:UIControlEventTouchUpInside];
        CGSize size = [chip sizeThatFits:CGSizeMake(CGFLOAT_MAX, 30)];
        chip.frame = CGRectMake(x, 0, MAX(size.width, 60), 30);
        [self.fontScroll addSubview:chip];
        x = CGRectGetMaxX(chip.frame) + 12;
    }
    self.fontScroll.contentSize = CGSizeMake(x + 13, 30);
}

-(void)chipClick:(UIButton *)sender
{
    RDFontOption *option = [self.fontOptions objectAtIndexSafely:sender.tag];
    [RDReadConfigManager sharedInstance].fontName = option.fontName ?: @"";
    [[RDReadConfigManager sharedInstance] archive];
    [self reloadFontChips];
}
-(UIImageView *)bigWord
{
    if (!_bigWord) {
        _bigWord = [[UIImageView alloc] init];
        _bigWord.image = [UIImage imageNamed:@"book_set_unselect"];
    }
    return _bigWord;
}

-(UIImageView *)smallWord
{
    if (!_smallWord) {
        _smallWord = [[UIImageView alloc] init];
        _smallWord.image = [UIImage imageNamed:@"book_set_unselect"];
    }
    return _smallWord;
}

-(StepSlider *)stepSlider
{
    if (!_stepSlider) {
        _stepSlider = [[StepSlider alloc] init];
        _stepSlider.maxCount = (kConfigMaxFontSize-kConfigMinFontSize)/2;
        _stepSlider.index = ([RDReadConfigManager sharedInstance].fontSize-kConfigMinFontSize)/2;
        _stepSlider.trackHeight = 1;
        _stepSlider.trackColor = RDSeparatorColor;
        [_stepSlider setTintColor:RDSeparatorColor];
        _stepSlider.sliderCircleRadius = 10;
        _stepSlider.sliderCircleColor = [UIColor whiteColor];
        _stepSlider.dotsInteractionEnabled = NO;
        [_stepSlider setTrackCircleImage:[UIImage imageNamed:@"step"] forState:UIControlStateNormal];
        [_stepSlider addTarget:self action:@selector(sliderFontSize:) forControlEvents:UIControlEventTouchUpInside];
        [_stepSlider addTarget:self action:@selector(sliderFontSize:) forControlEvents:UIControlEventTouchUpOutside];
    }
    return _stepSlider;
}

-(RDReadToolPageView *)pageView
{
    if (!_pageView) {
        _pageView = [[RDReadToolPageView alloc] init];
        _pageView.defaultType = [RDReadConfigManager sharedInstance].pageType;
        __weak typeof(self) ws = self;
        [_pageView setPageType:^(RDPageType type) {
            if ([ws.delegate respondsToSelector:@selector(didChangePageType)]) {
                [ws.delegate didChangePageType];
            }
        }];
    }
    return _pageView;
}

-(void)sliderFontSize:(StepSlider *)sender
{
    CGFloat fonSize = sender.index*2+kConfigMinFontSize;
    [RDReadConfigManager sharedInstance].lineSpace = fonSize-8;
//    [RDReadConfigManager sharedInstance].firstLineHeadIndent = fonSize * 2;
    [RDReadConfigManager sharedInstance].fontSize = fonSize;
    [[RDReadConfigManager sharedInstance] archive];
    
}
-(void)layoutSubviews
{
    [super layoutSubviews];
    self.smallWord.frame = CGRectMake(25, 25, 18, 18);
    self.bigWord.frame = CGRectMake(0, 0, 25, 25);
    self.bigWord.right = self.width-25;
    self.bigWord.centerY = self.smallWord.centerY;
    CGFloat sHeight = 44.f;
    self.stepSlider.frame = CGRectMake(self.smallWord.right+25, 0, self.width-self.smallWord.right-50-18-25, sHeight);
    self.stepSlider.centerY = self.smallWord.centerY+11;

    self.fontScroll.frame = CGRectMake(0, self.stepSlider.bottom+10, self.width, 30);
    self.pageView.frame = CGRectMake(0, self.fontScroll.bottom+14, self.width, 25);

}
@end
