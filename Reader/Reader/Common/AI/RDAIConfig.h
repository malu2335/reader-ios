//
//  RDAIConfig.h
//  Reader
//
//  AI 配置:多供应商 profile(OpenAI / Anthropic / Gemini 及其兼容格式)
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// 六种供应商类型(展示名与协议选择共用同一字符串)
FOUNDATION_EXPORT NSString * const RDAIProviderTypeOpenAI;
FOUNDATION_EXPORT NSString * const RDAIProviderTypeAnthropic;
FOUNDATION_EXPORT NSString * const RDAIProviderTypeOpenAICompat;
FOUNDATION_EXPORT NSString * const RDAIProviderTypeAnthropicCompat;
FOUNDATION_EXPORT NSString * const RDAIProviderTypeGemini;
FOUNDATION_EXPORT NSString * const RDAIProviderTypeGeminiCompat;

/// 备份 zip 中的 AI 配置条目名(legado 风格附加项)
FOUNDATION_EXPORT NSString * const RDAIConfigBackupEntryName;

@interface RDAIConfigProfile : NSObject <NSCopying>
@property (nonatomic, copy) NSString *profileId;
@property (nonatomic, copy) NSString *name;
/// 必须是六种类型之一
@property (nonatomic, copy) NSString *type;
@property (nonatomic, copy) NSString *apiKey;
@property (nonatomic, copy) NSString *model;
/// 自定义 Base URL;三种「格式」类型必填,原生类型可空(走默认域名)
@property (nonatomic, copy, nullable) NSString *baseURL;
/// 备份恢复后的待确认状态:为 YES 时 isUsable 为 NO,须用户在设置中「设为当前」或重新保存后才可用于出站翻译
@property (nonatomic, assign) BOOL pendingConfirm;
/// 是否可用(至少有 key + model;格式类型还需 baseURL;且非 pendingConfirm)
- (BOOL)isUsable;
- (NSDictionary *)toDictionary;
+ (nullable instancetype)profileFromDictionary:(NSDictionary *)dict;
@end

@interface RDAIConfigStore : NSObject

+ (instancetype)sharedInstance;

/// 单元测试可注入独立目录;传 nil 恢复默认 Documents 路径
+ (void)setStorageDirectoryOverride:(nullable NSString *)directory;

@property (nonatomic, copy, readonly) NSArray <RDAIConfigProfile *>*profiles;
@property (nonatomic, copy, readonly, nullable) NSString *activeProfileId;

/// 六种可选类型(固定顺序)
+ (NSArray <NSString *>*)allProviderTypes;

- (nullable RDAIConfigProfile *)activeProfile;
- (nullable RDAIConfigProfile *)profileWithId:(NSString *)profileId;
/// 写入 profile 与 Keychain;Keychain 失败返回 NO,不更新内存/磁盘
- (BOOL)upsertProfile:(RDAIConfigProfile *)profile;
- (void)removeProfileId:(NSString *)profileId;
/// 设为当前并清除该 profile 的 pendingConfirm(用户确认)
- (void)setActiveProfileId:(nullable NSString *)activeProfileId;
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
