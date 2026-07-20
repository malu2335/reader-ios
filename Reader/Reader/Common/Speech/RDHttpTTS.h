//
//  RDHttpTTS.h
//  Reader
//
//  在线朗读引擎(兼容阅读/legado HttpTTS JSON 子集)
//  字段对齐: id / name / url / contentType / header / concurrentRate
//  url 支持占位: {{speakText}} {{speakSpeed}} (文本会做 URL encode)
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// preferredVoiceIdentifier 前缀,与系统 AVSpeech identifier 区分
FOUNDATION_EXPORT NSString * const RDHttpTTSIdentifierPrefix; // @"httpTts:"

@interface RDHttpTTS : NSObject <NSCopying>
@property (nonatomic, assign) long long engineId;
@property (nonatomic, copy) NSString *name;
/// 请求地址模板,可含 {{speakText}} {{speakSpeed}}
@property (nonatomic, copy) NSString *url;
/// 期望 Content-Type 正则,可空;若服务返回 text/json 一律视为错误
@property (nonatomic, copy, nullable) NSString *contentType;
/// JSON 对象字符串,如 {"Authorization":"Bearer xxx"}
@property (nonatomic, copy, nullable) NSString *header;
/// 并发限制提示(legado 字段,当前 iOS 实现串行请求,仅保存)
@property (nonatomic, copy, nullable) NSString *concurrentRate;
@property (nonatomic, assign) NSTimeInterval lastUpdateTime;

/// 选中用的稳定 identifier: httpTts:<id>
- (NSString *)voiceIdentifier;

- (NSDictionary *)toDictionary;
+ (nullable instancetype)engineFromDictionary:(NSDictionary *)dict;
/// 解析 legado 单对象或数组 JSON
+ (NSArray <RDHttpTTS *>*)enginesFromJSONData:(NSData *)data error:(NSError * _Nullable * _Nullable)error;

@end

@interface RDHttpTTSStore : NSObject
+ (instancetype)sharedInstance;
@property (nonatomic, copy, readonly) NSArray <RDHttpTTS *>*engines;
- (nullable RDHttpTTS *)engineWithId:(long long)engineId;
- (nullable RDHttpTTS *)engineWithVoiceIdentifier:(NSString *)identifier;
- (BOOL)upsertEngine:(RDHttpTTS *)engine;
- (void)removeEngineId:(long long)engineId;
/// 导入 legado 格式,合并写入;返回导入条数
- (NSInteger)importJSONData:(NSData *)data error:(NSError * _Nullable * _Nullable)error;
- (void)reloadFromDisk;
@end

NS_ASSUME_NONNULL_END
