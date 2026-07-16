//
//  RDSpeechManager.m
//  Reader
//

#import "RDSpeechManager.h"
#import <AVFoundation/AVFoundation.h>
#import "RDBookDetailModel.h"
#import "RDCharpterModel.h"
#import "RDCharpterDataManager.h"

@interface RDSpeechManager ()<AVSpeechSynthesizerDelegate>
@property (nonatomic,strong) AVSpeechSynthesizer *synthesizer;
@property (nonatomic,strong) RDBookDetailModel *book;
@property (nonatomic,strong) NSArray <RDCharpterModel *>*chapters;
@property (nonatomic,assign) NSInteger chapterIndex;
@property (nonatomic,assign) BOOL active;
@property (nonatomic,assign) BOOL paused;
@property (nonatomic,assign) CGFloat rateMultiplier;
@property (nonatomic,assign) BOOL stopping;   //手动停止时不触发续播
@end

@implementation RDSpeechManager

IMP_SINGLETON(RDSpeechManager)

- (instancetype)init
{
    self = [super init];
    if (self) {
        _rateMultiplier = 1.0;
    }
    return self;
}

- (AVSpeechSynthesizer *)synthesizer
{
    if (!_synthesizer) {
        _synthesizer = [[AVSpeechSynthesizer alloc] init];
        _synthesizer.delegate = self;
    }
    return _synthesizer;
}

#pragma mark - 控制

- (void)startWithBook:(RDBookDetailModel *)book chapters:(NSArray<RDCharpterModel *> *)chapters chapterIndex:(NSInteger)chapterIndex text:(NSString *)text
{
    [self stopSynthesizerOnly];
    self.book = book;
    self.chapters = chapters;
    self.chapterIndex = chapterIndex;
    self.active = YES;
    self.paused = NO;

    [[AVAudioSession sharedInstance] setCategory:AVAudioSessionCategoryPlayback error:nil];
    [[AVAudioSession sharedInstance] setActive:YES error:nil];

    [self speakText:text];
    [self.delegate speechManagerStateChanged];
}

- (void)speakText:(NSString *)text
{
    if (text.length == 0) {
        [self advanceToNextChapter];
        return;
    }
    AVSpeechUtterance *utterance = [AVSpeechUtterance speechUtteranceWithString:text];
    utterance.voice = [AVSpeechSynthesisVoice voiceWithLanguage:@"zh-CN"];
    utterance.rate = [self currentRate];
    [self.synthesizer speakUtterance:utterance];
}

- (float)currentRate
{
    float rate = AVSpeechUtteranceDefaultSpeechRate * self.rateMultiplier;
    return MAX(AVSpeechUtteranceMinimumSpeechRate, MIN(AVSpeechUtteranceMaximumSpeechRate, rate));
}

- (void)pause
{
    if (!self.active || self.paused) {
        return;
    }
    [self.synthesizer pauseSpeakingAtBoundary:AVSpeechBoundaryWord];
    self.paused = YES;
    [self.delegate speechManagerStateChanged];
}

- (void)resume
{
    if (!self.active || !self.paused) {
        return;
    }
    [self.synthesizer continueSpeaking];
    self.paused = NO;
    [self.delegate speechManagerStateChanged];
}

- (void)stop
{
    if (!self.active) {
        return;
    }
    [self stopSynthesizerOnly];
    self.active = NO;
    self.paused = NO;
    [[AVAudioSession sharedInstance] setActive:NO withOptions:AVAudioSessionSetActiveOptionNotifyOthersOnDeactivation error:nil];
    [self.delegate speechManagerDidStop];
}

- (void)stopSynthesizerOnly
{
    self.stopping = YES;
    if (_synthesizer.isSpeaking || _synthesizer.isPaused) {
        [_synthesizer stopSpeakingAtBoundary:AVSpeechBoundaryImmediate];
    }
    self.stopping = NO;
}

- (CGFloat)cycleRate
{
    NSArray *rates = @[@0.75, @1.0, @1.25, @1.5];
    NSInteger index = 0;
    for (NSInteger i = 0; i < rates.count; i++) {
        if (fabs([rates[i] doubleValue] - self.rateMultiplier) < 0.01) {
            index = (i + 1) % rates.count;
            break;
        }
    }
    self.rateMultiplier = [rates[index] doubleValue];

    //新语速对正在朗读的语句不生效,重启当前章剩余部分代价大;从下一章起生效,
    //若处于暂停状态则保持暂停,仅更新倍速显示
    [self.delegate speechManagerStateChanged];
    return self.rateMultiplier;
}

#pragma mark - 续播

- (void)advanceToNextChapter
{
    NSInteger next = self.chapterIndex + 1;
    if (next >= self.chapters.count) {
        [self stop];
        return;
    }
    RDCharpterModel *brief = self.chapters[next];
    RDCharpterModel *chapter = [RDCharpterDataManager getCharpterWithBookId:self.book.bookId charpterId:brief.charpterId];
    if (chapter.content.length == 0) {
        //内容缺失(在线书未缓存),结束朗读
        [self stop];
        return;
    }
    self.chapterIndex = next;
    [self.delegate speechManagerWillSpeakChapter:chapter];
    NSString *text = [NSString stringWithFormat:@"%@\n%@", chapter.name ?: @"", chapter.content];
    [self speakText:text];
}

#pragma mark - AVSpeechSynthesizerDelegate

- (void)speechSynthesizer:(AVSpeechSynthesizer *)synthesizer didFinishSpeechUtterance:(AVSpeechUtterance *)utterance
{
    if (!self.active || self.stopping) {
        return;
    }
    [self advanceToNextChapter];
}

@end
