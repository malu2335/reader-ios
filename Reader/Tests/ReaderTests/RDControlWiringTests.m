//
//  RDControlWiringTests.m
//  ReaderTests
//
//  防"假按钮"回归。
//
//  阅读进度条两侧的左右箭头曾经是 UIImageView,既无 target-action 也无手势,
//  画在那儿纯装饰,点了毫无反应 —— 这类缺陷静态断言和数据链路用例都抓不到,
//  只能靠"控件必须真的接了线"这条断言守住。
//

#import "RDTestSupport.h"
#import "RDReadProgressView.h"
#import "RDCharpterModel.h"
#import "RDBookDetailModel.h"

@interface RDControlWiringTests : XCTestCase
@end

@implementation RDControlWiringTests

/// 递归收集视图树里所有的 UIControl
- (NSArray<UIControl *> *)p_controlsIn:(UIView *)view
{
    NSMutableArray<UIControl *> *found = [NSMutableArray array];
    for (UIView *sub in view.subviews) {
        if ([sub isKindOfClass:UIControl.class]) {
            [found addObject:(UIControl *)sub];
        }
        [found addObjectsFromArray:[self p_controlsIn:sub]];
    }
    return found;
}

- (RDReadProgressView *)p_progressViewWithChapters:(NSInteger)count currentIndex:(NSInteger)current
{
    RDReadProgressView *view = [[RDReadProgressView alloc] initWithFrame:CGRectMake(0, 0, 390, 120)];
    NSMutableArray<RDCharpterModel *> *chapters = [NSMutableArray array];
    for (NSInteger i = 0; i < count; i++) {
        RDCharpterModel *chapter = [[RDCharpterModel alloc] init];
        chapter.bookId = -1;
        chapter.charpterId = i + 1;
        chapter.name = [NSString stringWithFormat:@"第%ld章", (long)(i + 1)];
        [chapters addObject:chapter];
    }
    view.charpters = chapters;

    RDBookDetailModel *book = [[RDBookDetailModel alloc] init];
    book.bookId = -1;
    book.charpterModel = chapters[current];
    view.book = book;

    [view layoutIfNeeded];
    return view;
}

/// 进度条上的每个控件都必须至少接了一个 action
- (void)testProgressViewControlsAreAllWired
{
    RDReadProgressView *view = [self p_progressViewWithChapters:10 currentIndex:5];
    NSArray<UIControl *> *controls = [self p_controlsIn:view];

    XCTAssertGreaterThanOrEqual(controls.count, 3,
                                @"进度条应至少有滑块 + 左右两个按钮,实际 %lu 个",
                                (unsigned long)controls.count);

    for (UIControl *control in controls) {
        XCTAssertGreaterThan(control.allTargets.count, 0,
                             @"%@ 没有接任何 target —— 又一个只能看不能点的假控件",
                             NSStringFromClass(control.class));
    }
}

/// 左右箭头的点击区域必须达到 HIG 的 44pt
- (void)testArrowButtonsHaveUsableHitArea
{
    RDReadProgressView *view = [self p_progressViewWithChapters:10 currentIndex:5];
    NSArray<UIControl *> *controls = [self p_controlsIn:view];

    NSInteger buttonCount = 0;
    for (UIControl *control in controls) {
        if (![control isKindOfClass:UIButton.class]) {
            continue;
        }
        buttonCount++;
        XCTAssertGreaterThanOrEqual(CGRectGetWidth(control.frame), 44,
                                    @"按钮宽度不足 44pt,手指点不中");
        XCTAssertGreaterThanOrEqual(CGRectGetHeight(control.frame), 44,
                                    @"按钮高度不足 44pt,手指点不中");
    }
    XCTAssertEqual(buttonCount, 2, @"应有左右两个箭头按钮");
}

/// 图标必须按设计尺寸绘制,不能跑成素材原始尺寸(素材是 35pt,直接塞进
/// UIButton 会按原尺寸铺开,箭头会明显偏大)
- (void)testArrowIconsUseDesignSize
{
    RDReadProgressView *view = [self p_progressViewWithChapters:10 currentIndex:5];
    NSInteger checked = 0;
    for (UIControl *control in [self p_controlsIn:view]) {
        if (![control isKindOfClass:UIButton.class]) {
            continue;
        }
        UIImageView *glyph = [(UIButton *)control imageView];
        XCTAssertNotNil(glyph.image, @"箭头图标素材缺失");
        XCTAssertEqualWithAccuracy(CGRectGetWidth(glyph.frame), 24, 0.5,
                                   @"图标宽度应为设计尺寸 24pt,实际 %.1f", CGRectGetWidth(glyph.frame));
        XCTAssertEqualWithAccuracy(CGRectGetHeight(glyph.frame), 24, 0.5,
                                   @"图标高度应为设计尺寸 24pt,实际 %.1f", CGRectGetHeight(glyph.frame));
        // 图标要小于命中区,否则等于没有留出扩大的点击范围
        XCTAssertLessThan(CGRectGetWidth(glyph.frame), CGRectGetWidth(control.frame));
        checked++;
    }
    XCTAssertEqual(checked, 2, @"应检查到左右两个箭头");
}

/// 首章禁用"上一章"、末章禁用"下一章",不能点了没反应还没提示
- (void)testArrowsDisabledAtChapterBounds
{
    NSArray<UIControl *> *(^buttonsOf)(RDReadProgressView *) = ^(RDReadProgressView *v) {
        NSMutableArray *buttons = [NSMutableArray array];
        for (UIControl *c in [self p_controlsIn:v]) {
            if ([c isKindOfClass:UIButton.class]) {
                [buttons addObject:c];
            }
        }
        return buttons;
    };

    RDReadProgressView *first = [self p_progressViewWithChapters:10 currentIndex:0];
    NSArray<UIControl *> *firstButtons = buttonsOf(first);
    XCTAssertEqual(firstButtons.count, 2);
    XCTAssertFalse(firstButtons[0].enabled, @"首章时'上一章'应禁用");
    XCTAssertTrue(firstButtons[1].enabled, @"首章时'下一章'应可用");

    RDReadProgressView *last = [self p_progressViewWithChapters:10 currentIndex:9];
    NSArray<UIControl *> *lastButtons = buttonsOf(last);
    XCTAssertTrue(lastButtons[0].enabled, @"末章时'上一章'应可用");
    XCTAssertFalse(lastButtons[1].enabled, @"末章时'下一章'应禁用");
}

/// 滑块位置换算:末章必须落在最右端(分母是 count-1,不是 count)
- (void)testSliderReachesBothEnds
{
    UISlider *(^sliderOf)(RDReadProgressView *) = ^(RDReadProgressView *v) {
        for (UIControl *c in [self p_controlsIn:v]) {
            if ([c isKindOfClass:UISlider.class]) {
                return (UISlider *)c;
            }
        }
        return (UISlider *)nil;
    };

    UISlider *atFirst = sliderOf([self p_progressViewWithChapters:10 currentIndex:0]);
    XCTAssertNotNil(atFirst);
    XCTAssertEqualWithAccuracy(atFirst.value, 0.0, 0.001, @"首章滑块应在最左端");

    UISlider *atLast = sliderOf([self p_progressViewWithChapters:10 currentIndex:9]);
    XCTAssertEqualWithAccuracy(atLast.value, 1.0, 0.001,
                               @"末章滑块必须到最右端;分母用 count 会永远差一格");
}

@end
