//
//  RDHttpTTSClient.h
//  Reader
//
//  在线 TTS 请求:替换 legado 占位符 → HTTP 拉音频 → 主线程回调
//

#import <Foundation/Foundation.h>
@class RDHttpTTS;

NS_ASSUME_NONNULL_BEGIN

@interface RDHttpTTSClient : NSObject

+ (instancetype)sharedClient;

/// 取消当前在途请求
- (void)cancel;

/// speakSpeed 对齐 legado: 常用 5~15,对应语速;默认 10
- (void)fetchAudioForEngine:(RDHttpTTS *)engine
                       text:(NSString *)text
                 speakSpeed:(NSInteger)speakSpeed
                 completion:(void(^)(NSData * _Nullable audio, NSError * _Nullable error))completion;

/// 将 url 模板中的 {{speakText}} / {{speakSpeed}} 替换(公开便于测试)
+ (NSString *)resolveURLTemplate:(NSString *)template
                            text:(NSString *)text
                      speakSpeed:(NSInteger)speakSpeed;

@end

NS_ASSUME_NONNULL_END
