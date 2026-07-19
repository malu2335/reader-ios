//
//  RDDateUtil.m
//  Reader
//
//  Created by yuenov on 2019/12/24.
//  Copyright © 2019 yuenov. All rights reserved.
//

#import "RDDateUtil.h"

@implementation RDDateUtil
+(NSString *)lastUpdateTimeWith:(NSTimeInterval)time
{
    NSTimeInterval interval = ([NSDate date].timeIntervalSince1970*1000-time)/1000;
    NSInteger year,month,day,hour,mintiue;
    mintiue = interval/60;
    hour = interval/60/60;
    day = interval/60/60/24;
    month = interval/60/60/24/30;
    year = interval/60/60/24/365;
    if (year>0) {
        return [NSString stringWithFormat:@"%ld年前",(long)year];
    }
    if (month>0) {
        return [NSString stringWithFormat:@"%ld月前",(long)month];
    }
    if (day>0) {
        return [NSString stringWithFormat:@"%ld天前",(long)day];
    }
    if (hour>0) {
        return [NSString stringWithFormat:@"%ld小时前",(long)hour];
    }
    if (mintiue>0) {
        return [NSString stringWithFormat:@"%ld分钟前",(long)mintiue];
    }
    return nil;
}
@end
