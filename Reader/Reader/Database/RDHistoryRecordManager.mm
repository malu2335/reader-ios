//
//  RDHistoryRecordManager.m
//  Reader
//
//  Created by yuenov on 2020/3/2.
//  Copyright © 2020 yuenov. All rights reserved.
//

#import "RDHistoryRecordManager.h"
#import "RDBookDetailModel.h"
#import "RDBookDetailModel+WCTTableCoding.h"
#import "RDDatabaseManager.h"

@implementation RDHistoryRecordManager

+(BOOL)insertOrReplaceModel:(RDBookDetailModel *)model
{
    if (!model || model.bookId == 0) {
        return NO;
    }
    __block BOOL ok = NO;
    [[RDDatabaseManager sharedInstance] performSync:^(WCTDatabase *db) {
        ok = [db insertOrReplaceObject:model into:kHistoryRecordTable];
    }];
    return ok;
}

+(NSInteger)getHisoryCount
{
    __block NSInteger count = 0;
    [[RDDatabaseManager sharedInstance] performSync:^(WCTDatabase *db) {
        count = [[db getOneValueOnResult:RDBookDetailModel.AnyProperty.count() fromTable:kHistoryRecordTable] integerValue];
    }];
    return count;
}

+(NSArray *)getAllHistory
{
    __block NSArray *result = nil;
    [[RDDatabaseManager sharedInstance] performSync:^(WCTDatabase *db) {
        result = [db getObjectsOfClass:RDBookDetailModel.class fromTable:kHistoryRecordTable orderBy:RDBookDetailModel.readTime.order(WCTOrderedDescending)];
    }];
    return result;
}

+(BOOL)deleteHistoryWithBookId:(NSInteger)bookId
{
    if (bookId == 0) {
        return NO;
    }
    __block BOOL ok = NO;
    [[RDDatabaseManager sharedInstance] performSync:^(WCTDatabase *db) {
        ok = [db deleteObjectsFromTable:kHistoryRecordTable where:RDBookDetailModel.bookId.is(bookId)];
    }];
    return ok;
}

+(BOOL)deleteAllHistory
{
    __block BOOL ok = NO;
    [[RDDatabaseManager sharedInstance] performSync:^(WCTDatabase *db) {
        ok = [db deleteAllObjectsFromTable:kHistoryRecordTable];
    }];
    return ok;
}
@end
