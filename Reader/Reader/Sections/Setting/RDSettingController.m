//
//  RDSettingController.m
//  Reader
//

#import "RDSettingController.h"
#import "RDLocalBookManager.h"
#import "RDBookDetailModel.h"
#import "RDReadRecordManager.h"
#import "RDCharpterDataManager.h"
#import "LEEAlert.h"
#import "RDFontManager.h"
#import "RDBackupManager.h"
#import "RDAIConfigController.h"
#import "RDAIConfig.h"
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import "AppDelegate.h"
#import "RDMainController.h"

typedef NS_ENUM(NSInteger, RDSettingRow) {
    RDSettingRowImport = 0,
    RDSettingRowImportFont,
    RDSettingRowStorage,
    RDSettingRowClear,
    RDSettingRowAIConfig,
    RDSettingRowBackup,
    RDSettingRowRestore,
    RDSettingRowVersion,
};

@interface RDSettingController ()<UITableViewDelegate, UITableViewDataSource, UIDocumentPickerDelegate>
@property (nonatomic,strong) UITableView *tableView;
@property (nonatomic,strong) NSArray <NSArray <NSNumber *>*>*sections;
@property (nonatomic,copy) NSString *storageText;
@end

@implementation RDSettingController

- (void)viewDidLoad
{
    [super viewDidLoad];
    //书籍一组,AI 一组,备份一组,关于一组
    self.sections = @[@[@(RDSettingRowImport), @(RDSettingRowImportFont), @(RDSettingRowStorage), @(RDSettingRowClear)],
                      @[@(RDSettingRowAIConfig)],
                      @[@(RDSettingRowBackup), @(RDSettingRowRestore)],
                      @[@(RDSettingRowVersion)]];
    [self.view addSubview:self.topView];
    [self.view addSubview:self.tableView];
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    [self p_refreshStorage];
}

- (RDTopView *)topView
{
    if (!_topView) {
        _topView = [[RDTopView alloc] init];
        _topView.titleLabel.text = @"设置";
        _topView.titleLabel.font = RDTitleFont19;
    }
    return _topView;
}

- (UITableView *)tableView
{
    if (!_tableView) {
        _tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStyleInsetGrouped];
        _tableView.backgroundColor = RDBackgroudColor;
        _tableView.separatorColor = RDLightSeparatorColor;
        _tableView.delegate = self;
        _tableView.dataSource = self;
        _tableView.rowHeight = 54;
        _tableView.sectionHeaderHeight = 12;
        _tableView.sectionFooterHeight = 12;
    }
    return _tableView;
}

- (void)viewDidLayoutSubviews
{
    [super viewDidLayoutSubviews];
    self.tableView.frame = CGRectMake(0, self.topView.bottom, self.view.width, self.view.height - self.topView.bottom);
}

#pragma mark - 数据

- (void)p_refreshStorage
{
    dispatch_async(dispatch_get_global_queue(0, 0), ^{
        NSArray *books = [RDReadRecordManager getAllOnBookshelf];
        NSUInteger count = books.count;
        unsigned long long bytes = 0;
        NSString *dir = [PATH_DOCUMENT stringByAppendingPathComponent:@"LocalBooks"];
        NSDirectoryEnumerator *enumerator = [[NSFileManager defaultManager] enumeratorAtPath:dir];
        for (NSString *file in enumerator) {
            NSDictionary *attrs = [[NSFileManager defaultManager] attributesOfItemAtPath:[dir stringByAppendingPathComponent:file] error:nil];
            bytes += attrs.fileSize;
        }
        //数据库(章节内容)也计入
        NSString *dbPath = [PATH_DOCUMENT stringByAppendingPathComponent:@"book"];
        NSDictionary *dbAttrs = [[NSFileManager defaultManager] attributesOfItemAtPath:dbPath error:nil];
        bytes += dbAttrs.fileSize;

        NSString *size = [NSByteCountFormatter stringFromByteCount:bytes countStyle:NSByteCountFormatterCountStyleFile];
        dispatch_async(dispatch_get_main_queue(), ^{
            self.storageText = [NSString stringWithFormat:@"%@ 本 · %@", @(count), size];
            [self.tableView reloadData];
        });
    });
}

- (NSString *)p_version
{
    NSString *version = [NSBundle mainBundle].infoDictionary[@"CFBundleShortVersionString"] ?: @"1.0";
    NSString *build = [NSBundle mainBundle].infoDictionary[@"CFBundleVersion"] ?: @"";
    return build.length > 0 ? [NSString stringWithFormat:@"%@ (%@)", version, build] : version;
}

#pragma mark - UITableViewDataSource

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
    return self.sections.count;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    return self.sections[section].count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    static NSString *identifier = @"RDSettingCell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:identifier];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:identifier];
        cell.backgroundColor = RDSurfaceColor;
        cell.textLabel.font = RDFont16;
        cell.textLabel.textColor = RDBlackColor;
        cell.detailTextLabel.font = RDFont14;
        cell.detailTextLabel.textColor = RDLightGrayColor;
    }
    cell.accessoryType = UITableViewCellAccessoryNone;
    cell.selectionStyle = UITableViewCellSelectionStyleDefault;
    cell.detailTextLabel.text = nil;
    cell.textLabel.textColor = RDBlackColor;

    RDSettingRow row = self.sections[indexPath.section][indexPath.row].integerValue;
    switch (row) {
        case RDSettingRowImport:
            cell.textLabel.text = @"导入本地书籍";
            cell.detailTextLabel.text = @"txt · epub · mobi · pdf";
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
            break;
        case RDSettingRowImportFont:
            cell.textLabel.text = @"导入阅读字体";
            cell.detailTextLabel.text = @"ttf · otf";
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
            break;
        case RDSettingRowStorage:
            cell.textLabel.text = @"本地存储";
            cell.detailTextLabel.text = self.storageText ?: @"统计中…";
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
            break;
        case RDSettingRowClear:
            cell.textLabel.text = @"清空书架";
            cell.textLabel.textColor = [UIColor systemRedColor];
            break;
        case RDSettingRowAIConfig: {
            cell.textLabel.text = @"AI 配置";
            RDAIConfigProfile *active = [[RDAIConfigStore sharedInstance] activeProfile];
            if (active.isUsable) {
                NSString *label = active.name.length > 0 ? active.name : active.type;
                cell.detailTextLabel.text = [NSString stringWithFormat:@"%@ · %@", label, active.model ?: @""];
            } else if (active) {
                cell.detailTextLabel.text = @"未完成配置";
            } else {
                cell.detailTextLabel.text = @"OpenAI · Anthropic · Gemini";
            }
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
            break;
        }
        case RDSettingRowBackup:
            cell.textLabel.text = @"备份到文件";
            cell.detailTextLabel.text = @"书籍 · 进度 · 设置 · AI(不含密钥)";
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
            break;
        case RDSettingRowRestore:
            cell.textLabel.text = @"从备份恢复";
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
            break;
        case RDSettingRowVersion:
            cell.textLabel.text = @"版本";
            cell.detailTextLabel.text = [self p_version];
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
            break;
    }
    return cell;
}

#pragma mark - UITableViewDelegate

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    RDSettingRow row = self.sections[indexPath.section][indexPath.row].integerValue;
    if (row == RDSettingRowImport) {
        [[NSNotificationCenter defaultCenter] postNotificationName:RDLocalBookImportRequestNotification object:nil];
        [RDAppDelegate.mainController setSelectedIndex:RDMainBookShelf];
    }
    else if (row == RDSettingRowImportFont) {
        [self p_pickFont];
    }
    else if (row == RDSettingRowClear) {
        [self p_confirmClear];
    }
    else if (row == RDSettingRowAIConfig) {
        RDAIConfigController *ai = [[RDAIConfigController alloc] init];
        [self.navigationController pushViewController:ai animated:YES];
    }
    else if (row == RDSettingRowBackup) {
        [self p_backup];
    }
    else if (row == RDSettingRowRestore) {
        [self p_pickRestore];
    }
}

#pragma mark - 备份与恢复

- (void)p_backup
{
    [self showLoading:@"正在生成备份..." cancel:nil];
    [RDBackupManager createBackupWithComplete:^(NSString *zipPath, NSString *errorMessage) {
        [self hideLoading];
        if (!zipPath) {
            [self showText:errorMessage ?: @"备份失败"];
            return;
        }
        if (![[NSFileManager defaultManager] fileExistsAtPath:zipPath]) {
            [self showText:@"备份文件不存在"];
            return;
        }
        // 写在 Caches/Exports 下的 fileURL;比 tmp 更适合系统分享
        NSURL *fileURL = [NSURL fileURLWithPath:zipPath isDirectory:NO];
        [fileURL setResourceValue:@(YES) forKey:NSURLIsExcludedFromBackupKey error:nil];
        UIActivityViewController *activity = [[UIActivityViewController alloc] initWithActivityItems:@[fileURL] applicationActivities:nil];
        activity.popoverPresentationController.sourceView = self.view;
        activity.popoverPresentationController.sourceRect = CGRectMake(self.view.width / 2, self.view.height / 2, 1, 1);
        [self presentViewController:activity animated:YES completion:nil];
    }];
}

- (void)p_pickRestore
{
    UTType *zip = [UTType typeWithFilenameExtension:@"zip"];
    UIDocumentPickerViewController *picker = [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:zip ? @[zip] : @[] asCopy:YES];
    picker.delegate = self;
    picker.allowsMultipleSelection = NO;
    [self presentViewController:picker animated:YES completion:nil];
}

#pragma mark - 字体导入

- (void)p_pickFont
{
    NSMutableArray <UTType *>*types = [NSMutableArray array];
    for (NSString *ext in @[@"ttf", @"otf", @"ttc"]) {
        UTType *type = [UTType typeWithFilenameExtension:ext];
        if (type && ![types containsObject:type]) {
            [types addObject:type];
        }
    }
    UIDocumentPickerViewController *picker = [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:types asCopy:YES];
    picker.delegate = self;
    picker.allowsMultipleSelection = NO;
    [self presentViewController:picker animated:YES completion:nil];
}

- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls
{
    NSURL *url = urls.firstObject;
    if (!url) {
        return;
    }
    //同一个 picker 回调,按扩展名分流:zip → 恢复备份,其余 → 字体
    if ([url.pathExtension.lowercaseString isEqualToString:@"zip"]) {
        [self showLoading:@"正在恢复备份..." cancel:nil];
        [RDBackupManager restoreFromURL:url complete:^(NSInteger bookCount, NSString *errorMessage) {
            [self hideLoading];
            if (bookCount > 0) {
                NSString *text = [NSString stringWithFormat:@"已恢复 %@ 本书", @(bookCount)];
                if (errorMessage) {
                    text = [text stringByAppendingFormat:@"(部分失败:%@)", errorMessage];
                }
                [self showText:text];
                [self p_refreshStorage];
            }
            else{
                [self showText:errorMessage ?: @"恢复失败"];
            }
        }];
        return;
    }
    [self showLoading:@"正在导入字体..." cancel:nil];
    [[RDFontManager sharedInstance] importFontAtURL:url complete:^(RDFontOption *option, NSString *errorMessage) {
        [self hideLoading];
        if (option) {
            [self showText:[NSString stringWithFormat:@"字体「%@」已可在阅读设置中选择", option.displayName]];
        }
        else{
            [self showText:errorMessage ?: @"导入失败"];
        }
    }];
}

- (void)p_confirmClear
{
    __weak typeof(self) weakSelf = self;
    [LEEAlert alert].config
    .LeeTitle(@"清空书架")
    .LeeContent(@"将删除全部书籍、章节缓存与阅读进度,且无法恢复。")
    .LeeAddAction(^(LEEAction *action) {
        action.type = LEEActionTypeCancel;
        action.title = @"取消";
        action.titleColor = RDGrayColor;
    })
    .LeeAddAction(^(LEEAction *action) {
        action.type = LEEActionTypeDestructive;
        action.title = @"清空";
        action.titleColor = [UIColor systemRedColor];
        [action setClickBlock:^{
            [weakSelf p_clearAll];
        }];
    })
    .LeeShow();
}

- (void)p_clearAll
{
    NSArray *books = [RDReadRecordManager getAllOnBookshelf];
    for (RDBookDetailModel *book in books) {
        if (book.isLocalBook) {
            [RDLocalBookManager removeLocalBook:book];
        }
        else{
            [RDReadRecordManager removeBookFromBookShelfWithBookId:book.bookId];
            [RDCharpterDataManager deleteAllCharpterWithBookId:book.bookId];
        }
    }
    [self showText:@"书架已清空"];
    [self p_refreshStorage];
    [[NSNotificationCenter defaultCenter] postNotificationName:RDLocalBookImportedNotification object:nil];
}

@end
