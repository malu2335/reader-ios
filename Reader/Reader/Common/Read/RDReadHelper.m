//
//  RDReadHelper.m
//  Reader
//
//  Created by yuenov on 2020/2/21.
//  Copyright © 2020 yuenov. All rights reserved.
//

#import "RDReadHelper.h"
#import "RDBookDetailModel.h"
#import "RDReadPageViewController.h"
#import "RDReadRecordManager.h"
#import "RDCharpterManager.h"
#import "RDCharpterDataManager.h"
#import "AppDelegate.h"
#import "RDMainController.h"
#import "RDPdfReadController.h"
#import "RDLocalBookManager.h"

@implementation RDReadHelper

+(void)beginReadWithBookDetail:(RDBookDetailModel *)book
{
    [self beginReadWithBookDetail:book animation:YES];
}

+(void)beginReadWithBookDetail:(RDBookDetailModel *)book animation:(BOOL)animation
{
    if (!book) {
        return;
    }
    // 本地 PDF 使用专用阅读器
    if (book.isLocalBook && [book.fileType isEqualToString:@"pdf"]) {
        NSString *path = [RDLocalBookManager absolutePathForBook:book];
        if (path.length == 0 || ![[NSFileManager defaultManager] fileExistsAtPath:path]) {
            [RDToastView showText:@"本地文件已丢失,请重新导入" delay:1.5 inView:[RDUtilities applicationKeyWindow]];
            return;
        }
        RDBookDetailModel *pdfRecord = [RDReadRecordManager getReadRecordWithBookId:book.bookId] ?: book;
        [RDReadRecordManager updateReadTime:pdfRecord];
        RDPdfReadController *pdfController = [[RDPdfReadController alloc] init];
        pdfController.bookDetail = pdfRecord;
        [RDAppDelegate.mainController.navigationController pushViewController:pdfController animated:animation];
        return;
    }

    // 本地非 PDF:校验文件与章节完整性
    if (book.isLocalBook) {
        NSString *path = [RDLocalBookManager absolutePathForBook:book];
        if (path.length == 0 || ![[NSFileManager defaultManager] fileExistsAtPath:path]) {
            [RDToastView showText:@"本地文件已丢失,请重新导入" delay:1.5 inView:[RDUtilities applicationKeyWindow]];
            return;
        }
        if (![RDCharpterDataManager isExsitWithBookId:book.bookId]) {
            [RDToastView showText:@"章节数据缺失,请删除后重新导入" delay:1.5 inView:[RDUtilities applicationKeyWindow]];
            return;
        }
    }

    RDBookDetailModel *record = [RDReadRecordManager getReadRecordWithBookId:book.bookId];
    RDReadPageViewController *controller = [[RDReadPageViewController alloc] init];
    if (record.charpterModel) {
        controller.bookDetail = record;
        [RDReadRecordManager updateReadTime:record];
        [RDAppDelegate.mainController.navigationController pushViewController:controller animated:animation];
    }
    else{
        [RDCharpterManager getCharpterWithBookId:book.bookId complete:^(BOOL success,RDCharpterModel * _Nonnull model) {
            if (success) {
                RDBookDetailModel *detail  = [book yy_modelCopy];
                detail.onBookshelf = record.onBookshelf;
                detail.charpterModel = model;
                [RDReadRecordManager insertOrReplaceModel:detail];
                controller.bookDetail = detail;
                [RDAppDelegate.mainController.navigationController pushViewController:controller animated:animation];
            }
            else if (book.isLocalBook) {
                [RDToastView showText:@"无法打开,请重新导入本书" delay:1.5 inView:[RDUtilities applicationKeyWindow]];
            }
        }];
    }
}

+(void)beginReadWithBookDetail:(RDBookDetailModel *)book charpterId:(NSInteger)charpterid
{
    [RDCharpterManager getCharpterWithBookId:book.bookId charpterId:charpterid complete:^(BOOL success, RDCharpterModel *model) {
        if (success) {
            RDReadPageViewController *controller = [[RDReadPageViewController alloc] init];
            RDBookDetailModel *detail = [book yy_modelCopy];
            detail.charpterModel = model;
            [RDReadRecordManager insertOrReplaceModel:detail];
            controller.bookDetail = detail;
            [[RDUtilities getCurrentVC].navigationController pushViewController:controller animated:YES];
        }
    }];
}

+(void)addBookshelfWithBookDetail:(RDBookDetailModel *)book comlpete:(void(^)(void))complete
{
    RDBookDetailModel *record = [RDReadRecordManager getReadRecordWithBookId:book.bookId];
    if (record) {
        record.onBookshelf = YES;
        [RDReadRecordManager updateBookshelfState:record];
        if (complete) {
            complete();
        }
    }
    else{
        RDBookDetailModel *detail = [book yy_modelCopy];
        detail.onBookshelf = YES;
        [RDReadRecordManager insertOrReplaceModel:detail];
        if (complete) {
            complete();
        }
        
    }
    
}
@end
