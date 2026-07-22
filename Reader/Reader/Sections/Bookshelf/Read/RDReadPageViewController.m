//
//  RDReadPageViewController.m
//  Reader
//
//  Created by yuenov on 2019/11/21.
//  Copyright © 2019 yuenov. All rights reserved.
//

#import "RDReadPageViewController.h"
#import "RDReadParser.h"
#import "RDReadController.h"
#import "RDCharpterDataManager.h"
#import "RDReadRecordManager.h"
#import "RDCharpterManager.h"
#import "RDMenuView.h"
#import "RDReadCatalogCell.h"
#import "RDReadCatalogView.h"
#import "RDReadProgressView.h"
#import "UINavigationController+FDFullscreenPopGesture.h"
#import "RDReadConfigManager.h"
#import "RDReadSetView.h"
#import "RDCacheModel.h"
#import "RDSpeechManager.h"
#import "RDReadSpeechBar.h"
#import "RDReadTranslateHelper.h"
#import "RDAIClient.h"
#import "RDDisplayBoost.h"
#import "RDShareCardBuilder.h"
#import "RDVoiceManager.h"
#import "RDVoicePickerController.h"
#import "RDBookmarkManager.h"
#import "RDBookmarkModel.h"
#import "RDReadBookmarkView.h"
#import "RDReplaceRule.h"

@implementation UIPageViewController (EnlargeTapRegion)
-(BOOL) gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldReceiveTouch:(UITouch *)touch{
    if ([gestureRecognizer isKindOfClass:[UITapGestureRecognizer class]]) {
        return NO;
    }
    return YES;
}
 
@end


@interface RDReadPageView : UIView
@property (nonatomic,strong) UIView *brightnessView;
@end

@implementation RDReadPageView
-(void)addSubview:(UIView *)view
{
    if (view != self.brightnessView && self.brightnessView) {
        NSInteger index = [self.subviews indexOfObject:self.brightnessView];
        if (index != NSNotFound) {
            [self insertSubview:view atIndex:index];
        }
        else{
            [super addSubview:view];
        }
    }
    else{
        [super addSubview:view];
    }
}
@end

/// 译文缓存存结构化句对+兜底原文/译文,不存已渲染好的富文本——
/// 展示时才按“当前”字号/字体/主题重新渲染,避免改字号后仍显示旧样式(P1-10 之二)。
@interface RDCachedTranslation : NSObject
@property (nonatomic,copy) NSArray <RDTranslatePair *>*pairs;
@property (nonatomic,copy) NSString *fallbackSource;
@property (nonatomic,copy) NSString *fallbackTranslation;
@end
@implementation RDCachedTranslation
@end

@interface RDReadPageViewController ()<UIPageViewControllerDelegate,UIPageViewControllerDataSource,RDMenuViewDelegate,RDReadControllerDelegate,RDSpeechManagerDelegate>
@property (nonatomic,strong) RDReadSpeechBar *speechBar;
@property (nonatomic,strong) UIPageViewController *pageViewController;

@property (nonatomic,strong) NSArray <RDCharpterModel *>*charpters;    //简短的章节信息，不包含内容
@property (nonatomic,strong) UIView *brightnessView;

@property (nonatomic,assign) BOOL isShowStatusBar;
@property (nonatomic,strong) RDMenuView *menuView;

/// 后台翻译会话:关闭显示后仍继续预译缓存
@property (nonatomic,assign) BOOL translateBackgroundEnabled;
/// 是否在正文区展示译文
@property (nonatomic,assign) BOOL translateDisplayEnabled;
/// 译文缓存 key=bookId_chapterId_原文内容哈希(不再用页码,重新分页后同页码可能是不同原文);
/// 值为结构化句对,NSCache 限量,长会话内存有界
@property (nonatomic,strong) NSCache <NSString *, RDCachedTranslation *>*translateCache;
/// 正在后台请求中的 key,防重复打;同时充当在途并发上限
@property (nonatomic,strong) NSMutableSet <NSString *>*translatePendingKeys;
/// 后台分页代次:快速改字号时丢弃过期结果
@property (nonatomic,assign) NSUInteger paginateGeneration;
/// 每阅读器串行分页队列:避免多章/多次改字号并行 CoreText(P2-FE-02)
@property (nonatomic,strong) dispatch_queue_t paginateQueue;
/// 邻章预分页缓存:key=bookId_chapterId_typo_rules → @{content, pages}(P1-FE-01)
@property (nonatomic,strong) NSMutableDictionary <NSString *, NSDictionary *>*neighborPageCache;
@property (nonatomic,strong) NSMutableSet <NSString *>*neighborPagePending;
@end

@implementation RDReadPageViewController

-(void)loadView
{
    UIView *view = [[RDReadPageView alloc] initWithFrame:[UIScreen mainScreen].bounds];
    self.view = view;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [RDCacheModel sharedInstance].book = self.bookDetail;
    [[RDCacheModel sharedInstance] archive];
    self.fd_interactivePopDisabled = YES;
    self.paginateQueue = dispatch_queue_create("com.reader.read.paginate", DISPATCH_QUEUE_SERIAL);
    self.neighborPageCache = [NSMutableDictionary dictionary];
    self.neighborPagePending = [NSMutableSet set];
    // 正确 containment: addChild → 触达 view 装入 → didMove(Phase 3 / P2-02)
    [self addChildViewController:self.pageViewController];
    [self.pageViewController didMoveToParentViewController:self];
    self.charpters = [RDCharpterDataManager getBriefCharptersWithBookId:self.bookDetail.bookId];
    [self initSteup];
    
    

        
    RDReadPageView *view = (RDReadPageView *)self.view;
    view.brightnessView = self.brightnessView;
    
    [self.view addSubview:self.brightnessView];
    
    
    //亮度
    [self.KVOController observe:[RDReadConfigManager sharedInstance] keyPath:@"brightness" options:NSKeyValueObservingOptionNew block:^(RDReadPageViewController*  observer, RDReadConfigManager  * object, NSDictionary<NSString *,id> * _Nonnull change) {
        observer.brightnessView.alpha = kConfigMaxBrightnessValue - object.brightness;
    }];
    //字体(字号与字体名变化都重新分页) — 用 charOffset 记忆位置,避免页码漂移
    [self.KVOController observe:[RDReadConfigManager sharedInstance] keyPaths:@[@"fontSize",@"fontName"] options:NSKeyValueObservingOptionNew block:^(RDReadPageViewController*  observer, RDReadConfigManager  * object, NSDictionary<NSString *,id> * _Nonnull change) {
        [observer p_saveRecord];
        NSUInteger gen = [observer p_bumpPaginateGeneration];
        [observer p_paginateContent:observer.bookDetail.charpterModel.content
                           charpter:observer.bookDetail.charpterModel.name
                         generation:gen
                           complete:^(NSAttributedString *content, NSArray *pages) {
            if (gen != observer.paginateGeneration) {
                return;
            }
            NSInteger page = [observer p_pageForOffset:observer.bookDetail.charOffset pages:pages];
            observer.bookDetail.page = page;
            [observer.pageViewController setViewControllers:@[[observer p_creatReadController:observer.bookDetail.charpterModel.name content:[observer p_getCurPageContentWithContent:content page:page pages:pages] page:page totalPage:pages.count charpterIndex:[observer p_getCurCharpter] totalCharpter:observer.charpters.count charpterModel:observer.bookDetail.charpterModel charpterContent:content pages:pages]] direction:UIPageViewControllerNavigationDirectionForward animated:NO completion:nil];
            [observer p_prefetchNeighborChapters];
        }];
    }];
    
    // 退到后台时也落盘进度
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(p_saveRecord) name:UIApplicationWillResignActiveNotification object:nil];
}

- (void)viewWillDisappear:(BOOL)animated
{
    [super viewWillDisappear:animated];
    [self p_saveRecord];
}


-(UIView *)brightnessView
{
    if (!_brightnessView) {
        _brightnessView = [[UIView alloc] initWithFrame:[UIScreen mainScreen].bounds];
        _brightnessView.backgroundColor = [UIColor blackColor];
        _brightnessView.alpha = kConfigMaxBrightnessValue - [RDReadConfigManager sharedInstance].brightness;
        _brightnessView.userInteractionEnabled = NO;
    }
    return _brightnessView;
}
-(BOOL)prefersStatusBarHidden
{
    return !_isShowStatusBar;
}



-(void)nextPage:(RDReadController *)controller
{
    if (self.pageViewController.transitionStyle == UIPageViewControllerTransitionStylePageCurl) {
        [self p_setAfterOrBeforeViewControllerWithBefore:NO mirror:YES];
    }
    else{
        [self p_setAfterOrBeforeViewControllerWithBefore:NO];
    }
    
    [self p_saveRecord];
    // 点击/滑动翻页(非 curl 动画回调)也要自动译
    [self p_applyTranslateModeIfNeeded];
}
-(void)lastPage:(RDReadController *)controller
{
    if (self.pageViewController.transitionStyle == UIPageViewControllerTransitionStylePageCurl){
        [self p_setAfterOrBeforeViewControllerWithBefore:YES mirror:YES];
    }
    else{
        [self p_setAfterOrBeforeViewControllerWithBefore:YES];
    }
    [self p_saveRecord];
    [self p_applyTranslateModeIfNeeded];
}
-(void)invokeMenu:(RDReadController *)controller
{
    if (self.menuView.superview) {
        _isShowStatusBar = NO;
        [self setNeedsStatusBarAppearanceUpdate];
        [self.menuView dismiss];
    }
    else{
        _isShowStatusBar = YES;
        [self setNeedsStatusBarAppearanceUpdate];
        self.menuView = [[RDMenuView alloc] init];
        self.menuView.delegate = self;
        self.menuView.charpters = self.charpters;
        self.menuView.book = self.bookDetail;
        [self.menuView showInView:self.view];
    }
}

/// 每次推进代次时清空邻章缓存/pending,避免取消后的 key 永久卡住(Round 3 Issue 1)
- (NSUInteger)p_bumpPaginateGeneration
{
    NSUInteger gen = ++self.paginateGeneration;
    [self.neighborPageCache removeAllObjects];
    [self.neighborPagePending removeAllObjects];
    return gen;
}

-(void)initSteup{
    // 优先用 charOffset 恢复(字体变化后仍准),否则用 page
    // 后台分页:不截断正文,避免主线程 watchdog(P1-03)
    // TOC/进度/书签跳转也会进这里:必须清邻章 pending,否则跨章永远 skip(Issue 1)
    NSUInteger gen = [self p_bumpPaginateGeneration];
    [self p_paginateContent:self.bookDetail.charpterModel.content
                   charpter:self.bookDetail.charpterModel.name
                 generation:gen
                   complete:^(NSAttributedString *content, NSArray *pages) {
        if (gen != self.paginateGeneration) {
            return;
        }
        NSInteger page = self.bookDetail.charOffset > 0
            ? [self p_pageForOffset:self.bookDetail.charOffset pages:pages]
            : [self p_safePage:self.bookDetail.page totalPages:pages.count];
        self.bookDetail.page = page;
        [self.pageViewController setViewControllers:@[[self p_creatReadController:self.bookDetail.charpterModel.name content:[self p_getCurPageContentWithContent:content page:page pages:pages] page:page totalPage:pages.count charpterIndex:[self p_getCurCharpter] totalCharpter:self.charpters.count charpterModel:self.bookDetail.charpterModel charpterContent:content pages:pages]] direction:UIPageViewControllerNavigationDirectionForward animated:NO completion:nil];
        // 翻译模式跨章节/重建后继续
        [self p_applyTranslateModeIfNeeded];
        [self p_prefetchNeighborChapters];
    }];
    //默认加载上一章或下一章的数据
    [self p_downloads];
}

/// 阅读器私有串行队列 + generation cancel(P2-FE-02)
- (void)p_paginateContent:(NSString *)content
                 charpter:(NSString *)charpter
               generation:(NSUInteger)gen
                 complete:(void(^)(NSAttributedString *content, NSArray *pages))complete
{
    __weak typeof(self) weakSelf = self;
    CGRect bounds = CGRectMake(0, 0, ScreenWidth - kLeftMargin - kRightMargin, ScreenHeight - kTopMargin - kBottomMargin);
    [RDReadParser paginateWithContent:content
                             charpter:charpter
                               bounds:bounds
                                queue:self.paginateQueue
                        allowTruncate:NO
                          cancelCheck:^BOOL{
        __strong typeof(weakSelf) self = weakSelf;
        return !self || gen != self.paginateGeneration;
    } complete:complete];
}

- (NSString *)p_neighborCacheKeyForChapterId:(NSInteger)chapterId
{
    RDReadConfigManager *cfg = [RDReadConfigManager sharedInstance];
    // 字号/字体变化后 key 失效;规则条数变化也失效(轻量版本信号)
    NSUInteger rulesVersion = [RDReplaceRuleStore sharedInstance].rules.count;
    return [NSString stringWithFormat:@"%ld_%ld_%.1f_%@_%lu",
            (long)self.bookDetail.bookId, (long)chapterId, cfg.fontSize,
            cfg.fontName ?: @"", (unsigned long)rulesVersion];
}

/// 跨章缓存未就绪:后台分页(不截断),完成后若仍在章边界则自动翻页(Issue 3/6)
- (void)p_requestNeighborPaginationBefore:(BOOL)before
                               charpterId:(NSInteger)charpterId
                            existingModel:(RDCharpterModel *)existingModel
                                direction:(UIPageViewControllerNavigationDirection)direction
                                  animate:(BOOL)animate
                        currentController:(RDReadController *)currentController
{
    NSString *cacheKey = [self p_neighborCacheKeyForChapterId:charpterId];
    if ([self.neighborPagePending containsObject:cacheKey]) {
        // 已在路上:轻量提示,避免用户以为手势坏了(Issue 6)
        [RDToastView showText:@"正在排版下一章…" delay:0.8 inView:self.view];
        return;
    }
    [self.neighborPagePending addObject:cacheKey];
    [RDToastView showText:@"正在排版下一章…" delay:0.8 inView:self.view];
    NSUInteger gen = self.paginateGeneration;
    __weak typeof(self) weakSelf = self;
    void (^afterModel)(RDCharpterModel *) = ^(RDCharpterModel *model) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self || gen != self.paginateGeneration || model.content.length == 0) {
            [self.neighborPagePending removeObject:cacheKey];
            return;
        }
        [self p_paginateContent:model.content charpter:model.name generation:gen complete:^(NSAttributedString *content, NSArray *pages) {
            __strong typeof(weakSelf) self2 = weakSelf;
            // 无论 gen 是否匹配都摘掉 pending,避免取消/换代后 key 永久卡住(Issue 1)
            [self2.neighborPagePending removeObject:cacheKey];
            if (!self2 || gen != self2.paginateGeneration) {
                return;
            }
            if (!content || !pages.count) {
                return;
            }
            self2.neighborPageCache[cacheKey] = @{@"content": content, @"pages": pages, @"model": model};
            // 仍停在章边界时自动切入邻章(generation 守卫)
            RDReadController *cur = (RDReadController *)self2.pageViewController.viewControllers.firstObject;
            if (!cur) {
                return;
            }
            BOOL stillOnEdge = before ? (cur.page == 0) : (cur.page == (NSInteger)cur.pages.count - 1);
            if (!stillOnEdge) {
                return;
            }
            NSInteger targetPage = before ? MAX(0, (NSInteger)pages.count - 1) : 0;
            NSInteger chapterIndex = [self2.charpters indexOfObject:model];
            if (chapterIndex == NSNotFound) {
                chapterIndex = before ? cur.charpterIndex - 1 : cur.charpterIndex + 1;
            }
            RDReadController *next = [self2 p_creatReadController:model.name
                                                          content:[self2 p_getCurPageContentWithContent:content page:targetPage pages:pages]
                                                             page:targetPage
                                                        totalPage:pages.count
                                                    charpterIndex:chapterIndex
                                                    totalCharpter:self2.charpters.count
                                                    charpterModel:model
                                                  charpterContent:content
                                                            pages:pages
                                                           mirror:NO];
            BOOL realCurl = ([RDReadConfigManager sharedInstance].pageType == RDRealTypePage);
            if (realCurl) {
                if (before) {
                    RDReadController *mirrorCtrl = [self2 p_creatReadController:model.name content:next.content page:targetPage totalPage:pages.count charpterIndex:chapterIndex totalCharpter:self2.charpters.count charpterModel:model charpterContent:content pages:pages mirror:YES];
                    [self2.pageViewController setViewControllers:@[next, mirrorCtrl] direction:direction animated:animate completion:nil];
                } else {
                    RDReadController *mirrorCtrl = [self2 p_creatReadController:cur.charpter content:cur.content page:cur.page totalPage:cur.totalPage charpterIndex:cur.charpterIndex totalCharpter:cur.totalCharpter charpterModel:cur.charpterModel charpterContent:cur.charpterContent pages:cur.pages mirror:YES];
                    [self2.pageViewController setViewControllers:@[next, mirrorCtrl] direction:direction animated:animate completion:nil];
                }
            } else {
                [self2.pageViewController setViewControllers:@[next] direction:direction animated:animate completion:nil];
            }
            [self2 p_saveRecord];
            [self2 p_prefetchNeighborChapters];
        }];
    };
    if (existingModel.content.length > 0) {
        afterModel(existingModel);
    } else {
        [RDCharpterManager getCharpterWithBookId:self.bookDetail.bookId charpterId:charpterId complete:^(BOOL success, RDCharpterModel *model) {
            if (success && model) {
                afterModel(model);
            } else {
                __strong typeof(weakSelf) self = weakSelf;
                [self.neighborPagePending removeObject:cacheKey];
            }
        }];
    }
}

/// 当前章展示后预分页前后各一章,dataSource 只消费缓存(P1-FE-01)
- (void)p_prefetchNeighborChapters
{
    NSInteger idx = [self.charpters indexOfObject:self.bookDetail.charpterModel];
    if (idx == NSNotFound) {
        idx = [self p_getCurCharpter];
    }
    NSMutableArray <NSNumber *>*targets = [NSMutableArray array];
    if (idx > 0) {
        [targets addObject:@(self.charpters[idx - 1].charpterId)];
    }
    if (idx >= 0 && idx + 1 < (NSInteger)self.charpters.count) {
        [targets addObject:@(self.charpters[idx + 1].charpterId)];
    }
    NSUInteger gen = self.paginateGeneration;
    for (NSNumber *cidNum in targets) {
        NSInteger chapterId = cidNum.integerValue;
        NSString *key = [self p_neighborCacheKeyForChapterId:chapterId];
        if (self.neighborPageCache[key] || [self.neighborPagePending containsObject:key]) {
            continue;
        }
        RDCharpterModel *model = [RDCharpterDataManager getCharpterWithBookId:self.bookDetail.bookId charpterId:chapterId];
        if (model.content.length == 0) {
            continue;
        }
        [self.neighborPagePending addObject:key];
        __weak typeof(self) weakSelf = self;
        [self p_paginateContent:model.content charpter:model.name generation:gen complete:^(NSAttributedString *content, NSArray *pages) {
            __strong typeof(weakSelf) self = weakSelf;
            // gen 失配时也必须 remove pending(Issue 1)
            [self.neighborPagePending removeObject:key];
            if (!self || gen != self.paginateGeneration) {
                return;
            }
            if (content && pages) {
                self.neighborPageCache[key] = @{@"content": content, @"pages": pages, @"model": model};
            }
        }];
    }
}

-(void)p_downloads{
    NSInteger index = [self.charpters indexOfObject:self.bookDetail.charpterModel];
    NSMutableArray *charpters = [NSMutableArray array];
    if (index == 0) {
        //第一页
        if (self.charpters.count>2) {
            RDCharpterModel *model1 = self.charpters[1];
            RDCharpterModel *model2 = self.charpters[2];
            [charpters addObjectsFromArray:@[@(model1.charpterId),@(model2.charpterId)]];
        }
    }
    else if (index == self.charpters.count-1){
        //最后一页
        if (self.charpters.count>2) {
            RDCharpterModel *model1 = self.charpters[index-2];
            RDCharpterModel *model2 = self.charpters[index-1];
            [charpters addObjectsFromArray:@[@(model1.charpterId),@(model2.charpterId)]];
        }
    }
    else{
        //中间页
        RDCharpterModel *model1 = self.charpters[index-1];
        RDCharpterModel *model2 = self.charpters[index+1];
        [charpters addObjectsFromArray:@[@(model1.charpterId),@(model2.charpterId)]];
    }
    [RDCharpterManager slientDownWithBookId:self.bookDetail.bookId charpterIds:charpters.copy];
}

-(void)p_saveRecord
{
    NSInteger charpterId = self.bookDetail.charpterModel.charpterId;
    
    RDReadController *readController = self.pageViewController.viewControllers.firstObject;
    if (!readController || readController.isMirror) {
        // 仿真翻页可能拿到镜像页,取非镜像
        for (UIViewController *vc in self.pageViewController.viewControllers) {
            if ([vc isKindOfClass:RDReadController.class] && ![(RDReadController *)vc isMirror]) {
                readController = (RDReadController *)vc;
                break;
            }
        }
    }
    if (!readController) {
        return;
    }
    self.bookDetail.charpterModel = readController.charpterModel;
    self.bookDetail.page = readController.page;
    // 字符偏移:字体/排版变化后仍可恢复到附近位置
    NSInteger offset = 0;
    if (readController.pages.count > 0) {
        NSInteger page = [self p_safePage:readController.page totalPages:readController.pages.count];
        offset = [readController.pages[page] integerValue];
    }
    self.bookDetail.charOffset = offset;
    // 高频调用:只按列更新进度(章节引用不含正文),不整行回写、不再写 history 表
    [RDReadRecordManager updateProgressWithModel:self.bookDetail];

    if (charpterId != self.bookDetail.charpterModel.charpterId && self.bookDetail.page == 0) {
        //新的一章
        [self p_downloads];
    }
}

/// 根据 charOffset 在 pages 中定位页码
-(NSInteger)p_pageForOffset:(NSInteger)offset pages:(NSArray *)pages
{
    if (pages.count == 0) {
        return 0;
    }
    if (offset <= 0) {
        return 0;
    }
    NSInteger best = 0;
    for (NSInteger i = 0; i < (NSInteger)pages.count; i++) {
        NSInteger loc = [pages[i] integerValue];
        if (loc <= offset) {
            best = i;
        } else {
            break;
        }
    }
    return [self p_safePage:best totalPages:pages.count];
}

-(RDReadController *)p_creatReadController:(NSString *)charpter content:(NSAttributedString *)content page:(NSInteger)page totalPage:(NSInteger)totalPage charpterIndex:(NSInteger)index totalCharpter:(NSInteger)total charpterModel:(RDCharpterModel *)charpterModel charpterContent:(NSAttributedString *)charpterContent pages:(NSArray *)pages;
{
    return [self p_creatReadController:charpter content:content page:page totalPage:totalPage charpterIndex:index totalCharpter:total charpterModel:charpterModel charpterContent:charpterContent pages:pages mirror:NO];
}

-(RDReadController *)p_creatReadController:(NSString *)charpter content:(NSAttributedString *)content page:(NSInteger)page totalPage:(NSInteger)totalPage charpterIndex:(NSInteger)index totalCharpter:(NSInteger)total charpterModel:(RDCharpterModel *)charpterModel charpterContent:(NSAttributedString *)charpterContent pages:(NSArray *)pages mirror:(BOOL)mirror
{
    RDReadController *readController = [[RDReadController alloc] init];
    readController.mirror = mirror;
    [readController setCharpter:charpter content:content page:page totalPage:totalPage charpterIndex:index totalCharpter:total];
    readController.charpterContent = charpterContent;
    readController.charpterModel = charpterModel;
    readController.pages = pages;
    readController.delegate = self;
    return readController;
}


-(NSInteger)p_safePage:(NSInteger)page totalPages:(NSInteger)pages
{
    if (page<0) {
        page = 0;
    }
    if (page>= pages) {
        page = pages-1;
    }
    return page;
}

-(NSAttributedString *)p_getCurPageContentWithContent:(NSAttributedString *)conetnt page:(NSInteger)page pages:(NSArray *)pages
{
//    if (page>0) {
//        NSAttributedString *last = [self p_subGetCurPageContentWithContent:conetnt page:page-1 pages:pages];
//
//        NSAttributedString *current = [self p_subGetCurPageContentWithContent:conetnt page:page pages:pages];
//
//        if (![[last.string substringFromIndex:last.string.length-1] isEqualToString:@"\n"]) {
//            //最后一个字符不是换行，下一页首行不缩进
//            NSMutableAttributedString *muCurrent = [[NSMutableAttributedString alloc] initWithAttributedString:current];
//            NSDictionary *attr = [RDReadParser paraserFontArrribute:[RDReadConfigManager sharedInstance]];
//            NSMutableDictionary *muAttr = attr.mutableCopy;
//            NSMutableParagraphStyle *para = muAttr[NSParagraphStyleAttributeName];
//            para.firstLineHeadIndent = 0;
//            [muCurrent setAttributes:muAttr range:NSMakeRange(0, 1)];
//            return muCurrent.copy;
//        }
//        return current;
//
//    }
//    else{
//        return [self p_subGetCurPageContentWithContent:conetnt page:page pages:pages];
//    }
    return [self p_subGetCurPageContentWithContent:conetnt page:page pages:pages];
}

-(NSAttributedString *)p_subGetCurPageContentWithContent:(NSAttributedString *)conetnt page:(NSInteger)page pages:(NSArray *)pages
{
    NSInteger index = page;
    NSInteger loc = [pages[index] integerValue];
    NSInteger len = 0;
    if (index<pages.count-1) {
        len = [pages[index+1] integerValue] - loc;
    }
    else{
        len = conetnt.length - loc;
    }
    return [conetnt attributedSubstringFromRange:NSMakeRange(loc, len)];

}



//当前章节索引
-(NSInteger)p_getCurCharpter
{
    return [self.charpters indexOfObject:self.bookDetail.charpterModel];
}

-(UIPageViewController *)pageViewController
{
    if (!_pageViewController) {
        RDPageType pageType = [RDReadConfigManager sharedInstance].pageType;
        UIPageViewControllerTransitionStyle style;
        switch (pageType) {
            case RDRealTypePage:
                style = UIPageViewControllerTransitionStylePageCurl;
                break;
            default:
                style = UIPageViewControllerTransitionStyleScroll;
                break;
        }
        // 滑动翻页: inter-page spacing 0,全屏页,配合 ProMotion 更顺
        NSDictionary *options = nil;
        if (style == UIPageViewControllerTransitionStyleScroll) {
            options = @{UIPageViewControllerOptionInterPageSpacingKey: @0};
        }
        _pageViewController = [[UIPageViewController alloc] initWithTransitionStyle:style
                                                              navigationOrientation:UIPageViewControllerNavigationOrientationHorizontal
                                                                            options:options];
        _pageViewController.delegate = self;
        if (pageType != RDNoneTypePage) {
            _pageViewController.dataSource = self;
            _pageViewController.doubleSided = (style == UIPageViewControllerTransitionStylePageCurl);
        }
        [self.view addSubview:_pageViewController.view];
        // ProMotion:配置内嵌 ScrollView,关闭栅格化
        [RDDisplayBoost applyToPageViewController:_pageViewController];
    }
    return _pageViewController;
}

#pragma mark - UIPageViewContrillerDelegate
- (void)pageViewController:(UIPageViewController *)pageViewController didFinishAnimating:(BOOL)finished previousViewControllers:(NSArray *)previousViewControllers transitionCompleted:(BOOL)completed
{
    if (completed) {
        [self p_saveRecord];
        [self p_applyTranslateModeIfNeeded];
    }
}

#pragma mark - UIPageViewControllerDataSource
- (nullable UIViewController *)pageViewController:(UIPageViewController *)pageViewController viewControllerBeforeViewController:(UIViewController *)viewController
{
    if (self.pageViewController.transitionStyle == UIPageViewControllerTransitionStylePageCurl) {
        RDReadController *currentController = (RDReadController *)viewController;
        if (!currentController.mirror) {
            RDReadController *mirrorController = (RDReadController *)[self p_afterOrBeforeWithViewController:viewController before:YES mirror:YES];
            return mirrorController;
        }
        return [self p_creatReadController:currentController.charpter content:currentController.content page:currentController.page totalPage:currentController.totalPage charpterIndex:currentController.charpterIndex totalCharpter:currentController.totalCharpter charpterModel:currentController.charpterModel charpterContent:currentController.charpterContent pages:currentController.pages mirror:NO];
    }
    return [self p_afterOrBeforeWithViewController:viewController before:YES];
}
- (nullable UIViewController *)pageViewController:(UIPageViewController *)pageViewController viewControllerAfterViewController:(UIViewController *)viewController
{
    if (self.pageViewController.transitionStyle == UIPageViewControllerTransitionStylePageCurl) {
        RDReadController *currentController = (RDReadController *)viewController;
        if (!currentController.mirror) {
            return [self p_creatReadController:currentController.charpter content:currentController.content page:currentController.page totalPage:currentController.totalPage charpterIndex:currentController.charpterIndex totalCharpter:currentController.totalCharpter charpterModel:currentController.charpterModel charpterContent:currentController.charpterContent pages:currentController.pages mirror:YES];
        }
    }
   return [self p_afterOrBeforeWithViewController:viewController before:NO];
    
}

/// 返回前一个或者后一个控制器
/// @param controller 当前控制区内
/// @param before 是否是前一个控制器
-(UIViewController *)p_afterOrBeforeWithViewController:(UIViewController *)controller before:(BOOL)before
{
    return [self p_afterOrBeforeWithViewController:controller before:before mirror:NO];

}
-(UIViewController *)p_afterOrBeforeWithViewController:(UIViewController *)controller before:(BOOL)before mirror:(BOOL)mirror
{
    RDReadController *currentController = (RDReadController *)controller;
    NSInteger page = currentController.page;   //当前页数
    NSInteger charpter = currentController.charpterIndex; //当前章节
    RDCharpterModel *charpterModel = currentController.charpterModel;   //当前章节信息
    NSAttributedString *charpterContent = currentController.charpterContent;    //当前章节内容
    NSArray *pages = currentController.pages;       //分页信息数组
    
    
    UIPageViewControllerNavigationDirection direction;
    if (before) {
        direction = UIPageViewControllerNavigationDirectionReverse;
    }
    else{
        direction = UIPageViewControllerNavigationDirectionForward;
    }
    
    BOOL animate;
    if ([RDReadConfigManager sharedInstance].pageType == RDNoneTypePage) {
        animate = NO;
    }
    else{
        animate = YES;
    }
    
    if (before) {
        if (page == 0 && charpter == 0) {
           //第一章，第一页，不用做任何处理
            return nil;
        }
    }
    else{
        if (page == pages.count-1 && charpter == self.charpters.count-1) {
            //最后一张最后一页，不用做任何处理
            return nil;
        }
    }
    if ((before && (page == 0)) || (!before && (page == pages.count-1) )) {
        //上一章的数据 或者下一章的数据
        NSInteger charpterId;
        if (before) {
            charpterId = self.charpters[charpter-1].charpterId;
        }
        else{
            charpterId = self.charpters[charpter+1].charpterId;
        }
        
        RDCharpterModel *otherCharpterModel = [RDCharpterDataManager getCharpterWithBookId:self.bookDetail.bookId charpterId:charpterId];
        // 邻章:统一走缓存 / 后台分页,禁止同步截断路径(Issue 3 / P1-FE-01)
        NSString *cacheKey = [self p_neighborCacheKeyForChapterId:charpterId];
        NSDictionary *cached = self.neighborPageCache[cacheKey];
        if (cached[@"content"] && cached[@"pages"]) {
            NSAttributedString *content = cached[@"content"];
            NSArray *cachedPages = cached[@"pages"];
            RDCharpterModel *model = cached[@"model"] ?: otherCharpterModel;
            NSInteger targetPage = before ? MAX(0, (NSInteger)cachedPages.count - 1) : 0;
            NSInteger chapterIndex = [self.charpters indexOfObject:model];
            if (chapterIndex == NSNotFound) {
                chapterIndex = before ? charpter - 1 : charpter + 1;
            }
            return [self p_creatReadController:model.name
                                       content:[self p_getCurPageContentWithContent:content page:targetPage pages:cachedPages]
                                          page:targetPage
                                     totalPage:cachedPages.count
                                 charpterIndex:chapterIndex
                                 totalCharpter:self.charpters.count
                                 charpterModel:model
                               charpterContent:content
                                         pages:cachedPages
                                        mirror:mirror];
        }
        // 缓存未就绪:触发后台分页(含正文缺失时的拉取),返回 nil 阻止跨章动画
        [self p_requestNeighborPaginationBefore:before
                                     charpterId:charpterId
                                  existingModel:otherCharpterModel
                                      direction:direction
                                        animate:animate
                            currentController:currentController];
        return nil;
        

    }
    else{
        RDReadController *readController = [self p_creatReadController:charpterModel.name content:[self p_getCurPageContentWithContent:charpterContent page:before?page-1:page+1 pages:pages] page:before?page-1:page+1 totalPage:pages.count charpterIndex:charpter totalCharpter:self.charpters.count charpterModel:charpterModel charpterContent:charpterContent pages:pages mirror:mirror];
        return readController;
        
    }
}

-(void)p_setAfterOrBeforeViewControllerWithBefore:(BOOL)before
{
    [self p_setAfterOrBeforeViewControllerWithBefore:before mirror:NO];
}

/// 菜单/手势主动翻页:复用 dataSource 的 p_afterOrBefore 建页,再 setViewControllers。
/// 仿真卷页 mirror 对仍保留 curl 双页布局(Phase 3 双胞胎收敛)。
-(void)p_setAfterOrBeforeViewControllerWithBefore:(BOOL)before mirror:(BOOL)mirror
{
    RDReadController *currentController = (RDReadController *)_pageViewController.viewControllers.firstObject;
    if (!currentController) {
        return;
    }
    UIPageViewControllerNavigationDirection direction = before
        ? UIPageViewControllerNavigationDirectionReverse
        : UIPageViewControllerNavigationDirectionForward;
    BOOL animate = [RDReadConfigManager sharedInstance].pageType != RDNoneTypePage;
    BOOL realCurl = ([RDReadConfigManager sharedInstance].pageType == RDRealTypePage) && mirror;

    // 章内翻页 / 已有正文的邻章:afterOrBefore 同步建页
    // 正文缺失的邻章:afterOrBefore 内部异步拉取并自行 setViewControllers
    UIViewController *next = [self p_afterOrBeforeWithViewController:currentController before:before mirror:NO];
    if (!next) {
        // 边界或异步加载中
        return;
    }
    RDReadController *primary = (RDReadController *)next;
    if (realCurl) {
        if (before) {
            RDReadController *mirrorCtrl = [self p_creatReadController:primary.charpter content:primary.content page:primary.page totalPage:primary.totalPage charpterIndex:primary.charpterIndex totalCharpter:primary.totalCharpter charpterModel:primary.charpterModel charpterContent:primary.charpterContent pages:primary.pages mirror:YES];
            [self.pageViewController setViewControllers:@[primary, mirrorCtrl] direction:direction animated:animate completion:nil];
        } else {
            RDReadController *mirrorCtrl = [self p_creatReadController:currentController.charpter content:currentController.content page:currentController.page totalPage:currentController.totalPage charpterIndex:currentController.charpterIndex totalCharpter:currentController.totalCharpter charpterModel:currentController.charpterModel charpterContent:currentController.charpterContent pages:currentController.pages mirror:YES];
            [self.pageViewController setViewControllers:@[primary, mirrorCtrl] direction:direction animated:animate completion:nil];
        }
    } else {
        [self.pageViewController setViewControllers:@[primary] direction:direction animated:animate completion:nil];
    }
    [self p_saveRecord];
}
-(void)reload{
    
    RDReadController *currentController = (RDReadController *)_pageViewController.viewControllers.firstObject;
    NSInteger charpter = currentController.charpterIndex; //当前章节
    NSAttributedString *charpterContent = currentController.charpterContent;    //当前章节内容
    NSArray *pages = currentController.pages;       //分页信息数组
    [self.pageViewController setViewControllers:@[[self p_creatReadController:self.bookDetail.charpterModel.name content:[self p_getCurPageContentWithContent:charpterContent page:self.bookDetail.page pages:pages] page:[self p_safePage:self.bookDetail.page totalPages:pages.count] totalPage:pages.count charpterIndex:charpter totalCharpter:self.charpters.count charpterModel:self.bookDetail.charpterModel charpterContent:charpterContent pages:pages]] direction:UIPageViewControllerNavigationDirectionForward animated:NO completion:nil];
}

#pragma mark - Delegate
//选择章节
-(void)didSelectCharpter:(RDCharpterModel *)charpter
{
    [self invokeMenu:self.pageViewController.viewControllers.firstObject];
    [RDCharpterManager getCharpterWithBookId:self.bookDetail.bookId charpterId:charpter.charpterId complete:^(BOOL success,RDCharpterModel * _Nonnull model) {
        if (success) {
            self.bookDetail.charpterModel = model;
            self.bookDetail.page = 0;
            // charOffset 必须同步清零,否则 initSteup 会按旧偏移定位到新章节的错误页
            self.bookDetail.charOffset = 0;
            if (![RDReadRecordManager updateProgressWithModel:self.bookDetail]) {
                [RDToastView showText:@"进度保存失败" delay:1.2 inView:self.view];
            }
            [self initSteup];
        }

    }];

}
//滑动到某个章节
-(void)sliderToCharpter:(RDCharpterModel *)charpter
{
    [RDCharpterManager getCharpterWithBookId:self.bookDetail.bookId charpterId:charpter.charpterId complete:^(BOOL success,RDCharpterModel * _Nonnull model) {
        if (success) {
            self.bookDetail.charpterModel = model;
            self.bookDetail.page = 0;
            self.bookDetail.charOffset = 0;
            if (![RDReadRecordManager updateProgressWithModel:self.bookDetail]) {
                [RDToastView showText:@"进度保存失败" delay:1.2 inView:self.view];
            }
            [self initSteup];
        }

    }];

}
//返回
-(void)backAction
{
    [self p_stopTranslateBackground];
    // 退出阅读:停听书、存进度、清自动续读缓存(业务收敛在这里,dealloc 只做纯清理)
    if ([RDSpeechManager sharedInstance].active) {
        [RDSpeechManager sharedInstance].delegate = nil;
        [[RDSpeechManager sharedInstance] stop];
    }
    [self p_saveRecord];
    [RDCacheModel sharedInstance].book = nil;
    [[RDCacheModel sharedInstance] archive];
    [self.navigationController popViewControllerAnimated:YES];
}

#pragma mark - AI 翻译

// 在途 LLM 请求上限:当前页 + 前后预取,超出丢弃(翻页停下后会重新补)
static const NSUInteger kTranslateMaxInflight = 3;

- (NSCache <NSString *, RDCachedTranslation *>*)translateCache
{
    if (!_translateCache) {
        _translateCache = [[NSCache alloc] init];
        _translateCache.countLimit = 60;
    }
    return _translateCache;
}

- (NSMutableSet <NSString *>*)translatePendingKeys
{
    if (!_translatePendingKeys) {
        _translatePendingKeys = [NSMutableSet set];
    }
    return _translatePendingKeys;
}

- (RDReadController *)p_currentReadController
{
    RDReadController *current = (RDReadController *)self.pageViewController.viewControllers.firstObject;
    if ([current isKindOfClass:RDReadController.class] && !current.isMirror) {
        return current;
    }
    for (UIViewController *vc in self.pageViewController.viewControllers) {
        if ([vc isKindOfClass:RDReadController.class] && ![(RDReadController *)vc isMirror]) {
            return (RDReadController *)vc;
        }
    }
    return [current isKindOfClass:RDReadController.class] ? current : nil;
}

// djb2 变体,足够区分不同原文,不追求密码学强度
static NSUInteger RDReadTranslateTextHash(NSString *text) {
    NSUInteger hash = 5381;
    NSUInteger length = text.length;
    for (NSUInteger i = 0; i < length; i++) {
        hash = ((hash << 5) + hash) + [text characterAtIndex:i];
    }
    return hash;
}

/// 按"原文内容"而非页码建 key:重新分页(改字号/字体后)同一页码可能对应不同原文,
/// 用页码做 key 会让旧译文错配到新原文上(P1-10)。
- (NSString *)p_translateKeyForBook:(NSInteger)bookId chapter:(NSInteger)cid text:(NSString *)text
{
    return [NSString stringWithFormat:@"%ld_%ld_%lu", (long)bookId, (long)cid, (unsigned long)RDReadTranslateTextHash(text ?: @"")];
}

- (NSString *)p_translateKeyForController:(RDReadController *)c
{
    if (!c || c.content.string.length == 0) {
        return @"";
    }
    return [self p_translateKeyForBook:self.bookDetail.bookId chapter:c.charpterModel.charpterId text:c.content.string];
}

/// 缓存只存结构化句对+兜底文本,展示前按"当前"字号/字体/主题重新渲染
- (NSAttributedString *)p_renderCachedTranslation:(RDCachedTranslation *)cached
{
    if (!cached) {
        return nil;
    }
    return [RDReadTranslateHelper attributedStringForPairs:cached.pairs
                                              fallbackSource:cached.fallbackSource
                                          fallbackTranslation:cached.fallbackTranslation];
}

/// 后台会话开启时:有缓存且「显示开」则套用;始终后台拉当前页+邻页缓存
- (void)p_applyTranslateModeIfNeeded
{
    if (!self.translateBackgroundEnabled) {
        return;
    }
    RDReadController *page = [self p_currentReadController];
    if (!page) {
        return;
    }
    NSString *key = [self p_translateKeyForController:page];
    if (key.length == 0) {
        return;
    }
    RDCachedTranslation *cached = [self.translateCache objectForKey:key];
    if (self.translateDisplayEnabled) {
        if (cached) {
            [page showInlineTranslation:[self p_renderCachedTranslation:cached]];
        } else {
            // 显示开但无缓存:先原文,后台译完再插
            if (page.showingInlineTranslation) {
                [page showInlineTranslation:nil];
            }
            [self p_requestTranslateKey:key
                               pageText:page.content.string
                            chapterText:page.charpterContent.string
                             rawContent:page.charpterModel.content
                             forDisplay:YES
                                  quiet:YES];
        }
    } else {
        // 仅后台:不展示,继续译当前页写入缓存
        if (page.showingInlineTranslation) {
            [page showInlineTranslation:nil];
        }
        if (!cached) {
            [self p_requestTranslateKey:key
                               pageText:page.content.string
                            chapterText:page.charpterContent.string
                             rawContent:page.charpterModel.content
                             forDisplay:NO
                                  quiet:YES];
        }
    }
    [self p_prefetchAdjacentTranslationsFrom:page];
}

/// 预取当前页 ±1(同章),纯后台写缓存
- (void)p_prefetchAdjacentTranslationsFrom:(RDReadController *)page
{
    if (!self.translateBackgroundEnabled || !page.pages.count) {
        return;
    }
    NSArray *pages = page.pages;
    NSInteger total = pages.count;
    NSInteger cid = page.charpterModel.charpterId;
    NSAttributedString *chapterContent = page.charpterContent;
    NSInteger bookId = self.bookDetail.bookId;

    for (NSNumber *delta in @[@(1), @(-1)]) {
        NSInteger p = page.page + delta.integerValue;
        if (p < 0 || p >= total) {
            continue;
        }
        NSAttributedString *slice = [self p_getCurPageContentWithContent:chapterContent page:p pages:pages];
        NSString *text = slice.string;
        if (text.length == 0) {
            continue;
        }
        NSString *key = [self p_translateKeyForBook:bookId chapter:cid text:text];
        if ([self.translateCache objectForKey:key] || [self.translatePendingKeys containsObject:key]) {
            continue;
        }
        // 预取受在途上限约束,快速翻页不堆积请求
        if (self.translatePendingKeys.count >= kTranslateMaxInflight) {
            break;
        }
        [self p_requestTranslateKey:key
                           pageText:text
                        chapterText:nil
                         rawContent:nil
                         forDisplay:NO
                              quiet:YES];
    }
}

/// forDisplay 且「显示开」且仍是当前页 → 套 UI;否则只写缓存(后台继续)
- (void)p_requestTranslateKey:(NSString *)key
                     pageText:(NSString *)pageText
                  chapterText:(NSString *)chapterText
                   rawContent:(NSString *)rawContent
                   forDisplay:(BOOL)forDisplay
                        quiet:(BOOL)quiet
{
    if (key.length == 0 || !self.translateBackgroundEnabled) {
        return;
    }
    RDCachedTranslation *hit = [self.translateCache objectForKey:key];
    if (hit) {
        if (forDisplay && self.translateDisplayEnabled) {
            RDReadController *cur = [self p_currentReadController];
            if ([[self p_translateKeyForController:cur] isEqualToString:key]) {
                [cur showInlineTranslation:[self p_renderCachedTranslation:hit]];
            }
        }
        return;
    }
    if ([self.translatePendingKeys containsObject:key]) {
        return;
    }
    // 在途上限:当前页展示请求(forDisplay)始终放行,纯预取超限丢弃
    if (!forDisplay && self.translatePendingKeys.count >= kTranslateMaxInflight) {
        return;
    }
    [self.translatePendingKeys addObject:key];

    __weak typeof(self) weakSelf = self;
    [RDReadTranslateHelper translateFromHost:self
                                    pageText:pageText
                                 chapterText:chapterText
                                  rawContent:rawContent
                                       quiet:quiet
                                  completion:^(NSArray<RDTranslatePair *> *pairs, NSString *fullTranslation, NSError *error) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) {
            return;
        }
        [self.translatePendingKeys removeObject:key];
        // 关闭「显示」后仍写缓存;仅彻底停止后台会话才丢弃
        if (!self.translateBackgroundEnabled) {
            return;
        }
        if (error || (!pairs.count && fullTranslation.length == 0)) {
            return;
        }
        // 缓存结构化句对而非渲染好的富文本,展示时按当前字号/字体/主题重新渲染(P1-10)
        RDCachedTranslation *cachedValue = [[RDCachedTranslation alloc] init];
        cachedValue.pairs = pairs;
        cachedValue.fallbackSource = pageText;
        cachedValue.fallbackTranslation = fullTranslation;
        NSAttributedString *attr = [self p_renderCachedTranslation:cachedValue];
        if (attr.length == 0) {
            return;
        }
        [self.translateCache setObject:cachedValue forKey:key];
        // 仅显示开 + 仍在该页 → 插入正文
        if (self.translateDisplayEnabled) {
            RDReadController *cur = [self p_currentReadController];
            if (cur && [[self p_translateKeyForController:cur] isEqualToString:key]) {
                [cur showInlineTranslation:attr];
            }
        }
        if (!quiet) {
            [RDToastView showText:@"翻译已开 · 隐藏后后台仍继续 · 再点两次可全停" delay:2.0 inView:self.view];
        }
    }];
}

- (void)p_stopTranslateBackground
{
    self.translateBackgroundEnabled = NO;
    self.translateDisplayEnabled = NO;
    [self.translatePendingKeys removeAllObjects];
    // 真正取消在途的后台请求:否则"已停止"之后旧请求仍在计费、仍会写缓存(P2-07)
    [[RDAIClient sharedClient] cancelBackgroundTranslations];
    RDReadController *cur = [self p_currentReadController];
    [cur showInlineTranslation:nil];
}

-(void)translateAction
{
    if (self.menuView.superview) {
        [self invokeMenu:self.pageViewController.viewControllers.firstObject];
    }
    RDReadController *currentController = [self p_currentReadController];
    if (!currentController) {
        return;
    }

    // ① 显示中 → 隐藏译文,后台继续译/预取
    if (self.translateBackgroundEnabled && self.translateDisplayEnabled) {
        self.translateDisplayEnabled = NO;
        [currentController showInlineTranslation:nil];
        [RDToastView showText:@"已隐藏译文 · 后台继续翻译" delay:1.5 inView:self.view];
        // 继续当前+邻页后台
        [self p_applyTranslateModeIfNeeded];
        return;
    }

    // ② 仅后台中 → 完全停止
    if (self.translateBackgroundEnabled && !self.translateDisplayEnabled) {
        [self p_stopTranslateBackground];
        [RDToastView showText:@"已停止后台翻译" delay:1.2 inView:self.view];
        return;
    }

    // ③ 全关 → 开启显示+后台。先校验配置,避免弹窗后仍误开翻译会话
    if (![RDReadTranslateHelper ensureUsableAIConfigFromHost:self quiet:NO]) {
        return;
    }

    self.translateBackgroundEnabled = YES;
    self.translateDisplayEnabled = YES;
    NSString *key = [self p_translateKeyForController:currentController];
    RDCachedTranslation *cached = [self.translateCache objectForKey:key];
    if (cached) {
        [currentController showInlineTranslation:[self p_renderCachedTranslation:cached]];
        [RDToastView showText:@"翻译已开 · 翻页后台同步 · 点「译」可隐藏" delay:1.6 inView:self.view];
        [self p_prefetchAdjacentTranslationsFrom:currentController];
        return;
    }
    __weak typeof(self) weakSelf = self;
    [self p_requestTranslateKey:key
                       pageText:currentController.content.string
                    chapterText:currentController.charpterContent.string
                     rawContent:currentController.charpterModel.content
                     forDisplay:YES
                          quiet:NO];
    dispatch_async(dispatch_get_main_queue(), ^{
        [weakSelf p_prefetchAdjacentTranslationsFrom:currentController];
    });
}

#pragma mark - 分享金句

-(void)shareQuoteAction
{
    if (self.menuView.superview) {
        [self invokeMenu:self.pageViewController.viewControllers.firstObject];
    }
    RDReadController *currentController = [self p_currentReadController];
    NSString *source = currentController.content.string;
    if (source.length == 0) {
        source = currentController.charpterContent.string;
    }
    if (source.length == 0) {
        [RDToastView showText:@"本页没有可分享的文字" delay:1.2 inView:self.view];
        return;
    }
    //选句面板:长按选中要分享的字句,生成卡片后仅以图片分享
    RDQuoteShareController *picker = [[RDQuoteShareController alloc] init];
    picker.book = self.bookDetail;
    picker.pageText = source;
    picker.modalPresentationStyle = UIModalPresentationPageSheet;
    [self presentViewController:picker animated:YES completion:nil];
}

#pragma mark - 听书

-(void)speechAction
{
    if (self.menuView.superview) {
        [self invokeMenu:self.pageViewController.viewControllers.firstObject];
    }
    RDReadController *currentController = (RDReadController *)self.pageViewController.viewControllers.firstObject;
    if (!currentController) {
        return;
    }
    //从当前页起朗读本章剩余内容
    NSAttributedString *charpterContent = currentController.charpterContent;
    NSArray *pages = currentController.pages;
    NSInteger page = currentController.page;
    NSInteger loc = 0;
    if (page >= 0 && page < pages.count) {
        loc = [pages[page] integerValue];
    }
    NSString *text = [charpterContent.string substringFromIndex:MIN(loc, charpterContent.string.length)];

    RDSpeechManager *manager = [RDSpeechManager sharedInstance];
    manager.delegate = self;
    [manager startWithBook:self.bookDetail chapters:self.charpters chapterIndex:currentController.charpterIndex text:text];

    if (!self.speechBar.superview) {
        [self.speechBar showInView:self.view];
    }
    [self.speechBar updatePlaying:YES rate:manager.rateMultiplier];
    [self.speechBar updateVoiceName:[[RDVoiceManager sharedInstance] preferredDisplayName]];
}

-(RDReadSpeechBar *)speechBar
{
    if (!_speechBar) {
        _speechBar = [[RDReadSpeechBar alloc] init];
        __weak typeof(self) weakSelf = self;
        RDSpeechManager *manager = [RDSpeechManager sharedInstance];
        _speechBar.onPlayPause = ^{
            if (manager.paused) {
                [manager resume];
            }
            else{
                [manager pause];
            }
        };
        _speechBar.onRate = ^{
            [manager cycleRate];
            [RDToastView showText:@"新语速将从下一章开始生效" delay:1.2 inView:weakSelf.view];
        };
        _speechBar.onVoice = ^{
            RDVoicePickerController *vc = [[RDVoicePickerController alloc] init];
            [weakSelf.navigationController pushViewController:vc animated:YES];
        };
        _speechBar.onExit = ^{
            [manager stop];
        };
        [_speechBar updateVoiceName:[[RDVoiceManager sharedInstance] preferredDisplayName]];
    }
    return _speechBar;
}

#pragma mark - RDSpeechManagerDelegate

-(void)speechManagerWillSpeakChapter:(RDCharpterModel *)chapter
{
    //续播新章节时,阅读页同步跳到该章首页
    self.bookDetail.charpterModel = chapter;
    self.bookDetail.page = 0;
    self.bookDetail.charOffset = 0;
    // 听书切章:失败仅记内存态,下一次生命周期会再写;不打断朗读弹 toast
    [RDReadRecordManager updateProgressWithModel:self.bookDetail];
    [self initSteup];
}

-(void)speechManagerDidStop
{
    [self.speechBar removeFromSuperview];
    self.speechBar = nil;
}

-(void)speechManagerStateChanged
{
    RDSpeechManager *manager = [RDSpeechManager sharedInstance];
    [self.speechBar updatePlaying:manager.active && !manager.paused rate:manager.rateMultiplier];
}
//更改翻页方式
-(void)didChangePageType
{
    [self invokeMenu:self.pageViewController.viewControllers.firstObject];
    RDReadController *currentController = (RDReadController *)_pageViewController.viewControllers.firstObject;
    NSInteger charpter = currentController.charpterIndex; //当前章节
    NSAttributedString *charpterContent = currentController.charpterContent;    //当前章节内容
    NSArray *pages = currentController.pages;       //分页信息数组
    
    // 完整 containment 拆除:willMove → remove view → removeFromParent(P2-02)
    [_pageViewController willMoveToParentViewController:nil];
    [_pageViewController.view removeFromSuperview];
    [_pageViewController removeFromParentViewController];
    _pageViewController = nil;
    [self addChildViewController:self.pageViewController];
    [self.pageViewController didMoveToParentViewController:self];
    
    [self.pageViewController setViewControllers:@[[self p_creatReadController:self.bookDetail.charpterModel.name content:[self p_getCurPageContentWithContent:charpterContent page:self.bookDetail.page pages:pages] page:[self p_safePage:self.bookDetail.page totalPages:pages.count] totalPage:pages.count charpterIndex:charpter totalCharpter:self.charpters.count charpterModel:self.bookDetail.charpterModel charpterContent:charpterContent pages:pages]] direction:UIPageViewControllerNavigationDirectionForward animated:NO completion:nil];
    
}


-(void)cancelShowMenu:(RDMenuView *)menu
{
    [self invokeMenu:self.pageViewController.viewControllers.firstObject];
}

#pragma mark - 书签

-(void)bookmarkViewDidAddCurrent
{
    RDReadController *cur = (RDReadController *)self.pageViewController.viewControllers.firstObject;
    if (!cur || cur.isMirror) {
        for (UIViewController *vc in self.pageViewController.viewControllers) {
            if ([vc isKindOfClass:RDReadController.class] && ![(RDReadController *)vc isMirror]) {
                cur = (RDReadController *)vc;
                break;
            }
        }
    }
    if (!cur.charpterModel) {
        [RDToastView showText:@"无法添加书签" delay:1.2 inView:self.view];
        return;
    }
    NSInteger offset = 0;
    if (cur.pages.count > 0) {
        NSInteger page = [self p_safePage:cur.page totalPages:cur.pages.count];
        offset = [cur.pages[page] integerValue];
    }
    NSString *snippet = cur.content.string;
    if (snippet.length > 100) {
        snippet = [[snippet substringToIndex:100] stringByAppendingString:@"…"];
    }
    RDBookmarkModel *bm = [RDBookmarkManager addBookmarkForBook:self.bookDetail
                                                       chapter:cur.charpterModel
                                                          page:cur.page
                                                    charOffset:offset
                                                       snippet:snippet];
    if (bm) {
        [RDToastView showText:@"已添加书签" delay:1.2 inView:self.view];
        [self.menuView.toolBar.bookmark setSelected:YES];
    }
}

-(void)bookmarkViewDidSelect:(RDBookmarkModel *)bookmark
{
    if (!bookmark) {
        return;
    }
    // 关闭菜单后跳转
    if (self.menuView.superview) {
        [self invokeMenu:self.pageViewController.viewControllers.firstObject];
    }
    [RDCharpterManager getCharpterWithBookId:self.bookDetail.bookId charpterId:bookmark.charpterId complete:^(BOOL success, RDCharpterModel *model) {
        if (!success || !model) {
            [RDToastView showText:@"章节不存在" delay:1.2 inView:self.view];
            return;
        }
        self.bookDetail.charpterModel = model;
        self.bookDetail.page = bookmark.page;
        self.bookDetail.charOffset = bookmark.charOffset;
        BOOL progressOK = [RDReadRecordManager updateProgressWithModel:self.bookDetail];
        [self initSteup];
        if (progressOK) {
            [RDToastView showText:@"已跳转到书签" delay:1.0 inView:self.view];
        } else {
            [RDToastView showText:@"已跳转,但进度保存失败" delay:1.2 inView:self.view];
        }
    }];
}

-(void)dealloc
{
    // 进度保存/停听书/清缓存已在 backAction 与 viewWillDisappear 完成;
    // dealloc 期间不再调用业务方法(避免析构中创建弱引用/写库)
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    _translateBackgroundEnabled = NO;
    _translateDisplayEnabled = NO;
    if ([RDSpeechManager sharedInstance].delegate == self) {
        [RDSpeechManager sharedInstance].delegate = nil;
    }
}

@end
