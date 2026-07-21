//
// Created by yuenov on 2019/10/24.
// Copyright (c) 2019 yuenov. All rights reserved.
//

#import "UIColor+rd_wid.h"


@implementation UIColor (rd_wid)
+ (UIColor *)colorWithHexString:(NSString *)stringToConvert andAlpha:(CGFloat)alpha
{
    //去掉前后空格换行符
    NSString *cString = [[stringToConvert stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] uppercaseString];

    if ([cString hasPrefix:@"0X"])
        cString = [cString substringFromIndex:2];
    else if ([cString hasPrefix:@"#"])
        cString = [cString substringFromIndex:1];

    if ([cString length] != 6)
        return nil;

    // Separate into r, g, b substrings
    NSRange range;
    range.location = 0;
    range.length = 2;
    NSString *rString = [cString substringWithRange:range];

    range.location = 2;
    NSString *gString = [cString substringWithRange:range];

    range.location = 4;
    NSString *bString = [cString substringWithRange:range];

    unsigned int r, g, b;
    [[NSScanner scannerWithString:rString] scanHexInt:&r];
    [[NSScanner scannerWithString:gString] scanHexInt:&g];
    [[NSScanner scannerWithString:bString] scanHexInt:&b];

    return [UIColor colorWithRed:r / 255.0 green:g / 255.0 blue:b / 255.0 alpha:alpha];
}

+ (UIColor *)colorWithHexValue:(NSInteger)color alpha:(CGFloat)alpha
{
    return [UIColor colorWithRed:((float) ((color & 0xff0000) >> 16)) / 255.0
                           green:((float) ((color & 0x00ff00) >> 8)) / 255.0
                            blue:((float) (color & 0x0000ff)) / 255.0
                           alpha:alpha];
}

+ (UIColor *)colorWithHexValue:(NSInteger)color
{
    return [UIColor colorWithRed:((float) ((color & 0xff0000) >> 16)) / 255.0
                           green:((float) ((color & 0x00ff00) >> 8)) / 255.0
                            blue:((float) (color & 0x0000ff)) / 255.0
                           alpha:1.0];
}

+ (CGFloat)redColorFromHexRGBColor:(NSInteger)color
{
    return (((color & 0xff0000) >> 16) / 255.0);
}

+ (CGFloat)greenColorFromRGBColor:(NSInteger)color
{
    return (((color & 0x00ff00) >> 8) / 255.0);
}

+ (CGFloat)blueColorFromRGBColor:(NSInteger)color
{
    return ((color & 0x0000ff) / 255.0);
}

- (void)getColorComponentsWithRed:(CGFloat *)red green:(CGFloat *)green blue:(CGFloat *)blue alpha:(CGFloat *)alpha
{
    if ([self respondsToSelector:@selector(getRed:green:blue:alpha:)]) {
        [self getRed:red green:green blue:blue alpha:alpha];
    }
    else {
        const CGFloat *components = CGColorGetComponents(self.CGColor);
        *red = components[0];
        *green = components[1];
        *blue = components[2];
        *alpha = components[3];
    }
}

+ (UIColor*)gradientFromColor:(UIColor*)c1 toColor:(UIColor*)c2 withHeight:(int)height
{
    CGSize size = CGSizeMake(1, height);
    UIGraphicsBeginImageContextWithOptions(size, NO, 0);
    CGContextRef context = UIGraphicsGetCurrentContext();
    CGColorSpaceRef colorspace = CGColorSpaceCreateDeviceRGB();

    NSArray* colors = [NSArray arrayWithObjects:(id)c1.CGColor, (id)c2.CGColor, nil];
    CGGradientRef gradient = CGGradientCreateWithColors(colorspace, (__bridge CFArrayRef)colors, NULL);
    CGContextDrawLinearGradient(context, gradient, CGPointMake(0, 0), CGPointMake(0, size.height), 0);

    UIImage *image = UIGraphicsGetImageFromCurrentImageContext();

    CGGradientRelease(gradient);
    CGColorSpaceRelease(colorspace);
    UIGraphicsEndImageContext();

    return [UIColor colorWithPatternImage:image];
}

#pragma mark - App tokens (light paper / dark night)

+ (UIColor *)rd_dynamicLight:(NSInteger)lightHex dark:(NSInteger)darkHex
{
    return [self rd_dynamicLight:lightHex lightAlpha:1 dark:darkHex darkAlpha:1];
}

+ (UIColor *)rd_dynamicLight:(NSInteger)lightHex lightAlpha:(CGFloat)la dark:(NSInteger)darkHex darkAlpha:(CGFloat)da
{
    return [UIColor colorWithDynamicProvider:^UIColor * _Nonnull(UITraitCollection * _Nonnull trait) {
        if (trait.userInterfaceStyle == UIUserInterfaceStyleDark) {
            return [UIColor colorWithHexValue:darkHex alpha:da];
        }
        return [UIColor colorWithHexValue:lightHex alpha:la];
    }];
}

// 浅色:暖纸;深色:夜读暖炭(与 RDReadConfigManager 夜读色板对齐)
+ (UIColor *)rd_paperBackgroundColor
{
    return [self rd_dynamicLight:0xF7F3EA dark:0x141210];
}

+ (UIColor *)rd_paperSurfaceColor
{
    return [self rd_dynamicLight:0xFDFBF5 dark:0x1C1A18];
}

+ (UIColor *)rd_paperReadBackgroundColor
{
    return [self rd_dynamicLight:0xF5EFE2 dark:0x1C1A18];
}

+ (UIColor *)rd_inkColor
{
    return [self rd_dynamicLight:0x2C2620 dark:0xE8E0D4];
}

+ (UIColor *)rd_inkSecondaryColor
{
    return [self rd_dynamicLight:0x6E6459 dark:0x9A9084];
}

+ (UIColor *)rd_inkTertiaryColor
{
    return [self rd_dynamicLight:0x9A8F81 dark:0x6A6258];
}

+ (UIColor *)rd_inkPlaceholderColor
{
    return [self rd_dynamicLight:0xB9AE9C dark:0x5A534A];
}

+ (UIColor *)rd_accentColor
{
    // 深色略提亮,保证按钮/选中态可读
    return [self rd_dynamicLight:0x8F5B3B dark:0xC4895E];
}

+ (UIColor *)rd_accentSoftColor
{
    return [self rd_dynamicLight:0x8F5B3B lightAlpha:0.10 dark:0xC4895E darkAlpha:0.18];
}

+ (UIColor *)rd_separatorColor
{
    return [self rd_dynamicLight:0xDCD3C3 dark:0x3A3530];
}

+ (UIColor *)rd_lightSeparatorColor
{
    return [self rd_dynamicLight:0xEDE7D9 dark:0x2E2A26];
}

@end
