//
//  RDBookTextUtil.m
//  Reader
//

#import "RDBookTextUtil.h"

@implementation RDBookTextUtil

+ (NSString *)stringFromData:(NSData *)data
{
    if (data.length == 0) {
        return @"";
    }
    const uint8_t *bytes = data.bytes;
    // BOM
    if (data.length >= 3 && bytes[0] == 0xEF && bytes[1] == 0xBB && bytes[2] == 0xBF) {
        return [[NSString alloc] initWithData:[data subdataWithRange:NSMakeRange(3, data.length - 3)] encoding:NSUTF8StringEncoding];
    }
    if (data.length >= 2 && bytes[0] == 0xFF && bytes[1] == 0xFE) {
        return [[NSString alloc] initWithData:data encoding:NSUTF16LittleEndianStringEncoding];
    }
    if (data.length >= 2 && bytes[0] == 0xFE && bytes[1] == 0xFF) {
        return [[NSString alloc] initWithData:data encoding:NSUTF16BigEndianStringEncoding];
    }
    // UTF-8 严格解码
    NSString *result = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    if (result) {
        return result;
    }
    // GB18030(覆盖 GBK/GB2312)
    NSStringEncoding gb18030 = CFStringConvertEncodingToNSStringEncoding(kCFStringEncodingGB_18030_2000);
    result = [[NSString alloc] initWithData:data encoding:gb18030];
    if (result) {
        return result;
    }
    // Big5
    NSStringEncoding big5 = CFStringConvertEncodingToNSStringEncoding(kCFStringEncodingBig5);
    result = [[NSString alloc] initWithData:data encoding:big5];
    if (result) {
        return result;
    }
    return [[NSString alloc] initWithData:data encoding:NSISOLatin1StringEncoding];
}

+ (NSString *)stringFromData:(NSData *)data encoding:(NSStringEncoding)encoding
{
    if (data.length == 0) {
        return @"";
    }
    NSString *result = [[NSString alloc] initWithData:data encoding:encoding];
    if (result) {
        return result;
    }
    return [self stringFromData:data];
}

#pragma mark - HTML

+ (NSString *)plainTextFromHTML:(NSString *)html
{
    if (html.length == 0) {
        return @"";
    }
    NSMutableString *text = [html mutableCopy];

    void (^regexReplace)(NSString *, NSString *) = ^(NSString *pattern, NSString *replacement) {
        NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:pattern
                                                                               options:NSRegularExpressionCaseInsensitive | NSRegularExpressionDotMatchesLineSeparators
                                                                                 error:nil];
        [regex replaceMatchesInString:text options:0 range:NSMakeRange(0, text.length) withTemplate:replacement];
    };

    regexReplace(@"<(script|style|head)[^>]*>.*?</\\1>", @"");
    regexReplace(@"<!--.*?-->", @"");
    // 块级标签结束 → 换行
    regexReplace(@"<br\\s*/?>", @"\n");
    regexReplace(@"</(p|div|h1|h2|h3|h4|h5|h6|li|tr|blockquote|section|article)>", @"\n");
    regexReplace(@"<(p|h1|h2|h3|h4|h5|h6|li|blockquote)[^>]*>", @"\n");
    regexReplace(@"<[^>]+>", @"");

    NSString *decoded = [self decodeHTMLEntities:text];
    return [self collapseWhitespace:decoded];
}

+ (NSString *)headingFromHTML:(NSString *)html
{
    if (html.length == 0) {
        return nil;
    }
    // 优先 h1-h4 / <title>
    NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:@"<(h1|h2|h3|h4|title)[^>]*>(.*?)</\\1>"
                                                                           options:NSRegularExpressionCaseInsensitive | NSRegularExpressionDotMatchesLineSeparators
                                                                             error:nil];
    NSArray <NSTextCheckingResult *>*matches = [regex matchesInString:html options:0 range:NSMakeRange(0, html.length)];
    for (NSTextCheckingResult *match in matches) {
        NSString *tag = [[html substringWithRange:[match rangeAtIndex:1]] lowercaseString];
        NSString *inner = [html substringWithRange:[match rangeAtIndex:2]];
        NSString *stripped = [self plainTextFromHTML:inner];
        NSString *trimmed = [stripped stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        // 跳过无意义 title(如 "cover" / 文件名)
        if (trimmed.length == 0) {
            continue;
        }
        if ([tag isEqualToString:@"title"] && trimmed.length < 3) {
            continue;
        }
        if (trimmed.length > 80) {
            trimmed = [[trimmed substringToIndex:80] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        }
        return trimmed;
    }
    // 无标题标签:用正文首行(许多英文 epub 扉页只有 p/div)
    return [self titleCandidateFromPlainText:[self plainTextFromHTML:html]];
}

+ (NSString *)titleCandidateFromPlainText:(NSString *)text
{
    if (text.length == 0) {
        return nil;
    }
    NSArray <NSString *>*lines = [text componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]];
    for (NSString *raw in lines) {
        NSString *line = [raw stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (line.length < 2) {
            continue;
        }
        // 跳过纯标点 / 过长(像正文段落)
        if (line.length > 80) {
            // 长句不像标题,取前 60 字并尽量在空格处截断
            NSString *cut = [line substringToIndex:60];
            NSRange sp = [cut rangeOfString:@" " options:NSBackwardsSearch];
            if (sp.location != NSNotFound && sp.location > 20) {
                cut = [cut substringToIndex:sp.location];
            }
            line = cut;
        }
        // 纯数字 / 仅符号
        NSCharacterSet *alnum = [NSCharacterSet alphanumericCharacterSet];
        BOOL hasLetter = NO;
        for (NSUInteger i = 0; i < line.length; i++) {
            if ([alnum characterIsMember:[line characterAtIndex:i]]) {
                hasLetter = YES;
                break;
            }
        }
        if (!hasLetter) {
            continue;
        }
        return line;
    }
    return nil;
}

+ (NSString *)decodeHTMLEntities:(NSString *)string
{
    if ([string rangeOfString:@"&"].location == NSNotFound) {
        return string;
    }
    NSMutableString *text = [string mutableCopy];
    NSDictionary *entities = @{@"&nbsp;": @" ", @"&amp;": @"&", @"&lt;": @"<", @"&gt;": @">",
                               @"&quot;": @"\"", @"&#39;": @"'", @"&apos;": @"'", @"&hellip;": @"…",
                               @"&mdash;": @"—", @"&ndash;": @"–", @"&ldquo;": @"“", @"&rdquo;": @"”",
                               @"&lsquo;": @"‘", @"&rsquo;": @"’", @"&copy;": @"©"};
    for (NSString *key in entities) {
        [text replaceOccurrencesOfString:key withString:entities[key] options:NSCaseInsensitiveSearch range:NSMakeRange(0, text.length)];
    }
    // 数字实体 &#123; / &#x1F;
    NSRegularExpression *numeric = [NSRegularExpression regularExpressionWithPattern:@"&#(x?)([0-9a-fA-F]+);" options:0 error:nil];
    NSArray *matches = [numeric matchesInString:text options:0 range:NSMakeRange(0, text.length)];
    for (NSTextCheckingResult *match in matches.reverseObjectEnumerator) {
        BOOL isHex = [match rangeAtIndex:1].length > 0;
        NSString *value = [text substringWithRange:[match rangeAtIndex:2]];
        unsigned int code = 0;
        NSScanner *scanner = [NSScanner scannerWithString:value];
        BOOL ok = isHex ? [scanner scanHexInt:&code] : (code = (unsigned int)value.integerValue, YES);
        if (ok && code > 0 && code <= 0x10FFFF) {
            unichar chars[2];
            NSInteger len = 0;
            if (code <= 0xFFFF) {
                chars[len++] = (unichar)code;
            }
            else {
                code -= 0x10000;
                chars[len++] = (unichar)(0xD800 + (code >> 10));
                chars[len++] = (unichar)(0xDC00 + (code & 0x3FF));
            }
            [text replaceCharactersInRange:match.range withString:[NSString stringWithCharacters:chars length:len]];
        }
    }
    return text;
}

+ (NSString *)collapseWhitespace:(NSString *)string
{
    NSString *text = [self normalizeLineBreaks:string];
    NSRegularExpression *blank = [NSRegularExpression regularExpressionWithPattern:@"\n{3,}" options:0 error:nil];
    text = [blank stringByReplacingMatchesInString:text options:0 range:NSMakeRange(0, text.length) withTemplate:@"\n\n"];
    return [text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

+ (NSString *)normalizeLineBreaks:(NSString *)text
{
    NSMutableString *result = [text mutableCopy];
    [result replaceOccurrencesOfString:@"\r\n" withString:@"\n" options:0 range:NSMakeRange(0, result.length)];
    [result replaceOccurrencesOfString:@"\r" withString:@"\n" options:0 range:NSMakeRange(0, result.length)];
    // 去行尾空白
    NSRegularExpression *trailing = [NSRegularExpression regularExpressionWithPattern:@"[ \t　]+\n" options:0 error:nil];
    [trailing replaceMatchesInString:result options:0 range:NSMakeRange(0, result.length) withTemplate:@"\n"];
    return result;
}

@end
