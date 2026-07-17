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

+(void)paginateWithContent:(NSString *)content charpter:(NSString *)charpter bounds:(CGRect)bounds complete:(void(^)(NSAttributedString *content,NSArray *pages))complete
{
    // legado 风格净化:分页前应用启用中的替换规则
    NSString *cleaned = [[RDReplaceRuleStore sharedInstance] applyToText:content ?: @""];

    // 分页目前是主线程同步 CoreText 排版(P1-11);正常章节耗时很短,但异常解析或恶意文件
    // 可能产生几 MB 的单"章",一次性排版会长时间阻塞主线程甚至触发 watchdog 强杀。
    // 这里先加一道硬上限兜底,真正的后台可取消分页是更大的架构改动,留作后续。
    static const NSUInteger kMaxPaginateCharacters = 300000;
    if (cleaned.length > kMaxPaginateCharacters) {
        NSRange safe = [cleaned rangeOfComposedCharacterSequencesForRange:NSMakeRange(0, kMaxPaginateCharacters)];
        cleaned = [[cleaned substringWithRange:safe] stringByAppendingString:@"\n\n(内容过长,本章已在此截断)"];
    }

    NSMutableArray *pageArray = [NSMutableArray array];
    CTFramesetterRef frameSetter;
    CGPathRef path;
    
    NSMutableAttributedString *attrString = [[NSMutableAttributedString  alloc] initWithString:[charpter stringByAppendingString:@"\n"]];
    NSDictionary *charpterAttribute = [RDReadParser paraserChapterFontArrribute:[RDReadConfigManager sharedInstance]];
    [attrString setAttributes:charpterAttribute range:NSMakeRange(0, attrString.length)];
    
    NSMutableAttributedString *contentAttr = [[NSMutableAttributedString  alloc] initWithString:cleaned];
    NSDictionary *contentAttribute = [RDReadParser paraserFontArrribute:[RDReadConfigManager sharedInstance]];
    [contentAttr setAttributes:contentAttribute range:NSMakeRange(0, contentAttr.length)];
    
    
    [attrString appendAttributedString:contentAttr];
    
    
    frameSetter = CTFramesetterCreateWithAttributedString((__bridge CFAttributedStringRef) attrString);
    path = CGPathCreateWithRect(bounds, NULL);
    
    int currentOffset = 0;
    int currentInnerOffset = 0;
    BOOL hasMorePages = YES;
    // 防止死循环，如果在同一个位置获取CTFrame超过2次，则跳出循环
    int preventDeadLoopSign = currentOffset;
    int samePlaceRepeatCount = 0;
    
    while (hasMorePages) {
        if (preventDeadLoopSign == currentOffset) {
            
            ++samePlaceRepeatCount;
            
        } else {
            
            samePlaceRepeatCount = 0;
        }
        
        if (samePlaceRepeatCount > 1) {
            // 退出循环前检查一下最后一页是否已经加上
            if (pageArray.count == 0) {
                [pageArray addObject:@(currentOffset)];
            }
            else {
                
                NSUInteger lastOffset = [[pageArray lastObject] integerValue];
                
                if (lastOffset != currentOffset) {
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
            // 已经分完，提示跳出循环
            hasMorePages = NO;
        }
        if (frame) CFRelease(frame);
    }
    
    CGPathRelease(path);
    CFRelease(frameSetter);
    if (complete) {
        complete(attrString,pageArray.copy);
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
