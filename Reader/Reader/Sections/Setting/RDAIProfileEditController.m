//
//  RDAIProfileEditController.m
//  Reader
//

#import "RDAIProfileEditController.h"
#import "RDAIConfig.h"
#import "RDAIClient.h"

typedef NS_ENUM(NSInteger, RDAIEditRow) {
    RDAIEditRowName = 0,
    RDAIEditRowType,
    RDAIEditRowAPIKey,
    RDAIEditRowModel,
    RDAIEditRowBaseURL,
    RDAIEditRowCount,
};

@interface RDAIProfileEditController () <UITableViewDelegate, UITableViewDataSource, UITextFieldDelegate>
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) RDAIConfigProfile *editing;
@property (nonatomic, strong) UITextField *nameField;
@property (nonatomic, strong) UITextField *keyField;
@property (nonatomic, strong) UITextField *modelField;
@property (nonatomic, strong) UITextField *baseField;
@end

@implementation RDAIProfileEditController

- (void)viewDidLoad
{
    [super viewDidLoad];
    if (self.profile) {
        self.editing = [self.profile copy];
        self.topView.titleLabel.text = @"编辑 AI 配置";
    } else {
        self.editing = [[RDAIConfigProfile alloc] init];
        self.editing.name = @"默认";
        self.editing.type = RDAIProviderTypeOpenAI;
        self.editing.model = @"gpt-4o-mini";
        self.topView.titleLabel.text = @"添加 AI 配置";
    }
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

- (void)p_save
{
    [self.view endEditing:YES];
    self.editing.name = self.nameField.text ?: @"";
    self.editing.apiKey = self.keyField.text ?: @"";
    self.editing.model = self.modelField.text ?: @"";
    self.editing.baseURL = self.baseField.text ?: @"";
    if (self.editing.apiKey.length == 0) {
        [self showText:@"请填写 API Key"];
        return;
    }
    if (self.editing.model.length == 0) {
        [self showText:@"请填写模型名"];
        return;
    }
    if ([self p_needsBaseURL] && self.editing.baseURL.length == 0) {
        [self showText:@"兼容格式需要填写 Base URL"];
        return;
    }
    if (self.editing.name.length == 0) {
        self.editing.name = self.editing.type;
    }
    [[RDAIConfigStore sharedInstance] upsertProfile:self.editing];
    [self showText:@"已保存"];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.4 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self.navigationController popViewControllerAnimated:YES];
    });
}

- (void)p_pickType
{
    NSArray *types = [RDAIConfigStore allProviderTypes];
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:@"选择类型" message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    __weak typeof(self) weakSelf = self;
    for (NSString *type in types) {
        [sheet addAction:[UIAlertAction actionWithTitle:type style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
            weakSelf.editing.type = type;
            // 切换类型时给合理默认 model
            if ([RDAIClient isOpenAIFamily:type] && weakSelf.editing.model.length == 0) {
                weakSelf.editing.model = @"gpt-4o-mini";
            } else if ([RDAIClient isAnthropicFamily:type] && (weakSelf.editing.model.length == 0 || [weakSelf.editing.model hasPrefix:@"gpt"] || [weakSelf.editing.model hasPrefix:@"gemini"])) {
                weakSelf.editing.model = @"claude-3-5-sonnet-latest";
            } else if ([RDAIClient isGeminiFamily:type] && (weakSelf.editing.model.length == 0 || [weakSelf.editing.model hasPrefix:@"gpt"] || [weakSelf.editing.model hasPrefix:@"claude"])) {
                weakSelf.editing.model = @"gemini-2.0-flash";
            }
            [weakSelf.tableView reloadData];
        }]];
    }
    [sheet addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    sheet.popoverPresentationController.sourceView = self.view;
    sheet.popoverPresentationController.sourceRect = CGRectMake(self.view.width / 2, self.view.height / 2, 1, 1);
    [self presentViewController:sheet animated:YES completion:nil];
}

#pragma mark - Table

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    return RDAIEditRowCount;
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section
{
    NSString *def = [RDAIClient defaultBaseURLForType:self.editing.type];
    if ([self p_needsBaseURL]) {
        return @"兼容格式必须填写 Base URL(例如 https://your-proxy.example.com ),请求路径会自动拼接 /v1/chat/completions、/v1/messages 或 Gemini generateContent。";
    }
    return [NSString stringWithFormat:@"原生类型默认地址: %@。也可选填 Base URL 覆盖。", def];
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
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
    }
    cell.accessoryView = nil;
    cell.accessoryType = UITableViewCellAccessoryNone;
    cell.detailTextLabel.text = nil;
    cell.selectionStyle = UITableViewCellSelectionStyleNone;

    switch ((RDAIEditRow)indexPath.row) {
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
            cell.textLabel.text = @"类型";
            cell.detailTextLabel.text = self.editing.type;
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
            cell.textLabel.text = @"模型";
            if (!self.modelField) {
                self.modelField = [self p_fieldWithPlaceholder:@"model id" text:self.editing.model secure:NO];
            }
            self.modelField.text = self.editing.model;
            cell.accessoryView = self.modelField;
            self.modelField.frame = CGRectMake(0, 0, tableView.width * 0.55, 36);
            break;
        }
        case RDAIEditRowBaseURL: {
            cell.textLabel.text = [self p_needsBaseURL] ? @"Base URL *" : @"Base URL";
            if (!self.baseField) {
                self.baseField = [self p_fieldWithPlaceholder:@"https://..." text:self.editing.baseURL secure:NO];
                self.baseField.keyboardType = UIKeyboardTypeURL;
            }
            self.baseField.text = self.editing.baseURL;
            cell.accessoryView = self.baseField;
            self.baseField.frame = CGRectMake(0, 0, tableView.width * 0.55, 36);
            break;
        }
        default:
            break;
    }
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.row == RDAIEditRowType) {
        [self p_pickType];
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
    }
}

@end
