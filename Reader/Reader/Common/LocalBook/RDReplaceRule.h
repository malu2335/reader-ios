//
//  RDReplaceRule.h
//  Reader
//
//  正文净化/替换规则(对齐 legado ReplaceRule 核心字段)
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface RDReplaceRule : NSObject <NSCopying>
@property (nonatomic, copy) NSString *ruleId;
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSString *pattern;      // 匹配串(或正则)
@property (nonatomic, copy) NSString *replacement;  // 替换为
@property (nonatomic, assign) BOOL isRegex;
@property (nonatomic, assign) BOOL isEnabled;
@property (nonatomic, assign) NSInteger order;

- (NSDictionary *)toDictionary;
+ (nullable instancetype)ruleFromDictionary:(NSDictionary *)dict;

/// 惰性编译并缓存的正则(pattern 变化自动失效);非法 pattern 返回 nil
- (nullable NSRegularExpression *)compiledRegex;
@end

@interface RDReplaceRuleStore : NSObject
+ (instancetype)sharedInstance;
@property (nonatomic, copy, readonly) NSArray <RDReplaceRule *>*rules;

- (void)reload;
- (BOOL)save;
- (void)upsertRule:(RDReplaceRule *)rule;
- (void)removeRuleId:(NSString *)ruleId;
- (void)replaceAllRules:(NSArray <RDReplaceRule *>*)rules;

/// 按启用规则依次净化正文
- (NSString *)applyToText:(NSString *)text;

/// 内置默认规则(首次空库时植入)
+ (NSArray <RDReplaceRule *>*)defaultRules;
@end

NS_ASSUME_NONNULL_END
