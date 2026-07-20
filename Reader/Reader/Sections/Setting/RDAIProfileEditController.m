//
//  RDAIProfileEditController.m
//  Reader
//

#import "RDAIProfileEditController.h"
#import "RDAIConfig.h"
#import "RDAIClient.h"
#import "RDPaperAlert.h"

typedef NS_ENUM(NSInteger, RDAIEditRow) {
    RDAIEditRowName = 0,
    RDAIEditRowType,
    RDAIEditRowAPIKey,
    RDAIEditRowModel,
    RDAIEditRowBaseURL,
    RDAIEditRowProbeModels, // 翻译:探测模型列表
    RDAIEditRowTest,        // 翻译:测试连接
    RDAIEditRowTTSModel,
    RDAIEditRowTTSVoice,
};

@interface RDAIProfileEditController () <UITableViewDelegate, UITableViewDataSource, UITextFieldDelegate>
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) RDAIConfigProfile *editing;
@property (nonatomic, strong) UITextField *nameField;
@property (nonatomic, strong) UITextField *keyField;
@property (nonatomic, strong) UITextField *modelField;
@property (nonatomic, strong) UITextField *baseField;
@property (nonatomic, strong) UITextField *ttsModelField;
@property (nonatomic, copy) NSArray <NSNumber *>*rowMap;
@property (nonatomic, assign) BOOL busy;
@end

@implementation RDAIProfileEditController

- (void)viewDidLoad
{
    [super viewDidLoad];
    if (self.profile) {
        self.editing = [self.profile copy];
        // 按已有 role 校正模式(不再把 MiMo 强行切到 TTS 编辑)
        if ([self.editing.role isEqualToString:RDAIProfileRoleTTS]) {
            self.editMode = RDAIProfileEditModeTTS;
        } else if (self.editMode != RDAIProfileEditModeTTS) {
            self.editMode = RDAIProfileEditModeTranslate;
        }
        self.topView.titleLabel.text = (self.editMode == RDAIProfileEditModeTTS) ? @"编辑 AI 朗读" : @"编辑翻译配置";
    } else {
        self.editing = [[RDAIConfigProfile alloc] init];
        if (self.editMode == RDAIProfileEditModeTTS) {
            self.editing.role = RDAIProfileRoleTTS;
            self.editing.name = @"MiMo 朗读";
            self.editing.type = RDAIProviderTypeMiMo;
            self.editing.model = @"mimo-v2.5-tts";
            self.editing.baseURL = [RDAIClient defaultBaseURLForType:RDAIProviderTypeMiMo];
            self.editing.ttsModel = @"mimo-v2.5-tts";
            self.editing.ttsVoice = @"mimo_default";
            self.topView.titleLabel.text = @"添加 AI 朗读";
        } else {
            self.editing.role = RDAIProfileRoleTranslate;
            self.editing.name = @"默认";
            self.editing.type = RDAIProviderTypeOpenAI;
            self.editing.model = @"gpt-4o-mini";
            self.topView.titleLabel.text = @"添加翻译配置";
        }
    }
    [self p_rebuildRows];
    UIButton *saveBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    [saveBtn setTitle:@"保存" forState:UIControlStateNormal];
    saveBtn.titleLabel.font = [UIFont boldSystemFontOfSize:16];
    [saveBtn addTarget:self action:@selector(p_save) forControlEvents:UIControlEventTouchUpInside];
    [self.topView addSubview:saveBtn];
    saveBtn.translatesAutoresizingMaskIntoConstraints = NO;
    [NSLayoutConstraint activateConstraints:@[
        [saveBtn.trailingAnchor constraintEqualToAnchor:self.topView.trailingAnchor constant:-16],
        [saveBtn.centerYAnchor constraintEqualToAnchor:self.topView.titleLabel.centerYAnchor],
    ]];
    [self.view addSubview:self.topView];
    [self.view addSubview:self.tableView];
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
        _tableView.rowHeight = 52;
        _tableView.keyboardDismissMode = UIScrollViewKeyboardDismissModeOnDrag;
    }
    return _tableView;
}

- (void)p_rebuildRows
{
    NSMutableArray *rows = [NSMutableArray array];
    [rows addObject:@(RDAIEditRowName)];
    [rows addObject:@(RDAIEditRowType)];
    [rows addObject:@(RDAIEditRowAPIKey)];
    if (self.editMode == RDAIProfileEditModeTranslate) {
        [rows addObject:@(RDAIEditRowModel)];
        [rows addObject:@(RDAIEditRowBaseURL)];
        [rows addObject:@(RDAIEditRowProbeModels)];
        [rows addObject:@(RDAIEditRowTest)];
    } else {
        [rows addObject:@(RDAIEditRowBaseURL)];
        [rows addObject:@(RDAIEditRowTTSModel)];
        [rows addObject:@(RDAIEditRowTTSVoice)];
    }
    self.rowMap = rows;
}

- (RDAIEditRow)p_rowAtIndex:(NSInteger)index
{
    if (index < 0 || index >= (NSInteger)self.rowMap.count) {
        return RDAIEditRowName;
    }
    return (RDAIEditRow)self.rowMap[index].integerValue;
}

- (UITextField *)p_fieldWithPlaceholder:(NSString *)ph text:(NSString *)text secure:(BOOL)secure
{
    UITextField *f = [[UITextField alloc] initWithFrame:CGRectMake(0, 0, 200, 36)];
    f.placeholder = ph;
    f.text = text;
    f.font = RDFont15;
    f.textAlignment = NSTextAlignmentRight;
    f.clearButtonMode = UITextFieldViewModeWhileEditing;
    f.secureTextEntry = secure;
    f.autocapitalizationType = UITextAutocapitalizationTypeNone;
    f.autocorrectionType = UITextAutocorrectionTypeNo;
    f.delegate = self;
    return f;
}

- (BOOL)p_needsBaseURL
{
    NSString *t = self.editing.type;
    return [t isEqualToString:RDAIProviderTypeOpenAICompat]
        || [t isEqualToString:RDAIProviderTypeAnthropicCompat]
        || [t isEqualToString:RDAIProviderTypeGeminiCompat];
}

- (NSArray <NSString *>*)p_availableTypes
{
    if (self.editMode == RDAIProfileEditModeTTS) {
        return @[
            RDAIProviderTypeMiMo,
            RDAIProviderTypeOpenAI,
            RDAIProviderTypeOpenAICompat,
        ];
    }
    return @[
        RDAIProviderTypeOpenAI,
        RDAIProviderTypeAnthropic,
        RDAIProviderTypeOpenAICompat,
        RDAIProviderTypeAnthropicCompat,
        RDAIProviderTypeGemini,
        RDAIProviderTypeGeminiCompat,
        RDAIProviderTypeMiMo,
    ];
}

- (void)p_syncFieldsFromEditing
{
    if (self.nameField) {
        self.nameField.text = self.editing.name;
    }
    if (self.keyField) {
        self.keyField.text = self.editing.apiKey;
    }
    if (self.modelField) {
        self.modelField.text = self.editing.model;
    }
    if (self.baseField) {
        self.baseField.text = self.editing.baseURL;
    }
    if (self.ttsModelField) {
        self.ttsModelField.text = self.editing.ttsModel;
    }
}

- (void)p_pullFieldsIntoEditing
{
    if (self.nameField) {
        self.editing.name = self.nameField.text ?: @"";
    }
    if (self.keyField) {
        self.editing.apiKey = self.keyField.text ?: @"";
    }
    if (self.modelField) {
        self.editing.model = self.modelField.text ?: @"";
    }
    if (self.baseField) {
        self.editing.baseURL = self.baseField.text ?: @"";
    }
    if (self.ttsModelField) {
        self.editing.ttsModel = self.ttsModelField.text ?: @"";
    }
}

- (void)p_applyTypeDefaults:(NSString *)type
{
    if ([RDAIClient isMiMoType:type]) {
        if (self.editMode == RDAIProfileEditModeTTS) {
            if (self.editing.model.length == 0 || [self.editing.model hasPrefix:@"gpt"] || [self.editing.model hasPrefix:@"claude"]) {
                self.editing.model = @"mimo-v2.5-tts";
            }
            self.editing.ttsModel = @"mimo-v2.5-tts";
            self.editing.ttsVoice = @"mimo_default";
            if (self.editing.name.length == 0 || [self.editing.name isEqualToString:@"OpenAI 朗读"] || [self.editing.name isEqualToString:@"默认"]) {
                self.editing.name = @"MiMo 朗读";
            }
        } else {
            if (self.editing.model.length == 0 || [self.editing.model hasPrefix:@"gpt"] || [self.editing.model hasPrefix:@"claude"] || [self.editing.model hasPrefix:@"gemini"] || [self.editing.model hasPrefix:@"tts-"]) {
                self.editing.model = @"mimo-v2.5-pro";
            }
        }
        if (self.editing.baseURL.length == 0
            || [self.editing.baseURL containsString:@"openai.com"]
            || [self.editing.baseURL containsString:@"anthropic"]
            || [self.editing.baseURL containsString:@"googleapis"]) {
            self.editing.baseURL = [RDAIClient defaultBaseURLForType:type];
        }
    } else if ([type isEqualToString:RDAIProviderTypeOpenAI] || [type isEqualToString:RDAIProviderTypeOpenAICompat]) {
        if (self.editing.model.length == 0
            || [self.editing.model hasPrefix:@"mimo"]
            || [self.editing.model hasPrefix:@"claude"]
            || [self.editing.model hasPrefix:@"gemini"]) {
            self.editing.model = self.editMode == RDAIProfileEditModeTTS ? @"tts-1" : @"gpt-4o-mini";
        }
        if (self.editMode == RDAIProfileEditModeTTS) {
            self.editing.ttsModel = @"tts-1";
            self.editing.ttsVoice = @"alloy";
            if ([self.editing.name isEqualToString:@"MiMo 朗读"] || self.editing.name.length == 0) {
                self.editing.name = [type isEqualToString:RDAIProviderTypeOpenAICompat] ? @"OpenAI 兼容朗读" : @"OpenAI 朗读";
            }
        }
        if ([type isEqualToString:RDAIProviderTypeOpenAI]
            || [self.editing.baseURL.lowercaseString containsString:@"xiaomimimo.com"]) {
            if ([type isEqualToString:RDAIProviderTypeOpenAI]) {
                self.editing.baseURL = @"";
            } else if ([self.editing.baseURL.lowercaseString containsString:@"xiaomimimo.com"]) {
                self.editing.baseURL = @"";
            }
        }
    } else if ([RDAIClient isAnthropicFamily:type]) {
        if (self.editing.model.length == 0 || [self.editing.model hasPrefix:@"gpt"] || [self.editing.model hasPrefix:@"gemini"] || [self.editing.model hasPrefix:@"mimo"]) {
            self.editing.model = @"claude-3-5-sonnet-latest";
        }
    } else if ([RDAIClient isGeminiFamily:type]) {
        if (self.editing.model.length == 0 || [self.editing.model hasPrefix:@"gpt"] || [self.editing.model hasPrefix:@"claude"] || [self.editing.model hasPrefix:@"mimo"]) {
            self.editing.model = @"gemini-2.0-flash";
        }
    }
}

- (void)p_save
{
    [self.view endEditing:YES];
    [self p_pullFieldsIntoEditing];

    if (self.editMode == RDAIProfileEditModeTTS) {
        self.editing.role = RDAIProfileRoleTTS;
        BOOL mimo = [RDAIClient isMiMoType:self.editing.type] || self.editing.usesMiMoSpeechAPI;
        NSString *ttsFallback = mimo ? @"mimo-v2.5-tts" : @"tts-1";
        NSString *voiceFallback = mimo ? @"mimo_default" : @"alloy";
        if (self.editing.ttsModel.length == 0) {
            self.editing.ttsModel = ttsFallback;
        }
        if (self.editing.ttsVoice.length == 0) {
            self.editing.ttsVoice = voiceFallback;
        }
        if (self.editing.model.length == 0) {
            self.editing.model = self.editing.ttsModel;
        }
    } else {
        self.editing.role = RDAIProfileRoleTranslate;
    }

    if (self.editing.apiKey.length == 0) {
        [self showText:@"请填写 API Key"];
        return;
    }
    if (self.editMode == RDAIProfileEditModeTranslate && self.editing.model.length == 0) {
        [self showText:@"请填写模型名"];
        return;
    }
    if (self.editMode == RDAIProfileEditModeTTS && self.editing.ttsModel.length == 0) {
        [self showText:@"请填写 TTS 模型"];
        return;
    }
    if ([self p_needsBaseURL] && self.editing.baseURL.length == 0) {
        [self showText:@"兼容格式需要填写 Base URL"];
        return;
    }
    if (self.editing.baseURL.length > 0) {
        NSError *urlErr = nil;
        if (![RDAIClient validateBaseURLString:self.editing.baseURL error:&urlErr]) {
            [self showText:urlErr.localizedDescription ?: @"Base URL 不符合安全策略"];
            return;
        }
    }
    if (self.editing.name.length == 0) {
        self.editing.name = (self.editMode == RDAIProfileEditModeTTS) ? @"AI 朗读" : self.editing.type;
    }
    if (![[RDAIConfigStore sharedInstance] upsertProfile:self.editing]) {
        [self showText:@"保存失败,密钥未能写入安全存储"];
        return;
    }
    [self showText:@"已保存"];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.4 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self.navigationController popViewControllerAnimated:YES];
    });
}

- (void)p_pickType
{
    NSArray *types = [self p_availableTypes];
    __weak typeof(self) weakSelf = self;
    NSMutableArray *actions = [NSMutableArray array];
    for (NSString *type in types) {
        NSString *picked = [type copy];
        NSString *title = picked;
        if ([picked isEqualToString:RDAIProviderTypeMiMo]) {
            title = (self.editMode == RDAIProfileEditModeTTS) ? @"MiMo（小米语音合成）" : @"MiMo（小米）";
        } else if ([picked isEqualToString:RDAIProviderTypeOpenAI]) {
            title = self.editMode == RDAIProfileEditModeTTS ? @"OpenAI TTS" : @"OpenAI";
        } else if ([picked isEqualToString:RDAIProviderTypeOpenAICompat]) {
            title = self.editMode == RDAIProfileEditModeTTS ? @"OpenAI 兼容 TTS" : @"openai格式";
        }
        [actions addObject:[RDPaperAlertAction actionWithTitle:title style:RDPaperAlertActionStyleDefault handler:^{
            __strong typeof(weakSelf) self = weakSelf;
            if (!self) {
                return;
            }
            self.editing.type = picked;
            [self p_applyTypeDefaults:picked];
            [self p_syncFieldsFromEditing];
            [self p_rebuildRows];
            [self.tableView reloadData];
        }]];
    }
    NSString *sheetTitle = (self.editMode == RDAIProfileEditModeTTS) ? @"选择朗读服务商" : @"选择类型";
    [RDPaperAlert showActionSheetWithTitle:sheetTitle message:nil actions:actions];
}

#pragma mark - Probe / Test

- (RDAIConfigProfile *)p_draftProfileForProbe
{
    [self.view endEditing:YES];
    [self p_pullFieldsIntoEditing];
    RDAIConfigProfile *p = [self.editing copy];
    p.role = RDAIProfileRoleTranslate;
    p.pendingConfirm = NO;
    return p;
}

- (void)p_probeModels
{
    if (self.busy) {
        return;
    }
    RDAIConfigProfile *draft = [self p_draftProfileForProbe];
    if (draft.apiKey.length == 0) {
        [self showText:@"请先填写 API Key"];
        return;
    }
    if ([self p_needsBaseURL] && draft.baseURL.length == 0) {
        [self showText:@"兼容格式需要填写 Base URL"];
        return;
    }
    self.busy = YES;
    [self showLoading:@"探测模型中…" cancel:^{
        self.busy = NO;
    }];
    __weak typeof(self) weakSelf = self;
    [[RDAIClient sharedClient] listModelsForProfile:draft completion:^(NSArray<NSString *> *models, NSError *error) {
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
                self.editing.model = mid;
                if (self.modelField) {
                    self.modelField.text = mid;
                }
                [self.tableView reloadData];
                [self showText:[NSString stringWithFormat:@"已选择 %@", mid]];
            }]];
        }
        if ((NSInteger)models.count > limit) {
            [actions addObject:[RDPaperAlertAction actionWithTitle:[NSString stringWithFormat:@"…另有 %ld 个未列出", (long)(models.count - limit)]
                                                             style:RDPaperAlertActionStyleCancel
                                                           handler:nil]];
        }
        [RDPaperAlert showActionSheetWithTitle:[NSString stringWithFormat:@"可用模型(%ld)", (long)models.count]
                                       message:@"点选填入「翻译模型」"
                                       actions:actions];
    }];
}

- (void)p_testConnection
{
    if (self.busy) {
        return;
    }
    RDAIConfigProfile *draft = [self p_draftProfileForProbe];
    if (draft.apiKey.length == 0 || draft.model.length == 0) {
        [self showText:@"请先填写 API Key 与模型名"];
        return;
    }
    if ([self p_needsBaseURL] && draft.baseURL.length == 0) {
        [self showText:@"兼容格式需要填写 Base URL"];
        return;
    }
    self.busy = YES;
    [self showLoading:@"测试中…" cancel:^{
        self.busy = NO;
    }];
    __weak typeof(self) weakSelf = self;
    [[RDAIClient sharedClient] testProfile:draft completion:^(NSString *sample, NSError *error) {
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
                                     actions:@[
                [RDPaperAlertAction actionWithTitle:@"知道了" style:RDPaperAlertActionStylePrimary handler:nil],
            ]];
            return;
        }
        NSString *preview = sample.length > 120 ? [[sample substringToIndex:120] stringByAppendingString:@"…"] : sample;
        [RDPaperAlert showAlertWithTitle:@"测试成功"
                                 message:[NSString stringWithFormat:@"模型已响应:\n%@", preview]
                              symbolName:@"checkmark.circle"
                                 actions:@[
            [RDPaperAlertAction actionWithTitle:@"好的" style:RDPaperAlertActionStylePrimary handler:nil],
        ]];
    }];
}

#pragma mark - Table

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    return (NSInteger)self.rowMap.count;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section
{
    return (self.editMode == RDAIProfileEditModeTTS) ? @"AI 朗读引擎" : @"翻译服务";
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section
{
    if (self.editMode == RDAIProfileEditModeTTS) {
        if ([RDAIClient isMiMoType:self.editing.type]) {
            return @"小米 MiMo 使用 /v1/chat/completions 合成语音。TTS 模型推荐 mimo-v2.5-tts。保存后在「朗读语音 → AI 模型朗读」中选用。";
        }
        return @"OpenAI 使用 /v1/audio/speech。朗读配置与翻译服务相互独立。";
    }
    NSString *def = [RDAIClient defaultBaseURLForType:self.editing.type];
    NSString *hint = @"\n\n「探测模型」从服务商拉取可用模型并点选填入;「测试连接」发送短句验证 Key/模型是否可用。朗读请到下方「AI 朗读」分区单独配置。";
    if ([self p_needsBaseURL]) {
        return [@"兼容格式必须填写 Base URL。" stringByAppendingString:hint];
    }
    return [[NSString stringWithFormat:@"原生类型默认地址: %@。也可选填 Base URL 覆盖。", def] stringByAppendingString:hint];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    static NSString *cellId = @"RDAIEditCell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:cellId];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:cellId];
        cell.backgroundColor = RDSurfaceColor;
        cell.textLabel.font = RDFont16;
        cell.textLabel.textColor = RDBlackColor;
        cell.detailTextLabel.font = RDFont15;
        cell.detailTextLabel.textColor = RDLightGrayColor;
    }
    cell.accessoryView = nil;
    cell.accessoryType = UITableViewCellAccessoryNone;
    cell.detailTextLabel.text = nil;
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    cell.textLabel.textColor = RDBlackColor;

    RDAIEditRow row = [self p_rowAtIndex:indexPath.row];
    BOOL mimo = [RDAIClient isMiMoType:self.editing.type] || self.editing.usesMiMoSpeechAPI;

    switch (row) {
        case RDAIEditRowName: {
            cell.textLabel.text = @"名称";
            if (!self.nameField) {
                self.nameField = [self p_fieldWithPlaceholder:@"显示名称" text:self.editing.name secure:NO];
            }
            self.nameField.text = self.editing.name;
            cell.accessoryView = self.nameField;
            self.nameField.frame = CGRectMake(0, 0, tableView.width * 0.55, 36);
            break;
        }
        case RDAIEditRowType: {
            cell.textLabel.text = (self.editMode == RDAIProfileEditModeTTS) ? @"服务商" : @"类型";
            NSString *typeLabel = self.editing.type;
            if ([RDAIClient isMiMoType:self.editing.type]) {
                typeLabel = @"MiMo（小米）";
            }
            cell.detailTextLabel.text = typeLabel;
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
            cell.selectionStyle = UITableViewCellSelectionStyleDefault;
            break;
        }
        case RDAIEditRowAPIKey: {
            cell.textLabel.text = @"API Key";
            if (!self.keyField) {
                self.keyField = [self p_fieldWithPlaceholder:@"sk-... / key" text:self.editing.apiKey secure:YES];
            }
            self.keyField.text = self.editing.apiKey;
            cell.accessoryView = self.keyField;
            self.keyField.frame = CGRectMake(0, 0, tableView.width * 0.55, 36);
            break;
        }
        case RDAIEditRowModel: {
            cell.textLabel.text = @"翻译模型";
            if (!self.modelField) {
                self.modelField = [self p_fieldWithPlaceholder:@"model id" text:self.editing.model secure:NO];
            }
            self.modelField.text = self.editing.model;
            cell.accessoryView = self.modelField;
            self.modelField.frame = CGRectMake(0, 0, tableView.width * 0.55, 36);
            break;
        }
        case RDAIEditRowBaseURL: {
            BOOL need = [self p_needsBaseURL];
            cell.textLabel.text = need ? @"Base URL *" : @"Base URL";
            NSString *ph = [RDAIClient isMiMoType:self.editing.type]
                ? @"https://api.xiaomimimo.com/v1"
                : @"https://...";
            if (!self.baseField) {
                self.baseField = [self p_fieldWithPlaceholder:ph text:self.editing.baseURL secure:NO];
                self.baseField.keyboardType = UIKeyboardTypeURL;
            } else {
                self.baseField.placeholder = ph;
            }
            self.baseField.text = self.editing.baseURL;
            cell.accessoryView = self.baseField;
            self.baseField.frame = CGRectMake(0, 0, tableView.width * 0.55, 36);
            break;
        }
        case RDAIEditRowProbeModels: {
            cell.textLabel.text = @"探测模型";
            cell.detailTextLabel.text = @"从 API 拉取列表";
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
            cell.selectionStyle = UITableViewCellSelectionStyleDefault;
            cell.textLabel.textColor = [UIColor systemBlueColor];
            break;
        }
        case RDAIEditRowTest: {
            cell.textLabel.text = @"测试连接";
            cell.detailTextLabel.text = @"发送短句验证";
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
            cell.selectionStyle = UITableViewCellSelectionStyleDefault;
            cell.textLabel.textColor = [UIColor systemBlueColor];
            break;
        }
        case RDAIEditRowTTSModel: {
            cell.textLabel.text = @"TTS 模型";
            NSString *placeholder = mimo ? @"mimo-v2.5-tts" : @"tts-1";
            NSString *fallback = mimo ? @"mimo-v2.5-tts" : @"tts-1";
            if (!self.ttsModelField) {
                self.ttsModelField = [self p_fieldWithPlaceholder:placeholder text:self.editing.ttsModel secure:NO];
            } else {
                self.ttsModelField.placeholder = placeholder;
            }
            self.ttsModelField.text = self.editing.ttsModel.length ? self.editing.ttsModel : fallback;
            cell.accessoryView = self.ttsModelField;
            self.ttsModelField.frame = CGRectMake(0, 0, tableView.width * 0.55, 36);
            break;
        }
        case RDAIEditRowTTSVoice: {
            cell.textLabel.text = @"TTS 音色";
            NSString *fallback = mimo ? @"mimo_default" : @"alloy";
            cell.detailTextLabel.text = self.editing.ttsVoice.length ? self.editing.ttsVoice : fallback;
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
            cell.selectionStyle = UITableViewCellSelectionStyleDefault;
            break;
        }
    }
    return cell;
}

- (void)p_pickTTSVoice
{
    BOOL mimo = [RDAIClient isMiMoType:self.editing.type] || self.editing.usesMiMoSpeechAPI;
    NSArray *voices = mimo ? [RDAIConfigProfile commonMiMoTTSVoices] : [RDAIConfigProfile commonTTSVoices];
    NSString *msg = mimo
        ? @"MiMo 内置音色:mimo_default / 冰糖 / 茉莉 / 苏打 / 白桦 / Mia / Chloe / Milo / Dean"
        : @"OpenAI /v1/audio/speech 的 voice 参数";
    __weak typeof(self) weakSelf = self;
    NSMutableArray *actions = [NSMutableArray array];
    for (NSString *v in voices) {
        [actions addObject:[RDPaperAlertAction actionWithTitle:v style:RDPaperAlertActionStyleDefault handler:^{
            weakSelf.editing.ttsVoice = v;
            [weakSelf.tableView reloadData];
        }]];
    }
    [RDPaperAlert showActionSheetWithTitle:@"选择 TTS 音色" message:msg actions:actions];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    RDAIEditRow row = [self p_rowAtIndex:indexPath.row];
    if (row == RDAIEditRowType) {
        [self p_pickType];
    } else if (row == RDAIEditRowTTSVoice) {
        [self p_pickTTSVoice];
    } else if (row == RDAIEditRowProbeModels) {
        [self p_probeModels];
    } else if (row == RDAIEditRowTest) {
        [self p_testConnection];
    }
}

- (void)textFieldDidEndEditing:(UITextField *)textField
{
    if (textField == self.nameField) {
        self.editing.name = textField.text ?: @"";
    } else if (textField == self.keyField) {
        self.editing.apiKey = textField.text ?: @"";
    } else if (textField == self.modelField) {
        self.editing.model = textField.text ?: @"";
    } else if (textField == self.baseField) {
        self.editing.baseURL = textField.text ?: @"";
    } else if (textField == self.ttsModelField) {
        BOOL mimo = [RDAIClient isMiMoType:self.editing.type] || self.editing.usesMiMoSpeechAPI;
        NSString *fallback = mimo ? @"mimo-v2.5-tts" : @"tts-1";
        self.editing.ttsModel = textField.text.length ? textField.text : fallback;
    }
}

@end
