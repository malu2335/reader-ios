//
//  RDEpubBookParser.m
//  Reader
//

#import "RDEpubBookParser.h"
#import "RDZipArchive.h"
#import "RDBookTextUtil.h"
#import "RDCharpterModel.h"

#pragma mark - OPF 解析代理

@interface RDEpubManifestItem : NSObject
@property (nonatomic,copy) NSString *itemId;
@property (nonatomic,copy) NSString *href;
@property (nonatomic,copy) NSString *mediaType;
@property (nonatomic,copy) NSString *properties;
@end
@implementation RDEpubManifestItem
@end

@interface RDEpubOpfParser : NSObject <NSXMLParserDelegate>
@property (nonatomic,strong) NSMutableDictionary <NSString *,RDEpubManifestItem *>*manifest;  //id → item
@property (nonatomic,strong) NSMutableArray <NSString *>*spine;      //idref 顺序
@property (nonatomic,copy) NSString *title;
@property (nonatomic,copy) NSString *author;
@property (nonatomic,copy) NSString *coverId;    //<meta name="cover" content="...">
@property (nonatomic,strong) NSMutableString *characters;
@property (nonatomic,copy) NSString *currentElement;
@end

@implementation RDEpubOpfParser

- (instancetype)init
{
    self = [super init];
    if (self) {
        _manifest = [NSMutableDictionary dictionary];
        _spine = [NSMutableArray array];
        _characters = [NSMutableString string];
    }
    return self;
}

- (void)parser:(NSXMLParser *)parser didStartElement:(NSString *)elementName namespaceURI:(NSString *)namespaceURI qualifiedName:(NSString *)qName attributes:(NSDictionary<NSString *,NSString *> *)attributeDict
{
    NSString *name = [self localName:elementName];
    self.currentElement = name;
    [self.characters setString:@""];

    if ([name isEqualToString:@"item"]) {
        RDEpubManifestItem *item = [[RDEpubManifestItem alloc] init];
        item.itemId = attributeDict[@"id"] ?: @"";
        item.href = attributeDict[@"href"] ?: @"";
        item.mediaType = attributeDict[@"media-type"] ?: @"";
        item.properties = attributeDict[@"properties"] ?: @"";
        if (item.itemId.length > 0 && item.href.length > 0) {
            self.manifest[item.itemId] = item;
        }
    }
    else if ([name isEqualToString:@"itemref"]) {
        NSString *idref = attributeDict[@"idref"];
        //linear="no" 的辅助页跳过
        NSString *linear = attributeDict[@"linear"];
        if (idref.length > 0 && !(linear && [linear caseInsensitiveCompare:@"no"] == NSOrderedSame)) {
            [self.spine addObject:idref];
        }
    }
    else if ([name isEqualToString:@"meta"]) {
        NSString *metaName = attributeDict[@"name"];
        if ([metaName isEqualToString:@"cover"] && attributeDict[@"content"].length > 0) {
            self.coverId = attributeDict[@"content"];
        }
    }
}

- (void)parser:(NSXMLParser *)parser foundCharacters:(NSString *)string
{
    [self.characters appendString:string];
}

- (void)parser:(NSXMLParser *)parser didEndElement:(NSString *)elementName namespaceURI:(NSString *)namespaceURI qualifiedName:(NSString *)qName
{
    NSString *name = [self localName:elementName];
    NSString *text = [self.characters stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if ([name isEqualToString:@"title"] && self.title.length == 0 && text.length > 0) {
        self.title = text;
    }
    else if ([name isEqualToString:@"creator"] && self.author.length == 0 && text.length > 0) {
        self.author = text;
    }
    [self.characters setString:@""];
}

- (NSString *)localName:(NSString *)elementName
{
    NSRange colon = [elementName rangeOfString:@":"];
    return colon.location == NSNotFound ? elementName : [elementName substringFromIndex:colon.location + 1];
}

@end

#pragma mark - NCX 目录解析(href → 章节名)

@interface RDEpubNcxParser : NSObject <NSXMLParserDelegate>
@property (nonatomic,strong) NSMutableDictionary <NSString *,NSString *>*titleByHref;
@property (nonatomic,strong) NSMutableString *characters;
@property (nonatomic,copy) NSString *pendingLabel;
@property (nonatomic,assign) BOOL inText;
@end

@implementation RDEpubNcxParser

- (instancetype)init
{
    self = [super init];
    if (self) {
        _titleByHref = [NSMutableDictionary dictionary];
        _characters = [NSMutableString string];
    }
    return self;
}

- (void)parser:(NSXMLParser *)parser didStartElement:(NSString *)elementName namespaceURI:(NSString *)namespaceURI qualifiedName:(NSString *)qName attributes:(NSDictionary<NSString *,NSString *> *)attributeDict
{
    if ([elementName hasSuffix:@"text"]) {
        self.inText = YES;
        [self.characters setString:@""];
    }
    else if ([elementName hasSuffix:@"content"]) {
        NSString *src = attributeDict[@"src"];
        if (src.length > 0 && self.pendingLabel.length > 0) {
            //去掉锚点,只按文件路径匹配
            NSString *href = [src componentsSeparatedByString:@"#"].firstObject;
            if (href.length > 0 && !self.titleByHref[href]) {
                self.titleByHref[href] = self.pendingLabel;
            }
        }
    }
}

- (void)parser:(NSXMLParser *)parser foundCharacters:(NSString *)string
{
    if (self.inText) {
        [self.characters appendString:string];
    }
}

- (void)parser:(NSXMLParser *)parser didEndElement:(NSString *)elementName namespaceURI:(NSString *)namespaceURI qualifiedName:(NSString *)qName
{
    if ([elementName hasSuffix:@"text"]) {
        self.inText = NO;
        NSString *label = [self.characters stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (label.length > 0) {
            self.pendingLabel = label;
        }
    }
}

@end

#pragma mark - 解析器主体

@implementation RDEpubBookParser

+ (RDLocalBookParseResult *)parseFileAtPath:(NSString *)path error:(NSString **)errorMessage
{
    RDZipArchive *zip = [[RDZipArchive alloc] initWithPath:path];
    if (!zip) {
        if (errorMessage) *errorMessage = @"不是有效的 EPUB 文件";
        return nil;
    }

    //1. container.xml → OPF 路径
    NSString *containerName = [zip entryMatchingName:@"META-INF/container.xml"];
    NSData *containerData = containerName ? [zip dataForEntry:containerName] : nil;
    NSString *opfPath = nil;
    if (containerData) {
        NSString *containerXml = [RDBookTextUtil stringFromData:containerData];
        NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:@"full-path\\s*=\\s*\"([^\"]+)\"" options:0 error:nil];
        NSTextCheckingResult *match = [regex firstMatchInString:containerXml options:0 range:NSMakeRange(0, containerXml.length)];
        if (match) {
            opfPath = [containerXml substringWithRange:[match rangeAtIndex:1]];
        }
    }
    if (!opfPath) {
        //兜底:直接找 .opf 条目
        for (NSString *name in zip.entryNames) {
            if ([name.pathExtension.lowercaseString isEqualToString:@"opf"]) {
                opfPath = name;
                break;
            }
        }
    }
    NSData *opfData = opfPath ? [zip dataForEntry:([zip entryMatchingName:opfPath] ?: opfPath)] : nil;
    if (!opfData) {
        if (errorMessage) *errorMessage = @"EPUB 缺少可识别的内容清单";
        return nil;
    }

    //2. OPF:manifest + spine + metadata
    RDEpubOpfParser *opf = [[RDEpubOpfParser alloc] init];
    NSXMLParser *xml = [[NSXMLParser alloc] initWithData:opfData];
    xml.delegate = opf;
    [xml parse];
    if (opf.spine.count == 0) {
        //现实 EPUB(Sigil 衍生工具等)偶见非法 XML,如无值属性 <dc:creator opf:role>,
        //NSXMLParser 严格模式会中途终止;退回正则从 OPF 文本直接抽取
        [self p_populateOpf:opf fromOpfData:opfData];
    }
    if (opf.spine.count == 0) {
        if (errorMessage) *errorMessage = @"EPUB 中没有可阅读的章节";
        return nil;
    }
    NSString *opfDir = [opfPath stringByDeletingLastPathComponent];

    //3. NCX / nav 目录,用于章节命名
    NSDictionary <NSString *,NSString *>*titleByHref = [self chapterTitlesWithZip:zip opf:opf opfDir:opfDir];

    //4. 逐个 spine 项抽取文本
    NSMutableArray <RDCharpterModel *>*chapters = [NSMutableArray array];
    for (NSString *idref in opf.spine) {
        RDEpubManifestItem *item = opf.manifest[idref];
        if (!item) {
            continue;
        }
        NSString *href = [self resolveHref:item.href baseDir:opfDir];
        NSString *entry = [zip entryMatchingName:href];
        NSData *chapterData = entry ? [zip dataForEntry:entry] : nil;
        if (!chapterData) {
            continue;
        }
        NSString *html = [RDBookTextUtil stringFromData:chapterData];
        NSString *content = [RDBookTextUtil plainTextFromHTML:html];
        if (content.length == 0) {
            continue;
        }
        NSString *name = titleByHref[item.href] ?: titleByHref[href];
        if (name.length == 0) {
            name = [RDBookTextUtil headingFromHTML:html];
        }
        if (name.length == 0) {
            name = [NSString stringWithFormat:@"第%@节", @(chapters.count + 1)];
        }
        RDCharpterModel *model = [[RDCharpterModel alloc] init];
        model.charpterId = chapters.count + 1;
        model.name = name;
        model.content = content;
        [chapters addObject:model];
    }
    if (chapters.count == 0) {
        if (errorMessage) *errorMessage = @"EPUB 中没有可阅读的章节";
        return nil;
    }

    RDLocalBookParseResult *result = [[RDLocalBookParseResult alloc] init];
    result.title = opf.title;
    result.author = opf.author;
    result.chapters = chapters.copy;
    result.coverData = [self coverDataWithZip:zip opf:opf opfDir:opfDir];
    return result;
}

//从标签文本里取属性值(双/单引号均可);attr 名前置 \b 防止匹配到别的属性子串
static NSString *RDEpubAttrValue(NSString *tag, NSString *attr)
{
    NSString *pattern = [NSString stringWithFormat:@"\\b%@\\s*=\\s*[\"']([^\"']*)[\"']", attr];
    NSRegularExpression *re = [NSRegularExpression regularExpressionWithPattern:pattern
                                                                        options:NSRegularExpressionCaseInsensitive
                                                                          error:nil];
    NSTextCheckingResult *m = [re firstMatchInString:tag options:0 range:NSMakeRange(0, tag.length)];
    return m ? [tag substringWithRange:[m rangeAtIndex:1]] : nil;
}

///宽容模式:XML 解析失败时用正则从 OPF 原文抽 manifest/spine/title/creator/cover
+ (void)p_populateOpf:(RDEpubOpfParser *)opf fromOpfData:(NSData *)opfData
{
    NSString *text = [RDBookTextUtil stringFromData:opfData];
    if (text.length == 0) {
        return;
    }
    NSRange full = NSMakeRange(0, text.length);

    //manifest <item .../>(\b 保证不吞 <itemref>)
    NSRegularExpression *itemRe = [NSRegularExpression regularExpressionWithPattern:@"<item\\b[^>]*>"
                                                                            options:NSRegularExpressionCaseInsensitive
                                                                              error:nil];
    for (NSTextCheckingResult *m in [itemRe matchesInString:text options:0 range:full]) {
        NSString *tag = [text substringWithRange:m.range];
        RDEpubManifestItem *item = [[RDEpubManifestItem alloc] init];
        item.itemId = RDEpubAttrValue(tag, @"id") ?: @"";
        item.href = RDEpubAttrValue(tag, @"href") ?: @"";
        item.mediaType = RDEpubAttrValue(tag, @"media-type") ?: @"";
        item.properties = RDEpubAttrValue(tag, @"properties") ?: @"";
        if (item.itemId.length > 0 && item.href.length > 0 && !opf.manifest[item.itemId]) {
            opf.manifest[item.itemId] = item;
        }
    }

    //spine <itemref .../>,保持文档顺序;linear="no" 跳过
    NSRegularExpression *refRe = [NSRegularExpression regularExpressionWithPattern:@"<itemref\\b[^>]*>"
                                                                           options:NSRegularExpressionCaseInsensitive
                                                                             error:nil];
    for (NSTextCheckingResult *m in [refRe matchesInString:text options:0 range:full]) {
        NSString *tag = [text substringWithRange:m.range];
        NSString *idref = RDEpubAttrValue(tag, @"idref");
        NSString *linear = RDEpubAttrValue(tag, @"linear");
        if (idref.length > 0 && !(linear && [linear caseInsensitiveCompare:@"no"] == NSOrderedSame)) {
            [opf.spine addObject:idref];
        }
    }

    //metadata:title / creator(取第一个非空文本)
    if (opf.title.length == 0) {
        NSRegularExpression *titleRe = [NSRegularExpression regularExpressionWithPattern:@"<(?:\\w+:)?title[^>]*>\\s*([^<]+?)\\s*<"
                                                                                 options:NSRegularExpressionCaseInsensitive
                                                                                   error:nil];
        NSTextCheckingResult *m = [titleRe firstMatchInString:text options:0 range:full];
        if (m) {
            opf.title = [text substringWithRange:[m rangeAtIndex:1]];
        }
    }
    if (opf.author.length == 0) {
        NSRegularExpression *creatorRe = [NSRegularExpression regularExpressionWithPattern:@"<(?:\\w+:)?creator[^>]*>\\s*([^<]+?)\\s*<"
                                                                                   options:NSRegularExpressionCaseInsensitive
                                                                                     error:nil];
        NSTextCheckingResult *m = [creatorRe firstMatchInString:text options:0 range:full];
        if (m) {
            opf.author = [text substringWithRange:[m rangeAtIndex:1]];
        }
    }
    if (opf.coverId.length == 0) {
        NSRegularExpression *metaRe = [NSRegularExpression regularExpressionWithPattern:@"<meta\\b[^>]*>"
                                                                                options:NSRegularExpressionCaseInsensitive
                                                                                  error:nil];
        for (NSTextCheckingResult *m in [metaRe matchesInString:text options:0 range:full]) {
            NSString *tag = [text substringWithRange:m.range];
            NSString *name = RDEpubAttrValue(tag, @"name");
            if ([name caseInsensitiveCompare:@"cover"] == NSOrderedSame) {
                NSString *content = RDEpubAttrValue(tag, @"content");
                if (content.length > 0) {
                    opf.coverId = content;
                    break;
                }
            }
        }
    }
}

//读取 toc.ncx(EPUB2)或 nav 文档(EPUB3)得到 href → 章节名
+ (NSDictionary <NSString *,NSString *>*)chapterTitlesWithZip:(RDZipArchive *)zip opf:(RDEpubOpfParser *)opf opfDir:(NSString *)opfDir
{
    NSString *tocHref = nil;
    for (RDEpubManifestItem *item in opf.manifest.allValues) {
        if ([item.mediaType isEqualToString:@"application/x-dtbncx+xml"]) {
            tocHref = item.href;
            break;
        }
        if ([item.properties containsString:@"nav"]) {
            tocHref = tocHref ?: item.href;
        }
    }
    if (!tocHref) {
        return @{};
    }
    NSString *entry = [zip entryMatchingName:[self resolveHref:tocHref baseDir:opfDir]];
    NSData *tocData = entry ? [zip dataForEntry:entry] : nil;
    if (!tocData) {
        return @{};
    }

    if ([entry.pathExtension.lowercaseString isEqualToString:@"ncx"]) {
        RDEpubNcxParser *ncx = [[RDEpubNcxParser alloc] init];
        NSXMLParser *xml = [[NSXMLParser alloc] initWithData:tocData];
        xml.delegate = ncx;
        [xml parse];
        return ncx.titleByHref.copy;
    }

    //EPUB3 nav 文档:抓 <a href="...">标题</a>
    NSString *html = [RDBookTextUtil stringFromData:tocData];
    NSMutableDictionary *titles = [NSMutableDictionary dictionary];
    NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:@"<a[^>]+href\\s*=\\s*\"([^\"#]+)[^\"]*\"[^>]*>(.*?)</a>"
                                                                           options:NSRegularExpressionCaseInsensitive | NSRegularExpressionDotMatchesLineSeparators
                                                                             error:nil];
    for (NSTextCheckingResult *match in [regex matchesInString:html options:0 range:NSMakeRange(0, html.length)]) {
        NSString *href = [html substringWithRange:[match rangeAtIndex:1]];
        NSString *label = [RDBookTextUtil plainTextFromHTML:[html substringWithRange:[match rangeAtIndex:2]]];
        if (href.length > 0 && label.length > 0 && !titles[href]) {
            titles[href] = label;
        }
    }
    return titles.copy;
}

+ (NSData *)coverDataWithZip:(RDZipArchive *)zip opf:(RDEpubOpfParser *)opf opfDir:(NSString *)opfDir
{
    RDEpubManifestItem *coverItem = nil;
    for (RDEpubManifestItem *item in opf.manifest.allValues) {
        if ([item.properties containsString:@"cover-image"]) {
            coverItem = item;
            break;
        }
    }
    if (!coverItem && opf.coverId.length > 0) {
        coverItem = opf.manifest[opf.coverId];
    }
    if (!coverItem) {
        //兜底:manifest 里 id 含 cover 的图片
        for (RDEpubManifestItem *item in opf.manifest.allValues) {
            if ([item.mediaType hasPrefix:@"image/"] && [item.itemId.lowercaseString containsString:@"cover"]) {
                coverItem = item;
                break;
            }
        }
    }
    if (!coverItem || ![coverItem.mediaType hasPrefix:@"image/"]) {
        return nil;
    }
    NSString *entry = [zip entryMatchingName:[self resolveHref:coverItem.href baseDir:opfDir]];
    return entry ? [zip dataForEntry:entry] : nil;
}

//相对 OPF 目录解析 href,处理 ../ 与 URL 编码
+ (NSString *)resolveHref:(NSString *)href baseDir:(NSString *)baseDir
{
    NSString *decoded = href.stringByRemovingPercentEncoding ?: href;
    NSString *joined = baseDir.length > 0 ? [baseDir stringByAppendingPathComponent:decoded] : decoded;
    NSMutableArray *parts = [NSMutableArray array];
    for (NSString *component in joined.pathComponents) {
        if ([component isEqualToString:@".."]) {
            [parts removeLastObject];
        }
        else if (![component isEqualToString:@"."]) {
            [parts addObject:component];
        }
    }
    return [parts componentsJoinedByString:@"/"];
}

@end
