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

    //如果异常退出是阅读状态，那么直接打开书籍
    RDBookDetailModel *book = [RDCacheModel sharedInstance].book;
    if(book){
         [RDReadHelper beginReadWithBookDetail:book animation:NO];
    }

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
    __block NSString *lastError = nil;
    for (NSURL *url in urls) {
        [RDLocalBookManager importBookAtURL:url complete:^(RDBookDetailModel *book, NSString *errorMessage) {
            pending--;
            if (book) {
                succeed++;
            }
            else if (errorMessage) {
                lastError = errorMessage;
            }
            if (pending == 0) {
                [self hideLoading];
                if (succeed > 0 && !lastError) {
                    [self showText:[NSString stringWithFormat:@"已导入 %@ 本书", @(succeed)]];
                }
                else if (lastError) {
                    [self showText:succeed > 0 ? [NSString stringWithFormat:@"导入 %@ 本,失败:%@", @(succeed), lastError] : lastError];
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
    return CGFLOAT_MIN;
}

- (CGFloat)tableView:(UITableView *)tableView heightForFooterInSection:(NSInteger)section {
    return CGFLOAT_MIN;
}
#pragma mark - action

-(void)p_reload
{
    [self.dataSource removeAllObjects];
    [self.bookSource removeAllObjects];

    NSArray *books = [RDReadRecordManager getAllOnBookshelf];

    if (books.count == 0) {
        [self.dataSource addObject:@"RDBookshelfNoneCell"];
    }
    else{
        NSMutableArray *array;
        for (int i=0; i<books.count; i++) {
            if (i%kItemCount == 0) {
                array = [NSMutableArray array];
                [self.bookSource addObject:array];
            }
            [array addObject:books[i]];
        }
        [self.dataSource addObjectsFromArray:self.bookSource];
    }
    
    
    [self.tableView reloadData];
}

-(void)viewDidLayoutSubviews
{
    [super viewDidLayoutSubviews];
    self.tableView.frame = CGRectMake(0, self.topView.bottom, self.view.width, self.view.height-self.topView.bottom);
}
@end
