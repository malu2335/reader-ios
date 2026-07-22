//
//  RDHistoryRecordManager.h
//  Reader
//
//  Created by yuenov on 2020/3/2.
//  Copyright © 2020 yuenov. All rights reserved.
//

#import <Foundation/Foundation.h>

@class RDBookDetailModel;

@interface RDHistoryRecordManager : NSObject

/// 插入阅读记录;返回是否写库成功(P2-DB-03)
+(BOOL)insertOrReplaceModel:(RDBookDetailModel *)model;

/// 获取所有的阅读记录
+(NSArray *)getAllHistory;


/// 删除某一个阅读记录;返回是否写库成功(P2-DB-03)
/// @param bookId 书籍Id
+(BOOL)deleteHistoryWithBookId:(NSInteger )bookId;

/// 获取阅读记录数量
+(NSInteger)getHisoryCount;


/// 删除所有的记录
/// 清空历史;返回是否写库成功(Issue 14)
+(BOOL)deleteAllHistory;
@end


