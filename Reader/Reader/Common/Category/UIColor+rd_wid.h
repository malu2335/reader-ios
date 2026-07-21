//
// Created by yuenov on 2019/10/24.
// Copyright (c) 2019 yuenov. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

@interface UIColor (rd_wid)
+ (UIColor *)colorWithHexString:(NSString *)stringToConvert andAlpha:(CGFloat)alpha;

+ (UIColor *)colorWithHexValue:(NSInteger)color alpha:(CGFloat)alpha;

+ (UIColor *)colorWithHexValue:(NSInteger)color;

+ (CGFloat)redColorFromHexRGBColor:(NSInteger)hex;

+ (CGFloat)greenColorFromRGBColor:(NSInteger)hex;

+ (CGFloat)blueColorFromRGBColor:(NSInteger)hex;

- (void)getColorComponentsWithRed:(CGFloat *)red
                            green:(CGFloat *)green
                             blue:(CGFloat *)blue
                            alpha:(CGFloat *)alpha;

+ (UIColor*)gradientFromColor:(UIColor*)c1
                      toColor:(UIColor*)c2
                   withHeight:(int)height;

/// 浅/深双色动态令牌(随 window.userInterfaceStyle 切换)
+ (UIColor *)rd_dynamicLight:(NSInteger)lightHex dark:(NSInteger)darkHex;
+ (UIColor *)rd_dynamicLight:(NSInteger)lightHex lightAlpha:(CGFloat)la dark:(NSInteger)darkHex darkAlpha:(CGFloat)da;
+ (UIColor *)rd_paperBackgroundColor;
+ (UIColor *)rd_paperSurfaceColor;
+ (UIColor *)rd_paperReadBackgroundColor;
+ (UIColor *)rd_inkColor;
+ (UIColor *)rd_inkSecondaryColor;
+ (UIColor *)rd_inkTertiaryColor;
+ (UIColor *)rd_inkPlaceholderColor;
+ (UIColor *)rd_accentColor;
+ (UIColor *)rd_accentSoftColor;
+ (UIColor *)rd_separatorColor;
+ (UIColor *)rd_lightSeparatorColor;

@end

// ============ 设计令牌:安静纸质阅读感(支持全局深色) ============
// 浅色:暖纸;深色:与阅读「夜读」一致的暖炭底 + 米黄字
#define RDBackgroudColor    [UIColor rd_paperBackgroundColor]
#define RDSurfaceColor      [UIColor rd_paperSurfaceColor]
#define RDReadBg            [UIColor rd_paperReadBackgroundColor]

#define RDBlackColor        [UIColor rd_inkColor]
#define RDGrayColor         [UIColor rd_inkSecondaryColor]
#define RDLightGrayColor    [UIColor rd_inkTertiaryColor]
#define RDPlaceholderColor  [UIColor rd_inkPlaceholderColor]

#define RDAccentColor       [UIColor rd_accentColor]
#define RDAccentSoftColor   [UIColor rd_accentSoftColor]
#define RDGreenColor        RDAccentColor

#define RDSeparatorColor    [UIColor rd_separatorColor]
#define RDLightSeparatorColor [UIColor rd_lightSeparatorColor]
