//
//  RDTxtBookParser.m
//  Reader
//

#import "RDTxtBookParser.h"
#import "RDBookTextUtil.h"
#import "RDCharpterModel.h"

//没有识别到章节时按该长度分段
static const NSUInteger kTxtFallbackChunkLength = 8000;
//章节数上限,防止异常文本切出海量章节
static const NSUInteger kTxtMaxChapterCount = 8000;

@implementation RDTxtBookParser

+ (RDLocalBookParseResult *)parseFileAtPath:(NSString *)path error:(NSString **)errorMessage
{
    NSData *data = [NSData dataWithContentsOfFile:path];
    if (data.length == 0) {
        if (errorMessage) *errorMessage = @"文件为空或无法读取";
        return nil;
    }
    NSString *raw = [RDBookTextUtil stringFromData:data];
    if (raw.length == 0) {
        if (errorMessage) *errorMessage = @"无法识别文本编码";
        return nil;
    }
    NSString *text = [RDBookTextUtil normalizeLineBreaks:raw];

    RDLocalBookParseResult *result = [[RDLocalBookParseResult alloc] init];
    result.chapters = [self splitChapters:text];
    if (result.chapters.count == 0) {
        if (errorMessage) *errorMessage = @"文件没有可阅读的内容";
        return nil;
    }
    return result;
}

+ (NSArray <RDCharpterModel *>*)splitChapters:(NSString *)text
{
    // 常见网文章节标题:第x章/卷/回/节/集/部/篇/话,以及 序章/序言/楔子/引子/番外/尾声
    NSString *pattern = @"(?m)^[ \t　]*((?:第[0-9零一二三四五六七八九十百千万〇两]{1,10}[章卷回节集部篇话])|(?:(?:序章|序言|楔子|引子|尾声|后记|番外)))[ \t　]*[^\n]{0,40}$";
    NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:pattern options:0 error:nil];
    NSArray <NSTextCheckingResult *>*matches = [regex matchesInString:text options:0 range:NSMakeRange(0, text.length)];

    NSMutableArray *chapters = [NSMutableArray array];
    if (matches.count >= 2) {
        //标题前的内容作为开篇
        NSUInteger firstLoc = matches.firstObject.range.location;
        if (firstLoc > 0) {
            NSString *preface = [self trimmed:[text substringToIndex:firstLoc]];
            if (preface.length > 0) {
                [chapters addObject:[self chapterWithName:@"开篇" content:preface index:chapters.count]];
            }
        }
        for (NSUInteger i = 0; i < matches.count && chapters.count < kTxtMaxChapterCount; i++) {
            NSRange titleRange = matches[i].range;
            NSUInteger contentStart = NSMaxRange(titleRange);
            NSUInteger contentEnd = (i + 1 < matches.count) ? matches[i + 1].range.location : text.length;
            NSString *name = [self trimmed:[text substringWithRange:titleRange]];
            NSString *content = [self trimmed:[text substringWithRange:NSMakeRange(contentStart, contentEnd - contentStart)]];
            if (name.length == 0) {
                name = [NSString stringWithFormat:@"第%@章", @(chapters.count + 1)];
            }
            [chapters addObject:[self chapterWithName:name content:content index:chapters.count]];
        }
    }
    else {
        //无章节结构:按固定长度分段,断点尽量落在换行处
        NSString *body = [self trimmed:text];
        NSUInteger loc = 0, part = 0;
        while (loc < body.length && part < kTxtMaxChapterCount) {
            NSUInteger len = MIN(kTxtFallbackChunkLength, body.length - loc);
            if (loc + len < body.length) {
                NSRange newline = [body rangeOfString:@"\n" options:NSBackwardsSearch range:NSMakeRange(loc, len)];
                if (newline.location != NSNotFound && newline.location > loc + len / 2) {
                    len = newline.location - loc;
                }
            }
            //避免截断代理对
            NSRange safe = [body rangeOfComposedCharacterSequencesForRange:NSMakeRange(loc, len)];
            NSString *content = [self trimmed:[body substringWithRange:safe]];
            part++;
            if (content.length > 0) {
                NSString *name = [NSString stringWithFormat:@"第%@部分", @(part)];
                [chapters addObject:[self chapterWithName:name content:content index:chapters.count]];
            }
            loc = NSMaxRange(safe);
        }
    }
    return chapters.copy;
}

+ (RDCharpterModel *)chapterWithName:(NSString *)name content:(NSString *)content index:(NSUInteger)index
{
    RDCharpterModel *model = [[RDCharpterModel alloc] init];
    model.charpterId = index + 1;
    model.name = name;
    model.content = content.length > 0 ? content : @" ";
    return model;
}

+ (NSString *)trimmed:(NSString *)string
{
    return [string stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

@end
