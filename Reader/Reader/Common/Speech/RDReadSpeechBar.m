//
//  RDReadSpeechBar.m
//  Reader
//

#import "RDReadSpeechBar.h"

@interface RDReadSpeechBar ()
@property (nonatomic,strong) UIButton *playBtn;
@property (nonatomic,strong) UIButton *rateBtn;
@property (nonatomic,strong) UIButton *exitBtn;
@end

@implementation RDReadSpeechBar

- (instancetype)initWithFrame:(CGRect)frame
{
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = RDSurfaceColor;
        self.layer.cornerRadius = 25;
        self.layer.borderWidth = 1.0 / UIScreen.mainScreen.scale;
        self.layer.borderColor = RDSeparatorColor.CGColor;
        self.layer.shadowColor = [UIColor colorWithHexValue:0x8F5B3B alpha:0.18].CGColor;
        self.layer.shadowOffset = CGSizeMake(0, 4);
        self.layer.shadowRadius = 12;
        self.layer.shadowOpacity = 1;
        [self addSubview:self.playBtn];
        [self addSubview:self.rateBtn];
        [self addSubview:self.exitBtn];
    }
    return self;
}

- (UIButton *)playBtn
{
    if (!_playBtn) {
        _playBtn = [[UIButton alloc] init];
        [_playBtn addTarget:self action:@selector(click:) forControlEvents:UIControlEventTouchUpInside];
    }
    return _playBtn;
}

- (UIButton *)rateBtn
{
    if (!_rateBtn) {
        _rateBtn = [[UIButton alloc] init];
        [_rateBtn setTitleColor:RDGrayColor forState:UIControlStateNormal];
        _rateBtn.titleLabel.font = RDBoldFont14;
        [_rateBtn addTarget:self action:@selector(click:) forControlEvents:UIControlEventTouchUpInside];
    }
    return _rateBtn;
}

- (UIButton *)exitBtn
{
    if (!_exitBtn) {
        _exitBtn = [[UIButton alloc] init];
        UIImageSymbolConfiguration *config = [UIImageSymbolConfiguration configurationWithPointSize:16 weight:UIImageSymbolWeightMedium];
        UIImage *icon = [[UIImage systemImageNamed:@"xmark" withConfiguration:config] imageWithTintColor:RDGrayColor renderingMode:UIImageRenderingModeAlwaysOriginal];
        [_exitBtn setImage:icon forState:UIControlStateNormal];
        [_exitBtn addTarget:self action:@selector(click:) forControlEvents:UIControlEventTouchUpInside];
    }
    return _exitBtn;
}

- (void)click:(UIButton *)sender
{
    if (sender == self.playBtn && self.onPlayPause) {
        self.onPlayPause();
    }
    else if (sender == self.rateBtn && self.onRate) {
        self.onRate();
    }
    else if (sender == self.exitBtn && self.onExit) {
        self.onExit();
    }
}

- (void)updatePlaying:(BOOL)playing rate:(CGFloat)rate
{
    UIImageSymbolConfiguration *config = [UIImageSymbolConfiguration configurationWithPointSize:20 weight:UIImageSymbolWeightMedium];
    NSString *symbol = playing ? @"pause.fill" : @"play.fill";
    UIImage *icon = [[UIImage systemImageNamed:symbol withConfiguration:config] imageWithTintColor:RDAccentColor renderingMode:UIImageRenderingModeAlwaysOriginal];
    [self.playBtn setImage:icon forState:UIControlStateNormal];
    [self.rateBtn setTitle:[NSString stringWithFormat:@"%.2gx", rate] forState:UIControlStateNormal];
}

- (void)showInView:(UIView *)view
{
    CGFloat width = 200, height = 50;
    self.frame = CGRectMake((view.width - width) / 2, view.height - height - [UIView safeBottomBar] - 24, width, height);
    self.alpha = 0;
    [view addSubview:self];
    [UIView animateWithDuration:0.25 animations:^{
        self.alpha = 1;
    }];
}

- (void)layoutSubviews
{
    [super layoutSubviews];
    CGFloat third = self.width / 3;
    self.playBtn.frame = CGRectMake(0, 0, third, self.height);
    self.rateBtn.frame = CGRectMake(third, 0, third, self.height);
    self.exitBtn.frame = CGRectMake(third * 2, 0, third, self.height);
}

@end
