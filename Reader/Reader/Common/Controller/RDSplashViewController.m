//
//  RDSplashViewController.m
//  Reader
//

#import "RDSplashViewController.h"
#import "RDBookshelfPrefetch.h"

@implementation RDSplashViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor whiteColor];

    UIView *brand = [[UIView alloc] init];
    brand.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:brand];

    UIImageView *icon = [[UIImageView alloc] initWithImage:[UIImage imageNamed:@"app_icon_white70"]];
    icon.contentMode = UIViewContentModeScaleAspectFit;
    icon.translatesAutoresizingMaskIntoConstraints = NO;
    [brand addSubview:icon];

    UILabel *title = [[UILabel alloc] init];
    title.text = @"阅小说";
    title.font = [UIFont systemFontOfSize:26 weight:UIFontWeightRegular];
    title.textColor = [UIColor colorWithWhite:0.2 alpha:1];
    title.translatesAutoresizingMaskIntoConstraints = NO;
    [brand addSubview:title];

    UILabel *sub = [[UILabel alloc] init];
    sub.text = @"要看的 在这里";
    sub.font = [UIFont systemFontOfSize:12];
    sub.textColor = [UIColor colorWithWhite:0.4 alpha:1];
    sub.translatesAutoresizingMaskIntoConstraints = NO;
    [brand addSubview:sub];

    UIActivityIndicatorView *spin = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
    spin.translatesAutoresizingMaskIntoConstraints = NO;
    spin.color = [UIColor colorWithWhite:0.45 alpha:1];
    [spin startAnimating];
    [self.view addSubview:spin];

    UILabel *hint = [[UILabel alloc] init];
    hint.text = @"正在加载书架…";
    hint.font = [UIFont systemFontOfSize:13];
    hint.textColor = [UIColor colorWithWhite:0.5 alpha:1];
    hint.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:hint];

    [NSLayoutConstraint activateConstraints:@[
        [brand.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [brand.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor constant:-100],
        [brand.widthAnchor constraintEqualToConstant:200],

        [icon.leadingAnchor constraintEqualToAnchor:brand.leadingAnchor],
        [icon.topAnchor constraintEqualToAnchor:brand.topAnchor],
        [icon.widthAnchor constraintEqualToConstant:65],
        [icon.heightAnchor constraintEqualToConstant:65],
        [icon.bottomAnchor constraintEqualToAnchor:brand.bottomAnchor],

        [title.leadingAnchor constraintEqualToAnchor:icon.trailingAnchor constant:12],
        [title.topAnchor constraintEqualToAnchor:icon.topAnchor constant:6],

        [sub.leadingAnchor constraintEqualToAnchor:title.leadingAnchor],
        [sub.topAnchor constraintEqualToAnchor:title.bottomAnchor constant:4],

        [spin.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [spin.topAnchor constraintEqualToAnchor:brand.bottomAnchor constant:48],

        [hint.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [hint.topAnchor constraintEqualToAnchor:spin.bottomAnchor constant:12],
    ]];
}

- (void)viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];
    // 启动页出现后再跑预加载,用户感知=启动页在干活
    __weak typeof(self) weakSelf = self;
    [RDBookshelfPrefetch runWithComplete:^{
        if (weakSelf.onFinished) {
            weakSelf.onFinished();
        }
    }];
}

- (BOOL)prefersStatusBarHidden
{
    return NO;
}

- (UIStatusBarStyle)preferredStatusBarStyle
{
    return UIStatusBarStyleDarkContent;
}

@end
