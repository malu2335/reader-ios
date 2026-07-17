//
//  RDBackupManager.m
//  Reader
//

#import "RDBackupManager.h"
#import "RDZipArchive.h"
#import "RDLocalBookManager.h"
#import "RDBookDetailModel.h"
#import "RDCharpterModel.h"
#import "RDReadRecordManager.h"
#import "RDReadConfigManager.h"
#import "RDAIConfig.h"
#import "RDBookmarkManager.h"
#import "RDBookmarkModel.h"
#import "RDReplaceRule.h"
#import "RDFontManager.h"

//与 legado 一致的清单文件名
static NSString * const kBackupBookshelfEntry = @"bookshelf.json";
static NSString * const kBackupConfigEntry = @"config.json";
static NSString * const kBackupBookmarksEntry = @"bookmarks.json";
static NSString * const kBackupReplaceRulesEntry = @"replace_rules.json";
static NSString * const kBackupBooksDir = @"books";
static NSString * const kBackupFontsDir = @"fonts";

@implementation RDBackupManager

+ (NSString *)aiConfigEntryName
{
    return RDAIConfigBackupEntryName;
}

+ (NSData *)aiConfigBackupData
{
    return [[RDAIConfigStore sharedInstance] exportBackupData];
}

+ (BOOL)restoreAIConfigFromData:(NSData *)data error:(NSError **)error
{
    if (data.length == 0) {
        return YES; // 旧备份无 AI 配置,视为成功跳过
    }
    return [[RDAIConfigStore sharedInstance] importBackupData:data error:error];
}

+ (BOOL)writeAIConfigToZipWriter:(id)writer
{
    if (![writer isKindOfClass:RDZipWriter.class]) {
        return NO;
    }
    RDZipWriter *zipWriter = (RDZipWriter *)writer;
    NSData *aiData = [self aiConfigBackupData];
    if (aiData.length == 0) {
        // 保证条目存在,便于恢复路径稳定
        aiData = [@"{\"version\":1,\"activeProfileId\":\"\",\"profiles\":[]}" dataUsingEncoding:NSUTF8StringEncoding];
    }
    return [zipWriter addEntryWithName:[self aiConfigEntryName] data:aiData];
}

+ (void)restoreAIConfigFromZip:(id)zip
{
    if (![zip isKindOfClass:RDZipArchive.class]) {
        return;
    }
    RDZipArchive *archive = (RDZipArchive *)zip;
    NSData *aiData = [archive dataForEntry:[self aiConfigEntryName]];
    if (aiData.length > 0) {
        [[RDAIConfigStore sharedInstance] importBackupData:aiData error:nil];
    }
}

#pragma mark - 备份

+ (void)createBackupWithComplete:(void(^)(NSString * _Nullable, NSString * _Nullable))complete
{
    void (^finish)(NSString *, NSString *) = ^(NSString *path, NSString *message) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (complete) {
                complete(path, message);
            }
        });
    };
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSArray <RDBookDetailModel *>*books = [RDReadRecordManager getAllOnBookshelf];
        NSMutableArray *localBooks = [NSMutableArray array];
        for (RDBookDetailModel *book in books) {
            if (book.isLocalBook) {
                [localBooks addObject:book];
            }
        }
        BOOL hasAI = [RDAIConfigStore sharedInstance].profiles.count > 0;
        // 允许仅备份 AI/阅读配置(无本地书时)
        if (localBooks.count == 0 && !hasAI) {
            finish(nil, @"书架上还没有本地书籍,也没有 AI 配置可备份");
            return;
        }

        // 写到 Caches/Exports,比 tmp 更适合 UIActivity 分享,减少 share mode / file provider 报错
        NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
        formatter.dateFormat = @"yyyy-MM-dd";
        NSString *zipName = [NSString stringWithFormat:@"backup%@.zip", [formatter stringFromDate:[NSDate date]]];
        NSString *exportDir = [PATH_CACHES stringByAppendingPathComponent:@"Exports"];
        [[NSFileManager defaultManager] createDirectoryAtPath:exportDir withIntermediateDirectories:YES attributes:nil error:nil];
        NSString *zipPath = [exportDir stringByAppendingPathComponent:zipName];
        [[NSFileManager defaultManager] removeItemAtPath:zipPath error:nil];

        RDZipWriter *writer = [[RDZipWriter alloc] initWithPath:zipPath];
        if (!writer) {
            finish(nil, @"创建备份文件失败");
            return;
        }

        //bookshelf.json
        NSMutableArray *shelf = [NSMutableArray array];
        for (RDBookDetailModel *book in localBooks) {
            [shelf addObject:@{
                @"bookId": @(book.bookId),
                @"name": book.title ?: @"",
                @"author": book.author ?: @"",
                @"fileType": book.fileType ?: @"",
                @"localPath": book.localPath ?: @"",
                @"coverImg": book.coverImg ?: @"",
                @"durChapterId": @(book.charpterModel.charpterId),
                @"durChapterPage": @(book.page),
                @"durChapterOffset": @(book.charOffset),
                @"lastReadTime": @(book.readTime),
            }];
        }
        NSData *shelfData = [NSJSONSerialization dataWithJSONObject:shelf options:NSJSONWritingPrettyPrinted error:nil];
        if (!shelfData || ![writer addEntryWithName:kBackupBookshelfEntry data:shelfData]) {
            finish(nil, @"写入书架清单失败");
            return;
        }

        //config.json(阅读配置)
        RDReadConfigManager *config = [RDReadConfigManager sharedInstance];
        NSDictionary *configDict = @{
            @"fontSize": @(config.fontSize),
            @"fontName": config.fontName ?: @"",
            @"lineSpace": @(config.lineSpace),
            @"theme": @(config.theme),
            @"pageType": @(config.pageType),
        };
        NSData *configData = [NSJSONSerialization dataWithJSONObject:configDict options:NSJSONWritingPrettyPrinted error:nil];
        [writer addEntryWithName:kBackupConfigEntry data:configData];

        //ai_config.json(AI 翻译配置,legado 兼容扩展)
        if (![self writeAIConfigToZipWriter:writer]) {
            finish(nil, @"写入 AI 配置失败");
            return;
        }

        //bookmarks.json(本地书全部书签)
        NSMutableArray *bookmarkList = [NSMutableArray array];
        for (RDBookDetailModel *book in localBooks) {
            for (RDBookmarkModel *bm in [RDBookmarkManager bookmarksForBookId:book.bookId]) {
                [bookmarkList addObject:@{
                    @"bookmarkId": bm.bookmarkId ?: @"",
                    @"bookId": @(bm.bookId),
                    @"bookTitle": bm.bookTitle ?: @"",
                    @"charpterId": @(bm.charpterId),
                    @"charpterName": bm.charpterName ?: @"",
                    @"page": @(bm.page),
                    @"charOffset": @(bm.charOffset),
                    @"snippet": bm.snippet ?: @"",
                    @"note": bm.note ?: @"",
                    @"createTime": @(bm.createTime),
                }];
            }
        }
        NSData *bookmarksData = [NSJSONSerialization dataWithJSONObject:bookmarkList options:NSJSONWritingPrettyPrinted error:nil];
        if (bookmarksData) {
            [writer addEntryWithName:kBackupBookmarksEntry data:bookmarksData];
        }

        //replace_rules.json(正文净化规则,legado 同名)
        NSMutableArray *ruleList = [NSMutableArray array];
        for (RDReplaceRule *rule in [RDReplaceRuleStore sharedInstance].rules) {
            [ruleList addObject:[rule toDictionary]];
        }
        NSData *rulesData = [NSJSONSerialization dataWithJSONObject:@{@"version": @1, @"rules": ruleList} options:NSJSONWritingPrettyPrinted error:nil];
        if (rulesData) {
            [writer addEntryWithName:kBackupReplaceRulesEntry data:rulesData];
        }

        //fonts/:自定义阅读字体
        NSString *fontsDir = [RDFontManager fontsDirectory];
        for (NSString *file in [[NSFileManager defaultManager] contentsOfDirectoryAtPath:fontsDir error:nil]) {
            NSString *ext = file.pathExtension.lowercaseString;
            if (![@[@"ttf", @"otf", @"ttc"] containsObject:ext]) {
                continue;
            }
            [writer addEntryWithName:[NSString stringWithFormat:@"%@/%@", kBackupFontsDir, file]
                          fileAtPath:[fontsDir stringByAppendingPathComponent:file]];
        }

        //books/:源文件与封面(流式写入,大 PDF/漫画不整包进内存)
        for (RDBookDetailModel *book in localBooks) {
            NSString *filePath = [RDLocalBookManager absolutePathForBook:book];
            if (!filePath || ![[NSFileManager defaultManager] fileExistsAtPath:filePath]) {
                continue;
            }
            NSString *entry = [NSString stringWithFormat:@"%@/%@", kBackupBooksDir, book.localPath];
            if (![writer addEntryWithName:entry fileAtPath:filePath]) {
                finish(nil, @"写入书籍文件失败");
                return;
            }
            if (book.coverImg.length > 0) {
                NSString *coverPath = [[RDLocalBookManager booksDirectory] stringByAppendingPathComponent:book.coverImg];
                NSData *coverData = [NSData dataWithContentsOfFile:coverPath options:NSDataReadingMappedIfSafe error:nil];
                if (coverData.length > 0) {
                    [writer addEntryWithName:[NSString stringWithFormat:@"%@/%@", kBackupBooksDir, book.coverImg] data:coverData];
                }
            }
        }

        if (![writer finalizeArchive]) {
            finish(nil, @"生成备份文件失败");
            return;
        }
        finish(zipPath, nil);
    });
}

#pragma mark - 恢复

+ (void)restoreFromURL:(NSURL *)url complete:(void(^)(NSInteger, NSString * _Nullable))complete
{
    void (^finish)(NSInteger, NSString *) = ^(NSInteger count, NSString *message) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (complete) {
                complete(count, message);
            }
        });
    };
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        BOOL scoped = [url startAccessingSecurityScopedResource];
        RDZipArchive *zip = [[RDZipArchive alloc] initWithPath:url.path];
        if (scoped) {
            [url stopAccessingSecurityScopedResource];
        }
        if (!zip) {
            finish(0, @"不是有效的备份文件");
            return;
        }
        NSData *shelfData = [zip dataForEntry:kBackupBookshelfEntry];
        NSArray *shelf = shelfData ? [NSJSONSerialization JSONObjectWithData:shelfData options:0 error:nil] : nil;
        if (![shelf isKindOfClass:NSArray.class]) {
            shelf = @[];
        }
        NSData *aiProbe = [zip dataForEntry:[self aiConfigEntryName]];
        if (shelf.count == 0 && aiProbe.length == 0) {
            finish(0, @"备份中没有书架或 AI 配置数据");
            return;
        }

        NSInteger restored = 0;
        NSInteger failed = 0;
        NSString *lastError = nil;
        for (NSDictionary *item in shelf) {
            if (![item isKindOfClass:NSDictionary.class]) {
                continue;
            }
            NSString *localPath = MakeNSStringNoNull(item[@"localPath"]);
            NSInteger bookId = [MakeNSNumber(item[@"bookId"]) integerValue];
            if (localPath.length == 0 || bookId >= 0) {
                continue;
            }
            //还原书籍源文件(流式落盘:writeEntry 内部先写 .part 再原子替换)
            NSString *target = [[RDLocalBookManager booksDirectory] stringByAppendingPathComponent:localPath];
            NSString *bookEntry = [NSString stringWithFormat:@"%@/%@", kBackupBooksDir, localPath];
            if (![zip writeEntry:bookEntry toFile:target]) {
                lastError = @"备份中缺少书籍文件或写入失败";
                failed++;
                continue;
            }
            //还原封面
            NSString *cover = MakeNSStringNoNull(item[@"coverImg"]);
            if (cover.length > 0) {
                NSData *coverData = [zip dataForEntry:[NSString stringWithFormat:@"%@/%@", kBackupBooksDir, cover]];
                if (coverData.length > 0) {
                    [coverData writeToFile:[[RDLocalBookManager booksDirectory] stringByAppendingPathComponent:cover] atomically:YES];
                }
            }

            //还原书籍记录与进度
            RDBookDetailModel *book = [[RDBookDetailModel alloc] init];
            book.bookId = bookId;
            book.title = MakeNSStringNoNull(item[@"name"]);
            book.author = MakeNSStringNoNull(item[@"author"]);
            book.fileType = MakeNSStringNoNull(item[@"fileType"]);
            book.localPath = localPath;
            book.coverImg = cover;
            book.page = [MakeNSNumber(item[@"durChapterPage"]) integerValue];
            book.charOffset = [MakeNSNumber(item[@"durChapterOffset"]) integerValue];
            book.readTime = [MakeNSNumber(item[@"lastReadTime"]) doubleValue];
            book.onBookshelf = YES;
            book.end = YES;

            RDCharpterModel *placeholder = [[RDCharpterModel alloc] init];
            placeholder.bookId = bookId;
            placeholder.charpterId = [MakeNSNumber(item[@"durChapterId"]) integerValue];
            book.charpterModel = placeholder;

            //重新解析生成章节(章节内容不入备份,从源文件重建)
            NSString *rebuildError = nil;
            if (![RDLocalBookManager rebuildChaptersForBook:book errorMessage:&rebuildError]) {
                lastError = rebuildError;
                failed++;
                continue;
            }
            // 保留备份里的 lastReadTime,恢复后书架顺序与备份前一致
            [RDReadRecordManager insertOrReplaceModel:book touchReadTime:NO];
            restored++;
        }

        if (restored > 0) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [[NSNotificationCenter defaultCenter] postNotificationName:RDLocalBookImportedNotification object:nil];
            });
        }

        //还原阅读配置
        NSData *configData = [zip dataForEntry:kBackupConfigEntry];
        NSDictionary *configDict = configData ? [NSJSONSerialization JSONObjectWithData:configData options:0 error:nil] : nil;
        if ([configDict isKindOfClass:NSDictionary.class]) {
            dispatch_async(dispatch_get_main_queue(), ^{
                RDReadConfigManager *config = [RDReadConfigManager sharedInstance];
                NSNumber *fontSize = MakeNSNumber(configDict[@"fontSize"]);
                if (fontSize.doubleValue >= kConfigMinFontSize && fontSize.doubleValue <= kConfigMaxFontSize) {
                    config.fontSize = fontSize.doubleValue;
                    config.lineSpace = config.fontSize - 8;
                }
                NSString *fontName = MakeNSString(configDict[@"fontName"]);
                if (fontName) {
                    config.fontName = fontName;
                }
                NSNumber *theme = MakeNSNumber(configDict[@"theme"]);
                if (theme && theme.integerValue >= RDWhiteTheme && theme.integerValue <= RDBlackTheme) {
                    config.theme = theme.integerValue;
                }
                NSNumber *pageType = MakeNSNumber(configDict[@"pageType"]);
                if (pageType && pageType.integerValue >= RDNoneTypePage && pageType.integerValue <= RDSliderPage) {
                    config.pageType = pageType.integerValue;
                }
                [config archive];
            });
        }

        //还原书签(旧备份无该条目则跳过)
        NSData *bookmarksData = [zip dataForEntry:kBackupBookmarksEntry];
        NSArray *bookmarkItems = bookmarksData ? [NSJSONSerialization JSONObjectWithData:bookmarksData options:0 error:nil] : nil;
        if ([bookmarkItems isKindOfClass:NSArray.class]) {
            for (NSDictionary *item in bookmarkItems) {
                if (![item isKindOfClass:NSDictionary.class]) {
                    continue;
                }
                RDBookmarkModel *bm = [[RDBookmarkModel alloc] init];
                bm.bookmarkId = MakeNSStringNoNull(item[@"bookmarkId"]);
                bm.bookId = [MakeNSNumber(item[@"bookId"]) integerValue];
                bm.bookTitle = MakeNSStringNoNull(item[@"bookTitle"]);
                bm.charpterId = [MakeNSNumber(item[@"charpterId"]) integerValue];
                bm.charpterName = MakeNSStringNoNull(item[@"charpterName"]);
                bm.page = [MakeNSNumber(item[@"page"]) integerValue];
                bm.charOffset = [MakeNSNumber(item[@"charOffset"]) integerValue];
                bm.snippet = MakeNSStringNoNull(item[@"snippet"]);
                bm.note = MakeNSStringNoNull(item[@"note"]);
                bm.createTime = [MakeNSNumber(item[@"createTime"]) doubleValue];
                [RDBookmarkManager insertOrReplaceBookmark:bm];
            }
        }

        //还原正文净化规则
        NSData *rulesData = [zip dataForEntry:kBackupReplaceRulesEntry];
        NSDictionary *rulesRoot = rulesData ? [NSJSONSerialization JSONObjectWithData:rulesData options:0 error:nil] : nil;
        if ([rulesRoot isKindOfClass:NSDictionary.class] && [rulesRoot[@"rules"] isKindOfClass:NSArray.class]) {
            NSMutableArray *rules = [NSMutableArray array];
            for (id item in rulesRoot[@"rules"]) {
                RDReplaceRule *rule = [RDReplaceRule ruleFromDictionary:item];
                if (rule.pattern.length) {
                    [rules addObject:rule];
                }
            }
            if (rules.count > 0) {
                [[RDReplaceRuleStore sharedInstance] replaceAllRules:rules];
            }
        }

        //还原自定义字体并注册
        BOOL fontRestored = NO;
        NSString *fontsDir = [RDFontManager fontsDirectory];
        for (NSString *entry in zip.entryNames) {
            NSString *prefix = [kBackupFontsDir stringByAppendingString:@"/"];
            if (![entry hasPrefix:prefix]) {
                continue;
            }
            NSString *fileName = entry.lastPathComponent;
            NSString *ext = fileName.pathExtension.lowercaseString;
            if (fileName.length == 0 || ![@[@"ttf", @"otf", @"ttc"] containsObject:ext]) {
                continue;
            }
            if ([zip writeEntry:entry toFile:[fontsDir stringByAppendingPathComponent:fileName]]) {
                fontRestored = YES;
            }
        }
        if (fontRestored) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [[RDFontManager sharedInstance] registerCustomFontsAtLaunch];
                [[NSNotificationCenter defaultCenter] postNotificationName:RDFontListChangedNotification object:nil];
            });
        }

        //还原 AI 配置(不含密钥明文;密钥若本机 Keychain 已有同 profileId 会保留)
        [self restoreAIConfigFromZip:zip];

        if (restored == 0 && failed == 0 && aiProbe.length > 0) {
            // 仅 AI/配置备份
            finish(0, nil);
            return;
        }
        if (restored == 0) {
            finish(0, lastError ?: @"没有可恢复的书籍");
        }
        else if (failed > 0) {
            NSString *msg = [NSString stringWithFormat:@"成功 %ld 本,失败 %ld 本%@", (long)restored, (long)failed, lastError ? [NSString stringWithFormat:@":%@", lastError] : @""];
            finish(restored, msg);
        }
        else{
            finish(restored, nil);
        }
    });
}

@end
