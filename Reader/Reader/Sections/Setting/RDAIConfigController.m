//
//  RDAIConfigController.m
//  Reader
//

#import "RDAIConfigController.h"
#import "RDAIConfig.h"
#import "RDAIClient.h"
#import "RDAIProfileEditController.h"
#import "RDPaperAlert.h"
#import "RDVoiceManager.h"

typedef NS_ENUM(NSInteger, RDAIConfigSection) {
    RDAIConfigSectionTranslate = 0,
    RDAIConfigSectionTTS = 1,
    RDAIConfigSectionCount,
};

@interface RDAIConfigController () <UITableViewDelegate, UITableViewDataSource>
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, copy) NSArray <RDAIConfigProfile *>*translateProfiles;
@property (nonatomic, copy) NSArray <RDAIConfigProfile *>*ttsProfiles;
@property (nonatomic, assign) BOOL busy;
@end

@implementation RDAIConfigController

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.topView.titleLabel.text = @"AI 配置";
    [self.view addSubview:self.topView];
    [self.view addSubview:self.tableView];
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
        _tableView.rowHeight = UITableViewAutomaticDimension;
        _tableView.estimatedRowHeight = 72;
    }
    return _tableView;
}

- (void)p_reload
{
    NSArray <RDAIConfigProfile *>*all = [RDAIConfigStore sharedInstance].profiles;
    NSMutableArray *translate = [NSMutableArray array];
    NSMutableArray *tts = [NSMutableArray array];
    for (RDAIConfigProfile *p in all) {
        if (p.isTTSRole) {
            [tts addObject:p];
        } else {
            [translate addObject:p];
        }
    }
    self.translateProfiles = translate;
    self.ttsProfiles = tts;
    [self.tableView reloadData];
}

- (void)p_addTranslate
{
    RDAIProfileEditController *edit = [[RDAIProfileEditController alloc] init];
    edit.profile = nil;
    edit.editMode = RDAIProfileEditModeTranslate;
    [self.navigationController pushViewController:edit animated:YES];
}

- (void)p_addTTS
{
    RDAIProfileEditController *edit = [[RDAIProfileEditController alloc] init];
    edit.profile = nil;
    edit.editMode = RDAIProfileEditModeTTS;
    [self.navigationController pushViewController:edit animated:YES];
}

- (void)p_editProfile:(RDAIConfigProfile *)p mode:(RDAIProfileEditMode)mode
{
    RDAIProfileEditController *edit = [[RDAIProfileEditController alloc] init];
    edit.profile = p;
    edit.editMode = mode;
    [self.navigationController pushViewController:edit animated:YES];
}

#pragma mark - UITableView

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
    return RDAIConfigSectionCount;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    if (section == RDAIConfigSectionTranslate) {
        return self.translateProfiles.count + 1;
    }
    return self.ttsProfiles.count + 1;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section
{
    if (section == RDAIConfigSectionTranslate) {
        return @"翻译服务";
    }
    return @"AI 朗读（MiMo / OpenAI TTS）";
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section
{
    if (section == RDAIConfigSectionTranslate) {
        return @"阅读页「译」使用「设为当前」的配置。可在编辑页「探测模型 / 测试连接」。朗读请用下方分区,二者互不混用。";
    }
    return @"专用于听书。小米 MiMo 走 chat 式 TTS;OpenAI 走 /v1/audio/speech。保存后「设为朗读引擎」或到「朗读语音」中选择。";
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    static NSString *cellId = @"RDAIConfigCell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:cellId];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:cellId];
        cell.backgroundColor = RDSurfaceColor;
        cell.textLabel.font = RDFont16;
        cell.textLabel.textColor = RDBlackColor;
        cell.detailTextLabel.font = RDFont13;
        cell.detailTextLabel.textColor = RDLightGrayColor;
        cell.detailTextLabel.numberOfLines = 0;
        cell.textLabel.numberOfLines = 2;
    }
    cell.accessoryView = nil;
    cell.accessoryType = UITableViewCellAccessoryNone;
    cell.selectionStyle = UITableViewCellSelectionStyleDefault;
    cell.textLabel.textColor = RDBlackColor;

    if (indexPath.section == RDAIConfigSectionTranslate) {
        if (indexPath.row >= (NSInteger)self.translateProfiles.count) {
            cell.textLabel.text = @"添加翻译配置";
            cell.detailTextLabel.text = @"OpenAI / Anthropic / Gemini / MiMo 及兼容格式";
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
            cell.textLabel.textColor = [UIColor systemBlueColor];
            return cell;
        }
        return [self p_configureProfileCell:cell profile:self.translateProfiles[indexPath.row] forTTS:NO];
    }

    if (indexPath.row >= (NSInteger)self.ttsProfiles.count) {
        cell.textLabel.text = @"添加 AI 朗读（MiMo / OpenAI）";
        cell.detailTextLabel.text = @"推荐:小米 MiMo mimo-v2.5-tts · 内置中文音色";
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        cell.textLabel.textColor = [UIColor systemBlueColor];
        return cell;
    }
    return [self p_configureProfileCell:cell profile:self.ttsProfiles[indexPath.row] forTTS:YES];
}

- (UITableViewCell *)p_configureProfileCell:(UITableViewCell *)cell
                                    profile:(RDAIConfigProfile *)p
                                     forTTS:(BOOL)forTTS
{
    NSString *title = p.name.length > 0 ? p.name : p.type;
    if (p.pendingConfirm) {
        title = [NSString stringWithFormat:@"%@ · 待确认", title];
    }
    cell.textLabel.text = title;

    NSMutableString *detail = [NSMutableString string];
    if (forTTS) {
        NSString *tm = p.ttsModel.length ? p.ttsModel : ([RDAIClient isMiMoType:p.type] ? @"mimo-v2.5-tts" : @"tts-1");
        NSString *tv = p.ttsVoice.length ? p.ttsVoice : ([RDAIClient isMiMoType:p.type] ? @"mimo_default" : @"alloy");
        [detail appendFormat:@"%@ · %@ · %@", p.type, tm, tv];
        if (p.isTTSUsable) {
            [detail appendString:@"\n可朗读"];
        } else if (p.pendingConfirm) {
            [detail appendString:@"\n备份导入 · 设为当前后可用"];
        } else if (p.apiKey.length == 0) {
            [detail appendString:@"\n未填 API Key"];
        } else {
            [detail appendString:@"\n配置不完整"];
        }
        NSString *pref = [RDVoiceManager sharedInstance].preferredVoiceIdentifier;
        if (pref.length && [pref isEqualToString:[p ttsVoiceIdentifier]]) {
            [detail appendString:@" · 当前听书引擎"];
        }
    } else {
        [detail appendFormat:@"%@ · %@", p.type, p.model.length > 0 ? p.model : @"未填模型"];
        if (p.baseURL.length > 0) {
            [detail appendFormat:@"\n%@", p.baseURL];
        }
        if (p.pendingConfirm) {
            [detail appendString:@"\n备份导入 · 设为当前后可用"];
        } else if (p.isUsable) {
            [detail appendString:@"\n可翻译"];
        }
    }
    cell.detailTextLabel.text = detail;

    BOOL activeTranslate = !forTTS
        && p.profileId.length > 0
        && [[RDAIConfigStore sharedInstance].activeProfileId isEqualToString:p.profileId];
    BOOL activeTTS = forTTS
        && p.isTTSUsable
        && [[[RDVoiceManager sharedInstance] preferredVoiceIdentifier] isEqualToString:[p ttsVoiceIdentifier]];

    if (activeTranslate || activeTTS) {
        UIImageSymbolConfiguration *cfg = [UIImageSymbolConfiguration configurationWithPointSize:16 weight:UIImageSymbolWeightSemibold];
        UIImage *check = [UIImage systemImageNamed:@"checkmark.circle.fill" withConfiguration:cfg];
        UIImageView *iv = [[UIImageView alloc] initWithImage:[check imageWithTintColor:[UIColor systemGreenColor] renderingMode:UIImageRenderingModeAlwaysOriginal]];
        cell.accessoryView = iv;
    } else if (p.pendingConfirm) {
        UIImageSymbolConfiguration *cfg = [UIImageSymbolConfiguration configurationWithPointSize:16 weight:UIImageSymbolWeightRegular];
        UIImage *warn = [UIImage systemImageNamed:@"exclamationmark.circle" withConfiguration:cfg];
        UIImageView *iv = [[UIImageView alloc] initWithImage:[warn imageWithTintColor:[UIColor systemOrangeColor] renderingMode:UIImageRenderingModeAlwaysOriginal]];
        cell.accessoryView = iv;
    } else {
        cell.accessoryView = nil;
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    }
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.section == RDAIConfigSectionTranslate) {
        if (indexPath.row >= (NSInteger)self.translateProfiles.count) {
            [self p_addTranslate];
            return;
        }
        [self p_presentActionsForProfile:self.translateProfiles[indexPath.row] forTTS:NO];
        return;
    }
    if (indexPath.row >= (NSInteger)self.ttsProfiles.count) {
        [self p_addTTS];
        return;
    }
    [self p_presentActionsForProfile:self.ttsProfiles[indexPath.row] forTTS:YES];
}

- (void)p_testProfile:(RDAIConfigProfile *)p
{
    if (self.busy) {
        return;
    }
    self.busy = YES;
    [self showLoading:@"测试中…" cancel:^{
        self.busy = NO;
    }];
    __weak typeof(self) weakSelf = self;
    [[RDAIClient sharedClient] testProfile:p completion:^(NSString *sample, NSError *error) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) {
            return;
        }
        self.busy = NO;
        [self hideLoading];
        if (error) {
            [RDPaperAlert showAlertWithTitle:@"测试失败"
                                     message:error.localizedDescription ?: @"未知错误"
                                  symbolName:@"xmark.circle"
                                     actions:@[[RDPaperAlertAction actionWithTitle:@"知道了" style:RDPaperAlertActionStylePrimary handler:nil]]];
            return;
        }
        NSString *preview = sample.length > 120 ? [[sample substringToIndex:120] stringByAppendingString:@"…"] : sample;
        [RDPaperAlert showAlertWithTitle:@"测试成功"
                                 message:[NSString stringWithFormat:@"模型已响应:\n%@", preview]
                              symbolName:@"checkmark.circle"
                                 actions:@[[RDPaperAlertAction actionWithTitle:@"好的" style:RDPaperAlertActionStylePrimary handler:nil]]];
    }];
}

- (void)p_probeModelsForProfile:(RDAIConfigProfile *)p
{
    if (self.busy) {
        return;
    }
    self.busy = YES;
    [self showLoading:@"探测模型中…" cancel:^{
        self.busy = NO;
    }];
    __weak typeof(self) weakSelf = self;
    [[RDAIClient sharedClient] listModelsForProfile:p completion:^(NSArray<NSString *> *models, NSError *error) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) {
            return;
        }
        self.busy = NO;
        [self hideLoading];
        if (error || models.count == 0) {
            [self showText:error.localizedDescription ?: @"未获取到模型"];
            return;
        }
        NSMutableArray *actions = [NSMutableArray array];
        NSInteger limit = MIN((NSInteger)models.count, 40);
        for (NSInteger i = 0; i < limit; i++) {
            NSString *mid = models[i];
            [actions addObject:[RDPaperAlertAction actionWithTitle:mid style:RDPaperAlertActionStyleDefault handler:^{
                RDAIConfigProfile *copy = [p copy];
                copy.model = mid;
                if (![[RDAIConfigStore sharedInstance] upsertProfile:copy]) {
                    [self showText:@"写入模型失败"];
                    return;
                }
                [self showText:[NSString stringWithFormat:@"已设为 %@", mid]];
                [self p_reload];
            }]];
        }
        [RDPaperAlert showActionSheetWithTitle:[NSString stringWithFormat:@"可用模型(%ld)", (long)models.count]
                                       message:@"点选将写入该配置的翻译模型"
                                       actions:actions];
    }];
}

- (void)p_presentActionsForProfile:(RDAIConfigProfile *)p forTTS:(BOOL)forTTS
{
    __weak typeof(self) weakSelf = self;
    NSMutableArray *actions = [NSMutableArray array];

    if (!forTTS) {
        [actions addObject:[RDPaperAlertAction actionWithTitle:@"设为当前(翻译)" style:RDPaperAlertActionStyleDefault handler:^{
            if (![[RDAIConfigStore sharedInstance] activateProfileId:p.profileId]) {
                [weakSelf showText:@"设置失败,请重试"];
            }
            [weakSelf p_reload];
        }]];
        [actions addObject:[RDPaperAlertAction actionWithTitle:@"测试连接"
                                                      subtitle:@"发送短句验证 Key 与模型"
                                                         style:RDPaperAlertActionStyleDefault
                                                       handler:^{
            [weakSelf p_testProfile:p];
        }]];
        [actions addObject:[RDPaperAlertAction actionWithTitle:@"探测模型"
                                                      subtitle:@"从 API 拉取可用模型列表"
                                                         style:RDPaperAlertActionStyleDefault
                                                       handler:^{
            [weakSelf p_probeModelsForProfile:p];
        }]];
    } else {
        // 仅朗读分区:设为听书引擎
        [actions addObject:[RDPaperAlertAction actionWithTitle:p.isTTSUsable ? @"设为朗读引擎" : @"设为朗读引擎(需补全)"
                                                      subtitle:p.isTTSUsable ? @"听书使用此 AI TTS" : @"请先编辑并填写 API Key"
                                                         style:RDPaperAlertActionStyleDefault
                                                       handler:^{
            if (!p.isTTSUsable) {
                [weakSelf showText:p.pendingConfirm ? @"请先确认备份配置" : @"请先补全 API Key 等 TTS 字段"];
                return;
            }
            [[RDVoiceManager sharedInstance] setPreferredIdentifier:[p ttsVoiceIdentifier]];
            [[NSNotificationCenter defaultCenter] postNotificationName:RDVoiceListChangedNotification object:nil];
            [weakSelf showText:@"已设为听书引擎"];
            [weakSelf p_reload];
        }]];
    }

    [actions addObject:[RDPaperAlertAction actionWithTitle:@"编辑" style:RDPaperAlertActionStyleDefault handler:^{
        RDAIProfileEditMode mode = forTTS ? RDAIProfileEditModeTTS : RDAIProfileEditModeTranslate;
        [weakSelf p_editProfile:p mode:mode];
    }]];

    [actions addObject:[RDPaperAlertAction actionWithTitle:@"删除" style:RDPaperAlertActionStyleDestructive handler:^{
        NSString *ttsId = [p ttsVoiceIdentifier];
        if ([[[RDVoiceManager sharedInstance] preferredVoiceIdentifier] isEqualToString:ttsId]) {
            [[RDVoiceManager sharedInstance] setPreferredIdentifier:nil];
        }
        [[RDAIConfigStore sharedInstance] removeProfileId:p.profileId];
        [weakSelf p_reload];
    }]];

    NSString *title = p.name.length ? p.name : @"AI 配置";
    NSString *msg = forTTS
        ? [NSString stringWithFormat:@"%@ · TTS %@ · %@", p.type, p.ttsModel ?: @"—", p.ttsVoice ?: @"—"]
        : [NSString stringWithFormat:@"%@ · %@", p.type, p.model ?: @"—"];
    [RDPaperAlert showActionSheetWithTitle:title message:msg actions:actions];
}

@end
