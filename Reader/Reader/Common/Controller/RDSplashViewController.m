//
//  RDSplashViewController.m
//  Reader
//
//  布局必须与 LaunchScreen.storyboard 完全一致,避免系统启动图切到本页时「跳一下」
//

#import "RDSplashViewController.h"
#import "RDBookshelfPrefetch.h"

static NSString * const kAppDisplayName = @"轻阅";
static NSString * const kAppTagline = @"要看的 在这里";

@implementation RDSplashViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
    // 与 LaunchScreen 同色,无安全区偏移
    self.view.backgroundColor = [UIColor whiteColor];
    self.view.overrideUserInterfaceStyle = UIUserInterfaceStyleLight;

    // —— 品牌区:宽 167 高 70,相对屏幕中心上移 100pt(与 storyboard 一致) ——
    UIView *brand = [[UIView alloc] init];
    brand.translatesAutoresizingMaskIntoConstraints = NO;
    brand.backgroundColor = [UIColor whiteColor];
    [self.view addSubview:brand];

    UIImageView *icon = [[UIImageView alloc] initWithImage:[UIImage imageNamed:@"app_icon_white70"]];
    icon.contentMode = UIViewContentModeScaleAspectFit;
    icon.translatesAutoresizingMaskIntoConstraints = NO;
    [brand addSubview:icon];

    UILabel *title = [[UILabel alloc] init];
    title.text = kAppDisplayName;
    title.font = [UIFont systemFontOfSize:26 weight:UIFontWeightRegular];
    title.textColor = [UIColor colorWithRed:0.2 green:0.2 blue:0.2 alpha:1];
    title.translatesAutoresizingMaskIntoConstraints = NO;
    [brand addSubview:title];

    UILabel *sub = [[UILabel alloc] init];
    sub.text = kAppTagline;
    sub.font = [UIFont systemFontOfSize:12 weight:UIFontWeightRegular];
    sub.textColor = [UIColor colorWithRed:0.4 green:0.4 blue:0.4 alpha:1];
    sub.translatesAutoresizingMaskIntoConstraints = NO;
    [brand addSubview:sub];

    // 加载提示叠在下方,不改 brand 位置,避免与系统启动图错位
    UIActivityIndicatorView *spin = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
    spin.translatesAutoresizingMaskIntoConstraints = NO;
    spin.color = [UIColor colorWithWhite:0.55 alpha:1];
    spin.alpha = 0;
    [spin startAnimating];
    [self.view addSubview:spin];

    UILabel *hint = [[UILabel alloc] init];
    hint.text = @"正在加载书架…";
    hint.font = [UIFont systemFontOfSize:13];
    hint.textColor = [UIColor colorWithWhite:0.55 alpha:1];
    hint.translatesAutoresizingMaskIntoConstraints = NO;
    hint.alpha = 0;
    [self.view addSubview:hint];

    [NSLayoutConstraint activateConstraints:@[
        // brand 与 LaunchScreen: centerX / centerY-100 / 167×70
        [brand.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [brand.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor constant:-100],
        [brand.widthAnchor constraintEqualToConstant:167],
        [brand.heightAnchor constraintEqualToConstant:70],

        // icon: 约 (4,3) 65×65 — storyboard fixedFrame
        [icon.leadingAnchor constraintEqualToAnchor:brand.leadingAnchor constant:4],
        [icon.topAnchor constraintEqualToAnchor:brand.topAnchor constant:3],
        [icon.widthAnchor constraintEqualToConstant:65],
        [icon.heightAnchor constraintEqualToConstant:65],

        // title: 约 (84,7)
        [title.leadingAnchor constraintEqualToAnchor:brand.leadingAnchor constant:84],
        [title.topAnchor constraintEqualToAnchor:brand.topAnchor constant:7],

        // sub: 约 (85,42)
        [sub.leadingAnchor constraintEqualToAnchor:brand.leadingAnchor constant:85],
        [sub.topAnchor constraintEqualToAnchor:brand.topAnchor constant:42],

        // 加载区:在 brand 下方居中,淡入不位移 brand
        [spin.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [spin.topAnchor constraintEqualToAnchor:brand.bottomAnchor constant:40],
        [hint.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [hint.topAnchor constraintEqualToAnchor:spin.bottomAnchor constant:10],
    ]];

    // 稍后再显示 spinner,首帧尽量与系统启动图重合
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.12 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [UIView animateWithDuration:0.25 animations:^{
            spin.alpha = 1;
            hint.alpha = 1;
        }];
    });
}

- (void)viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];
    static BOOL started = NO;
    if (started) {
        return;
    }
    started = YES;
    __weak typeof(self) weakSelf = self;
    [RDBookshelfPrefetch runWithComplete:^{
        if (weakSelf.onFinished) {
            weakSelf.onFinished();
        }
    }];
}

- (BOOL)prefersStatusBarHidden
{
    // 与系统 LaunchScreen 一致,减少状态栏高度造成的视觉偏移
    return YES;
}

- (UIStatusBarStyle)preferredStatusBarStyle
{
    return UIStatusBarStyleDarkContent;
}

@end
