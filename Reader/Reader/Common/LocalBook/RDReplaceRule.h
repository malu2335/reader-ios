//
//  RDReplaceRule.h
//  Reader
//
//  正文净化/替换规则 — 兼容阅读/legado ReplaceRule JSON
//  字段:name/group/pattern/replacement/isRegex/isEnabled/order/scopeTitle/scopeContent/id
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSString * const RDReplaceRuleImportDidChangeNotification;

@interface RDReplaceRule : NSObject <NSCopying>
/// 内部稳定 id(UUID);legado 数字 id 映射到此或存在 legadoId
@property (nonatomic, copy) NSString *ruleId;
/// legado 原始数字 id(可选,导入时保留便于合并)
@property (nonatomic, assign) long long legadoId;
@property (nonatomic, copy) NSString *name;
/// 分组,legado group
@property (nonatomic, copy) NSString *groupName;
@property (nonatomic, copy) NSString *pattern;      // 匹配串(或正则)
@property (nonatomic, copy) NSString *replacement;  // 替换为;@js: 前缀表示 JS 规则(本端跳过执行)
@property (nonatomic, assign) BOOL isRegex;
@property (nonatomic, assign) BOOL isEnabled;
@property (nonatomic, assign) NSInteger order;
/// 作用于标题(legado scopeTitle)
@property (nonatomic, assign) BOOL scopeTitle;
/// 作用于正文(legado scopeContent);默认 YES
@property (nonatomic, assign) BOOL scopeContent;

- (NSDictionary *)toDictionary;
/// 导出为 legado 兼容单条(数组元素)
- (NSDictionary *)toLegadoDictionary;
+ (nullable instancetype)ruleFromDictionary:(NSDictionary *)dict;

/// 惰性编译并缓存的正则;非法 pattern 返回 nil
- (nullable NSRegularExpression *)compiledRegex;
/// 是否为 JS 替换(本端不执行,仅保留/展示)
- (BOOL)isJavaScriptReplacement;
@end

@interface RDReplaceRuleStore : NSObject
+ (instancetype)sharedInstance;
@property (nonatomic, copy, readonly) NSArray <RDReplaceRule *>*rules;

- (void)reload;
- (BOOL)save;
- (void)upsertRule:(RDReplaceRule *)rule;
- (void)removeRuleId:(NSString *)ruleId;
- (void)replaceAllRules:(NSArray <RDReplaceRule *>*)rules;

/// 按启用规则依次净化正文(仅 scopeContent=YES 的规则)
- (NSString *)applyToText:(NSString *)text;
/// 净化标题(仅 scopeTitle=YES)
- (NSString *)applyToTitle:(NSString *)title;

/// 内置默认规则(首次空库时植入)
+ (NSArray <RDReplaceRule *>*)defaultRules;

/// 从 legado / 本 App JSON 解析规则列表(支持根数组、{rules:[]}、单对象)
+ (nullable NSArray <RDReplaceRule *>*)rulesFromJSONData:(NSData *)data error:(NSError * _Nullable * _Nullable)error;

/// 合并导入:按 legadoId 或 (name+pattern) 更新,否则追加。返回新增/更新条数
- (NSInteger)importRules:(NSArray <RDReplaceRule *>*)incoming merge:(BOOL)merge;

/// 导出全部为 legado 兼容 JSON data(数组)
- (nullable NSData *)exportLegadoJSONData;

/// 从 URL 远程拉取并导入(HTTP/HTTPS)
- (void)importFromURLString:(NSString *)urlString
                      merge:(BOOL)merge
                 completion:(void (^)(NSInteger count, NSError * _Nullable error))completion;

@end

NS_ASSUME_NONNULL_END
