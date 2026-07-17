//
//  RDAllCategoryApi.m
//  Reader
//
//  Created by yuenov on 2020/2/25.
//  Copyright © 2020 yuenov. All rights reserved.
//

#import "RDAllCategoryApi.h"

@implementation RDAllCategoryApi
- (NSString *)requestUrl {
    return @"";
}

-(NSArray <RDChannelModel *>*)channel
{
    return [[RDModelAgent agent] createModel:RDChannelModel.class fromJson:self.httpModel.data[@"channels"]];
}
@end
