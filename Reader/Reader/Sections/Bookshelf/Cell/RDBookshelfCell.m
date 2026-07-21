//
//  RDBookshelfCell.m
//  Reader
//
//  书架宫格:点击阅读 / 长按 分享·改名·删除 等
//

#import "RDBookshelfCell.h"
#import "RDBookDetailModel.h"
#import "UIImageView+WebCache.h"
#import "UIView+WebCache.h"
#import "RDReadRecordManager.h"
#import "RDReadPageViewController.h"
#import "RDCharpterManager.h"
#import "RDPaperAlert.h"
#import "RDCharpterDataManager.h"
#import "RDLocalBookManager.h"
#import "RDCharpterModel.h"
#import "RDBookmarkManager.h"
#import "RDHistoryRecordManager.h"

#define kItemCount ([RDUtilities iPad] ? 5 : 3)
#define kShelfTopPad 14.f
#define kShelfHSpace 22.f

@interface RDBookshelfCoverView : UIView
@property (nonatomic,strong) UIImageView *cover;
@property (nonatomic,strong) UILabel *bookLabel;
@property (nonatomic,strong) UILabel *authorLabel;
@property (nonatomic,strong) UIImageView *updateTag;
@property (nonatomic,strong) UILabel *typeTag;
@property (nonatomic,strong) UIView *shadowHost;
@property (nonatomic,strong) RDBookDetailModel *book;
@end

@implementation RDBookshelfCoverView
- (instancetype)initWithFrame:(CGRect)frame
{
    self = [super initWithFrame:frame];
    if (self) {
        [self addSubview:self.shadowHost];
        [self.shadowHost addSubview:self.cover];
        [self addSubview:self.bookLabel];
        [self addSubview:self.authorLabel];
        [self.cover addSubview:self.updateTag];
        [self.cover addSubview:self.typeTag];
    }
    return self;
}

-(void)setBook:(RDBookDetailModel *)book
{
    _book = book;
    UIImage *cover = [RDLocalBookManager coverForBook:book];
    if (cover) {
        [self.cover sd_cancelCurrentImageLoad];
        self.cover.image = cover;
    } else {
        [self.cover sd_cancelCurrentImageLoad];
        self.cover.image = [UIImage imageNamed:@"app_placeholder"];
    }

    self.typeTag.hidden = !book.isLocalBook;
    if (book.isLocalBook) {
        self.typeTag.text = book.fileType.uppercaseString;
        [self.typeTag sizeToFit];
        [self setNeedsLayout];
    }
    self.updateTag.hidden = !book.bookUpdate;
    self.bookLabel.text = book.title;
    // 阅读记忆:优先 readChapterName(轻量列表),其次 charpterModel
    NSString *chapter = book.readChapterName.length ? book.readChapterName : book.charpterModel.name;
    if (chapter.length) {
        self.authorLabel.text = [NSString stringWithFormat:@"读到 · %@", chapter];
    } else {
        self.authorLabel.text = book.author.length ? book.author : @"未知作者";
    }
}

-(UIView *)shadowHost
{
    if (!_shadowHost) {
        _shadowHost = [[UIView alloc] init];
        _shadowHost.layer.shadowColor = [UIColor colorWithWhite:0 alpha:0.18].CGColor;
        _shadowHost.layer.shadowOpacity = 1;
        _shadowHost.layer.shadowRadius = 8;
        _shadowHost.layer.shadowOffset = CGSizeMake(0, 4);
    }
    return _shadowHost;
}

-(UIImageView *)cover
{
    if(!_cover){
        _cover = [[UIImageView alloc] init];
        _cover.contentMode = UIViewContentModeScaleAspectFill;
        _cover.clipsToBounds = YES;
        _cover.layer.cornerRadius = 6;
    }
    return _cover;
}

-(UIImageView *)updateTag
{
    if (!_updateTag) {
        _updateTag = [[UIImageView alloc] initWithImage:[UIImage imageNamed:@"ic_update"]];
        _updateTag.hidden = YES;
    }
    return _updateTag;
}

-(UILabel *)bookLabel
{
    if (!_bookLabel) {
        _bookLabel = [[UILabel alloc] init];
        _bookLabel.font = RDBoldFont13;
        _bookLabel.textColor = RDBlackColor;
        _bookLabel.numberOfLines = 2;
    }
    return _bookLabel;
}

-(UILabel *)authorLabel
{
    if (!_authorLabel) {
        _authorLabel = [[UILabel alloc] init];
        _authorLabel.font = RDFont11;
        _authorLabel.textColor = RDLightGrayColor;
    }
    return _authorLabel;
}

-(UILabel *)typeTag
{
    if (!_typeTag) {
        _typeTag = [[UILabel alloc] init];
        _typeTag.font = [UIFont systemFontOfSize:9 weight:UIFontWeightSemibold];
        _typeTag.textColor = [UIColor whiteColor];
        _typeTag.backgroundColor = [RDAccentColor colorWithAlphaComponent:0.9];
        _typeTag.textAlignment = NSTextAlignmentCenter;
        _typeTag.layer.cornerRadius = 3;
        _typeTag.clipsToBounds = YES;
        _typeTag.hidden = YES;
    }
    return _typeTag;
}

-(void)layoutSubviews
{
    [super layoutSubviews];
    CGFloat coverH = self.height - 58;
    self.shadowHost.frame = CGRectMake(0, 0, self.width, coverH);
    self.cover.frame = self.shadowHost.bounds;
    self.updateTag.frame = CGRectMake(0, 0, 28, 15);
    self.updateTag.right = self.cover.width-4;
    self.typeTag.frame = CGRectMake(4, self.cover.height-18, self.typeTag.width+10, 14);
    self.bookLabel.frame = CGRectMake(0, self.shadowHost.bottom+8, self.width, RDBoldFont13.lineHeight * 2);
    self.authorLabel.frame = CGRectMake(0, self.height - RDFont11.lineHeight, self.width, RDFont11.lineHeight);
}

@end


@interface RDBookshelfCell ()
@property (nonatomic,strong) NSArray <RDBookshelfCoverView *>*items;
@end

@implementation RDBookshelfCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier
{
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (self) {
        self.selectionStyle = UITableViewCellSelectionStyleNone;
        self.backgroundColor = [UIColor clearColor];
        self.contentView.backgroundColor = [UIColor clearColor];
        for (RDBookshelfCoverView *view in self.items) {
            [self.contentView addSubview:view];
        }
    }
    return self;
}

-(NSArray <RDBookshelfCoverView *>*)items
{
    if (!_items) {
        NSMutableArray *array = [NSMutableArray array];
        for (int i = 0; i<kItemCount; i++) {
            RDBookshelfCoverView *view = [[RDBookshelfCoverView alloc] init];
            [view addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(tap:)]];
            UILongPressGestureRecognizer *lp = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(longPress:)];
            lp.minimumPressDuration = 0.22;
            [view addGestureRecognizer:lp];
            [array addObject:view];
        }
        _items = array.copy;
    }
    return _items;
}

-(void)tap:(UITapGestureRecognizer *)ges
{
    RDBookshelfCoverView *view = (RDBookshelfCoverView *)ges.view;
    RDBookDetailModel *model = view.book;
    if (model){
        if (model.bookUpdate) {
            [RDReadRecordManager updateOnBookselfUpdateWithBookId:model.bookId update:NO];
            if (self.needReload) {
                self.needReload();
            }
        }
        [RDReadHelper beginReadWithBookDetail:model];
    }
}

#pragma mark - 长按菜单

-(void)longPress:(UILongPressGestureRecognizer *)ges
{
    if (ges.state != UIGestureRecognizerStateBegan) {
        return;
    }
    RDBookshelfCoverView *coverView = (RDBookshelfCoverView *)ges.view;
    RDBookDetailModel *book = coverView.book;
    if (!book) {
        return;
    }
    // 轻微触感
    if (@available(iOS 10.0, *)) {
        UIImpactFeedbackGenerator *gen = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium];
        [gen impactOccurred];
    }

    __weak typeof(self) weakSelf = self;
    NSMutableArray *actions = [NSMutableArray array];
    [actions addObject:[RDPaperAlertAction actionWithTitle:@"分享书籍" style:RDPaperAlertActionStyleDefault handler:^{
        [weakSelf p_shareBook:book];
    }]];
    [actions addObject:[RDPaperAlertAction actionWithTitle:@"修改书名" style:RDPaperAlertActionStyleDefault handler:^{
        [weakSelf p_renameBook:book];
    }]];
    [actions addObject:[RDPaperAlertAction actionWithTitle:@"更换封面" style:RDPaperAlertActionStyleDefault handler:^{
        if (weakSelf.changeCover) {
            weakSelf.changeCover(book);
        }
    }]];
    if ([RDLocalBookManager customCoverForBook:book]) {
        [actions addObject:[RDPaperAlertAction actionWithTitle:@"恢复默认封面" style:RDPaperAlertActionStyleDefault handler:^{
            if (weakSelf.resetCover) {
                weakSelf.resetCover(book);
            }
        }]];
    }
    [actions addObject:[RDPaperAlertAction actionWithTitle:@"删除" style:RDPaperAlertActionStyleDestructive handler:^{
        [weakSelf p_confirmDelete:book];
    }]];
    [RDPaperAlert showActionSheetWithTitle:nil message:nil actions:actions];
}

- (void)p_shareBook:(RDBookDetailModel *)book
{
    NSString *text = [NSString stringWithFormat:@"我正在读《%@》%@，推荐给你。#纸羽轻阅",
                      book.title ?: @"",
                      book.author.length ? [NSString stringWithFormat:@"（%@）", book.author] : @""];
    NSMutableArray *items = [NSMutableArray arrayWithObject:text];
    UIImage *cover = [RDLocalBookManager coverForBook:book];
    if (cover) {
        [items addObject:cover];
    }
    UIActivityViewController *avc = [[UIActivityViewController alloc] initWithActivityItems:items applicationActivities:nil];
    UIViewController *vc = [RDUtilities getCurrentVC];
    avc.popoverPresentationController.sourceView = vc.view;
    avc.popoverPresentationController.sourceRect = CGRectMake(vc.view.width/2, vc.view.height/2, 1, 1);
    [vc presentViewController:avc animated:YES completion:nil];
}

- (void)p_renameBook:(RDBookDetailModel *)book
{
    __weak typeof(self) weakSelf = self;
    NSString *msg = book.author.length ? [NSString stringWithFormat:@"作者：%@", book.author] : nil;
    [RDPaperAlert showTextFieldsWithTitle:@"修改书名"
                                  message:msg
                               fieldSpecs:@[
        @{@"placeholder": @"书名", @"text": book.title ?: @""},
        @{@"placeholder": @"作者(可选)", @"text": book.author ?: @""},
    ]
                              cancelTitle:@"取消"
                             confirmTitle:@"保存"
                                  confirm:^(NSArray<NSString *> *values) {
        NSString *title = [values[0] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        NSString *author = [values[1] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (title.length == 0) {
            return;
        }
        book.title = title;
        if (author) {
            book.author = author;
        }
        // 书架传入的是轻量投影(无 charpterModel 等列),整行回写会清掉阅读进度;只按列改书名/作者
        [RDReadRecordManager updateTitle:title author:author forBookId:book.bookId];
        if (weakSelf.needReload) {
            weakSelf.needReload();
        }
    }];
}

- (void)p_confirmDelete:(RDBookDetailModel *)book
{
    __weak typeof(self) weakSelf = self;
    [RDPaperAlert showConfirmWithTitle:@"删除书籍"
                               message:[NSString stringWithFormat:@"确定删除《%@》？本地文件与章节缓存将一并清除。", book.title ?: @""]
                           cancelTitle:@"取消"
                          confirmTitle:@"删除"
                           destructive:YES
                               confirm:^{
        // 文件/PDF 回填可能正在串行队列中，删除放后台避免阻塞主线程。
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
            if (book.isLocalBook) {
                [RDLocalBookManager removeLocalBook:book];
            } else {
                [RDReadRecordManager removeBookFromBookShelfWithBookId:book.bookId];
                [RDLocalBookManager removeCustomCoverForBook:book];
                [RDBookmarkManager deleteAllForBookId:book.bookId];
                [RDHistoryRecordManager deleteHistoryWithBookId:book.bookId];
                [RDCharpterDataManager deleteAllCharpterWithBookId:book.bookId];
            }
            dispatch_async(dispatch_get_main_queue(), ^{
                if (weakSelf.needReload) {
                    weakSelf.needReload();
                }
            });
        });
    }];
}

-(void)setBooks:(NSArray<RDBookDetailModel *> *)books
{
    _books = books;
    for (int i=0; i<books.count; i++) {
        self.items[i].book = books[i];
        self.items[i].hidden = NO;
    }
    if (self.items.count>books.count) {
        for (NSInteger i=self.items.count-1; i>self.books.count-1; i--) {
            self.items[i].hidden = YES;
        }
    }
}

-(void)layoutSubviews
{
    [super layoutSubviews];
    CGFloat space = kShelfHSpace;
    CGFloat width = (self.width-space*(kItemCount+1))/kItemCount;
    for (int i=0; i<self.items.count; i++) {
        self.items[i].frame = CGRectMake(space+(width+space)*i, kShelfTopPad, width, self.height - kShelfTopPad - 8);
    }
}

+(CGFloat )cellHeight
{
    CGFloat itemWidth = (ScreenWidth-kShelfHSpace*(kItemCount+1))/kItemCount;
    // 封面比例 + 标题两行 + 作者 + 上下留白
    return kShelfTopPad + itemWidth*1.35 + 58 + 8;
}

@end
