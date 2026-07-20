//
//  RDPaperAlert.m
//  Reader
//

#import "RDPaperAlert.h"
#import <objc/runtime.h>

static const NSInteger kRDPaperAlertScrimTag = 0x52445041; // 'RDPA'

@implementation RDPaperAlertAction

+ (instancetype)actionWithTitle:(NSString *)title
                          style:(RDPaperAlertActionStyle)style
                        handler:(void (^)(void))handler
{
    return [self actionWithTitle:title subtitle:nil style:style handler:handler];
}

+ (instancetype)actionWithTitle:(NSString *)title
                       subtitle:(NSString *)subtitle
                          style:(RDPaperAlertActionStyle)style
                        handler:(void (^)(void))handler
{
    RDPaperAlertAction *a = [[RDPaperAlertAction alloc] init];
    a.title = title ?: @"";
    a.subtitle = subtitle;
    a.style = style;
    a.handler = handler;
    return a;
}

@end

#pragma mark -

@interface RDPaperAlert ()
@end

@implementation RDPaperAlert

#pragma mark - Public

+ (void)showConfirmWithTitle:(NSString *)title
                     message:(NSString *)message
                 cancelTitle:(NSString *)cancelTitle
                confirmTitle:(NSString *)confirmTitle
                 destructive:(BOOL)destructive
                     confirm:(void (^)(void))confirm
{
    NSMutableArray *actions = [NSMutableArray array];
    [actions addObject:[RDPaperAlertAction actionWithTitle:cancelTitle ?: @"取消"
                                                     style:RDPaperAlertActionStyleCancel
                                                   handler:nil]];
    [actions addObject:[RDPaperAlertAction actionWithTitle:confirmTitle ?: @"确定"
                                                     style:destructive ? RDPaperAlertActionStyleDestructive : RDPaperAlertActionStylePrimary
                                                   handler:confirm]];
    NSString *symbol = destructive ? @"exclamationmark.triangle" : nil;
    [self showAlertWithTitle:title message:message symbolName:symbol actions:actions];
}

+ (void)showAlertWithTitle:(NSString *)title
                   message:(NSString *)message
                symbolName:(NSString *)symbolName
                   actions:(NSArray<RDPaperAlertAction *> *)actions
{
    if (actions.count == 0) {
        return;
    }
    UIWindow *window = [self p_window];
    if (!window) {
        return;
    }
    [self dismissAnimated:NO completion:nil];

    UIView *scrim = [self p_makeScrimInWindow:window];
    CGFloat cardW = MIN(312, window.bounds.size.width - 48);
    UIView *card = [self p_buildCenterCardWidth:cardW
                                          title:title
                                        message:message
                                     symbolName:symbolName
                                        actions:actions
                                          scrim:scrim];
    [self p_presentCard:card inScrim:scrim window:window fromBottom:NO];
}

+ (void)showActionSheetWithTitle:(NSString *)title
                         message:(NSString *)message
                         actions:(NSArray<RDPaperAlertAction *> *)actions
{
    NSMutableArray <RDPaperAlertAction *>*list = [actions mutableCopy] ?: [NSMutableArray array];
    BOOL hasCancel = NO;
    for (RDPaperAlertAction *a in list) {
        if (a.style == RDPaperAlertActionStyleCancel) {
            hasCancel = YES;
            break;
        }
    }
    if (!hasCancel) {
        [list addObject:[RDPaperAlertAction actionWithTitle:@"取消" style:RDPaperAlertActionStyleCancel handler:nil]];
    }

    UIWindow *window = [self p_window];
    if (!window) {
        return;
    }
    [self dismissAnimated:NO completion:nil];

    UIView *scrim = [self p_makeScrimInWindow:window];
    UIView *sheet = [self p_buildActionSheetWidth:window.bounds.size.width
                                            title:title
                                          message:message
                                          actions:list
                                            scrim:scrim];
    [self p_presentCard:sheet inScrim:scrim window:window fromBottom:YES];
}

+ (void)showTextFieldsWithTitle:(NSString *)title
                        message:(NSString *)message
                     fieldSpecs:(NSArray<NSDictionary *> *)fieldSpecs
                    cancelTitle:(NSString *)cancelTitle
                   confirmTitle:(NSString *)confirmTitle
                        confirm:(void (^)(NSArray<NSString *> *))confirm
{
    UIWindow *window = [self p_window];
    if (!window) {
        return;
    }
    [self dismissAnimated:NO completion:nil];

    UIView *scrim = [self p_makeScrimInWindow:window];
    CGFloat cardW = MIN(320, window.bounds.size.width - 40);
    UIView *card = [self p_buildTextFieldCardWidth:cardW
                                             title:title
                                           message:message
                                        fieldSpecs:fieldSpecs
                                       cancelTitle:cancelTitle
                                      confirmTitle:confirmTitle
                                           confirm:confirm
                                             scrim:scrim];
    [self p_presentCard:card inScrim:scrim window:window fromBottom:NO];
}

+ (void)dismiss
{
    [self dismissAnimated:YES completion:nil];
}

+ (void)dismissAnimated:(BOOL)animated completion:(void (^)(void))completion
{
    UIWindow *window = [self p_window];
    UIView *scrim = [window viewWithTag:kRDPaperAlertScrimTag];
    if (!scrim) {
        if (completion) completion();
        return;
    }
    UIView *panel = scrim.subviews.firstObject;
    void (^finish)(void) = ^{
        [scrim removeFromSuperview];
        if (completion) completion();
    };
    if (!animated) {
        finish();
        return;
    }
    BOOL fromBottom = panel.tag == 2;
    [UIView animateWithDuration:0.2 delay:0 options:UIViewAnimationOptionCurveEaseIn animations:^{
        scrim.alpha = 0;
        if (fromBottom) {
            panel.transform = CGAffineTransformMakeTranslation(0, panel.bounds.size.height + 40);
        } else {
            panel.transform = CGAffineTransformMakeScale(0.94, 0.94);
            panel.alpha = 0;
        }
    } completion:^(BOOL finished) {
        finish();
    }];
}

#pragma mark - Window / scrim

+ (UIWindow *)p_window
{
    return [RDUtilities applicationKeyWindow];
}

+ (UIView *)p_makeScrimInWindow:(UIWindow *)window
{
    UIView *scrim = [[UIView alloc] initWithFrame:window.bounds];
    scrim.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    scrim.backgroundColor = [[UIColor colorWithHexValue:0x2C2620] colorWithAlphaComponent:0.40];
    scrim.tag = kRDPaperAlertScrimTag;
    scrim.alpha = 0;
    scrim.accessibilityViewIsModal = YES;
    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(p_scrimTapped:)];
    // 必须为 NO:否则点操作表行时 scrim 手势也会识别并 cancel 子视图 TouchUpInside,表现为「点了没反应」
    tap.cancelsTouchesInView = NO;
    tap.delaysTouchesBegan = NO;
    tap.delaysTouchesEnded = NO;
    [scrim addGestureRecognizer:tap];
    return scrim;
}

+ (void)p_scrimTapped:(UITapGestureRecognizer *)gr
{
    if (gr.state != UIGestureRecognizerStateEnded) {
        return;
    }
    CGPoint p = [gr locationInView:gr.view];
    UIView *panel = gr.view.subviews.firstObject;
    // 点在底部 sheet / 中心卡内:忽略(由行按钮自己处理)
    if (panel && CGRectContainsPoint(panel.frame, p)) {
        return;
    }
    // 再兜一层:若 hit-test 落在 panel 子树,也不 dismiss
    UIView *hit = [gr.view hitTest:p withEvent:nil];
    if (hit && hit != gr.view && [hit isDescendantOfView:panel]) {
        return;
    }
    [self dismissAnimated:YES completion:nil];
}

+ (void)p_presentCard:(UIView *)panel
              inScrim:(UIView *)scrim
               window:(UIWindow *)window
           fromBottom:(BOOL)fromBottom
{
    panel.tag = fromBottom ? 2 : 1;
    [scrim addSubview:panel];
    [window addSubview:scrim];

    if (fromBottom) {
        CGFloat safeB = window.safeAreaInsets.bottom;
        panel.frame = CGRectMake(0, window.bounds.size.height, panel.bounds.size.width, panel.bounds.size.height);
        // final frame set after layout
        CGFloat h = panel.bounds.size.height;
        CGFloat y = window.bounds.size.height - h;
        panel.frame = CGRectMake(0, window.bounds.size.height, window.bounds.size.width, h);
        panel.autoresizingMask = UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleWidth;
        [UIView animateWithDuration:0.32 delay:0 usingSpringWithDamping:0.88 initialSpringVelocity:0.4 options:0 animations:^{
            scrim.alpha = 1;
            panel.frame = CGRectMake(0, y, window.bounds.size.width, h);
            // re-apply safe area bottom padding already in content
            (void)safeB;
        } completion:nil];
    } else {
        panel.center = CGPointMake(CGRectGetMidX(scrim.bounds), CGRectGetMidY(scrim.bounds));
        panel.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin
            | UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleBottomMargin;
        panel.transform = CGAffineTransformMakeScale(0.92, 0.92);
        panel.alpha = 0;
        [UIView animateWithDuration:0.32 delay:0 usingSpringWithDamping:0.86 initialSpringVelocity:0.4 options:0 animations:^{
            scrim.alpha = 1;
            panel.transform = CGAffineTransformIdentity;
            panel.alpha = 1;
        } completion:nil];
    }
}

+ (void)p_runAction:(RDPaperAlertAction *)action
{
    void (^handler)(void) = [action.handler copy];
    [self dismissAnimated:YES completion:^{
        if (handler) {
            handler();
        }
    }];
}

#pragma mark - Center card

+ (UIView *)p_buildCenterCardWidth:(CGFloat)width
                             title:(NSString *)title
                           message:(NSString *)message
                        symbolName:(NSString *)symbolName
                           actions:(NSArray<RDPaperAlertAction *> *)actions
                             scrim:(UIView *)scrim
{
    UIView *card = [[UIView alloc] init];
    card.backgroundColor = RDSurfaceColor;
    card.layer.cornerRadius = 18;
    card.layer.shadowColor = [UIColor colorWithHexValue:0x2C2620].CGColor;
    card.layer.shadowOpacity = 0.14;
    card.layer.shadowRadius = 22;
    card.layer.shadowOffset = CGSizeMake(0, 10);

    UIView *border = [[UIView alloc] init];
    border.userInteractionEnabled = NO;
    border.layer.cornerRadius = 18;
    border.layer.borderWidth = 1.0 / UIScreen.mainScreen.scale;
    border.layer.borderColor = RDSeparatorColor.CGColor;
    border.translatesAutoresizingMaskIntoConstraints = NO;
    [card addSubview:border];

    NSMutableArray <UIView *>*chain = [NSMutableArray array];
    UIView *last = nil;

    if (symbolName.length > 0) {
        UIView *iconWell = [[UIView alloc] init];
        iconWell.backgroundColor = RDAccentSoftColor;
        iconWell.layer.cornerRadius = 28;
        iconWell.translatesAutoresizingMaskIntoConstraints = NO;
        [card addSubview:iconWell];
        UIImageSymbolConfiguration *cfg = [UIImageSymbolConfiguration configurationWithPointSize:24 weight:UIImageSymbolWeightMedium];
        UIImage *sym = [[UIImage systemImageNamed:symbolName withConfiguration:cfg]
                        imageWithTintColor:RDAccentColor renderingMode:UIImageRenderingModeAlwaysOriginal];
        UIImageView *iv = [[UIImageView alloc] initWithImage:sym];
        iv.translatesAutoresizingMaskIntoConstraints = NO;
        [iconWell addSubview:iv];
        [NSLayoutConstraint activateConstraints:@[
            [iconWell.topAnchor constraintEqualToAnchor:card.topAnchor constant:28],
            [iconWell.centerXAnchor constraintEqualToAnchor:card.centerXAnchor],
            [iconWell.widthAnchor constraintEqualToConstant:56],
            [iconWell.heightAnchor constraintEqualToConstant:56],
            [iv.centerXAnchor constraintEqualToAnchor:iconWell.centerXAnchor],
            [iv.centerYAnchor constraintEqualToAnchor:iconWell.centerYAnchor],
            [iv.widthAnchor constraintEqualToConstant:28],
            [iv.heightAnchor constraintEqualToConstant:28],
        ]];
        last = iconWell;
        [chain addObject:iconWell];
    }

    if (title.length > 0) {
        UILabel *titleLabel = [[UILabel alloc] init];
        titleLabel.text = title;
        titleLabel.font = RDTitleFont19;
        titleLabel.textColor = RDBlackColor;
        titleLabel.textAlignment = NSTextAlignmentCenter;
        titleLabel.numberOfLines = 0;
        titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [card addSubview:titleLabel];
        CGFloat topPad = last ? 18 : 28;
        [NSLayoutConstraint activateConstraints:@[
            [titleLabel.topAnchor constraintEqualToAnchor:(last ? last.bottomAnchor : card.topAnchor) constant:topPad],
            [titleLabel.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:24],
            [titleLabel.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-24],
        ]];
        last = titleLabel;
    }

    if (message.length > 0) {
        UILabel *body = [[UILabel alloc] init];
        NSMutableParagraphStyle *ps = [[NSMutableParagraphStyle alloc] init];
        ps.lineSpacing = 5;
        ps.alignment = NSTextAlignmentCenter;
        body.attributedText = [[NSAttributedString alloc] initWithString:message attributes:@{
            NSFontAttributeName: RDFont14,
            NSForegroundColorAttributeName: RDGrayColor,
            NSParagraphStyleAttributeName: ps,
        }];
        body.numberOfLines = 0;
        body.translatesAutoresizingMaskIntoConstraints = NO;
        [card addSubview:body];
        [NSLayoutConstraint activateConstraints:@[
            [body.topAnchor constraintEqualToAnchor:(last ? last.bottomAnchor : card.topAnchor) constant:last ? 10 : 28],
            [body.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:24],
            [body.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-24],
        ]];
        last = body;
    }

    // 拆分:Primary/Destructive 做成填充主按钮;其余为文字按钮
    NSMutableArray <RDPaperAlertAction *>*primaryLike = [NSMutableArray array];
    NSMutableArray <RDPaperAlertAction *>*secondary = [NSMutableArray array];
    for (RDPaperAlertAction *a in actions) {
        if (a.style == RDPaperAlertActionStylePrimary || a.style == RDPaperAlertActionStyleDestructive) {
            [primaryLike addObject:a];
        } else {
            [secondary addObject:a];
        }
    }
    // 若没有主按钮,把最后一个 default 当主按钮
    if (primaryLike.count == 0 && actions.count > 0) {
        for (NSInteger i = (NSInteger)actions.count - 1; i >= 0; i--) {
            RDPaperAlertAction *a = actions[i];
            if (a.style != RDPaperAlertActionStyleCancel) {
                [primaryLike addObject:a];
                [secondary removeObject:a];
                break;
            }
        }
    }

    UIView *btnAnchor = last;
    CGFloat gap = 24;
    for (RDPaperAlertAction *a in primaryLike) {
        UIButton *btn = [self p_filledButtonForAction:a];
        [card addSubview:btn];
        [NSLayoutConstraint activateConstraints:@[
            [btn.topAnchor constraintEqualToAnchor:(btnAnchor ? btnAnchor.bottomAnchor : card.topAnchor) constant:btnAnchor ? gap : 28],
            [btn.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:24],
            [btn.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-24],
            [btn.heightAnchor constraintEqualToConstant:46],
        ]];
        btnAnchor = btn;
        gap = 10;
    }
    for (RDPaperAlertAction *a in secondary) {
        UIButton *btn = [self p_textButtonForAction:a];
        [card addSubview:btn];
        [NSLayoutConstraint activateConstraints:@[
            [btn.topAnchor constraintEqualToAnchor:(btnAnchor ? btnAnchor.bottomAnchor : card.topAnchor) constant:btnAnchor ? 6 : 28],
            [btn.centerXAnchor constraintEqualToAnchor:card.centerXAnchor],
            [btn.heightAnchor constraintEqualToConstant:40],
            [btn.leadingAnchor constraintGreaterThanOrEqualToAnchor:card.leadingAnchor constant:24],
            [btn.trailingAnchor constraintLessThanOrEqualToAnchor:card.trailingAnchor constant:-24],
        ]];
        btnAnchor = btn;
    }

    [NSLayoutConstraint activateConstraints:@[
        [border.topAnchor constraintEqualToAnchor:card.topAnchor],
        [border.leadingAnchor constraintEqualToAnchor:card.leadingAnchor],
        [border.trailingAnchor constraintEqualToAnchor:card.trailingAnchor],
        [border.bottomAnchor constraintEqualToAnchor:card.bottomAnchor],
        [btnAnchor.bottomAnchor constraintEqualToAnchor:card.bottomAnchor constant:-16],
        [card.widthAnchor constraintEqualToConstant:width],
    ]];

    CGSize fitted = [card systemLayoutSizeFittingSize:CGSizeMake(width, UILayoutFittingCompressedSize.height)
                        withHorizontalFittingPriority:UILayoutPriorityRequired
                              verticalFittingPriority:UILayoutPriorityFittingSizeLevel];
    card.bounds = CGRectMake(0, 0, width, ceil(fitted.height));
    (void)scrim;
    return card;
}

+ (UIButton *)p_filledButtonForAction:(RDPaperAlertAction *)action
{
    UIButton *btn = [UIButton buttonWithType:UIButtonTypeSystem];
    [btn setTitle:action.title forState:UIControlStateNormal];
    [btn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    btn.titleLabel.font = RDBoldFont16;
    btn.layer.cornerRadius = 23;
    btn.translatesAutoresizingMaskIntoConstraints = NO;
    if (action.style == RDPaperAlertActionStyleDestructive) {
        btn.backgroundColor = [UIColor colorWithHexValue:0xC0453A];
    } else {
        btn.backgroundColor = RDAccentColor;
    }
    objc_setAssociatedObject(btn, @selector(p_actionButtonTapped:), action, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [btn addTarget:self action:@selector(p_actionButtonTapped:) forControlEvents:UIControlEventTouchUpInside];
    return btn;
}

+ (UIButton *)p_textButtonForAction:(RDPaperAlertAction *)action
{
    UIButton *btn = [UIButton buttonWithType:UIButtonTypeSystem];
    [btn setTitle:action.title forState:UIControlStateNormal];
    btn.titleLabel.font = RDFont15;
    btn.translatesAutoresizingMaskIntoConstraints = NO;
    UIColor *color = RDLightGrayColor;
    if (action.style == RDPaperAlertActionStyleDestructive) {
        color = [UIColor colorWithHexValue:0xC0453A];
        btn.titleLabel.font = RDBoldFont15;
    } else if (action.style == RDPaperAlertActionStyleDefault) {
        color = RDGrayColor;
    }
    [btn setTitleColor:color forState:UIControlStateNormal];
    objc_setAssociatedObject(btn, @selector(p_actionButtonTapped:), action, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [btn addTarget:self action:@selector(p_actionButtonTapped:) forControlEvents:UIControlEventTouchUpInside];
    return btn;
}

+ (void)p_actionButtonTapped:(UIButton *)sender
{
    RDPaperAlertAction *action = objc_getAssociatedObject(sender, @selector(p_actionButtonTapped:));
    [self p_runAction:action];
}

#pragma mark - Action sheet

+ (UIView *)p_buildActionSheetWidth:(CGFloat)width
                              title:(NSString *)title
                            message:(NSString *)message
                            actions:(NSArray<RDPaperAlertAction *> *)actions
                              scrim:(UIView *)scrim
{
    CGFloat safeB = [self p_window].safeAreaInsets.bottom;
    UIView *sheet = [[UIView alloc] initWithFrame:CGRectMake(0, 0, width, 0)];
    sheet.backgroundColor = RDBackgroudColor;

    CGFloat y = 0;
    CGFloat side = 12;
    CGFloat innerW = width - side * 2;

    // 顶部分组卡:说明区 + 可点行(视觉上与标题分离)
    UIView *card = [[UIView alloc] initWithFrame:CGRectMake(side, 8, innerW, 0)];
    card.backgroundColor = RDSurfaceColor;
    card.layer.cornerRadius = 16;
    card.clipsToBounds = YES;
    [sheet addSubview:card];

    CGFloat cy = 0;
    // 抓手,表明这是面板而非按钮
    {
        UIView *grab = [[UIView alloc] initWithFrame:CGRectMake((innerW - 36) / 2, 8, 36, 4)];
        grab.backgroundColor = RDSeparatorColor;
        grab.layer.cornerRadius = 2;
        [card addSubview:grab];
        cy = 20;
    }

    if (title.length || message.length) {
        // 说明区用纸色底,不可点,与下方操作行区分
        UIView *info = [[UIView alloc] initWithFrame:CGRectMake(12, cy, innerW - 24, 0)];
        info.backgroundColor = RDBackgroudColor;
        info.layer.cornerRadius = 12;
        info.userInteractionEnabled = NO;
        CGFloat iy = 12;
        if (title.length) {
            UILabel *tl = [[UILabel alloc] initWithFrame:CGRectMake(14, iy, innerW - 52, 0)];
            tl.text = title;
            tl.font = RDTitleFont17;
            tl.textColor = RDBlackColor;
            tl.textAlignment = NSTextAlignmentLeft;
            tl.numberOfLines = 0;
            CGSize sz = [tl sizeThatFits:CGSizeMake(innerW - 52, CGFLOAT_MAX)];
            tl.frame = CGRectMake(14, iy, innerW - 52, ceil(sz.height));
            [info addSubview:tl];
            iy = CGRectGetMaxY(tl.frame) + 6;
        }
        if (message.length) {
            UILabel *ml = [[UILabel alloc] initWithFrame:CGRectMake(14, iy, innerW - 52, 0)];
            ml.text = message;
            ml.font = RDFont13;
            ml.textColor = RDGrayColor;
            ml.textAlignment = NSTextAlignmentLeft;
            ml.numberOfLines = 0;
            CGSize sz = [ml sizeThatFits:CGSizeMake(innerW - 52, CGFLOAT_MAX)];
            ml.frame = CGRectMake(14, iy, innerW - 52, ceil(sz.height));
            [info addSubview:ml];
            iy = CGRectGetMaxY(ml.frame) + 12;
        } else {
            iy += 6;
        }
        info.frame = CGRectMake(12, cy, innerW - 24, iy);
        [card addSubview:info];
        cy = CGRectGetMaxY(info.frame) + 8;
    }

    NSMutableArray <RDPaperAlertAction *>*rows = [NSMutableArray array];
    RDPaperAlertAction *cancelAction = nil;
    for (RDPaperAlertAction *a in actions) {
        if (a.style == RDPaperAlertActionStyleCancel) {
            cancelAction = a;
        } else {
            [rows addObject:a];
        }
    }

    for (NSInteger i = 0; i < (NSInteger)rows.count; i++) {
        RDPaperAlertAction *a = rows[i];
        BOOL hasSub = a.subtitle.length > 0;
        CGFloat rowH = hasSub ? 68 : 54;
        UIControl *row = [[UIControl alloc] initWithFrame:CGRectMake(0, cy, innerW, rowH)];
        row.backgroundColor = RDSurfaceColor;
        row.isAccessibilityElement = YES;
        row.accessibilityLabel = a.title;
        row.accessibilityTraits = UIAccessibilityTraitButton;
        row.exclusiveTouch = YES;
        objc_setAssociatedObject(row, @selector(p_actionButtonTapped:), a, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [row addTarget:self action:@selector(p_actionRowTapped:) forControlEvents:UIControlEventTouchUpInside];
        [row addTarget:self action:@selector(p_actionRowHighlight:) forControlEvents:UIControlEventTouchDown | UIControlEventTouchDragEnter];
        [row addTarget:self action:@selector(p_actionRowUnhighlight:) forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside | UIControlEventTouchCancel | UIControlEventTouchDragExit];

        UILabel *titleL = [[UILabel alloc] init];
        titleL.text = a.title;
        titleL.font = RDBoldFont16;
        titleL.textColor = (a.style == RDPaperAlertActionStyleDestructive)
            ? [UIColor colorWithHexValue:0xC0453A] : RDBlackColor;
        titleL.userInteractionEnabled = NO;
        if (hasSub) {
            titleL.frame = CGRectMake(18, 12, innerW - 52, 22);
        } else {
            titleL.frame = CGRectMake(18, 0, innerW - 52, rowH);
        }
        [row addSubview:titleL];

        if (hasSub) {
            UILabel *subL = [[UILabel alloc] initWithFrame:CGRectMake(18, 36, innerW - 52, 20)];
            subL.text = a.subtitle;
            subL.font = RDFont12;
            subL.textColor = RDLightGrayColor;
            subL.userInteractionEnabled = NO;
            [row addSubview:subL];
        }

        // 右侧 chevron 表示点选后进入下一步
        UIImageSymbolConfiguration *cfg = [UIImageSymbolConfiguration configurationWithPointSize:13 weight:UIImageSymbolWeightSemibold];
        UIImage *chev = [[UIImage systemImageNamed:@"chevron.right" withConfiguration:cfg]
                         imageWithTintColor:RDPlaceholderColor renderingMode:UIImageRenderingModeAlwaysOriginal];
        UIImageView *iv = [[UIImageView alloc] initWithImage:chev];
        iv.frame = CGRectMake(innerW - 28, (rowH - 14) / 2, 10, 14);
        iv.userInteractionEnabled = NO;
        [row addSubview:iv];

        [card addSubview:row];
        cy = CGRectGetMaxY(row.frame);
        if (i < (NSInteger)rows.count - 1) {
            UIView *sep = [[UIView alloc] initWithFrame:CGRectMake(18, cy, innerW - 36, 1.0 / UIScreen.mainScreen.scale)];
            sep.backgroundColor = RDLightSeparatorColor;
            [card addSubview:sep];
        }
    }
    cy += 8;
    card.frame = CGRectMake(side, 8, innerW, cy);
    y = CGRectGetMaxY(card.frame);

    CGFloat sheetH = y;
    if (cancelAction) {
        UIButton *cancel = [UIButton buttonWithType:UIButtonTypeSystem];
        cancel.frame = CGRectMake(side, y + 8, innerW, 50);
        cancel.backgroundColor = RDSurfaceColor;
        cancel.layer.cornerRadius = 14;
        [cancel setTitle:cancelAction.title.length ? cancelAction.title : @"取消" forState:UIControlStateNormal];
        [cancel setTitleColor:RDGrayColor forState:UIControlStateNormal];
        cancel.titleLabel.font = RDBoldFont16;
        objc_setAssociatedObject(cancel, @selector(p_actionButtonTapped:), cancelAction, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [cancel addTarget:self action:@selector(p_actionButtonTapped:) forControlEvents:UIControlEventTouchUpInside];
        [sheet addSubview:cancel];
        sheetH = CGRectGetMaxY(cancel.frame) + 10 + safeB;
    } else {
        sheetH = y + 10 + safeB;
    }

    sheet.frame = CGRectMake(0, 0, width, sheetH);
    (void)scrim;
    return sheet;
}

+ (void)p_actionRowTapped:(UIControl *)sender
{
    RDPaperAlertAction *action = objc_getAssociatedObject(sender, @selector(p_actionButtonTapped:));
    [self p_runAction:action];
}

+ (void)p_actionRowHighlight:(UIControl *)sender
{
    sender.backgroundColor = RDAccentSoftColor;
}

+ (void)p_actionRowUnhighlight:(UIControl *)sender
{
    sender.backgroundColor = RDSurfaceColor;
}

#pragma mark - Text fields

+ (UIView *)p_buildTextFieldCardWidth:(CGFloat)width
                                title:(NSString *)title
                              message:(NSString *)message
                           fieldSpecs:(NSArray<NSDictionary *> *)fieldSpecs
                          cancelTitle:(NSString *)cancelTitle
                         confirmTitle:(NSString *)confirmTitle
                              confirm:(void (^)(NSArray<NSString *> *))confirm
                                scrim:(UIView *)scrim
{
    UIView *card = [[UIView alloc] init];
    card.backgroundColor = RDSurfaceColor;
    card.layer.cornerRadius = 18;
    card.layer.shadowColor = [UIColor colorWithHexValue:0x2C2620].CGColor;
    card.layer.shadowOpacity = 0.14;
    card.layer.shadowRadius = 22;
    card.layer.shadowOffset = CGSizeMake(0, 10);
    card.translatesAutoresizingMaskIntoConstraints = NO;

    UILabel *titleLabel = [[UILabel alloc] init];
    titleLabel.text = title;
    titleLabel.font = RDTitleFont19;
    titleLabel.textColor = RDBlackColor;
    titleLabel.textAlignment = NSTextAlignmentCenter;
    titleLabel.numberOfLines = 0;
    titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [card addSubview:titleLabel];

    UIView *last = titleLabel;
    [NSLayoutConstraint activateConstraints:@[
        [titleLabel.topAnchor constraintEqualToAnchor:card.topAnchor constant:24],
        [titleLabel.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:20],
        [titleLabel.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-20],
    ]];

    if (message.length) {
        UILabel *msg = [[UILabel alloc] init];
        msg.text = message;
        msg.font = RDFont13;
        msg.textColor = RDLightGrayColor;
        msg.textAlignment = NSTextAlignmentCenter;
        msg.numberOfLines = 0;
        msg.translatesAutoresizingMaskIntoConstraints = NO;
        [card addSubview:msg];
        [NSLayoutConstraint activateConstraints:@[
            [msg.topAnchor constraintEqualToAnchor:titleLabel.bottomAnchor constant:8],
            [msg.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:20],
            [msg.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-20],
        ]];
        last = msg;
    }

    NSMutableArray <UITextField *>*fields = [NSMutableArray array];
    for (NSDictionary *spec in fieldSpecs) {
        UITextField *tf = [[UITextField alloc] init];
        tf.placeholder = spec[@"placeholder"] ?: @"";
        tf.text = spec[@"text"] ?: @"";
        tf.secureTextEntry = [spec[@"secure"] boolValue];
        tf.borderStyle = UITextBorderStyleNone;
        tf.backgroundColor = RDBackgroudColor;
        tf.layer.cornerRadius = 10;
        tf.font = RDFont16;
        tf.textColor = RDBlackColor;
        tf.clearButtonMode = UITextFieldViewModeWhileEditing;
        tf.autocapitalizationType = UITextAutocapitalizationTypeNone;
        tf.leftView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 12, 1)];
        tf.leftViewMode = UITextFieldViewModeAlways;
        tf.rightView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 12, 1)];
        tf.rightViewMode = UITextFieldViewModeAlways;
        tf.translatesAutoresizingMaskIntoConstraints = NO;
        [card addSubview:tf];
        [NSLayoutConstraint activateConstraints:@[
            [tf.topAnchor constraintEqualToAnchor:last.bottomAnchor constant:12],
            [tf.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:20],
            [tf.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-20],
            [tf.heightAnchor constraintEqualToConstant:44],
        ]];
        last = tf;
        [fields addObject:tf];
    }

    UIButton *confirmBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    [confirmBtn setTitle:confirmTitle ?: @"确定" forState:UIControlStateNormal];
    [confirmBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    confirmBtn.titleLabel.font = RDBoldFont16;
    confirmBtn.backgroundColor = RDAccentColor;
    confirmBtn.layer.cornerRadius = 23;
    confirmBtn.translatesAutoresizingMaskIntoConstraints = NO;
    [card addSubview:confirmBtn];

    UIButton *cancelBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    [cancelBtn setTitle:cancelTitle ?: @"取消" forState:UIControlStateNormal];
    [cancelBtn setTitleColor:RDLightGrayColor forState:UIControlStateNormal];
    cancelBtn.titleLabel.font = RDFont15;
    cancelBtn.translatesAutoresizingMaskIntoConstraints = NO;
    [card addSubview:cancelBtn];

    [NSLayoutConstraint activateConstraints:@[
        [confirmBtn.topAnchor constraintEqualToAnchor:last.bottomAnchor constant:20],
        [confirmBtn.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:20],
        [confirmBtn.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-20],
        [confirmBtn.heightAnchor constraintEqualToConstant:46],
        [cancelBtn.topAnchor constraintEqualToAnchor:confirmBtn.bottomAnchor constant:6],
        [cancelBtn.centerXAnchor constraintEqualToAnchor:card.centerXAnchor],
        [cancelBtn.heightAnchor constraintEqualToConstant:40],
        [cancelBtn.bottomAnchor constraintEqualToAnchor:card.bottomAnchor constant:-14],
        [card.widthAnchor constraintEqualToConstant:width],
    ]];

    [cancelBtn addTarget:self action:@selector(p_textCancel) forControlEvents:UIControlEventTouchUpInside];

    // store fields + confirm on button
    objc_setAssociatedObject(confirmBtn, @selector(p_textConfirm:), fields, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    if (confirm) {
        objc_setAssociatedObject(confirmBtn, "rd_paper_confirm_block", [confirm copy], OBJC_ASSOCIATION_COPY_NONATOMIC);
    }
    [confirmBtn addTarget:self action:@selector(p_textConfirm:) forControlEvents:UIControlEventTouchUpInside];

    // layout size
    // force layout
    [card setNeedsLayout];
    [card layoutIfNeeded];
    CGSize fitted = [card systemLayoutSizeFittingSize:CGSizeMake(width, UILayoutFittingCompressedSize.height)
                        withHorizontalFittingPriority:UILayoutPriorityRequired
                              verticalFittingPriority:UILayoutPriorityFittingSizeLevel];
    // card uses constraints with width; for frame-based present need bounds
    UIView *wrap = [[UIView alloc] initWithFrame:CGRectMake(0, 0, width, ceil(fitted.height))];
    wrap.backgroundColor = [UIColor clearColor];
    card.translatesAutoresizingMaskIntoConstraints = YES;
    card.frame = wrap.bounds;
    card.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [wrap addSubview:card];
    // re-enable auto layout inside by using frame only on wrap
    // Actually simpler: use frame layout for whole card without wrap complexity
    // Rebuild with frames for text form to avoid AL issues...
    // Current AL on card as subview of wrap with fixed frame works if card fills wrap.
    card.frame = wrap.bounds;
    // Fix: card still has constraints needing superview width - activate left/right to wrap
    card.translatesAutoresizingMaskIntoConstraints = NO;
    [NSLayoutConstraint activateConstraints:@[
        [card.topAnchor constraintEqualToAnchor:wrap.topAnchor],
        [card.leadingAnchor constraintEqualToAnchor:wrap.leadingAnchor],
        [card.trailingAnchor constraintEqualToAnchor:wrap.trailingAnchor],
        [card.bottomAnchor constraintEqualToAnchor:wrap.bottomAnchor],
    ]];
    wrap.bounds = CGRectMake(0, 0, width, ceil(fitted.height));
    (void)scrim;
    return wrap;
}

+ (void)p_textCancel
{
    [self dismissAnimated:YES completion:nil];
}

+ (void)p_textConfirm:(UIButton *)sender
{
    NSArray <UITextField *>*fields = objc_getAssociatedObject(sender, @selector(p_textConfirm:));
    void (^block)(NSArray *) = objc_getAssociatedObject(sender, "rd_paper_confirm_block");
    NSMutableArray *values = [NSMutableArray array];
    for (UITextField *tf in fields) {
        [values addObject:tf.text ?: @""];
    }
    [self dismissAnimated:YES completion:^{
        if (block) {
            block(values);
        }
    }];
}

@end
