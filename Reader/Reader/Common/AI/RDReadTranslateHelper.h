//
//  RDReadTranslateHelper.h
//  Reader
//
//  阅读页 AI 翻译:结果以内联方式插入语句下方(非弹窗)
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/// 一句原文 + 对应译文
@interface RDTranslatePair : NSObject
@property (nonatomic, copy) NSString *source;
@property (nonatomic, copy) NSString *translated;
@end

@interface RDReadTranslateHelper : NSObject

/// 发起翻译;成功后 completion 回主线程 pairs(可能为空时用 fullTranslation 兜底)
+ (void)translateFromHost:(UIViewController *)host
                 pageText:(nullable NSString *)pageText
              chapterText:(nullable NSString *)chapterText
               rawContent:(nullable NSString *)rawContent
               completion:(nullable void(^)(NSArray <RDTranslatePair *>* _Nullable pairs,
                                            NSString * _Nullable fullTranslation,
                                            NSError * _Nullable error))completion;

/// 兼容旧调用(无 completion 时仍走内联由 PageVC 处理;此方法仅发起)
+ (void)translateFromHost:(UIViewController *)host
                 pageText:(nullable NSString *)pageText
              chapterText:(nullable NSString *)chapterText
               rawContent:(nullable NSString *)rawContent;

+ (void)cancel;

/// 将模型输出解析为句对;失败返回 nil
+ (nullable NSArray <RDTranslatePair *>*)parsePairsFromModelOutput:(NSString *)output;

/// 生成阅读内联展示的富文本(原文 + 下方译文)
+ (NSAttributedString *)attributedStringForPairs:(NSArray <RDTranslatePair *>*)pairs
                                   fallbackSource:(nullable NSString *)source
                               fallbackTranslation:(nullable NSString *)translation;

@end

NS_ASSUME_NONNULL_END
