//
//  RDReadToolTheme.m
//  Reader
//
//  阅读主题色板:素笺 / 旧书页 / 青灰笺 / 竹纸 / 夜读
//

#import "RDReadToolTheme.h"
#import "RDLayoutButton.h"
#import "RDReadConfigManager.h"

@interface RDReadToolTheme ()
@property (nonatomic,strong) RDLayoutButton *white;
@property (nonatomic,strong) RDLayoutButton *yellow;
@property (nonatomic,strong) RDLayoutButton *blue;
@property (nonatomic,strong) RDLayoutButton *green;
@property (nonatomic,strong) RDLayoutButton *black;
@property (nonatomic,strong) RDLayoutButton *selectTheme;

@property (nonatomic,strong) UIImageView *greenIcon;
@property (nonatomic,strong) UIImageView *blackIcon;
@end

@implementation RDReadToolTheme

- (instancetype)initWithFrame:(CGRect)frame
{
    self = [super initWithFrame:frame];
    if (self) {
        [self addSubview:self.white];
        [self addSubview:self.yellow];
        [self addSubview:self.blue];
        [self addSubview:self.green];
        [self.green addSubview:self.greenIcon];
        [self addSubview:self.black];
        [self.black addSubview:self.blackIcon];
        self.accessibilityLabel = @"阅读纸色";
    }
    return self;
}

- (RDLayoutButton *)p_swatchButtonForTheme:(RDThemeType)theme
{
    RDLayoutButton *btn = [[RDLayoutButton alloc] init];
    CGFloat d = 28;
    UIImage *swatch = [RDReadConfigManager swatchImageForTheme:theme diameter:d];
    UIImage *ring = [RDReadConfigManager selectionRingForTheme:theme diameter:d + 8];
    [btn setImage:swatch forState:UIControlStateNormal];
    [btn setImage:swatch forState:UIControlStateHighlighted];
    [btn setImage:swatch forState:UIControlStateSelected];
    btn.imageView.layer.cornerRadius = d / 2;
    btn.imageView.clipsToBounds = YES;
    btn.imageView.layer.borderWidth = 0.5;
    btn.imageView.layer.borderColor = [[UIColor colorWithWhite:0 alpha:0.08] CGColor];
    [btn setImageSize:CGSizeMake(d, d)];
    [btn setBackgroundImage:nil forState:UIControlStateNormal];
    [btn setBackgroundImage:ring forState:UIControlStateSelected];
    [btn addTarget:self action:@selector(click:) forControlEvents:UIControlEventTouchUpInside];
    btn.accessibilityLabel = [RDReadConfigManager displayNameForTheme:theme];
    btn.accessibilityTraits = UIAccessibilityTraitButton;
    return btn;
}

-(void)setTheme:(RDThemeType)theme
{
    self.white.selected = NO;
    self.yellow.selected = NO;
    self.blue.selected = NO;
    self.green.selected = NO;
    self.black.selected = NO;
    switch (theme) {
        case RDWhiteTheme:
            self.white.selected = YES;
            self.selectTheme = self.white;
            break;
        case RDYellowTheme:
            self.yellow.selected = YES;
            self.selectTheme = self.yellow;
            break;
        case RDBlueTheme:
            self.blue.selected = YES;
            self.selectTheme = self.blue;
            break;
        case RDGreenTheme:
            self.green.selected = YES;
            self.selectTheme = self.green;
            break;
        case RDBlackTheme:
            self.black.selected = YES;
            self.selectTheme = self.black;
            break;
    }
}

-(RDLayoutButton *)white
{
    if (!_white) {
        _white = [self p_swatchButtonForTheme:RDWhiteTheme];
    }
    return _white;
}
-(RDLayoutButton *)yellow
{
    if (!_yellow) {
        _yellow = [self p_swatchButtonForTheme:RDYellowTheme];
    }
    return _yellow;
}

-(RDLayoutButton *)blue
{
    if (!_blue) {
        _blue = [self p_swatchButtonForTheme:RDBlueTheme];
    }
    return _blue;
}

-(RDLayoutButton *)green
{
    if (!_green) {
        _green = [self p_swatchButtonForTheme:RDGreenTheme];
    }
    return _green;
}

-(RDLayoutButton *)black
{
    if (!_black) {
        _black = [self p_swatchButtonForTheme:RDBlackTheme];
    }
    return _black;
}

-(UIImageView *)greenIcon
{
    if (!_greenIcon) {
        _greenIcon = [[UIImageView alloc] initWithImage:[UIImage imageNamed:@"theme_eye"]];
        _greenIcon.userInteractionEnabled = NO;
        // 竹纸上图标略淡,不抢纸色
        _greenIcon.alpha = 0.85;
    }
    return _greenIcon;
}

-(UIImageView *)blackIcon
{
    if (!_blackIcon) {
        _blackIcon = [[UIImageView alloc] initWithImage:[UIImage imageNamed:@"theme_moon"]];
        _blackIcon.userInteractionEnabled = NO;
        _blackIcon.alpha = 0.9;
    }
    return _blackIcon;
}

-(void)click:(RDLayoutButton *)sender
{
    self.selectTheme.selected = NO;
    sender.selected = YES;
    self.selectTheme = sender;
    RDThemeType type = RDWhiteTheme;
    if (sender == self.white) {
        type = RDWhiteTheme;
    }
    else if (sender == self.yellow){
        type = RDYellowTheme;
    }
    else if (sender == self.blue){
        type = RDBlueTheme;
    }
    else if (sender == self.green){
        type = RDGreenTheme;
    }
    else if (sender == self.black){
        type = RDBlackTheme;
    }
    [RDReadConfigManager sharedInstance].theme = type;
    [[RDReadConfigManager sharedInstance] archive];
}
-(void)layoutSubviews
{
    [super layoutSubviews];
    CGFloat width = 36;
    CGFloat spacing = (self.width-40-width*5)/4;
    self.white.frame = CGRectMake(20, 0, width, self.height);
    self.yellow.frame = CGRectMake(self.white.right+spacing,0, width, self.height);
    self.blue.frame = CGRectMake(self.yellow.right+spacing, 0, width, self.height);
    self.green.frame = CGRectMake(self.blue.right+spacing, 0, width, self.height);
    self.black.frame = CGRectMake(self.green.right+spacing, 0, width, self.height);
    self.greenIcon.frame = CGRectMake(0, 0, 16, 16);
    self.greenIcon.center = CGPointMake(self.green.width/2, self.green.height/2);
    self.blackIcon.frame = CGRectMake(0, 0, 16, 16);
    self.blackIcon.center = CGPointMake(self.black.width/2, self.black.height/2);
}

@end
