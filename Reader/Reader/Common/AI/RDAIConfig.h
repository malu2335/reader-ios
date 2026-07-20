//
//  RDAIConfig.h
//  Reader
//
//  AI 配置:多供应商 profile(OpenAI / Anthropic / Gemini 及其兼容格式)
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// 供应商类型(展示名与协议选择共用同一字符串)
FOUNDATION_EXPORT NSString * const RDAIProviderTypeOpenAI;
FOUNDATION_EXPORT NSString * const RDAIProviderTypeAnthropic;
FOUNDATION_EXPORT NSString * const RDAIProviderTypeOpenAICompat;
FOUNDATION_EXPORT NSString * const RDAIProviderTypeAnthropicCompat;
FOUNDATION_EXPORT NSString * const RDAIProviderTypeGemini;
FOUNDATION_EXPORT NSString * const RDAIProviderTypeGeminiCompat;
/// 小米 MiMo:OpenAI 兼容 chat;TTS 走 /v1/chat/completions + audio base64(非 /v1/audio/speech)
FOUNDATION_EXPORT NSString * const RDAIProviderTypeMiMo;

/// 备份 zip 中的 AI 配置条目名(legado 风格附加项)
FOUNDATION_EXPORT NSString * const RDAIConfigBackupEntryName;

/// 朗读引擎 identifier 前缀:aiTts:<profileId>
FOUNDATION_EXPORT NSString * const RDAITtsVoiceIdentifierPrefix;

/// 配置用途:翻译与朗读分栏隔离
FOUNDATION_EXPORT NSString * const RDAIProfileRoleTranslate;
FOUNDATION_EXPORT NSString * const RDAIProfileRoleTTS;

@interface RDAIConfigProfile : NSObject <NSCopying>
@property (nonatomic, copy) NSString *profileId;
@property (nonatomic, copy) NSString *name;
/// 必须是已知类型之一
@property (nonatomic, copy) NSString *type;
@property (nonatomic, copy) NSString *apiKey;
@property (nonatomic, copy) NSString *model;
/// 自定义 Base URL;三种「格式」类型必填,原生类型可空(走默认域名)
@property (nonatomic, copy, nullable) NSString *baseURL;
/// 备份恢复后的待确认状态:为 YES 时 isUsable 为 NO,须用户在设置中「设为当前」或重新保存后才可用于出站翻译
@property (nonatomic, assign) BOOL pendingConfirm;
/// 用途:RDAIProfileRoleTranslate / RDAIProfileRoleTTS;默认翻译
@property (nonatomic, copy) NSString *role;
/// TTS 模型:OpenAI 默认 tts-1;MiMo 默认 mimo-v2.5-tts(仅 role=tts 有效)
@property (nonatomic, copy, nullable) NSString *ttsModel;
/// TTS 音色:OpenAI 为 alloy 等;MiMo 为 mimo_default / 冰糖 等
@property (nonatomic, copy, nullable) NSString *ttsVoice;
/// 是否可用(至少有 key + model;格式类型还需 baseURL;且非 pendingConfirm);翻译用途
- (BOOL)isUsable;
/// 是否可用于 AI 朗读(role=tts + 密钥 + 支持的服务商)
- (BOOL)isTTSUsable;
/// 是否为朗读专用配置
- (BOOL)isTTSRole;
/// 是否走 MiMo 聊天补全式 TTS(chat/completions + audio base64)
- (BOOL)usesMiMoSpeechAPI;
/// 朗读用 identifier
- (NSString *)ttsVoiceIdentifier;
- (NSDictionary *)toDictionary;
+ (nullable instancetype)profileFromDictionary:(NSDictionary *)dict;
/// 常见 OpenAI TTS 音色列表
+ (NSArray <NSString *>*)commonTTSVoices;
/// 小米 MiMo-V2.5-TTS 内置音色
+ (NSArray <NSString *>*)commonMiMoTTSVoices;
@end

@interface RDAIConfigStore : NSObject

+ (instancetype)sharedInstance;

/// 单元测试可注入独立目录;传 nil 恢复默认 Documents 路径
+ (void)setStorageDirectoryOverride:(nullable NSString *)directory;

@property (nonatomic, copy, readonly) NSArray <RDAIConfigProfile *>*profiles;
@property (nonatomic, copy, readonly, nullable) NSString *activeProfileId;

/// 可选类型(固定顺序)
+ (NSArray <NSString *>*)allProviderTypes;

- (nullable RDAIConfigProfile *)activeProfile;
- (nullable RDAIConfigProfile *)profileWithId:(NSString *)profileId;
/// 写入 profile 与 Keychain/磁盘;失败返回 NO 并回滚内存(不留下半应用状态)
- (BOOL)upsertProfile:(RDAIConfigProfile *)profile;
- (void)removeProfileId:(NSString *)profileId;
/// 设为当前并清除该 profile 的 pendingConfirm(用户确认);磁盘失败返回 NO 并回滚。
/// 注意:不可命名为 setActiveProfileId:(与 readonly 属性合成 setter 冲突且必须 void)
- (BOOL)activateProfileId:(nullable NSString *)profileId;
- (void)reloadFromDisk;
- (BOOL)saveToDisk;
/// 清空内存与磁盘(备份恢复测试用)
- (void)clearAll;
/// 导出为备份 JSON data
- (nullable NSData *)exportBackupData;
/// 从备份 JSON 恢复(覆盖当前)。导入 profile 一律 pendingConfirm=YES,activeProfileId 置空;不自动出站
- (BOOL)importBackupData:(NSData *)data error:(NSError * _Nullable * _Nullable)error;

@end

NS_ASSUME_NONNULL_END
