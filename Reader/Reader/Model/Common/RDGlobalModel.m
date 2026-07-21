//
//  RDGlobalModel.m
//  Reader
//
//  历史在线书城全局配置残留。本地优先产品不再请求 yuenov；
//  保留单例与字段以免旧归档/工具方法崩溃，但不初始化远程 URL(Phase 5)。
//

#import "RDGlobalModel.h"
#import "RDCommParamManager.h"
#import "RDConfigModel.h"

static inline uint32_t fnv_32a(void *buf, size_t len) {
    uint32_t hval = 0x811C9DC5;
    unsigned char *bp = (unsigned char *) buf;
    unsigned char *be = bp + len;
    while (bp < be) {
        hval ^= (uint32_t) *bp++;
        hval += (hval << 1) + (hval << 4) +
                (hval << 7) + (hval << 8) + (hval << 24);
    }
    return hval;
}

@implementation RDGlobalModel
+ (RDGlobalModel *)sharedInstance {
    static RDGlobalModel *sharedInstance = nil;
    static dispatch_once_t onceToken;

    dispatch_once(&onceToken, ^{
        if (!sharedInstance) {
            sharedInstance = [[self alloc] init];
            // 本地阅读器:不配置远程 base/pic URL,避免误连在线书城
            sharedInstance.baseUrl = @"";
            sharedInstance.picBaseUrl = @"";
        }
    });

    return sharedInstance;
}
- (NSString *)domain
{
    return @"";
}
-(NSString *)prefix
{
    return @"";
}

- (NSString *)fnv1aHashForStr:(NSString *)str {
    if (str.length == 0) {
        NSAssert(NO, @"nil input");
        return nil;
    }

    return [NSString stringWithFormat:@"%x", fnv_32a((void *) [str UTF8String], str.length)];
}

-(void)changePort
{
    // 在线端口轮换已废弃
}
@end
