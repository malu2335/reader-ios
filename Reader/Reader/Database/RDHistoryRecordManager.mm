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

+(void)insertOrReplaceModel:(RDBookDetailModel *)model
{
    [[RDDatabaseManager sharedInstance] performSync:^(WCTDatabase *db) {
        [db insertOrReplaceObject:model into:kHistoryRecordTable];
    }];
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

+(void)deleteHistoryWithBookId:(NSInteger)bookId
{
    [[RDDatabaseManager sharedInstance] performSync:^(WCTDatabase *db) {
        [db deleteObjectsFromTable:kHistoryRecordTable where:RDBookDetailModel.bookId.is(bookId)];
    }];
}

+(void)deleteAllHistory
{
    [[RDDatabaseManager sharedInstance] performSync:^(WCTDatabase *db) {
        [db deleteAllObjectsFromTable:kHistoryRecordTable];
    }];
}
@end
