//
//  RDVoicePickerController.m
//  Reader
//

#import "RDVoicePickerController.h"
#import "RDVoiceManager.h"
#import "RDHttpTTS.h"
#import "RDPaperAlert.h"
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

@interface RDVoicePickerController () <UITableViewDelegate, UITableViewDataSource, UIDocumentPickerDelegate>
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, copy) NSArray <NSDictionary *>*groups;
@property (nonatomic, strong) UIActivityIndicatorView *spinner;
@property (nonatomic, assign) BOOL loading;
@end

@implementation RDVoicePickerController

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.topView.titleLabel.text = @"朗读语音";
    [self p_setupNavActions];
    [self.view addSubview:self.topView];
    [self.view addSubview:self.tableView];
    [self.view addSubview:self.spinner];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(p_reload)
                                                 name:RDVoiceListChangedNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(p_reload)
                                                 name:RDPreferredVoiceChangedNotification
                                               object:nil];
    // 首屏不阻塞:speechVoices 放到后台
    [self p_reload];
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [[RDVoiceManager sharedInstance] stopPreview];
}

- (void)p_setupNavActions
{
    UIButton *more = [UIButton buttonWithType:UIButtonTypeSystem];
    [more setTitle:@"导入" forState:UIControlStateNormal];
    more.titleLabel.font = RDFont16;
    [more addTarget:self action:@selector(showImportMenu) forControlEvents:UIControlEventTouchUpInside];
    more.translatesAutoresizingMaskIntoConstraints = NO;
    [self.topView addSubview:more];
    [NSLayoutConstraint activateConstraints:@[
        [more.trailingAnchor constraintEqualToAnchor:self.topView.trailingAnchor constant:-16],
        [more.centerYAnchor constraintEqualToAnchor:self.topView.titleLabel.centerYAnchor],
    ]];
}

- (void)viewDidLayoutSubviews
{
    [super viewDidLayoutSubviews];
    self.tableView.frame = CGRectMake(0, self.topView.bottom, self.view.width, self.view.height - self.topView.bottom);
    self.spinner.center = CGPointMake(self.view.width / 2, self.view.height / 2);
}

- (UITableView *)tableView
{
    if (!_tableView) {
        _tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStyleInsetGrouped];
        _tableView.backgroundColor = RDBackgroudColor;
        _tableView.delegate = self;
        _tableView.dataSource = self;
        _tableView.rowHeight = 58;
    }
    return _tableView;
}

- (UIActivityIndicatorView *)spinner
{
    if (!_spinner) {
        _spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
        _spinner.hidesWhenStopped = YES;
    }
    return _spinner;
}

- (void)p_reload
{
    if (self.loading) {
        return;
    }
    self.loading = YES;
    if (self.groups.count == 0) {
        [self.spinner startAnimating];
    }
    __weak typeof(self) weakSelf = self;
    [[RDVoiceManager sharedInstance] loadGroupedOptions:^(NSArray<NSDictionary *> *groups) {
        weakSelf.loading = NO;
        [weakSelf.spinner stopAnimating];
        weakSelf.groups = groups;
        [weakSelf.tableView reloadData];
    }];
}

#pragma mark - Import menu

- (void)showImportMenu
{
    // 说明区(非按钮) + 选项副标题;点选后直接进入对应界面,不再叠第二层废话弹窗
    __weak typeof(self) weakSelf = self;
    [RDPaperAlert showActionSheetWithTitle:@"导入与管理"
                                   message:@"点选后直接进入对应流程。支持:本机语音收藏配置、阅读/legado 在线朗读引擎(HttpTTS) JSON,或跳转系统下载增强语音。"
                                   actions:@[
        [RDPaperAlertAction actionWithTitle:@"导入配置 / HttpTTS"
                                   subtitle:@"JSON · 本机收藏配置或阅读在线引擎"
                                      style:RDPaperAlertActionStyleDefault
                                    handler:^{
            [weakSelf p_pickConfig];
        }],
        [RDPaperAlertAction actionWithTitle:@"下载系统增强语音"
                                   subtitle:@"跳转系统「朗读内容 → 声音」"
                                      style:RDPaperAlertActionStyleDefault
                                    handler:^{
            [[RDVoiceManager sharedInstance] openSystemVoiceDownloadHelp];
        }],
        [RDPaperAlertAction actionWithTitle:@"导出当前配置"
                                   subtitle:@"生成 JSON 并用系统分享面板发出"
                                      style:RDPaperAlertActionStyleDefault
                                    handler:^{
            [weakSelf p_exportConfig];
        }],
        [RDPaperAlertAction actionWithTitle:@"刷新语音列表"
                                   subtitle:@"重新扫描本机可用 TTS 语音"
                                      style:RDPaperAlertActionStyleDefault
                                    handler:^{
            [weakSelf p_reload];
            [weakSelf showText:@"已刷新"];
        }],
    ]];
}

- (void)p_pickConfig
{
    // 关表后下一 runloop 再 present 文件选择器,避免与纸感遮罩叠层抢 present
    UTType *json = [UTType typeWithFilenameExtension:@"json"] ?: UTTypeJSON;
    UIDocumentPickerViewController *picker = [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:@[json] asCopy:YES];
    picker.delegate = self;
    picker.allowsMultipleSelection = NO;
    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_main_queue(), ^{
        [weakSelf presentViewController:picker animated:YES completion:nil];
    });
}

- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls
{
    NSURL *url = urls.firstObject;
    if (!url) {
        return;
    }
    NSError *err = nil;
    // 优先 HttpTTS;再本机收藏配置
    NSData *data = nil;
    BOOL access = [url startAccessingSecurityScopedResource];
    data = [NSData dataWithContentsOfURL:url];
    if (access) {
        [url stopAccessingSecurityScopedResource];
    }
    NSInteger ttsN = data.length ? [[RDHttpTTSStore sharedInstance] importJSONData:data error:&err] : 0;
    if (ttsN > 0) {
        [self showText:[NSString stringWithFormat:@"已导入 %ld 个在线朗读引擎", (long)ttsN]];
        [self p_reload];
        return;
    }
    if ([[RDVoiceManager sharedInstance] importConfigFromURL:url error:&err]) {
        [self showText:@"语音配置已导入"];
        [self p_reload];
    } else {
        [self showText:err.localizedDescription ?: @"导入失败"];
    }
}

- (void)p_exportConfig
{
    NSError *err = nil;
    NSURL *url = [[RDVoiceManager sharedInstance] exportConfigToCachesError:&err];
    if (!url) {
        [self showText:err.localizedDescription ?: @"导出失败"];
        return;
    }
    UIActivityViewController *avc = [[UIActivityViewController alloc] initWithActivityItems:@[url] applicationActivities:nil];
    avc.popoverPresentationController.sourceView = self.view;
    [self presentViewController:avc animated:YES completion:nil];
}

#pragma mark - Table

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
    return self.groups.count;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    NSArray *items = self.groups[section][@"items"];
    return items.count;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section
{
    return self.groups[section][@"title"];
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section
{
    if (section == 0) {
        return @"点选设为默认;侧滑可收藏/试听。右上角「导入」可导入配置文件或下载系统增强语音。";
    }
    return nil;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    static NSString *cid = @"voice";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:cid];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:cid];
        cell.textLabel.font = RDFont16;
        cell.detailTextLabel.font = RDFont12;
        cell.detailTextLabel.textColor = RDLightGrayColor;
        cell.detailTextLabel.numberOfLines = 2;
    }
    RDVoiceOption *opt = self.groups[indexPath.section][@"items"][indexPath.row];
    cell.textLabel.text = opt.displayName;
    cell.detailTextLabel.text = opt.detail;
    cell.accessoryType = opt.isPreferred ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
    cell.tintColor = RDAccentColor;
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    RDVoiceOption *opt = self.groups[indexPath.section][@"items"][indexPath.row];
    NSString *ident = opt.identifier.length ? opt.identifier : nil;
    [[RDVoiceManager sharedInstance] setPreferredIdentifier:ident];
    [[RDVoiceManager sharedInstance] previewIdentifier:opt.identifier ?: @""];
    [self p_reload];
    [self showText:[NSString stringWithFormat:@"已选择：%@", opt.displayName]];
}

- (UISwipeActionsConfiguration *)tableView:(UITableView *)tableView trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath
{
    RDVoiceOption *opt = self.groups[indexPath.section][@"items"][indexPath.row];
    if (opt.identifier.length == 0) {
        return nil;
    }
    __weak typeof(self) weakSelf = self;
    BOOL fav = [[RDVoiceManager sharedInstance] isFavorite:opt.identifier];
    UIContextualAction *star = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleNormal
                                                                       title:fav ? @"取消收藏" : @"收藏导入"
                                                                     handler:^(__kindof UIContextualAction *action, __kindof UIView *sourceView, void (^completionHandler)(BOOL)) {
        [[RDVoiceManager sharedInstance] toggleFavoriteIdentifier:opt.identifier];
        [weakSelf p_reload];
        completionHandler(YES);
    }];
    star.backgroundColor = fav ? RDGrayColor : RDAccentColor;

    UIContextualAction *preview = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleNormal
                                                                          title:@"试听"
                                                                        handler:^(__kindof UIContextualAction *action, __kindof UIView *sourceView, void (^completionHandler)(BOOL)) {
        [[RDVoiceManager sharedInstance] previewIdentifier:opt.identifier];
        completionHandler(YES);
    }];
    preview.backgroundColor = [UIColor systemBlueColor];
    return [UISwipeActionsConfiguration configurationWithActions:@[star, preview]];
}

@end
