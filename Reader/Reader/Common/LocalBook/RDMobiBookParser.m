//
//  RDMobiBookParser.m
//  Reader
//

#import "RDMobiBookParser.h"
#import "RDBookTextUtil.h"
#import "RDCharpterModel.h"
#import "RDImportPolicy.h"

//PalmDOC 压缩方式
static const uint16_t kMobiCompressionNone = 1;
static const uint16_t kMobiCompressionPalmDoc = 2;
static const uint16_t kMobiCompressionHuff = 17480;

@implementation RDMobiBookParser

static uint16_t readBE16(const uint8_t *p) { return (uint16_t)((p[0] << 8) | p[1]); }
static uint32_t readBE32(const uint8_t *p) { return ((uint32_t)p[0] << 24) | ((uint32_t)p[1] << 16) | ((uint32_t)p[2] << 8) | p[3]; }

+ (RDLocalBookParseResult *)parseFileAtPath:(NSString *)path error:(NSString **)errorMessage
{
    NSDictionary *attrs = [[NSFileManager defaultManager] attributesOfItemAtPath:path error:nil];
    unsigned long long fileSize = attrs.fileSize;
    if (attrs == nil) {
        if (errorMessage) *errorMessage = @"无法读取 MOBI 文件";
        return nil;
    }
    if (fileSize > kRDImportMaxMobiFileBytes) {
        if (errorMessage) {
            *errorMessage = [NSString stringWithFormat:@"MOBI 文件过大(上限 %llu MB),无法导入",
                             kRDImportMaxMobiFileBytes / (1024ull * 1024ull)];
        }
        return nil;
    }
    NSData *data = [NSData dataWithContentsOfFile:path options:NSDataReadingMappedIfSafe error:nil];
    const uint8_t *bytes = data.bytes;
    if (data.length < 78 + 8) {
        if (errorMessage) *errorMessage = @"不是有效的 MOBI 文件";
        return nil;
    }

    //---- PalmDB 头:type/creator 位于 60/64,记录数在 76 ----
    char type[5] = {0}, creator[5] = {0};
    memcpy(type, bytes + 60, 4);
    memcpy(creator, bytes + 64, 4);
    BOOL isMobi = (strncmp(type, "BOOK", 4) == 0 && strncmp(creator, "MOBI", 4) == 0);
    BOOL isPalmDoc = (strncmp(type, "TEXt", 4) == 0 && strncmp(creator, "REAd", 4) == 0);
    if (!isMobi && !isPalmDoc) {
        if (errorMessage) *errorMessage = @"不是有效的 MOBI 文件";
        return nil;
    }
    uint16_t numRecords = readBE16(bytes + 76);
    if (numRecords == 0 || 78 + (NSUInteger)numRecords * 8 > data.length) {
        if (errorMessage) *errorMessage = @"MOBI 文件已损坏";
        return nil;
    }

    //记录偏移表
    NSMutableArray <NSNumber *>*offsets = [NSMutableArray arrayWithCapacity:numRecords + 1];
    for (uint16_t i = 0; i < numRecords; i++) {
        [offsets addObject:@(readBE32(bytes + 78 + i * 8))];
    }
    [offsets addObject:@(data.length)];

    NSData *(^recordData)(NSUInteger) = ^NSData *(NSUInteger index) {
        if (index >= numRecords) {
            return nil;
        }
        NSUInteger start = offsets[index].unsignedIntegerValue;
        NSUInteger end = offsets[index + 1].unsignedIntegerValue;
        if (start >= end || end > data.length) {
            return nil;
        }
        return [data subdataWithRange:NSMakeRange(start, end - start)];
    };

    //---- 记录 0:PalmDOC 头 + MOBI 头 ----
    NSData *record0 = recordData(0);
    const uint8_t *r0 = record0.bytes;
    if (record0.length < 16) {
        if (errorMessage) *errorMessage = @"MOBI 文件已损坏";
        return nil;
    }
    uint16_t compression = readBE16(r0);
    uint32_t textLength = readBE32(r0 + 4);
    uint16_t textRecordCount = readBE16(r0 + 8);
    uint16_t encryption = readBE16(r0 + 12);

    if (encryption != 0) {
        if (errorMessage) *errorMessage = @"该文件带有 DRM 保护,无法导入";
        return nil;
    }
    if (compression == kMobiCompressionHuff) {
        if (errorMessage) *errorMessage = @"暂不支持 HUFF/CDIC 压缩的 MOBI,可用 Calibre 转换后导入";
        return nil;
    }
    if (compression != kMobiCompressionNone && compression != kMobiCompressionPalmDoc) {
        if (errorMessage) *errorMessage = @"无法识别的 MOBI 压缩格式";
        return nil;
    }

    //---- MOBI 头(可选,PalmDOC 无此头)----
    uint32_t textEncoding = 65001;
    uint16_t extraDataFlags = 0;
    NSString *fullName = nil;
    NSString *author = nil;
    NSData *coverData = nil;
    if (isMobi && record0.length >= 24 && memcmp(r0 + 16, "MOBI", 4) == 0) {
        uint32_t mobiHeaderLength = readBE32(r0 + 20);
        if (record0.length >= 32) {
            textEncoding = readBE32(r0 + 28);
        }
        //extra data flags:MOBI 头足够长时位于记录 0 偏移 0xF2
        if (mobiHeaderLength >= 0xE4 && record0.length >= 0xF4) {
            extraDataFlags = readBE16(r0 + 0xF2);
        }
        //书名(两个 uint32_t 直接相加会在 32 位内溢出回绕,绕过越界检查;先转 64 位再判断)
        if (record0.length >= 92) {
            uint32_t nameOffset = readBE32(r0 + 84);
            uint32_t nameLength = readBE32(r0 + 88);
            unsigned long long nameEnd = (unsigned long long)nameOffset + (unsigned long long)nameLength;
            if (nameLength > 0 && nameOffset <= record0.length && nameEnd <= record0.length) {
                NSData *nameData = [record0 subdataWithRange:NSMakeRange(nameOffset, nameLength)];
                fullName = [RDBookTextUtil stringFromData:nameData encoding:[self encodingFromMobi:textEncoding]];
            }
        }
        //EXTH:作者与封面
        uint32_t exthFlags = record0.length >= 132 ? readBE32(r0 + 128) : 0;
        if ((exthFlags & 0x40) && record0.length > 16 + mobiHeaderLength + 12) {
            NSUInteger exthStart = 16 + mobiHeaderLength;
            if (memcmp(r0 + exthStart, "EXTH", 4) == 0) {
                uint32_t exthCount = readBE32(r0 + exthStart + 8);
                NSUInteger cursor = exthStart + 12;
                uint32_t coverOffset = UINT32_MAX;
                for (uint32_t i = 0; i < exthCount && cursor + 8 <= record0.length; i++) {
                    uint32_t recType = readBE32(r0 + cursor);
                    uint32_t recLen = readBE32(r0 + cursor + 4);
                    if (recLen < 8 || cursor + recLen > record0.length) {
                        break;
                    }
                    NSData *value = [record0 subdataWithRange:NSMakeRange(cursor + 8, recLen - 8)];
                    if (recType == 100 && !author) {
                        author = [RDBookTextUtil stringFromData:value encoding:[self encodingFromMobi:textEncoding]];
                    }
                    else if (recType == 503 && !fullName) {
                        fullName = [RDBookTextUtil stringFromData:value encoding:[self encodingFromMobi:textEncoding]];
                    }
                    else if (recType == 201 && value.length >= 4) {
                        coverOffset = readBE32((const uint8_t *)value.bytes);
                    }
                    cursor += recLen;
                }
                //封面:firstImageIndex(记录 0 偏移 108)+ coverOffset;同样先转 64 位再相加防溢出
                if (coverOffset != UINT32_MAX && record0.length >= 112) {
                    uint32_t firstImageIndex = readBE32(r0 + 108);
                    unsigned long long coverRecordIndex = (unsigned long long)firstImageIndex + (unsigned long long)coverOffset;
                    if (firstImageIndex != UINT32_MAX && coverRecordIndex < numRecords) {
                        coverData = recordData((NSUInteger)coverRecordIndex);
                    }
                }
            }
        }
    }

    //---- 解压正文 ----
    // textLength 是文件自身声明值,仅作为容量提示,不可信;真正硬上限见 kRDImportMaxMobiTextBytes,
    // 每次 append 前检查剩余预算,PalmDoc 解压过程中也强制不越过上限。
    NSUInteger textHardCap = (NSUInteger)kRDImportMaxMobiTextBytes;
    NSUInteger textCapacityHint = MIN((NSUInteger)textLength, textHardCap);
    NSMutableData *rawText = [NSMutableData dataWithCapacity:textCapacityHint];
    for (uint16_t i = 1; i <= textRecordCount && i < numRecords; i++) {
        NSData *record = recordData(i);
        if (!record) {
            break;
        }
        NSUInteger usableLength = record.length - [self trailingEntriesSize:record extraDataFlags:extraDataFlags];
        if (usableLength > record.length) {
            usableLength = record.length;
        }
        NSData *payload = [record subdataWithRange:NSMakeRange(0, usableLength)];
        NSData *chunk = nil;
        if (compression == kMobiCompressionPalmDoc) {
            NSUInteger remaining = textHardCap > rawText.length ? (textHardCap - rawText.length) : 0;
            if (remaining == 0) {
                if (errorMessage) {
                    *errorMessage = [NSString stringWithFormat:@"MOBI 正文过大(上限 %llu MB),无法导入",
                                     kRDImportMaxMobiTextBytes / (1024ull * 1024ull)];
                }
                return nil;
            }
            chunk = [self decompressPalmDoc:payload maxOutputBytes:remaining];
            if (!chunk) {
                if (errorMessage) {
                    *errorMessage = [NSString stringWithFormat:@"MOBI 正文过大或损坏(上限 %llu MB),无法导入",
                                     kRDImportMaxMobiTextBytes / (1024ull * 1024ull)];
                }
                return nil;
            }
        }
        else {
            chunk = payload;
        }
        if (rawText.length + chunk.length > textHardCap) {
            if (errorMessage) {
                *errorMessage = [NSString stringWithFormat:@"MOBI 正文过大(上限 %llu MB),无法导入",
                                 kRDImportMaxMobiTextBytes / (1024ull * 1024ull)];
            }
            return nil;
        }
        [rawText appendData:chunk];
        if (rawText.length >= textLength && textLength > 0) {
            break;
        }
    }
    if (textLength > 0 && rawText.length > textLength && textLength <= textHardCap) {
        rawText.length = textLength;
    }
    if (rawText.length == 0) {
        if (errorMessage) *errorMessage = @"MOBI 中没有可阅读的内容";
        return nil;
    }

    NSString *html = [RDBookTextUtil stringFromData:rawText encoding:[self encodingFromMobi:textEncoding]];
    NSArray *chapters = [self splitChaptersFromHTML:html];
    if (chapters.count == 0) {
        if (errorMessage) *errorMessage = @"MOBI 中没有可阅读的内容";
        return nil;
    }

    RDLocalBookParseResult *result = [[RDLocalBookParseResult alloc] init];
    result.title = fullName;
    result.author = author;
    result.chapters = chapters;
    result.coverData = coverData;
    return result;
}

#pragma mark - PalmDOC LZ77

/// PalmDoc LZ77 解压;maxOutputBytes 为输出硬上限,超出返回 nil(防止扩张炸弹)
+ (NSData *)decompressPalmDoc:(NSData *)input maxOutputBytes:(NSUInteger)maxOutputBytes
{
    const uint8_t *inBytes = input.bytes;
    NSUInteger inLength = input.length;
    NSUInteger capacity = MIN(inLength * 4, maxOutputBytes > 0 ? maxOutputBytes : inLength * 4);
    NSMutableData *output = [NSMutableData dataWithCapacity:MAX(capacity, (NSUInteger)64)];
    NSUInteger i = 0;
    while (i < inLength) {
        if (output.length >= maxOutputBytes) {
            return nil;
        }
        uint8_t c = inBytes[i++];
        if (c == 0x00) {
            if (output.length + 1 > maxOutputBytes) {
                return nil;
            }
            [output appendBytes:&c length:1];
        }
        else if (c <= 0x08) {
            //c 个原样字节
            NSUInteger count = MIN((NSUInteger)c, inLength - i);
            if (output.length + count > maxOutputBytes) {
                return nil;
            }
            [output appendBytes:inBytes + i length:count];
            i += count;
        }
        else if (c <= 0x7F) {
            if (output.length + 1 > maxOutputBytes) {
                return nil;
            }
            [output appendBytes:&c length:1];
        }
        else if (c <= 0xBF) {
            //两字节回溯引用
            if (i >= inLength) {
                break;
            }
            uint16_t pair = (uint16_t)((c << 8) | inBytes[i++]);
            NSUInteger distance = (pair >> 3) & 0x7FF;
            NSUInteger length = (pair & 0x07) + 3;
            if (distance == 0 || distance > output.length) {
                continue;
            }
            if (output.length + length > maxOutputBytes) {
                return nil;
            }
            //逐字节复制,允许目标区与来源区重叠
            NSUInteger start = output.length - distance;
            for (NSUInteger j = 0; j < length; j++) {
                uint8_t byte = ((const uint8_t *)output.bytes)[start + j];
                [output appendBytes:&byte length:1];
            }
        }
        else {
            //0xC0-0xFF:空格 + (c ^ 0x80)
            if (output.length + 2 > maxOutputBytes) {
                return nil;
            }
            uint8_t space = ' ';
            uint8_t ch = c ^ 0x80;
            [output appendBytes:&space length:1];
            [output appendBytes:&ch length:1];
        }
    }
    return output;
}

//记录尾部附加数据长度(extra data flags)
+ (NSUInteger)trailingEntriesSize:(NSData *)record extraDataFlags:(uint16_t)flags
{
    const uint8_t *bytes = record.bytes;
    NSUInteger size = record.length;
    NSUInteger removed = 0;
    uint16_t highFlags = flags >> 1;
    while (highFlags) {
        if (highFlags & 1) {
            removed += [self trailingEntrySize:bytes end:size - removed];
        }
        highFlags >>= 1;
    }
    if (flags & 1) {
        //多字节字符尾块:最后一个字节低 2 位 + 1
        if (size - removed > 0) {
            removed += (bytes[size - removed - 1] & 0x03) + 1;
        }
    }
    return MIN(removed, size);
}

//尾部反向变长整数
+ (NSUInteger)trailingEntrySize:(const uint8_t *)bytes end:(NSUInteger)end
{
    NSUInteger result = 0;
    NSUInteger bitpos = 0;
    NSUInteger pos = end;
    while (pos > 0) {
        uint8_t v = bytes[pos - 1];
        result |= (NSUInteger)(v & 0x7F) << bitpos;
        bitpos += 7;
        pos--;
        if ((v & 0x80) || bitpos >= 28) {
            break;
        }
    }
    return MIN(result, end);
}

#pragma mark - 章节切分

+ (NSArray <RDCharpterModel *>*)splitChaptersFromHTML:(NSString *)html
{
    //优先按 mobi 分页符切,其次按 h1-h3
    NSArray <NSString *>*pieces = nil;
    NSRegularExpression *pagebreak = [NSRegularExpression regularExpressionWithPattern:@"<\\s*(?:mbp|mobi)\\s*:\\s*pagebreak[^>]*>"
                                                                               options:NSRegularExpressionCaseInsensitive
                                                                                 error:nil];
    NSArray *matches = [pagebreak matchesInString:html options:0 range:NSMakeRange(0, html.length)];
    if (matches.count >= 1) {
        NSMutableArray *parts = [NSMutableArray array];
        NSUInteger last = 0;
        for (NSTextCheckingResult *match in matches) {
            [parts addObject:[html substringWithRange:NSMakeRange(last, match.range.location - last)]];
            last = NSMaxRange(match.range);
        }
        [parts addObject:[html substringFromIndex:last]];
        pieces = parts;
    }
    else {
        //按标题分:在每个 h1-h3 开始处断开
        NSRegularExpression *heading = [NSRegularExpression regularExpressionWithPattern:@"<h[1-3][^>]*>"
                                                                                 options:NSRegularExpressionCaseInsensitive
                                                                                   error:nil];
        NSArray *headMatches = [heading matchesInString:html options:0 range:NSMakeRange(0, html.length)];
        if (headMatches.count >= 2) {
            NSMutableArray *parts = [NSMutableArray array];
            NSUInteger last = 0;
            for (NSTextCheckingResult *match in headMatches) {
                if (match.range.location > last) {
                    [parts addObject:[html substringWithRange:NSMakeRange(last, match.range.location - last)]];
                }
                last = match.range.location;
            }
            [parts addObject:[html substringFromIndex:last]];
            pieces = parts;
        }
        else {
            pieces = @[html];
        }
    }

    NSMutableArray <RDCharpterModel *>*chapters = [NSMutableArray array];
    for (NSString *piece in pieces) {
        NSString *content = [RDBookTextUtil plainTextFromHTML:piece];
        if (content.length == 0) {
            continue;
        }
        NSString *name = [RDBookTextUtil headingFromHTML:piece];
        if (name.length == 0) {
            NSString *plain = [RDBookTextUtil plainTextFromHTML:piece];
            name = [RDBookTextUtil titleCandidateFromPlainText:plain];
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
    //单章且过长时按长度再切,避免一章几 MB 分页卡顿
    if (chapters.count == 1 && chapters.firstObject.content.length > 20000) {
        NSString *content = chapters.firstObject.content;
        NSMutableArray *split = [NSMutableArray array];
        NSUInteger loc = 0;
        while (loc < content.length) {
            NSUInteger len = MIN((NSUInteger)10000, content.length - loc);
            NSRange safe = [content rangeOfComposedCharacterSequencesForRange:NSMakeRange(loc, len)];
            RDCharpterModel *model = [[RDCharpterModel alloc] init];
            model.charpterId = split.count + 1;
            model.name = [NSString stringWithFormat:@"第%@部分", @(split.count + 1)];
            model.content = [content substringWithRange:safe];
            [split addObject:model];
            loc = NSMaxRange(safe);
        }
        return split.copy;
    }
    return chapters.copy;
}

+ (NSStringEncoding)encodingFromMobi:(uint32_t)textEncoding
{
    switch (textEncoding) {
        case 1252:
            return NSWindowsCP1252StringEncoding;
        case 932:
            return NSShiftJISStringEncoding;
        case 65001:
        default:
            return NSUTF8StringEncoding;
    }
}

@end
