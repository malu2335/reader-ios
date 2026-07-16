//
//  RDFontManager.m
//  Reader
//

#import "RDFontManager.h"
#import <CoreText/CoreText.h>

NSString * const RDFontListChangedNotification = @"RDFontListChangedNotification";

static NSString * const kFontsDirName = @"Fonts";

@implementation RDFontOption
@end

@interface RDFontManager ()
@property (nonatomic,strong) NSMutableArray <RDFontOption *>*customOptions;
@end

@implementation RDFontManager

IMP_SINGLETON(RDFontManager)

- (NSMutableArray<RDFontOption *> *)customOptions
{
    if (!_customOptions) {
        _customOptions = [NSMutableArray array];
    }
    return _customOptions;
}

+ (NSString *)fontsDirectory
{
    NSString *dir = [PATH_DOCUMENT stringByAppendingPathComponent:kFontsDirName];
    if (![[NSFileManager defaultManager] fileExistsAtPath:dir]) {
        [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
    }
    return dir;
}

#pragma mark - 字体列表

- (NSArray <RDFontOption *>*)allOptions
{
    NSMutableArray *options = [NSMutableArray array];

    RDFontOption *system = [[RDFontOption alloc] init];
    system.displayName = @"系统";
    system.fontName = nil;
    [options addObject:system];

    //内置中文字体:每项给出候选 PostScript 名,取设备上第一个可用的
    NSDictionary *builtIns = @{
        @"宋体": @[@"STSongti-SC-Regular", @"Songti SC"],
        @"楷体": @[@"STKaitiSC-Regular", @"KaitiSC-Regular", @"STKaiti"],
        @"圆体": @[@"YuantiSC-Regular", @"Yuanti SC"],
    };
    for (NSString *display in @[@"宋体", @"楷体", @"圆体"]) {
        for (NSString *candidate in builtIns[display]) {
            if ([UIFont fontWithName:candidate size:12]) {
                RDFontOption *option = [[RDFontOption alloc] init];
                option.displayName = display;
                option.fontName = candidate;
                [options addObject:option];
                break;
            }
        }
    }

    [options addObjectsFromArray:self.customOptions];
    return options.copy;
}

#pragma mark - 注册与导入

- (void)registerCustomFontsAtLaunch
{
    [self.customOptions removeAllObjects];
    NSString *dir = [RDFontManager fontsDirectory];
    NSArray *files = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:dir error:nil];
    for (NSString *file in files) {
        NSString *ext = file.pathExtension.lowercaseString;
        if (![@[@"ttf", @"otf", @"ttc"] containsObject:ext]) {
            continue;
        }
        RDFontOption *option = [self registerFontFileAtPath:[dir stringByAppendingPathComponent:file]];
        if (option) {
            [self.customOptions addObject:option];
        }
    }
}

//注册单个字体文件并返回选项(已注册过也能取到名字)
- (RDFontOption *)registerFontFileAtPath:(NSString *)path
{
    NSURL *url = [NSURL fileURLWithPath:path];
    CTFontManagerRegisterFontsForURL((__bridge CFURLRef)url, kCTFontManagerScopeProcess, NULL);

    NSArray *descriptors = (__bridge_transfer NSArray *)CTFontManagerCreateFontDescriptorsFromURL((__bridge CFURLRef)url);
    if (descriptors.count == 0) {
        return nil;
    }
    CTFontDescriptorRef descriptor = (__bridge CTFontDescriptorRef)descriptors.firstObject;
    NSString *postScript = (__bridge_transfer NSString *)CTFontDescriptorCopyAttribute(descriptor, kCTFontNameAttribute);
    NSString *display = (__bridge_transfer NSString *)CTFontDescriptorCopyAttribute(descriptor, kCTFontDisplayNameAttribute);
    if (postScript.length == 0) {
        return nil;
    }
    RDFontOption *option = [[RDFontOption alloc] init];
    option.fontName = postScript;
    option.displayName = display.length > 0 ? display : postScript;
    option.custom = YES;
    return option;
}

- (void)importFontAtURL:(NSURL *)url complete:(void(^)(RDFontOption * _Nullable, NSString * _Nullable))complete
{
    void (^finish)(RDFontOption *, NSString *) = ^(RDFontOption *option, NSString *message) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (option) {
                [[NSNotificationCenter defaultCenter] postNotificationName:RDFontListChangedNotification object:option];
            }
            if (complete) {
                complete(option, message);
            }
        });
    };

    NSString *ext = url.pathExtension.lowercaseString;
    if (![@[@"ttf", @"otf", @"ttc"] containsObject:ext]) {
        finish(nil, @"仅支持 ttf / otf 字体文件");
        return;
    }
    BOOL scoped = [url startAccessingSecurityScopedResource];
    NSData *data = [NSData dataWithContentsOfURL:url];
    if (scoped) {
        [url stopAccessingSecurityScopedResource];
    }
    if (data.length == 0) {
        finish(nil, @"字体文件无法读取");
        return;
    }
    NSString *path = [[RDFontManager fontsDirectory] stringByAppendingPathComponent:url.lastPathComponent];
    if (![data writeToFile:path atomically:YES]) {
        finish(nil, @"保存字体失败");
        return;
    }
    RDFontOption *option = [self registerFontFileAtPath:path];
    if (!option || ![UIFont fontWithName:option.fontName size:12]) {
        [[NSFileManager defaultManager] removeItemAtPath:path error:nil];
        finish(nil, @"无法识别该字体文件");
        return;
    }
    //去重:同名字体覆盖旧选项
    for (RDFontOption *exist in self.customOptions.copy) {
        if ([exist.fontName isEqualToString:option.fontName]) {
            [self.customOptions removeObject:exist];
        }
    }
    [self.customOptions addObject:option];
    finish(option, nil);
}

- (void)removeCustomFont:(RDFontOption *)option
{
    if (!option.custom) {
        return;
    }
    [self.customOptions removeObject:option];
    //删除对应文件(按注册出的 PostScript 名反查)
    NSString *dir = [RDFontManager fontsDirectory];
    NSArray *files = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:dir error:nil];
    for (NSString *file in files) {
        NSString *path = [dir stringByAppendingPathComponent:file];
        NSArray *descriptors = (__bridge_transfer NSArray *)CTFontManagerCreateFontDescriptorsFromURL((__bridge CFURLRef)[NSURL fileURLWithPath:path]);
        if (descriptors.count == 0) {
            continue;
        }
        NSString *name = (__bridge_transfer NSString *)CTFontDescriptorCopyAttribute((__bridge CTFontDescriptorRef)descriptors.firstObject, kCTFontNameAttribute);
        if ([name isEqualToString:option.fontName]) {
            [[NSFileManager defaultManager] removeItemAtPath:path error:nil];
        }
    }
    [[NSNotificationCenter defaultCenter] postNotificationName:RDFontListChangedNotification object:nil];
}

+ (UIFont *)readFontWithName:(NSString *)fontName size:(CGFloat)size
{
    if (fontName.length > 0) {
        UIFont *font = [UIFont fontWithName:fontName size:size];
        if (font) {
            return font;
        }
    }
    return [UIFont systemFontOfSize:size];
}

@end
