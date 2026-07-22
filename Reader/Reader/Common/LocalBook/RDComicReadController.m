//
//  RDComicReadController.m
//  Reader
//
//  本地漫画/图集:默认(左→右) / 日漫(右→左) / 条漫(竖滑)
//

#import "RDComicReadController.h"
#import "RDBookDetailModel.h"
#import "RDCharpterModel.h"
#import "RDCharpterDataManager.h"
#import "RDLocalBookManager.h"
#import "RDReadRecordManager.h"
#import "RDReadConfigManager.h"
#import "RDAppAppearance.h"
#import "RDLayoutButton.h"
#import "RDZipArchive.h"
#import "RDComicHelper.h"
#import "RDPaperAlert.h"
#import "UINavigationController+FDFullscreenPopGesture.h"

static NSString * const kRDComicWebtoonCellId = @"RDComicWebtoonCell";
/// 与 RDReadProgressView / RDReadToolBar 图标一致
static const CGFloat kRDComicProgressArrowIcon = 24;
static const CGFloat kRDComicProgressArrowHit = 44;
/// 底栏内容区高度(不含安全区),对齐文字阅读进度面板节奏
static const CGFloat kRDComicBottomContentHeight = 108;

@interface RDComicWebtoonCell : UITableViewCell
@property (nonatomic, strong) UIImageView *pageView;
@property (nonatomic, assign) NSInteger pageIndex;
@end

@implementation RDComicWebtoonCell
- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier
{
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (self) {
        self.selectionStyle = UITableViewCellSelectionStyleNone;
        self.backgroundColor = [UIColor blackColor];
        self.contentView.backgroundColor = [UIColor blackColor];
        _pageView = [[UIImageView alloc] initWithFrame:CGRectZero];
        _pageView.contentMode = UIViewContentModeScaleAspectFit;
        _pageView.clipsToBounds = YES;
        _pageView.backgroundColor = [UIColor blackColor];
        [self.contentView addSubview:_pageView];
    }
    return self;
}
- (void)layoutSubviews
{
    [super layoutSubviews];
    self.pageView.frame = self.contentView.bounds;
}
@end

@interface RDComicReadController () <UIScrollViewDelegate, UIGestureRecognizerDelegate, UITableViewDataSource, UITableViewDelegate>
@property (nonatomic, strong) UIScrollView *zoomScroll;
@property (nonatomic, strong) UIImageView *imageView;
@property (nonatomic, strong) UITableView *webtoonTable;
@property (nonatomic, strong) UILabel *pageLabel;
@property (nonatomic, strong) UISlider *pageSlider;
@property (nonatomic, strong) UIButton *modeButton;
@property (nonatomic, strong) RDLayoutButton *prevButton;
@property (nonatomic, strong) RDLayoutButton *nextButton;
@property (nonatomic, strong) UIView *bottomHairline;
@property (nonatomic, strong) UIView *bottomBar;
@property (nonatomic, assign) BOOL barsHidden;
@property (nonatomic, strong) RDZipArchive *archive;
@property (nonatomic, copy) NSArray <NSString *>*pages;
/// 与 pages 等长:每页所属话(条漫连续滚时会跨多话)
@property (nonatomic, copy) NSArray <RDCharpterModel *>*pageOwners;
@property (nonatomic, strong) NSMutableSet <NSNumber *>*loadedChapterIds;
@property (nonatomic, assign) NSInteger currentIndex;
/// 缓存 key 用条目路径,跨话 append/prepend 不失效
@property (nonatomic, strong) NSCache <NSString *, UIImage *>*imageCache;
@property (nonatomic, assign) RDComicReadMode readMode;
@property (nonatomic, strong) NSMutableDictionary <NSNumber *, NSNumber *>*webtoonHeights;
@property (nonatomic, assign) BOOL suppressingWebtoonScrollSave;
@property (nonatomic, assign) NSUInteger pageGeneration;
@property (nonatomic, assign) NSUInteger displayMaxPixelSize;
@property (nonatomic, strong) dispatch_queue_t decodeQueue;
@property (nonatomic, assign) BOOL isPageTurning;
@property (nonatomic, assign) BOOL isSwitchingChapter;
@property (nonatomic, assign) BOOL isExtendingChapter; // 条漫静默接话中
@end

@implementation RDComicReadController

- (void)viewDidLoad
{
    [super viewDidLoad];
    // 阅读页禁用全屏左滑返回,避免与翻页/条漫手势冲突
    self.fd_interactivePopDisabled = YES;
    self.fd_prefersNavigationBarHidden = YES;

    self.view.backgroundColor = [UIColor blackColor];
    self.imageCache = [[NSCache alloc] init];
    self.imageCache.countLimit = 16;
    self.imageCache.totalCostLimit = 48 * 1024 * 1024;
    self.webtoonHeights = [NSMutableDictionary dictionary];
    self.loadedChapterIds = [NSMutableSet set];
    self.decodeQueue = dispatch_queue_create("xyz.malu2335.reader.comic.decode", DISPATCH_QUEUE_SERIAL);
    self.readMode = [RDComicHelper readModeForBookId:self.bookDetail.bookId];

    if (!self.chapter && self.bookDetail.charpterModel.content.length > 0 &&
        [RDComicHelper comicChapterInfoFromContent:self.bookDetail.charpterModel.content]) {
        self.chapter = self.bookDetail.charpterModel;
    }

    CGFloat screenEdge = MAX(UIScreen.mainScreen.bounds.size.width, UIScreen.mainScreen.bounds.size.height);
    CGFloat scale = UIScreen.mainScreen.scale;
    // 首屏用约 1×屏像素解码,翻页更轻;放大时仍够用
    self.displayMaxPixelSize = (NSUInteger)llround(screenEdge * scale);
    if (self.displayMaxPixelSize < 1080) {
        self.displayMaxPixelSize = 1080;
    }

    NSString *title = self.bookDetail.title ?: @"";
    if (self.chapter.name.length > 0) {
        title = [NSString stringWithFormat:@"%@ · %@", title, self.chapter.name];
    }
    self.topView.titleLabel.text = title;

    // 先挂轻量壳(黑底+栏),ZIP 打开/页列表放到后台,不堵 push 动画
    [self.view addSubview:self.zoomScroll];
    [self.zoomScroll addSubview:self.imageView];
    [self.view addSubview:self.topView];
    [self.view addSubview:self.bottomBar];
    self.zoomScroll.hidden = YES;
    self.bottomBar.alpha = 0.0;
    [self p_applyChromeTheme];
    [self p_refreshModeButton];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(p_applyChromeTheme)
                                                 name:RDReadThemeDidChangeNotification
                                               object:nil];
    // RDTopView 会响应外观通知重置配色,需再套回阅读 chrome
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(p_applyChromeTheme)
                                                 name:RDAppAppearanceDidChangeNotification
                                               object:nil];
    [self showLoading:@"加载中…" cancel:nil];

    NSInteger startPage = self.bookDetail.page;
    NSString *bookPath = [RDLocalBookManager absolutePathForBook:self.bookDetail];
    RDCharpterModel *chapter = self.chapter;
    NSUInteger maxPx = self.displayMaxPixelSize;
    BOOL wantWebtoon = (self.readMode == RDComicReadModeWebtoon);
    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        RDZipArchive *zip = nil;
        NSArray <NSString *>*pages = nil;
        BOOL ok = [RDComicReadController p_loadPagesAtPath:bookPath
                                                   chapter:chapter
                                                       zip:&zip
                                                     pages:&pages];
        NSInteger page = startPage;
        if (page < 0) { page = 0; }
        UIImage *firstImage = nil;
        UIImage *secondImage = nil;
        if (ok && pages.count > 0) {
            if (page >= (NSInteger)pages.count) {
                page = (NSInteger)pages.count - 1;
            }
            firstImage = [RDComicReadController p_decodeEntry:pages[page]
                                                          zip:zip
                                                    maxPixels:maxPx];
            if (page + 1 < (NSInteger)pages.count) {
                secondImage = [RDComicReadController p_decodeEntry:pages[page + 1]
                                                               zip:zip
                                                         maxPixels:maxPx];
            }
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) self = weakSelf;
            if (!self) { return; }
            [self hideLoading];
            if (!ok || pages.count == 0) {
                [self showText:@"无法打开该图集"];
                return;
            }
            self.archive = zip;
            self.pages = pages;
            [self p_bindPages:pages owner:self.chapter resetLoaded:YES];
            if (firstImage && page < (NSInteger)pages.count) {
                [self p_storeImage:firstImage forEntry:pages[page]];
                [self p_rememberHeightForIndex:page image:firstImage];
            }
            if (secondImage && page + 1 < (NSInteger)pages.count) {
                [self p_storeImage:secondImage forEntry:pages[page + 1]];
                [self p_rememberHeightForIndex:page + 1 image:secondImage];
            }
            self.currentIndex = page;
            [self p_updateSliderForCurrentChapter];
            self.bottomBar.alpha = 1.0;
            if (wantWebtoon || [self p_isWebtoon]) {
                [self.view insertSubview:self.webtoonTable belowSubview:self.topView];
                self.webtoonTable.frame = self.view.bounds;
                self.webtoonTable.hidden = NO;
                self.zoomScroll.hidden = YES;
                [self.webtoonTable reloadData];
                [self p_scrollWebtoonToIndex:self.currentIndex animated:NO];
            } else {
                self.zoomScroll.hidden = NO;
                self.webtoonTable.hidden = YES;
                if (firstImage) {
                    self.imageView.image = firstImage;
                    [self p_layoutImage];
                } else {
                    [self p_showPage:self.currentIndex save:NO];
                }
            }
            [self p_refreshModeButton];
            [self p_updatePageInfo];
            [self p_prefetchAround:self.currentIndex];
        });
    });
}

#pragma mark - Load

/// 纯后台:打开路径并收集页列表(不碰 UI 属性)
+ (BOOL)p_loadPagesAtPath:(NSString *)path
                  chapter:(RDCharpterModel *)chapter
                      zip:(RDZipArchive * __autoreleasing *)outZip
                    pages:(NSArray <NSString *> * __autoreleasing *)outPages
{
    if (path.length == 0 || ![[NSFileManager defaultManager] fileExistsAtPath:path]) {
        return NO;
    }
    BOOL isDir = NO;
    [[NSFileManager defaultManager] fileExistsAtPath:path isDirectory:&isDir];
    if (isDir) {
        NSArray *rels = [RDComicHelper sortedImageRelativePathsInDirectory:path];
        NSMutableArray *abs = [NSMutableArray arrayWithCapacity:rels.count];
        for (NSString *rel in rels) {
            [abs addObject:[path stringByAppendingPathComponent:rel]];
        }
        if (outZip) { *outZip = nil; }
        if (outPages) { *outPages = abs.copy; }
        return abs.count > 0;
    }
    RDZipArchive *zip = [[RDZipArchive alloc] initWithPath:path];
    if (!zip) {
        return NO;
    }
    NSString *prefix = nil;
    if (chapter.content.length > 0) {
        NSDictionary *info = [RDComicHelper comicChapterInfoFromContent:chapter.content];
        prefix = info[@"prefix"];
    }
    NSArray <NSString *>*entries = [RDComicHelper sortedImageEntriesInZip:zip prefix:prefix];
    if (outZip) { *outZip = zip; }
    if (outPages) { *outPages = entries; }
    return entries.count > 0;
}

+ (UIImage *)p_decodeEntry:(NSString *)entry zip:(RDZipArchive *)zip maxPixels:(NSUInteger)maxPx
{
    if (entry.length == 0) {
        return nil;
    }
    NSData *data = nil;
    if (zip) {
        data = [zip dataForEntry:entry];
    } else {
        data = [NSData dataWithContentsOfFile:entry options:NSDataReadingMappedIfSafe error:nil];
    }
    return [RDComicHelper imageFromData:data maxPixelSize:maxPx];
}

#pragma mark - Views

- (UIScrollView *)zoomScroll
{
    if (!_zoomScroll) {
        _zoomScroll = [[UIScrollView alloc] initWithFrame:self.view.bounds];
        _zoomScroll.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        _zoomScroll.backgroundColor = [UIColor blackColor];
        _zoomScroll.delegate = self;
        _zoomScroll.minimumZoomScale = 1.0;
        _zoomScroll.maximumZoomScale = 4.0;
        _zoomScroll.showsVerticalScrollIndicator = NO;
        _zoomScroll.showsHorizontalScrollIndicator = NO;
        _zoomScroll.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentNever;
        _zoomScroll.delaysContentTouches = NO;

        UITapGestureRecognizer *pageTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(p_handlePageTap:)];
        pageTap.numberOfTapsRequired = 1;
        [_zoomScroll addGestureRecognizer:pageTap];

        UITapGestureRecognizer *pageDoubleTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(p_handleDoubleTap:)];
        pageDoubleTap.numberOfTapsRequired = 2;
        [_zoomScroll addGestureRecognizer:pageDoubleTap];
        [pageTap requireGestureRecognizerToFail:pageDoubleTap];

        UISwipeGestureRecognizer *swipeLeft = [[UISwipeGestureRecognizer alloc] initWithTarget:self action:@selector(p_swipeLeft)];
        swipeLeft.direction = UISwipeGestureRecognizerDirectionLeft;
        swipeLeft.delegate = self;
        [_zoomScroll addGestureRecognizer:swipeLeft];

        UISwipeGestureRecognizer *swipeRight = [[UISwipeGestureRecognizer alloc] initWithTarget:self action:@selector(p_swipeRight)];
        swipeRight.direction = UISwipeGestureRecognizerDirectionRight;
        swipeRight.delegate = self;
        [_zoomScroll addGestureRecognizer:swipeRight];
    }
    return _zoomScroll;
}

- (UIImageView *)imageView
{
    if (!_imageView) {
        _imageView = [[UIImageView alloc] init];
        _imageView.contentMode = UIViewContentModeScaleAspectFit;
        _imageView.userInteractionEnabled = YES;
    }
    return _imageView;
}

- (UITableView *)webtoonTable
{
    if (!_webtoonTable) {
        _webtoonTable = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStylePlain];
        _webtoonTable.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        _webtoonTable.backgroundColor = [UIColor blackColor];
        _webtoonTable.separatorStyle = UITableViewCellSeparatorStyleNone;
        _webtoonTable.dataSource = self;
        _webtoonTable.delegate = self;
        _webtoonTable.showsVerticalScrollIndicator = YES;
        _webtoonTable.showsHorizontalScrollIndicator = NO;
        _webtoonTable.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentNever;
        _webtoonTable.alwaysBounceVertical = YES;
        _webtoonTable.estimatedRowHeight = 0;
        _webtoonTable.estimatedSectionHeaderHeight = 0;
        _webtoonTable.estimatedSectionFooterHeight = 0;
        _webtoonTable.hidden = YES;
        if (@available(iOS 15.0, *)) {
            _webtoonTable.sectionHeaderTopPadding = 0;
        }
        [_webtoonTable registerClass:RDComicWebtoonCell.class forCellReuseIdentifier:kRDComicWebtoonCellId];

        UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(p_handleWebtoonTap:)];
        tap.cancelsTouchesInView = NO;
        [_webtoonTable addGestureRecognizer:tap];
    }
    return _webtoonTable;
}

- (UIView *)bottomBar
{
    if (!_bottomBar) {
        _bottomBar = [[UIView alloc] init];
        // 纸感 chrome 底栏(与文字阅读进度面板一致),非半透明黑条
        [_bottomBar addSubview:self.bottomHairline];
        [_bottomBar addSubview:self.pageLabel];
        [_bottomBar addSubview:self.modeButton];
        [_bottomBar addSubview:self.prevButton];
        [_bottomBar addSubview:self.nextButton];
        [_bottomBar addSubview:self.pageSlider];
    }
    return _bottomBar;
}

- (UIView *)bottomHairline
{
    if (!_bottomHairline) {
        _bottomHairline = [[UIView alloc] init];
    }
    return _bottomHairline;
}

- (UISlider *)pageSlider
{
    if (!_pageSlider) {
        _pageSlider = [[UISlider alloc] init];
        _pageSlider.minimumValue = 0;
        _pageSlider.minimumTrackTintColor = RDAccentColor;
        _pageSlider.maximumTrackTintColor = RDSeparatorColor;
        [_pageSlider setThumbImage:[UIImage imageNamed:@"white_slider"] forState:UIControlStateNormal];
        [_pageSlider addTarget:self action:@selector(p_sliderChanged:) forControlEvents:UIControlEventValueChanged];
        [_pageSlider addTarget:self action:@selector(p_sliderEnded:) forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside];
    }
    return _pageSlider;
}

- (UILabel *)pageLabel
{
    if (!_pageLabel) {
        _pageLabel = [[UILabel alloc] init];
        _pageLabel.font = RDFont14;
        _pageLabel.textColor = RDGrayColor;
        _pageLabel.textAlignment = NSTextAlignmentCenter;
        _pageLabel.lineBreakMode = NSLineBreakByTruncatingMiddle;
    }
    return _pageLabel;
}

- (UIButton *)modeButton
{
    if (!_modeButton) {
        _modeButton = [UIButton buttonWithType:UIButtonTypeSystem];
        _modeButton.titleLabel.font = RDFont13;
        _modeButton.layer.cornerRadius = 14;
        _modeButton.layer.borderWidth = 1.0 / [UIScreen mainScreen].scale;
        _modeButton.contentEdgeInsets = UIEdgeInsetsMake(5, 14, 5, 14);
        [_modeButton addTarget:self action:@selector(p_pickMode) forControlEvents:UIControlEventTouchUpInside];
    }
    return _modeButton;
}

- (RDLayoutButton *)p_arrowButtonWithImage:(NSString *)imageName action:(SEL)action
{
    RDLayoutButton *button = [[RDLayoutButton alloc] init];
    [button setImage:[UIImage imageNamed:imageName] forState:UIControlStateNormal];
    button.imageSize = CGSizeMake(kRDComicProgressArrowIcon, kRDComicProgressArrowIcon);
    [button addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    return button;
}

- (RDLayoutButton *)prevButton
{
    if (!_prevButton) {
        _prevButton = [self p_arrowButtonWithImage:@"read_progress_left" action:@selector(p_goPrevChapter)];
        _prevButton.accessibilityLabel = @"上一话";
    }
    return _prevButton;
}

- (RDLayoutButton *)nextButton
{
    if (!_nextButton) {
        _nextButton = [self p_arrowButtonWithImage:@"read_progress_right" action:@selector(p_goNextChapter)];
        _nextButton.accessibilityLabel = @"下一话";
    }
    return _nextButton;
}

/// 顶/底 chrome 对齐文字阅读菜单:纸感背景、前景色、强调色滑轨
- (void)p_applyChromeTheme
{
    RDReadConfigManager *cfg = [RDReadConfigManager sharedInstance];
    UIColor *bg = [cfg chromeBackgroundColor];
    UIColor *fg = [cfg chromeForegroundColor];
    UIColor *sec = [cfg chromeSecondaryColor];
    UIColor *sep = [cfg chromeSeparatorColor];

    self.topView.backgroundColor = bg;
    self.topView.titleLabel.textColor = fg;
    if ([self.topView.backBtn respondsToSelector:@selector(setTintColor:)]) {
        self.topView.backBtn.tintColor = fg;
        UIImage *back = [[UIImage imageNamed:@"button_back"] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
        [self.topView.backBtn setImage:back forState:UIControlStateNormal];
    }
    if (self.topView.separate) {
        self.topView.separate.backgroundColor = sep;
    }

    self.bottomBar.backgroundColor = bg;
    self.bottomHairline.backgroundColor = sep;
    self.pageLabel.textColor = sec;
    self.pageSlider.minimumTrackTintColor = RDAccentColor;
    self.pageSlider.maximumTrackTintColor = sep;

    UIImage *leftImg = [[[UIImage imageNamed:@"read_progress_left"] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate]
                        imageWithTintColor:fg renderingMode:UIImageRenderingModeAlwaysOriginal];
    UIImage *rightImg = [[[UIImage imageNamed:@"read_progress_right"] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate]
                         imageWithTintColor:fg renderingMode:UIImageRenderingModeAlwaysOriginal];
    [self.prevButton setImage:leftImg forState:UIControlStateNormal];
    [self.nextButton setImage:rightImg forState:UIControlStateNormal];

    [self.modeButton setTitleColor:fg forState:UIControlStateNormal];
    // 浅描边胶囊,纸面不抢戏
    if (cfg.isDarkTheme) {
        self.modeButton.backgroundColor = [UIColor colorWithWhite:1 alpha:0.06];
    } else {
        self.modeButton.backgroundColor = [UIColor colorWithWhite:0 alpha:0.04];
    }
    self.modeButton.layer.borderColor = sep.CGColor;
    [self p_updateArrowStates];
}

- (void)p_updateArrowStates
{
    // 左右箭头 = 上一话 / 下一话(非翻页);无多话结构时灰显
    BOOL canPrev = (self.chapter != nil && [self p_adjacentChapter:NO] != nil);
    BOOL canNext = (self.chapter != nil && [self p_adjacentChapter:YES] != nil);
    self.prevButton.enabled = canPrev;
    self.nextButton.enabled = canNext;
    self.prevButton.alpha = canPrev ? 1.0 : 0.35;
    self.nextButton.alpha = canNext ? 1.0 : 0.35;
    // 滑块仍管当前话内页码
    NSInteger chapterPages = [self p_pageCountInCurrentChapter];
    self.pageSlider.enabled = chapterPages > 1;
}

- (void)viewDidLayoutSubviews
{
    [super viewDidLayoutSubviews];
    CGFloat safeBottom = [UIView safeBottomBar];
    CGFloat bottomHeight = kRDComicBottomContentHeight + safeBottom;
    self.bottomBar.frame = CGRectMake(0, self.barsHidden ? self.view.height : self.view.height - bottomHeight, self.view.width, bottomHeight);

    CGFloat w = self.view.width;
    // 顶部分割线
    CGFloat hair = 1.0 / [UIScreen mainScreen].scale;
#ifdef MinPixel
    hair = MAX(MinPixel, hair);
#endif
    self.bottomHairline.frame = CGRectMake(0, 0, w, hair);

    // 与 RDReadProgressView 一致:上方章节/页码,下方箭头+滑块
    CGFloat labelTop = 14;
    CGFloat labelH = RDFont14.lineHeight;
    self.pageLabel.frame = CGRectMake(20, labelTop, w - 40, labelH);

    const CGFloat iconSize = kRDComicProgressArrowIcon;
    const CGFloat hitSize = kRDComicProgressArrowHit;
    CGFloat sliderCenterY = labelTop + labelH + 12 + iconSize / 2.0;
    CGFloat leftCenterX = 20 + iconSize / 2.0;
    CGFloat rightCenterX = w - 20 - iconSize / 2.0;
    self.prevButton.frame = CGRectMake(leftCenterX - hitSize / 2.0, sliderCenterY - hitSize / 2.0, hitSize, hitSize);
    self.nextButton.frame = CGRectMake(rightCenterX - hitSize / 2.0, sliderCenterY - hitSize / 2.0, hitSize, hitSize);

    CGFloat sliderLeft = 20 + iconSize + 15;
    CGFloat sliderRight = w - 20 - iconSize - 15;
    self.pageSlider.frame = CGRectMake(sliderLeft, 0, MAX(40, sliderRight - sliderLeft), 28);
    self.pageSlider.center = CGPointMake(CGRectGetMidX(self.pageSlider.frame), sliderCenterY);
    // re-set frame with correct center
    CGRect sf = self.pageSlider.frame;
    sf.origin.y = sliderCenterY - sf.size.height / 2.0;
    self.pageSlider.frame = sf;

    // 方式按钮:滑块下方居中胶囊
    [self.modeButton sizeToFit];
    CGFloat modeW = MIN(w - 40, MAX(96, CGRectGetWidth(self.modeButton.bounds)));
    CGFloat modeH = 28;
    CGFloat modeTop = sliderCenterY + hitSize / 2.0 + 6;
    self.modeButton.frame = CGRectMake((w - modeW) / 2.0, modeTop, modeW, modeH);

    self.zoomScroll.frame = self.view.bounds;
    self.webtoonTable.frame = self.view.bounds;
    if (self.readMode != RDComicReadModeWebtoon) {
        [self p_layoutImage];
    }
}

#pragma mark - Mode

- (BOOL)p_isRTL
{
    return self.readMode == RDComicReadModePageRTL;
}

- (BOOL)p_isWebtoon
{
    return self.readMode == RDComicReadModeWebtoon;
}

- (void)p_refreshModeButton
{
    NSString *title = [NSString stringWithFormat:@"方式 · %@", [RDComicHelper displayNameForReadMode:self.readMode]];
    [self.modeButton setTitle:title forState:UIControlStateNormal];
    [self.view setNeedsLayout];
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)p_applyReadModeLayoutAnimated:(BOOL)animated jumpToCurrent:(BOOL)jump
{
    [self p_refreshModeButton];
    BOOL webtoon = [self p_isWebtoon];
    void (^apply)(void) = ^{
        self.zoomScroll.hidden = webtoon;
        self.webtoonTable.hidden = !webtoon;
        if (webtoon) {
            [self.webtoonTable reloadData];
            if (jump) {
                [self p_scrollWebtoonToIndex:self.currentIndex animated:NO];
            }
        } else if (jump) {
            [self p_showPage:self.currentIndex save:YES];
        }
        [self p_updatePageInfo];
    };
    if (animated) {
        [UIView transitionWithView:self.view duration:0.18 options:UIViewAnimationOptionTransitionCrossDissolve animations:apply completion:nil];
    } else {
        apply();
    }
}

- (void)p_pickMode
{
    __weak typeof(self) weakSelf = self;
    NSMutableArray *actions = [NSMutableArray array];
    for (NSNumber *n in @[@(RDComicReadModePageLTR), @(RDComicReadModePageRTL), @(RDComicReadModeWebtoon)]) {
        RDComicReadMode m = n.integerValue;
        NSString *name = [RDComicHelper displayNameForReadMode:m];
        NSString *label = (m == self.readMode) ? [NSString stringWithFormat:@"✓ %@", name] : name;
        [actions addObject:[RDPaperAlertAction actionWithTitle:label
                                                     subtitle:[RDComicHelper detailForReadMode:m]
                                                        style:RDPaperAlertActionStyleDefault
                                                      handler:^{
            [weakSelf p_setReadMode:m];
        }]];
    }
    [actions addObject:[RDPaperAlertAction actionWithTitle:@"取消"
                                                    style:RDPaperAlertActionStyleCancel
                                                  handler:nil]];
    [RDPaperAlert showActionSheetWithTitle:@"漫画阅读方式"
                                   message:@"切换后记住本书;新书默认跟随设置"
                                   actions:actions];
}

- (void)p_setReadMode:(RDComicReadMode)mode
{
    if (mode == self.readMode) {
        return;
    }
    if ([self p_isWebtoon]) {
        [self p_syncIndexFromWebtoon];
    }
    self.readMode = mode;
    [RDComicHelper setReadMode:mode forBookId:self.bookDetail.bookId];
    [self p_applyReadModeLayoutAnimated:YES jumpToCurrent:YES];
}

#pragma mark - Decode (background)

- (NSData *)p_dataAtIndex:(NSInteger)index
{
    if (index < 0 || index >= (NSInteger)self.pages.count) {
        return nil;
    }
    if (self.archive) {
        return [self.archive dataForEntry:self.pages[index]];
    }
    return [NSData dataWithContentsOfFile:self.pages[index] options:NSDataReadingMappedIfSafe error:nil];
}

- (nullable NSString *)p_entryAtIndex:(NSInteger)index
{
    if (index < 0 || index >= (NSInteger)self.pages.count) {
        return nil;
    }
    return self.pages[index];
}

- (void)p_storeImage:(UIImage *)image forEntry:(NSString *)entry
{
    if (!image || entry.length == 0) {
        return;
    }
    NSUInteger cost = (NSUInteger)(image.size.width * image.size.height * image.scale * image.scale * 4);
    [self.imageCache setObject:image forKey:entry cost:cost];
}

- (UIImage *)p_cachedImageAtIndex:(NSInteger)index
{
    NSString *entry = [self p_entryAtIndex:index];
    if (entry.length == 0) {
        return nil;
    }
    return [self.imageCache objectForKey:entry];
}

/// 绑定页列表归属;resetLoaded=YES 时清空已加载话集合
- (void)p_bindPages:(NSArray <NSString *>*)pages owner:(RDCharpterModel *)owner resetLoaded:(BOOL)reset
{
    self.pages = pages ?: @[];
    if (owner) {
        NSMutableArray *owners = [NSMutableArray arrayWithCapacity:self.pages.count];
        for (NSUInteger i = 0; i < self.pages.count; i++) {
            [owners addObject:owner];
        }
        self.pageOwners = owners.copy;
        if (reset || !self.loadedChapterIds) {
            self.loadedChapterIds = [NSMutableSet set];
        }
        [self.loadedChapterIds addObject:@(owner.charpterId)];
    } else {
        self.pageOwners = @[];
        if (reset) {
            self.loadedChapterIds = [NSMutableSet set];
        }
    }
}

- (void)p_rememberHeightForIndex:(NSInteger)index image:(UIImage *)image
{
    if (!image || index < 0) {
        return;
    }
    CGFloat w = MAX(1, self.view.bounds.size.width > 1 ? self.view.bounds.size.width : UIScreen.mainScreen.bounds.size.width);
    CGFloat h = image.size.width > 1 ? (w * image.size.height / image.size.width) : (w * 1.4);
    self.webtoonHeights[@(index)] = @(MAX(120, h));
}

/// 后台解码并写入 cache;completion 在主线程
- (void)p_decodeIndex:(NSInteger)index completion:(void (^)(UIImage * _Nullable image))completion
{
    if (index < 0 || index >= (NSInteger)self.pages.count) {
        if (completion) {
            dispatch_async(dispatch_get_main_queue(), ^{ completion(nil); });
        }
        return;
    }
    UIImage *cached = [self p_cachedImageAtIndex:index];
    if (cached) {
        if (completion) {
            dispatch_async(dispatch_get_main_queue(), ^{ completion(cached); });
        }
        return;
    }
    NSUInteger maxPx = self.displayMaxPixelSize;
    __weak typeof(self) weakSelf = self;
    dispatch_async(self.decodeQueue, ^{
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) { return; }
        UIImage *again = [self p_cachedImageAtIndex:index];
        if (again) {
            if (completion) {
                dispatch_async(dispatch_get_main_queue(), ^{ completion(again); });
            }
            return;
        }
        NSString *entry = [self p_entryAtIndex:index];
        NSData *data = [self p_dataAtIndex:index];
        UIImage *image = [RDComicHelper imageFromData:data maxPixelSize:maxPx];
        if (image && entry.length > 0) {
            [self p_storeImage:image forEntry:entry];
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) self2 = weakSelf;
            if (!self2) { return; }
            if (image) {
                [self2 p_rememberHeightForIndex:index image:image];
            }
            if (completion) {
                completion(image);
            }
        });
    });
}

- (void)p_prefetchAround:(NSInteger)index
{
    for (NSInteger d = 1; d <= 2; d++) {
        [self p_decodeIndex:index + d completion:nil];
        [self p_decodeIndex:index - d completion:nil];
    }
}

#pragma mark - Page mode show

- (void)p_showPage:(NSInteger)index save:(BOOL)save
{
    if (self.pages.count == 0) {
        return;
    }
    index = MAX(0, MIN(index, (NSInteger)self.pages.count - 1));
    self.currentIndex = index;
    self.pageGeneration += 1;
    NSUInteger gen = self.pageGeneration;
    self.zoomScroll.zoomScale = 1.0;
    self.zoomScroll.transform = CGAffineTransformIdentity;

    UIImage *cached = [self p_cachedImageAtIndex:index];
    if (cached) {
        self.imageView.image = cached;
        [self p_layoutImage];
    } else {
        // 先清空避免闪旧图;后台解码后上屏
        self.imageView.image = nil;
        __weak typeof(self) weakSelf = self;
        [self p_decodeIndex:index completion:^(UIImage *image) {
            __strong typeof(weakSelf) self = weakSelf;
            if (!self || self.pageGeneration != gen || self.currentIndex != index) {
                return;
            }
            self.imageView.image = image;
            [self p_layoutImage];
        }];
    }
    [self p_updatePageInfo];
    if (save) {
        [self p_saveRecord];
    }
    [self p_prefetchAround:index];
}

/// 横向翻页滑动动画。forward=YES 表示下一页。
/// 默认:下一页从右侧滑入;日漫:下一页从左侧滑入(阅读方向相反)。
- (void)p_animateTurnToPage:(NSInteger)index forward:(BOOL)forward
{
    if (self.pages.count == 0 || self.isPageTurning || [self p_isWebtoon]) {
        return;
    }
    index = MAX(0, MIN(index, (NSInteger)self.pages.count - 1));
    if (index == self.currentIndex) {
        return;
    }

    // 视觉方向:前进时 LTR 从右进、RTL 从左进;后退相反
    BOOL enterFromRight = forward ? ![self p_isRTL] : [self p_isRTL];
    CGFloat width = self.zoomScroll.bounds.size.width;
    if (width < 1) {
        width = self.view.bounds.size.width;
    }

    // 旧页快照
    UIView *outgoing = [self.zoomScroll snapshotViewAfterScreenUpdates:NO];
    if (!outgoing) {
        [self p_showPage:index save:YES];
        return;
    }
    outgoing.frame = self.zoomScroll.frame;
    // 盖在当前内容上、顶栏底栏下
    [self.view insertSubview:outgoing aboveSubview:self.zoomScroll];

    // 新页先落到 zoomScroll,再从屏外滑入
    [self p_showPage:index save:YES];
    self.zoomScroll.transform = CGAffineTransformMakeTranslation(enterFromRight ? width : -width, 0);

    self.isPageTurning = YES;
    self.zoomScroll.userInteractionEnabled = NO;
    // 略长 + easeOut,减少「硬切」感
    [UIView animateWithDuration:0.36
                          delay:0
         usingSpringWithDamping:0.92
          initialSpringVelocity:0.15
                        options:UIViewAnimationOptionCurveEaseOut | UIViewAnimationOptionAllowUserInteraction
                     animations:^{
        outgoing.transform = CGAffineTransformMakeTranslation(enterFromRight ? -width : width, 0);
        self.zoomScroll.transform = CGAffineTransformIdentity;
    } completion:^(BOOL finished) {
        [outgoing removeFromSuperview];
        self.zoomScroll.transform = CGAffineTransformIdentity;
        self.isPageTurning = NO;
        self.zoomScroll.userInteractionEnabled = YES;
        // 页模式接近章末时预热下一话
        [self p_prefetchAdjacentChapterIfNeeded];
    }];
}

/// 翻到邻页:优先等解码再播动画,避免滑入空白。越界时自动切上下话。
- (void)p_turnForward:(BOOL)forward
{
    if (self.isPageTurning || self.isSwitchingChapter || [self p_isWebtoon] || self.pages.count == 0) {
        return;
    }
    NSInteger target = forward ? (self.currentIndex + 1) : (self.currentIndex - 1);
    if (target < 0 || target >= (NSInteger)self.pages.count) {
        [self p_goAdjacentChapter:forward];
        return;
    }
    if ([self p_cachedImageAtIndex:target]) {
        [self p_animateTurnToPage:target forward:forward];
        return;
    }
    // 未缓存:先锁手势,解码完再动画
    self.isPageTurning = YES;
    __weak typeof(self) weakSelf = self;
    [self p_decodeIndex:target completion:^(UIImage *image) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) { return; }
        self.isPageTurning = NO;
        if (!image) {
            [self p_showPage:target save:YES];
            return;
        }
        [self p_animateTurnToPage:target forward:forward];
    }];
}

#pragma mark - Cross-chapter (seamless)

/// 多话列表中相对某话的上一/下一话
- (nullable RDCharpterModel *)p_chapterAdjacent:(BOOL)forward toChapter:(RDCharpterModel *)chapter
{
    if (!chapter || self.bookDetail.bookId == 0) {
        return nil;
    }
    NSArray <RDCharpterModel *>*rows = [RDCharpterDataManager getComicChapterRowsWithBookId:self.bookDetail.bookId];
    if (rows.count < 2) {
        return nil;
    }
    NSInteger idx = NSNotFound;
    for (NSInteger i = 0; i < (NSInteger)rows.count; i++) {
        if (rows[i].charpterId == chapter.charpterId) {
            idx = i;
            break;
        }
    }
    if (idx == NSNotFound) {
        return nil;
    }
    NSInteger next = forward ? (idx + 1) : (idx - 1);
    if (next < 0 || next >= (NSInteger)rows.count) {
        return nil;
    }
    return rows[next];
}

- (nullable RDCharpterModel *)p_adjacentChapter:(BOOL)forward
{
    return [self p_chapterAdjacent:forward toChapter:self.chapter];
}

/// 当前话在连续 pages 中的区间
- (NSRange)p_rangeOfChapter:(RDCharpterModel *)chapter
{
    if (!chapter || self.pageOwners.count == 0) {
        return NSMakeRange(0, self.pages.count);
    }
    NSInteger start = NSNotFound;
    NSInteger end = NSNotFound;
    for (NSInteger i = 0; i < (NSInteger)self.pageOwners.count; i++) {
        if (self.pageOwners[i].charpterId == chapter.charpterId) {
            if (start == NSNotFound) {
                start = i;
            }
            end = i;
        } else if (start != NSNotFound) {
            break;
        }
    }
    if (start == NSNotFound) {
        return NSMakeRange(0, self.pages.count);
    }
    return NSMakeRange((NSUInteger)start, (NSUInteger)(end - start + 1));
}

- (void)p_updateSliderForCurrentChapter
{
    NSRange r = [self p_rangeOfChapter:self.chapter];
    NSInteger count = (NSInteger)r.length;
    self.pageSlider.maximumValue = MAX(0, count - 1);
    NSInteger local = self.currentIndex - (NSInteger)r.location;
    local = MAX(0, MIN(local, MAX(0, count - 1)));
    if (!self.pageSlider.isTracking) {
        self.pageSlider.value = local;
    }
}

- (NSInteger)p_localPageInCurrentChapter
{
    NSRange r = [self p_rangeOfChapter:self.chapter];
    return MAX(0, self.currentIndex - (NSInteger)r.location);
}

- (NSInteger)p_pageCountInCurrentChapter
{
    return (NSInteger)[self p_rangeOfChapter:self.chapter].length;
}

/// 根据 currentIndex 同步所属话(条漫跨话连续滚时)
- (void)p_syncChapterFromCurrentIndex
{
    if (self.currentIndex < 0 || self.currentIndex >= (NSInteger)self.pageOwners.count) {
        return;
    }
    RDCharpterModel *owner = self.pageOwners[self.currentIndex];
    if (!owner) {
        return;
    }
    if (self.chapter && self.chapter.charpterId == owner.charpterId) {
        [self p_updateSliderForCurrentChapter];
        return;
    }
    self.chapter = owner;
    self.bookDetail.charpterModel = owner;
    self.bookDetail.readChapterName = owner.name;
    NSString *title = self.bookDetail.title ?: @"";
    if (owner.name.length > 0) {
        title = [NSString stringWithFormat:@"%@ · %@", title, owner.name];
    }
    self.topView.titleLabel.text = title;
    [self p_updateSliderForCurrentChapter];
    [self p_saveProgressWithChapter];
}

- (void)p_goAdjacentChapter:(BOOL)forward
{
    if (self.isSwitchingChapter || self.isPageTurning || self.isExtendingChapter) {
        return;
    }
    if (!self.chapter) {
        [self showText:forward ? @"已经是最后一页" : @"已经是第一页"];
        return;
    }
    RDCharpterModel *next = [self p_adjacentChapter:forward];
    if (!next) {
        [self showText:forward ? @"已经是最后一话" : @"已经是第一话"];
        return;
    }

    // 条漫:静默接页,不重开
    if ([self p_isWebtoon]) {
        [self p_webtoonExtendChapter:next forward:forward thenScroll:YES];
        return;
    }
    // 翻页模式:保留当前画面,就绪后滑动切入(无 Loading)
    NSInteger startPage = 0;
    if (!forward) {
        NSDictionary *info = [RDComicHelper comicChapterInfoFromContent:next.content];
        NSInteger pc = [info[@"pageCount"] integerValue];
        startPage = MAX(0, pc - 1);
    }
    [self p_softSwitchToChapter:next startPage:startPage forward:forward];
}

/// 翻页模式软切话:不关黑屏、不 Loading,就绪后用翻页动画接入
- (void)p_softSwitchToChapter:(RDCharpterModel *)chapter
                    startPage:(NSInteger)startPage
                      forward:(BOOL)forward
{
    if (!chapter || self.isSwitchingChapter) {
        return;
    }
    self.isSwitchingChapter = YES;
    NSString *bookPath = [RDLocalBookManager absolutePathForBook:self.bookDetail];
    NSUInteger maxPx = self.displayMaxPixelSize;
    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        RDZipArchive *zip = nil;
        NSArray <NSString *>*pages = nil;
        BOOL ok = [RDComicReadController p_loadPagesAtPath:bookPath
                                                   chapter:chapter
                                                       zip:&zip
                                                     pages:&pages];
        NSInteger page = MAX(0, startPage);
        UIImage *firstImage = nil;
        if (ok && pages.count > 0) {
            if (page >= (NSInteger)pages.count) {
                page = (NSInteger)pages.count - 1;
            }
            firstImage = [RDComicReadController p_decodeEntry:pages[page] zip:zip maxPixels:maxPx];
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) self = weakSelf;
            if (!self) { return; }
            self.isSwitchingChapter = NO;
            if (!ok || pages.count == 0) {
                [self showText:@"无法打开该话"];
                return;
            }
            // 快照当前页,再换数据源,滑入新页 —— 视觉上像连续翻页
            UIView *outgoing = [self.zoomScroll snapshotViewAfterScreenUpdates:NO];
            if (outgoing) {
                outgoing.frame = self.zoomScroll.frame;
                [self.view insertSubview:outgoing aboveSubview:self.zoomScroll];
            }

            if (zip) {
                self.archive = zip;
            }
            [self p_bindPages:pages owner:chapter resetLoaded:YES];
            self.chapter = chapter;
            self.bookDetail.charpterModel = chapter;
            self.bookDetail.readChapterName = chapter.name;
            self.bookDetail.page = page;
            self.webtoonHeights = [NSMutableDictionary dictionary];
            self.currentIndex = page;
            self.pageGeneration += 1;
            if (firstImage) {
                [self p_storeImage:firstImage forEntry:pages[page]];
                self.imageView.image = firstImage;
                [self p_layoutImage];
            } else {
                [self p_showPage:page save:NO];
            }

            NSString *title = self.bookDetail.title ?: @"";
            if (chapter.name.length > 0) {
                title = [NSString stringWithFormat:@"%@ · %@", title, chapter.name];
            }
            self.topView.titleLabel.text = title;
            [self p_updatePageInfo];
            [self p_prefetchAround:page];
            [self p_saveProgressWithChapter];

            if (outgoing) {
                BOOL enterFromRight = forward ? ![self p_isRTL] : [self p_isRTL];
                CGFloat width = self.zoomScroll.bounds.size.width;
                if (width < 1) {
                    width = self.view.bounds.size.width;
                }
                self.zoomScroll.transform = CGAffineTransformMakeTranslation(enterFromRight ? width : -width, 0);
                self.isPageTurning = YES;
                self.zoomScroll.userInteractionEnabled = NO;
                [UIView animateWithDuration:0.38
                                      delay:0
                     usingSpringWithDamping:0.9
                      initialSpringVelocity:0.12
                                    options:UIViewAnimationOptionCurveEaseOut
                                 animations:^{
                    outgoing.transform = CGAffineTransformMakeTranslation(enterFromRight ? -width : width, 0);
                    self.zoomScroll.transform = CGAffineTransformIdentity;
                } completion:^(BOOL finished) {
                    [outgoing removeFromSuperview];
                    self.zoomScroll.transform = CGAffineTransformIdentity;
                    self.isPageTurning = NO;
                    self.zoomScroll.userInteractionEnabled = YES;
                }];
            }
        });
    });
}

/// 条漫:把相邻话页追加/前插到同一 table,不 reload 整表、不 Loading
- (void)p_webtoonExtendChapter:(RDCharpterModel *)chapter
                       forward:(BOOL)forward
                    thenScroll:(BOOL)thenScroll
{
    if (!chapter || ![self p_isWebtoon]) {
        return;
    }
    if ([self.loadedChapterIds containsObject:@(chapter.charpterId)]) {
        // 已接上:直接滚到该话边界
        if (thenScroll) {
            NSRange r = [self p_rangeOfChapter:chapter];
            if (r.length > 0) {
                NSInteger target = forward ? (NSInteger)r.location : (NSInteger)(r.location + r.length - 1);
                self.currentIndex = target;
                [self p_syncChapterFromCurrentIndex];
                [self p_scrollWebtoonToIndex:target animated:YES];
                [self p_updatePageInfo];
            }
        }
        return;
    }
    if (self.isExtendingChapter) {
        return;
    }
    self.isExtendingChapter = YES;
    NSString *bookPath = [RDLocalBookManager absolutePathForBook:self.bookDetail];
    NSUInteger maxPx = self.displayMaxPixelSize;
    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        RDZipArchive *zip = nil;
        NSArray <NSString *>*newPages = nil;
        BOOL ok = [RDComicReadController p_loadPagesAtPath:bookPath
                                                   chapter:chapter
                                                       zip:&zip
                                                     pages:&newPages];
        // 预解前 2 张,接上时少空白
        UIImage *img0 = nil;
        UIImage *img1 = nil;
        if (ok && newPages.count > 0) {
            img0 = [RDComicReadController p_decodeEntry:newPages[0] zip:zip maxPixels:maxPx];
            if (newPages.count > 1) {
                img1 = [RDComicReadController p_decodeEntry:newPages[1] zip:zip maxPixels:maxPx];
            }
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) self = weakSelf;
            if (!self) { return; }
            self.isExtendingChapter = NO;
            if (!ok || newPages.count == 0) {
                if (thenScroll) {
                    [self showText:@"无法打开该话"];
                }
                return;
            }
            if (zip) {
                self.archive = zip;
            }
            if (img0) {
                [self p_storeImage:img0 forEntry:newPages[0]];
            }
            if (img1 && newPages.count > 1) {
                [self p_storeImage:img1 forEntry:newPages[1]];
            }

            NSInteger oldCount = (NSInteger)self.pages.count;
            NSMutableArray <NSString *>*pages = (self.pages ?: @[]).mutableCopy;
            NSMutableArray <RDCharpterModel *>*owners = (self.pageOwners ?: @[]).mutableCopy;

            if (forward) {
                // 追加到末尾
                NSMutableArray <NSIndexPath *>*paths = [NSMutableArray arrayWithCapacity:newPages.count];
                for (NSUInteger i = 0; i < newPages.count; i++) {
                    [pages addObject:newPages[i]];
                    [owners addObject:chapter];
                    NSInteger row = oldCount + (NSInteger)i;
                    [paths addObject:[NSIndexPath indexPathForRow:row inSection:0]];
                    if (i == 0 && img0) {
                        [self p_rememberHeightForIndex:row image:img0];
                    } else if (i == 1 && img1) {
                        [self p_rememberHeightForIndex:row image:img1];
                    }
                }
                self.pages = pages.copy;
                self.pageOwners = owners.copy;
                [self.loadedChapterIds addObject:@(chapter.charpterId)];

                if (self.webtoonTable.window && !self.webtoonTable.hidden) {
                    [self.webtoonTable performBatchUpdates:^{
                        [self.webtoonTable insertRowsAtIndexPaths:paths withRowAnimation:UITableViewRowAnimationNone];
                    } completion:^(BOOL finished) {
                        if (thenScroll) {
                            [self p_scrollWebtoonToIndex:oldCount animated:YES];
                            self.currentIndex = oldCount;
                            [self p_syncChapterFromCurrentIndex];
                            [self p_updatePageInfo];
                            [self p_saveProgressWithChapter];
                        }
                    }];
                } else {
                    [self.webtoonTable reloadData];
                    if (thenScroll) {
                        self.currentIndex = oldCount;
                        [self p_scrollWebtoonToIndex:oldCount animated:NO];
                        [self p_syncChapterFromCurrentIndex];
                        [self p_updatePageInfo];
                    }
                }
            } else {
                // 前插:平移高度字典与 contentOffset
                NSInteger shift = (NSInteger)newPages.count;
                NSMutableDictionary *newHeights = [NSMutableDictionary dictionary];
                [self.webtoonHeights enumerateKeysAndObjectsUsingBlock:^(NSNumber *key, NSNumber *val, BOOL *stop) {
                    newHeights[@(key.integerValue + shift)] = val;
                }];
                self.webtoonHeights = newHeights;
                for (NSInteger i = (NSInteger)newPages.count - 1; i >= 0; i--) {
                    [pages insertObject:newPages[i] atIndex:0];
                    [owners insertObject:chapter atIndex:0];
                }
                if (img0) {
                    [self p_rememberHeightForIndex:0 image:img0];
                }
                if (img1 && shift > 1) {
                    [self p_rememberHeightForIndex:1 image:img1];
                }
                self.pages = pages.copy;
                self.pageOwners = owners.copy;
                [self.loadedChapterIds addObject:@(chapter.charpterId)];

                CGFloat prependH = 0;
                CGFloat w = self.webtoonTable.bounds.size.width > 1 ? self.webtoonTable.bounds.size.width : UIScreen.mainScreen.bounds.size.width;
                for (NSInteger i = 0; i < shift; i++) {
                    NSNumber *h = self.webtoonHeights[@(i)];
                    prependH += h ? h.doubleValue : MAX(220, w * 1.4);
                }

                self.suppressingWebtoonScrollSave = YES;
                self.currentIndex = self.currentIndex + shift;
                if (self.webtoonTable.window && !self.webtoonTable.hidden) {
                    CGPoint offset = self.webtoonTable.contentOffset;
                    [self.webtoonTable reloadData];
                    offset.y += prependH;
                    [self.webtoonTable setContentOffset:offset animated:NO];
                    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.05 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                        self.suppressingWebtoonScrollSave = NO;
                        if (thenScroll) {
                            NSInteger target = shift - 1;
                            self.currentIndex = MAX(0, target);
                            [self p_scrollWebtoonToIndex:self.currentIndex animated:YES];
                            [self p_syncChapterFromCurrentIndex];
                            [self p_updatePageInfo];
                            [self p_saveProgressWithChapter];
                        }
                    });
                } else {
                    [self.webtoonTable reloadData];
                    self.suppressingWebtoonScrollSave = NO;
                    if (thenScroll) {
                        self.currentIndex = MAX(0, shift - 1);
                        [self p_scrollWebtoonToIndex:self.currentIndex animated:NO];
                        [self p_syncChapterFromCurrentIndex];
                    }
                }
            }
            [self p_prefetchAround:self.currentIndex];
        });
    });
}

/// 接近话边界时静默预加载邻话(条漫连续滚的关键)
- (void)p_prefetchAdjacentChapterIfNeeded
{
    if (!self.chapter || self.isExtendingChapter || self.isSwitchingChapter) {
        return;
    }
    if (self.pages.count == 0 || ![self p_isWebtoon]) {
        // 翻页模式:不预挂载,只在跨话软切时加载
        return;
    }
    NSRange r = [self p_rangeOfChapter:self.chapter];
    if (r.length == 0) {
        return;
    }
    NSInteger local = self.currentIndex - (NSInteger)r.location;
    // 末 3 页内预接下一话
    if (local >= (NSInteger)r.length - 3) {
        RDCharpterModel *next = [self p_chapterAdjacent:YES toChapter:self.chapter];
        if (next && ![self.loadedChapterIds containsObject:@(next.charpterId)]) {
            [self p_webtoonExtendChapter:next forward:YES thenScroll:NO];
        }
    }
    // 前 2 页内预接上一话
    if (local <= 1) {
        RDCharpterModel *prev = [self p_chapterAdjacent:NO toChapter:self.chapter];
        if (prev && ![self.loadedChapterIds containsObject:@(prev.charpterId)]) {
            [self p_webtoonExtendChapter:prev forward:NO thenScroll:NO];
        }
    }
}

- (void)p_layoutImage
{
    UIImage *image = self.imageView.image;
    CGSize bounds = self.zoomScroll.bounds.size;
    if (!image || bounds.width < 1 || bounds.height < 1) {
        self.imageView.frame = CGRectZero;
        self.zoomScroll.contentSize = bounds;
        return;
    }
    CGFloat scale = MIN(bounds.width / image.size.width, bounds.height / image.size.height);
    CGFloat w = image.size.width * scale;
    CGFloat h = image.size.height * scale;
    self.imageView.frame = CGRectMake(0, 0, w, h);
    self.zoomScroll.contentSize = CGSizeMake(w, h);
    CGFloat ox = MAX(0, (bounds.width - w) / 2.0);
    CGFloat oy = MAX(0, (bounds.height - h) / 2.0);
    self.zoomScroll.contentInset = UIEdgeInsetsMake(oy, ox, oy, ox);
}

- (void)p_updatePageInfo
{
    // 进度以「当前话内」计,避免条漫连续加载后页码爆炸
    NSInteger total = [self p_pageCountInCurrentChapter];
    if (total <= 0) {
        total = (NSInteger)self.pages.count;
    }
    NSInteger local = [self p_localPageInCurrentChapter];
    NSInteger cur = total > 0 ? (local + 1) : 0;
    CGFloat percent = (total > 0) ? (100.0 * cur / (CGFloat)total) : 0;
    if (self.chapter.name.length > 0) {
        self.pageLabel.text = [NSString stringWithFormat:@"%@  ·  %ld / %ld  ·  %.0f%%",
                               self.chapter.name, (long)cur, (long)total, percent];
    } else if (total > 0) {
        self.pageLabel.text = [NSString stringWithFormat:@"%ld / %ld  ·  %.0f%%",
                               (long)cur, (long)total, percent];
    } else {
        self.pageLabel.text = @"—";
    }
    [self p_updateSliderForCurrentChapter];
    [self p_updateArrowStates];
}

- (void)p_saveRecord
{
    NSInteger local = [self p_localPageInCurrentChapter];
    NSInteger chapterTotal = [self p_pageCountInCurrentChapter];
    self.bookDetail.page = local;
    self.bookDetail.total = chapterTotal > 0 ? chapterTotal : (NSInteger)self.pages.count;
    [RDReadRecordManager asyncUpdatePage:local forBookId:self.bookDetail.bookId];
}

- (void)p_saveProgressWithChapter
{
    NSInteger local = [self p_localPageInCurrentChapter];
    NSInteger chapterTotal = [self p_pageCountInCurrentChapter];
    self.bookDetail.page = local;
    self.bookDetail.total = chapterTotal > 0 ? chapterTotal : (NSInteger)self.pages.count;
    if (self.chapter) {
        self.bookDetail.charpterModel = self.chapter;
        self.bookDetail.readChapterName = self.chapter.name;
    }
    [RDReadRecordManager updateProgressWithModel:self.bookDetail];
}

#pragma mark - Page interaction (LTR / RTL)

- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)gestureRecognizer
{
    if ([gestureRecognizer isKindOfClass:UISwipeGestureRecognizer.class]) {
        return self.zoomScroll.zoomScale <= 1.01 && !self.zoomScroll.hidden;
    }
    return YES;
}

/// 点屏/滑动翻页(页内)
- (void)p_goNext
{
    if ([self p_isWebtoon]) {
        [self p_webtoonStepPage:YES];
        return;
    }
    [self p_turnForward:YES];
}

- (void)p_goPrev
{
    if ([self p_isWebtoon]) {
        [self p_webtoonStepPage:NO];
        return;
    }
    [self p_turnForward:NO];
}

/// 底栏左右箭头:上一话 / 下一话
- (void)p_goPrevChapter
{
    [self p_goAdjacentChapter:NO];
}

- (void)p_goNextChapter
{
    [self p_goAdjacentChapter:YES];
}

/// 条漫页内步进(点屏边缘);到列表边界再尝试接话
- (void)p_webtoonStepPage:(BOOL)forward
{
    if (self.isExtendingChapter || self.isSwitchingChapter || self.pages.count == 0) {
        return;
    }
    NSInteger target = forward ? (self.currentIndex + 1) : (self.currentIndex - 1);
    if (target >= 0 && target < (NSInteger)self.pages.count) {
        self.currentIndex = target;
        [self p_scrollWebtoonToIndex:target animated:YES];
        [self p_syncChapterFromCurrentIndex];
        [self p_updatePageInfo];
        [self p_saveRecord];
        [self p_prefetchAdjacentChapterIfNeeded];
        return;
    }
    // 页边界:静默接邻话并滚过去,保持阅读连贯
    [self p_goAdjacentChapter:forward];
}

- (void)p_swipeLeft
{
    if ([self p_isRTL]) {
        [self p_goPrev];
    } else {
        [self p_goNext];
    }
}

- (void)p_swipeRight
{
    if ([self p_isRTL]) {
        [self p_goNext];
    } else {
        [self p_goPrev];
    }
}

- (void)p_handlePageTap:(UITapGestureRecognizer *)tap
{
    CGPoint p = [tap locationInView:self.zoomScroll];
    CGFloat w = self.zoomScroll.bounds.size.width;
    if (p.x < w * 0.28) {
        if ([self p_isRTL]) {
            [self p_goNext];
        } else {
            [self p_goPrev];
        }
        return;
    }
    if (p.x > w * 0.72) {
        if ([self p_isRTL]) {
            [self p_goPrev];
        } else {
            [self p_goNext];
        }
        return;
    }
    [self p_toggleBars];
}

- (void)p_handleDoubleTap:(UITapGestureRecognizer *)tap
{
    if (self.zoomScroll.zoomScale > 1.01) {
        [self.zoomScroll setZoomScale:1.0 animated:YES];
    } else {
        CGPoint point = [tap locationInView:self.imageView];
        CGFloat scale = MIN(self.zoomScroll.maximumZoomScale, 2.5);
        CGFloat w = self.zoomScroll.bounds.size.width / scale;
        CGFloat h = self.zoomScroll.bounds.size.height / scale;
        CGRect rect = CGRectMake(point.x - w / 2, point.y - h / 2, w, h);
        [self.zoomScroll zoomToRect:rect animated:YES];
    }
}

- (void)p_handleWebtoonTap:(UITapGestureRecognizer *)tap
{
    if (self.webtoonTable.isDragging || self.webtoonTable.isDecelerating) {
        return;
    }
    CGPoint p = [tap locationInView:self.webtoonTable];
    CGFloat h = self.webtoonTable.bounds.size.height;
    CGFloat y = p.y - self.webtoonTable.contentOffset.y;
    if (y > h * 0.30 && y < h * 0.70) {
        [self p_toggleBars];
    }
}

- (void)p_toggleBars
{
    self.barsHidden = !self.barsHidden;
    CGFloat bottomHeight = kRDComicBottomContentHeight + [UIView safeBottomBar];
    [UIView animateWithDuration:0.25 animations:^{
        self.topView.top = self.barsHidden ? -self.topView.height : 0;
        self.bottomBar.top = self.barsHidden ? self.view.height : self.view.height - bottomHeight;
        self.topView.alpha = self.barsHidden ? 0 : 1;
        self.bottomBar.alpha = self.barsHidden ? 0 : 1;
    }];
}

- (void)p_sliderChanged:(UISlider *)slider
{
    // slider 值是当前话内页码
    NSInteger local = (NSInteger)llroundf(slider.value);
    NSInteger total = [self p_pageCountInCurrentChapter];
    NSInteger cur = total > 0 ? (local + 1) : 0;
    CGFloat percent = (total > 0) ? (100.0 * cur / (CGFloat)total) : 0;
    if (self.chapter.name.length > 0) {
        self.pageLabel.text = [NSString stringWithFormat:@"%@  ·  %ld / %ld  ·  %.0f%%",
                               self.chapter.name, (long)cur, (long)total, percent];
    } else {
        self.pageLabel.text = [NSString stringWithFormat:@"%ld / %ld  ·  %.0f%%",
                               (long)cur, (long)total, percent];
    }
}

- (void)p_sliderEnded:(UISlider *)slider
{
    NSInteger local = (NSInteger)llroundf(slider.value);
    NSRange r = [self p_rangeOfChapter:self.chapter];
    NSInteger global = (NSInteger)r.location + local;
    global = MAX(0, MIN(global, (NSInteger)self.pages.count - 1));
    if ([self p_isWebtoon]) {
        self.currentIndex = global;
        [self p_scrollWebtoonToIndex:self.currentIndex animated:YES];
        [self p_saveRecord];
        [self p_updatePageInfo];
    } else {
        [self p_showPage:global save:YES];
    }
}

#pragma mark - Webtoon table

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    return (NSInteger)self.pages.count;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath
{
    NSNumber *cached = self.webtoonHeights[@(indexPath.row)];
    if (cached) {
        return cached.doubleValue;
    }
    CGFloat w = tableView.bounds.size.width > 1 ? tableView.bounds.size.width : UIScreen.mainScreen.bounds.size.width;
    return MAX(220, w * 1.4);
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    RDComicWebtoonCell *cell = [tableView dequeueReusableCellWithIdentifier:kRDComicWebtoonCellId forIndexPath:indexPath];
    NSInteger idx = indexPath.row;
    cell.pageIndex = idx;
    UIImage *cached = [self p_cachedImageAtIndex:idx];
    cell.pageView.image = cached;
    if (!cached) {
        __weak typeof(self) weakSelf = self;
        __weak RDComicWebtoonCell *weakCell = cell;
        [self p_decodeIndex:idx completion:^(UIImage *image) {
            __strong typeof(weakSelf) self = weakSelf;
            __strong RDComicWebtoonCell *strongCell = weakCell;
            if (!self || !strongCell || strongCell.pageIndex != idx) {
                return;
            }
            strongCell.pageView.image = image;
            // 高度若从估算变精确,只改一次,避免 beginUpdates 风暴
            NSNumber *oldH = self.webtoonHeights[@(idx)];
            [self p_rememberHeightForIndex:idx image:image];
            NSNumber *newH = self.webtoonHeights[@(idx)];
            if (oldH && newH && fabs(oldH.doubleValue - newH.doubleValue) > 2.0) {
                [UIView performWithoutAnimation:^{
                    [tableView beginUpdates];
                    [tableView endUpdates];
                }];
            }
        }];
    } else {
        [self p_rememberHeightForIndex:idx image:cached];
    }
    [self p_prefetchAround:idx];
    return cell;
}

- (void)p_scrollWebtoonToIndex:(NSInteger)index animated:(BOOL)animated
{
    if (self.pages.count == 0 || self.webtoonTable.hidden) {
        return;
    }
    index = MAX(0, MIN(index, (NSInteger)self.pages.count - 1));
    self.suppressingWebtoonScrollSave = YES;
    // 确保数据已 reload
    if (self.webtoonTable.numberOfSections > 0 &&
        [self.webtoonTable numberOfRowsInSection:0] > index) {
        NSIndexPath *ip = [NSIndexPath indexPathForRow:index inSection:0];
        [self.webtoonTable scrollToRowAtIndexPath:ip atScrollPosition:UITableViewScrollPositionTop animated:animated];
    }
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)((animated ? 0.4 : 0.05) * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        self.suppressingWebtoonScrollSave = NO;
    });
}

- (void)p_syncIndexFromWebtoon
{
    if (self.webtoonTable.hidden) {
        return;
    }
    NSArray <NSIndexPath *>*visible = [self.webtoonTable indexPathsForVisibleRows];
    if (visible.count == 0) {
        return;
    }
    CGFloat mid = self.webtoonTable.contentOffset.y + self.webtoonTable.bounds.size.height * 0.35;
    NSInteger best = self.currentIndex;
    CGFloat bestDist = CGFLOAT_MAX;
    for (NSIndexPath *ip in visible) {
        CGRect r = [self.webtoonTable rectForRowAtIndexPath:ip];
        CGFloat dist = fabs(CGRectGetMidY(r) - mid);
        if (dist < bestDist) {
            bestDist = dist;
            best = ip.row;
        }
    }
    if (best != self.currentIndex) {
        self.currentIndex = best;
        [self p_syncChapterFromCurrentIndex];
        [self p_updatePageInfo];
        [self p_saveRecord];
    } else {
        [self p_syncChapterFromCurrentIndex];
    }
    // 接近话界时静默把下一话页接上,用户继续滑即可读
    [self p_prefetchAdjacentChapterIfNeeded];
}

- (void)scrollViewDidScroll:(UIScrollView *)scrollView
{
    if (scrollView != self.webtoonTable || self.suppressingWebtoonScrollSave || ![self p_isWebtoon]) {
        return;
    }
    // 轻量:滑近底部时提前接话(不依赖松手)
    CGFloat maxY = MAX(0, scrollView.contentSize.height - scrollView.bounds.size.height);
    if (scrollView.contentOffset.y > maxY - 600) {
        [self p_prefetchAdjacentChapterIfNeeded];
    }
}

- (void)scrollViewDidEndDecelerating:(UIScrollView *)scrollView
{
    if (scrollView == self.webtoonTable && !self.suppressingWebtoonScrollSave) {
        [self p_syncIndexFromWebtoon];
        [self p_maybeCrossChapterFromWebtoonScroll:scrollView];
    }
}

- (void)scrollViewDidEndDragging:(UIScrollView *)scrollView willDecelerate:(BOOL)decelerate
{
    if (scrollView == self.webtoonTable && !self.suppressingWebtoonScrollSave) {
        if (!decelerate) {
            [self p_syncIndexFromWebtoon];
        }
        [self p_maybeCrossChapterFromWebtoonScroll:scrollView];
    }
}

/// 条漫过滑:若邻话未接上则静默扩展;已接上则自然滚入,不再「重开」
- (void)p_maybeCrossChapterFromWebtoonScroll:(UIScrollView *)scrollView
{
    if (![self p_isWebtoon] || self.isSwitchingChapter || self.isExtendingChapter || !self.chapter || self.pages.count == 0) {
        return;
    }
    CGFloat maxY = MAX(0, scrollView.contentSize.height - scrollView.bounds.size.height);
    CGFloat y = scrollView.contentOffset.y;
    if (self.currentIndex >= (NSInteger)self.pages.count - 1 && y > maxY + 24) {
        RDCharpterModel *next = [self p_adjacentChapter:YES];
        if (!next) {
            [self showText:@"已经是最后一话"];
            return;
        }
        // 未加载则接上(thenScroll=NO,用户接着滑即可);已在尾部则已无更多行
        if (![self.loadedChapterIds containsObject:@(next.charpterId)]) {
            [self p_webtoonExtendChapter:next forward:YES thenScroll:NO];
        }
        return;
    }
    if (self.currentIndex <= 0 && y < -24) {
        RDCharpterModel *prev = [self p_adjacentChapter:NO];
        if (!prev) {
            [self showText:@"已经是第一话"];
            return;
        }
        if (![self.loadedChapterIds containsObject:@(prev.charpterId)]) {
            [self p_webtoonExtendChapter:prev forward:NO thenScroll:NO];
        }
    }
}

- (void)scrollViewDidEndScrollingAnimation:(UIScrollView *)scrollView
{
    if (scrollView == self.webtoonTable) {
        self.suppressingWebtoonScrollSave = NO;
        [self p_syncIndexFromWebtoon];
    }
}

#pragma mark - UIScrollViewDelegate (zoom)

- (UIView *)viewForZoomingInScrollView:(UIScrollView *)scrollView
{
    if (scrollView == self.zoomScroll) {
        return self.imageView;
    }
    return nil;
}

- (void)scrollViewDidZoom:(UIScrollView *)scrollView
{
    if (scrollView != self.zoomScroll) {
        return;
    }
    CGSize bounds = scrollView.bounds.size;
    CGSize size = scrollView.contentSize;
    CGFloat ox = MAX(0, (bounds.width - size.width) / 2.0);
    CGFloat oy = MAX(0, (bounds.height - size.height) / 2.0);
    scrollView.contentInset = UIEdgeInsetsMake(oy, ox, oy, ox);
}

- (void)viewWillDisappear:(BOOL)animated
{
    [super viewWillDisappear:animated];
    if ([self p_isWebtoon]) {
        [self p_syncIndexFromWebtoon];
    }
    [self p_saveProgressWithChapter];
}

- (UIStatusBarStyle)preferredStatusBarStyle
{
    return UIStatusBarStyleLightContent;
}

@end
