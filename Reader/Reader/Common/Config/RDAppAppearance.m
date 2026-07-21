//
//  RDAppAppearance.m
//  Reader
//

#import "RDAppAppearance.h"
#import "RDReadConfigManager.h"

NSString * const RDAppAppearanceDidChangeNotification = @"RDAppAppearanceDidChangeNotification";

static NSString * const kRDAppDarkModeEnabledKey = @"RDAppDarkModeEnabled";

@interface RDAppAppearance ()
@property (nonatomic, assign) BOOL lastAppliedDark;
@property (nonatomic, assign) BOOL hasAppliedOnce;
@end

@implementation RDAppAppearance

+ (instancetype)sharedInstance
{
    static RDAppAppearance *inst;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        inst = [[RDAppAppearance alloc] init];
    });
    return inst;
}

- (instancetype)init
{
    self = [super init];
    if (self) {
        _darkModeEnabled = [[NSUserDefaults standardUserDefaults] boolForKey:kRDAppDarkModeEnabledKey];
        _lastAppliedDark = NO;
        _hasAppliedOnce = NO;
        // 阅读夜读主题变化时,外层也要跟着黑
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(p_themeOrPreferenceChanged)
                                                     name:RDReadThemeDidChangeNotification
                                                   object:nil];
    }
    return self;
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)setDarkModeEnabled:(BOOL)darkModeEnabled
{
    if (_darkModeEnabled == darkModeEnabled) {
        return;
    }
    _darkModeEnabled = darkModeEnabled;
    [[NSUserDefaults standardUserDefaults] setBool:darkModeEnabled forKey:kRDAppDarkModeEnabledKey];
    [self p_themeOrPreferenceChanged];
}

- (BOOL)isEffectiveDark
{
    // 设置开关 OR 阅读页夜读 → 全局深色
    if (self.darkModeEnabled) {
        return YES;
    }
    return [RDReadConfigManager sharedInstance].isDarkTheme;
}

- (void)bootstrap
{
    [self applyToWindows];
}

- (void)p_themeOrPreferenceChanged
{
    [self applyToWindows];
}

- (void)applyToWindows
{
    BOOL dark = [self isEffectiveDark];
    UIUserInterfaceStyle style = dark ? UIUserInterfaceStyleDark : UIUserInterfaceStyleLight;

    // 遍历所有 scene window
    NSArray<UIScene *> *scenes = UIApplication.sharedApplication.connectedScenes.allObjects;
    for (UIScene *scene in scenes) {
        if (![scene isKindOfClass:UIWindowScene.class]) {
            continue;
        }
        for (UIWindow *window in ((UIWindowScene *)scene).windows) {
            // 启动页强制浅色,不在此覆盖
            if ([window.rootViewController isKindOfClass:NSClassFromString(@"RDSplashViewController")]) {
                continue;
            }
            if (window.overrideUserInterfaceStyle != style) {
                window.overrideUserInterfaceStyle = style;
            }
            // 窗口底色随令牌
            window.backgroundColor = RDBackgroudColor;
        }
    }
    // 兼容 AppDelegate.window 指针
    UIWindow *key = [RDUtilities applicationKeyWindow];
    if (key && key.overrideUserInterfaceStyle != style
        && ![key.rootViewController isKindOfClass:NSClassFromString(@"RDSplashViewController")]) {
        key.overrideUserInterfaceStyle = style;
        key.backgroundColor = RDBackgroudColor;
    }

    // 首次应用也要通知(启动时主题归档可能已是夜读,但主界面尚未创建)
    BOOL changed = !self.hasAppliedOnce || (self.lastAppliedDark != dark);
    self.hasAppliedOnce = YES;
    self.lastAppliedDark = dark;
    if (changed) {
        [[NSNotificationCenter defaultCenter] postNotificationName:RDAppAppearanceDidChangeNotification object:self];
    }
}

@end
