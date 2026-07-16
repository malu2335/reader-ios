//
//  RDCharpterModel.mm
//  Reader
//
//  Created by yuenov on 2019/11/21.
//  Copyright © 2019 yuenov. All rights reserved.
//

#import "RDCharpterModel+WCTTableCoding.h"
#import "RDCharpterModel.h"
#import <WCDB/WCDB.h>


@implementation RDCharpterModel

WCDB_IMPLEMENTATION(RDCharpterModel)
WCDB_SYNTHESIZE_COLUMN(RDCharpterModel, primaryId,"primaryId")
WCDB_SYNTHESIZE_COLUMN(RDCharpterModel, charpterId,"charpterId")
WCDB_SYNTHESIZE_COLUMN(RDCharpterModel, name,"name")
WCDB_SYNTHESIZE_COLUMN(RDCharpterModel, content,"content")
WCDB_SYNTHESIZE_COLUMN(RDCharpterModel, bookId,"bookId")
WCDB_SYNTHESIZE_COLUMN(RDCharpterModel, bookName,"bookName")
WCDB_SYNTHESIZE_COLUMN(RDCharpterModel, author,"author")


WCDB_PRIMARY(RDCharpterModel, primaryId)


WCDB_INDEX(RDCharpterModel, "_bookId_charpterId_index", bookId)
WCDB_INDEX(RDCharpterModel, "_bookId_charpterId_index", charpterId)

// 不再对 content 建索引:大文本写入放大、空间膨胀

+ (NSDictionary *)modelCustomPropertyMapper {
    return @{@"charpterId" : @"id"};
}

-(NSString *)primaryId
{
    if (!_primaryId) {
        // 分隔符避免 bookId/charpterId 数字拼接碰撞(如 -12+3 与 -1+23)
        _primaryId = [NSString stringWithFormat:@"%@_%@", @(_bookId), @(_charpterId)];
    }
    return _primaryId;
}
-(BOOL)isEqual:(id)object
{
    if (object == self) {
        return YES;
    }
    if ([object isKindOfClass:self.class]) {
        RDCharpterModel *model = object;
        return self.bookId == model.bookId && self.charpterId == model.charpterId;
    }
    return NO;
}

- (NSUInteger)hash
{
    return (NSUInteger)self.bookId * 31u + (NSUInteger)self.charpterId;
}
@end
