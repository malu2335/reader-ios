//
//  RDReadTopBar.m
//  Reader
//

#import "RDReadTopBar.h"
#import "RDLayoutButton.h"

@interface RDReadTopBar ()
@property(nonatomic, strong) RDLayoutButton *backBtn;
@property (nonatomic,strong) UIButton *speechBtn;
@property (nonatomic,strong) UIButton *translateBtn;
@end
@implementation RDReadTopBar

-(instancetype)initWithFrame:(CGRect)frame
{
    self = [super initWithFrame:frame];
    if (self) {
        [self addSubview:self.backBtn];
        [self addSubview:self.translateBtn];
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

- (UIButton *)translateBtn
{
    if (!_translateBtn) {
        _translateBtn = [[UIButton alloc] init];
        UIImageSymbolConfiguration *config = [UIImageSymbolConfiguration configurationWithPointSize:16 weight:UIImageSymbolWeightRegular];
        UIImage *icon = [[UIImage systemImageNamed:@"globe" withConfiguration:config] imageWithTintColor:RDBlackColor renderingMode:UIImageRenderingModeAlwaysOriginal];
        [_translateBtn setImage:icon forState:UIControlStateNormal];
        [_translateBtn setTitle:@" 翻译" forState:UIControlStateNormal];
        [_translateBtn setTitleColor:RDBlackColor forState:UIControlStateNormal];
        _translateBtn.titleLabel.font = RDFont15;
        [_translateBtn addTarget:self action:@selector(click:) forControlEvents:UIControlEventTouchUpInside];
    }
    return _translateBtn;
}

- (UIButton *)speechBtn
{
    if (!_speechBtn) {
        _speechBtn = [[UIButton alloc] init];
        UIImageSymbolConfiguration *config = [UIImageSymbolConfiguration configurationWithPointSize:17 weight:UIImageSymbolWeightRegular];
        UIImage *icon = [[UIImage systemImageNamed:@"headphones" withConfiguration:config] imageWithTintColor:RDBlackColor renderingMode:UIImageRenderingModeAlwaysOriginal];
        [_speechBtn setImage:icon forState:UIControlStateNormal];
        [_speechBtn setTitle:@" 听书" forState:UIControlStateNormal];
        [_speechBtn setTitleColor:RDBlackColor forState:UIControlStateNormal];
        _speechBtn.titleLabel.font = RDFont15;
        [_speechBtn addTarget:self action:@selector(click:) forControlEvents:UIControlEventTouchUpInside];
    }
    return _speechBtn;
}

-(void)click:(UIButton *)sender
{
    if (sender == self.backBtn) {
        if ([self.delegate respondsToSelector:@selector(backAction)]) {
            [self.delegate backAction];
        }
    }
    else if (sender == self.speechBtn){
        if ([self.delegate respondsToSelector:@selector(speechAction)]) {
            [self.delegate speechAction];
        }
    }
    else if (sender == self.translateBtn) {
        if ([self.delegate respondsToSelector:@selector(translateAction)]) {
            [self.delegate translateAction];
        }
    }
}

-(void)layoutSubviews
{
    [super layoutSubviews];
    CGFloat height = [UIView navigationBar];
    CGFloat y = [UIView statusBar];
    self.speechBtn.frame = CGRectMake(0, y, 72, height);
    self.speechBtn.right = self.width - 8;
    self.translateBtn.frame = CGRectMake(0, y, 72, height);
    self.translateBtn.right = self.speechBtn.left - 4;
}
@end
