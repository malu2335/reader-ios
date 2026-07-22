//
//  RDComicChapterListController.m
//  Reader
//

#import "RDComicChapterListController.h"
#import "RDBookDetailModel.h"
#import "RDCharpterModel.h"
#import "RDCharpterDataManager.h"
#import "RDComicReadController.h"
#import "RDComicHelper.h"
#import "RDLocalBookManager.h"
#import "RDReadRecordManager.h"
#import "RDAppAppearance.h"
#import "RDTopView.h"
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

@interface RDComicChapterListController () <UITableViewDelegate, UITableViewDataSource, UIDocumentPickerDelegate>
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) UIView *headerView;
@property (nonatomic, strong) UIImageView *coverView;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *metaLabel;
@property (nonatomic, strong) UILabel *progressLabel;
@property (nonatomic, copy) NSArray <RDCharpterModel *>*chapters;
@property (nonatomic, strong) NSDictionary <NSNumber *, NSDictionary *>*infoById; // charpterId -> comic info
@end

@implementation RDComicChapterListController

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.view.backgroundColor = RDBackgroudColor;
    self.topView.titleLabel.text = self.bookDetail.title.length ? self.bookDetail.title : @"目录";
    UIButton *importBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    [importBtn setTitle:@"导入新话" forState:UIControlStateNormal];
    importBtn.titleLabel.font = RDFont15;
    [importBtn setTitleColor:RDAccentColor forState:UIControlStateNormal];
    [importBtn addTarget:self action:@selector(p_importNewChapters) forControlEvents:UIControlEventTouchUpInside];
    [self.topView addRightBtn:importBtn];

    [self.view addSubview:self.topView];
    [self.view addSubview:self.tableView];
    [self p_buildHeader];
    [self p_reloadChapters];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(p_onAppearance)
                                                 name:RDAppAppearanceDidChangeNotification
                                               object:nil];
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    // 从阅读返回时刷新「读到」进度
    RDBookDetailModel *record = [RDReadRecordManager getReadRecordWithBookId:self.bookDetail.bookId];
    if (record) {
        self.bookDetail = record;
    }
    [self p_refreshHeader];
    [self.tableView reloadData];
}

- (void)viewDidLayoutSubviews
{
    [super viewDidLayoutSubviews];
    self.tableView.frame = CGRectMake(0, self.topView.bottom, self.view.width, self.view.height - self.topView.bottom);
    if (self.headerView && fabs(self.headerView.bounds.size.width - self.view.width) > 0.5) {
        CGRect hf = self.headerView.frame;
        hf.size.width = self.view.width;
        self.headerView.frame = hf;
        self.titleLabel.frame = CGRectMake(108, 20, self.view.width - 128, 44);
        self.metaLabel.frame = CGRectMake(108, 68, self.view.width - 128, 20);
        self.progressLabel.frame = CGRectMake(108, 92, self.view.width - 128, 20);
        self.tableView.tableHeaderView = self.headerView; // re-assign to refresh height
    }
}

- (void)p_onAppearance
{
    self.view.backgroundColor = RDBackgroudColor;
    self.tableView.backgroundColor = RDBackgroudColor;
    self.headerView.backgroundColor = RDBackgroudColor;
    self.titleLabel.textColor = RDBlackColor;
    self.metaLabel.textColor = RDLightGrayColor;
    self.progressLabel.textColor = RDGrayColor;
    self.topView.backgroundColor = RDBackgroudColor;
    self.topView.titleLabel.textColor = RDBlackColor;
    [self.tableView reloadData];
}

- (void)p_reloadChapters
{
    // 一次取 id/name/content(JSON 很小),避免 24 次 getCharpter 往返
    NSArray *rows = [RDCharpterDataManager getComicChapterRowsWithBookId:self.bookDetail.bookId];
    NSMutableDictionary *map = [NSMutableDictionary dictionary];
    for (RDCharpterModel *ch in rows) {
        NSDictionary *info = [RDComicHelper comicChapterInfoFromContent:ch.content];
        if (info) {
            map[@(ch.charpterId)] = info;
        }
    }
    self.chapters = rows ?: @[];
    self.infoById = map.copy;
    [self p_refreshHeader];
    [self.tableView reloadData];
}

- (void)p_buildHeader
{
    UIView *header = [[UIView alloc] initWithFrame:CGRectMake(0, 0, self.view.width, 140)];
    header.backgroundColor = RDBackgroudColor;

    UIImageView *cover = [[UIImageView alloc] initWithFrame:CGRectMake(20, 16, 72, 100)];
    cover.contentMode = UIViewContentModeScaleAspectFill;
    cover.clipsToBounds = YES;
    cover.layer.cornerRadius = 6;
    cover.backgroundColor = RDSurfaceColor;
    UIImage *img = [RDLocalBookManager coverForBook:self.bookDetail];
    cover.image = img ?: [UIImage imageNamed:@"app_placeholder"];
    [header addSubview:cover];
    self.coverView = cover;

    UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(108, 20, self.view.width - 128, 44)];
    title.font = RDBoldFont17;
    title.textColor = RDBlackColor;
    title.numberOfLines = 2;
    [header addSubview:title];
    self.titleLabel = title;

    UILabel *meta = [[UILabel alloc] initWithFrame:CGRectMake(108, 68, self.view.width - 128, 20)];
    meta.font = RDFont13;
    meta.textColor = RDLightGrayColor;
    [header addSubview:meta];
    self.metaLabel = meta;

    UILabel *progress = [[UILabel alloc] initWithFrame:CGRectMake(108, 92, self.view.width - 128, 20)];
    progress.font = RDFont13;
    progress.textColor = RDGrayColor;
    [header addSubview:progress];
    self.progressLabel = progress;

    UIView *sep = [[UIView alloc] initWithFrame:CGRectMake(20, 139, self.view.width - 40, 1.0 / [UIScreen mainScreen].scale)];
    sep.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleTopMargin;
    sep.backgroundColor = RDLightSeparatorColor;
    [header addSubview:sep];

    self.headerView = header;
    self.tableView.tableHeaderView = header;
    [self p_refreshHeader];
}

- (void)p_refreshHeader
{
    self.titleLabel.text = self.bookDetail.title ?: @"";
    NSInteger n = self.chapters.count;
    RDComicReadMode mode = [RDComicHelper readModeForBookId:self.bookDetail.bookId];
    if (n > 0) {
        self.metaLabel.text = [NSString stringWithFormat:@"共 %ld 话 · %@", (long)n, [RDComicHelper displayNameForReadMode:mode]];
    } else {
        self.metaLabel.text = [NSString stringWithFormat:@"整本图集 · %@", [RDComicHelper displayNameForReadMode:mode]];
    }
    NSString *chName = self.bookDetail.readChapterName.length
        ? self.bookDetail.readChapterName
        : self.bookDetail.charpterModel.name;
    if (chName.length > 0) {
        NSInteger page = self.bookDetail.page + 1;
        self.progressLabel.text = [NSString stringWithFormat:@"读到 %@ · 第 %ld 页", chName, (long)MAX(1, page)];
    } else if (self.bookDetail.page > 0 || self.bookDetail.total > 0) {
        self.progressLabel.text = [NSString stringWithFormat:@"读到第 %ld 页", (long)(self.bookDetail.page + 1)];
    } else {
        self.progressLabel.text = @"尚未阅读 · 可点右上角导入新话";
    }
    UIImage *img = [RDLocalBookManager coverForBook:self.bookDetail];
    if (img) {
        self.coverView.image = img;
    }
}

- (UITableView *)tableView
{
    if (!_tableView) {
        _tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
        _tableView.delegate = self;
        _tableView.dataSource = self;
        _tableView.backgroundColor = RDBackgroudColor;
        _tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
        _tableView.rowHeight = 56;
        _tableView.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentNever;
    }
    return _tableView;
}

#pragma mark - Import new chapters

- (void)p_importNewChapters
{
    NSMutableArray <UTType *>*types = [NSMutableArray array];
    UTType *zip = [UTType typeWithIdentifier:@"public.zip-archive"];
    if (zip) { [types addObject:zip]; }
    if (UTTypeFolder) { [types addObject:UTTypeFolder]; }
    for (NSString *ext in @[@"zip", @"cbz"]) {
        UTType *t = [UTType typeWithFilenameExtension:ext];
        if (t && ![types containsObject:t]) {
            [types addObject:t];
        }
    }
    // 也允许直接选图片(会当作单文件导入失败提示;文件夹/压缩包为主)
    UIDocumentPickerViewController *picker =
        [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:types asCopy:YES];
    picker.delegate = self;
    picker.allowsMultipleSelection = YES;
    picker.shouldShowFileExtensions = YES;
    [self presentViewController:picker animated:YES completion:nil];
}

- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls
{
    if (urls.count == 0) { return; }
    [self showLoading:@"正在导入新话…" cancel:nil];
    __block NSInteger pending = urls.count;
    __block NSInteger totalAdded = 0;
    __block NSString *lastError = nil;
    for (NSURL *url in urls) {
        [RDLocalBookManager appendComicChaptersToBook:self.bookDetail
                                              fromURL:url
                                             complete:^(NSInteger addedCount, NSString *errorMessage) {
            pending--;
            if (addedCount > 0) {
                totalAdded += addedCount;
            } else if (errorMessage.length > 0) {
                lastError = errorMessage;
            }
            if (pending == 0) {
                [self hideLoading];
                // 刷新记录与目录
                RDBookDetailModel *record = [RDReadRecordManager getReadRecordWithBookId:self.bookDetail.bookId];
                if (record) {
                    self.bookDetail = record;
                }
                [self p_reloadChapters];
                if (totalAdded > 0) {
                    [self showText:[NSString stringWithFormat:@"已导入 %ld 话", (long)totalAdded]];
                } else {
                    [self showText:lastError ?: @"导入失败"];
                }
            }
        }];
    }
}

- (void)documentPickerWasCancelled:(UIDocumentPickerViewController *)controller
{
}

#pragma mark - Table

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    // 扁平图集无章节行:给一行「整本阅读」入口
    return self.chapters.count > 0 ? self.chapters.count : 1;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    static NSString *cid = @"RDComicChapterCell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:cid];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:cid];
        cell.backgroundColor = RDSurfaceColor;
        cell.textLabel.font = RDFont16;
        cell.detailTextLabel.font = RDFont13;
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    }
    cell.backgroundColor = RDSurfaceColor;
    cell.textLabel.textColor = RDBlackColor;
    cell.detailTextLabel.textColor = RDLightGrayColor;

    if (self.chapters.count == 0) {
        cell.textLabel.text = @"整本阅读";
        NSInteger total = self.bookDetail.total;
        cell.detailTextLabel.text = total > 0 ? [NSString stringWithFormat:@"%ld 页", (long)total] : @"图集";
        return cell;
    }

    RDCharpterModel *ch = self.chapters[indexPath.row];
    cell.textLabel.text = ch.name ?: [NSString stringWithFormat:@"第%ld话", (long)ch.charpterId];

    NSDictionary *info = self.infoById[@(ch.charpterId)];
    NSInteger pageCount = [info[@"pageCount"] integerValue];
    BOOL isCurrent = (self.bookDetail.charpterModel.charpterId == ch.charpterId)
        || (self.bookDetail.readChapterName.length && [self.bookDetail.readChapterName isEqualToString:ch.name]);
    if (isCurrent && self.bookDetail.page >= 0) {
        cell.detailTextLabel.text = [NSString stringWithFormat:@"读到 %ld · %ld页", (long)(self.bookDetail.page + 1), (long)pageCount];
        cell.textLabel.textColor = RDAccentColor;
    } else if (pageCount > 0) {
        cell.detailTextLabel.text = [NSString stringWithFormat:@"%ld页", (long)pageCount];
    } else {
        cell.detailTextLabel.text = nil;
    }
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (self.chapters.count == 0) {
        // 扁平图集
        RDComicReadController *comic = [[RDComicReadController alloc] init];
        comic.bookDetail = self.bookDetail;
        [self.navigationController pushViewController:comic animated:YES];
        return;
    }
    RDCharpterModel *ch = self.chapters[indexPath.row];
    [self p_openChapter:ch];
}

- (void)p_openChapter:(RDCharpterModel *)chapter
{
    if (!chapter) { return; }
    // 点击瞬间不写库、不二次读库,先 push 出阅读页,避免卡顿
    RDBookDetailModel *record = self.bookDetail;
    BOOL same = (record.charpterModel.charpterId == chapter.charpterId);
    NSInteger page = same ? MAX(0, record.page) : 0;

    record.charpterModel = chapter;
    record.readChapterName = chapter.name;
    record.page = page;

    RDComicReadController *comic = [[RDComicReadController alloc] init];
    comic.bookDetail = record;
    comic.chapter = chapter;
    [self.navigationController pushViewController:comic animated:YES];

    // 进度落库挪到转场之后
    NSInteger bookId = record.bookId;
    NSInteger pageToSave = page;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.35 * NSEC_PER_SEC)), dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        RDBookDetailModel *patch = [[RDBookDetailModel alloc] init];
        patch.bookId = bookId;
        patch.charpterModel = chapter;
        patch.readChapterName = chapter.name;
        patch.page = pageToSave;
        [RDReadRecordManager updateProgressWithModel:patch];
    });
}

@end
