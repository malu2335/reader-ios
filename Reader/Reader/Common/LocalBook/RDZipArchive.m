//
//  RDZipArchive.m
//  Reader
//

#import "RDZipArchive.h"
#import <zlib.h>

//ZIP 签名
static const uint32_t kZipEOCDSignature = 0x06054b50;
static const uint32_t kZipCentralSignature = 0x02014b50;
static const uint32_t kZipLocalSignature = 0x04034b50;

//恶意/损坏归档防护预算:条目数量、单条目解压后大小、整包累计解压量(仅内存路径)、
//压缩比上限(deflate 理论极限约 1032:1,留有余量)。stored 落盘路径(书籍源文件)
//允许更大的单文件上限,但仍需有界,避免声明离谱大小耗尽磁盘。
static const NSUInteger kRDZipMaxEntryCount = 20000;
static const unsigned long long kRDZipMaxEntryUncompressedBytes = 200ull * 1024 * 1024;
static const unsigned long long kRDZipMaxArchiveUncompressedBytes = 1024ull * 1024 * 1024;
static const double kRDZipMaxCompressionRatio = 1200.0;
static const unsigned long long kRDZipMaxExtractedFileBytes = 3ull * 1024 * 1024 * 1024;

@interface RDZipEntry : NSObject
@property (nonatomic,copy) NSString *name;
@property (nonatomic,assign) uint16_t method;
@property (nonatomic,assign) uint32_t crc;
@property (nonatomic,assign) uint32_t compressedSize;
@property (nonatomic,assign) uint32_t uncompressedSize;
@property (nonatomic,assign) uint32_t localHeaderOffset;
@end
@implementation RDZipEntry
@end

@interface RDZipArchive ()
@property (nonatomic,strong) NSData *data;
@property (nonatomic,strong) NSDictionary <NSString *,RDZipEntry *>*entries;
@property (nonatomic,copy) NSArray <NSString *>*entryNames;
/// 累计解压量只按「不同条目」计一次,避免漫画重读/预取同一页耗尽预算导致空白
@property (nonatomic,assign) unsigned long long totalDecompressedBytes;
@property (nonatomic,strong) NSMutableSet <NSString *>*chargedEntryNames;
@property (nonatomic,strong) NSObject *budgetLock;
@end

@implementation RDZipArchive

static uint16_t readU16(const uint8_t *p) { return (uint16_t)(p[0] | (p[1] << 8)); }
static uint32_t readU32(const uint8_t *p) { return (uint32_t)(p[0] | (p[1] << 8) | (p[2] << 16) | ((uint32_t)p[3] << 24)); }

- (instancetype)initWithPath:(NSString *)path
{
    self = [super init];
    if (self) {
        _budgetLock = [[NSObject alloc] init];
        _chargedEntryNames = [NSMutableSet set];
        _data = [NSData dataWithContentsOfFile:path options:NSDataReadingMappedIfSafe error:nil];
        if (_data.length < 22 || ![self parseCentralDirectory]) {
            return nil;
        }
    }
    return self;
}

- (BOOL)parseCentralDirectory
{
    const uint8_t *bytes = self.data.bytes;
    NSUInteger length = self.data.length;

    //从尾部反向找 EOCD(注释最长 65535 字节)
    NSInteger scanStart = (NSInteger)length - 22;
    NSInteger scanEnd = MAX(0, scanStart - 65535);
    NSInteger eocd = -1;
    for (NSInteger i = scanStart; i >= scanEnd; i--) {
        if (readU32(bytes + i) == kZipEOCDSignature) {
            eocd = i;
            break;
        }
    }
    if (eocd < 0) {
        return NO;
    }
    uint16_t total = readU16(bytes + eocd + 10);
    uint32_t centralOffset = readU32(bytes + eocd + 16);
    if (centralOffset >= length) {
        return NO;
    }
    if (total > kRDZipMaxEntryCount) {
        // 条目数量本身就是资源耗尽手段之一(如 10 万条空文件),直接拒绝整个归档
        return NO;
    }

    NSMutableDictionary *entries = [NSMutableDictionary dictionary];
    NSMutableArray *names = [NSMutableArray array];
    NSUInteger cursor = centralOffset;
    for (uint16_t i = 0; i < total; i++) {
        if (cursor + 46 > length || readU32(bytes + cursor) != kZipCentralSignature) {
            break;
        }
        RDZipEntry *entry = [[RDZipEntry alloc] init];
        entry.method = readU16(bytes + cursor + 10);
        entry.crc = readU32(bytes + cursor + 16);
        entry.compressedSize = readU32(bytes + cursor + 20);
        entry.uncompressedSize = readU32(bytes + cursor + 24);
        uint16_t nameLen = readU16(bytes + cursor + 28);
        uint16_t extraLen = readU16(bytes + cursor + 30);
        uint16_t commentLen = readU16(bytes + cursor + 32);
        entry.localHeaderOffset = readU32(bytes + cursor + 42);
        if (cursor + 46 + nameLen > length) {
            break;
        }
        NSString *name = [[NSString alloc] initWithBytes:bytes + cursor + 46 length:nameLen encoding:NSUTF8StringEncoding];
        if (!name) {
            name = [[NSString alloc] initWithBytes:bytes + cursor + 46 length:nameLen encoding:NSISOLatin1StringEncoding];
        }
        if (name.length > 0 && ![name hasSuffix:@"/"]) {
            entry.name = name;
            entries[name] = entry;
            [names addObject:name];
        }
        cursor += 46 + nameLen + extraLen + commentLen;
    }
    self.entries = entries.copy;
    self.entryNames = names.copy;
    return names.count > 0;
}

- (NSData *)dataForEntry:(NSString *)name
{
    RDZipEntry *entry = self.entries[name];
    if (!entry) {
        return nil;
    }
    //单条目/累计解压量与压缩比预算:防止声明离谱大小或高倍率炸弹式条目
    if (entry.uncompressedSize > kRDZipMaxEntryUncompressedBytes) {
        return nil;
    }
    if (entry.method == 8) {
        double ratio = (double)entry.uncompressedSize / (double)MAX(entry.compressedSize, (uint32_t)1);
        if (ratio > kRDZipMaxCompressionRatio) {
            return nil;
        }
    }
    // 同一条目重复读取(漫画往返翻页/预取)不再重复计入累计预算
    @synchronized (self.budgetLock) {
        BOOL alreadyCharged = [self.chargedEntryNames containsObject:name];
        if (!alreadyCharged &&
            self.totalDecompressedBytes + entry.uncompressedSize > kRDZipMaxArchiveUncompressedBytes) {
            return nil;
        }
    }
    const uint8_t *bytes = self.data.bytes;
    NSUInteger length = self.data.length;
    NSUInteger offset = entry.localHeaderOffset;
    if (offset + 30 > length || readU32(bytes + offset) != kZipLocalSignature) {
        return nil;
    }
    //local header 的 name/extra 长度可能与 central 不同,以 local 为准
    uint16_t nameLen = readU16(bytes + offset + 26);
    uint16_t extraLen = readU16(bytes + offset + 28);
    NSUInteger dataStart = offset + 30 + nameLen + extraLen;
    if (dataStart + entry.compressedSize > length) {
        return nil;
    }
    NSData *compressed = [self.data subdataWithRange:NSMakeRange(dataStart, entry.compressedSize)];
    NSData *result = nil;
    if (entry.method == 0) {
        result = compressed;
    }
    else if (entry.method == 8) {
        result = [self inflate:compressed expectedSize:entry.uncompressedSize];
    }
    if (!result) {
        return nil;
    }
    //central directory 中的 CRC32 校验:损坏/篡改/截断归档在此处即失败,不放行到解析层
    if ((uint32_t)crc32(0, result.bytes, (uInt)result.length) != entry.crc) {
        return nil;
    }
    @synchronized (self.budgetLock) {
        if (![self.chargedEntryNames containsObject:name]) {
            // 再次检查:实际解压长度可能大于声明 uncompressedSize
            if (self.totalDecompressedBytes + result.length > kRDZipMaxArchiveUncompressedBytes) {
                return nil;
            }
            self.totalDecompressedBytes += result.length;
            [self.chargedEntryNames addObject:name];
        }
    }
    return result;
}

- (NSData *)inflate:(NSData *)compressed expectedSize:(uint32_t)expectedSize
{
    if (compressed.length == 0) {
        return [NSData data];
    }
    //expectedSize 来自归档自身声明,不可全信;真正的硬上限是单条目预算
    NSUInteger capacityHint = MIN((NSUInteger)expectedSize, (NSUInteger)kRDZipMaxEntryUncompressedBytes);
    z_stream stream;
    memset(&stream, 0, sizeof(stream));
    //windowBits 为负:raw deflate(ZIP 条目无 zlib 头)
    if (inflateInit2(&stream, -MAX_WBITS) != Z_OK) {
        return nil;
    }
    NSMutableData *output = [NSMutableData dataWithLength:MAX(capacityHint, (NSUInteger)4096)];
    stream.next_in = (Bytef *)compressed.bytes;
    stream.avail_in = (uInt)compressed.length;
    int status = Z_OK;
    while (status == Z_OK) {
        if (stream.total_out >= output.length) {
            if (output.length >= kRDZipMaxEntryUncompressedBytes) {
                //实际解压量已越过硬上限,声明的 expectedSize 撒谎也不再放行(真正的炸弹防线)
                inflateEnd(&stream);
                return nil;
            }
            //increaseLengthBy: 传入的是增量,不是新总长;先算目标总长再回推增量,避免下溢
            NSUInteger targetLength = MIN(output.length + (output.length / 2 + 4096), (NSUInteger)kRDZipMaxEntryUncompressedBytes);
            [output increaseLengthBy:targetLength - output.length];
        }
        stream.next_out = (Bytef *)output.mutableBytes + stream.total_out;
        stream.avail_out = (uInt)(output.length - stream.total_out);
        status = inflate(&stream, Z_NO_FLUSH);
    }
    NSUInteger totalOut = stream.total_out;
    inflateEnd(&stream);
    if (status != Z_STREAM_END) {
        return nil;
    }
    output.length = totalOut;
    return output;
}

- (NSString *)entryMatchingName:(NSString *)name
{
    if (self.entries[name]) {
        return name;
    }
    for (NSString *candidate in self.entryNames) {
        if ([candidate caseInsensitiveCompare:name] == NSOrderedSame) {
            return candidate;
        }
    }
    return nil;
}

- (BOOL)writeEntry:(NSString *)name toFile:(NSString *)path
{
    RDZipEntry *entry = self.entries[name];
    if (!entry || path.length == 0) {
        return NO;
    }
    if (entry.method != 0) {
        // deflate 条目量级小(json/封面),回退内存解压(已带资源预算与 CRC 校验)
        NSData *data = [self dataForEntry:name];
        return data ? [data writeToFile:path atomically:YES] : NO;
    }
    // stored 条目 compressedSize == uncompressedSize,单独放宽到更大的落盘上限(书籍源文件)
    if (entry.uncompressedSize > kRDZipMaxExtractedFileBytes) {
        return NO;
    }
    const uint8_t *bytes = self.data.bytes;
    NSUInteger length = self.data.length;
    NSUInteger offset = entry.localHeaderOffset;
    if (offset + 30 > length || readU32(bytes + offset) != kZipLocalSignature) {
        return NO;
    }
    uint16_t nameLen = readU16(bytes + offset + 26);
    uint16_t extraLen = readU16(bytes + offset + 28);
    NSUInteger dataStart = offset + 30 + nameLen + extraLen;
    if (dataStart + entry.compressedSize > length) {
        return NO;
    }
    // 分块从 mmap 数据拷贝到目标文件,峰值内存恒定;边拷贝边累计 CRC32,校验损坏/篡改归档
    NSString *tmp = [path stringByAppendingString:@".part"];
    [[NSFileManager defaultManager] removeItemAtPath:tmp error:nil];
    if (![[NSFileManager defaultManager] createFileAtPath:tmp contents:nil attributes:nil]) {
        return NO;
    }
    NSFileHandle *out = [NSFileHandle fileHandleForWritingAtPath:tmp];
    if (!out) {
        return NO;
    }
    BOOL ok = YES;
    uLong runningCrc = crc32(0, NULL, 0);
    const NSUInteger chunk = 1024 * 1024;
    @try {
        NSUInteger written = 0;
        while (written < entry.compressedSize) {
            NSUInteger n = MIN(chunk, entry.compressedSize - written);
            @autoreleasepool {
                runningCrc = crc32(runningCrc, bytes + dataStart + written, (uInt)n);
                NSData *slice = [NSData dataWithBytes:bytes + dataStart + written length:n];
                [out writeData:slice];
            }
            written += n;
        }
        [out closeFile];
    }
    @catch (NSException *exception) {
        ok = NO;
    }
    if (!ok || (uint32_t)runningCrc != entry.crc) {
        [[NSFileManager defaultManager] removeItemAtPath:tmp error:nil];
        return NO;
    }
    [[NSFileManager defaultManager] removeItemAtPath:path error:nil];
    return [[NSFileManager defaultManager] moveItemAtPath:tmp toPath:path error:nil];
}

@end

#pragma mark - RDZipWriter

@interface RDZipRecordedEntry : NSObject
@property (nonatomic,strong) NSData *nameData;
@property (nonatomic,assign) uint32_t crc;
@property (nonatomic,assign) uint32_t size;
@property (nonatomic,assign) uint32_t offset;
@end
@implementation RDZipRecordedEntry
@end

@interface RDZipWriter ()
@property (nonatomic,strong) NSFileHandle *handle;
@property (nonatomic,strong) NSMutableArray <RDZipRecordedEntry *>*records;
@property (nonatomic,assign) uint32_t offset;
@property (nonatomic,assign) BOOL finalized;
@end

@implementation RDZipWriter

static void appendU16(NSMutableData *data, uint16_t value) {
    uint8_t bytes[2] = {(uint8_t)(value & 0xFF), (uint8_t)(value >> 8)};
    [data appendBytes:bytes length:2];
}
static void appendU32(NSMutableData *data, uint32_t value) {
    uint8_t bytes[4] = {(uint8_t)(value & 0xFF), (uint8_t)((value >> 8) & 0xFF), (uint8_t)((value >> 16) & 0xFF), (uint8_t)(value >> 24)};
    [data appendBytes:bytes length:4];
}

- (instancetype)initWithPath:(NSString *)path
{
    self = [super init];
    if (self) {
        [[NSFileManager defaultManager] removeItemAtPath:path error:nil];
        if (![[NSFileManager defaultManager] createFileAtPath:path contents:nil attributes:nil]) {
            return nil;
        }
        _handle = [NSFileHandle fileHandleForWritingAtPath:path];
        if (!_handle) {
            return nil;
        }
        _records = [NSMutableArray array];
    }
    return self;
}

- (BOOL)addEntryWithName:(NSString *)name data:(NSData *)data
{
    if (self.finalized || name.length == 0 || !data) {
        return NO;
    }
    NSData *nameData = [name dataUsingEncoding:NSUTF8StringEncoding];
    uint32_t crc = (uint32_t)crc32(0, data.bytes, (uInt)data.length);
    if (data.length > UINT32_MAX || self.offset > UINT32_MAX - data.length - 1024) {
        return NO;   //不支持 zip64
    }

    RDZipRecordedEntry *record = [[RDZipRecordedEntry alloc] init];
    record.nameData = nameData;
    record.crc = crc;
    record.size = (uint32_t)data.length;
    record.offset = self.offset;
    [self.records addObject:record];

    //local file header:method 0(store),UTF-8 名字标志位 0x0800
    NSMutableData *header = [NSMutableData data];
    appendU32(header, 0x04034b50);
    appendU16(header, 20);
    appendU16(header, 0x0800);
    appendU16(header, 0);
    appendU16(header, 0);   //time
    appendU16(header, 0x21); //date(1980-01-01)
    appendU32(header, crc);
    appendU32(header, record.size);
    appendU32(header, record.size);
    appendU16(header, (uint16_t)nameData.length);
    appendU16(header, 0);
    [header appendData:nameData];

    @try {
        [self.handle writeData:header];
        [self.handle writeData:data];
    }
    @catch (NSException *exception) {
        return NO;
    }
    self.offset += header.length + data.length;
    return YES;
}

- (BOOL)addEntryWithName:(NSString *)name fileAtPath:(NSString *)path
{
    if (self.finalized || name.length == 0 || path.length == 0) {
        return NO;
    }
    NSDictionary *attrs = [[NSFileManager defaultManager] attributesOfItemAtPath:path error:nil];
    unsigned long long fileSize = attrs.fileSize;
    if (fileSize == 0) {
        return NO;
    }
    if (fileSize > UINT32_MAX || self.offset > UINT32_MAX - fileSize - 1024) {
        return NO;   //不支持 zip64
    }
    NSData *nameData = [name dataUsingEncoding:NSUTF8StringEncoding];

    //第一遍:分块算 crc32
    NSInputStream *crcStream = [NSInputStream inputStreamWithFileAtPath:path];
    if (!crcStream) {
        return NO;
    }
    [crcStream open];
    uLong crc = crc32(0, NULL, 0);
    uint8_t buffer[256 * 1024];
    unsigned long long total = 0;
    while (crcStream.hasBytesAvailable) {
        NSInteger n = [crcStream read:buffer maxLength:sizeof(buffer)];
        if (n < 0) {
            [crcStream close];
            return NO;
        }
        if (n == 0) {
            break;
        }
        crc = crc32(crc, buffer, (uInt)n);
        total += (unsigned long long)n;
    }
    [crcStream close];
    if (total != fileSize) {
        return NO;   //读取期间文件被改动
    }

    RDZipRecordedEntry *record = [[RDZipRecordedEntry alloc] init];
    record.nameData = nameData;
    record.crc = (uint32_t)crc;
    record.size = (uint32_t)fileSize;
    record.offset = self.offset;

    NSMutableData *header = [NSMutableData data];
    appendU32(header, 0x04034b50);
    appendU16(header, 20);
    appendU16(header, 0x0800);
    appendU16(header, 0);
    appendU16(header, 0);    //time
    appendU16(header, 0x21); //date(1980-01-01)
    appendU32(header, record.crc);
    appendU32(header, record.size);
    appendU32(header, record.size);
    appendU16(header, (uint16_t)nameData.length);
    appendU16(header, 0);
    [header appendData:nameData];

    //第二遍:分块拷贝正文
    NSInputStream *copyStream = [NSInputStream inputStreamWithFileAtPath:path];
    if (!copyStream) {
        return NO;
    }
    [copyStream open];
    BOOL ok = YES;
    @try {
        [self.handle writeData:header];
        while (copyStream.hasBytesAvailable) {
            NSInteger n = [copyStream read:buffer maxLength:sizeof(buffer)];
            if (n < 0) {
                ok = NO;
                break;
            }
            if (n == 0) {
                break;
            }
            @autoreleasepool {
                [self.handle writeData:[NSData dataWithBytes:buffer length:n]];
            }
        }
    }
    @catch (NSException *exception) {
        ok = NO;
    }
    [copyStream close];
    if (!ok) {
        return NO;
    }
    [self.records addObject:record];
    self.offset += header.length + record.size;
    return YES;
}

- (BOOL)finalizeArchive
{
    if (self.finalized) {
        return NO;
    }
    self.finalized = YES;

    NSMutableData *central = [NSMutableData data];
    for (RDZipRecordedEntry *record in self.records) {
        appendU32(central, 0x02014b50);
        appendU16(central, 20);          //made by
        appendU16(central, 20);          //version needed
        appendU16(central, 0x0800);      //UTF-8 名字
        appendU16(central, 0);           //method: store
        appendU16(central, 0);           //time
        appendU16(central, 0x21);        //date(1980-01-01)
        appendU32(central, record.crc);
        appendU32(central, record.size);
        appendU32(central, record.size);
        appendU16(central, (uint16_t)record.nameData.length);
        appendU16(central, 0);           //extra
        appendU16(central, 0);           //comment
        appendU16(central, 0);           //disk
        appendU16(central, 0);           //internal attrs
        appendU32(central, 0);           //external attrs
        appendU32(central, record.offset);
        [central appendData:record.nameData];
    }

    NSMutableData *eocd = [NSMutableData data];
    appendU32(eocd, 0x06054b50);
    appendU16(eocd, 0);                                  //disk number
    appendU16(eocd, 0);                                  //central dir disk
    appendU16(eocd, (uint16_t)self.records.count);
    appendU16(eocd, (uint16_t)self.records.count);
    appendU32(eocd, (uint32_t)central.length);
    appendU32(eocd, self.offset);                        //central dir 起始偏移
    appendU16(eocd, 0);                                  //comment length

    @try {
        [self.handle writeData:central];
        [self.handle writeData:eocd];
        [self.handle closeFile];
    }
    @catch (NSException *exception) {
        return NO;
    }
    return YES;
}

@end
