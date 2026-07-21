//
//  RDReadToolBar.m
//  Reader
//
//  阅读底栏:目录 · 书签 · 亮度 · 设置
//

#import "RDReadToolBar.h"
#import "RDReadConfigManager.h"

@interface RDReadToolBar ()
@property (nonatomic,strong) RDLayoutButton *lastButton;
@end

@implementation RDReadToolBar
-(instancetype)initWithFrame:(CGRect)frame
{
    self = [super initWithFrame:frame];
    if (self) {
        [self addSubview:self.menu];
        [self addSubview:self.bookmark];
        [self addSubview:self.light];
        [self addSubview:self.setting];
        [self applyChromeTheme];
    }
    return self;
}

- (UIImage *)p_tintedImageNamed:(NSString *)name color:(UIColor *)color
{
    UIImage *img = [UIImage imageNamed:name];
    if (!img) {
        return nil;
    }
    return [[img imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate] imageWithTintColor:color renderingMode:UIImageRenderingModeAlwaysOriginal];
}

- (void)applyChromeTheme
{
    RDReadConfigManager *cfg = [RDReadConfigManager sharedInstance];
    UIColor *bg = [cfg chromeBackgroundColor];
    UIColor *fg = [cfg chromeForegroundColor];
    UIColor *accent = RDAccentColor;
    self.backgroundColor = bg;

    [self.menu setImage:[self p_tintedImageNamed:@"book_menu_unselect" color:fg] forState:UIControlStateNormal];
    [self.menu setImage:[self p_tintedImageNamed:@"book_menu_select" color:accent] forState:UIControlStateSelected];
    [self.light setImage:[self p_tintedImageNamed:@"book_light_unselect" color:fg] forState:UIControlStateNormal];
    [self.light setImage:[self p_tintedImageNamed:@"book_light_select" color:accent] forState:UIControlStateSelected];
    [self.setting setImage:[self p_tintedImageNamed:@"book_set_unselect" color:fg] forState:UIControlStateNormal];
    [self.setting setImage:[self p_tintedImageNamed:@"book_set_select" color:accent] forState:UIControlStateSelected];

    UIImageSymbolConfiguration *config = [UIImageSymbolConfiguration configurationWithPointSize:20 weight:UIImageSymbolWeightRegular];
    UIImage *n = [[UIImage systemImageNamed:@"bookmark" withConfiguration:config] imageWithTintColor:fg renderingMode:UIImageRenderingModeAlwaysOriginal];
    UIImage *s = [[UIImage systemImageNamed:@"bookmark.fill" withConfiguration:config] imageWithTintColor:accent renderingMode:UIImageRenderingModeAlwaysOriginal];
    [self.bookmark setImage:n forState:UIControlStateNormal];
    [self.bookmark setImage:s forState:UIControlStateSelected];
}

-(RDLayoutButton *)p_buttonWithImage:(NSString *)normal selected:(NSString *)selected
{
    RDLayoutButton *btn = [[RDLayoutButton alloc] init];
    [btn setImage:[UIImage imageNamed:normal] forState:UIControlStateNormal];
    if (selected.length) {
        [btn setImage:[UIImage imageNamed:selected] forState:UIControlStateSelected];
    }
    btn.imageSize = CGSizeMake(24, 24);
    [btn addTarget:self action:@selector(click:) forControlEvents:UIControlEventTouchUpInside];
    return btn;
}

-(RDLayoutButton *)menu
{
    if (!_menu) {
        _menu = [self p_buttonWithImage:@"book_menu_unselect" selected:@"book_menu_select"];
    }
    return _menu;
}

-(RDLayoutButton *)bookmark
{
    if (!_bookmark) {
        _bookmark = [[RDLayoutButton alloc] init];
        UIImageSymbolConfiguration *config = [UIImageSymbolConfiguration configurationWithPointSize:20 weight:UIImageSymbolWeightRegular];
        UIImage *n = [[UIImage systemImageNamed:@"bookmark" withConfiguration:config] imageWithTintColor:RDBlackColor renderingMode:UIImageRenderingModeAlwaysOriginal];
        UIImage *s = [[UIImage systemImageNamed:@"bookmark.fill" withConfiguration:config] imageWithTintColor:RDAccentColor renderingMode:UIImageRenderingModeAlwaysOriginal];
        [_bookmark setImage:n forState:UIControlStateNormal];
        [_bookmark setImage:s forState:UIControlStateSelected];
        _bookmark.imageSize = CGSizeMake(22, 22);
        [_bookmark addTarget:self action:@selector(click:) forControlEvents:UIControlEventTouchUpInside];
    }
    return _bookmark;
}

-(RDLayoutButton *)light
{
    if (!_light) {
        _light = [self p_buttonWithImage:@"book_light_unselect" selected:@"book_light_select"];
    }
    return _light;
}

-(RDLayoutButton *)setting
{
    if (!_setting) {
        _setting = [self p_buttonWithImage:@"book_set_unselect" selected:@"book_set_select"];
    }
    return _setting;
}

-(void)click:(RDLayoutButton *)sender
{
    if (sender != self.lastButton) {
        self.lastButton.selected = NO;
    }
    sender.selected = !sender.selected;
    self.lastButton = sender;
    if (sender == self.menu) {
        if ([self.delegate respondsToSelector:@selector(didMenu)]) {
            [self.delegate didMenu];
        }
    }
    else if (sender == self.bookmark) {
        if ([self.delegate respondsToSelector:@selector(didBookmark)]) {
            [self.delegate didBookmark];
        }
    }
    else if (sender == self.light) {
        if ([self.delegate respondsToSelector:@selector(didLight)]) {
            [self.delegate didLight];
        }
    }
    else if (sender == self.setting) {
        if ([self.delegate respondsToSelector:@selector(didSetting)]) {
            [self.delegate didSetting];
        }
    }
}

-(void)layoutSubviews
{
    [super layoutSubviews];
    // 四等分:目录 · 书签 · 亮度 · 设置
    CGFloat width = self.width / 4.0;
    CGFloat h = self.height - [UIView safeBottomBar];
    self.menu.frame = CGRectMake(0, 0, width, h);
    self.bookmark.frame = CGRectMake(width, 0, width, h);
    self.light.frame = CGRectMake(width * 2, 0, width, h);
    self.setting.frame = CGRectMake(width * 3, 0, width, h);
}

@end
