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
#import "RDBookshelfCollectionController.h"
#import "AppDelegate.h"
#import "RDMainController.h"
#import "RDPdfReadController.h"
#import "RDComicReadController.h"
#import "RDComicChapterListController.h"
#import "RDComicHelper.h"
#import "RDLocalBookManager.h"

/// 正在打开中的 bookId,仅主线程读写(P2-02 阅读入口 single-flight)
static NSInteger sRDOpeningBookId = 0;

@implementation RDReadHelper

/// 顶部是否已经是同一本书的阅读器
+ (BOOL)p_isAlreadyReadingBookId:(NSInteger)bookId
{
    UIViewController *top = RDAppDelegate.mainController.navigationController.topViewController;
    RDBookDetailModel *detail = nil;
    if ([top isKindOfClass:RDReadPageViewController.class]) {
        detail = [(RDReadPageViewController *)top bookDetail];
    }
    else if ([top isKindOfClass:RDPdfReadController.class]) {
        detail = [(RDPdfReadController *)top bookDetail];
    }
    else if ([top isKindOfClass:RDComicReadController.class]) {
        detail = [(RDComicReadController *)top bookDetail];
    }
    return detail != nil && detail.bookId == bookId;
}

/// 返回 NO 表示这次打开请求应被忽略(重复点击或已在阅读同一本)
+ (BOOL)p_beginOpeningBookId:(NSInteger)bookId
{
    if (bookId == 0) {
        return NO;
    }
    if (sRDOpeningBookId != 0 || [self p_isAlreadyReadingBookId:bookId]) {
        return NO;
    }
    sRDOpeningBookId = bookId;
    return YES;
}

+ (void)p_endOpening
{
    sRDOpeningBookId = 0;
}

+(void)beginReadWithBookDetail:(RDBookDetailModel *)book
{
    [self beginReadWithBookDetail:book animation:YES];
}

+(void)beginReadWithBookDetail:(RDBookDetailModel *)book animation:(BOOL)animation
{
    if (!book) {
        return;
    }
    // 连击/重复入口只允许一次真正打开(P2-02)
    if (![self p_beginOpeningBookId:book.bookId]) {
        return;
    }
    // 合集壳:进成员目录,不进阅读器
    if (book.isLocalBook && book.isCollection) {
        RDBookDetailModel *record = [RDReadRecordManager getReadRecordWithBookId:book.bookId] ?: book;
        [RDReadRecordManager updateReadTime:record];
        RDBookshelfCollectionController *list = [[RDBookshelfCollectionController alloc] init];
        list.collection = record;
        [RDAppDelegate.mainController.navigationController pushViewController:list animated:animation];
        [self p_endOpening];
        return;
    }

    // 本地 PDF / 漫画图集使用专用阅读器(无文字章节库)
    if (book.isLocalBook && ([book.fileType isEqualToString:@"pdf"] || [RDComicHelper isComicFileType:book.fileType])) {
        NSString *path = [RDLocalBookManager absolutePathForBook:book];
        if (path.length == 0 || ![[NSFileManager defaultManager] fileExistsAtPath:path]) {
            [RDToastView showText:@"本地文件已丢失,请重新导入" delay:1.5 inView:[RDUtilities applicationKeyWindow]];
            [self p_endOpening];
            return;
        }
        RDBookDetailModel *record = [RDReadRecordManager getReadRecordWithBookId:book.bookId] ?: book;
        [RDReadRecordManager updateReadTime:record];
        if ([RDComicHelper isComicFileType:book.fileType]) {
            // 一律先目录:多话列表 / 扁平「整本阅读」+ 导入新话
            RDComicChapterListController *list = [[RDComicChapterListController alloc] init];
            list.bookDetail = record;
            [RDAppDelegate.mainController.navigationController pushViewController:list animated:animation];
        } else {
            RDPdfReadController *pdfController = [[RDPdfReadController alloc] init];
            pdfController.bookDetail = record;
            [RDAppDelegate.mainController.navigationController pushViewController:pdfController animated:animation];
        }
        [self p_endOpening];
        return;
    }

    // 本地文字书:校验文件与章节完整性
    if (book.isLocalBook) {
        NSString *path = [RDLocalBookManager absolutePathForBook:book];
        if (path.length == 0 || ![[NSFileManager defaultManager] fileExistsAtPath:path]) {
            [RDToastView showText:@"本地文件已丢失,请重新导入" delay:1.5 inView:[RDUtilities applicationKeyWindow]];
            [self p_endOpening];
            return;
        }
        if (![RDCharpterDataManager isExsitWithBookId:book.bookId]) {
            [RDToastView showText:@"章节数据缺失,请删除后重新导入" delay:1.5 inView:[RDUtilities applicationKeyWindow]];
            [self p_endOpening];
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
                [self p_endOpening];
            } else {
                // 章节失效则从第一章重新(p_openFromFirstChapter 内部负责收尾)
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
        [self p_endOpening];
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
