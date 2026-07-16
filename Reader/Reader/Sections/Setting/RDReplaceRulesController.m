//
//  RDReplaceRulesController.m
//  Reader
//

#import "RDReplaceRulesController.h"
#import "RDReplaceRule.h"
#import "LEEAlert.h"

@interface RDReplaceRulesController () <UITableViewDelegate, UITableViewDataSource>
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, copy) NSArray <RDReplaceRule *>*rules;
@end

@implementation RDReplaceRulesController

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.topView.titleLabel.text = @"正文净化";
    UIButton *add = [UIButton buttonWithType:UIButtonTypeSystem];
    [add setTitle:@"添加" forState:UIControlStateNormal];
    add.titleLabel.font = RDFont16;
    [add addTarget:self action:@selector(p_add) forControlEvents:UIControlEventTouchUpInside];
    [self.topView addSubview:add];
    add.translatesAutoresizingMaskIntoConstraints = NO;
    [NSLayoutConstraint activateConstraints:@[
        [add.trailingAnchor constraintEqualToAnchor:self.topView.trailingAnchor constant:-16],
        [add.centerYAnchor constraintEqualToAnchor:self.topView.titleLabel.centerYAnchor],
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
        _tableView.rowHeight = 64;
    }
    return _tableView;
}

- (void)p_reload
{
    self.rules = [RDReplaceRuleStore sharedInstance].rules;
    [self.tableView reloadData];
}

- (void)p_add
{
    [self p_editRule:nil];
}

- (void)p_editRule:(RDReplaceRule *)rule
{
    RDReplaceRule *editing = rule ? [rule copy] : [[RDReplaceRule alloc] init];
    if (!rule) {
        editing.name = @"新规则";
        editing.isRegex = YES;
        editing.isEnabled = YES;
    }
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:rule ? @"编辑规则" : @"添加规则"
                                                                   message:@"支持正则;替换为空即删除匹配内容"
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *tf) {
        tf.placeholder = @"名称";
        tf.text = editing.name;
    }];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *tf) {
        tf.placeholder = @"匹配(正则或原文)";
        tf.text = editing.pattern;
        tf.autocapitalizationType = UITextAutocapitalizationTypeNone;
    }];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *tf) {
        tf.placeholder = @"替换为(可空)";
        tf.text = editing.replacement;
        tf.autocapitalizationType = UITextAutocapitalizationTypeNone;
    }];
    __weak typeof(self) weakSelf = self;
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"保存" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        editing.name = alert.textFields[0].text ?: @"";
        editing.pattern = alert.textFields[1].text ?: @"";
        editing.replacement = alert.textFields[2].text ?: @"";
        if (editing.pattern.length == 0) {
            return;
        }
        [[RDReplaceRuleStore sharedInstance] upsertRule:editing];
        [weakSelf p_reload];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

#pragma mark - Table

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    return self.rules.count;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section
{
    return @"阅读时自动应用已启用的规则(对齐legado替换净化)";
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    static NSString *cid = @"rule";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:cid];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:cid];
        cell.backgroundColor = RDSurfaceColor;
        cell.textLabel.font = RDFont16;
        cell.detailTextLabel.font = RDFont12;
        cell.detailTextLabel.textColor = RDLightGrayColor;
        cell.detailTextLabel.numberOfLines = 2;
    }
    RDReplaceRule *r = self.rules[indexPath.row];
    cell.textLabel.text = r.name.length ? r.name : @"未命名";
    cell.detailTextLabel.text = [NSString stringWithFormat:@"%@ · %@", r.isRegex ? @"正则" : @"原文", r.pattern];
    UISwitch *sw = [[UISwitch alloc] init];
    sw.on = r.isEnabled;
    sw.tag = indexPath.row;
    [sw addTarget:self action:@selector(p_toggle:) forControlEvents:UIControlEventValueChanged];
    cell.accessoryView = sw;
    return cell;
}

- (void)p_toggle:(UISwitch *)sw
{
    if (sw.tag < 0 || sw.tag >= (NSInteger)self.rules.count) {
        return;
    }
    RDReplaceRule *r = [self.rules[sw.tag] copy];
    r.isEnabled = sw.on;
    [[RDReplaceRuleStore sharedInstance] upsertRule:r];
    [self p_reload];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    RDReplaceRule *r = self.rules[indexPath.row];
    __weak typeof(self) weakSelf = self;
    [LEEAlert actionsheet].config
    .LeeAddAction(^(LEEAction *action) {
        action.title = @"编辑";
        action.clickBlock = ^{ [weakSelf p_editRule:r]; };
    })
    .LeeAddAction(^(LEEAction *action) {
        action.type = LEEActionTypeDestructive;
        action.title = @"删除";
        action.clickBlock = ^{
            [[RDReplaceRuleStore sharedInstance] removeRuleId:r.ruleId];
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
