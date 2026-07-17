//
//  RDBaseApi.m
//  Reader
//
//  Created by yuenov on 2019/12/23.
//  Copyright © 2019 yuenov. All rights reserved.
//

#import "RDBaseApi.h"
@implementation RDBaseApi

- (YTKRequestMethod)requestMethod {
    return YTKRequestMethodGET;
}

- (YTKRequestSerializerType)requestSerializerType {
    return YTKRequestSerializerTypeHTTP;
}

- (BOOL)isSucc {
    return NO;
}
- (NSString *)errorMsg {
    return kBaseApiOtherError;
}
- (void)startWithCompletionBlock:(void (^)(RDBaseApi *request, NSString *error))block {
    if (!block) {
        return;
    }
    dispatch_async(dispatch_get_main_queue(), ^{
        block(self, kBaseApiOtherError);
    });
}

- (void)stop
{
}
@end
