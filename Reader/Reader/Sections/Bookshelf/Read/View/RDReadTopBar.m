//
//  RDReadTopBar.m
//  Reader
//
//  阅读页顶栏:返回 + 分享金句 + AI 翻译 + 听书
//

#import "RDReadTopBar.h"
#import "RDLayoutButton.h"
#import "RDReadConfigManager.h"

@interface RDReadTopBar ()
@property (nonatomic, strong) RDLayoutButton *backBtn;
@property (nonatomic, strong) UIButton *speechBtn;
@property (nonatomic, strong) UIButton *translateBtn;
@property (nonatomic, strong) UIButton *shareBtn;
@end

@implementation RDReadTopBar

-(instancetype)initWithFrame:(CGRect)frame
{
    self = [super initWithFrame:frame];
    if (self) {
        [self addSubview:self.backBtn];
        [self addSubview:self.shareBtn];
        [self addSubview:self.translateBtn];
        [self addSubview:self.speechBtn];
        [self applyChromeTheme];
    }
    return self;
}

- (void)applyChromeTheme
{
    RDReadConfigManager *cfg = [RDReadConfigManager sharedInstance];
    UIColor *bg = [cfg chromeBackgroundColor];
    UIColor *fg = [cfg chromeForegroundColor];
    self.backgroundColor = bg;

    UIImage *back = [[UIImage imageNamed:@"button_back"] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    [self.backBtn setImage:back forState:UIControlStateNormal];
    self.backBtn.tintColor = fg;

    [self p_restyleButton:self.speechBtn symbol:@"headphones" title:@"听" color:fg];
    [self p_restyleButton:self.translateBtn symbol:@"globe" title:@"译" color:fg];
    [self p_restyleButton:self.shareBtn symbol:@"square.and.arrow.up" title:@"享" color:fg];
}

- (void)p_restyleButton:(UIButton *)btn symbol:(NSString *)name title:(NSString *)title color:(UIColor *)color
{
    UIImageSymbolConfiguration *config = [UIImageSymbolConfiguration configurationWithPointSize:15 weight:UIImageSymbolWeightRegular];
    UIImage *icon = [[UIImage systemImageNamed:name withConfiguration:config] imageWithTintColor:color renderingMode:UIImageRenderingModeAlwaysOriginal];
    [btn setImage:icon forState:UIControlStateNormal];
    [btn setTitle:[NSString stringWithFormat:@" %@", title] forState:UIControlStateNormal];
    [btn setTitleColor:color forState:UIControlStateNormal];
}

- (RDLayoutButton *)backBtn {
    if (!_backBtn) {
        RDLayoutButton *button = [[RDLayoutButton alloc] initWithFrame:CGRectMake(0, [UIView statusBar], 40, [UIView navigationBar])];
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        button.adjustsImageWhenDisabled = NO;
#pragma clang diagnostic pop
        button.imageSize = CGSizeMake(11, 19);
        _backBtn = button;
        [_backBtn addTarget:self action:@selector(click:) forControlEvents:UIControlEventTouchUpInside];
    }
    return _backBtn;
}

- (UIButton *)p_iconButtonWithSymbol:(NSString *)name title:(NSString *)title
{
    UIButton *btn = [[UIButton alloc] init];
    btn.titleLabel.font = RDFont13;
    [btn addTarget:self action:@selector(click:) forControlEvents:UIControlEventTouchUpInside];
    [self p_restyleButton:btn symbol:name title:title color:RDBlackColor];
    return btn;
}

- (UIButton *)translateBtn
{
    if (!_translateBtn) {
        _translateBtn = [self p_iconButtonWithSymbol:@"globe" title:@"译"];
    }
    return _translateBtn;
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
    else if (sender == self.translateBtn) {
        if ([self.delegate respondsToSelector:@selector(translateAction)]) {
            [self.delegate translateAction];
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
    self.translateBtn.frame = CGRectMake(0, y, btnW, height);
    self.translateBtn.right = self.speechBtn.left - gap;
    self.shareBtn.frame = CGRectMake(0, y, btnW, height);
    self.shareBtn.right = self.translateBtn.left - gap;
}

@end
