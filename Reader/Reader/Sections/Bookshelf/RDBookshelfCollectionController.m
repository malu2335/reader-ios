//
//  RDBookshelfCollectionController.m
//  Reader
//

#import "RDBookshelfCollectionController.h"
#import "RDBookDetailModel.h"
#import "RDBookCollectionManager.h"
#import "RDLocalBookManager.h"
#import "RDReadRecordManager.h"
#import "RDReadHelper.h"
#import "RDAppAppearance.h"
#import "RDPaperAlert.h"
#import "RDTopView.h"
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

@interface RDBookshelfCollectionController () <UITableViewDelegate, UITableViewDataSource, UIDocumentPickerDelegate>
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) UIView *headerView;
@property (nonatomic, strong) UIImageView *coverView;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *metaLabel;
@property (nonatomic, strong) UILabel *progressLabel;
@property (nonatomic, copy) NSArray <RDBookDetailModel *>*members;
@end

@implementation RDBookshelfCollectionController

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.view.backgroundColor = RDBackgroudColor;
    self.topView.titleLabel.text = self.collection.title.length ? self.collection.title : @"合集";

    UIButton *importBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    [importBtn setTitle:@"导入新书" forState:UIControlStateNormal];
    importBtn.titleLabel.font = RDFont15;
    [importBtn setTitleColor:RDAccentColor forState:UIControlStateNormal];
    [importBtn addTarget:self action:@selector(p_importBooks) forControlEvents:UIControlEventTouchUpInside];
    [self.topView addRightBtn:importBtn];

    [self.view addSubview:self.topView];
    [self.view addSubview:self.tableView];
    [self p_buildHeader];
    [self p_reload];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(p_onAppearance)
                                                 name:RDAppAppearanceDidChangeNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(p_reload)
                                                 name:RDBookCollectionDidChangeNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(p_reload)
                                                 name:RDLocalBookImportedNotification
                                               object:nil];
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    [self p_reload];
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
        self.tableView.tableHeaderView = self.headerView;
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

- (void)p_reload
{
    RDBookDetailModel *hub = [RDReadRecordManager getReadRecordWithBookId:self.collection.bookId];
    if (hub) {
        self.collection = hub;
        self.topView.titleLabel.text = hub.title.length ? hub.title : @"合集";
    }
    self.members = [RDBookCollectionManager membersOfCollectionId:self.collection.bookId];
    [RDBookCollectionManager refreshCollectionSummary:self.collection.bookId];
    hub = [RDReadRecordManager getReadRecordWithBookId:self.collection.bookId];
    if (hub) {
        self.collection = hub;
    }
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

    UIView *sep = [[UIView alloc] initWithFrame:CGRectMake(20, 139, self.view.width - 40, 1.0 / UIScreen.mainScreen.scale)];
    sep.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleTopMargin;
    sep.backgroundColor = RDLightSeparatorColor;
    [header addSubview:sep];

    self.headerView = header;
    self.tableView.tableHeaderView = header;
    [self p_refreshHeader];
}

- (void)p_refreshHeader
{
    self.titleLabel.text = self.collection.title ?: @"合集";
    NSInteger n = self.members.count;
    self.metaLabel.text = [NSString stringWithFormat:@"共 %ld 本 · 点进某一本开始阅读", (long)n];
    NSString *last = self.collection.readChapterName;
    if (last.length == 0) {
        RDBookDetailModel *latest = nil;
        for (RDBookDetailModel *m in self.members) {
            if (!latest || m.readTime > latest.readTime) {
                latest = m;
            }
        }
        last = latest.title;
    }
    self.progressLabel.text = last.length ? [NSString stringWithFormat:@"最近 · %@", last] : @"尚未阅读";
    UIImage *img = [RDLocalBookManager coverForBook:self.collection];
    if (!img && self.members.firstObject) {
        img = [RDLocalBookManager coverForBook:self.members.firstObject];
    }
    self.coverView.image = img ?: [UIImage imageNamed:@"app_placeholder"];
}

- (UITableView *)tableView
{
    if (!_tableView) {
        _tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
        _tableView.delegate = self;
        _tableView.dataSource = self;
        _tableView.backgroundColor = RDBackgroudColor;
        _tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
        _tableView.rowHeight = 72;
        _tableView.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentNever;
    }
    return _tableView;
}

#pragma mark - Import

- (void)p_importBooks
{
    NSMutableArray <UTType *>*types = [NSMutableArray array];
    [types addObject:UTTypePlainText];
    [types addObject:UTTypePDF];
    UTType *epub = [UTType typeWithIdentifier:@"org.idpf.epub-container"];
    if (epub) {
        [types addObject:epub];
    }
    UTType *zip = [UTType typeWithIdentifier:@"public.zip-archive"];
    if (zip) {
        [types addObject:zip];
    }
    if (UTTypeFolder) {
        [types addObject:UTTypeFolder];
    }
    for (NSString *ext in @[@"epub", @"mobi", @"azw", @"txt", @"zip", @"cbz"]) {
        UTType *t = [UTType typeWithFilenameExtension:ext];
        if (t && ![types containsObject:t]) {
            [types addObject:t];
        }
    }
    UIDocumentPickerViewController *picker =
        [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:types asCopy:YES];
    picker.delegate = self;
    picker.allowsMultipleSelection = YES;
    [self presentViewController:picker animated:YES completion:nil];
}

- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls
{
    if (urls.count == 0) {
        return;
    }
    [self showLoading:@"正在导入…" cancel:nil];
    __block NSInteger pending = urls.count;
    __block NSInteger added = 0;
    __block NSString *lastError = nil;
    NSInteger collectionId = self.collection.bookId;
    for (NSURL *url in urls) {
        [RDLocalBookManager importBookAtURL:url complete:^(RDBookDetailModel *book, NSString *errorMessage, BOOL isDuplicate) {
            if (book) {
                NSString *err = nil;
                if ([RDBookCollectionManager addBookId:book.bookId toCollectionId:collectionId errorMessage:&err]) {
                    added++;
                } else if (err.length) {
                    lastError = err;
                }
            } else if (errorMessage.length) {
                lastError = errorMessage;
            }
            pending--;
            if (pending == 0) {
                [self hideLoading];
                [self p_reload];
                if (added > 0) {
                    [self showText:[NSString stringWithFormat:@"已加入合集 %ld 本", (long)added]];
                } else {
                    [self showText:lastError ?: @"导入失败"];
                }
            }
        }];
    }
}

#pragma mark - Table

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    return MAX((NSInteger)self.members.count, 1);
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    static NSString *cid = @"RDCollectionMemberCell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:cid];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:cid];
        cell.backgroundColor = RDSurfaceColor;
        cell.textLabel.font = RDFont16;
        cell.detailTextLabel.font = RDFont12;
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        cell.imageView.contentMode = UIViewContentModeScaleAspectFill;
        cell.imageView.clipsToBounds = YES;
        cell.imageView.layer.cornerRadius = 4;
    }
    cell.backgroundColor = RDSurfaceColor;
    cell.textLabel.textColor = RDBlackColor;
    cell.detailTextLabel.textColor = RDLightGrayColor;

    if (self.members.count == 0) {
        cell.textLabel.text = @"合集为空";
        cell.detailTextLabel.text = @"点右上角「导入新书」添加";
        cell.imageView.image = nil;
        cell.accessoryType = UITableViewCellAccessoryNone;
        return cell;
    }

    RDBookDetailModel *book = self.members[indexPath.row];
    cell.textLabel.text = [NSString stringWithFormat:@"%ld. %@", (long)(indexPath.row + 1), book.title ?: @"未命名"];
    NSString *sub = book.readChapterName.length
        ? [NSString stringWithFormat:@"读到 · %@", book.readChapterName]
        : (book.author.length ? book.author : (book.fileType.uppercaseString ?: @""));
    cell.detailTextLabel.text = sub;
    UIImage *cover = [RDLocalBookManager coverForBook:book];
    cell.imageView.image = cover ?: [UIImage imageNamed:@"app_placeholder"];
    // 固定缩略图尺寸
    CGSize sz = CGSizeMake(40, 56);
    UIGraphicsBeginImageContextWithOptions(sz, NO, 0);
    [cell.imageView.image drawInRect:CGRectMake(0, 0, sz.width, sz.height)];
    cell.imageView.image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.row >= (NSInteger)self.members.count) {
        return;
    }
    RDBookDetailModel *book = self.members[indexPath.row];
    // 打开前刷新合集最近阅读
    [RDReadRecordManager updateReadTime:self.collection];
    [RDReadHelper beginReadWithBookDetail:book];
}

- (UISwipeActionsConfiguration *)tableView:(UITableView *)tableView
    trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath
{
    if (indexPath.row >= (NSInteger)self.members.count) {
        return nil;
    }
    RDBookDetailModel *book = self.members[indexPath.row];
    __weak typeof(self) weakSelf = self;
    UIContextualAction *remove = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleDestructive
                                                                         title:@"移出合集"
                                                                       handler:^(UIContextualAction *action, UIView *sourceView, void (^completionHandler)(BOOL)) {
        [RDBookCollectionManager removeBookId:book.bookId fromCollection:weakSelf.collection.bookId];
        [weakSelf p_reload];
        // 若合集已解散,返回书架
        RDBookDetailModel *hub = [RDReadRecordManager getReadRecordWithBookId:weakSelf.collection.bookId];
        if (!hub.isCollection) {
            [weakSelf.navigationController popViewControllerAnimated:YES];
        }
        completionHandler(YES);
    }];
    return [UISwipeActionsConfiguration configurationWithActions:@[remove]];
}

@end
