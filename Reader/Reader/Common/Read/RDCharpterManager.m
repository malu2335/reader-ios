//
//  RDChapterManager.m
//  Reader
//
//  Created by yuenov on 2019/12/29.
//  Copyright © 2019 yuenov. All rights reserved.
//
//  纯本地阅读器:章节一律来自本地数据库,不再发起任何网络请求。
//  历史遗留的在线书(bookId>0)若章节缺失,直接提示,不回源拉取。
//

#import "RDCharpterManager.h"
#import "RDUtilities.h"
#import "RDCharpterModel.h"
#import "RDCharpterDataManager.h"


@implementation RDCharpterManager


+(void)getCharpterWithBookId:(NSInteger)bookId complete:(void(^)(BOOL success,RDCharpterModel *model))complete
{
    [self getCharpterWithBookId:bookId charpterId:-1 complete:complete];
}

+(void)getCharpterWithBookId:(NSInteger)bookId charpterId:(NSInteger)charpterId complete:(void(^)(BOOL success,RDCharpterModel *model))complete
{
    NSInteger localCharpterId = charpterId;
    if (localCharpterId == -1) {
        localCharpterId = [RDCharpterDataManager getFirstCharpterIdWirhBookId:bookId];
    }
    RDCharpterModel *local = [RDCharpterDataManager getCharpterWithBookId:bookId charpterId:localCharpterId];
    if (local.content.length > 0) {
        if (complete) {
            complete(YES, local);
        }
    }
    else{
        [RDToastView showText:@"内容不存在" delay:1 inView:[RDUtilities applicationKeyWindow]];
        if (complete) {
            complete(NO, nil);
        }
    }
}

+(void)slientDownWithBookId:(NSInteger)bookId charpterIds:(NSArray *)charpters
{
    //本地书内容已全部入库,无需预下载
}

+(void)getAllNoConetntCharpterWithBookId:(NSInteger)bookId complete:(void(^)(NSArray <RDCharpterModel *>*charpters))complete
{
    if (complete) {
        complete(@[]);
    }
}
@end
