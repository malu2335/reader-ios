//
//  RDReplaceRulesController.m
//  Reader
//
//  正文净化 — legado 风格;弹窗统一 RDPaperAlert 纸感
//

#import "RDReplaceRulesController.h"
#import "RDReplaceRule.h"
#import "RDPaperAlert.h"
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

@interface RDReplaceRulesController () <UITableViewDelegate, UITableViewDataSource, UIDocumentPickerDelegate>
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, copy) NSArray <NSDictionary *>*groups;
@end

@implementation RDReplaceRulesController

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.topView.titleLabel.text = @"正文净化";

    UIButton *ioBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    [ioBtn setTitle:@"导入/导出" forState:UIControlStateNormal];
    ioBtn.titleLabel.font = RDFont16;
    [ioBtn setTitleColor:RDAccentColor forState:UIControlStateNormal];
    [ioBtn addTarget:self action:@selector(p_importExportMenu) forControlEvents:UIControlEventTouchUpInside];
    [self.topView addSubview:ioBtn];
    ioBtn.translatesAutoresizingMaskIntoConstraints = NO;
    [NSLayoutConstraint activateConstraints:@[
        [ioBtn.trailingAnchor constraintEqualToAnchor:self.topView.trailingAnchor constant:-16],
        [ioBtn.centerYAnchor constraintEqualToAnchor:self.topView.titleLabel.centerYAnchor],
    ]];
    [self.view addSubview:self.topView];
    [self.view addSubview:self.tableView];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(p_reload)
                                                 name:RDReplaceRuleImportDidChangeNotification
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
}

- (UITableView *)tableView
{
    if (!_tableView) {
        _tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStyleInsetGrouped];
        _tableView.backgroundColor = RDBackgroudColor;
        _tableView.delegate = self;
        _tableView.dataSource = self;
        _tableView.rowHeight = 68;
    }
    return _tableView;
}

- (void)p_reload
{
    NSArray <RDReplaceRule *>*all = [RDReplaceRuleStore sharedInstance].rules;
    NSMutableDictionary <NSString *, NSMutableArray *>*map = [NSMutableDictionary dictionary];
    NSMutableArray <NSString *>*order = [NSMutableArray array];
    for (RDReplaceRule *r in all) {
        NSString *g = r.groupName.length ? r.groupName : @"未分组";
        if (!map[g]) {
            map[g] = [NSMutableArray array];
            [order addObject:g];
        }
        [map[g] addObject:r];
    }
    NSMutableArray *groups = [NSMutableArray array];
    for (NSString *g in order) {
        [groups addObject:@{@"title": g, @"items": map[g]}];
    }
    self.groups = groups;
    [self.tableView reloadData];
}

- (RDReplaceRule *)p_ruleAtIndexPath:(NSIndexPath *)ip
{
    if (ip.section < 0 || ip.section >= (NSInteger)self.groups.count) {
        return nil;
    }
    NSArray *items = self.groups[ip.section][@"items"];
    if (ip.row < 0 || ip.row >= (NSInteger)items.count) {
        return nil;
    }
    return items[ip.row];
}

#pragma mark - Add / Edit

- (void)p_editRule:(RDReplaceRule *)rule
{
    RDReplaceRule *editing = rule ? [rule copy] : [[RDReplaceRule alloc] init];
    if (!rule) {
        editing.name = @"新规则";
        editing.groupName = @"默认";
        editing.isRegex = YES;
        editing.isEnabled = YES;
        editing.scopeContent = YES;
        editing.scopeTitle = NO;
    }
    __weak typeof(self) weakSelf = self;
    [RDPaperAlert showTextFieldsWithTitle:rule ? @"编辑规则" : @"添加规则"
                                  message:@"纸墨净化 · 兼容阅读 legado。替换为空即删除匹配内容。"
                               fieldSpecs:@[
        @{@"placeholder": @"名称", @"text": editing.name ?: @""},
        @{@"placeholder": @"分组（如 默认 / 广告）", @"text": editing.groupName ?: @""},
        @{@"placeholder": @"匹配内容（正则或原文）", @"text": editing.pattern ?: @""},
        @{@"placeholder": @"替换为（可留空）", @"text": editing.replacement ?: @""},
    ]
                              cancelTitle:@"取消"
                             confirmTitle:@"保存"
                                  confirm:^(NSArray<NSString *> *values) {
        editing.name = values.count > 0 ? (values[0] ?: @"") : @"";
        editing.groupName = values.count > 1 ? (values[1] ?: @"") : @"";
        editing.pattern = values.count > 2 ? (values[2] ?: @"") : @"";
        editing.replacement = values.count > 3 ? (values[3] ?: @"") : @"";
        if (editing.pattern.length == 0) {
            [RDPaperAlert showToast:@"匹配内容不能为空"];
            return;
        }
        if (!rule) {
            editing.isRegex = YES;
        }
        [[RDReplaceRuleStore sharedInstance] upsertRule:editing];
        [weakSelf p_reload];
        if (editing.isJavaScriptReplacement) {
            [RDPaperAlert showResultSuccess:YES
                                      title:@"已保存"
                                    message:@"规则已写入。此条含 @js 脚本,本端会跳过执行,可在列表中开关。"];
        } else {
            [RDPaperAlert showToast:@"规则已保存"];
        }
    }];
}

#pragma mark - Import / Export menu

- (void)p_importExportMenu
{
    __weak typeof(self) weakSelf = self;
    [RDPaperAlert showActionSheetWithTitle:@"导入/导出"
                                   message:@"导入始终合并到本地(按 id 或名称+匹配更新)。格式兼容阅读 legado replaceRule。"
                                   actions:@[
        [RDPaperAlertAction actionWithTitle:@"手动添加规则"
                                   subtitle:@"填写名称、匹配与替换"
                                      style:RDPaperAlertActionStyleDefault
                                    handler:^{
            [weakSelf p_editRule:nil];
        }],
        [RDPaperAlertAction actionWithTitle:@"本地导入 · 文件"
                                   subtitle:@"从「文件」选择 .json / .txt"
                                      style:RDPaperAlertActionStyleDefault
                                    handler:^{
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.32 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                [weakSelf p_importFromFile];
            });
        }],
        [RDPaperAlertAction actionWithTitle:@"粘贴导入"
                                   subtitle:@"粘贴规则 JSON 文本"
                                      style:RDPaperAlertActionStyleDefault
                                    handler:^{
            [weakSelf p_importFromPaste];
        }],
        [RDPaperAlertAction actionWithTitle:@"导出文件"
                                   subtitle:@"生成 replaceRule.json · 系统分享 / 存到「文件」"
                                      style:RDPaperAlertActionStyleDefault
                                    handler:^{
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.32 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                [weakSelf p_exportShare];
            });
        }],
    ]];
}

/// 粘贴导入:JSON 正文(本地,无远程拉取)
- (void)p_importFromPaste
{
    NSString *clip = [UIPasteboard generalPasteboard].string ?: @"";
    clip = [clip stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    // 剪贴板过长时(整份 JSON)仍预填,输入框可改
    NSString *pref = clip;
    if (pref.length > 4000) {
        pref = @""; // 超长 JSON 不塞进单行框,导入时再读剪贴板
    }
    __weak typeof(self) weakSelf = self;
    [RDPaperAlert showTextFieldsWithTitle:@"粘贴导入"
                                  message:@"粘贴规则 JSON 文本(不支持远程链接)"
                               fieldSpecs:@[
        @{@"placeholder": @"JSON 或链接", @"text": pref},
    ]
                              cancelTitle:@"取消"
                             confirmTitle:@"导入"
                                  confirm:^(NSArray<NSString *> *values) {
        NSString *raw = values.firstObject ?: @"";
        raw = [raw stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        // 输入框空且剪贴板有超长 JSON → 用剪贴板
        if (raw.length == 0) {
            raw = [UIPasteboard generalPasteboard].string ?: @"";
            raw = [raw stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        }
        if (raw.length == 0) {
            [RDPaperAlert showToast:@"请粘贴规则 JSON"];
            return;
        }
        [weakSelf p_importFromPastedString:raw];
    }];
}

- (void)p_importFromPastedString:(NSString *)raw
{
    NSData *data = [raw dataUsingEncoding:NSUTF8StringEncoding];
    if (data.length == 0) {
        [RDPaperAlert showToast:@"内容为空"];
        return;
    }
    [self p_importJSONData:data];
}

- (void)p_importFromFile
{
    NSMutableArray <UTType *>*types = [NSMutableArray array];
    UTType *json = [UTType typeWithFilenameExtension:@"json"] ?: [UTType typeWithIdentifier:@"public.json"] ?: UTTypeJSON;
    if (json) [types addObject:json];
    UTType *txt = [UTType typeWithFilenameExtension:@"txt"] ?: UTTypePlainText;
    if (txt) [types addObject:txt];
    if (UTTypeText) [types addObject:UTTypeText];
    if (UTTypeData) [types addObject:UTTypeData];

    UIDocumentPickerViewController *picker = [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:types asCopy:YES];
    picker.delegate = self;
    picker.allowsMultipleSelection = NO;
    picker.shouldShowFileExtensions = YES;
    picker.modalPresentationStyle = UIModalPresentationFormSheet;

    __weak typeof(self) weakSelf = self;
    [RDPaperAlert dismissAnimated:YES completion:^{
        dispatch_async(dispatch_get_main_queue(), ^{
            [weakSelf presentViewController:picker animated:YES completion:nil];
        });
    }];
}

- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls
{
    NSURL *url = urls.firstObject;
    if (!url) {
        return;
    }
    NSError *readErr = nil;
    BOOL access = [url startAccessingSecurityScopedResource];
    NSData *data = [NSData dataWithContentsOfURL:url options:0 error:&readErr];
    if (access) {
        [url stopAccessingSecurityScopedResource];
    }
    if (data.length == 0) {
        [RDPaperAlert showResultSuccess:NO title:@"读取失败" message:readErr.localizedDescription ?: @"无法读取所选文件"];
        return;
    }
    [self p_importJSONData:data];
}

- (void)documentPickerWasCancelled:(UIDocumentPickerViewController *)controller
{
}

- (void)p_importJSONData:(NSData *)data
{
    NSError *err = nil;
    NSArray *rules = [RDReplaceRuleStore rulesFromJSONData:data error:&err];
    if (!rules) {
        [RDPaperAlert showResultSuccess:NO title:@"导入失败" message:err.localizedDescription ?: @"无法解析 JSON"];
        return;
    }
    NSInteger n = [[RDReplaceRuleStore sharedInstance] importRules:rules merge:YES];
    [self p_reload];
    NSInteger jsCount = 0;
    for (RDReplaceRule *r in rules) {
        if (r.isJavaScriptReplacement) jsCount++;
    }
    NSString *extra = jsCount > 0
        ? [NSString stringWithFormat:@"\n其中 %ld 条含 @js,本端跳过执行。", (long)jsCount]
        : @"";
    [RDPaperAlert showResultSuccess:YES
                              title:@"导入成功"
                            message:[NSString stringWithFormat:@"已合并 %ld 条规则%@", (long)n, extra]];
}

- (void)p_exportShare
{
    NSData *data = [[RDReplaceRuleStore sharedInstance] exportLegadoJSONData];
    if (data.length == 0) {
        [RDPaperAlert showToast:@"没有可导出的规则"];
        return;
    }
    NSString *stamp = [NSDateFormatter localizedStringFromDate:[NSDate date]
                                                     dateStyle:NSDateFormatterShortStyle
                                                     timeStyle:NSDateFormatterShortStyle];
    NSString *name = [NSString stringWithFormat:@"replaceRule_%@.json", stamp];
    name = [[name componentsSeparatedByCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"/:"]] componentsJoinedByString:@"-"];
    NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:name];
    if (![data writeToFile:path atomically:YES]) {
        [RDPaperAlert showToast:@"写入临时文件失败"];
        return;
    }
    NSURL *fileURL = [NSURL fileURLWithPath:path];
    UIActivityViewController *av = [[UIActivityViewController alloc] initWithActivityItems:@[fileURL] applicationActivities:nil];
    // 仅文件分享,排除复制到剪贴板等非文件路径
    av.excludedActivityTypes = @[
        UIActivityTypeCopyToPasteboard,
        UIActivityTypeAssignToContact,
        UIActivityTypeAddToReadingList,
        UIActivityTypePostToFacebook,
        UIActivityTypePostToTwitter,
        UIActivityTypePostToWeibo,
        UIActivityTypeMessage,
        UIActivityTypeMail,
        UIActivityTypePrint,
    ];
    if (av.popoverPresentationController) {
        av.popoverPresentationController.sourceView = self.view;
        av.popoverPresentationController.sourceRect = CGRectMake(self.view.bounds.size.width - 40, self.topView.bottom, 1, 1);
    }
    __weak typeof(self) weakSelf = self;
    [RDPaperAlert dismissAnimated:YES completion:^{
        [weakSelf presentViewController:av animated:YES completion:nil];
    }];
}

#pragma mark - Table

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
    return MAX((NSInteger)self.groups.count, 1);
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    if (self.groups.count == 0) {
        return 0;
    }
    NSArray *items = self.groups[section][@"items"];
    return items.count;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section
{
    if (self.groups.count == 0) {
        return @"暂无规则 · 点右上角「导入/导出」添加或导入";
    }
    return self.groups[section][@"title"];
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section
{
    if (section == (NSInteger)self.groups.count - 1 || (self.groups.count == 0 && section == 0)) {
        return @"阅读时自动应用已启用规则。导入始终合并(按 id 或名称+匹配更新),不会清空本地。";
    }
    return nil;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    static NSString *cid = @"rule";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:cid];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:cid];
        cell.backgroundColor = RDSurfaceColor;
        cell.textLabel.font = RDFont16;
        cell.textLabel.textColor = RDBlackColor;
        cell.detailTextLabel.font = RDFont12;
        cell.detailTextLabel.textColor = RDLightGrayColor;
        cell.detailTextLabel.numberOfLines = 2;
    }
    RDReplaceRule *r = [self p_ruleAtIndexPath:indexPath];
    cell.textLabel.text = r.name.length ? r.name : @"未命名";
    NSMutableString *detail = [NSMutableString string];
    [detail appendString:r.isRegex ? @"正则" : @"原文"];
    if (r.isJavaScriptReplacement) {
        [detail appendString:@" · JS(跳过)"];
    }
    if (r.scopeTitle && r.scopeContent) {
        [detail appendString:@" · 标题+正文"];
    } else if (r.scopeTitle) {
        [detail appendString:@" · 仅标题"];
    } else {
        [detail appendString:@" · 正文"];
    }
    NSString *pat = r.pattern.length > 48 ? [[r.pattern substringToIndex:48] stringByAppendingString:@"…"] : r.pattern;
    [detail appendFormat:@"\n%@", pat ?: @""];
    cell.detailTextLabel.text = detail;

    UISwitch *sw = [[UISwitch alloc] init];
    sw.on = r.isEnabled;
    sw.onTintColor = RDAccentColor;
    sw.tag = indexPath.section * 10000 + indexPath.row;
    [sw addTarget:self action:@selector(p_toggle:) forControlEvents:UIControlEventValueChanged];
    cell.accessoryView = sw;
    return cell;
}

- (void)p_toggle:(UISwitch *)sw
{
    NSInteger section = sw.tag / 10000;
    NSInteger row = sw.tag % 10000;
    NSIndexPath *ip = [NSIndexPath indexPathForRow:row inSection:section];
    RDReplaceRule *r = [[self p_ruleAtIndexPath:ip] copy];
    if (!r) {
        return;
    }
    r.isEnabled = sw.on;
    [[RDReplaceRuleStore sharedInstance] upsertRule:r];
    [self p_reload];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    RDReplaceRule *r = [self p_ruleAtIndexPath:indexPath];
    if (!r) {
        return;
    }
    __weak typeof(self) weakSelf = self;
    NSMutableArray *actions = [NSMutableArray array];
    [actions addObject:[RDPaperAlertAction actionWithTitle:@"编辑"
                                                  subtitle:@"修改名称、匹配与替换"
                                                     style:RDPaperAlertActionStyleDefault
                                                   handler:^{
        [weakSelf p_editRule:r];
    }]];
    [actions addObject:[RDPaperAlertAction actionWithTitle:r.isRegex ? @"改为原文匹配" : @"改为正则匹配"
                                                     style:RDPaperAlertActionStyleDefault
                                                   handler:^{
        RDReplaceRule *c = [r copy];
        c.isRegex = !c.isRegex;
        [[RDReplaceRuleStore sharedInstance] upsertRule:c];
        [weakSelf p_reload];
        [RDPaperAlert showToast:c.isRegex ? @"已设为正则" : @"已设为原文"];
    }]];
    [actions addObject:[RDPaperAlertAction actionWithTitle:r.scopeContent ? @"关闭 · 作用于正文" : @"开启 · 作用于正文"
                                                     style:RDPaperAlertActionStyleDefault
                                                   handler:^{
        RDReplaceRule *c = [r copy];
        c.scopeContent = !c.scopeContent;
        if (!c.scopeContent && !c.scopeTitle) {
            c.scopeTitle = YES;
        }
        [[RDReplaceRuleStore sharedInstance] upsertRule:c];
        [weakSelf p_reload];
    }]];
    [actions addObject:[RDPaperAlertAction actionWithTitle:r.scopeTitle ? @"关闭 · 作用于标题" : @"开启 · 作用于标题"
                                                     style:RDPaperAlertActionStyleDefault
                                                   handler:^{
        RDReplaceRule *c = [r copy];
        c.scopeTitle = !c.scopeTitle;
        if (!c.scopeContent && !c.scopeTitle) {
            c.scopeContent = YES;
        }
        [[RDReplaceRuleStore sharedInstance] upsertRule:c];
        [weakSelf p_reload];
    }]];
    [actions addObject:[RDPaperAlertAction actionWithTitle:@"删除"
                                                     style:RDPaperAlertActionStyleDestructive
                                                   handler:^{
        [RDPaperAlert showConfirmWithTitle:@"删除规则"
                                   message:r.name.length ? r.name : @"确定删除这条净化规则？"
                               cancelTitle:@"取消"
                              confirmTitle:@"删除"
                               destructive:YES
                                   confirm:^{
            [[RDReplaceRuleStore sharedInstance] removeRuleId:r.ruleId];
            [weakSelf p_reload];
            [RDPaperAlert showToast:@"已删除"];
        }];
    }]];
    NSString *msg = r.isJavaScriptReplacement
        ? @"含 @js 的规则可保留与开关,本 App 不会执行脚本。"
        : nil;
    [RDPaperAlert showActionSheetWithTitle:r.name.length ? r.name : @"规则" message:msg actions:actions];
}

@end
