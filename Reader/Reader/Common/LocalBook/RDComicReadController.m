//
//  RDComicReadController.m
//  Reader
//

#import "RDComicReadController.h"
#import "RDBookDetailModel.h"
#import "RDLocalBookManager.h"
#import "RDReadRecordManager.h"
#import "RDZipArchive.h"
#import "RDComicHelper.h"

@interface RDComicReadController () <UIScrollViewDelegate, UIGestureRecognizerDelegate>
@property (nonatomic,strong) UIScrollView *zoomScroll;
@property (nonatomic,strong) UIImageView *imageView;
@property (nonatomic,strong) UILabel *pageLabel;
@property (nonatomic,strong) UISlider *pageSlider;
@property (nonatomic,strong) UIView *bottomBar;
@property (nonatomic,assign) BOOL barsHidden;
@property (nonatomic,strong) RDZipArchive *archive;
@property (nonatomic,copy) NSArray <NSString *>*pages;
@property (nonatomic,assign) NSInteger currentIndex;
@property (nonatomic,strong) NSCache <NSNumber *,UIImage *>*imageCache;
@end

@implementation RDComicReadController

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor blackColor];
    self.imageCache = [[NSCache alloc] init];
    self.imageCache.countLimit = 5;

    self.topView.titleLabel.text = self.bookDetail.title;
    self.topView.titleLabel.textColor = [UIColor whiteColor];
    self.topView.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.55];
    [self.view addSubview:self.zoomScroll];
    [self.zoomScroll addSubview:self.imageView];
    [self.view addSubview:self.topView];
    [self.view addSubview:self.bottomBar];

    if (![self p_loadPages]) {
        [self showText:@"无法打开该图集"];
        return;
    }

    NSInteger page = self.bookDetail.page;
    if (page < 0) {
        page = 0;
    }
    if (page >= (NSInteger)self.pages.count) {
        page = MAX(0, (NSInteger)self.pages.count - 1);
    }
    self.pageSlider.maximumValue = MAX(0, (NSInteger)self.pages.count - 1);
    [self p_showPage:page];

    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(p_handleTap:)];
    tap.numberOfTapsRequired = 1;
    [self.zoomScroll addGestureRecognizer:tap];

    UITapGestureRecognizer *doubleTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(p_handleDoubleTap:)];
    doubleTap.numberOfTapsRequired = 2;
    [self.zoomScroll addGestureRecognizer:doubleTap];
    [tap requireGestureRecognizerToFail:doubleTap];

    UISwipeGestureRecognizer *left = [[UISwipeGestureRecognizer alloc] initWithTarget:self action:@selector(p_swipeLeft)];
    left.direction = UISwipeGestureRecognizerDirectionLeft;
    left.delegate = self;
    [self.zoomScroll addGestureRecognizer:left];
    UISwipeGestureRecognizer *right = [[UISwipeGestureRecognizer alloc] initWithTarget:self action:@selector(p_swipeRight)];
    right.direction = UISwipeGestureRecognizerDirectionRight;
    right.delegate = self;
    [self.zoomScroll addGestureRecognizer:right];
}

// 放大状态下滑动应平移图片,不触发翻页
- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)gestureRecognizer
{
    if ([gestureRecognizer isKindOfClass:UISwipeGestureRecognizer.class]) {
        return self.zoomScroll.zoomScale <= 1.01;
    }
    return YES;
}

- (BOOL)p_loadPages
{
    NSString *path = [RDLocalBookManager absolutePathForBook:self.bookDetail];
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
        self.pages = abs.copy;
        self.archive = nil;
        return self.pages.count > 0;
    }
    self.archive = [[RDZipArchive alloc] initWithPath:path];
    self.pages = [RDComicHelper sortedImageEntriesInZip:self.archive];
    return self.pages.count > 0;
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

- (UIView *)bottomBar
{
    if (!_bottomBar) {
        _bottomBar = [[UIView alloc] init];
        _bottomBar.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.55];
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
        _pageSlider.maximumTrackTintColor = [UIColor colorWithWhite:1 alpha:0.25];
        [_pageSlider addTarget:self action:@selector(p_sliderChanged:) forControlEvents:UIControlEventValueChanged];
        [_pageSlider addTarget:self action:@selector(p_sliderEnded:) forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside];
    }
    return _pageSlider;
}

- (UILabel *)pageLabel
{
    if (!_pageLabel) {
        _pageLabel = [[UILabel alloc] init];
        _pageLabel.font = RDFont13;
        _pageLabel.textColor = [UIColor colorWithWhite:1 alpha:0.85];
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
    self.zoomScroll.frame = self.view.bounds;
    [self p_layoutImage];
}

#pragma mark - Pages

- (UIImage *)p_imageAtIndex:(NSInteger)index
{
    if (index < 0 || index >= (NSInteger)self.pages.count) {
        return nil;
    }
    NSNumber *key = @(index);
    UIImage *cached = [self.imageCache objectForKey:key];
    if (cached) {
        return cached;
    }
    NSData *data = nil;
    if (self.archive) {
        data = [self.archive dataForEntry:self.pages[index]];
    } else {
        data = [NSData dataWithContentsOfFile:self.pages[index] options:NSDataReadingMappedIfSafe error:nil];
    }
    UIImage *image = [RDComicHelper imageFromData:data];
    if (image) {
        [self.imageCache setObject:image forKey:key];
    }
    return image;
}

- (void)p_showPage:(NSInteger)index
{
    if (self.pages.count == 0) {
        return;
    }
    index = MAX(0, MIN(index, (NSInteger)self.pages.count - 1));
    self.currentIndex = index;
    self.zoomScroll.zoomScale = 1.0;
    self.imageView.image = [self p_imageAtIndex:index];
    [self p_layoutImage];
    [self p_updatePageInfo];
    [self p_saveRecord];
    // 预载相邻页
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        [self p_imageAtIndex:index + 1];
        [self p_imageAtIndex:index - 1];
    });
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
    self.pageLabel.text = [NSString stringWithFormat:@"%@ / %@", @(self.currentIndex + 1), @(self.pages.count)];
    if (!self.pageSlider.isTracking) {
        self.pageSlider.value = self.currentIndex;
    }
}

- (void)p_saveRecord
{
    self.bookDetail.page = self.currentIndex;
    self.bookDetail.total = self.pages.count;
    // 每翻一页触发:只按列异步写 page/readTime,不整行回写
    [RDReadRecordManager asyncUpdatePage:self.currentIndex forBookId:self.bookDetail.bookId];
}

#pragma mark - Interaction

- (void)p_handleTap:(UITapGestureRecognizer *)tap
{
    CGPoint p = [tap locationInView:self.zoomScroll];
    CGFloat w = self.zoomScroll.bounds.size.width;
    if (p.x < w * 0.28) {
        [self p_swipeRight];
        return;
    }
    if (p.x > w * 0.72) {
        [self p_swipeLeft];
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

- (void)p_swipeLeft
{
    if (self.currentIndex + 1 < (NSInteger)self.pages.count) {
        [self p_showPage:self.currentIndex + 1];
    }
}

- (void)p_swipeRight
{
    if (self.currentIndex > 0) {
        [self p_showPage:self.currentIndex - 1];
    }
}

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
    self.pageLabel.text = [NSString stringWithFormat:@"%@ / %@", @(index + 1), @(self.pages.count)];
}

- (void)p_sliderEnded:(UISlider *)slider
{
    NSInteger index = (NSInteger)llroundf(slider.value);
    [self p_showPage:index];
}

#pragma mark - UIScrollViewDelegate

- (UIView *)viewForZoomingInScrollView:(UIScrollView *)scrollView
{
    return self.imageView;
}

- (void)scrollViewDidZoom:(UIScrollView *)scrollView
{
    CGSize bounds = scrollView.bounds.size;
    CGSize size = scrollView.contentSize;
    CGFloat ox = MAX(0, (bounds.width - size.width) / 2.0);
    CGFloat oy = MAX(0, (bounds.height - size.height) / 2.0);
    scrollView.contentInset = UIEdgeInsetsMake(oy, ox, oy, ox);
}

- (void)viewWillDisappear:(BOOL)animated
{
    [super viewWillDisappear:animated];
    [self p_saveRecord];
}

- (UIStatusBarStyle)preferredStatusBarStyle
{
    return UIStatusBarStyleLightContent;
}

@end
