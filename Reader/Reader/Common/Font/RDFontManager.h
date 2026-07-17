//
//  RDFontManager.h
//  Reader
//
//  阅读字体管理:内置中文字体 + 用户导入的 ttf/otf 字体
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

//字体列表变化(导入成功)后发出
extern NSString * const RDFontListChangedNotification;

@interface RDFontOption : NSObject
@property (nonatomic,copy) NSString *displayName;           //如「宋体」
@property (nonatomic,copy,nullable) NSString *fontName;     //PostScript 名;nil 表示系统字体
@property (nonatomic,assign) BOOL custom;                   //是否用户导入
@end

@interface RDFontManager : NSObject

+ (instancetype)sharedInstance;

/// 自定义字体存放目录 Documents/Fonts(不存在会创建;备份/恢复用)
+ (NSString *)fontsDirectory;

/// 系统 + 内置中文字体 + 已导入字体(始终以「系统」开头)
- (NSArray <RDFontOption *>*)allOptions;

/// App 启动时注册 Documents/Fonts 下的全部字体(进程级)
- (void)registerCustomFontsAtLaunch;

/// 导入 ttf/otf 字体文件,主线程回调
- (void)importFontAtURL:(NSURL *)url complete:(void(^)(RDFontOption * _Nullable option, NSString * _Nullable errorMessage))complete;

/// 删除导入的字体
- (void)removeCustomFont:(RDFontOption *)option;

/// 按阅读配置的 fontName 取字体,名字无效时回退系统字体
+ (UIFont *)readFontWithName:(nullable NSString *)fontName size:(CGFloat)size;

@end

NS_ASSUME_NONNULL_END
