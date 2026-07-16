//
//  RDSpeechManager.h
//  Reader
//
//  听书:AVSpeechSynthesizer 朗读当前章节,读完自动续播下一章
//

#import <Foundation/Foundation.h>
@class RDBookDetailModel, RDCharpterModel;

NS_ASSUME_NONNULL_BEGIN

@protocol RDSpeechManagerDelegate <NSObject>
/// 即将朗读新的章节(续播时通知阅读页跳转)
- (void)speechManagerWillSpeakChapter:(RDCharpterModel *)chapter;
/// 全书读完或朗读中止
- (void)speechManagerDidStop;
/// 播放/暂停/语速状态变化(刷新控制条)
- (void)speechManagerStateChanged;
@end

@interface RDSpeechManager : NSObject

+ (RDSpeechManager *)sharedInstance;

@property (nonatomic,weak,nullable) id<RDSpeechManagerDelegate> delegate;
@property (nonatomic,assign,readonly) BOOL active;     //听书会话进行中(含暂停)
@property (nonatomic,assign,readonly) BOOL paused;
@property (nonatomic,assign,readonly) CGFloat rateMultiplier;  //0.75 / 1.0 / 1.25 / 1.5

/// 从指定章节的 text(当前页起的剩余文本)开始朗读
- (void)startWithBook:(RDBookDetailModel *)book
             chapters:(NSArray <RDCharpterModel *>*)chapters
         chapterIndex:(NSInteger)chapterIndex
                 text:(NSString *)text;

- (void)pause;
- (void)resume;
- (void)stop;
/// 循环切换语速,返回新的倍速
- (CGFloat)cycleRate;

@end

NS_ASSUME_NONNULL_END
