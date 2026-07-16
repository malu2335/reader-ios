//
//  RDReadTranslateHelper.h
//  Reader
//
//  阅读页 AI 翻译编排(从 RDReadPageViewController 抽出,便于复用与测试)
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface RDReadTranslateHelper : NSObject

/// 从当前页/章文本发起翻译;host 用于 loading/toast/导航到设置
+ (void)translateFromHost:(UIViewController *)host
              pageText:(nullable NSString *)pageText
           chapterText:(nullable NSString *)chapterText
              rawContent:(nullable NSString *)rawContent;

/// 取消进行中的翻译
+ (void)cancel;

@end

NS_ASSUME_NONNULL_END
