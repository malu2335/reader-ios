//
//  RDGlobalModel.m
//  Reader
//
//  Created by yuenov on 2019/12/23.
//  Copyright © 2019 yuenov. All rights reserved.
//

#import "RDGlobalModel.h"
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
    self.baseUrl = @"";
    self.picBaseUrl = @"";
}
@end
