//
//  RDAIClient.h
//  Reader
//
//  多供应商 AI 翻译客户端:请求构建 / 响应解析 / 可注入 transport / 可取消
//

#import <Foundation/Foundation.h>
#import "RDAIConfig.h"

NS_ASSUME_NONNULL_BEGIN

typedef void (^RDAITransportCompletion)(NSData * _Nullable data, NSHTTPURLResponse * _Nullable response, NSError * _Nullable error);

@protocol RDAIHTTPTransport <NSObject>
/// 发送请求,返回可取消 token(NSURLSessionTask 或任意 id)
- (id)sendRequest:(NSURLRequest *)request completion:(RDAITransportCompletion)completion;
- (void)cancelToken:(nullable id)token;
@end

@interface RDAIURLSessionTransport : NSObject <RDAIHTTPTransport>
@end

@interface RDAIRecordingTransport : NSObject <RDAIHTTPTransport>
@property (nonatomic, strong, nullable) NSURLRequest *lastRequest;
@property (nonatomic, copy, nullable) NSData *responseData;
@property (nonatomic, assign) NSInteger statusCode;
@property (nonatomic, copy, nullable) NSError *errorToReturn;
@property (nonatomic, assign) NSInteger sendCount;
@end

@interface RDAIClient : NSObject

@property (nonatomic, strong) id<RDAIHTTPTransport> transport;
/// 是否有进行中的翻译
@property (nonatomic, assign, readonly) BOOL isTranslating;

+ (instancetype)sharedClient;

/// 取消「可取消」类进行中的翻译(Replace 策略)
- (void)cancelInFlightTranslate;

/// 统一翻译入口;默认会取消上一次 Replace 请求
- (void)translateText:(NSString *)text
              profile:(RDAIConfigProfile *)profile
           completion:(void (^)(NSString * _Nullable translated, NSError * _Nullable error))completion;

/// concurrent=YES:不取消其他请求,适合翻页后台预取;不置 isTranslating 门闩
- (void)translateText:(NSString *)text
              profile:(RDAIConfigProfile *)profile
           concurrent:(BOOL)concurrent
           completion:(void (^)(NSString * _Nullable translated, NSError * _Nullable error))completion;

- (nullable NSString *)translateTextSync:(NSString *)text
                                 profile:(RDAIConfigProfile *)profile
                                   error:(NSError * _Nullable * _Nullable)error;

+ (nullable NSURLRequest *)requestForProfile:(RDAIConfigProfile *)profile
                                        text:(NSString *)text
                                       error:(NSError * _Nullable * _Nullable)error;

+ (nullable NSString *)translatedTextFromResponseData:(NSData *)data
                                              profile:(RDAIConfigProfile *)profile
                                                error:(NSError * _Nullable * _Nullable)error;

+ (NSString *)defaultBaseURLForType:(NSString *)type;
+ (BOOL)isOpenAIFamily:(NSString *)type;
+ (BOOL)isAnthropicFamily:(NSString *)type;
+ (BOOL)isGeminiFamily:(NSString *)type;

/// Base URL 安全策略:默认仅 HTTPS;HTTP 仅允许 loopback / 局域网(本地 Ollama 等)。拒绝其它 scheme。
+ (BOOL)validateBaseURLString:(NSString *)baseURL error:(NSError * _Nullable * _Nullable)error;

@end

NS_ASSUME_NONNULL_END
