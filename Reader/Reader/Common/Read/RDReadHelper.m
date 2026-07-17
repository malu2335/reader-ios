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
#import "RDComicReadController.h"
#import "RDComicHelper.h"
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
    // 本地 PDF / 漫画图集使用专用阅读器(无文字章节库)
    if (book.isLocalBook && ([book.fileType isEqualToString:@"pdf"] || [RDComicHelper isComicFileType:book.fileType])) {
        NSString *path = [RDLocalBookManager absolutePathForBook:book];
        if (path.length == 0 || ![[NSFileManager defaultManager] fileExistsAtPath:path]) {
            [RDToastView showText:@"本地文件已丢失,请重新导入" delay:1.5 inView:[RDUtilities applicationKeyWindow]];
            return;
        }
        RDBookDetailModel *record = [RDReadRecordManager getReadRecordWithBookId:book.bookId] ?: book;
        [RDReadRecordManager updateReadTime:record];
        if ([RDComicHelper isComicFileType:book.fileType]) {
            RDComicReadController *comic = [[RDComicReadController alloc] init];
            comic.bookDetail = record;
            [RDAppDelegate.mainController.navigationController pushViewController:comic animated:animation];
        } else {
            RDPdfReadController *pdfController = [[RDPdfReadController alloc] init];
            pdfController.bookDetail = record;
            [RDAppDelegate.mainController.navigationController pushViewController:pdfController animated:animation];
        }
        return;
    }

    // 本地文字书:校验文件与章节完整性
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

    // 有阅读记忆:从上次章节/偏移打开
    if (record.charpterModel.charpterId != 0 || record.charpterModel.name.length > 0) {
        // 章节正文以章节库为准(记录里可能缺 content 或过旧)
        NSInteger cid = record.charpterModel.charpterId;
        [RDCharpterManager getCharpterWithBookId:book.bookId charpterId:cid complete:^(BOOL success, RDCharpterModel *model) {
            if (success && model) {
                record.charpterModel = model;
                // 保留 page / charOffset
                controller.bookDetail = record;
                [RDReadRecordManager updateReadTime:record];
                [RDAppDelegate.mainController.navigationController pushViewController:controller animated:animation];
            } else {
                // 章节失效则从第一章重新
                [self p_openFromFirstChapter:book record:record controller:controller animation:animation];
            }
        }];
        return;
    }

    [self p_openFromFirstChapter:book record:record controller:controller animation:animation];
}

+ (void)p_openFromFirstChapter:(RDBookDetailModel *)book
                        record:(RDBookDetailModel *)record
                    controller:(RDReadPageViewController *)controller
                     animation:(BOOL)animation
{
    [RDCharpterManager getCharpterWithBookId:book.bookId complete:^(BOOL success,RDCharpterModel * _Nonnull model) {
        if (success) {
            RDBookDetailModel *detail  = [book yy_modelCopy];
            detail.onBookshelf = record.onBookshelf;
            if (record) {
                // 阅读记录中的书名/作者可能由用户在书架手动修改,不要被线上详情覆盖。
                detail.title = record.title;
                detail.author = record.author;
            }
            detail.charpterModel = model;
            detail.page = 0;
            detail.charOffset = 0;
            // 继承本地字段
            if (record.localPath.length) {
                detail.localPath = record.localPath;
                detail.fileType = record.fileType;
            }
            [RDReadRecordManager insertOrReplaceModel:detail];
            controller.bookDetail = detail;
            [RDAppDelegate.mainController.navigationController pushViewController:controller animated:animation];
        }
        else if (book.isLocalBook) {
            [RDToastView showText:@"无法打开,请重新导入本书" delay:1.5 inView:[RDUtilities applicationKeyWindow]];
        }
    }];
}

+(void)beginReadWithBookDetail:(RDBookDetailModel *)book charpterId:(NSInteger)charpterid
{
    [RDCharpterManager getCharpterWithBookId:book.bookId charpterId:charpterid complete:^(BOOL success, RDCharpterModel *model) {
        if (success) {
            RDReadPageViewController *controller = [[RDReadPageViewController alloc] init];
            RDBookDetailModel *record = [RDReadRecordManager getReadRecordWithBookId:book.bookId];
            RDBookDetailModel *detail = record ? [record yy_modelCopy] : [book yy_modelCopy];
            detail.charpterModel = model;
            // 目录跳转从章首
            detail.page = 0;
            detail.charOffset = 0;
            if (record) {
                detail.onBookshelf = record.onBookshelf;
            }
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
