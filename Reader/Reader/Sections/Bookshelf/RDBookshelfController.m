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
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>


#import "RDCharpterModel.h"

#define kItemCount ([RDUtilities iPad] ? 5 : 3)

@interface RDBookshelfController ()<UIDocumentPickerDelegate>
@property (nonatomic,strong) NSMutableArray *dataSource;
@property (nonatomic,strong) UITableView *tableView;
@property (nonatomic,strong) NSMutableArray *bookSource;
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

#pragma mark - 本地导入

-(void)importAction
{
    NSMutableArray <UTType *>*types = [NSMutableArray array];
    [types addObject:UTTypePlainText];
    [types addObject:UTTypePDF];
    UTType *epub = [UTType typeWithIdentifier:@"org.idpf.epub-container"];
    if (epub) {
        [types addObject:epub];
    }
    for (NSString *ext in @[@"epub", @"mobi", @"azw", @"txt"]) {
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
                [self p_reload];
            }
        }];
    }
}
-(void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
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
        // 第一行不要贴顶:顶部留白 + 底部分页安全区
        _tableView.contentInset = UIEdgeInsetsMake(18, 0, 24, 0);
        _tableView.scrollIndicatorInsets = _tableView.contentInset;
        if (@available(iOS 15.0, *)) {
            _tableView.sectionHeaderTopPadding = 0;
        }
    }
    return _tableView;
}
-(NSMutableArray *)dataSource{
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

        UIButton *importBtn = [[UIButton alloc] init];
        [importBtn setTitle:@"导入" forState:UIControlStateNormal];
        [importBtn setTitleColor:RDAccentColor forState:UIControlStateNormal];
        [importBtn setTitleColor:[RDAccentColor colorWithAlphaComponent:0.5] forState:UIControlStateHighlighted];
        importBtn.titleLabel.font = RDFont15;
        [importBtn addTarget:self action:@selector(importAction) forControlEvents:UIControlEventTouchUpInside];
        [_topView addRightBtn:importBtn];
    }

    return _topView;
}

#pragma mark - Delegate

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    return self.dataSource.count;
}

-(UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    id model = [self.dataSource objectAtIndexSafely:indexPath.row];
    if ([model isKindOfClass:[NSString class]] && [model isEqualToString:@"RDBookshelfNoneCell"]) {
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
            [cell setNeedReload:^{
                [weakSelf p_reload];
            }];
        }
        cell.books = model;
        return cell;
    }
    
    return [UITableViewCell new];
}
- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath
{
    id model = [self.dataSource objectAtIndexSafely:indexPath.row];
    if ([model isKindOfClass:[NSString class]] && [model isEqualToString:@"RDBookshelfNoneCell"]){
        return ScreenHeight-[UIView navigationBar]-[UIView tarBar]-[UIView statusBar];
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
    lab.text = [NSString stringWithFormat:@"共 %@ 本 · 长按书籍可分享、改名、删除", @(count)];
    [header addSubview:lab];
    return header;
}

- (CGFloat)tableView:(UITableView *)tableView heightForFooterInSection:(NSInteger)section {
    return CGFLOAT_MIN;
}
#pragma mark - action

-(void)p_reload
{
    // 读库放到后台,主线程只做组装与刷新,缩短启动与返回书架卡顿
    NSInteger columns = kItemCount;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSArray *books = [RDReadRecordManager getAllOnBookshelf];
        NSMutableArray *rows = [NSMutableArray array];
        NSMutableArray *groups = [NSMutableArray array];
        if (books.count == 0) {
            [rows addObject:@"RDBookshelfNoneCell"];
        } else {
            NSMutableArray *array = nil;
            for (NSInteger i = 0; i < (NSInteger)books.count; i++) {
                if (i % columns == 0) {
                    array = [NSMutableArray array];
                    [groups addObject:array];
                }
                [array addObject:books[i]];
            }
            [rows addObjectsFromArray:groups];
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            if (!self.isViewLoaded) {
                return;
            }
            [self.dataSource removeAllObjects];
            [self.bookSource removeAllObjects];
            [self.bookSource addObjectsFromArray:groups];
            [self.dataSource addObjectsFromArray:rows];
            [self.tableView reloadData];
        });
    });
}

-(void)viewDidLayoutSubviews
{
    [super viewDidLayoutSubviews];
    self.tableView.frame = CGRectMake(0, self.topView.bottom, self.view.width, self.view.height-self.topView.bottom);
}
@end
