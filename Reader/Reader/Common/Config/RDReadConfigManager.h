//
//  RDReadConfigManager.h
//  Reader
//
//  Created by yuenov on 2019/11/13.
//  Copyright © 2019 yuenov. All rights reserved.
//

#import "RDModel.h"

NS_ASSUME_NONNULL_BEGIN

#define kConfigMaxBrightnessValue 0.5
#define kConfigMinFontSize 14.f
#define kConfigMaxFontSize 30.f

@interface RDReadConfigManager : RDModel
@property (nonatomic,assign) CGFloat lineSpace; //行间距
@property (nonatomic,assign) CGFloat fontSize;  //字体大小
@property (nonatomic,strong) NSString *fontName;    //字体名称
@property (nonatomic,strong) UIColor *fontColor;    //字体颜色
@property (nonatomic,strong) UIImage *background;   //主题背景(纸纹)
@property (nonatomic,assign) CGFloat chapterFontSize;   //标题字体大小
@property (nonatomic,assign) CGFloat chapterLineSpace;  //标题行间距
@property (nonatomic,assign) CGFloat firstLineHeadIndent;  //首行缩紧
@property (nonatomic,assign) CGFloat brightness;        //屏幕亮度
@property (nonatomic,assign) RDPageType pageType;       //翻页效果
@property (nonatomic,strong) UIColor *samllCharpterColor;   //左上角小标题颜色
@property (nonatomic,strong) UIColor *toolColor;        //下面电量进度颜色
/// 页边/工具条纸色(与背景同源,供菜单栏等使用)
@property (nonatomic,strong) UIColor *pageTintColor;
//设置主题
@property (nonatomic,assign) RDThemeType theme;
+ (instancetype)sharedInstance;

/// 是否夜读等深色主题(菜单/工具条需同步反色)
- (BOOL)isDarkTheme;
/// 阅读菜单/顶底栏背景色
- (UIColor *)chromeBackgroundColor;
/// 菜单主文字/图标色
- (UIColor *)chromeForegroundColor;
/// 菜单次级文字/分隔线
- (UIColor *)chromeSecondaryColor;
/// 菜单分隔线
- (UIColor *)chromeSeparatorColor;

/// 主题展示名(素笺/旧书页/青灰笺/竹纸/夜读)
+ (NSString *)displayNameForTheme:(RDThemeType)theme;
/// 主题圆形色板(设置栏缩略图)
+ (UIImage *)swatchImageForTheme:(RDThemeType)theme diameter:(CGFloat)diameter;
/// 选中环
+ (UIImage *)selectionRingForTheme:(RDThemeType)theme diameter:(CGFloat)diameter;

/// 阅读主题变更通知(菜单栏跟随后台色)
FOUNDATION_EXPORT NSString * const RDReadThemeDidChangeNotification;

@end

NS_ASSUME_NONNULL_END
