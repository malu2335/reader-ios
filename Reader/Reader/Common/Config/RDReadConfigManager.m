//
//  RDReadConfigManager.m
//  Reader
//
//  Created by yuenov on 2019/11/13.
//  Copyright © 2019 yuenov. All rights reserved.
//

#import "RDReadConfigManager.h"
#import "RDModelAgent.h"
#import "RDDisplayBoost.h"

static NSString * const kPromotedSliderPageOnProMotionKey = @"RDPromotedSliderPageOnProMotion_v1";

@implementation RDReadConfigManager
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
            // 默认使用纸色主题,契合整体「安静纸质」视觉
            sharedInstance.theme = RDYellowTheme;
            // 高刷默认滑动翻页(可跑 120Hz);仿真卷页系统层常锁 60Hz
            sharedInstance.pageType = [RDDisplayBoost preferredPageTypeForDisplay];
        } else if ([RDDisplayBoost isHighRefreshDisplay]
                   && sharedInstance.pageType == RDRealTypePage
                   && ![[NSUserDefaults standardUserDefaults] boolForKey:kPromotedSliderPageOnProMotionKey]) {
            // 仅升级一次:旧默认仿真 → 滑动,用户可在阅读设置改回仿真
            sharedInstance.pageType = RDSliderPage;
            [[NSUserDefaults standardUserDefaults] setBool:YES forKey:kPromotedSliderPageOnProMotionKey];
            [sharedInstance archive];
        }
    });

    return sharedInstance;
}

-(CGFloat)chapterFontSize
{
    return self.fontSize+10;
}

-(CGFloat)chapterLineSpace
{
    return self.lineSpace+30;
}

-(void)setTheme:(RDThemeType)theme
{
    switch (theme) {
        case RDWhiteTheme:
            self.fontColor = [UIColor blackColor];
            self.samllCharpterColor = [UIColor colorWithHexValue:0xababab];
            self.background = [UIImage stretchableImageNamed:@"theme1_read_bg"];
            self.toolColor = [UIColor colorWithHexValue:0x999999];
            break;
            
        case RDYellowTheme:
            self.fontColor = [UIColor colorWithHexValue:0x2d2d2d];
            self.samllCharpterColor = [UIColor colorWithHexValue:0xa29889];
            self.background = [UIImage stretchableImageNamed:@"theme2_read_bg"];
            self.toolColor = [UIColor colorWithHexValue:0x91887b];
            break;
        case RDBlueTheme:
            self.fontColor = [UIColor colorWithHexValue:0x313f4c];
            self.samllCharpterColor = [UIColor colorWithHexValue:0x8895a0];
            self.background = [UIImage stretchableImageNamed:@"theme3_read_bg"];
            self.toolColor = [UIColor colorWithHexValue:0x7a858f];
            break;
        case RDGreenTheme:
            self.fontColor = [UIColor colorWithHexValue:0x2f442e];
            self.samllCharpterColor = [UIColor colorWithHexValue:0x8f9d8f];
            self.background = [UIImage stretchableImageNamed:@"theme4_read_bg"];
            self.toolColor = [UIColor colorWithHexValue:0x808c80];
            break;
        case RDBlackTheme:
            self.fontColor = [UIColor colorWithHexValue:0x333333];
            self.samllCharpterColor = [UIColor colorWithHexValue:0x151515];
            self.background = [UIImage stretchableImageNamed:@"theme5_read_bg"];
            self.toolColor = [UIColor colorWithHexValue:0x151515];
            break;
    }
    _theme = theme;
}


@end
