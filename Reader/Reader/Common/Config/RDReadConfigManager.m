//
//  RDReadConfigManager.m
//  Reader
//
//  阅读主题模拟真实纸张:纤维噪点、微渐变、暖调墨色;夜读为柔和炭黑非纯黑。
//

#import "RDReadConfigManager.h"
#import "RDModelAgent.h"
#import "RDDisplayBoost.h"

static NSString * const kPromotedSliderPageOnProMotionKey = @"RDPromotedSliderPageOnProMotion_v1";
NSString * const RDReadThemeDidChangeNotification = @"RDReadThemeDidChangeNotification";

/// 纸张基底色板(sRGB 直观值)
typedef struct {
    uint32_t base;       // 主纸色
    uint32_t baseHi;     // 顶部略亮(窗光)
    uint32_t baseLo;     // 底部略暗
    uint32_t fiber;      // 纤维/杂质色
    uint32_t ink;        // 正文墨色
    uint32_t inkLight;   // 辅文/章节小字
    uint32_t tool;       // 电量时间
} RDPaperPalette;

static RDPaperPalette RDPaperPaletteForTheme(RDThemeType theme)
{
    // 色值参考:宣纸、旧书页、青灰信笺、竹纸、灯下夜读
    switch (theme) {
        case RDWhiteTheme: // 素笺 — 冷白宣纸,轻微纤维
            return (RDPaperPalette){ 0xF6F2EA, 0xFAF7F1, 0xEFE9DF, 0xD9D2C6, 0x2B2824, 0x9A948A, 0x8A847A };
        case RDYellowTheme: // 旧书页 — 米黄书页,时间的暖
            return (RDPaperPalette){ 0xF0E2C4, 0xF5EAD2, 0xE8D6AE, 0xD4C09A, 0x3A3126, 0xA09078, 0x96866E };
        case RDBlueTheme: // 青灰笺 — 淡青灰信纸
            return (RDPaperPalette){ 0xE6EBF0, 0xEEF2F5, 0xDCE3EA, 0xC5CED8, 0x2A333B, 0x87929C, 0x76828C };
        case RDGreenTheme: // 竹纸 — 微绿护眼纸
            return (RDPaperPalette){ 0xE4EBD8, 0xECF1E4, 0xD8E2C8, 0xC2CFB0, 0x2A3328, 0x87967E, 0x78886F };
        case RDBlackTheme: // 夜读 — 暖炭底 + 米黄字,减轻眩光
            return (RDPaperPalette){ 0x1C1A18, 0x24211E, 0x141210, 0x2E2A26, 0xD0C6B6, 0x6A6258, 0x7A7268 };
    }
    return RDPaperPaletteForTheme(RDYellowTheme);
}

static UIColor *RDUIColorHex(uint32_t hex)
{
    return [UIColor colorWithHexValue:hex];
}

/// 生成可平铺拉伸的纸纹图(含微渐变 + 纤维噪点)
static UIImage *RDMakePaperTexture(RDPaperPalette p, CGSize size, BOOL circular)
{
    CGFloat scale = [UIScreen mainScreen].scale;
    if (scale < 1) {
        scale = 2;
    }
    CGSize px = CGSizeMake(MAX(8, size.width), MAX(8, size.height));
    UIGraphicsBeginImageContextWithOptions(px, !circular, scale);
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    if (!ctx) {
        UIGraphicsEndImageContext();
        return nil;
    }

    CGRect rect = CGRectMake(0, 0, px.width, px.height);
    if (circular) {
        CGContextClearRect(ctx, rect);
        CGContextAddEllipseInRect(ctx, rect);
        CGContextClip(ctx);
    }

    // 垂直微渐变:顶部受光略亮,底部略沉 — 像摊开的书页
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    NSArray *colors = @[
        (id)RDUIColorHex(p.baseHi).CGColor,
        (id)RDUIColorHex(p.base).CGColor,
        (id)RDUIColorHex(p.baseLo).CGColor,
    ];
    CGFloat locs[] = { 0.0, 0.45, 1.0 };
    CGGradientRef grad = CGGradientCreateWithColors(space, (__bridge CFArrayRef)colors, locs);
    CGContextDrawLinearGradient(ctx, grad, CGPointMake(0, 0), CGPointMake(0, px.height), 0);
    CGGradientRelease(grad);
    CGColorSpaceRelease(space);

    // 纤维噪点:稀疏半透明小点,模拟纸浆
    CGFloat r, g, b;
    UIColor *fiber = RDUIColorHex(p.fiber);
    [fiber getRed:&r green:&g blue:&b alpha:NULL];
    NSUInteger dots = (NSUInteger)(px.width * px.height * 0.045);
    // 固定种子:同一主题每次生成一致,避免闪烁
    uint32_t seed = p.base ^ (uint32_t)(px.width * 31) ^ (uint32_t)(px.height * 17);
    for (NSUInteger i = 0; i < dots; i++) {
        seed = seed * 1664525u + 1013904223u;
        CGFloat x = (seed % 10000) / 10000.0 * px.width;
        seed = seed * 1664525u + 1013904223u;
        CGFloat y = (seed % 10000) / 10000.0 * px.height;
        seed = seed * 1664525u + 1013904223u;
        CGFloat a = 0.03 + ((seed % 100) / 100.0) * 0.08;
        seed = seed * 1664525u + 1013904223u;
        CGFloat s = 0.4 + ((seed % 100) / 100.0) * 1.2;
        CGContextSetRGBFillColor(ctx, r, g, b, a);
        CGContextFillRect(ctx, CGRectMake(x, y, s, s * (0.5 + (seed % 50) / 100.0)));
    }

    // 极淡水平纤维丝(宣纸/书页的长纤维感)
    CGContextSetRGBStrokeColor(ctx, r, g, b, 0.035);
    CGContextSetLineWidth(ctx, 0.6);
    for (NSInteger i = 0; i < 6; i++) {
        seed = seed * 1664525u + 1013904223u;
        CGFloat y = (seed % 10000) / 10000.0 * px.height;
        seed = seed * 1664525u + 1013904223u;
        CGFloat x0 = (seed % 10000) / 10000.0 * px.width * 0.3;
        seed = seed * 1664525u + 1013904223u;
        CGFloat x1 = x0 + 8 + ((seed % 100) / 100.0) * (px.width * 0.5);
        CGContextMoveToPoint(ctx, x0, y);
        CGContextAddLineToPoint(ctx, MIN(x1, px.width), y + ((seed % 3) - 1) * 0.4);
        CGContextStrokePath(ctx);
    }

    // 夜读额外:极弱 vignette,像台灯照在纸上
    if (p.base < 0x404040) {
        CGContextSetRGBFillColor(ctx, 0, 0, 0, 0.12);
        CGContextFillRect(ctx, CGRectMake(0, 0, px.width, px.height * 0.08));
        CGContextFillRect(ctx, CGRectMake(0, px.height * 0.92, px.width, px.height * 0.08));
    }

    UIImage *img = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return img;
}

static UIImage *RDMakeSelectionRing(UIColor *stroke, CGFloat diameter)
{
    CGFloat scale = [UIScreen mainScreen].scale;
    CGSize size = CGSizeMake(diameter, diameter);
    UIGraphicsBeginImageContextWithOptions(size, NO, scale);
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    CGFloat inset = 1.5;
    CGRect ring = CGRectInset(CGRectMake(0, 0, diameter, diameter), inset, inset);
    CGContextSetStrokeColorWithColor(ctx, stroke.CGColor);
    CGContextSetLineWidth(ctx, 2.0);
    CGContextStrokeEllipseInRect(ctx, ring);
    UIImage *img = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return img;
}

@implementation RDReadConfigManager {
    NSCache *_paperCache;
}

+ (RDReadConfigManager *)sharedInstance {
    static RDReadConfigManager *sharedInstance = nil;
    static dispatch_once_t onceToken;

    dispatch_once(&onceToken, ^{
        sharedInstance = [[RDModelAgent agent] readModelForClass:[self class]];
        if (!sharedInstance) {
            sharedInstance = [[self alloc] init];
            sharedInstance.fontSize = 16;
            sharedInstance.lineSpace = sharedInstance.fontSize-6;
            sharedInstance.brightness = kConfigMaxBrightnessValue;
            // 默认旧书页:最接近实体书纸
            sharedInstance.theme = RDYellowTheme;
            sharedInstance.pageType = [RDDisplayBoost preferredPageTypeForDisplay];
        } else if ([RDDisplayBoost isHighRefreshDisplay]
                   && sharedInstance.pageType == RDRealTypePage
                   && ![[NSUserDefaults standardUserDefaults] boolForKey:kPromotedSliderPageOnProMotionKey]) {
            sharedInstance.pageType = RDSliderPage;
            [[NSUserDefaults standardUserDefaults] setBool:YES forKey:kPromotedSliderPageOnProMotionKey];
            [sharedInstance archive];
        }
        // 归档后重新应用主题,确保纸纹与新色板生效
        RDThemeType t = sharedInstance.theme;
        sharedInstance.theme = t;
    });

    return sharedInstance;
}

- (instancetype)init
{
    self = [super init];
    if (self) {
        _paperCache = [[NSCache alloc] init];
        _paperCache.countLimit = 12;
    }
    return self;
}

- (NSCache *)p_paperCache
{
    if (!_paperCache) {
        _paperCache = [[NSCache alloc] init];
        _paperCache.countLimit = 12;
    }
    return _paperCache;
}

-(CGFloat)chapterFontSize
{
    return self.fontSize+10;
}

-(CGFloat)chapterLineSpace
{
    return self.lineSpace+30;
}

+ (NSString *)displayNameForTheme:(RDThemeType)theme
{
    switch (theme) {
        case RDWhiteTheme:  return @"素笺";
        case RDYellowTheme: return @"旧书页";
        case RDBlueTheme:   return @"青灰笺";
        case RDGreenTheme:  return @"竹纸";
        case RDBlackTheme:  return @"夜读";
    }
    return @"纸";
}

+ (UIImage *)swatchImageForTheme:(RDThemeType)theme diameter:(CGFloat)diameter
{
    RDPaperPalette p = RDPaperPaletteForTheme(theme);
    UIImage *img = RDMakePaperTexture(p, CGSizeMake(diameter, diameter), YES);
    return img;
}

+ (UIImage *)selectionRingForTheme:(RDThemeType)theme diameter:(CGFloat)diameter
{
    RDPaperPalette p = RDPaperPaletteForTheme(theme);
    // 选中环用墨色,夜读用浅墨
    UIColor *stroke = (theme == RDBlackTheme)
        ? RDUIColorHex(0xC8BEB0)
        : RDUIColorHex(p.ink);
    return RDMakeSelectionRing(stroke, diameter);
}

- (UIImage *)p_backgroundImageForTheme:(RDThemeType)theme
{
    // 小块纹理可拉伸平铺,省内存
    NSString *key = [NSString stringWithFormat:@"bg.%ld.%.0f", (long)theme, [UIScreen mainScreen].scale];
    UIImage *cached = [self.p_paperCache objectForKey:key];
    if (cached) {
        return cached;
    }
    RDPaperPalette p = RDPaperPaletteForTheme(theme);
    // 足够大的 tile 让噪点不显重复,再 stretch
    UIImage *tile = RDMakePaperTexture(p, CGSizeMake(96, 128), NO);
    UIImage *stretch = [tile stretchableImage];
    if (stretch) {
        [self.p_paperCache setObject:stretch forKey:key];
    }
    return stretch;
}

-(void)setTheme:(RDThemeType)theme
{
    RDPaperPalette p = RDPaperPaletteForTheme(theme);
    self.fontColor = RDUIColorHex(p.ink);
    self.samllCharpterColor = RDUIColorHex(p.inkLight);
    self.toolColor = RDUIColorHex(p.tool);
    self.pageTintColor = RDUIColorHex(p.base);
    self.background = [self p_backgroundImageForTheme:theme];
    // 兜底:生成失败时用纯色
    if (!self.background) {
        self.background = [UIImage imageWithColor:RDUIColorHex(p.base)];
    }
    _theme = theme;
    [[NSNotificationCenter defaultCenter] postNotificationName:RDReadThemeDidChangeNotification object:self];
}

- (BOOL)isDarkTheme
{
    return self.theme == RDBlackTheme;
}

- (UIColor *)chromeBackgroundColor
{
    // 比纸面略深一点的面板色,夜读用更深炭黑
    if (self.isDarkTheme) {
        return [UIColor colorWithHexValue:0x24211E];
    }
    return self.pageTintColor ?: RDReadBg;
}

- (UIColor *)chromeForegroundColor
{
    return self.fontColor ?: RDBlackColor;
}

- (UIColor *)chromeSecondaryColor
{
    return self.toolColor ?: RDGrayColor;
}

- (UIColor *)chromeSeparatorColor
{
    if (self.isDarkTheme) {
        return [UIColor colorWithHexValue:0x3A3530];
    }
    return RDSeparatorColor;
}

@end
