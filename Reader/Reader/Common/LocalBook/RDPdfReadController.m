//
//  RDPdfReadController.m
//  Reader
//

#import "RDPdfReadController.h"
#import <PDFKit/PDFKit.h>
#import "RDBookDetailModel.h"
#import "RDLocalBookManager.h"
#import "RDReadRecordManager.h"

@interface RDPdfReadController ()
@property (nonatomic,strong) PDFView *pdfView;
@property (nonatomic,strong) PDFDocument *document;
@property (nonatomic,strong) UILabel *pageLabel;
@property (nonatomic,strong) UISlider *pageSlider;
@property (nonatomic,strong) UIView *bottomBar;
@property (nonatomic,assign) BOOL barsHidden;
@property (nonatomic,assign) CFTimeInterval lastProgressSave;
@end

@implementation RDPdfReadController

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.view.backgroundColor = RDReadBg;

    NSString *path = [RDLocalBookManager absolutePathForBook:self.bookDetail];
    self.document = path ? [[PDFDocument alloc] initWithURL:[NSURL fileURLWithPath:path]] : nil;

    [self.view addSubview:self.pdfView];
    self.topView.titleLabel.text = self.bookDetail.title;
    [self.view addSubview:self.topView];
    [self.view addSubview:self.bottomBar];

    if (!self.document) {
        [self showText:@"无法打开该 PDF 文件"];
        return;
    }
    if (self.document.isLocked) {
        //加密 PDF:尝试空密码,失败则提示
        if (![self.document unlockWithPassword:@""]) {
            [self showText:@"该 PDF 已加密,无法打开"];
            return;
        }
    }
    self.pdfView.document = self.document;

    //恢复进度
    NSInteger page = self.bookDetail.page;
    if (page > 0 && page < self.document.pageCount) {
        [self.pdfView goToPage:[self.document pageAtIndex:page]];
    }
    self.pageSlider.maximumValue = MAX(1, self.document.pageCount - 1);
    [self p_updatePageInfo];

    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(p_pageChanged)
                                                 name:PDFViewPageChangedNotification object:self.pdfView];

    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(p_toggleBars)];
    [self.pdfView addGestureRecognizer:tap];
}

- (PDFView *)pdfView
{
    if (!_pdfView) {
        _pdfView = [[PDFView alloc] initWithFrame:self.view.bounds];
        _pdfView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        _pdfView.backgroundColor = RDReadBg;
        _pdfView.autoScales = YES;
        _pdfView.displayMode = kPDFDisplaySinglePageContinuous;
        _pdfView.displayDirection = kPDFDisplayDirectionVertical;
    }
    return _pdfView;
}

- (UIView *)bottomBar
{
    if (!_bottomBar) {
        _bottomBar = [[UIView alloc] init];
        _bottomBar.backgroundColor = RDBackgroudColor;
        UIView *line = [[UIView alloc] initWithFrame:CGRectMake(0, 0, ScreenWidth, 1.0 / UIScreen.mainScreen.scale)];
        line.backgroundColor = RDSeparatorColor;
        line.autoresizingMask = UIViewAutoresizingFlexibleWidth;
        [_bottomBar addSubview:line];
        [_bottomBar addSubview:self.pageSlider];
        [_bottomBar addSubview:self.pageLabel];
    }
    return _bottomBar;
}

- (UISlider *)pageSlider
{
    if (!_pageSlider) {
        _pageSlider = [[UISlider alloc] init];
        _pageSlider.minimumValue = 0;
        _pageSlider.minimumTrackTintColor = RDAccentColor;
        _pageSlider.maximumTrackTintColor = RDSeparatorColor;
        [_pageSlider addTarget:self action:@selector(p_sliderChanged:) forControlEvents:UIControlEventValueChanged];
    }
    return _pageSlider;
}

- (UILabel *)pageLabel
{
    if (!_pageLabel) {
        _pageLabel = [[UILabel alloc] init];
        _pageLabel.font = RDFont13;
        _pageLabel.textColor = RDGrayColor;
        _pageLabel.textAlignment = NSTextAlignmentCenter;
    }
    return _pageLabel;
}

- (void)viewDidLayoutSubviews
{
    [super viewDidLayoutSubviews];
    CGFloat bottomHeight = 74 + [UIView safeBottomBar];
    self.bottomBar.frame = CGRectMake(0, self.barsHidden ? self.view.height : self.view.height - bottomHeight, self.view.width, bottomHeight);
    self.pageSlider.frame = CGRectMake(20, 12, self.view.width - 40, 30);
    self.pageLabel.frame = CGRectMake(0, 46, self.view.width, 18);
}

#pragma mark - 交互

- (void)p_toggleBars
{
    self.barsHidden = !self.barsHidden;
    CGFloat bottomHeight = self.bottomBar.height;
    [UIView animateWithDuration:0.25 animations:^{
        self.topView.top = self.barsHidden ? -self.topView.height : 0;
        self.bottomBar.top = self.barsHidden ? self.view.height : self.view.height - bottomHeight;
        self.topView.alpha = self.barsHidden ? 0 : 1;
        self.bottomBar.alpha = self.barsHidden ? 0 : 1;
    }];
}

- (void)p_sliderChanged:(UISlider *)slider
{
    NSInteger index = (NSInteger)llroundf(slider.value);
    if (index >= 0 && index < self.document.pageCount) {
        [self.pdfView goToPage:[self.document pageAtIndex:index]];
    }
}

- (void)p_pageChanged
{
    [self p_updatePageInfo];
    // 连续滚动时高频触发,节流 0.5s;最终位置由 viewWillDisappear 兜底
    CFTimeInterval now = CACurrentMediaTime();
    if (now - self.lastProgressSave < 0.5) {
        return;
    }
    self.lastProgressSave = now;
    [self p_saveRecord];
}

- (void)p_updatePageInfo
{
    NSInteger index = [self.document indexForPage:self.pdfView.currentPage];
    if (index == NSNotFound) {
        return;
    }
    self.pageLabel.text = [NSString stringWithFormat:@"%@ / %@", @(index + 1), @(self.document.pageCount)];
    if (!self.pageSlider.isTracking) {
        self.pageSlider.value = index;
    }
}

- (void)p_saveRecord
{
    NSInteger index = [self.document indexForPage:self.pdfView.currentPage];
    if (index == NSNotFound) {
        return;
    }
    self.bookDetail.page = index;
    // 只更新 page/readTime 两列,异步写,不阻塞滚动
    [RDReadRecordManager asyncUpdatePage:index forBookId:self.bookDetail.bookId];
}

- (void)viewWillDisappear:(BOOL)animated
{
    [super viewWillDisappear:animated];
    if (self.document) {
        [self p_saveRecord];
    }
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

@end
