//
//  RDVoiceManager.h
//  Reader
//
//  TTS 语音管理:系统音/增强音/个人声音选择与收藏(「导入」)
//

#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>

NS_ASSUME_NONNULL_BEGIN

extern NSString * const RDVoiceListChangedNotification;
extern NSString * const RDPreferredVoiceChangedNotification;

typedef NS_ENUM(NSInteger, RDVoiceKind) {
    RDVoiceKindSystem = 0,
    RDVoiceKindEnhanced,   // 增强/高级(已下载)
    RDVoiceKindPersonal,   // 个人声音 iOS 17+
    RDVoiceKindFavorite,   // 用户收藏/导入
};

@interface RDVoiceOption : NSObject
@property (nonatomic, copy) NSString *identifier;      // AVSpeechSynthesisVoice.identifier
@property (nonatomic, copy) NSString *displayName;
@property (nonatomic, copy) NSString *language;        // zh-CN 等
@property (nonatomic, copy) NSString *detail;          // 质量/类型说明
@property (nonatomic, assign) RDVoiceKind kind;
@property (nonatomic, assign) BOOL isPreferred;
@end

@interface RDVoiceManager : NSObject

+ (instancetype)sharedInstance;

/// 当前选中的 voice identifier;nil 表示自动(优先中文增强)
@property (nonatomic, copy, nullable) NSString *preferredVoiceIdentifier;

/// 用户收藏的 identifier 列表(可视为「已导入」)
@property (nonatomic, copy, readonly) NSArray <NSString *>*favoriteIdentifiers;

/// 按分组返回可选语音:中文 / 其他 / 个人声音
- (NSArray <NSDictionary *>*)groupedOptions;
/// 全部选项(扁平)
- (NSArray <RDVoiceOption *>*)allOptions;

/// 解析当前应使用的 AVSpeechSynthesisVoice
- (AVSpeechSynthesisVoice *)resolvedVoice;

/// 设为默认朗读语音
- (void)setPreferredIdentifier:(nullable NSString *)identifier;

/// 收藏/取消收藏(导入到常用)
- (void)toggleFavoriteIdentifier:(NSString *)identifier;
- (BOOL)isFavorite:(NSString *)identifier;

/// iOS 17+ 请求个人声音权限,完成后刷新列表
- (void)requestPersonalVoiceAccess:(void(^)(BOOL granted, NSString * _Nullable message))complete;

/// 打开系统「辅助功能-朗读内容」说明(引导下载增强语音)
- (void)openSystemVoiceDownloadHelp;

/// 试听一段示例
- (void)previewIdentifier:(NSString *)identifier;
- (void)stopPreview;

/// 从 JSON 配置导入收藏与默认语音(备份互通)
- (BOOL)importConfigFromURL:(NSURL *)url error:(NSError * _Nullable * _Nullable)error;
/// 导出当前语音配置
- (nullable NSURL *)exportConfigToCachesError:(NSError * _Nullable * _Nullable)error;

/// 当前默认语音展示名
- (NSString *)preferredDisplayName;

@end

NS_ASSUME_NONNULL_END
