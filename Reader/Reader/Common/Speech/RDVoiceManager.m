//
//  RDVoiceManager.m
//  Reader
//

#import "RDVoiceManager.h"
#import "RDHttpTTS.h"
#import "RDHttpTTSClient.h"
#import "RDAIConfig.h"
#import "RDAIClient.h"
#import <objc/runtime.h>
#import <AVFoundation/AVFoundation.h>

NSString * const RDVoiceListChangedNotification = @"RDVoiceListChangedNotification";
NSString * const RDPreferredVoiceChangedNotification = @"RDPreferredVoiceChangedNotification";

static NSString * const kPreferredVoiceKey = @"rd.tts.preferredVoiceId";
static NSString * const kFavoriteVoicesKey = @"rd.tts.favoriteVoiceIds";

@implementation RDVoiceOption
@end

@interface RDVoiceManager ()
@property (nonatomic, strong) AVSpeechSynthesizer *previewSynthesizer;
@property (nonatomic, copy) NSArray <NSString *>*favoriteIdentifiers;
@property (nonatomic, copy, nullable) NSString *cachedDisplayName;
@property (nonatomic, copy, nullable) NSArray <NSDictionary *>*cachedGroups;
@property (nonatomic, strong, nullable) AVSpeechSynthesisVoice *cachedResolvedVoice;
@property (nonatomic, assign) BOOL loadingGroups;
@end

@implementation RDVoiceManager

IMP_SINGLETON(RDVoiceManager)

- (instancetype)init
{
    self = [super init];
    if (self) {
        _favoriteIdentifiers = [[NSUserDefaults standardUserDefaults] stringArrayForKey:kFavoriteVoicesKey] ?: @[];
        _preferredVoiceIdentifier = [[NSUserDefaults standardUserDefaults] stringForKey:kPreferredVoiceKey];
        if (@available(iOS 17.0, *)) {
            [[NSNotificationCenter defaultCenter] addObserver:self
                                                     selector:@selector(p_voicesChanged)
                                                         name:AVSpeechSynthesisAvailableVoicesDidChangeNotification
                                                       object:nil];
        }
    }
    return self;
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)p_invalidateCaches
{
    self.cachedDisplayName = nil;
    self.cachedGroups = nil;
    self.cachedResolvedVoice = nil;
}

- (void)p_voicesChanged
{
    [self p_invalidateCaches];
    [[NSNotificationCenter defaultCenter] postNotificationName:RDVoiceListChangedNotification object:nil];
}

- (void)p_saveFavorites
{
    [[NSUserDefaults standardUserDefaults] setObject:self.favoriteIdentifiers ?: @[] forKey:kFavoriteVoicesKey];
}

#pragma mark - Preferred

- (void)setPreferredVoiceIdentifier:(NSString *)preferredVoiceIdentifier
{
    _preferredVoiceIdentifier = [preferredVoiceIdentifier copy];
    if (preferredVoiceIdentifier.length) {
        [[NSUserDefaults standardUserDefaults] setObject:preferredVoiceIdentifier forKey:kPreferredVoiceKey];
    } else {
        [[NSUserDefaults standardUserDefaults] removeObjectForKey:kPreferredVoiceKey];
    }
    [self p_invalidateCaches];
    [[NSNotificationCenter defaultCenter] postNotificationName:RDPreferredVoiceChangedNotification object:nil];
}

- (void)setPreferredIdentifier:(NSString *)identifier
{
    self.preferredVoiceIdentifier = identifier;
}

- (NSString *)preferredDisplayName
{
    // 设置页 cell 会频繁调用:禁止扫 speechVoices(主线程极慢)
    if (self.cachedDisplayName.length) {
        return self.cachedDisplayName;
    }
    if (self.preferredVoiceIdentifier.length == 0) {
        self.cachedDisplayName = @"自动(中文)";
        return self.cachedDisplayName;
    }
    RDHttpTTS *http = [[RDHttpTTSStore sharedInstance] engineWithVoiceIdentifier:self.preferredVoiceIdentifier];
    if (http) {
        self.cachedDisplayName = [NSString stringWithFormat:@"%@ · 在线", http.name ?: @"HttpTTS"];
        return self.cachedDisplayName;
    }
    if ([self.preferredVoiceIdentifier hasPrefix:RDAITtsVoiceIdentifierPrefix]) {
        NSString *pid = [self.preferredVoiceIdentifier substringFromIndex:RDAITtsVoiceIdentifierPrefix.length];
        RDAIConfigProfile *p = [[RDAIConfigStore sharedInstance] profileWithId:pid];
        if (p) {
            self.cachedDisplayName = [NSString stringWithFormat:@"%@ · AI", p.name.length ? p.name : @"AI TTS"];
            return self.cachedDisplayName;
        }
    }
    AVSpeechSynthesisVoice *v = [AVSpeechSynthesisVoice voiceWithIdentifier:self.preferredVoiceIdentifier];
    if (v) {
        self.cachedDisplayName = [self p_displayNameForVoice:v];
    } else {
        self.cachedDisplayName = @"自动(中文)";
    }
    return self.cachedDisplayName;
}

#pragma mark - Favorites

- (BOOL)isFavorite:(NSString *)identifier
{
    if (identifier.length == 0) {
        return NO;
    }
    return [self.favoriteIdentifiers containsObject:identifier];
}

- (void)toggleFavoriteIdentifier:(NSString *)identifier
{
    if (identifier.length == 0) {
        return;
    }
    NSMutableArray *arr = [self.favoriteIdentifiers mutableCopy] ?: [NSMutableArray array];
    if ([arr containsObject:identifier]) {
        [arr removeObject:identifier];
    } else {
        [arr addObject:identifier];
    }
    self.favoriteIdentifiers = [arr copy];
    [self p_saveFavorites];
    self.cachedGroups = nil;
    [[NSNotificationCenter defaultCenter] postNotificationName:RDVoiceListChangedNotification object:nil];
}

#pragma mark - Resolve

- (AVSpeechSynthesisVoice *)resolvedVoice
{
    if (self.cachedResolvedVoice) {
        return self.cachedResolvedVoice;
    }
    if (self.preferredVoiceIdentifier.length) {
        AVSpeechSynthesisVoice *v = [AVSpeechSynthesisVoice voiceWithIdentifier:self.preferredVoiceIdentifier];
        if (v) {
            self.cachedResolvedVoice = v;
            return v;
        }
    }
    // 自动:先快速取系统默认中文,避免 UI 路径扫全量语音
    AVSpeechSynthesisVoice *fast = [AVSpeechSynthesisVoice voiceWithLanguage:@"zh-CN"];
    if (fast) {
        // 朗读时再尝试升级到增强音(仅首次)
        static dispatch_once_t once;
        dispatch_once(&once, ^{
            dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
                NSArray *all = [AVSpeechSynthesisVoice speechVoices];
                AVSpeechSynthesisVoice *enhanced = nil;
                for (AVSpeechSynthesisVoice *v in all) {
                    if ([v.language hasPrefix:@"zh"] && [self p_isEnhanced:v]) {
                        enhanced = v;
                        break;
                    }
                }
                if (enhanced) {
                    dispatch_async(dispatch_get_main_queue(), ^{
                        if (self.preferredVoiceIdentifier.length == 0) {
                            self.cachedResolvedVoice = enhanced;
                        }
                    });
                }
            });
        });
        self.cachedResolvedVoice = fast;
        return fast;
    }
    self.cachedResolvedVoice = [AVSpeechSynthesisVoice voiceWithLanguage:@"zh-CN"];
    return self.cachedResolvedVoice;
}

#pragma mark - Listing

- (BOOL)p_isEnhanced:(AVSpeechSynthesisVoice *)voice
{
    if (@available(iOS 16.0, *)) {
        // quality: Default=1, Enhanced=2, Premium=3
        return voice.quality >= AVSpeechSynthesisVoiceQualityEnhanced;
    }
    NSString *idStr = voice.identifier.lowercaseString ?: @"";
    return [idStr containsString:@"enhanced"] || [idStr containsString:@"premium"] || [idStr containsString:@"siri"];
}

- (BOOL)p_isPersonal:(AVSpeechSynthesisVoice *)voice
{
    if (@available(iOS 17.0, *)) {
        return (voice.voiceTraits & AVSpeechSynthesisVoiceTraitIsPersonalVoice) != 0;
    }
    return NO;
}

- (NSString *)p_displayNameForVoice:(AVSpeechSynthesisVoice *)v
{
    NSString *name = v.name.length ? v.name : @"未命名";
    // 去掉过长的 Apple 前缀
    if ([name hasPrefix:@"com.apple."]) {
        name = [[name componentsSeparatedByString:@"."] lastObject] ?: name;
    }
    return name;
}

- (NSString *)p_detailForVoice:(AVSpeechSynthesisVoice *)v kind:(RDVoiceKind)kind
{
    NSMutableArray *parts = [NSMutableArray array];
    [parts addObject:v.language ?: @""];
    if (kind == RDVoiceKindPersonal) {
        [parts addObject:@"个人声音"];
    } else if (kind == RDVoiceKindEnhanced) {
        if (@available(iOS 16.0, *)) {
            if (v.quality >= AVSpeechSynthesisVoiceQualityPremium) {
                [parts addObject:@"高级"];
            } else {
                [parts addObject:@"增强"];
            }
        } else {
            [parts addObject:@"增强"];
        }
    } else {
        [parts addObject:@"标准"];
    }
    if ([self isFavorite:v.identifier]) {
        [parts addObject:@"已收藏"];
    }
    return [parts componentsJoinedByString:@" · "];
}

- (RDVoiceOption *)p_optionFromVoice:(AVSpeechSynthesisVoice *)v
{
    RDVoiceOption *opt = [[RDVoiceOption alloc] init];
    opt.identifier = v.identifier;
    opt.displayName = [self p_displayNameForVoice:v];
    opt.language = v.language;
    RDVoiceKind kind = RDVoiceKindSystem;
    if ([self p_isPersonal:v]) {
        kind = RDVoiceKindPersonal;
    } else if ([self p_isEnhanced:v]) {
        kind = RDVoiceKindEnhanced;
    }
    opt.kind = kind;
    opt.detail = [self p_detailForVoice:v kind:kind];
    opt.isPreferred = [v.identifier isEqualToString:self.preferredVoiceIdentifier];
    return opt;
}

- (NSArray <RDVoiceOption *>*)allOptions
{
    NSMutableArray *arr = [NSMutableArray array];
    for (AVSpeechSynthesisVoice *v in [AVSpeechSynthesisVoice speechVoices]) {
        [arr addObject:[self p_optionFromVoice:v]];
    }
    // 中文优先,增强优先,名字排序
    [arr sortUsingComparator:^NSComparisonResult(RDVoiceOption *a, RDVoiceOption *b) {
        BOOL azh = [a.language hasPrefix:@"zh"];
        BOOL bzh = [b.language hasPrefix:@"zh"];
        if (azh != bzh) {
            return azh ? NSOrderedAscending : NSOrderedDescending;
        }
        if (a.kind != b.kind) {
            // personal > enhanced > system
            return a.kind > b.kind ? NSOrderedAscending : NSOrderedDescending;
        }
        return [a.displayName localizedCompare:b.displayName];
    }];
    return arr;
}

- (NSArray <NSDictionary *>*)groupedOptions
{
    if (self.cachedGroups) {
        return self.cachedGroups;
    }
    NSMutableArray *favorites = [NSMutableArray array];
    NSMutableArray *chinese = [NSMutableArray array];
    NSMutableArray *personal = [NSMutableArray array];
    NSMutableArray *others = [NSMutableArray array];

    NSSet *favSet = [NSSet setWithArray:self.favoriteIdentifiers ?: @[]];

    for (RDVoiceOption *opt in [self allOptions]) {
        if ([favSet containsObject:opt.identifier]) {
            AVSpeechSynthesisVoice *voice = [AVSpeechSynthesisVoice voiceWithIdentifier:opt.identifier];
            if (voice) {
                RDVoiceOption *copy = [self p_optionFromVoice:voice];
                copy.kind = RDVoiceKindFavorite;
                [favorites addObject:copy];
            }
        }
        if (opt.kind == RDVoiceKindPersonal) {
            [personal addObject:opt];
        } else if ([opt.language hasPrefix:@"zh"]) {
            [chinese addObject:opt];
        } else {
            [others addObject:opt];
        }
    }

    NSMutableArray *groups = [NSMutableArray array];
    // 自动项
    RDVoiceOption *autoOpt = [[RDVoiceOption alloc] init];
    autoOpt.identifier = @"";
    autoOpt.displayName = @"自动(推荐中文增强音)";
    autoOpt.language = @"zh-CN";
    autoOpt.detail = @"未指定时优先使用已下载的中文增强/高级语音";
    autoOpt.kind = RDVoiceKindSystem;
    autoOpt.isPreferred = (self.preferredVoiceIdentifier.length == 0);
    [groups addObject:@{@"title": @"默认", @"items": @[autoOpt]}];

    if (favorites.count) {
        [groups addObject:@{@"title": @"已导入/收藏", @"items": favorites}];
    }
    // 在线 HttpTTS(legado 兼容)
    NSMutableArray *online = [NSMutableArray array];
    for (RDHttpTTS *engine in [RDHttpTTSStore sharedInstance].engines) {
        RDVoiceOption *opt = [[RDVoiceOption alloc] init];
        opt.identifier = [engine voiceIdentifier];
        opt.displayName = engine.name.length ? engine.name : @"在线引擎";
        opt.language = @"online";
        opt.detail = @"HttpTTS · 阅读兼容 · 文本将发送到引擎服务器";
        opt.kind = RDVoiceKindHttpTTS;
        opt.isPreferred = [opt.identifier isEqualToString:self.preferredVoiceIdentifier];
        [online addObject:opt];
        if ([favSet containsObject:opt.identifier]) {
            RDVoiceOption *fav = [[RDVoiceOption alloc] init];
            fav.identifier = opt.identifier;
            fav.displayName = opt.displayName;
            fav.language = opt.language;
            fav.detail = opt.detail;
            fav.kind = RDVoiceKindFavorite;
            fav.isPreferred = opt.isPreferred;
            [favorites addObject:fav];
        }
    }

    if (personal.count) {
        [groups addObject:@{@"title": @"个人声音", @"items": personal}];
    }
    // AI 模型 TTS(OpenAI /v1/audio/speech 或小米 MiMo chat TTS)
    NSMutableArray *aiTTS = [NSMutableArray array];
    for (RDAIConfigProfile *p in [RDAIConfigStore sharedInstance].profiles) {
        if (!p.isTTSUsable) {
            continue;
        }
        RDVoiceOption *opt = [[RDVoiceOption alloc] init];
        opt.identifier = [p ttsVoiceIdentifier];
        opt.displayName = p.name.length ? p.name : @"AI 朗读";
        opt.language = @"ai";
        BOOL mimo = p.usesMiMoSpeechAPI;
        NSString *tm = p.ttsModel.length ? p.ttsModel : (mimo ? @"mimo-v2.5-tts" : @"tts-1");
        NSString *tv = p.ttsVoice.length ? p.ttsVoice : (mimo ? @"mimo_default" : @"alloy");
        opt.detail = [NSString stringWithFormat:@"%@ · %@ · %@", mimo ? @"MiMo TTS" : @"AI TTS", tm, tv];
        opt.kind = RDVoiceKindAITTS;
        opt.isPreferred = [opt.identifier isEqualToString:self.preferredVoiceIdentifier];
        [aiTTS addObject:opt];
    }

    if (online.count) {
        [groups addObject:@{@"title": @"在线朗读(HttpTTS)", @"items": online}];
    }
    if (aiTTS.count) {
        [groups addObject:@{@"title": @"AI 模型朗读", @"items": aiTTS}];
    }
    if (chinese.count) {
        [groups addObject:@{@"title": @"中文语音", @"items": chinese}];
    }
    if (others.count) {
        [groups addObject:@{@"title": @"其他语言", @"items": others}];
    }
    self.cachedGroups = groups;
    return groups;
}

- (void)loadGroupedOptions:(void (^)(NSArray<NSDictionary *> *))complete
{
    if (self.cachedGroups) {
        if (complete) {
            complete(self.cachedGroups);
        }
        return;
    }
    if (self.loadingGroups) {
        // 简单:稍后再取缓存
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.15 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            if (complete) {
                complete(self.cachedGroups ?: @[]);
            }
        });
        return;
    }
    self.loadingGroups = YES;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        // speechVoices 放后台
        NSArray *groups = [self groupedOptions];
        dispatch_async(dispatch_get_main_queue(), ^{
            self.loadingGroups = NO;
            if (complete) {
                complete(groups ?: @[]);
            }
        });
    });
}

#pragma mark - Personal Voice

- (void)requestPersonalVoiceAccess:(void (^)(BOOL, NSString * _Nullable))complete
{
    if (@available(iOS 17.0, *)) {
        [AVSpeechSynthesizer requestPersonalVoiceAuthorizationWithCompletionHandler:^(AVSpeechSynthesisPersonalVoiceAuthorizationStatus status) {
            dispatch_async(dispatch_get_main_queue(), ^{
                BOOL ok = (status == AVSpeechSynthesisPersonalVoiceAuthorizationStatusAuthorized);
                NSString *msg = nil;
                switch (status) {
                    case AVSpeechSynthesisPersonalVoiceAuthorizationStatusAuthorized:
                        msg = @"已授权,个人声音会出现在列表中(需先在系统「设置-辅助功能-个人声音」中创建)";
                        break;
                    case AVSpeechSynthesisPersonalVoiceAuthorizationStatusDenied:
                        msg = @"已拒绝,可在系统设置中重新开启";
                        break;
                    case AVSpeechSynthesisPersonalVoiceAuthorizationStatusUnsupported:
                        msg = @"当前设备不支持个人声音";
                        break;
                    case AVSpeechSynthesisPersonalVoiceAuthorizationStatusNotDetermined:
                        msg = @"尚未完成授权";
                        break;
                }
                [[NSNotificationCenter defaultCenter] postNotificationName:RDVoiceListChangedNotification object:nil];
                if (complete) {
                    complete(ok, msg);
                }
            });
        }];
    } else {
        if (complete) {
            complete(NO, @"个人声音需要 iOS 17 及以上");
        }
    }
}

- (void)openSystemVoiceDownloadHelp
{
    // 无法直接跳到语音下载页,打开辅助功能根路径并提示用户
    NSURL *url = [NSURL URLWithString:UIApplicationOpenSettingsURLString];
    if ([[UIApplication sharedApplication] canOpenURL:url]) {
        [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:nil];
    }
}

#pragma mark - Preview

- (AVSpeechSynthesizer *)previewSynthesizer
{
    if (!_previewSynthesizer) {
        _previewSynthesizer = [[AVSpeechSynthesizer alloc] init];
    }
    return _previewSynthesizer;
}

- (void)previewIdentifier:(NSString *)identifier
{
    [self stopPreview];
    void (^playAudio)(NSData *) = ^(NSData *audio) {
        if (!audio) {
            return;
        }
        NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:@"rd_tts_preview.mp3"];
        [audio writeToFile:path atomically:YES];
        NSError *err = nil;
        AVAudioPlayer *player = [[AVAudioPlayer alloc] initWithContentsOfURL:[NSURL fileURLWithPath:path] error:&err];
        if (player) {
            objc_setAssociatedObject(self, "rd_preview_player", player, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            [player play];
        }
    };
    RDHttpTTS *engine = [[RDHttpTTSStore sharedInstance] engineWithVoiceIdentifier:identifier];
    if (engine) {
        [[AVAudioSession sharedInstance] setCategory:AVAudioSessionCategoryPlayback error:nil];
        [[AVAudioSession sharedInstance] setActive:YES error:nil];
        [[RDHttpTTSClient sharedClient] fetchAudioForEngine:engine
                                                       text:@"你好,这是在线朗读引擎试听。"
                                                 speakSpeed:10
                                                 completion:^(NSData *audio, NSError *error) {
            playAudio(audio);
        }];
        return;
    }
    if ([identifier hasPrefix:RDAITtsVoiceIdentifierPrefix]) {
        NSString *pid = [identifier substringFromIndex:RDAITtsVoiceIdentifierPrefix.length];
        RDAIConfigProfile *p = [[RDAIConfigStore sharedInstance] profileWithId:pid];
        if (p.isTTSUsable) {
            [[AVAudioSession sharedInstance] setCategory:AVAudioSessionCategoryPlayback error:nil];
            [[AVAudioSession sharedInstance] setActive:YES error:nil];
            [[RDAIClient sharedClient] synthesizeSpeechText:@"你好,这是 AI 朗读试听。"
                                                    profile:p
                                                 completion:^(NSData *audio, NSError *error) {
                playAudio(audio);
            }];
            return;
        }
    }
    AVSpeechSynthesisVoice *voice = nil;
    if (identifier.length) {
        voice = [AVSpeechSynthesisVoice voiceWithIdentifier:identifier];
    } else {
        voice = [self resolvedVoice];
    }
    if (!voice) {
        return;
    }
    [[AVAudioSession sharedInstance] setCategory:AVAudioSessionCategoryPlayback error:nil];
    [[AVAudioSession sharedInstance] setActive:YES error:nil];
    NSString *sample = @"你好,这是朗读语音试听。春江潮水连海平,海上明月共潮生。";
    if (![voice.language hasPrefix:@"zh"]) {
        sample = @"Hello, this is a voice preview for reading aloud.";
    }
    AVSpeechUtterance *u = [AVSpeechUtterance speechUtteranceWithString:sample];
    u.voice = voice;
    u.rate = AVSpeechUtteranceDefaultSpeechRate;
    [self.previewSynthesizer speakUtterance:u];
}

- (void)stopPreview
{
    if (_previewSynthesizer.isSpeaking) {
        [_previewSynthesizer stopSpeakingAtBoundary:AVSpeechBoundaryImmediate];
    }
    AVAudioPlayer *player = objc_getAssociatedObject(self, "rd_preview_player");
    [player stop];
    objc_setAssociatedObject(self, "rd_preview_player", nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [[RDHttpTTSClient sharedClient] cancel];
}

#pragma mark - Import / Export config

- (BOOL)importConfigFromURL:(NSURL *)url error:(NSError *__autoreleasing  _Nullable *)error
{
    BOOL access = [url startAccessingSecurityScopedResource];
    NSData *data = [NSData dataWithContentsOfURL:url options:0 error:error];
    if (access) {
        [url stopAccessingSecurityScopedResource];
    }
    if (!data) {
        return NO;
    }

    // 1) 优先尝试阅读/legado HttpTTS(单条或数组,含 name+url)
    NSError *ttsErr = nil;
    NSInteger ttsCount = [[RDHttpTTSStore sharedInstance] importJSONData:data error:&ttsErr];
    if (ttsCount > 0) {
        self.cachedGroups = nil;
        [[NSNotificationCenter defaultCenter] postNotificationName:RDVoiceListChangedNotification object:nil];
        return YES;
    }

    id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:error];
    if (![json isKindOfClass:[NSDictionary class]]) {
        if (error) {
            *error = ttsErr ?: [NSError errorWithDomain:@"RDVoice" code:1 userInfo:@{NSLocalizedDescriptionKey: @"无效的语音配置(支持本机收藏配置或阅读 HttpTTS JSON)"}];
        }
        return NO;
    }
    NSDictionary *dict = (NSDictionary *)json;
    // 2) 本机收藏/默认语音配置
    if (![dict[@"preferredVoiceIdentifier"] isKindOfClass:NSString.class] && ![dict[@"favoriteIdentifiers"] isKindOfClass:NSArray.class]) {
        if (error) {
            *error = ttsErr ?: [NSError errorWithDomain:@"RDVoice" code:1 userInfo:@{NSLocalizedDescriptionKey: @"无效的语音配置文件"}];
        }
        return NO;
    }
    NSString *pref = dict[@"preferredVoiceIdentifier"];
    if ([pref isKindOfClass:[NSString class]]) {
        self.preferredVoiceIdentifier = pref.length ? pref : nil;
    }
    NSArray *favs = dict[@"favoriteIdentifiers"];
    if ([favs isKindOfClass:[NSArray class]]) {
        NSMutableArray *clean = [NSMutableArray array];
        for (id item in favs) {
            if ([item isKindOfClass:[NSString class]] && [item length]) {
                [clean addObject:item];
            }
        }
        self.favoriteIdentifiers = clean;
        [self p_saveFavorites];
    }
    self.cachedGroups = nil;
    [[NSNotificationCenter defaultCenter] postNotificationName:RDVoiceListChangedNotification object:nil];
    return YES;
}

- (NSURL *)exportConfigToCachesError:(NSError *__autoreleasing  _Nullable *)error
{
    NSDictionary *dict = @{
        @"preferredVoiceIdentifier": self.preferredVoiceIdentifier ?: @"",
        @"favoriteIdentifiers": self.favoriteIdentifiers ?: @[],
        @"version": @1,
        @"exportedAt": @((NSInteger)[[NSDate date] timeIntervalSince1970]),
    };
    NSData *data = [NSJSONSerialization dataWithJSONObject:dict options:NSJSONWritingPrettyPrinted error:error];
    if (!data) {
        return nil;
    }
    NSString *dir = [NSTemporaryDirectory() stringByAppendingPathComponent:@"Exports"];
    [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
    NSString *path = [dir stringByAppendingPathComponent:@"tts_voices.json"];
    if (![data writeToFile:path options:NSDataWritingAtomic error:error]) {
        return nil;
    }
    return [NSURL fileURLWithPath:path];
}

@end
