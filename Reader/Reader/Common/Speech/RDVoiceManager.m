//
//  RDVoiceManager.m
//  Reader
//

#import "RDVoiceManager.h"

NSString * const RDVoiceListChangedNotification = @"RDVoiceListChangedNotification";
NSString * const RDPreferredVoiceChangedNotification = @"RDPreferredVoiceChangedNotification";

static NSString * const kPreferredVoiceKey = @"rd.tts.preferredVoiceId";
static NSString * const kFavoriteVoicesKey = @"rd.tts.favoriteVoiceIds";

@implementation RDVoiceOption
@end

@interface RDVoiceManager ()
@property (nonatomic, strong) AVSpeechSynthesizer *previewSynthesizer;
@property (nonatomic, copy) NSArray <NSString *>*favoriteIdentifiers;
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

- (void)p_voicesChanged
{
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
    [[NSNotificationCenter defaultCenter] postNotificationName:RDPreferredVoiceChangedNotification object:nil];
}

- (void)setPreferredIdentifier:(NSString *)identifier
{
    self.preferredVoiceIdentifier = identifier;
}

- (NSString *)preferredDisplayName
{
    AVSpeechSynthesisVoice *v = [self resolvedVoice];
    if (!v) {
        return @"系统默认";
    }
    return [self p_displayNameForVoice:v];
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
    [[NSNotificationCenter defaultCenter] postNotificationName:RDVoiceListChangedNotification object:nil];
}

#pragma mark - Resolve

- (AVSpeechSynthesisVoice *)resolvedVoice
{
    if (self.preferredVoiceIdentifier.length) {
        AVSpeechSynthesisVoice *v = [AVSpeechSynthesisVoice voiceWithIdentifier:self.preferredVoiceIdentifier];
        if (v) {
            return v;
        }
    }
    // 自动:优先中文增强,再普通 zh-CN
    NSArray *all = [AVSpeechSynthesisVoice speechVoices];
    AVSpeechSynthesisVoice *enhanced = nil;
    AVSpeechSynthesisVoice *normal = nil;
    for (AVSpeechSynthesisVoice *v in all) {
        if (![v.language hasPrefix:@"zh"]) {
            continue;
        }
        if ([self p_isEnhanced:v]) {
            if (!enhanced) {
                enhanced = v;
            }
        } else if (!normal && [v.language isEqualToString:@"zh-CN"]) {
            normal = v;
        }
    }
    if (enhanced) {
        return enhanced;
    }
    if (normal) {
        return normal;
    }
    return [AVSpeechSynthesisVoice voiceWithLanguage:@"zh-CN"] ?: [AVSpeechSynthesisVoice speechVoices].firstObject;
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
    NSMutableArray *favorites = [NSMutableArray array];
    NSMutableArray *chinese = [NSMutableArray array];
    NSMutableArray *personal = [NSMutableArray array];
    NSMutableArray *others = [NSMutableArray array];

    NSSet *favSet = [NSSet setWithArray:self.favoriteIdentifiers ?: @[]];

    for (RDVoiceOption *opt in [self allOptions]) {
        if ([favSet containsObject:opt.identifier]) {
            RDVoiceOption *copy = [self p_optionFromVoice:[AVSpeechSynthesisVoice voiceWithIdentifier:opt.identifier]];
            copy.kind = RDVoiceKindFavorite;
            [favorites addObject:copy];
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
    if (personal.count) {
        [groups addObject:@{@"title": @"个人声音", @"items": personal}];
    }
    if (chinese.count) {
        [groups addObject:@{@"title": @"中文语音", @"items": chinese}];
    }
    if (others.count) {
        [groups addObject:@{@"title": @"其他语言", @"items": others}];
    }
    return groups;
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
    id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:error];
    if (![json isKindOfClass:[NSDictionary class]]) {
        if (error) {
            *error = [NSError errorWithDomain:@"RDVoice" code:1 userInfo:@{NSLocalizedDescriptionKey: @"无效的语音配置文件"}];
        }
        return NO;
    }
    NSDictionary *dict = (NSDictionary *)json;
    NSString *pref = dict[@"preferredVoiceIdentifier"];
    if ([pref isKindOfClass:[NSString class]]) {
        // 若 identifier 在本机不存在,仍写入,resolved 时会回退
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
