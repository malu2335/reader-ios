//
//  RDSpeechManager.m
//  Reader
//

#import "RDSpeechManager.h"
#import <AVFoundation/AVFoundation.h>
#import "RDBookDetailModel.h"
#import "RDCharpterModel.h"
#import "RDCharpterDataManager.h"
#import "RDVoiceManager.h"
#import "RDReplaceRule.h"
#import "RDHttpTTS.h"
#import "RDHttpTTSClient.h"
#import "RDAIConfig.h"
#import "RDAIClient.h"

@interface RDSpeechManager () <AVSpeechSynthesizerDelegate, AVAudioPlayerDelegate>
@property (nonatomic, strong) AVSpeechSynthesizer *synthesizer;
@property (nonatomic, strong) RDBookDetailModel *book;
@property (nonatomic, strong) NSArray <RDCharpterModel *>*chapters;
@property (nonatomic, assign) NSInteger chapterIndex;
@property (nonatomic, assign) BOOL active;
@property (nonatomic, assign) BOOL paused;
@property (nonatomic, assign) CGFloat rateMultiplier;
@property (nonatomic, assign) BOOL stopping;

// 在线音频段落队列(HttpTTS 或 AI TTS)
@property (nonatomic, copy) NSArray <NSString *>*httpChunks;
@property (nonatomic, assign) NSInteger httpChunkIndex;
@property (nonatomic, strong, nullable) RDHttpTTS *httpEngine;
@property (nonatomic, strong, nullable) RDAIConfigProfile *aiTTSProfile;
@property (nonatomic, strong, nullable) AVAudioPlayer *audioPlayer;
@property (nonatomic, copy, nullable) NSString *httpTempPath;
@property (nonatomic, assign) BOOL audioEngineMode; // HttpTTS 或 AI TTS
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
    [self stopPlaybackOnly];
    self.book = book;
    self.chapters = chapters;
    self.chapterIndex = chapterIndex;
    self.active = YES;
    self.paused = NO;

    [[AVAudioSession sharedInstance] setCategory:AVAudioSessionCategoryPlayback error:nil];
    [[AVAudioSession sharedInstance] setActive:YES error:nil];

    NSString *pref = [RDVoiceManager sharedInstance].preferredVoiceIdentifier;
    self.httpEngine = [[RDHttpTTSStore sharedInstance] engineWithVoiceIdentifier:pref];
    self.aiTTSProfile = nil;
    if (!self.httpEngine && [pref hasPrefix:RDAITtsVoiceIdentifierPrefix]) {
        NSString *pid = [pref substringFromIndex:RDAITtsVoiceIdentifierPrefix.length];
        RDAIConfigProfile *p = [[RDAIConfigStore sharedInstance] profileWithId:pid];
        if (p.isTTSUsable) {
            self.aiTTSProfile = p;
        }
    }
    self.audioEngineMode = (self.httpEngine != nil || self.aiTTSProfile != nil);

    if (self.audioEngineMode) {
        [self p_startHttpSpeakText:text];
    } else {
        [self speakTextSystem:text];
    }
    [self.delegate speechManagerStateChanged];
}

- (void)speakTextSystem:(NSString *)text
{
    if (text.length == 0) {
        [self advanceToNextChapter];
        return;
    }
    AVSpeechUtterance *utterance = [AVSpeechUtterance speechUtteranceWithString:text];
    utterance.voice = [[RDVoiceManager sharedInstance] resolvedVoice];
    utterance.rate = [self currentRate];
    [self.synthesizer speakUtterance:utterance];
}

/// legado 风格:按行拆段,过滤空行
- (NSArray <NSString *>*)p_chunksFromText:(NSString *)text
{
    NSString *src = [text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (src.length == 0) {
        return @[];
    }
    NSArray *lines = [src componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]];
    NSMutableArray *chunks = [NSMutableArray array];
    for (NSString *line in lines) {
        NSString *t = [line stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (t.length == 0) {
            continue;
        }
        // 超长行再按句号切
        if (t.length > 280) {
            NSArray *parts = [t componentsSeparatedByCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"。！？；!?;"]];
            NSMutableString *buf = [NSMutableString string];
            for (NSString *p in parts) {
                NSString *s = [p stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
                if (s.length == 0) continue;
                if (buf.length + s.length > 280 && buf.length > 0) {
                    [chunks addObject:[buf copy]];
                    [buf setString:@""];
                }
                if (buf.length) [buf appendString:@"。"];
                [buf appendString:s];
            }
            if (buf.length) {
                [chunks addObject:[buf copy]];
            }
        } else {
            [chunks addObject:t];
        }
    }
    if (chunks.count == 0 && src.length) {
        [chunks addObject:src];
    }
    return chunks;
}

- (void)p_startHttpSpeakText:(NSString *)text
{
    self.httpChunks = [self p_chunksFromText:text];
    self.httpChunkIndex = 0;
    if (self.httpChunks.count == 0) {
        [self advanceToNextChapter];
        return;
    }
    [self p_fetchAndPlayCurrentHttpChunk];
}

- (NSInteger)p_httpSpeakSpeed
{
    // legado: speechRatePlay + 5, 约 5~15
    NSInteger base = 10;
    if (self.rateMultiplier < 0.9) base = 7;
    else if (self.rateMultiplier < 1.1) base = 10;
    else if (self.rateMultiplier < 1.4) base = 12;
    else base = 15;
    return base;
}

- (void)p_fetchAndPlayCurrentHttpChunk
{
    if (!self.active || self.stopping || (!self.httpEngine && !self.aiTTSProfile)) {
        return;
    }
    if (self.httpChunkIndex >= (NSInteger)self.httpChunks.count) {
        [self advanceToNextChapter];
        return;
    }
    NSString *chunk = self.httpChunks[self.httpChunkIndex];
    __weak typeof(self) weakSelf = self;
    void (^handle)(NSData *, NSError *) = ^(NSData *audio, NSError *error) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self || !self.active || self.stopping) {
            return;
        }
        if (!audio) {
            NSLog(@"[OnlineTTS] chunk fail: %@", error.localizedDescription);
            self.httpChunkIndex++;
            [self p_fetchAndPlayCurrentHttpChunk];
            return;
        }
        [self p_playAudioData:audio];
    };
    if (self.aiTTSProfile) {
        [[RDAIClient sharedClient] synthesizeSpeechText:chunk profile:self.aiTTSProfile completion:handle];
    } else {
        [[RDHttpTTSClient sharedClient] fetchAudioForEngine:self.httpEngine
                                                       text:chunk
                                                 speakSpeed:[self p_httpSpeakSpeed]
                                                 completion:handle];
    }
}

- (void)p_playAudioData:(NSData *)data
{
    [self p_clearHttpPlayer];
    NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:
                      [NSString stringWithFormat:@"rd_http_tts_%u.mp3", arc4random()]];
    if (![data writeToFile:path atomically:YES]) {
        self.httpChunkIndex++;
        [self p_fetchAndPlayCurrentHttpChunk];
        return;
    }
    self.httpTempPath = path;
    NSError *err = nil;
    self.audioPlayer = [[AVAudioPlayer alloc] initWithContentsOfURL:[NSURL fileURLWithPath:path] error:&err];
    if (!self.audioPlayer || err) {
        self.httpChunkIndex++;
        [self p_fetchAndPlayCurrentHttpChunk];
        return;
    }
    self.audioPlayer.delegate = self;
    self.audioPlayer.rate = 1.0;
    self.audioPlayer.enableRate = YES;
    // 轻微用 AVAudioPlayer rate 反映倍速
    self.audioPlayer.rate = MAX(0.5, MIN(2.0, self.rateMultiplier));
    [self.audioPlayer prepareToPlay];
    if (self.paused) {
        return;
    }
    [self.audioPlayer play];
}

- (void)p_clearHttpPlayer
{
    if (self.audioPlayer) {
        self.audioPlayer.delegate = nil;
        [self.audioPlayer stop];
        self.audioPlayer = nil;
    }
    if (self.httpTempPath.length) {
        [[NSFileManager defaultManager] removeItemAtPath:self.httpTempPath error:nil];
        self.httpTempPath = nil;
    }
}

- (void)audioPlayerDidFinishPlaying:(AVAudioPlayer *)player successfully:(BOOL)flag
{
    if (!self.active || self.stopping) {
        return;
    }
    self.httpChunkIndex++;
    [self p_fetchAndPlayCurrentHttpChunk];
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
    if (self.audioEngineMode) {
        [self.audioPlayer pause];
    } else {
        [self.synthesizer pauseSpeakingAtBoundary:AVSpeechBoundaryWord];
    }
    self.paused = YES;
    [self.delegate speechManagerStateChanged];
}

- (void)resume
{
    if (!self.active || !self.paused) {
        return;
    }
    if (self.audioEngineMode) {
        if (self.audioPlayer) {
            [self.audioPlayer play];
        } else {
            [self p_fetchAndPlayCurrentHttpChunk];
        }
    } else {
        [self.synthesizer continueSpeaking];
    }
    self.paused = NO;
    [self.delegate speechManagerStateChanged];
}

- (void)stop
{
    if (!self.active) {
        return;
    }
    [self stopPlaybackOnly];
    self.active = NO;
    self.paused = NO;
    [[AVAudioSession sharedInstance] setActive:NO withOptions:AVAudioSessionSetActiveOptionNotifyOthersOnDeactivation error:nil];
    [self.delegate speechManagerDidStop];
}

- (void)stopPlaybackOnly
{
    self.stopping = YES;
    [[RDHttpTTSClient sharedClient] cancel];
    [[RDAIClient sharedClient] cancelInFlightSpeech];
    [self p_clearHttpPlayer];
    if (_synthesizer.isSpeaking || _synthesizer.isPaused) {
        [_synthesizer stopSpeakingAtBoundary:AVSpeechBoundaryImmediate];
    }
    self.httpChunks = nil;
    self.httpChunkIndex = 0;
    self.httpEngine = nil;
    self.aiTTSProfile = nil;
    self.audioEngineMode = NO;
    self.stopping = NO;
}

- (void)stopSynthesizerOnly
{
    [self stopPlaybackOnly];
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
    if (self.audioEngineMode && self.audioPlayer) {
        self.audioPlayer.enableRate = YES;
        self.audioPlayer.rate = MAX(0.5, MIN(2.0, self.rateMultiplier));
    }
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
        [self stop];
        return;
    }
    self.chapterIndex = next;
    [self.delegate speechManagerWillSpeakChapter:chapter];
    NSString *cleaned = [[RDReplaceRuleStore sharedInstance] applyToText:chapter.content ?: @""];
    NSString *title = [[RDReplaceRuleStore sharedInstance] applyToTitle:chapter.name ?: @""];
    NSString *text = [NSString stringWithFormat:@"%@\n%@", title, cleaned];
    // 续播时重新解析引擎(用户可能中途改了语音)
    NSString *pref = [RDVoiceManager sharedInstance].preferredVoiceIdentifier;
    self.httpEngine = [[RDHttpTTSStore sharedInstance] engineWithVoiceIdentifier:pref];
    self.aiTTSProfile = nil;
    if (!self.httpEngine && [pref hasPrefix:RDAITtsVoiceIdentifierPrefix]) {
        NSString *pid = [pref substringFromIndex:RDAITtsVoiceIdentifierPrefix.length];
        RDAIConfigProfile *p = [[RDAIConfigStore sharedInstance] profileWithId:pid];
        if (p.isTTSUsable) {
            self.aiTTSProfile = p;
        }
    }
    self.audioEngineMode = (self.httpEngine != nil || self.aiTTSProfile != nil);
    if (self.audioEngineMode) {
        [self p_startHttpSpeakText:text];
    } else {
        [self speakTextSystem:text];
    }
}

#pragma mark - AVSpeechSynthesizerDelegate

- (void)speechSynthesizer:(AVSpeechSynthesizer *)synthesizer didFinishSpeechUtterance:(AVSpeechUtterance *)utterance
{
    if (!NSThread.isMainThread) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self speechSynthesizer:synthesizer didFinishSpeechUtterance:utterance];
        });
        return;
    }
    if (!self.active || self.stopping || self.audioEngineMode) {
        return;
    }
    [self advanceToNextChapter];
}

@end
