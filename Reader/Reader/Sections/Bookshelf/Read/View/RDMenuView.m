//
//  RDMenuView.m
//  Reader
//
//  Created by yuenov on 2019/11/13.
//  Copyright © 2019 yuenov. All rights reserved.
//

#import "RDMenuView.h"
#import "RDReadSetView.h"
#import "RDReadLightView.h"
#import "RDReadProgressView.h"
#import "RDReadCatalogView.h"
#import "RDReadCatalogCell.h"
#import "RDReadBookmarkView.h"
#import "RDBookmarkModel.h"
#import "RDDisplayBoost.h"
#import "RDReadConfigManager.h"

#define kToolBarHeight (50+[UIView safeBottomBar])
#define kSetViewHeight 180
#define kBookmarkViewHeight MIN(ScreenHeight * 0.55, 420)

@interface RDMenuView () <RDReadToolBarDelegate,RDReadCatalogViewDelegate,RDReadProgressViewDelegate,RDReadTopBarDelegate,RDReadSetViewDelegate,RDReadBookmarkViewDelegate>
@property (nonatomic,strong) RDReadSetView *setView;
@property (nonatomic,strong) RDReadLightView *lightView;
@property (nonatomic,strong) RDReadProgressView *progressView;
@property (nonatomic,strong) RDReadCatalogView *catalogView;
@property (nonatomic,strong) RDReadBookmarkView *bookmarkView;
@property (nonatomic,strong) UIView *showView;
@property (nonatomic,strong) UIView *gesView;
@end
@implementation RDMenuView

-(instancetype)initWithFrame:(CGRect)frame{
    self = [super initWithFrame:frame];
    if (self) {
        [self addSubview:self.gesView];
        [self addSubview:self.setView];
        [self addSubview:self.lightView];
        [self addSubview:self.progressView];
        [self addSubview:self.bookmarkView];
        [self addSubview:self.topBar];
        [self addSubview:self.catalogView];
        [self addSubview:self.toolBar];
        
        
        [self setBackgroundColor:[UIColor clearColor]];
        // 夜读/换纸色时同步顶底栏与功能面板,避免正文已黑面板仍是浅色
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(p_onReadThemeDidChange)
                                                     name:RDReadThemeDidChangeNotification
                                                   object:nil];
        [self p_applyChromeThemeToAll];
    }
    return self;
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

/// 刷新菜单体系所有 chrome(顶栏/底栏/亮度/设置/进度/书签/目录)
- (void)p_applyChromeThemeToAll
{
    [self.toolBar applyChromeTheme];
    [self.topBar applyChromeTheme];
    [self.lightView applyChromeTheme];
    [self.setView applyChromeTheme];
    [self.progressView applyChromeTheme];
    [self.bookmarkView applyChromeTheme];
    [self.catalogView applyChromeTheme];
}

- (void)p_onReadThemeDidChange
{
    [self p_applyChromeThemeToAll];
}

-(void)setCharpters:(NSArray<RDCharpterModel *> *)charpters
{
    _charpters = charpters;
    self.catalogView.charpters = charpters;
    self.progressView.charpters = charpters;
}
-(void)setBook:(RDBookDetailModel *)book
{
    _book = book;
    self.catalogView.book = book;
    self.progressView.book = book;
    self.bookmarkView.book = book;
    self.topBar.record = book;
    
}
-(RDReadToolBar *)toolBar
{
    if (!_toolBar) {
        _toolBar = [[RDReadToolBar alloc] initWithFrame:CGRectMake(0, ScreenSize.height, ScreenSize.width, kToolBarHeight)];
        _toolBar.delegate = self;
    }
    return _toolBar;
}
-(RDReadTopBar *)topBar
{
    if (!_topBar) {
        CGFloat height = [UIView navigationBar]+[UIView statusBar];
        _topBar = [[RDReadTopBar alloc] initWithFrame:CGRectMake(0, -height, ScreenSize.width, height)];
        _topBar.delegate = self;
        
    }
    return _topBar;
}

-(RDReadCatalogView *)catalogView
{
    if (!_catalogView) {
        _catalogView = [[RDReadCatalogView alloc] init];
        __weak typeof(self) weakSelf = self;
        _catalogView.clickBg = ^{
            [weakSelf.toolBar.menu sendActionsForControlEvents:UIControlEventTouchUpInside];
        };
        _catalogView.delegate = self;
        
    }
    return _catalogView;
}

-(RDReadSetView *)setView
{
    if (!_setView) {
        _setView = [[RDReadSetView alloc] initWithFrame:CGRectMake(0, ScreenSize.height, ScreenSize.width, kSetViewHeight)];
        _setView.delegate = self;
    }
    return _setView;
}
-(RDReadLightView *)lightView
{
    if (!_lightView) {
        _lightView = [[RDReadLightView alloc] initWithFrame:CGRectMake(0, ScreenSize.height, ScreenSize.width, 120)];
    }
    return _lightView;
}

-(RDReadProgressView *)progressView
{
    if (!_progressView) {
        _progressView = [[RDReadProgressView alloc] initWithFrame:CGRectMake(0, ScreenSize.height, ScreenSize.width, 120)];
        _progressView.delegate = self;
    }
    return _progressView;
}

-(RDReadBookmarkView *)bookmarkView
{
    if (!_bookmarkView) {
        _bookmarkView = [[RDReadBookmarkView alloc] initWithFrame:CGRectMake(0, ScreenSize.height, ScreenSize.width, kBookmarkViewHeight)];
        _bookmarkView.delegate = self;
    }
    return _bookmarkView;
}

-(UIView *)gesView
{
    if (!_gesView) {
        _gesView = [[UIView alloc] init];
        _gesView.backgroundColor = [UIColor clearColor];
        [_gesView addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(ges:)]];
    }
    return _gesView;
}

-(void)ges:(UITapGestureRecognizer *)ges
{
    if ([self.delegate respondsToSelector:@selector(cancelShowMenu:)]) {
        [self.delegate cancelShowMenu:self];
    }
}

-(void)showInView:(UIView *)view
{
    self.frame = view.bounds;
    [self p_applyChromeThemeToAll];
    [view addSubview:self];
    [UIView animateWithDuration:[RDDisplayBoost panelAnimationDuration] animations:^{
        self.toolBar.frame = CGRectMake(0, self.height-kToolBarHeight, self.width, kToolBarHeight);
        self.topBar.frame = CGRectMake(0, 0, self.width, [UIView navigationBar]+[UIView statusBar]);
    }];
}
-(void)dismiss
{
    [UIView animateWithDuration:[RDDisplayBoost panelAnimationDuration] animations:^{
        self.toolBar.frame = CGRectMake(0, ScreenHeight, ScreenWidth, kToolBarHeight);
         CGFloat height = [UIView navigationBar]+[UIView statusBar];
        self.topBar.frame = CGRectMake(0, -height, ScreenSize.width, height);
        if (self.showView) {
            self.showView.frame = CGRectMake(0, ScreenHeight, self.showView.width, self.showView.height);
        }
    } completion:^(BOOL finished) {
        [self removeFromSuperview];
    }];
}
-(void)showInView:(UIView *)view complete:(void(^)(void))complete
{
    self.frame = view.bounds;
    [self p_applyChromeThemeToAll];
    [view addSubview:self];
    [UIView animateWithDuration:[RDDisplayBoost panelAnimationDuration] animations:^{
        self.toolBar.frame = CGRectMake(0, self.height-kToolBarHeight, self.width, kToolBarHeight);
        self.topBar.frame = CGRectMake(0, 0, self.width, [UIView navigationBar]+[UIView statusBar]);
    } completion:^(BOOL finished) {
        if (complete) {
            complete();
        }
    }];
}
-(void)dismissComplete:(void(^)(void))complete
{
    [UIView animateWithDuration:[RDDisplayBoost panelAnimationDuration] animations:^{
        self.toolBar.frame = CGRectMake(0, ScreenHeight, ScreenWidth, kToolBarHeight);
         CGFloat height = [UIView navigationBar]+[UIView statusBar];
        self.topBar.frame = CGRectMake(0, -height, ScreenSize.width, height);
        if (self.showView) {
            self.showView.frame = CGRectMake(0, ScreenHeight, self.showView.width, self.showView.height);
        }
    } completion:^(BOOL finished) {
        [self removeFromSuperview];
        if (complete) {
            complete();
        }
    }];
}
#pragma mark - Action
-(void)didMenu
{
    if (self.showView && self.showView!=self.catalogView) {
        [self.catalogView show];
        self.showView.frame = CGRectMake(0, ScreenHeight, self.showView.width, self.showView.height);
        self.showView = self.catalogView;
    }
    else{
        if (self.showView == self.catalogView) {
            [self.catalogView dismiss];
            self.showView = nil;
        }else{
            [self.catalogView show];
            self.showView = self.catalogView;
        }
    }
}
-(void)didSlider
{
    if (self.showView && self.showView!=self.progressView) {
        self.progressView.frame = CGRectMake(0, self.height-kToolBarHeight-120, ScreenWidth, 120);
        if (self.showView == self.catalogView) {
            [self.catalogView dismiss];
        }
        else{
            self.showView.frame = CGRectMake(0, ScreenHeight, self.showView.width, self.showView.height);
        }
        self.showView = self.progressView;
    }
    else{
        if (self.showView == self.progressView) {
            [UIView animateWithDuration:[RDDisplayBoost panelAnimationDuration] animations:^{
                self.progressView.frame = CGRectMake(0, ScreenHeight, ScreenWidth, 120);
            }];
            self.showView = nil;
        }else{
            [UIView animateWithDuration:[RDDisplayBoost panelAnimationDuration] animations:^{
                self.progressView.frame = CGRectMake(0, self.height-kToolBarHeight-120, ScreenWidth, 120);
            }];
            self.showView = self.progressView;
        }
    }
}

-(void)didBookmark
{
    CGFloat h = kBookmarkViewHeight;
    if (self.showView && self.showView != self.bookmarkView) {
        self.bookmarkView.frame = CGRectMake(0, self.height - kToolBarHeight - h, ScreenWidth, h);
        if (self.showView == self.catalogView) {
            [self.catalogView dismiss];
        } else {
            self.showView.frame = CGRectMake(0, ScreenHeight, self.showView.width, self.showView.height);
        }
        [self.bookmarkView reloadData];
        self.showView = self.bookmarkView;
    } else {
        if (self.showView == self.bookmarkView) {
            [UIView animateWithDuration:[RDDisplayBoost panelAnimationDuration] animations:^{
                self.bookmarkView.frame = CGRectMake(0, ScreenHeight, ScreenWidth, h);
            }];
            self.showView = nil;
        } else {
            [self.bookmarkView reloadData];
            [UIView animateWithDuration:[RDDisplayBoost panelAnimationDuration] animations:^{
                self.bookmarkView.frame = CGRectMake(0, self.height - kToolBarHeight - h, ScreenWidth, h);
            }];
            self.showView = self.bookmarkView;
        }
    }
}

-(void)didLight
{
    if (self.showView && self.showView!=self.lightView) {
        self.lightView.frame = CGRectMake(0, self.height-kToolBarHeight-120, ScreenWidth, 120);
        if (self.showView == self.catalogView) {
            [self.catalogView dismiss];
        }
        else{
            self.showView.frame = CGRectMake(0, ScreenHeight, self.showView.width, self.showView.height);
        }
        
        self.showView = self.lightView;
    }
    else{
        if (self.showView == self.lightView) {
            [UIView animateWithDuration:[RDDisplayBoost panelAnimationDuration] animations:^{
                self.lightView.frame = CGRectMake(0, ScreenHeight, ScreenWidth, 120);
            }];
            self.showView = nil;
        }else{
            [UIView animateWithDuration:[RDDisplayBoost panelAnimationDuration] animations:^{
                self.lightView.frame = CGRectMake(0, self.height-kToolBarHeight-120, ScreenWidth, 120);
            }];
            self.showView = self.lightView;
        }
    }
    
}
-(void)didSetting
{
    if (self.showView && self.showView!=self.setView) {
        self.setView.frame = CGRectMake(0, self.height-kToolBarHeight-kSetViewHeight, ScreenWidth, kSetViewHeight);
        if (self.showView == self.catalogView) {
            [self.catalogView dismiss];
        }
        else{
            self.showView.frame = CGRectMake(0, ScreenHeight, self.showView.width, self.showView.height);
        }
        self.showView = self.setView;
    }
    else{
        if (self.showView == self.setView) {
           [UIView animateWithDuration:[RDDisplayBoost panelAnimationDuration] animations:^{
               self.setView.frame = CGRectMake(0, ScreenHeight, ScreenWidth, kSetViewHeight);
           }];
           self.showView = nil;
        }else{
            [UIView animateWithDuration:[RDDisplayBoost panelAnimationDuration] animations:^{
                           self.setView.frame = CGRectMake(0, self.height-kToolBarHeight-kSetViewHeight, ScreenWidth, kSetViewHeight);
                       }];
                       self.showView = self.setView;
        }
    }
    
}

#pragma mark -Delegate

-(void)didSelectCharpter:(RDCharpterModel *)charpter
{
    if ([self.delegate respondsToSelector:@selector(didSelectCharpter:)]) {
        [self.delegate didSelectCharpter:charpter];
    }
}

-(void)sliderToCharpter:(RDCharpterModel *)charpter
{
    if ([self.delegate respondsToSelector:@selector(sliderToCharpter:)]) {
        [self.delegate sliderToCharpter:charpter];
    }
}

-(void)bookmarkViewDidSelect:(RDBookmarkModel *)bookmark
{
    if ([self.delegate respondsToSelector:@selector(bookmarkViewDidSelect:)]) {
        [self.delegate bookmarkViewDidSelect:bookmark];
    }
}

-(void)bookmarkViewDidAddCurrent
{
    if ([self.delegate respondsToSelector:@selector(bookmarkViewDidAddCurrent)]) {
        [self.delegate bookmarkViewDidAddCurrent];
    }
}

-(void)backAction
{
    if ([self.delegate respondsToSelector:@selector(backAction)]) {
        [self.delegate backAction];
    }
}

-(void)speechAction
{
    if ([self.delegate respondsToSelector:@selector(speechAction)]) {
        [self.delegate speechAction];
    }
}

-(void)shareQuoteAction
{
    if ([self.delegate respondsToSelector:@selector(shareQuoteAction)]) {
        [self.delegate shareQuoteAction];
    }
}

-(void)didChangePageType
{
    if ([self.delegate respondsToSelector:@selector(didChangePageType)]) {
        [self.delegate didChangePageType];
    }
}



-(void)layoutSubviews
{
    [super layoutSubviews];
    self.gesView.frame = self.bounds;
}
@end
