//
//  RDReadParser.m
//  Reader
//
//  Created by yuenov on 2019/11/21.
//  Copyright © 2019 yuenov. All rights reserved.
//

#import "RDReadParser.h"
#import <CoreText/CoreText.h>
#import "RDFontManager.h"
#import "RDReplaceRule.h"

@implementation RDReadParser

/// 正文开头若已含章节名,去掉以免与分页拼入的标题重复
+ (NSString *)p_stripLeadingTitle:(NSString *)title fromContent:(NSString *)content
{
    if (title.length == 0 || content.length == 0) {
        return content ?: @"";
    }
    NSCharacterSet *ws = [NSCharacterSet whitespaceAndNewlineCharacterSet];
    NSString *t = [title stringByTrimmingCharactersInSet:ws];
    if (t.length == 0) {
        return content;
    }
    // 去掉开头空白
    NSUInteger i = 0;
    while (i < content.length && [ws characterIsMember:[content characterAtIndex:i]]) {
        i++;
    }
    if (i >= content.length) {
        return content;
    }
    NSString *body = [content substringFromIndex:i];
    // 1) 正文直接以章节名开头
    if ([body hasPrefix:t]) {
        NSString *rest = [body substringFromIndex:t.length];
        NSUInteger j = 0;
        while (j < rest.length && [ws characterIsMember:[rest characterAtIndex:j]]) {
            j++;
        }
        return j < rest.length ? [rest substringFromIndex:j] : @"";
    }
    // 2) 第一行等于章节名(常见 txt 章首自带标题)
    NSRange nl = [body rangeOfCharacterFromSet:[NSCharacterSet newlineCharacterSet]];
    NSString *firstLine = (nl.location != NSNotFound) ? [body substringToIndex:nl.location] : body;
    firstLine = [firstLine stringByTrimmingCharactersInSet:ws];
    if ([firstLine isEqualToString:t]) {
        if (nl.location == NSNotFound) {
            return @"";
        }
        NSString *rest = [body substringFromIndex:nl.location];
        NSUInteger j = 0;
        while (j < rest.length && [ws characterIsMember:[rest characterAtIndex:j]]) {
            j++;
        }
        return j < rest.length ? [rest substringFromIndex:j] : @"";
    }
    return content;
}

+(void)paginateWithContent:(NSString *)content charpter:(NSString *)charpter bounds:(CGRect)bounds complete:(void(^)(NSAttributedString *content,NSArray *pages))complete
{
    // 默认同步:UIPageViewController dataSource 契约要求立刻返回页面
    [self paginateWithContent:content charpter:charpter bounds:bounds preferBackground:NO complete:complete];
}

+(void)paginateWithContent:(NSString *)content
                  charpter:(NSString *)charpter
                    bounds:(CGRect)bounds
          preferBackground:(BOOL)preferBackground
                  complete:(void(^)(NSAttributedString *content,NSArray *pages))complete
{
    if (preferBackground) {
        [self paginateWithContent:content
                         charpter:charpter
                           bounds:bounds
                            queue:dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0)
                    allowTruncate:NO
                      cancelCheck:nil
                         complete:complete];
    } else {
        [self paginateWithContent:content
                         charpter:charpter
                           bounds:bounds
                            queue:nil
                    allowTruncate:YES
                      cancelCheck:nil
                         complete:complete];
    }
}

+(void)paginateWithContent:(NSString *)content
                  charpter:(NSString *)charpter
                    bounds:(CGRect)bounds
                     queue:(dispatch_queue_t)queue
             allowTruncate:(BOOL)allowTruncate
               cancelCheck:(BOOL(^)(void))cancelCheck
                  complete:(void(^)(NSAttributedString *content,NSArray *pages))complete
{
    void (^work)(void) = ^{
        if (cancelCheck && cancelCheck()) {
            return;
        }
        // legado 风格净化:分页前应用启用中的替换规则(正文 + 标题各自 scope)
        NSString *cleaned = [[RDReplaceRuleStore sharedInstance] applyToText:content ?: @""];
        if (cancelCheck && cancelCheck()) {
            return;
        }
        NSString *cleanTitle = [[RDReplaceRuleStore sharedInstance] applyToTitle:charpter ?: @""];
        cleaned = [self p_stripLeadingTitle:cleanTitle fromContent:cleaned];
        if (charpter.length && ![charpter isEqualToString:cleanTitle]) {
            cleaned = [self p_stripLeadingTitle:charpter fromContent:cleaned];
        }

        // 仅同步兜底路径允许保护性截断;邻章预分页与后台路径永不截断(P1-FE-01)
        static const NSUInteger kMaxSyncPaginateCharacters = 500000;
        if (allowTruncate && cleaned.length > kMaxSyncPaginateCharacters) {
            NSRange safe = [cleaned rangeOfComposedCharacterSequencesForRange:NSMakeRange(0, kMaxSyncPaginateCharacters)];
            cleaned = [[cleaned substringWithRange:safe] stringByAppendingString:@"\n\n(内容过长,本章已在此截断;可尝试拆章或缩小字号后重开)"];
        }

        if (cancelCheck && cancelCheck()) {
            return;
        }

        NSMutableArray *pageArray = [NSMutableArray array];
        NSMutableAttributedString *attrString = [[NSMutableAttributedString alloc] init];
        if (cleanTitle.length > 0) {
            NSMutableAttributedString *titleAttr = [[NSMutableAttributedString alloc] initWithString:[cleanTitle stringByAppendingString:@"\n"]];
            NSDictionary *charpterAttribute = [RDReadParser paraserChapterFontArrribute:[RDReadConfigManager sharedInstance]];
            [titleAttr setAttributes:charpterAttribute range:NSMakeRange(0, titleAttr.length)];
            [attrString appendAttributedString:titleAttr];
        }

        NSMutableAttributedString *contentAttr = [[NSMutableAttributedString alloc] initWithString:cleaned ?: @""];
        NSDictionary *contentAttribute = [RDReadParser paraserFontArrribute:[RDReadConfigManager sharedInstance]];
        if (contentAttr.length > 0) {
            [contentAttr setAttributes:contentAttribute range:NSMakeRange(0, contentAttr.length)];
        }
        [attrString appendAttributedString:contentAttr];

        CTFramesetterRef frameSetter = CTFramesetterCreateWithAttributedString((__bridge CFAttributedStringRef) attrString);
        CGPathRef path = CGPathCreateWithRect(bounds, NULL);

        int currentOffset = 0;
        int currentInnerOffset = 0;
        BOOL hasMorePages = YES;
        int preventDeadLoopSign = currentOffset;
        int samePlaceRepeatCount = 0;
        NSUInteger loopCount = 0;

        while (hasMorePages) {
            // 每 8 页检查一次 cancel,使快速改字号能真正停掉旧 work(P2-FE-02)
            if ((loopCount++ & 0x7) == 0 && cancelCheck && cancelCheck()) {
                CGPathRelease(path);
                CFRelease(frameSetter);
                return;
            }
            if (preventDeadLoopSign == currentOffset) {
                ++samePlaceRepeatCount;
            } else {
                samePlaceRepeatCount = 0;
                preventDeadLoopSign = currentOffset;
            }
            if (samePlaceRepeatCount > 1) {
                if (pageArray.count == 0) {
                    [pageArray addObject:@(currentOffset)];
                } else {
                    NSUInteger lastOffset = [[pageArray lastObject] integerValue];
                    if (lastOffset != (NSUInteger)currentOffset) {
                        [pageArray addObject:@(currentOffset)];
                    }
                }
                break;
            }

            [pageArray addObject:@(currentOffset)];
            CTFrameRef frame = CTFramesetterCreateFrame(frameSetter, CFRangeMake(currentInnerOffset, 0), path, NULL);
            CFRange range = CTFrameGetVisibleStringRange(frame);
            if ((range.location + range.length) != attrString.length) {
                currentOffset += range.length;
                currentInnerOffset += range.length;
            } else {
                hasMorePages = NO;
            }
            if (frame) CFRelease(frame);
        }

        CGPathRelease(path);
        CFRelease(frameSetter);
        if (cancelCheck && cancelCheck()) {
            return;
        }
        NSAttributedString *outAttr = attrString.copy;
        NSArray *outPages = pageArray.copy;
        if (queue) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if (cancelCheck && cancelCheck()) {
                    return;
                }
                if (complete) {
                    complete(outAttr, outPages);
                }
            });
        } else if (complete) {
            complete(outAttr, outPages);
        }
    };

    if (queue) {
        dispatch_async(queue, work);
    } else {
        work();
    }
}

+(NSString *)getShowContent:(NSString *)content charpter:(NSString *)charpter
{
    return [[NSString stringWithFormat:@"%@\n",charpter] stringByAppendingString:content];
}

+(NSDictionary *)paraserFontArrribute:(RDReadConfigManager *)config
{
    NSMutableDictionary *dict = [NSMutableDictionary dictionary];
    dict[NSForegroundColorAttributeName] = config.fontColor;
    dict[NSFontAttributeName] = [RDFontManager readFontWithName:config.fontName size:config.fontSize];
    NSMutableParagraphStyle *paragraphStyle = [[NSMutableParagraphStyle alloc] init];
    paragraphStyle.lineSpacing = config.lineSpace;
//    paragraphStyle.alignment = NSTextAlignmentJustified;
//    paragraphStyle.firstLineHeadIndent = config.firstLineHeadIndent
    paragraphStyle.paragraphSpacing = config.lineSpace+2;
    dict[NSParagraphStyleAttributeName] = paragraphStyle;
    return [dict copy];
}

/// 解析章节属性
+(NSDictionary *)paraserChapterFontArrribute:(RDReadConfigManager *)config
{
    NSMutableDictionary *dict = [NSMutableDictionary dictionary];
    dict[NSForegroundColorAttributeName] = config.fontColor;
    dict[NSFontAttributeName] = [RDFontManager readFontWithName:config.fontName size:config.chapterFontSize];
    NSMutableParagraphStyle *paragraphStyle = [[NSMutableParagraphStyle alloc] init];
    paragraphStyle.lineSpacing = config.chapterLineSpace;
    paragraphStyle.alignment = NSTextAlignmentJustified;
    dict[NSParagraphStyleAttributeName] = paragraphStyle;
    return [dict copy];
}

@end
