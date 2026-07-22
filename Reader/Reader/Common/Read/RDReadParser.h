//
//  RDReadParser.h
//  Reader
//
//  Created by yuenov on 2019/11/21.
//  Copyright © 2019 yuenov. All rights reserved.
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

#define kTopMargin (40+[UIView safeTopBar])
#define kBottomMargin (40+[UIView safeBottomBar])
#define kLeftMargin 20
#define kRightMargin 20

@interface RDReadParser : UIView

/// 分页。preferBackground=YES 时在后台线程排版(不截断正文),完成后主线程回调。
/// dataSource 等必须同步返回时传 NO:主线程同步执行,超长章才做保护性截断。
+(void)paginateWithContent:(NSString *)content charpter:(NSString *)charpter bounds:(CGRect)bounds complete:(void(^)(NSAttributedString *content,NSArray *pages))complete;
+(void)paginateWithContent:(NSString *)content
                  charpter:(NSString *)charpter
                    bounds:(CGRect)bounds
          preferBackground:(BOOL)preferBackground
                  complete:(void(^)(NSAttributedString *content,NSArray *pages))complete;

/// 完整分页 API:可指定串行队列与 cancelCheck(分页循环内检查,真正停止 work)(P2-FE-02)
/// allowTruncate=YES 时超长章截断(仅同步兜底路径);后台预分页传 NO。
+(void)paginateWithContent:(NSString *)content
                  charpter:(NSString *)charpter
                    bounds:(CGRect)bounds
                     queue:(nullable dispatch_queue_t)queue
              allowTruncate:(BOOL)allowTruncate
               cancelCheck:(nullable BOOL(^)(void))cancelCheck
                  complete:(void(^)(NSAttributedString *content,NSArray *pages))complete;


+(NSString *)getShowContent:(NSString *)content charpter:(NSString *)charpter;

/// 解析内容属性
+(NSDictionary *)paraserFontArrribute:(RDReadConfigManager *)config;

/// 解析章节属性
+(NSDictionary *)paraserChapterFontArrribute:(RDReadConfigManager *)config;


@end

NS_ASSUME_NONNULL_END
