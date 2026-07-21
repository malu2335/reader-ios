//
//  RDVoicePickerController.m
//  Reader
//

#import "RDVoicePickerController.h"
#import "RDVoiceManager.h"
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
    [more addTarget:self action:@selector(p_showImportMenu) forControlEvents:UIControlEventTouchUpInside];
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
    [self p_showImportMenu];
}

- (void)p_showImportMenu
{
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:@"导入 TTS 语音"
                                                                   message:@"可导入个人声音、语音配置,或引导下载系统增强音"
                                                            preferredStyle:UIAlertControllerStyleActionSheet];
    __weak typeof(self) weakSelf = self;
    [sheet addAction:[UIAlertAction actionWithTitle:@"导入个人声音(系统)" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        [weakSelf p_importPersonalVoice];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"导入语音配置(JSON)" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        [weakSelf p_pickConfig];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"导出当前配置" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        [weakSelf p_exportConfig];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"去系统设置下载增强语音" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        [weakSelf p_helpDownload];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"刷新语音列表" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        [weakSelf p_reload];
        [weakSelf showText:@"已刷新"];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    sheet.popoverPresentationController.sourceView = self.view;
    sheet.popoverPresentationController.sourceRect = CGRectMake(self.view.width - 40, self.topView.bottom, 1, 1);
    [self presentViewController:sheet animated:YES completion:nil];
}

- (void)p_importPersonalVoice
{
    __weak typeof(self) weakSelf = self;
    [[RDVoiceManager sharedInstance] requestPersonalVoiceAccess:^(BOOL granted, NSString *message) {
        [weakSelf showText:message ?: (granted ? @"已授权" : @"授权失败")];
        [weakSelf p_reload];
        if (granted) {
            // 引导用户创建
            UIAlertController *tip = [UIAlertController alertControllerWithTitle:@"个人声音"
                                                                         message:@"若列表为空,请先到系统「设置 → 辅助功能 → 个人声音」创建,再返回本页刷新。"
                                                                  preferredStyle:UIAlertControllerStyleAlert];
            [tip addAction:[UIAlertAction actionWithTitle:@"打开设置" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
                [[RDVoiceManager sharedInstance] openSystemVoiceDownloadHelp];
            }]];
            [tip addAction:[UIAlertAction actionWithTitle:@"好的" style:UIAlertActionStyleCancel handler:nil]];
            [weakSelf presentViewController:tip animated:YES completion:nil];
        }
    }];
}

- (void)p_pickConfig
{
    UTType *json = [UTType typeWithFilenameExtension:@"json"] ?: UTTypeJSON;
    UIDocumentPickerViewController *picker = [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:@[json] asCopy:YES];
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
    NSError *err = nil;
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

- (void)p_helpDownload
{
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"下载系统 TTS 语音"
                                                                   message:@"路径:设置 → 辅助功能 → 朗读内容 → 声音\n下载「中文(普通话)」增强/高级语音后返回本页刷新即可使用。\n\n个人声音:设置 → 辅助功能 → 个人声音"
                                                            preferredStyle:UIAlertControllerStyleAlert];
    __weak typeof(self) weakSelf = self;
    [alert addAction:[UIAlertAction actionWithTitle:@"打开系统设置" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        [[RDVoiceManager sharedInstance] openSystemVoiceDownloadHelp];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"知道了" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
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
        return @"点选设为默认;侧滑可收藏/试听。右上角「导入」可添加个人声音或配置文件。";
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
