//
//  RDReadProgressView.m
//  Reader
//
//  Created by yuenov on 2019/11/19.
//  Copyright © 2019 yuenov. All rights reserved.
//

#import "RDReadProgressView.h"
#import "RDBookDetailModel.h"
#import "RDCharpterModel.h"
#import "RDLayoutButton.h"
#import "RDReadConfigManager.h"
/// 图标视觉尺寸,与阅读工具栏的图标保持一致(RDReadToolBar 也是 24)
static const CGFloat kRDProgressArrowIconSize = 24;
/// 点击区域,满足 HIG 的 44pt 最小可点目标
static const CGFloat kRDProgressArrowHitSize = 44;

@interface RDReadProgressView  ()
@property (nonatomic,strong) RDLayoutButton *left;
@property (nonatomic,strong) RDLayoutButton *right;
@property (nonatomic,strong) UISlider *slider;
@property (nonatomic,strong) UILabel *chapterLabel;
@end
@implementation RDReadProgressView

-(instancetype)initWithFrame:(CGRect)frame
{
    self = [super initWithFrame:frame];
    if (self) {
        [self addSubview:self.chapterLabel];
        [self addSubview:self.slider];
        [self addSubview:self.left];
        [self addSubview:self.right];
        [self applyChromeTheme];
    }
    return self;
}

- (void)applyChromeTheme
{
    RDReadConfigManager *cfg = [RDReadConfigManager sharedInstance];
    UIColor *bg = [cfg chromeBackgroundColor];
    UIColor *fg = [cfg chromeForegroundColor];
    UIColor *sec = [cfg chromeSecondaryColor];
    self.backgroundColor = bg;
    self.chapterLabel.textColor = sec;
    self.slider.minimumTrackTintColor = RDAccentColor;
    self.slider.maximumTrackTintColor = [cfg chromeSeparatorColor];
    UIImage *leftImg = [[[UIImage imageNamed:@"read_progress_left"] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate] imageWithTintColor:fg renderingMode:UIImageRenderingModeAlwaysOriginal];
    UIImage *rightImg = [[[UIImage imageNamed:@"read_progress_right"] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate] imageWithTintColor:fg renderingMode:UIImageRenderingModeAlwaysOriginal];
    [self.left setImage:leftImg forState:UIControlStateNormal];
    [self.right setImage:rightImg forState:UIControlStateNormal];
}

-(void)setCharpters:(NSArray<RDCharpterModel *> *)charpters
{
    _charpters = charpters;
}


-(void)setBook:(RDBookDetailModel *)book
{
    _book = book;
    self.chapterLabel.text = book.charpterModel.name;
    NSInteger index = [self.charpters indexOfObject:book.charpterModel];
    if (index != NSNotFound) {
        // 分母用 count-1:否则最后一章也到不了滑块最右端,与 jump:/cancel: 的换算不一致
        self.slider.value = self.charpters.count > 1
            ? index / (CGFloat)(self.charpters.count - 1)
            : 0;
    }
    [self p_updateArrowStatesForIndex:(index == NSNotFound ? 0 : index)];
}

-(UILabel *)chapterLabel
{
    if (!_chapterLabel) {
        _chapterLabel = [[UILabel alloc] init];
        _chapterLabel.textColor = RDGrayColor;
        _chapterLabel.font = RDFont14;
        _chapterLabel.textAlignment = NSTextAlignmentCenter;
    }
    return _chapterLabel;
}

/// 原先左右箭头是 UIImageView,没有任何 target-action,点了不响应 —— 纯装饰的假按钮。
/// 改用项目自带的 RDLayoutButton:它的 imageSize 能把图标固定在设计尺寸,
/// 与按钮本身的点击区域解耦(素材原图 35pt,直接塞进 UIButton 会按原尺寸铺开)。
-(RDLayoutButton *)p_arrowButtonWithImage:(NSString *)imageName action:(SEL)action
{
    RDLayoutButton *button = [[RDLayoutButton alloc] init];
    [button setImage:[UIImage imageNamed:imageName] forState:UIControlStateNormal];
    button.imageSize = CGSizeMake(kRDProgressArrowIconSize, kRDProgressArrowIconSize);
    [button addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    return button;
}

-(RDLayoutButton *)left
{
    if (!_left) {
        _left = [self p_arrowButtonWithImage:@"read_progress_left" action:@selector(p_previousChapter)];
    }
    return _left;
}

-(RDLayoutButton *)right
{
    if (!_right) {
        _right = [self p_arrowButtonWithImage:@"read_progress_right" action:@selector(p_nextChapter)];
    }
    return _right;
}

/// 当前章节在目录中的下标;找不到时回退到滑块位置
-(NSInteger)p_currentIndex
{
    if (self.charpters.count == 0) {
        return NSNotFound;
    }
    NSInteger index = [self.charpters indexOfObject:self.book.charpterModel];
    if (index == NSNotFound) {
        index = (NSInteger)roundf(self.slider.value * (self.charpters.count - 1));
    }
    return MAX(0, MIN(index, (NSInteger)self.charpters.count - 1));
}

-(void)p_stepBy:(NSInteger)delta
{
    NSInteger current = [self p_currentIndex];
    if (current == NSNotFound) {
        return;
    }
    NSInteger target = current + delta;
    if (target < 0 || target >= (NSInteger)self.charpters.count) {
        return;   // 已在首/末章,不做环绕
    }
    RDCharpterModel *charpter = self.charpters[target];
    // 先把本视图的显示同步过去,再通知外部真正跳章
    self.chapterLabel.text = charpter.name;
    if (self.charpters.count > 1) {
        self.slider.value = target / (CGFloat)(self.charpters.count - 1);
    }
    [self p_updateArrowStatesForIndex:target];
    if ([self.delegate respondsToSelector:@selector(sliderToCharpter:)]) {
        [self.delegate sliderToCharpter:charpter];
    }
}

-(void)p_previousChapter
{
    [self p_stepBy:-1];
}

-(void)p_nextChapter
{
    [self p_stepBy:1];
}

/// 首/末章时把对应箭头置灰,避免点了没反应又没有任何反馈
-(void)p_updateArrowStatesForIndex:(NSInteger)index
{
    NSInteger count = (NSInteger)self.charpters.count;
    BOOL hasPrev = (count > 0 && index > 0);
    BOOL hasNext = (count > 0 && index < count - 1);
    self.left.enabled = hasPrev;
    self.right.enabled = hasNext;
    self.left.alpha = hasPrev ? 1.0 : 0.35;
    self.right.alpha = hasNext ? 1.0 : 0.35;
}

-(UISlider *)slider
{
    if (!_slider) {
        _slider = [[UISlider alloc] init];
        _slider.minimumTrackTintColor = RDAccentColor;
        _slider.maximumTrackTintColor = RDSeparatorColor;
        _slider.minimumValue = 0;
        _slider.maximumValue = 1;
        [_slider addTarget:self action:@selector(jump:) forControlEvents:UIControlEventValueChanged];
        [_slider setThumbImage:[UIImage imageNamed:@"white_slider"] forState:UIControlStateNormal];
        [_slider addTarget:self action:@selector(cancel:) forControlEvents:UIControlEventTouchUpInside];
        [_slider addTarget:self action:@selector(cancel:) forControlEvents:UIControlEventTouchUpOutside];
    }
    return _slider;
}

-(void)layoutSubviews
{
    [super layoutSubviews];
    self.chapterLabel.frame = CGRectMake(20, 20, self.width-40, RDFont14.lineHeight);

    // 图标按设计尺寸(24)绘制,按钮本体放大到 44×44 命中区,两者解耦。
    const CGFloat iconSize = kRDProgressArrowIconSize;
    const CGFloat hitSize = kRDProgressArrowHitSize;
    CGFloat iconCenterY = self.chapterLabel.bottom + 15 + iconSize / 2;
    CGFloat leftCenterX = 20 + iconSize / 2;
    CGFloat rightCenterX = self.width - 20 - iconSize / 2;

    self.left.frame = CGRectMake(leftCenterX - hitSize / 2, iconCenterY - hitSize / 2, hitSize, hitSize);
    self.right.frame = CGRectMake(rightCenterX - hitSize / 2, iconCenterY - hitSize / 2, hitSize, hitSize);

    CGFloat sliderLeft = 20 + iconSize + 15;
    CGFloat sliderRight = self.width - 20 - iconSize - 15;
    self.slider.frame = CGRectMake(sliderLeft, 0, sliderRight - sliderLeft, 20);
    self.slider.centerY = iconCenterY;
}

-(void)jump:(UISlider *)sender
{
    NSInteger index = sender.value * (self.charpters.count-1);
    if (index<self.charpters.count) {
        RDCharpterModel *charpter = self.charpters[index];
        self.chapterLabel.text = charpter.name;
    }
}
-(void)cancel:(UISlider *)sender
{
    if ([self.delegate respondsToSelector:@selector(sliderToCharpter:)]) {
        NSInteger index = sender.value * (self.charpters.count-1);
        if (index<self.charpters.count) {
            RDCharpterModel *charpter = self.charpters[index];
            [self.delegate sliderToCharpter:charpter];
        }
    }
}
@end
