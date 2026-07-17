//
//  RDBookshelfPrefetch.m
//  Reader
//

#import "RDBookshelfPrefetch.h"
#import "RDReadRecordManager.h"
#import "RDBookDetailModel.h"
#import "RDCacheModel.h"
#import "RDFontManager.h"
#import "RDAIConfig.h"
#import "RDVoiceManager.h"
#import <QuartzCore/QuartzCore.h>

NSString * const RDBookshelfPrefetchDidFinishNotification = @"RDBookshelfPrefetchDidFinishNotification";

@implementation RDBookshelfPrefetch

static BOOL s_ready = NO;
static NSArray <RDBookDetailModel *>*s_books = nil;
static NSArray *s_rows = nil;
static NSArray *s_groups = nil;
static BOOL s_running = NO;
static NSMutableArray <dispatch_block_t>*s_waiters = nil;

+ (BOOL)ready { return s_ready; }
+ (NSArray <RDBookDetailModel *>*)books { return s_books; }
+ (NSArray *)dataSourceRows { return s_rows; }
+ (NSArray <NSArray <RDBookDetailModel *>*>*)bookGroups { return s_groups; }

+ (void)invalidate
{
    s_ready = NO;
    s_books = nil;
    s_rows = nil;
    s_groups = nil;
}

+ (void)buildRowsFromBooks:(NSArray <RDBookDetailModel *>*)books
                   columns:(NSInteger)columns
                dataSource:(NSArray * _Nonnull * _Nonnull)outRows
                    groups:(NSArray * _Nonnull * _Nonnull)outGroups
{
    NSInteger cols = MAX(1, columns);
    NSMutableArray *rows = [NSMutableArray array];
    NSMutableArray *groups = [NSMutableArray array];
    if (books.count == 0) {
        [rows addObject:@"RDBookshelfNoneCell"];
    } else {
        NSMutableArray *array = nil;
        for (NSInteger i = 0; i < (NSInteger)books.count; i++) {
            if (i % cols == 0) {
                array = [NSMutableArray array];
                [groups addObject:array];
            }
            [array addObject:books[i]];
        }
        [rows addObjectsFromArray:groups];
    }
    if (outRows) {
        *outRows = rows;
    }
    if (outGroups) {
        *outGroups = groups;
    }
}

+ (void)p_loadIntoCacheColumns:(NSInteger)columns
{
    // 轻量列表:getBookshelfDisplayList 内部会打开 DB,不反序列化章节正文
    NSArray *books = [RDReadRecordManager getBookshelfDisplayList];
    NSArray *rows = nil;
    NSArray *groups = nil;
    [self buildRowsFromBooks:books columns:columns dataSource:&rows groups:&groups];
    s_books = [books copy];
    s_rows = rows;
    s_groups = groups;
    s_ready = YES;
}

+ (void)runWithComplete:(void (^)(void))complete
{
    if (s_ready) {
        if (complete) {
            dispatch_async(dispatch_get_main_queue(), complete);
        }
        return;
    }
    if (s_running) {
        // 已有任务在跑:登记回调,完成时统一在主线程触发,不轮询
        if (complete) {
            @synchronized (self) {
                if (!s_waiters) {
                    s_waiters = [NSMutableArray array];
                }
                [s_waiters addObject:[complete copy]];
            }
        }
        return;
    }
    s_running = YES;
    NSInteger columns = [RDUtilities iPad] ? 5 : 3;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSTimeInterval t0 = CACurrentMediaTime();
        [self p_loadIntoCacheColumns:columns];
        // 并行暖一下:缓存模型 / 字体 / AI 配置(Keychain) / 语音名,减少首次点设置卡顿
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
            (void)[RDCacheModel sharedInstance];
            [[RDFontManager sharedInstance] registerCustomFontsAtLaunch];
            (void)[[RDAIConfigStore sharedInstance] activeProfile];
            (void)[[RDVoiceManager sharedInstance] preferredDisplayName];
        });
        // 启动页至少展示一小段,避免闪一下
        NSTimeInterval elapsed = CACurrentMediaTime() - t0;
        NSTimeInterval minShow = 0.35;
        if (elapsed < minShow) {
            usleep((useconds_t)((minShow - elapsed) * 1e6));
        }
        s_running = NO;
        NSArray <dispatch_block_t>*waiters = nil;
        @synchronized (self) {
            waiters = s_waiters.copy;
            [s_waiters removeAllObjects];
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            [[NSNotificationCenter defaultCenter] postNotificationName:RDBookshelfPrefetchDidFinishNotification object:nil];
            if (complete) {
                complete();
            }
            for (dispatch_block_t waiter in waiters) {
                waiter();
            }
        });
    });
}

+ (void)refreshAsync:(void (^)(void))complete
{
    NSInteger columns = [RDUtilities iPad] ? 5 : 3;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        [self p_loadIntoCacheColumns:columns];
        dispatch_async(dispatch_get_main_queue(), ^{
            [[NSNotificationCenter defaultCenter] postNotificationName:RDBookshelfPrefetchDidFinishNotification object:nil];
            if (complete) {
                complete();
            }
        });
    });
}

+ (void)updateCacheWithBooks:(NSArray <RDBookDetailModel *>*)books columns:(NSInteger)columns
{
    NSArray *rows = nil;
    NSArray *groups = nil;
    [self buildRowsFromBooks:books columns:columns dataSource:&rows groups:&groups];
    s_books = [books copy];
    s_rows = rows;
    s_groups = groups;
    s_ready = YES;
}

@end
