//
// Created by yuenov on 2019/10/24.
// Copyright (c) 2019 yuenov. All rights reserved.
//

#import "RDBookshelfController.h"
#import "RDBookshelfNoneCell.h"
#import "RDBookDetailModel.h"
#import "RDReadRecordManager.h"
#import "RDBookshelfCell.h"
#import "RDCacheModel.h"
#import "RDReadHelper.h"
#import "RDCharpterDataManager.h"
#import "RDLocalBookManager.h"
#import "RDBookshelfPrefetch.h"
#import "RDAppAppearance.h"
#import "RDBookCollectionManager.h"
#import "RDPaperAlert.h"
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import <PhotosUI/PhotosUI.h>
#import <ImageIO/ImageIO.h>


#import "RDCharpterModel.h"

#define kItemCount ([RDUtilities iPad] ? 5 : 3)

@interface RDBookshelfController ()<UIDocumentPickerDelegate, PHPickerViewControllerDelegate>
@property (nonatomic,strong) NSMutableArray *dataSource;
@property (nonatomic,strong) UITableView *tableView;
@property (nonatomic,strong) NSMutableArray *bookSource;
@property (nonatomic,assign) BOOL didApplyPrefetch;
@property (nonatomic,assign) BOOL isReloading;
/// 运行期间又有新的刷新请求(如批量导入的后续通知)时置位,不丢失该请求
@property (nonatomic,assign) BOOL pendingReload;
@property (nonatomic,assign) BOOL skipNextAppearReload;
@property (nonatomic,strong) RDBookDetailModel *pendingCoverBook;
@property (nonatomic,assign) NSUInteger pendingCoverRequestVersion;
/// 合并合集多选
@property (nonatomic,assign) BOOL mergeSelectMode;
@property (nonatomic,strong) NSMutableSet <NSNumber *>*mergeSelectedIds;
@property (nonatomic,strong) UIButton *mergeBarButton;
@end

@implementation RDBookshelfController
-(void)viewDidLoad{
    [super viewDidLoad];
    [self.view addSubview:self.topView];
    [self.view addSubview:self.tableView];
    
    //导入完成后刷新书架(导入入口:顶栏按钮 / 空书架按钮 / 其他应用打开)
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(p_reload)
                                                 name:RDLocalBookImportedNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(importAction)
                                                 name:RDLocalBookImportRequestNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(p_beginMergeFromSettings)
                                                 name:RDBookshelfMergeRequestNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(p_onAppearanceChanged)
                                                 name:RDAppAppearanceDidChangeNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(p_reload)
                                                 name:RDBookCollectionDidChangeNotification object:nil];

    // 启动页已预加载:立刻灌入缓存,首帧不空白
    if ([RDBookshelfPrefetch ready]) {
        [self p_applyPrefetchCache];
        self.skipNextAppearReload = YES;
    }

    // 先出书架 UI,首帧后再恢复上次阅读,避免启动直接卡在读库/分页
    dispatch_async(dispatch_get_main_queue(), ^{
        RDBookDetailModel *book = [RDCacheModel sharedInstance].book;
        if (book) {
            [RDReadHelper beginReadWithBookDetail:book animation:NO];
        }
    });
}

-(void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)p_onAppearanceChanged
{
    self.view.backgroundColor = RDBackgroudColor;
    self.tableView.backgroundColor = RDBackgroudColor;
    self.topView.backgroundColor = RDBackgroudColor;
    self.topView.titleLabel.textColor = RDBlackColor;
    [self.tableView reloadData];
}

#pragma mark - 本地导入

-(void)importAction
{
    // 只有已上屏且没在展示别的模态时才 present;否则 UIKit 会丢弃这次 presentation。
    // 入口有三个(顶栏、空书架按钮、设置页通知),这里统一兜底(P2-01)。
    if (!self.view.window || self.presentedViewController) {
        return;
    }
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
    // 图片文件夹(图集)
    if (UTTypeFolder) {
        [types addObject:UTTypeFolder];
    }
    for (NSString *ext in @[@"epub", @"mobi", @"azw", @"txt", @"zip", @"cbz"]) {
        UTType *type = [UTType typeWithFilenameExtension:ext];
        if (type && ![types containsObject:type]) {
            [types addObject:type];
        }
    }
    UIDocumentPickerViewController *picker = [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:types asCopy:YES];
    picker.delegate = self;
    picker.allowsMultipleSelection = YES;
    [self presentViewController:picker animated:YES completion:nil];
}

-(void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls
{
    if (urls.count == 0) {
        return;
    }
    [self showLoading:@"正在导入..." cancel:nil];
    __block NSInteger pending = urls.count;
    __block NSInteger succeed = 0;
    __block NSInteger duplicated = 0;
    __block NSString *lastError = nil;
    __block NSString *lastDupMsg = nil;
    __block NSString *lastNewTitle = nil;
    for (NSURL *url in urls) {
        [RDLocalBookManager importBookAtURL:url complete:^(RDBookDetailModel *book, NSString *errorMessage, BOOL isDuplicate) {
            pending--;
            if (isDuplicate) {
                duplicated++;
                lastDupMsg = errorMessage;
            } else if (book) {
                succeed++;
                lastNewTitle = book.title;
            } else if (errorMessage) {
                lastError = errorMessage;
            }
            if (pending == 0) {
                [self hideLoading];
                if (urls.count == 1) {
                    // 单文件:直接展示重复/成功/失败文案
                    if (duplicated > 0) {
                        [self showText:lastDupMsg ?: @"该书已在书架"];
                    } else if (succeed > 0) {
                        [self showText:[NSString stringWithFormat:@"《%@》已加入书架", lastNewTitle ?: @"书籍"]];
                    } else {
                        [self showText:lastError ?: @"导入失败"];
                    }
                } else {
                    NSMutableString *msg = [NSMutableString string];
                    if (succeed > 0) {
                        [msg appendFormat:@"新导入 %@ 本", @(succeed)];
                    }
                    if (duplicated > 0) {
                        if (msg.length) {
                            [msg appendString:@","];
                        }
                        [msg appendFormat:@"重复 %@ 本", @(duplicated)];
                    }
                    if (lastError) {
                        if (msg.length) {
                            [msg appendString:@","];
                        }
                        [msg appendFormat:@"失败:%@", lastError];
                    }
                    [self showText:msg.length ? msg : @"导入完成"];
                }
                [RDBookshelfPrefetch invalidate];
                [self p_reload];
            }
        }];
    }
}
-(void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    if (self.skipNextAppearReload) {
        self.skipNextAppearReload = NO;
        return;
    }
    if ([RDBookshelfPrefetch ready] && !self.didApplyPrefetch) {
        [self p_applyPrefetchCache];
        return;
    }
    // 返回书架时异步轻量刷新(不读章节正文)
    [self p_reload];
}
- (UITableView *)tableView {
    if (!_tableView) {
        _tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStyleGrouped];
        _tableView.backgroundColor = RDBackgroudColor;
        _tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
        _tableView.delegate = self;
        _tableView.dataSource = self;
        _tableView.estimatedRowHeight = 0;
        _tableView.estimatedSectionHeaderHeight = 0;
        _tableView.estimatedSectionFooterHeight = 0;
        // Frame is below custom topView; never auto-adjust safe-area (replaces old VC insets flag).
        _tableView.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentNever;
        // 书架顶部留白:第一行封面不要贴顶栏
        _tableView.contentInset = UIEdgeInsetsMake(18, 0, 24, 0);
        _tableView.scrollIndicatorInsets = _tableView.contentInset;
        if (@available(iOS 15.0, *)) {
            _tableView.sectionHeaderTopPadding = 0;
        }
    }
    return _tableView;
}
-(NSMutableArray *)dataSource
{
    if (!_dataSource) {
        _dataSource = [NSMutableArray array];
    }
    return _dataSource;
}
-(NSMutableArray *)bookSource
{
    if (!_bookSource) {
        _bookSource = [NSMutableArray array];
    }
    return _bookSource;
}

- (RDTopView *)topView {
    if (!_topView) {
        _topView = [[RDTopView alloc] init];
        _topView.titleLabel.text = @"书架";
        _topView.titleLabel.font = RDTitleFont19;
        // 导入 / 合并 统一到设置;合并多选进行中才临时显示「完成」
    }
    return _topView;
}

/// 合并多选时临时顶栏「完成」按钮(平时不显示)
- (void)p_ensureMergeDoneButton
{
    if (self.mergeBarButton) {
        return;
    }
    UIButton *mergeBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    [mergeBtn setTitle:@"完成" forState:UIControlStateNormal];
    mergeBtn.titleLabel.font = RDFont16;
    [mergeBtn setTitleColor:RDAccentColor forState:UIControlStateNormal];
    [mergeBtn addTarget:self action:@selector(p_toggleMergeMode) forControlEvents:UIControlEventTouchUpInside];
    [self.topView addRightBtn:mergeBtn];
    self.mergeBarButton = mergeBtn;
    self.mergeBarButton.hidden = YES;
}

- (void)p_setMergeModeChromeActive:(BOOL)active
{
    [self p_ensureMergeDoneButton];
    self.mergeBarButton.hidden = !active;
    if (active) {
        NSInteger n = self.mergeSelectedIds.count;
        [self.mergeBarButton setTitle:(n >= 2 ? [NSString stringWithFormat:@"完成(%ld)", (long)n] : @"完成")
                             forState:UIControlStateNormal];
    } else {
        [self.mergeBarButton setTitle:@"完成" forState:UIControlStateNormal];
    }
    [self.topView refresh];
}

- (NSMutableSet <NSNumber *>*)mergeSelectedIds
{
    if (!_mergeSelectedIds) {
        _mergeSelectedIds = [NSMutableSet set];
    }
    return _mergeSelectedIds;
}

#pragma mark - 合集合并

- (void)p_beginMergeFromSettings
{
    // 设置页切入合并:清空旧勾选并进入多选
    self.mergeSelectMode = YES;
    [self.mergeSelectedIds removeAllObjects];
    [self p_setMergeModeChromeActive:YES];
    [self showText:@"点选至少两本书,再点「完成」合并"];
    [self.tableView reloadData];
}

- (void)p_toggleMergeMode
{
    if (self.mergeSelectMode) {
        // 结束或执行合并
        if (self.mergeSelectedIds.count >= 2) {
            [self p_confirmCreateCollectionFromSelection];
            return;
        }
        self.mergeSelectMode = NO;
        [self.mergeSelectedIds removeAllObjects];
        [self p_setMergeModeChromeActive:NO];
        [self.tableView reloadData];
        return;
    }
    self.mergeSelectMode = YES;
    [self.mergeSelectedIds removeAllObjects];
    [self p_setMergeModeChromeActive:YES];
    [self showText:@"点选至少两本书,再点「完成」合并"];
    [self.tableView reloadData];
}

- (void)p_confirmCreateCollectionFromSelection
{
    NSMutableArray <RDBookDetailModel *>*books = [NSMutableArray array];
    for (NSNumber *bid in self.mergeSelectedIds) {
        RDBookDetailModel *b = [RDReadRecordManager getReadRecordWithBookId:bid.integerValue];
        if (b && !b.isCollection) {
            [books addObject:b];
        }
    }
    if (books.count < 2) {
        [self showText:@"请至少选择两本书"];
        return;
    }
    NSString *defaultName = books.firstObject.title ?: @"合集";
    __weak typeof(self) weakSelf = self;
    [RDPaperAlert showTextFieldsWithTitle:@"合并为合集"
                                  message:[NSString stringWithFormat:@"将 %ld 本书合成一项,点开后可像话列表一样浏览", (long)books.count]
                               fieldSpecs:@[@{@"placeholder": @"合集名称", @"text": defaultName}]
                              cancelTitle:@"取消"
                             confirmTitle:@"合并"
                                  confirm:^(NSArray<NSString *> *values) {
        NSString *title = values.firstObject ?: defaultName;
        NSString *err = nil;
        RDBookDetailModel *hub = [RDBookCollectionManager createCollectionWithTitle:title books:books errorMessage:&err];
        weakSelf.mergeSelectMode = NO;
        [weakSelf.mergeSelectedIds removeAllObjects];
        [weakSelf p_setMergeModeChromeActive:NO];
        [RDBookshelfPrefetch invalidate];
        [weakSelf p_reload];
        if (hub) {
            [weakSelf showText:[NSString stringWithFormat:@"已创建合集《%@》", hub.title ?: @""]];
        } else {
            [weakSelf showText:err ?: @"合并失败"];
        }
    }];
}

- (void)p_createCollectionStartingWithBook:(RDBookDetailModel *)book
{
    if (!book || book.isCollection) {
        return;
    }
    // 进入多选并把当前书勾上
    self.mergeSelectMode = YES;
    [self.mergeSelectedIds removeAllObjects];
    [self.mergeSelectedIds addObject:@(book.bookId)];
    [self p_setMergeModeChromeActive:YES];
    [self showText:@"再选至少一本,点「完成」创建合集"];
    [self.tableView reloadData];
}

- (void)p_addBookToExistingCollection:(RDBookDetailModel *)book
{
    if (!book || book.isCollection) {
        return;
    }
    NSArray <RDBookDetailModel *>*cols = [RDBookCollectionManager allCollections];
    if (cols.count == 0) {
        [self showText:@"还没有合集,请先长按书籍「创建合集」或点顶栏「合并」"];
        return;
    }
    __weak typeof(self) weakSelf = self;
    NSMutableArray *actions = [NSMutableArray array];
    for (RDBookDetailModel *c in cols) {
        NSString *name = c.title.length ? c.title : @"未命名合集";
        [actions addObject:[RDPaperAlertAction actionWithTitle:name
                                                      subtitle:c.author
                                                         style:RDPaperAlertActionStyleDefault
                                                       handler:^{
            NSString *err = nil;
            BOOL ok = [RDBookCollectionManager addBookId:book.bookId toCollectionId:c.bookId errorMessage:&err];
            [RDBookshelfPrefetch invalidate];
            [weakSelf p_reload];
            [weakSelf showText:ok ? @"已加入合集" : (err ?: @"加入失败")];
        }]];
    }
    [actions addObject:[RDPaperAlertAction actionWithTitle:@"取消" style:RDPaperAlertActionStyleCancel handler:nil]];
    [RDPaperAlert showActionSheetWithTitle:@"加入合集" message:book.title actions:actions];
}

- (void)p_dissolveCollection:(RDBookDetailModel *)book
{
    if (!book.isCollection) {
        return;
    }
    __weak typeof(self) weakSelf = self;
    [RDPaperAlert showConfirmWithTitle:@"解散合集"
                               message:[NSString stringWithFormat:@"解散《%@》后,成员书会回到书架顶层", book.title ?: @""]
                           cancelTitle:@"取消"
                          confirmTitle:@"解散"
                           destructive:NO
                               confirm:^{
        [RDBookCollectionManager dissolveCollectionId:book.bookId];
        [RDBookshelfPrefetch invalidate];
        [weakSelf p_reload];
        [weakSelf showText:@"已解散合集"];
    }];
}
#pragma mark - delegate
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    return self.dataSource.count;
}

-(UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    id model = [self.dataSource objectAtIndexSafely:indexPath.row];
    if ([model isKindOfClass:NSString.class] && [model isEqualToString:@"RDBookshelfNoneCell"]) {
        RDBookshelfNoneCell *cell = [tableView dequeueReusableCellWithIdentifier:model];
        if (!cell) {
            cell = [[RDBookshelfNoneCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:model];
        }
        return cell;
    }
    if ([model isKindOfClass:NSArray.class]) {
        RDBookshelfCell *cell = [tableView dequeueReusableCellWithIdentifier:@"RDBookshelfCell"];
        if (!cell) {
            cell = [[RDBookshelfCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"RDBookshelfCell"];
            __weak typeof(self) weakSelf = self;
            cell.needReload = ^{
                [RDBookshelfPrefetch invalidate];
                [weakSelf p_reload];
            };
            cell.changeCover = ^(RDBookDetailModel *book) {
                [weakSelf p_changeCoverForBook:book];
            };
            cell.resetCover = ^(RDBookDetailModel *book) {
                [weakSelf p_resetCoverForBook:book];
            };
            cell.createCollection = ^(RDBookDetailModel *book) {
                [weakSelf p_createCollectionStartingWithBook:book];
            };
            cell.addToCollection = ^(RDBookDetailModel *book) {
                [weakSelf p_addBookToExistingCollection:book];
            };
            cell.dissolveCollection = ^(RDBookDetailModel *book) {
                [weakSelf p_dissolveCollection:book];
            };
            cell.toggleSelect = ^(RDBookDetailModel *book) {
                if (!book) { return; }
                NSNumber *key = @(book.bookId);
                if ([weakSelf.mergeSelectedIds containsObject:key]) {
                    [weakSelf.mergeSelectedIds removeObject:key];
                } else {
                    [weakSelf.mergeSelectedIds addObject:key];
                }
                [weakSelf p_setMergeModeChromeActive:YES];
                [weakSelf.tableView reloadData];
            };
        }
        cell.selectionMode = self.mergeSelectMode;
        cell.selectedBookIds = self.mergeSelectedIds;
        cell.books = model;
        return cell;
    }
    return [UITableViewCell new];
}
- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath
{
    id model = [self.dataSource objectAtIndexSafely:indexPath.row];
    if ([model isKindOfClass:NSString.class] && [model isEqualToString:@"RDBookshelfNoneCell"]) {
        return ScreenHeight - [UIView navigationBar] - [UIView tarBar] - [UIView statusBar];
    }
    if ([model isKindOfClass:NSArray.class]) {
        return [RDBookshelfCell cellHeight];
    }
    return CGFLOAT_MIN;
}

-(void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    [tableView deselectRowAtIndexPath:indexPath animated:NO];
}
- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section {
    // 有书时展示「共 N 本 · 长按管理」提示头
    id first = self.dataSource.firstObject;
    if ([first isKindOfClass:NSArray.class]) {
        return 36;
    }
    return CGFLOAT_MIN;
}

- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section
{
    id first = self.dataSource.firstObject;
    if (![first isKindOfClass:NSArray.class]) {
        return nil;
    }
    NSInteger count = 0;
    for (id row in self.dataSource) {
        if ([row isKindOfClass:NSArray.class]) {
            count += [(NSArray *)row count];
        }
    }
    UIView *header = [[UIView alloc] initWithFrame:CGRectMake(0, 0, tableView.width, 36)];
    UILabel *lab = [[UILabel alloc] initWithFrame:CGRectMake(22, 4, tableView.width - 44, 28)];
    lab.font = RDFont13;
    lab.textColor = RDLightGrayColor;
    if (self.mergeSelectMode) {
        lab.text = [NSString stringWithFormat:@"合并中 · 已选 %ld 本 · 点右上角「完成」", (long)self.mergeSelectedIds.count];
    } else {
        lab.text = [NSString stringWithFormat:@"共 %@ 项 · 长按管理 · 设置里导入/合并", @(count)];
    }
    [header addSubview:lab];
    return header;
}

- (CGFloat)tableView:(UITableView *)tableView heightForFooterInSection:(NSInteger)section {
    return CGFLOAT_MIN;
}
#pragma mark - action

-(NSUInteger)p_advanceCoverRequestForBook:(RDBookDetailModel *)book
{
    return [RDLocalBookManager beginCustomCoverRequestForBook:book];
}

-(BOOL)p_isCurrentCoverRequest:(NSUInteger)version forBook:(RDBookDetailModel *)book
{
    return [RDLocalBookManager isCustomCoverRequestCurrent:version forBook:book];
}

-(void)p_changeCoverForBook:(RDBookDetailModel *)book
{
    if (!book) {
        return;
    }
    PHPickerConfiguration *configuration = [[PHPickerConfiguration alloc] init];
    configuration.filter = [PHPickerFilter imagesFilter];
    configuration.selectionLimit = 1;
    PHPickerViewController *picker = [[PHPickerViewController alloc] initWithConfiguration:configuration];
    picker.delegate = self;
    self.pendingCoverBook = book;
    self.pendingCoverRequestVersion = [self p_advanceCoverRequestForBook:book];

    UIPopoverPresentationController *popover = picker.popoverPresentationController;
    if (popover) {
        popover.sourceView = self.view;
        popover.sourceRect = CGRectMake(CGRectGetMidX(self.view.bounds), CGRectGetMidY(self.view.bounds), 1, 1);
        popover.permittedArrowDirections = 0;
    }
    [self presentViewController:picker animated:YES completion:nil];
}

-(void)picker:(PHPickerViewController *)picker didFinishPicking:(NSArray<PHPickerResult *> *)results
{
    RDBookDetailModel *book = self.pendingCoverBook;
    NSUInteger requestVersion = self.pendingCoverRequestVersion;
    self.pendingCoverBook = nil;
    self.pendingCoverRequestVersion = 0;
    [picker dismissViewControllerAnimated:YES completion:nil];
    if (results.count == 0 || !book) {
        return;
    }

    NSItemProvider *provider = results.firstObject.itemProvider;
    if (![provider hasItemConformingToTypeIdentifier:UTTypeImage.identifier]) {
        [self showText:@"无法读取所选图片"];
        return;
    }

    __weak typeof(self) weakSelf = self;
    [provider loadFileRepresentationForTypeIdentifier:UTTypeImage.identifier completionHandler:^(NSURL *url, NSError *error) {
        if (![weakSelf p_isCurrentCoverRequest:requestVersion forBook:book]) {
            return;
        }
        UIImage *image = nil;
        if (url) {
            CGImageSourceRef source = CGImageSourceCreateWithURL((__bridge CFURLRef)url, NULL);
            if (source) {
                image = [weakSelf p_thumbnailFromImageSource:source];
                CFRelease(source);
            }
        }
        if (image) {
            [weakSelf p_saveCustomCoverImage:image forBook:book requestVersion:requestVersion];
            return;
        }
        [weakSelf p_loadCoverDataFromProvider:provider
                                      forBook:book
                               requestVersion:requestVersion
                                fallbackError:error];
    }];
}

-(UIImage *)p_thumbnailFromImageSource:(CGImageSourceRef)source
{
    if (!source) {
        return nil;
    }
    NSDictionary *options = @{
        (__bridge NSString *)kCGImageSourceCreateThumbnailFromImageAlways: @YES,
        (__bridge NSString *)kCGImageSourceCreateThumbnailWithTransform: @YES,
        (__bridge NSString *)kCGImageSourceThumbnailMaxPixelSize: @1200,
        (__bridge NSString *)kCGImageSourceShouldCacheImmediately: @YES
    };
    CGImageRef thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, (__bridge CFDictionaryRef)options);
    if (!thumbnail) {
        return nil;
    }
    UIImage *image = [UIImage imageWithCGImage:thumbnail];
    CGImageRelease(thumbnail);
    return image;
}

-(void)p_loadCoverDataFromProvider:(NSItemProvider *)provider
                           forBook:(RDBookDetailModel *)book
                    requestVersion:(NSUInteger)requestVersion
                     fallbackError:(NSError *)fallbackError
{
    __weak typeof(self) weakSelf = self;
    [provider loadDataRepresentationForTypeIdentifier:UTTypeImage.identifier completionHandler:^(NSData *data, NSError *error) {
        if (![weakSelf p_isCurrentCoverRequest:requestVersion forBook:book]) {
            return;
        }
        UIImage *image = nil;
        if (data.length > 0) {
            CGImageSourceRef source = CGImageSourceCreateWithData((__bridge CFDataRef)data, NULL);
            if (source) {
                image = [weakSelf p_thumbnailFromImageSource:source];
                CFRelease(source);
            }
        }
        if (!image) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if (![weakSelf p_isCurrentCoverRequest:requestVersion forBook:book]) {
                    return;
                }
                [weakSelf showText:error.localizedDescription ?: fallbackError.localizedDescription ?: @"无法读取所选图片"];
            });
            return;
        }
        [weakSelf p_saveCustomCoverImage:image forBook:book requestVersion:requestVersion];
    }];
}

-(void)p_saveCustomCoverImage:(UIImage *)image
                      forBook:(RDBookDetailModel *)book
               requestVersion:(NSUInteger)requestVersion
{
    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        if (![weakSelf p_isCurrentCoverRequest:requestVersion forBook:book]) {
            return;
        }
        NSString *errorMessage = nil;
        BOOL success = [RDLocalBookManager saveCustomCover:image
                                                   forBook:book
                                            requestVersion:requestVersion
                                              errorMessage:&errorMessage];
        dispatch_async(dispatch_get_main_queue(), ^{
            if (![weakSelf p_isCurrentCoverRequest:requestVersion forBook:book]) {
                return;
            }
            if (success) {
                [RDBookshelfPrefetch invalidate];
                [weakSelf p_reload];
                [weakSelf showText:@"封面已更新"];
            } else {
                [weakSelf showText:errorMessage ?: @"封面保存失败"];
            }
        });
    });
}

-(void)p_resetCoverForBook:(RDBookDetailModel *)book
{
    if (!book) {
        return;
    }
    // manager 会在同一临界区推进全局代次并删除文件，先前 picker 回调随后必定失效。
    [RDLocalBookManager removeCustomCoverForBook:book];
    [RDBookshelfPrefetch invalidate];
    [self p_reload];
    [self showText:@"已恢复默认封面"];
}

-(void)p_applyPrefetchCache
{
    if (![RDBookshelfPrefetch ready]) {
        return;
    }
    [self.dataSource removeAllObjects];
    [self.bookSource removeAllObjects];
    NSArray *rows = [RDBookshelfPrefetch dataSourceRows];
    NSArray *groups = [RDBookshelfPrefetch bookGroups];
    if (rows) {
        [self.dataSource addObjectsFromArray:rows];
    }
    if (groups) {
        [self.bookSource addObjectsFromArray:groups];
    }
    self.didApplyPrefetch = YES;
    [self.tableView reloadData];
}

-(void)p_reload
{
    if (self.isReloading) {
        // 已有刷新在跑:记下"还需要再刷一次",完成后自动补跑,不丢失这次请求(P1-09)。
        // 例如批量导入时前一本书的通知触发的刷新还没完成,后一本书的通知就到了。
        self.pendingReload = YES;
        return;
    }
    self.isReloading = YES;
    self.pendingReload = NO;
    // 读库放到后台,主线程只做组装与刷新;代次保证较慢完成的旧一轮不会覆盖更新的结果。
    NSInteger columns = kItemCount;
    NSUInteger generation = [RDBookshelfPrefetch beginRefreshGeneration];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSArray *books = [RDReadRecordManager getBookshelfDisplayList];
        if (!books) {
            // 查询失败:保留当前展示内容并提示可重试,绝不提交空快照把
            // 数据库错误显示成"一日无书"(P1-07 书架错误态)。
            dispatch_async(dispatch_get_main_queue(), ^{
                self.isReloading = NO;
                if (self.isViewLoaded && self.view.window) {
                    [RDToastView showText:@"书架读取失败,请稍后重试" delay:1.5 inView:self.view];
                }
                if (self.pendingReload) {
                    self.pendingReload = NO;
                    [self p_reload];
                }
            });
            return;
        }
        [RDLocalBookManager preparePDFCoversForBooks:books];
        [RDBookshelfPrefetch commitBooks:books columns:columns generation:generation];
        dispatch_async(dispatch_get_main_queue(), ^{
            self.isReloading = NO;
            if (!self.isViewLoaded) {
                if (self.pendingReload) {
                    self.pendingReload = NO;
                    [self p_reload];
                }
                return;
            }
            // 无论这份是否被更新的一轮抢先提交,dataSourceRows/bookGroups 都是当前
            // 已提交的最新快照,直接读出来展示即可。
            NSArray *rows = [RDBookshelfPrefetch dataSourceRows];
            NSArray *groups = [RDBookshelfPrefetch bookGroups];
            [self.dataSource removeAllObjects];
            [self.bookSource removeAllObjects];
            if (groups) {
                [self.bookSource addObjectsFromArray:groups];
            }
            if (rows) {
                [self.dataSource addObjectsFromArray:rows];
            }
            self.didApplyPrefetch = YES;
            [self.tableView reloadData];
            if (self.pendingReload) {
                self.pendingReload = NO;
                [self p_reload];
            }
        });
    });
}

-(void)viewDidLayoutSubviews
{
    [super viewDidLayoutSubviews];
    self.tableView.frame = CGRectMake(0, self.topView.bottom, self.view.width, self.view.height-self.topView.bottom);
}
@end
