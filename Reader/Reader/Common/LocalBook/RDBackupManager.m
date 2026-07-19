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
#import "RDLibraryTransaction.h"
#import "RDLibraryMutationCoordinator.h"
#import "RDReadConfigManager.h"
#import "RDBookmarkManager.h"
#import "RDBookmarkModel.h"
#import "RDReplaceRule.h"
#import "RDFontManager.h"

//清单中的文件名不可信:只取最后一段,并拒绝 "."/".."/空值,防止路径穿越
static NSString * RDBackupSafeFileName(NSString *raw) {
    NSString *name = raw.lastPathComponent;
    if (name.length == 0 || [name isEqualToString:@"."] || [name isEqualToString:@".."]) {
        return nil;
    }
    return name;
}

//落盘前的最终防线:标准化后必须仍在目标目录内(防御 lastPathComponent 之外的意外情况)
static BOOL RDBackupPathIsInsideDirectory(NSString *path, NSString *directory) {
    if (path.length == 0 || directory.length == 0) {
        return NO;
    }
    NSString *standardizedPath = path.stringByStandardizingPath;
    NSString *standardizedDir = directory.stringByStandardizingPath;
    if (![standardizedDir hasSuffix:@"/"]) {
        standardizedDir = [standardizedDir stringByAppendingString:@"/"];
    }
    return [standardizedPath hasPrefix:standardizedDir];
}

//与 legado 一致的清单文件名
static NSString * const kBackupBookshelfEntry = @"bookshelf.json";
static NSString * const kBackupConfigEntry = @"config.json";
static NSString * const kBackupBookmarksEntry = @"bookmarks.json";
static NSString * const kBackupReplaceRulesEntry = @"replace_rules.json";
static NSString * const kBackupBooksDir = @"books";
static NSString * const kBackupFontsDir = @"fonts";

@implementation RDBackupManager

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
        // 源文件缺失的书不写入清单:避免 bookshelf.json 里出现一本 zip 里根本没有对应文件的"幽灵书",
        // 让恢复端拿到看似完整、实则残缺的备份却收不到任何提示(P1-06)。
        NSInteger missingSourceCount = 0;
        for (RDBookDetailModel *book in books) {
            if (!book.isLocalBook) {
                continue;
            }
            NSString *filePath = [RDLocalBookManager absolutePathForBook:book];
            if (filePath.length > 0 && [[NSFileManager defaultManager] fileExistsAtPath:filePath]) {
                [localBooks addObject:book];
            } else {
                missingSourceCount++;
            }
        }
        NSMutableArray <NSString *>*warnings = [NSMutableArray array];
        if (missingSourceCount > 0) {
            [warnings addObject:[NSString stringWithFormat:@"%ld 本书源文件缺失,已跳过", (long)missingSourceCount]];
        }
        if (localBooks.count == 0) {
            finish(nil, missingSourceCount > 0 ? @"书架上的本地书均缺失源文件,无可备份内容" : @"书架上还没有本地书籍");
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
        // 手动封面很小（应用统一为 600x840 JPEG）；在 manager 串行队列内取一致性快照，
        // 后续清单与 zip 始终使用同一份数据，不受同时换封面影响。
        NSMutableDictionary <NSNumber *, NSData *>*customCoverSnapshots = [NSMutableDictionary dictionary];
        for (RDBookDetailModel *book in localBooks) {
            NSMutableDictionary *item = [@{
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
            } mutableCopy];
            NSData *customCoverData = [RDLocalBookManager customCoverDataForBook:book];
            NSString *customCoverFile = [RDLocalBookManager customCoverPathForBook:book].lastPathComponent;
            if (customCoverData.length > 0 && customCoverFile.length > 0) {
                // 可选扩展字段；旧版本备份无此字段时恢复逻辑保持不变。
                item[@"customCover"] = customCoverFile;
                customCoverSnapshots[@(book.bookId)] = customCoverData;
            }
            [shelf addObject:item];
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
        if (![writer addEntryWithName:kBackupConfigEntry data:configData]) {
            [warnings addObject:@"阅读配置写入失败"];
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
        if (!bookmarksData || ![writer addEntryWithName:kBackupBookmarksEntry data:bookmarksData]) {
            [warnings addObject:@"书签写入失败"];
        }

        //replace_rules.json(正文净化规则,legado 同名)
        NSMutableArray *ruleList = [NSMutableArray array];
        for (RDReplaceRule *rule in [RDReplaceRuleStore sharedInstance].rules) {
            [ruleList addObject:[rule toDictionary]];
        }
        NSData *rulesData = [NSJSONSerialization dataWithJSONObject:@{@"version": @1, @"rules": ruleList} options:NSJSONWritingPrettyPrinted error:nil];
        if (!rulesData || ![writer addEntryWithName:kBackupReplaceRulesEntry data:rulesData]) {
            [warnings addObject:@"净化规则写入失败"];
        }

        //fonts/:自定义阅读字体
        NSString *fontsDir = [RDFontManager fontsDirectory];
        NSInteger fontFailCount = 0;
        for (NSString *file in [[NSFileManager defaultManager] contentsOfDirectoryAtPath:fontsDir error:nil]) {
            NSString *ext = file.pathExtension.lowercaseString;
            if (![@[@"ttf", @"otf", @"ttc"] containsObject:ext]) {
                continue;
            }
            if (![writer addEntryWithName:[NSString stringWithFormat:@"%@/%@", kBackupFontsDir, file]
                                fileAtPath:[fontsDir stringByAppendingPathComponent:file]]) {
                fontFailCount++;
            }
        }
        if (fontFailCount > 0) {
            [warnings addObject:[NSString stringWithFormat:@"%ld 个自定义字体写入失败", (long)fontFailCount]];
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
            NSData *customCoverData = customCoverSnapshots[@(book.bookId)];
            NSString *customCoverFile = [RDLocalBookManager customCoverPathForBook:book].lastPathComponent;
            if (customCoverData.length > 0 && customCoverFile.length > 0) {
                NSString *customCoverEntry = [NSString stringWithFormat:@"%@/%@", kBackupBooksDir, customCoverFile];
                if (![writer addEntryWithName:customCoverEntry data:customCoverData]) {
                    finish(nil, @"写入手动封面失败");
                    return;
                }
            }
        }

        if (![writer finalizeArchive]) {
            finish(nil, @"生成备份文件失败");
            return;
        }
        // zip 本身生成成功,但存在可选内容缺失/写入失败时,不能只报"备份成功"——
        // 让调用方在展示分享面板的同时,把这些警告也展示给用户看见(P1-06)。
        finish(zipPath, warnings.count > 0 ? [warnings componentsJoinedByString:@";"] : nil);
    });
}

#pragma mark - 恢复

/// 本次恢复专用的暂存目录;失败返回 nil
+ (NSString *)p_createRestoreStagingDirectory
{
    NSString *root = [PATH_DOCUMENT stringByAppendingPathComponent:@"RestoreStaging"];
    NSString *dir = [root stringByAppendingPathComponent:[[NSUUID UUID] UUIDString]];
    NSError *error = nil;
    if (![[NSFileManager defaultManager] createDirectoryAtPath:dir
                                   withIntermediateDirectories:YES
                                                    attributes:@{NSFileProtectionKey: NSFileProtectionCompleteUntilFirstUserAuthentication}
                                                         error:&error]) {
        return nil;
    }
    return dir;
}

/// 把暂存文件移进正式路径;正式路径上已有文件时先移到 backupPath 留作回滚
+ (BOOL)p_commitStagedFile:(NSString *)staged toTarget:(NSString *)target backupPath:(NSString *)backupPath
{
    NSFileManager *fm = [NSFileManager defaultManager];
    [fm removeItemAtPath:backupPath error:nil];
    BOOL hadOld = [fm fileExistsAtPath:target];
    if (hadOld && ![fm moveItemAtPath:target toPath:backupPath error:nil]) {
        return NO;
    }
    if ([fm moveItemAtPath:staged toPath:target error:nil]) {
        return YES;
    }
    // 新文件没能就位:把旧文件原样放回
    if (hadOld) {
        [fm moveItemAtPath:backupPath toPath:target error:nil];
    }
    return NO;
}

/// 数据库提交失败时把旧源文件放回正式路径
+ (void)p_rollbackTarget:(NSString *)target fromBackup:(NSString *)backupPath
{
    NSFileManager *fm = [NSFileManager defaultManager];
    if (![fm fileExistsAtPath:backupPath]) {
        // 恢复前本来就没有这本书的文件,删掉刚放进去的新文件即可
        [fm removeItemAtPath:target error:nil];
        return;
    }
    [fm removeItemAtPath:target error:nil];
    [fm moveItemAtPath:backupPath toPath:target error:nil];
}

+ (void)restoreFromURL:(NSURL *)url complete:(void(^)(NSInteger, NSString * _Nullable))complete
{
    void (^finish)(NSInteger, NSString *) = ^(NSInteger count, NSString *message) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (complete) {
                complete(count, message);
            }
        });
    };
    // 恢复必须与导入/删除/清空同队列串行,否则会与并发导入交叉写同一本书(P1-01)
    [RDLibraryMutationCoordinator performAsync:^{
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
        if (shelf.count == 0) {
            finish(0, @"备份中没有书架数据");
            return;
        }

        NSInteger restored = 0;
        NSInteger failed = 0;
        NSInteger customCoverFailed = 0;
        NSString *lastError = nil;
        // 本次恢复的暂存目录:源文件先落这里,提交成功才进正式路径(P1-01)
        NSString *stagingRoot = [self p_createRestoreStagingDirectory];
        if (stagingRoot.length == 0) {
            finish(0, @"无法创建恢复暂存目录");
            return;
        }
        for (NSDictionary *item in shelf) {
            if (![item isKindOfClass:NSDictionary.class]) {
                continue;
            }
            //清单中的路径不可信:必须先规约成纯文件名,再校验落盘目标确实还在书籍目录内
            NSString *rawLocalPath = MakeNSStringNoNull(item[@"localPath"]);
            NSString *localPath = RDBackupSafeFileName(rawLocalPath);
            NSInteger bookId = [MakeNSNumber(item[@"bookId"]) integerValue];
            if (localPath.length == 0 || bookId >= 0) {
                continue;
            }
            NSString *booksDirectory = [RDLocalBookManager booksDirectory];
            //还原书籍源文件(流式落盘:writeEntry 内部先写 .part 再原子替换)
            NSString *target = [booksDirectory stringByAppendingPathComponent:localPath];
            if (!RDBackupPathIsInsideDirectory(target, booksDirectory)) {
                lastError = @"备份内容包含非法路径";
                failed++;
                continue;
            }
            //先落到暂存目录:正式路径上的旧文件在提交成功前一律不动
            NSString *staged = [stagingRoot stringByAppendingPathComponent:localPath];
            NSString *bookEntry = [NSString stringWithFormat:@"%@/%@", kBackupBooksDir, localPath];
            if (![zip writeEntry:bookEntry toFile:staged]) {
                lastError = @"备份中缺少书籍文件或写入失败";
                failed++;
                continue;
            }
            NSString *cover = RDBackupSafeFileName(MakeNSStringNoNull(item[@"coverImg"]));

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

            //重新解析生成章节(章节内容不入备份,从源文件重建);此处只解析不写库
            NSString *rebuildError = nil;
            NSArray *chapters = [RDLocalBookManager parseChaptersForBook:book atPath:staged errorMessage:&rebuildError];
            if (!chapters) {
                lastError = rebuildError;
                failed++;
                continue;
            }

            // 提交点:先把旧源文件挪到暂存备份,再把新文件原子移入正式路径,
            // 最后提交数据库事务。任一步失败都把旧文件放回去,保证只可能是
            // "完整旧状态"或"完整新状态",不出现文件与章节互不匹配(P1-01)。
            NSString *backup = [stagingRoot stringByAppendingPathComponent:
                                [NSString stringWithFormat:@"old_%@", localPath]];
            if (![self p_commitStagedFile:staged toTarget:target backupPath:backup]) {
                lastError = @"写入书籍文件失败";
                failed++;
                continue;
            }
            // 保留备份里的 lastReadTime,恢复后书架顺序与备份前一致;
            // 章节与读记录同一事务提交,失败则整体回滚(P1-02)。
            NSError *commitError = nil;
            if (![RDLibraryTransaction commitBook:book
                                         chapters:chapters
                                    touchReadTime:NO
                                            error:&commitError]) {
                [self p_rollbackTarget:target fromBackup:backup];
                lastError = commitError.localizedDescription ?: @"写入书籍记录失败";
                failed++;
                continue;
            }

            // 数据库已提交,以下是不影响可读性的附属文件,失败只降级为警告
            if (cover.length > 0) {
                NSString *coverTarget = [booksDirectory stringByAppendingPathComponent:cover];
                if (RDBackupPathIsInsideDirectory(coverTarget, booksDirectory)) {
                    NSData *coverData = [zip dataForEntry:[NSString stringWithFormat:@"%@/%@", kBackupBooksDir, cover]];
                    if (coverData.length > 0) {
                        [coverData writeToFile:coverTarget atomically:YES];
                    }
                }
            }
            // 新备份可携带手动封面；manager 在全局封面队列内失效旧请求并原子恢复。
            NSString *customCoverValue = MakeNSStringNoNull(item[@"customCover"]);
            NSString *customCoverFile = customCoverValue.lastPathComponent;
            if (customCoverFile.length > 0) {
                NSString *customCoverEntry = [NSString stringWithFormat:@"%@/%@", kBackupBooksDir, customCoverFile];
                NSData *customCoverData = [zip dataForEntry:customCoverEntry];
                if (![RDLocalBookManager restoreCustomCoverData:customCoverData forBook:book]) {
                    customCoverFailed++;
                }
            } else {
                // 旧备份没有手动封面时也应清掉同 bookId 的旧文件，避免恢复前状态泄漏。
                [RDLocalBookManager removeCustomCoverForBook:book];
            }
            restored++;
        }

        // 暂存目录里剩下的都是已提交的旧文件副本或失败残留,统一清掉
        [[NSFileManager defaultManager] removeItemAtPath:stagingRoot error:nil];

        // 全部书籍处理完毕后才发一次书架刷新,避免中途的混合状态被 UI 读到
        if (restored > 0) {
            [RDLibraryMutationCoordinator postLibraryChanged:nil];
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


        if (restored == 0) {
            finish(0, lastError ?: @"没有可恢复的书籍");
        }
        else if (failed > 0) {
            NSMutableString *msg = [NSMutableString stringWithFormat:@"成功 %ld 本,失败 %ld 本%@", (long)restored, (long)failed, lastError ? [NSString stringWithFormat:@":%@", lastError] : @""];
            if (customCoverFailed > 0) {
                [msg appendFormat:@",另有 %ld 张手动封面恢复失败", (long)customCoverFailed];
            }
            finish(restored, msg);
        }
        else if (customCoverFailed > 0) {
            finish(restored, [NSString stringWithFormat:@"已恢复 %ld 本,但 %ld 张手动封面恢复失败", (long)restored, (long)customCoverFailed]);
        }
        else{
            finish(restored, nil);
        }
    }];
}

@end
