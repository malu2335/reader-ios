//
//  RDAIConfigController.m
//  Reader
//

#import "RDAIConfigController.h"
#import "RDAIConfig.h"
#import "RDAIProfileEditController.h"
#import "LEEAlert.h"

@interface RDAIConfigController () <UITableViewDelegate, UITableViewDataSource>
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, copy) NSArray <RDAIConfigProfile *>*profiles;
@end

@implementation RDAIConfigController

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.topView.titleLabel.text = @"AI 配置";
    UIButton *addBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    [addBtn setTitle:@"添加" forState:UIControlStateNormal];
    addBtn.titleLabel.font = RDFont16;
    [addBtn addTarget:self action:@selector(p_add) forControlEvents:UIControlEventTouchUpInside];
    [self.topView addSubview:addBtn];
    addBtn.translatesAutoresizingMaskIntoConstraints = NO;
    [NSLayoutConstraint activateConstraints:@[
        [addBtn.trailingAnchor constraintEqualToAnchor:self.topView.trailingAnchor constant:-16],
        [addBtn.centerYAnchor constraintEqualToAnchor:self.topView.titleLabel.centerYAnchor],
    ]];
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
        _tableView.rowHeight = 60;
    }
    return _tableView;
}

- (void)p_reload
{
    self.profiles = [RDAIConfigStore sharedInstance].profiles;
    [self.tableView reloadData];
}

- (void)p_add
{
    RDAIProfileEditController *edit = [[RDAIProfileEditController alloc] init];
    edit.profile = nil;
    [self.navigationController pushViewController:edit animated:YES];
}

#pragma mark - UITableView

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    return MAX(self.profiles.count, 1);
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section
{
    return @"翻译服务配置(OpenAI / Anthropic / Gemini 及兼容格式)";
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section
{
    return @"在阅读页点击「翻译」将使用当前选中的配置。备份恢复的配置需手动「设为当前」确认后才可出站。兼容格式需填写自定义 Base URL(默认 HTTPS;本机/局域网 HTTP 仅用于 Ollama 等本地服务)。";
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
        cell.detailTextLabel.numberOfLines = 2;
    }
    if (self.profiles.count == 0) {
        cell.textLabel.text = @"尚未配置,点击添加";
        cell.detailTextLabel.text = @"支持 OpenAI、Anthropic、Gemini 及兼容格式";
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        cell.accessoryView = nil;
        return cell;
    }
    RDAIConfigProfile *p = self.profiles[indexPath.row];
    NSString *title = p.name.length > 0 ? p.name : p.type;
    cell.textLabel.text = title;
    NSString *detail = [NSString stringWithFormat:@"%@ · %@", p.type, p.model.length > 0 ? p.model : @"未填模型"];
    if (p.baseURL.length > 0) {
        detail = [detail stringByAppendingFormat:@"\n%@", p.baseURL];
    }
    if (p.pendingConfirm) {
        detail = [detail stringByAppendingString:@"\n备份导入 · 待确认(设为当前后可用)"];
    }
    cell.detailTextLabel.text = detail;
    BOOL active = p.profileId.length > 0
        && [[RDAIConfigStore sharedInstance].activeProfileId isEqualToString:p.profileId];
    if (active) {
        UIImageSymbolConfiguration *cfg = [UIImageSymbolConfiguration configurationWithPointSize:16 weight:UIImageSymbolWeightSemibold];
        UIImage *check = [UIImage systemImageNamed:@"checkmark.circle.fill" withConfiguration:cfg];
        UIImageView *iv = [[UIImageView alloc] initWithImage:[check imageWithTintColor:[UIColor systemGreenColor] renderingMode:UIImageRenderingModeAlwaysOriginal]];
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
    if (self.profiles.count == 0) {
        [self p_add];
        return;
    }
    RDAIConfigProfile *p = self.profiles[indexPath.row];
    __weak typeof(self) weakSelf = self;
    [LEEAlert actionsheet].config
    .LeeAddAction(^(LEEAction *action) {
        action.title = @"设为当前";
        action.clickBlock = ^{
            [[RDAIConfigStore sharedInstance] setActiveProfileId:p.profileId];
            [weakSelf p_reload];
        };
    })
    .LeeAddAction(^(LEEAction *action) {
        action.title = @"编辑";
        action.clickBlock = ^{
            RDAIProfileEditController *edit = [[RDAIProfileEditController alloc] init];
            edit.profile = p;
            [weakSelf.navigationController pushViewController:edit animated:YES];
        };
    })
    .LeeAddAction(^(LEEAction *action) {
        action.type = LEEActionTypeDestructive;
        action.title = @"删除";
        action.clickBlock = ^{
            [[RDAIConfigStore sharedInstance] removeProfileId:p.profileId];
            [weakSelf p_reload];
        };
    })
    .LeeAddAction(^(LEEAction *action) {
        action.type = LEEActionTypeCancel;
        action.title = @"取消";
    })
    .LeeShow();
}

@end
