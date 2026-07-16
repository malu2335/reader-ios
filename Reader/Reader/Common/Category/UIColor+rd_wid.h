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


// ============ 设计令牌:安静纸质阅读感 ============
// 纸面层次:页面底色 → 卡片表面 → 阅读纸色,统一暖色调
#define RDBackgroudColor    [UIColor colorWithHexValue:0xF7F3EA]   // 页面纸色
#define RDSurfaceColor      [UIColor colorWithHexValue:0xFDFBF5]   // 卡片/浮层表面
#define RDReadBg            [UIColor colorWithHexValue:0xF5EFE2]   // 阅读默认纸色

// 墨色文字层次
#define RDBlackColor        [UIColor colorWithHexValue:0x2C2620]   // 主文字(墨)
#define RDGrayColor         [UIColor colorWithHexValue:0x6E6459]   // 次级文字
#define RDLightGrayColor    [UIColor colorWithHexValue:0x9A8F81]   // 弱化文字
#define RDPlaceholderColor  [UIColor colorWithHexValue:0xB9AE9C]   // 占位文字

// 主题色:低饱和赭褐(旧名 RDGreenColor 保留以兼容既有调用)
#define RDAccentColor       [UIColor colorWithHexValue:0x8F5B3B]
#define RDAccentSoftColor   [UIColor colorWithHexValue:0x8F5B3B alpha:0.10f]
#define RDGreenColor        RDAccentColor

// 分隔线
#define RDSeparatorColor    [UIColor colorWithHexValue:0xDCD3C3]
#define RDLightSeparatorColor [UIColor colorWithHexValue:0xEDE7D9]

@end
