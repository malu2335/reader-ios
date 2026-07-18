//
//  RDLegalDocumentController.h
//  Reader
//
//  本地只读法律/声明文档页（隐私声明、开源软件使用声明等）
//

#import "RDBaseViewController.h"

NS_ASSUME_NONNULL_BEGIN

@interface RDLegalDocumentController : RDBaseViewController

/// @param title 导航标题
/// @param resourceName bundle 内 UTF-8 文本资源名（不含扩展名），例如 PrivacyPolicy.zh-Hans
- (instancetype)initWithTitle:(NSString *)title resourceName:(NSString *)resourceName;

@end

NS_ASSUME_NONNULL_END
