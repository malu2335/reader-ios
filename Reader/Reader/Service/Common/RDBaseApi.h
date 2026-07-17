//
//  RDBaseApi.h
//  Reader
//
//  Created by yuenov on 2019/12/23.
//  Copyright © 2019 yuenov. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "RDHttpModel.h"
#import "RDModelAgent.h"
#define kBaseApiOtherError  @"离线版本不支持网络请求"

#define kSuccHttpCode 0
#define kCreatUserCode 101
typedef NS_ENUM(NSInteger, YTKRequestMethod) {
    YTKRequestMethodGET = 0,
    YTKRequestMethodPOST,
};

typedef NS_ENUM(NSInteger, YTKRequestSerializerType) {
    YTKRequestSerializerTypeHTTP = 0,
    YTKRequestSerializerTypeJSON,
};

NS_ASSUME_NONNULL_BEGIN

@interface RDBaseApi : NSObject
@property(nonatomic, strong) RDHttpModel *httpModel;
- (BOOL)isSucc;

- (NSString *)errorMsg;

- (void)startWithCompletionBlock:(void (^)(RDBaseApi *request, NSString *error))block;
- (void)stop;
@end

NS_ASSUME_NONNULL_END
