//
//  RDSettingController.m
//  Reader
//

#import "RDSettingController.h"
#import "RDLocalBookManager.h"
#import "RDLibraryMutationCoordinator.h"
#import "RDBookDetailModel.h"
#import "RDReadRecordManager.h"
#import "RDCharpterDataManager.h"
#import "RDHistoryRecordManager.h"
#import "RDBookmarkManager.h"
#import "LEEAlert.h"
#import "RDFontManager.h"
#import "RDBackupManager.h"
#import "RDAIConfigController.h"
#import "RDAIConfig.h"
#import "RDReplaceRulesController.h"
#import "RDVoicePickerController.h"
#import "RDLegalDocumentController.h"
#import "RDVoiceManager.h"
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import "AppDelegate.h"
#import "RDMainController.h"

typedef NS_ENUM(NSInteger, RDSettingRow) {
    RDSettingRowImport = 0,
    RDSettingRowImportFont,
    RDSettingRowStorage,
    RDSettingRowClear,
    RDSettingRowAIConfig,
    RDSettingRowPurify,
    RDSettingRowDictionary,
    RDSettingRowTTSVoice,
    RDSettingRowBackup,
    RDSettingRowRestore,
    RDSettingRowPrivacy,
    RDSettingRowOpenSource,
    RDSettingRowVersion,
};

@interface RDSettingController ()<UITableViewDelegate, UITableViewDataSource, UIDocumentPickerDelegate>
@property (nonatomic,strong) UITableView *tableView;
@property (nonatomic,strong) NSArray <NSArray <NSNumber *>*>*sections;
@property (nonatomic,copy) NSString *storageText;
@property (nonatomic,copy) NSString *aiDetailText;
@property (nonatomic,copy) NSString *voiceDetailText;
@property (nonatomic,assign) BOOL storageRefreshing;
@property (nonatomic,assign) BOOL storageRefreshPending;
@property (nonatomic,assign) BOOL detailsLoadedOnce;
@end

@implementation RDSettingController

- (void)viewDidLoad
{
    [super viewDidLoad];
    // 书籍 / 阅读增强 / 备份 / 关于（隐私声明 · 开源声明 · 版本）
    self.sections = @[@[@(RDSettingRowImport), @(RDSettingRowImportFont), @(RDSettingRowStorage), @(RDSettingRowClear)],
                      @[@(RDSettingRowAIConfig), @(RDSettingRowPurify), @(RDSettingRowDictionary), @(RDSettingRowTTSVoice)],
                      @[@(RDSettingRowBackup), @(RDSettingRowRestore)],
                      @[@(RDSettingRowPrivacy), @(RDSettingRowOpenSource), @(RDSettingRowVersion)]];
    self.storageText = @"…";
    self.aiDetailText = @"OpenAI · Anthropic · Gemini";
    self.voiceDetailText = @"自动(中文)";
    [self.view addSubview:self.topView];
    [self.view addSubview:self.tableView];
    // 首屏只用占位文案出表;重活放到 view 出现后的下一帧,避免卡 Tab
    dispatch_async(dispatch_get_main_queue(), ^{
        [self p_refreshDetailsAsync];
    });
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    // 首次已在 viewDidLoad 排队刷新;之后返回再刷
    if (!self.detailsLoadedOnce) {
        return;
    }
    [self p_refreshDetailsAsync];
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

- (void)p_refreshDetailsAsync
{
    self.detailsLoadedOnce = YES;
    // AI / 语音 / 存储统计全部后台,主线程只更新文案。
    // 扫描期间再次请求不能直接丢弃(清空/恢复/改 AI 配置都会触发),
    // 记 pending,本轮结束后补跑一次,否则页面一直停在旧数字(P2-04)。
    if (self.storageRefreshing) {
        self.storageRefreshPending = YES;
        return;
    }
    self.storageRefreshing = YES;
    self.storageRefreshPending = NO;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        // 首次访问会读盘/Keychain,放后台
        RDAIConfigProfile *active = [[RDAIConfigStore sharedInstance] activeProfile];
        NSString *aiText = nil;
        if (active.isUsable) {
            NSString *label = active.name.length > 0 ? active.name : active.type;
            aiText = [NSString stringWithFormat:@"%@ · %@", label, active.model ?: @""];
        } else if (active) {
            aiText = @"未完成配置";
        } else {
            aiText = @"OpenAI · Anthropic · Gemini";
        }
        NSString *voiceText = [[RDVoiceManager sharedInstance] preferredDisplayName];

        NSInteger count = [RDReadRecordManager countOnBookshelf];
        unsigned long long bytes = 0;
        NSString *dir = [PATH_DOCUMENT stringByAppendingPathComponent:@"LocalBooks"];
        NSDirectoryEnumerator *enumerator = [[NSFileManager defaultManager] enumeratorAtPath:dir];
        for (NSString *file in enumerator) {
            @autoreleasepool {
                NSDictionary *attrs = [enumerator fileAttributes];
                if (!attrs) {
                    attrs = [[NSFileManager defaultManager] attributesOfItemAtPath:[dir stringByAppendingPathComponent:file] error:nil];
                }
                bytes += attrs.fileSize;
            }
        }
        NSString *dbPath = [PATH_DOCUMENT stringByAppendingPathComponent:@"book"];
        NSDictionary *dbAttrs = [[NSFileManager defaultManager] attributesOfItemAtPath:dbPath error:nil];
        bytes += dbAttrs.fileSize;
        for (NSString *suf in @[@"-wal", @"-shm"]) {
            NSDictionary *a = [[NSFileManager defaultManager] attributesOfItemAtPath:[dbPath stringByAppendingString:suf] error:nil];
            bytes += a.fileSize;
        }
        NSString *size = [NSByteCountFormatter stringFromByteCount:bytes countStyle:NSByteCountFormatterCountStyleFile];
        NSString *storageText = [NSString stringWithFormat:@"%@ 本 · %@", @(count), size];

        dispatch_async(dispatch_get_main_queue(), ^{
            self.storageRefreshing = NO;
            BOOL changed = NO;
            if (![self.aiDetailText isEqualToString:aiText]) {
                self.aiDetailText = aiText;
                changed = YES;
            }
            if (![self.voiceDetailText isEqualToString:voiceText]) {
                self.voiceDetailText = voiceText;
                changed = YES;
            }
            if (![self.storageText isEqualToString:storageText]) {
                self.storageText = storageText;
                changed = YES;
            }
            if (changed) {
                [self p_reloadDetailRows];
                [self p_reloadRow:RDSettingRowStorage];
            }
            if (self.storageRefreshPending) {
                self.storageRefreshPending = NO;
                [self p_refreshDetailsAsync];
            }
        });
    });
}

/// 兼容旧调用
- (void)p_refreshStorage
{
    [self p_refreshDetailsAsync];
}

- (NSIndexPath *)p_indexPathForRow:(RDSettingRow)row
{
    for (NSInteger s = 0; s < (NSInteger)self.sections.count; s++) {
        NSArray *rows = self.sections[s];
        for (NSInteger r = 0; r < (NSInteger)rows.count; r++) {
            if ([rows[r] integerValue] == row) {
                return [NSIndexPath indexPathForRow:r inSection:s];
            }
        }
    }
    return nil;
}

- (void)p_reloadRow:(RDSettingRow)row
{
    NSIndexPath *ip = [self p_indexPathForRow:row];
    if (!ip || !self.tableView.window) {
        return;
    }
    [self.tableView reloadRowsAtIndexPaths:@[ip] withRowAnimation:UITableViewRowAnimationNone];
}

- (void)p_reloadDetailRows
{
    // 未入窗或首次:整表一次即可,避免 reloadRows 在空表上异常
    if (!self.isViewLoaded || !self.tableView.window) {
        if (self.isViewLoaded) {
            [self.tableView reloadData];
        }
        return;
    }
    NSMutableArray *paths = [NSMutableArray array];
    for (NSNumber *n in @[@(RDSettingRowAIConfig), @(RDSettingRowTTSVoice)]) {
        NSIndexPath *ip = [self p_indexPathForRow:n.integerValue];
        if (ip) {
            [paths addObject:ip];
        }
    }
    if (paths.count == 0) {
        return;
    }
    @try {
        [self.tableView reloadRowsAtIndexPaths:paths withRowAnimation:UITableViewRowAnimationNone];
    } @catch (__unused NSException *ex) {
        [self.tableView reloadData];
    }
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
            cell.detailTextLabel.text = @"txt · epub · mobi · pdf · zip/cbz · 图片文件夹";
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
            cell.detailTextLabel.text = self.aiDetailText;
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
            break;
        }
        case RDSettingRowPurify:
            cell.textLabel.text = @"正文净化";
            cell.detailTextLabel.text = @"替换规则 · legado";
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
            break;
        case RDSettingRowDictionary:
            cell.textLabel.text = @"系统词典";
            cell.detailTextLabel.text = @"阅读中查词";
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
            break;
        case RDSettingRowTTSVoice:
            cell.textLabel.text = @"朗读语音";
            cell.detailTextLabel.text = self.voiceDetailText;
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
            break;
        case RDSettingRowBackup:
            cell.textLabel.text = @"备份到文件";
            cell.detailTextLabel.text = @"书籍 · 进度 · 书签 · 字体 · 规则 · AI";
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
            break;
        case RDSettingRowRestore:
            cell.textLabel.text = @"从备份恢复";
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
            break;
        case RDSettingRowPrivacy:
            cell.textLabel.text = @"隐私声明";
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
            break;
        case RDSettingRowOpenSource:
            cell.textLabel.text = @"开源软件使用声明";
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
        // 必须先切到书架、等 tab 切换落地后再请求 picker:
        // 反过来会由尚不可见的 controller 去 present,picker 可能不显示(P2-01)
        [RDAppDelegate.mainController setSelectedIndex:RDMainBookShelf];
        dispatch_async(dispatch_get_main_queue(), ^{
            [[NSNotificationCenter defaultCenter] postNotificationName:RDLocalBookImportRequestNotification object:nil];
        });
    }
    else if (row == RDSettingRowImportFont) {
        [self p_pickFont];
    }
    else if (row == RDSettingRowClear) {
        [self p_confirmClear];
    }
    else if (row == RDSettingRowAIConfig) {
        // 延后一帧再 push,让 deselect 动画先跑完,避免点选卡顿感
        dispatch_async(dispatch_get_main_queue(), ^{
            RDAIConfigController *ai = [[RDAIConfigController alloc] init];
            [self.navigationController pushViewController:ai animated:YES];
        });
    }
    else if (row == RDSettingRowPurify) {
        dispatch_async(dispatch_get_main_queue(), ^{
            RDReplaceRulesController *vc = [[RDReplaceRulesController alloc] init];
            [self.navigationController pushViewController:vc animated:YES];
        });
    }
    else if (row == RDSettingRowDictionary) {
        [RDUtilities presentDictionaryLookupFrom:self initialTerm:nil];
    }
    else if (row == RDSettingRowTTSVoice) {
        dispatch_async(dispatch_get_main_queue(), ^{
            RDVoicePickerController *vc = [[RDVoicePickerController alloc] init];
            [self.navigationController pushViewController:vc animated:YES];
        });
    }
    else if (row == RDSettingRowBackup) {
        [self p_backup];
    }
    else if (row == RDSettingRowRestore) {
        [self p_pickRestore];
    }
    else if (row == RDSettingRowPrivacy) {
        dispatch_async(dispatch_get_main_queue(), ^{
            RDLegalDocumentController *vc = [[RDLegalDocumentController alloc] initWithTitle:@"隐私声明"
                                                                               resourceName:@"PrivacyPolicy.zh-Hans"];
            [self.navigationController pushViewController:vc animated:YES];
        });
    }
    else if (row == RDSettingRowOpenSource) {
        dispatch_async(dispatch_get_main_queue(), ^{
            RDLegalDocumentController *vc = [[RDLegalDocumentController alloc] initWithTitle:@"开源软件使用声明"
                                                                               resourceName:@"OpenSourceLicenses"];
            [self.navigationController pushViewController:vc animated:YES];
        });
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
        if (errorMessage.length > 0) {
            // zip 已生成但存在部分内容缺失/写入失败,不能只提示"成功"却把警告吞掉
            [self showText:[NSString stringWithFormat:@"备份已生成,但%@", errorMessage]];
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
    // 文件与多表删除放后台,几十本书时不冻结 UI
    [self showLoading:@"正在清理..." cancel:nil];
    // 清空与导入/删除/恢复同队列串行,避免与并发导入交叉
    [RDLibraryMutationCoordinator performAsync:^{
        NSArray *books = [RDReadRecordManager getAllOnBookshelf];
        for (RDBookDetailModel *book in books) {
            if (book.isLocalBook) {
                // 本地书由 manager 在同一串行队列内删除记录、源文件与两类封面。
                [RDLocalBookManager removeLocalBook:book];
            }
            else{
                // 在线书先删记录，迟到的封面保存会校验失败，再清理确定性文件。
                [RDReadRecordManager removeBookFromBookShelfWithBookId:book.bookId];
                [RDLocalBookManager removeCustomCoverForBook:book];
                [RDBookmarkManager deleteAllForBookId:book.bookId];
                [RDCharpterDataManager deleteAllCharpterWithBookId:book.bookId];
            }
        }
        [RDHistoryRecordManager deleteAllHistory];
        // removeLocalBook 把章节删除排在本队列后面,完成提示必须再排一轮才不会
        // 早于最后一本书的章节删除(P2-17)。
        [RDLibraryMutationCoordinator performAsync:^{
            dispatch_async(dispatch_get_main_queue(), ^{
                [self hideLoading];
                [self showText:@"书架已清空"];
                [self p_refreshStorage];
                [[NSNotificationCenter defaultCenter] postNotificationName:RDLocalBookImportedNotification object:nil];
            });
        }];
    }];
}

@end
