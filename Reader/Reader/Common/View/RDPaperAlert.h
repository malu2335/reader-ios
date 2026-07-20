//
//  RDPaperAlert.h
//  Reader
//
//  统一纸感弹窗:中心确认卡 / 底部操作表 / 带输入框表单
//  设计令牌与设置页、空书架、AI 引导一致(RDSurfaceColor / RDAccentColor / 衬线标题)
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, RDPaperAlertActionStyle) {
    RDPaperAlertActionStyleDefault = 0,   // 墨色正文
    RDPaperAlertActionStyleCancel,        // 弱化 / 取消
    RDPaperAlertActionStyleDestructive,   // 警示红
    RDPaperAlertActionStylePrimary,       // 中心卡主按钮(赭褐填充)
};

@interface RDPaperAlertAction : NSObject
@property (nonatomic, copy) NSString *title;
/// 操作表可选副标题,弱化说明,避免与可点标题混为一谈
@property (nonatomic, copy, nullable) NSString *subtitle;
@property (nonatomic, assign) RDPaperAlertActionStyle style;
@property (nonatomic, copy, nullable) void (^handler)(void);
+ (instancetype)actionWithTitle:(NSString *)title
                          style:(RDPaperAlertActionStyle)style
                        handler:(nullable void (^)(void))handler;
+ (instancetype)actionWithTitle:(NSString *)title
                       subtitle:(nullable NSString *)subtitle
                          style:(RDPaperAlertActionStyle)style
                        handler:(nullable void (^)(void))handler;
@end

@interface RDPaperAlert : NSObject

/// 中心确认/提示卡(可选 SF Symbol)
+ (void)showAlertWithTitle:(nullable NSString *)title
                   message:(nullable NSString *)message
                symbolName:(nullable NSString *)symbolName
                   actions:(NSArray <RDPaperAlertAction *>*)actions;

/// 常用双按钮确认:取消 + 确认(destructive 时主按钮为警示红)
+ (void)showConfirmWithTitle:(NSString *)title
                     message:(NSString *)message
                 cancelTitle:(NSString *)cancelTitle
                confirmTitle:(NSString *)confirmTitle
                 destructive:(BOOL)destructive
                     confirm:(nullable void (^)(void))confirm;

/// 底部操作表;若 actions 中无 Cancel,自动追加「取消」
+ (void)showActionSheetWithTitle:(nullable NSString *)title
                         message:(nullable NSString *)message
                         actions:(NSArray <RDPaperAlertAction *>*)actions;

/// 纸感输入表单:fieldSpecs 每项 @{ @"placeholder":, @"text":, @"secure": @(NO) }
+ (void)showTextFieldsWithTitle:(NSString *)title
                        message:(nullable NSString *)message
                     fieldSpecs:(NSArray <NSDictionary *>*)fieldSpecs
                    cancelTitle:(NSString *)cancelTitle
                   confirmTitle:(NSString *)confirmTitle
                        confirm:(nullable void (^)(NSArray <NSString *>*values))confirm;

/// 关闭当前纸感弹层
+ (void)dismiss;
+ (void)dismissAnimated:(BOOL)animated completion:(nullable void (^)(void))completion;

@end

NS_ASSUME_NONNULL_END
