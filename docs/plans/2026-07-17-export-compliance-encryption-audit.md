# 加密文稿与出口合规审计（纸羽轻阅）
> 审计日期：2026-07-17  
> 分支：`codex/jianyue-offline-reader`  
> 对应计划：`docs/plans/2026-07-17-external-document-import.md` Task 8

## 1. 审计范围
- 目录：`Reader/Reader/**/*.{m,mm,h,c,cpp,hpp}`
- 依赖：`Reader/Podfile`、`Reader/Podfile.lock`
- 关键字：CommonCrypto、CCCrypt、CC_MD5/SHA、CryptoKit、SecKey、AES/3DES、openssl/BoringSSL/libsodium、sqlite3_key、setCipherKey、SQLCipher 相关
- 说明：仓库中已从 Target 排除的遗留网络/AI 源码若未编入二进制，不单独作为“App 使用了加密”的充分条件；本审计同时记录 Target 内可达代码与已链接依赖。

## 2. App Target 内疑似加密相关命中摘要

| 位置 | 用途判断 | 是否运行可达 |
|---|---|---|
| `Common/LocalBook/RDLocalBookManager.m` 使用 `CC_MD5` | 本地书籍文件/目录内容哈希，用于去重生成 `bookId` | 是（导入路径） |
| `Common/Category/NSData+rd_wid.m` / `NSString+rd_wid.m` 中 `CC_MD5`/`CC_SHA*` | 通用摘要工具方法 | 是（哈希工具） |
| ~~同上文件中 `CCCrypt` AES/3DES~~ | 已于 2026-07-17 删除 | 已移除 |
| `Common/LocalBook/RDMobiBookParser.m` 读取 MOBI `encryption` 字段 | 检测受 DRM/加密的 MOBI 并拒绝，**不解密** | 是 |
| `Common/LocalBook/RDZipArchive.m` CRC32 / 解压 | 完整性校验与解压，非加密算法 | 是 |
| 无 `CryptoKit` / `SecKey` 加解密业务 / 无自研密码学 | — | 无命中 |
| 无 OpenSSL/BoringSSL/libsodium 直接依赖 | — | 无命中 |
| 无 `sqlite3_key` / `setCipherKey` / `PRAGMA key` | WCDB 未启用库级加密 | 无命中 |

## 3. AES/3DES helper（已清理）

2026-07-17 已从 `NSData+rd_wid` / `NSString+rd_wid` 删除全部 AES/3DES 声明与实现，并移除 `CommonCryptor` / `CommonHMAC` 引用。清理前调用点核查结果（仅定义、无业务调用）如下（历史记录）：

- `Common/Category/NSString+rd_wid.m:97: - (NSString *)encryptedWithAESUsingKey:(NSString *)key andIV:(NSData *)iv`
- `Common/Category/NSString+rd_wid.m:99: NSData *encrypted = [[self dataUsingEncoding:NSUTF8StringEncoding] encryptedWithAESUsingKey:key andI`
- `Common/Category/NSString+rd_wid.m:105: - (NSString *)decryptedWithAESUsingKey:(NSString *)key andIV:(NSData *)iv`
- `Common/Category/NSString+rd_wid.m:107: NSData *decrypted = [[NSData base64DecodedDataForString:self] decryptedWithAESUsingKey:key andIV:iv]`
- `Common/Category/NSString+rd_wid.m:113: - (NSString *)encryptedWith3DESUsingKey:(NSString *)key andIV:(NSData *)iv`
- `Common/Category/NSString+rd_wid.m:115: NSData *encrypted = [[self dataUsingEncoding:NSUTF8StringEncoding] encryptedWith3DESUsingKey:key and`
- `Common/Category/NSString+rd_wid.m:121: - (NSString *)decryptedWith3DESUsingKey:(NSString *)key andIV:(NSData *)iv`
- `Common/Category/NSString+rd_wid.m:123: NSData *decrypted = [[NSData base64DecodedDataForString:self] decryptedWith3DESUsingKey:key andIV:iv`
- `Common/Category/NSData+rd_wid.m:58: - (NSData *)encryptedWithAESUsingKey:(NSString *)key andIV:(NSData *)iv`
- `Common/Category/NSData+rd_wid.m:87: - (NSData *)decryptedWithAESUsingKey:(NSString *)key andIV:(NSData *)iv`
- `Common/Category/NSData+rd_wid.m:116: - (NSData *)encryptedWith3DESUsingKey:(NSString *)key andIV:(NSData *)iv`
- `Common/Category/NSData+rd_wid.m:145: - (NSData *)decryptedWith3DESUsingKey:(NSString *)key andIV:(NSData *)iv`

结论（清理后）：Target 业务代码不再包含 AES/3DES 实现。MD5 用于书籍去重哈希；仍保留单向摘要与压缩/校验。

## 4. CocoaPods / 链接依赖

| 依赖 | 版本（Podfile.lock） | 与加密关系 | 本 App 实际用法 |
|---|---|---|---|
| WCDB | 1.0.7.5 | 依赖 WCDBOptimizedSQLCipher / SQLiteRepairKit | 本地 SQLite 数据库，**未设置 cipher key** |
| WCDBOptimizedSQLCipher | 1.2.1 | SQLCipher 衍生 SQLite 引擎 | 作为 WCDB 的 SQLite 实现链接；App 未调用库加密 API |
| SQLiteRepairKit | 1.2.2 | 修复工具，随 WCDB | 无业务侧加密配置 |
| 其余 UI/图片/手势 Pods | 见 lock | 无加密职责 | 布局、刷新、图片解码等 |
| libwebp | 1.1.0 | 图像编解码 | 封面 WebP |

未发现 AFNetworking/YTKNetwork 等在当前离线产品路径中作为活跃网络栈使用；`RDOfflineURLProtocol` 拦截 http/https。TLS 由系统提供的能力即便存在也不会被本 App 业务主动使用。

## 5. 加密 vs 非加密处理

| 能力 | 归类 |
|---|---|
| MD5/SHA 文件/内容哈希 | 单向摘要，通常不单独等同于“使用加密算法”申报项的主要用途 |
| CRC32 | 完整性校验 |
| Base64 / gzip / zlib | 编码与压缩 |
| 无密码 ZIP/CBZ | 归档 |
| 系统文件保护 / 代码签名 | 平台能力 |
| AES/3DES helper | **已删除** |

## 6. App Store Connect 选项建议

可选项回顾：
1. 专有或非标准加密算法  
2. 代替在 Apple 操作系统中使用或访问加密，或与这些操作同时使用的标准加密算法  
3. 兼用 1 与 2  
4. 不属于上述的任意一种算法  

**当前结论（2026-07-17 清理 AES 后）：**

- **App Store Connect 选项：4（不属于上述的任意一种算法）**
- 理由：
  - 业务可达路径仅使用摘要（MD5）做去重，以及压缩/校验；
  - 不发起 TLS 业务请求；
  - 不启用 SQLCipher 库加密（无 `setCipherKey` / `sqlite3_key`）；
  - AES/3DES 死代码已删除。
- **保留意见：** WCDBOptimizedSQLCipher 仍作为 WCDB 的 SQLite 引擎链接，但 App 未启用库级加密。本审计**不构成法律意见**。

## 7. 关于 `ITSAppUsesNonExemptEncryption`

已在 `Reader/Reader/Resource/Info.plist` 写入：

```xml
<key>ITSAppUsesNonExemptEncryption</key>
<false/>
```

Archive / 上传时 App Store Connect 加密文稿回答应与此一致（选项 4 / 不使用非豁免加密）。

## 8. 原始关键字扫描摘录（节选）

### `Common/Category/NSData+rd_wid.h`
- L15 [AES]: `- (NSData *)encryptedWithAESUsingKey:(NSString*)key andIV:(NSData*)iv;`
- L16 [AES]: `- (NSData *)decryptedWithAESUsingKey:(NSString*)key andIV:(NSData*)iv;`
- L17 [3DES]: `- (NSData *)encryptedWith3DESUsingKey:(NSString*)key andIV:(NSData*)iv;`
- L18 [3DES]: `- (NSData *)decryptedWith3DESUsingKey:(NSString*)key andIV:(NSData*)iv;`

### `Common/Category/NSData+rd_wid.m`
- L6 [NSData\+rd_wid]: `#import "NSData+rd_wid.h"`
- L7 [CommonCrypto]: `#import <CommonCrypto/CommonDigest.h>`
- L8 [CommonCrypto]: `#import <CommonCrypto/CommonCryptor.h>`
- L9 [CommonCrypto]: `#import <CommonCrypto/CommonHMAC.h>`
- L58 [AES]: `- (NSData *)encryptedWithAESUsingKey:(NSString *)key andIV:(NSData *)iv`
- L64 [AES]: `NSMutableData *encryptedData = [NSMutableData dataWithLength:self.length + kCCBlockSizeAES128];`
- L66 [CCCrypt]: `CCCryptorStatus status = CCCrypt(kCCEncrypt,                    // kCCEncrypt or kCCDecrypt`
- L67 [kCCAlgorithm]: `kCCAlgorithmAES128,`
- L87 [AES]: `- (NSData *)decryptedWithAESUsingKey:(NSString *)key andIV:(NSData *)iv`
- L93 [AES]: `NSMutableData *decryptedData = [NSMutableData dataWithLength:self.length + kCCBlockSizeAES128];`
- L95 [CCCrypt]: `CCCryptorStatus result = CCCrypt(kCCDecrypt,                    // kCCEncrypt or kCCDecrypt`
- L96 [kCCAlgorithm]: `kCCAlgorithmAES128,`
- L116 [3DES]: `- (NSData *)encryptedWith3DESUsingKey:(NSString *)key andIV:(NSData *)iv`
- L122 [3DES]: `NSMutableData *encryptedData = [NSMutableData dataWithLength:self.length + kCCBlockSize3DES];`
- L124 [CCCrypt]: `CCCryptorStatus result = CCCrypt(kCCEncrypt,                    // kCCEncrypt or kCCDecrypt`

### `Common/Category/NSString+rd_wid.h`
- L30 [AES]: `- (NSString*)encryptedWithAESUsingKey:(NSString*)key andIV:(NSData*)iv;`
- L31 [AES]: `- (NSString*)decryptedWithAESUsingKey:(NSString*)key andIV:(NSData*)iv;`
- L32 [3DES]: `- (NSString*)encryptedWith3DESUsingKey:(NSString*)key andIV:(NSData*)iv;`
- L33 [3DES]: `- (NSString*)decryptedWith3DESUsingKey:(NSString*)key andIV:(NSData*)iv;`

### `Common/Category/NSString+rd_wid.m`
- L97 [AES]: `- (NSString *)encryptedWithAESUsingKey:(NSString *)key andIV:(NSData *)iv`
- L99 [AES]: `NSData *encrypted = [[self dataUsingEncoding:NSUTF8StringEncoding] encryptedWithAESUsingKey:key andIV:iv];`
- L105 [AES]: `- (NSString *)decryptedWithAESUsingKey:(NSString *)key andIV:(NSData *)iv`
- L107 [AES]: `NSData *decrypted = [[NSData base64DecodedDataForString:self] decryptedWithAESUsingKey:key andIV:iv];`
- L113 [3DES]: `- (NSString *)encryptedWith3DESUsingKey:(NSString *)key andIV:(NSData *)iv`
- L115 [3DES]: `NSData *encrypted = [[self dataUsingEncoding:NSUTF8StringEncoding] encryptedWith3DESUsingKey:key andIV:iv];`
- L121 [3DES]: `- (NSString *)decryptedWith3DESUsingKey:(NSString *)key andIV:(NSData *)iv`
- L123 [3DES]: `NSData *decrypted = [[NSData base64DecodedDataForString:self] decryptedWith3DESUsingKey:key andIV:iv];`

### `Common/LocalBook/RDLocalBookManager.m`
- L7 [CommonCrypto]: `#import <CommonCrypto/CommonDigest.h>`
- L564 [CC_MD5]: `unsigned char digest[CC_MD5_DIGEST_LENGTH];`
- L565 [CC_MD5]: `CC_MD5(data.bytes, (CC_LONG)data.length, digest);`
- L581 [CC_MD5]: `CC_MD5_CTX ctx;`
- L582 [CC_MD5]: `CC_MD5_Init(&ctx);`
- L595 [CC_MD5]: `CC_MD5_Update(&ctx, buffer, (CC_LONG)n);`
- L601 [CC_MD5]: `unsigned char digest[CC_MD5_DIGEST_LENGTH];`
- L602 [CC_MD5]: `CC_MD5_Final(digest, &ctx);`
- L613 [CC_MD5]: `CC_MD5_CTX ctx;`
- L614 [CC_MD5]: `CC_MD5_Init(&ctx);`
- L620 [CC_MD5]: `CC_MD5_Update(&ctx, nameData.bytes, (CC_LONG)nameData.length);`
- L635 [CC_MD5]: `CC_MD5_Update(&ctx, buffer, (CC_LONG)n);`
- L642 [CC_MD5]: `unsigned char digest[CC_MD5_DIGEST_LENGTH];`
- L643 [CC_MD5]: `CC_MD5_Final(digest, &ctx);`

### `Sections/Bookshelf/Catalog/RDCatalogController.m`
- L113 [AES]: `- (void)aesedecing {`

### `Sections/Bookshelf/Read/View/Catalog/RDReadCatalogHeader.h`
- L14 [AES]: `-(void)aesedecing;`

### `Sections/Bookshelf/Read/View/Catalog/RDReadCatalogHeader.m`
- L59 [AES]: `if ([self.delegate respondsToSelector:@selector(aesedecing)]) {`
- L60 [AES]: `[self.delegate aesedecing];`

### `Sections/Bookshelf/Read/View/Catalog/RDReadCatalogView.m`
- L116 [AES]: `- (void)aesedecing {`

