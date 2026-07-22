//
//  RDReadBookmarkView.m
//  Reader
//

#import "RDReadBookmarkView.h"
#import "RDBookmarkManager.h"
#import "RDBookmarkModel.h"
#import "RDBookDetailModel.h"
#import "RDReadConfigManager.h"

@interface RDReadBookmarkView () <UITableViewDelegate, UITableViewDataSource>
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UIButton *addBtn;
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, copy) NSArray <RDBookmarkModel *>*items;
@end

@implementation RDReadBookmarkView

- (instancetype)initWithFrame:(CGRect)frame
{
    self = [super initWithFrame:frame];
    if (self) {
        [self addSubview:self.titleLabel];
        [self addSubview:self.addBtn];
        [self addSubview:self.tableView];
        UIView *line = [[UIView alloc] initWithFrame:CGRectMake(0, 0, ScreenWidth, 1.0 / UIScreen.mainScreen.scale)];
        line.tag = 8801;
        line.autoresizingMask = UIViewAutoresizingFlexibleWidth;
        [self addSubview:line];
        [self applyChromeTheme];
    }
    return self;
}

- (void)applyChromeTheme
{
    RDReadConfigManager *cfg = [RDReadConfigManager sharedInstance];
    self.backgroundColor = [cfg chromeBackgroundColor];
    self.titleLabel.textColor = [cfg chromeForegroundColor];
    [self.addBtn setTitleColor:RDAccentColor forState:UIControlStateNormal];
    self.tableView.separatorColor = [cfg chromeSeparatorColor];
    UIView *line = [self viewWithTag:8801];
    line.backgroundColor = [cfg chromeSeparatorColor];
    [self.tableView reloadData];
}

- (void)setBook:(RDBookDetailModel *)book
{
    _book = book;
    [self reloadData];
}

- (void)reloadData
{
    self.items = [RDBookmarkManager bookmarksForBookId:self.book.bookId];
    self.titleLabel.text = [NSString stringWithFormat:@"书签 · %@", @(self.items.count)];
    [self.tableView reloadData];
}

- (UILabel *)titleLabel
{
    if (!_titleLabel) {
        _titleLabel = [[UILabel alloc] init];
        _titleLabel.font = RDBoldFont16;
        _titleLabel.textColor = RDBlackColor;
        _titleLabel.text = @"书签";
    }
    return _titleLabel;
}

- (UIButton *)addBtn
{
    if (!_addBtn) {
        _addBtn = [UIButton buttonWithType:UIButtonTypeSystem];
        [_addBtn setTitle:@"添加当前页" forState:UIControlStateNormal];
        _addBtn.titleLabel.font = RDBoldFont15;
        [_addBtn setTitleColor:RDAccentColor forState:UIControlStateNormal];
        [_addBtn addTarget:self action:@selector(p_add) forControlEvents:UIControlEventTouchUpInside];
    }
    return _addBtn;
}

- (UITableView *)tableView
{
    if (!_tableView) {
        _tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
        _tableView.backgroundColor = [UIColor clearColor];
        _tableView.delegate = self;
        _tableView.dataSource = self;
        _tableView.rowHeight = 68;
        _tableView.separatorColor = RDLightSeparatorColor;
        _tableView.tableFooterView = [UIView new];
    }
    return _tableView;
}

- (void)layoutSubviews
{
    [super layoutSubviews];
    self.titleLabel.frame = CGRectMake(16, 10, self.width - 140, 28);
    self.addBtn.frame = CGRectMake(self.width - 120, 8, 104, 32);
    self.tableView.frame = CGRectMake(0, 44, self.width, self.height - 44);
}

- (void)p_add
{
    if ([self.delegate respondsToSelector:@selector(bookmarkViewDidAddCurrent)]) {
        [self.delegate bookmarkViewDidAddCurrent];
    }
    [self reloadData];
}

#pragma mark - Table

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    if (self.items.count == 0) {
        return 1;
    }
    return self.items.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    RDReadConfigManager *cfg = [RDReadConfigManager sharedInstance];
    UIColor *fg = [cfg chromeForegroundColor];
    UIColor *sec = [cfg chromeSecondaryColor];
    if (self.items.count == 0) {
        static NSString *emptyId = @"empty";
        UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:emptyId];
        if (!cell) {
            cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:emptyId];
            cell.textLabel.font = RDFont14;
            cell.textLabel.textAlignment = NSTextAlignmentCenter;
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
            cell.backgroundColor = [UIColor clearColor];
        }
        cell.textLabel.textColor = sec;
        cell.textLabel.text = @"暂无书签，点右上角添加当前页";
        return cell;
    }
    static NSString *cid = @"bm";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:cid];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:cid];
        cell.textLabel.font = RDBoldFont15;
        cell.detailTextLabel.font = RDFont12;
        cell.detailTextLabel.numberOfLines = 2;
        cell.backgroundColor = [UIColor clearColor];
    }
    cell.textLabel.textColor = fg;
    cell.detailTextLabel.textColor = sec;
    RDBookmarkModel *bm = self.items[indexPath.row];
    cell.textLabel.text = bm.charpterName.length ? bm.charpterName : @"未命名章节";
    NSString *time = [self p_formatTime:bm.createTime];
    NSString *snip = bm.snippet.length ? bm.snippet : @"（无摘录）";
    cell.detailTextLabel.text = [NSString stringWithFormat:@"%@ · %@", time, snip];
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (self.items.count == 0) {
        return;
    }
    RDBookmarkModel *bm = self.items[indexPath.row];
    if ([self.delegate respondsToSelector:@selector(bookmarkViewDidSelect:)]) {
        [self.delegate bookmarkViewDidSelect:bm];
    }
}

- (UISwipeActionsConfiguration *)tableView:(UITableView *)tableView trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath
{
    if (self.items.count == 0) {
        return nil;
    }
    RDBookmarkModel *bm = self.items[indexPath.row];
    __weak typeof(self) weakSelf = self;
    UIContextualAction *del = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleDestructive
                                                                      title:@"删除"
                                                                    handler:^(__kindof UIContextualAction *action, __kindof UIView *sourceView, void (^completionHandler)(BOOL)) {
        BOOL ok = [RDBookmarkManager deleteBookmark:bm];
        if (ok) {
            [weakSelf reloadData];
            completionHandler(YES);
        } else {
            // 失败时保留行,不伪装成功(Issue 9 / P2-DB-03)
            [RDToastView showText:@"删除书签失败" delay:1.2 inView:weakSelf];
            completionHandler(NO);
        }
    }];
    return [UISwipeActionsConfiguration configurationWithActions:@[del]];
}

- (NSString *)p_formatTime:(NSTimeInterval)ts
{
    if (ts <= 0) {
        return @"";
    }
    NSDateFormatter *fmt = [[NSDateFormatter alloc] init];
    fmt.dateFormat = @"MM-dd HH:mm";
    return [fmt stringFromDate:[NSDate dateWithTimeIntervalSince1970:ts]];
}

@end
