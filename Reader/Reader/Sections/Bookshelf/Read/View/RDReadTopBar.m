//
//  RDReadTopBar.m
//  Reader
//
//  阅读页顶栏:返回 + 分享金句 + 听书
//

#import "RDReadTopBar.h"
#import "RDLayoutButton.h"

@interface RDReadTopBar ()
@property (nonatomic, strong) RDLayoutButton *backBtn;
@property (nonatomic, strong) UIButton *speechBtn;
@property (nonatomic, strong) UIButton *shareBtn;
@end

@implementation RDReadTopBar

-(instancetype)initWithFrame:(CGRect)frame
{
    self = [super initWithFrame:frame];
    if (self) {
        [self addSubview:self.backBtn];
        [self addSubview:self.shareBtn];
        [self addSubview:self.speechBtn];
        [self setBackgroundColor:RDReadBg];
    }
    return self;
}

- (RDLayoutButton *)backBtn {
    if (!_backBtn) {
        RDLayoutButton *button = [[RDLayoutButton alloc] initWithFrame:CGRectMake(0, [UIView statusBar], 40, [UIView navigationBar])];
        button.adjustsImageWhenDisabled = NO;
        [button setImage:[UIImage imageNamed:@"button_back"] forState:UIControlStateNormal];
        button.imageSize = CGSizeMake(11, 19);
        _backBtn = button;
        [_backBtn addTarget:self action:@selector(click:) forControlEvents:UIControlEventTouchUpInside];
    }
    return _backBtn;
}

- (UIButton *)p_iconButtonWithSymbol:(NSString *)name title:(NSString *)title
{
    UIButton *btn = [[UIButton alloc] init];
    UIImageSymbolConfiguration *config = [UIImageSymbolConfiguration configurationWithPointSize:15 weight:UIImageSymbolWeightRegular];
    UIImage *icon = [[UIImage systemImageNamed:name withConfiguration:config] imageWithTintColor:RDBlackColor renderingMode:UIImageRenderingModeAlwaysOriginal];
    [btn setImage:icon forState:UIControlStateNormal];
    [btn setTitle:[NSString stringWithFormat:@" %@", title] forState:UIControlStateNormal];
    [btn setTitleColor:RDBlackColor forState:UIControlStateNormal];
    btn.titleLabel.font = RDFont13;
    [btn addTarget:self action:@selector(click:) forControlEvents:UIControlEventTouchUpInside];
    return btn;
}

- (UIButton *)speechBtn
{
    if (!_speechBtn) {
        _speechBtn = [self p_iconButtonWithSymbol:@"headphones" title:@"听"];
    }
    return _speechBtn;
}

- (UIButton *)shareBtn
{
    if (!_shareBtn) {
        _shareBtn = [self p_iconButtonWithSymbol:@"square.and.arrow.up" title:@"享"];
    }
    return _shareBtn;
}

-(void)click:(UIButton *)sender
{
    if (sender == self.backBtn) {
        if ([self.delegate respondsToSelector:@selector(backAction)]) {
            [self.delegate backAction];
        }
    }
    else if (sender == self.speechBtn) {
        if ([self.delegate respondsToSelector:@selector(speechAction)]) {
            [self.delegate speechAction];
        }
    }
    else if (sender == self.shareBtn) {
        if ([self.delegate respondsToSelector:@selector(shareQuoteAction)]) {
            [self.delegate shareQuoteAction];
        }
    }
}

-(void)layoutSubviews
{
    [super layoutSubviews];
    CGFloat height = [UIView navigationBar];
    CGFloat y = [UIView statusBar];
    CGFloat btnW = 52;
    CGFloat gap = 2;
    self.speechBtn.frame = CGRectMake(0, y, btnW, height);
    self.speechBtn.right = self.width - 4;
    self.shareBtn.frame = CGRectMake(0, y, btnW, height);
    self.shareBtn.right = self.speechBtn.left - gap;
}

@end
