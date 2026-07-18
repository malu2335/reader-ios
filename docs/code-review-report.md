# Reader iOS 系统性代码审查报告

> **状态更新（2026-07-17 之后）**  
> 本报告记录审查当时的发现。下列项在后续提交中**已处理或缓解**，阅读问题清单时请对照现状代码：  
> - **P0-B1 API Key 明文 / 备份泄露**：Key 已迁 **Keychain**；磁盘 JSON 与备份 zip 中 `apiKey` 故意为空。  
> - **P0-F1 硬编码本机 debug 日志路径**：生产路径中的 `/Users/luma/...debug-603e3d.log` 已移除。  
> - 产品展示名已改为 **轻阅**；主线能力以本地书 + AI 翻译 + 备份为主。  
> - 公开仓库：https://github.com/malu2335/reader-ios（`master` 已包含 feature 合并结果）。  
> 其余架构债、遗留在线模块、测试覆盖等条目仍可作为后续排期参考，**不保证分数与清单仍全部适用**。

| 项 | 内容 |
|----|------|
| 分支 | `feature/code-review-ai-translate`（已合并进 `master`） |
| 基线 | 审查时相对 `master` @ `7a21cea` 的工作区 |
| 审查日期 | 2026-07-17 |
| 应用类型 | iOS 本地优先阅读器（Objective-C + WCDB + CocoaPods） |
| 审查原则 | 从业务链路出发；不凭空猜测；未确认项标注「需要进一步验证」 |

> **架构映射说明**  
> 本仓库**不是**典型 Web 前后端分离。下表将用户审查维度映射到实际模块：  
> | 用户维度 | 本仓库对应 |
> |----------|------------|
> | 前端 | UIKit 页面 / 阅读控件 / 设置与 AI UI |
> | 后端 | 本地 Manager、Service(API)、业务编排（导入/备份/翻译） |
> | 数据库 | WCDB（`book` SQLite：`chapter`/`read`/`history`）+ JSON/NSKeyedArchiver |
> | 接口链路 | YTKNetwork 在线 API、NSURLSession AI 翻译、系统文档导入/分享 |
> | 权限 | iOS 沙盒 / DocumentPicker / ATS；无多角色账号体系 |

---

## 1. 整体代码质量结论

**结论：中等偏下，功能可交付但架构债与安全债集中。**

- **优势**
  - 本地书链路（导入 → 解析 → WCDB 章节 → 阅读 → 备份）主路径清晰，`bookId < 0` 与网络路径隔离设计合理。
  - AI 翻译将「请求构建 / 响应解析 / 可注入 transport」与 UI 解耦，AIHarness 对六协议与备份条目有可重复验证。
  - 备份布局对齐 legado（`bookshelf.json` / `config.json` / `books/`）并扩展 `ai_config.json`，方向正确。

- **核心问题**
  1. **密钥与隐私**：AI API Key 明文落盘并进入可分享 zip；书库 SQLite 无加密。
  2. **生产残留调试代码**：多处写死本机路径 `.cursor/debug-603e3d.log`。
  3. **产品形态与代码形态不一致**：Tab 仅「书架+设置」，但 Discover/Library/Search 与 `http://yuenov.com` 全量仍在二进制中，ATS 放开任意 HTTP。
  4. **数据层与并发**：WCDB 无统一串行队列；章节 bulk insert 存在逐条查询（N+1）；超大文件整文件 MD5/解析易 OOM。
  5. **测试缺口**：除 AI Foundation harness 外，导入/恢复/阅读分页/清空等核心路径几乎无自动化。

- **质量评分（主观，1–5）**

| 维度 | 分 | 说明 |
|------|----|------|
| 功能完整度（本地读） | 3.5 | 主路径可用 |
| 安全与隐私 | 1.5 | Key/备份/HTTP/调试日志 |
| 架构清晰度 | 2.5 | 新旧双轨、大文件上帝类 |
| 数据一致性 | 2.5 | 部分恢复、无事务边界 |
| 可测试性 | 2.0 | 仅 AI harness |
| 可维护性 | 2.5 | 拼写债务 + 遗留模块 |

---

## 2. 问题清单（按严重度）

严重度定义：

| 级别 | 含义 |
|------|------|
| **P0** | 安全/数据丢失/生产必炸或合规风险，应立即处理 |
| **P1** | 核心链路错误、明显性能/一致性风险，下一迭代必修 |
| **P2** | 可维护性/边界缺陷，应排期 |
| **P3** | 命名/风格/长期清理 |

每个问题格式：位置 · 描述 · 触发 · 影响 · 根因 · 方案 · 模块 · 回归

---

### 2.1 前端（UIKit）问题清单

#### P0-F1 生产代码写入开发者本机绝对路径日志
- **位置**：`AppDelegate.m`（`RDWriteDebugLog`）、`RDUtilities.m`、`LEEAlert.m`（同类 logPath）
- **描述**：`/Users/luma/code/reader-ios/.cursor/debug-603e3d.log` 硬编码，启动等路径写文件。
- **触发**：任意安装包启动 / 触发 LEEAlert / Utilities 日志点。
- **影响**：无意义 I/O、失败静默；若路径碰巧可写可能泄露 UI 状态；代码评审与上架风险。
- **根因**：调试埋点未剥离。
- **方案**：删除或 `#if DEBUG` + 相对缓存目录；禁止绝对用户路径。
- **模块**：Application / Util / Vender
- **回归**：Release 包 grep 无 `debug-603e3d`、`/Users/luma`；启动无该路径写文件。

#### P1-F1 翻译按钮依赖 Menu 转发（已修但脆弱）
- **位置**：`RDReadTopBar` → `RDMenuView` → `RDReadPageViewController`
- **描述**：`topBar.delegate = menu`，若 Menu 未实现 `translateAction` 则 `respondsToSelector` 静默失败（曾发生）。
- **触发**：阅读菜单打开后点「翻译」。
- **影响**：功能看起来有按钮但无效果。
- **根因**：间接代理链无编译期约束。
- **方案**：保持 forwarder；建议 TopBar 协议方法在 Menu 用显式 required 转发，或 harness 持续断言 forward 存在（已有 `run_tests.sh` 结构检查）。
- **模块**：Read UI
- **回归**：AIHarness UI wiring；真机点翻译出现 loading/配置引导。

#### P1-F2 翻译无防抖 / 无取消 / Loading 与多请求竞态
- **位置**：`RDReadPageViewController.m` `translateAction`
- **描述**：快速连点会并发多个 `translateText`；后返回者覆盖先返回；无 `NSURLSessionTask` 取消。
- **触发**：弱网下连点「翻译」。
- **影响**：重复计费、UI 结果错乱、Loading 状态可能与请求不匹配。
- **根因**：无 in-flight 标志与 task 句柄。
- **方案**：`isTranslating` 门闩；保存/取消上一次 task；按钮置灰。
- **模块**：Read + RDAIClient
- **回归**：连点 5 次仅 1 次网络请求；取消后不弹旧结果。

#### P1-F3 本地书无章节时打开阅读可能失败且无统一 UX
- **位置**：`RDReadHelper.m` `beginReadWithBookDetail:`
- **描述**：无 `record.charpterModel` 时走 `RDCharpterManager`；`bookId<0` 无内容仅 toast「内容不存在」，不 push。
- **触发**：损坏导入、PDF 误入分页阅读器、章节表被清空但书架仍在。
- **影响**：点击书籍无页面，仅短暂 toast。
- **根因**：打开路径未按 `fileType`/本地完整性预检。
- **方案**：本地书打开前校验文件存在 + 章节或 PDF 分流；失败给出「重新导入」操作。
- **模块**：ReadHelper / Bookshelf
- **回归**：删章节表后点书；空 PDF 走 PDF 控制器。

#### P2-F1 `RDReadPageViewController` 上帝类（~886 行）
- **位置**：`Sections/Bookshelf/Read/RDReadPageViewController.m`
- **描述**：分页、目录、进度、主题 KVO、听书、翻译、章节更新、镜像页全部堆叠。
- **触发**：任意阅读功能迭代。
- **影响**：回归成本高、易漏代理转发（如 translate）。
- **根因**：历史演进未拆分。
- **方案**：拆 `RDReadTranslateCoordinator` / `RDReadSpeechCoordinator` / 分页数据源。
- **模块**：Read
- **回归**：翻页/听书/翻译/主题切换冒烟。

#### P2-F2 遗留 Discover/Library/Search UI 仍可从残入口进入
- **位置**：`Sections/Discover|Library|Search`；书架搜索相关 cell
- **描述**：Tab 已去掉，但模块与网络依赖仍在；存在重新触发在线能力的路径。
- **触发**：搜索入口、深链、历史代码导航。
- **影响**：用户以为纯本地却发起 HTTP；维护成本。
- **根因**：产品本地化未做「死代码删除或 feature flag」。
- **方案**：编译宏 `READER_ONLINE=0` 剥离，或删除不可达模块。
- **模块**：Sections + Service
- **回归**：全局搜索无可达 online VC；Instruments 无对 yuenov 请求（本地书路径）。

#### P2-F3 翻译结果截断 4000 字无用户提示
- **位置**：`RDReadPageViewController` translateAction
- **描述**：静默 `substringToIndex:4000`。
- **触发**：长页/整章翻译。
- **影响**：用户以为译了全文。
- **方案**：Toast「仅翻译前 4000 字」或分页翻译。
- **回归**：超长章翻译文案含提示。

#### P3-F1 全文 `charpter` 拼写债务
- **位置**：全局模型/表/API
- **描述**：chapter 误拼贯穿库表与 API。
- **影响**：新人上手成本；与外部 legado 字段映射易错。
- **方案**：长期别名层，不宜一次全量 rename。
- **回归**：映射单测。

---

### 2.2 「后端」/业务服务问题清单

#### P0-B1 AI API Key 明文存储并进入备份分享
- **位置**：`RDAIConfig.m` → `Documents/AIConfig/ai_config.json`；`RDBackupManager` `ai_config.json` 条目
- **描述**：`apiKey` 以 JSON 明文保存；备份 zip 经 UIActivity 可分享到任意 App。
- **触发**：配置 AI；备份到文件/AirDrop。
- **影响**：密钥泄露、账号盗用、合规风险。
- **根因**：未使用 Keychain；备份未脱敏。
- **方案**：Key 入 Keychain（已有 `UICKeyChainStore` Pod 未真正使用）；备份可选加密或排除 key / 仅导出 profile 元数据。
- **模块**：AI + Backup
- **回归**：文件系统无明文 key；备份 zip 无明文或需密码。

#### P1-B1 在线 API 基址 HTTP + ATS 任意加载
- **位置**：`RDGlobalModel.m`（`http://` + `yuenov.com`）；`Info.plist` `NSAllowsArbitraryLoads=true`
- **描述**：全应用允许明文 HTTP。
- **触发**：任意 YTK 请求；中间人。
- **影响**：章节内容/请求可被篡改窃听。
- **根因**：历史服务端 HTTP。
- **方案**：HTTPS + 收紧 ATS；本地模式禁用 host。
- **模块**：Network + Info.plist
- **回归**：ATS 关闭任意加载后本地路径仍可用；在线路径仅 HTTPS。

#### P1-B2 导入路径整文件读入内存 + MD5
- **位置**：`RDLocalBookManager importBookAtURL:`
- **描述**：`dataWithContentsOfURL` 后对整包 MD5、再写盘、再解析。
- **触发**：>100MB EPUB/TXT/MOBI。
- **影响**：峰值内存接近 2× 文件大小，易 jetsam。
- **根因**：用 MD5 做稳定 bookId 的实现选择。
- **方案**：流式哈希；解析尽量流式；大文件提示。
- **模块**：LocalBook
- **回归**：大文件导入内存曲线；重复导入仍同一 bookId。

#### P1-B3 章节 bulk insert 事务内 N+1 查询
- **位置**：`RDCharpterDataManager insertObjectsWithCharpters:`
- **描述**：对每个 chapter `getCharpterWithBookId:charpterId:` 再 insert/update。
- **触发**：上千章导入/恢复。
- **影响**：导入时间随章节数近似二次劣化。
- **根因**：缺少「先删后插」或批量 upsert。
- **方案**：本地重建用 `deleteAll` + batch insert；在线更新用差分。
- **模块**：Database
- **回归**：1000 章导入耗时对比。

#### P1-B4 备份恢复非原子、部分成功语义模糊
- **位置**：`RDBackupManager restoreFromURL:`
- **描述**：单本失败 `continue`；文件已写盘；最后 `restored` 与 `lastError` 并存；AI 配置在书籍循环后仍恢复。
- **触发**：zip 缺部分 books 文件；磁盘满。
- **影响**：书架半恢复；用户以为全成功或全失败。
- **根因**：无事务/无临时目录提交。
- **方案**：恢复到临时目录 → 校验 → 切换；结果结构体 `{success, failed[], aiRestored}`。
- **模块**：Backup
- **回归**：故意缺一本的 zip；UI 展示部分失败列表。

#### P1-B5 Gemini API Key 放在 URL Query
- **位置**：`RDAIClient requestForProfile:` Gemini 分支
- **描述**：`?key=` 查询参数；错误日志/代理日志易泄露。
- **触发**：Gemini/gemini格式翻译。
- **影响**：Key 出现在 access log、截图、崩溃面包屑。
- **方案**：优先 `x-goog-api-key` header（需确认目标兼容网关是否支持——**需要进一步验证**各兼容端点）。
- **模块**：AI
- **回归**：抓包 header 含 key、URL 无 key（或兼容模式可配置）。

#### P2-B1 `RDCharpterManager` 成功路径在 content 空时可能不回调 complete
- **位置**：`RDCharpterManager.m` 约 77–80、117–119 行
- **描述**：`model.content.length == 0` 时 toast 后 `return`，未 `complete(NO,nil)`。
- **触发**：在线章节内容接口返回空。
- **影响**：调用方挂起、HUD 已 hide 但上层无失败处理（**本地 bookId<0 不受影响**）。
- **根因**：错误路径遗漏回调。
- **方案**：所有出口 complete。
- **模块**：CharpterManager
- **回归**：Mock 空内容 API；调用方必进 complete。

#### P2-B2 配置持久化双轨
- **位置**：阅读配置 `RDModelAgent` NSKeyedArchiver；AI `JSON` 文件
- **描述**：两套序列化与路径约定。
- **影响**：备份/迁移逻辑分叉；测试要 mock 两套。
- **方案**：统一 SettingsStore（JSON 或单一归档目录）。
- **回归**：升级安装配置不丢。

#### P3-B1 未使用的 Keychain Pod
- **位置**：`UICKeyChainStore` 仅在部分 import
- **描述**：依赖引入但密钥仍写文件。
- **方案**：用起来或移除 Pod。

---

### 2.3 数据库问题清单

#### P1-D1 书库无加密且含全文 content
- **位置**：`RDDatabaseManager` Documents/`book`；`RDCharpterModel.content`
- **描述**：章节正文明文 SQLite；设备备份/越狱可读。
- **触发**：任意本地书导入后。
- **影响**：隐私（私人笔记式全文）。
- **方案**：WCDB/SQLCipher 口令；或 content 外置加密文件。
- **回归**：无口令无法直接 sqlite3 读 content。

#### P1-D2 `content` 参与复合索引
- **位置**：`RDCharpterModel.mm` `_bookId_content_index` on `(bookId, content)`
- **描述**：对大文本列建索引，写入放大、空间膨胀。
- **触发**：大批量章节插入。
- **影响**：导入变慢、DB 体积异常。
- **方案**：删除 content 索引；保留 `(bookId, charpterId)`；按需 `bookId` 单列。
- **回归**：explain query plan；导入体积对比。

#### P1-D3 `RDCharpterModel isEqual:` 仅比较 charpterId
- **位置**：`RDCharpterModel.mm`
- **描述**：`charpterId` 相同即 equal，**忽略 bookId**；且 `charpterId==0` 永不 equal。
- **触发**：多书同章节号在集合/去重/indexOfObject。
- **影响**：目录选中、数组去重串书（**需要进一步验证**阅读页 `indexOfObject:` 实际是否踩中）。
- **方案**：`bookId + charpterId`；primaryId 比较。
- **回归**：两书同 chapterId 的集合行为单测。

#### P2-D1 `primaryId` 惰性拼接无分隔符
- **位置**：`primaryId = bookId 字符串 + charpterId 字符串`
- **描述**：理论碰撞：book `-12` + chapter `3` vs book `-1` + chapter `23` → `"-123"`。
- **触发**：特定 id 组合。
- **影响**：章节互相覆盖。
- **根因**：无分隔符。
- **方案**：`"%@_%@"` 或固定宽度；迁移脚本。
- **回归**：构造碰撞 id 对插入后仍两条。

#### P2-D2 read/history 共用模型类、表结构演进弱
- **位置**：`RDBookDetailModel` 同时进 `read`/`history`
- **描述**：本地字段 `localPath`/`fileType` 与线上字段混杂；无 schema version。
- **触发**：字段新增后旧库。
- **影响**：WCDB 一般可加列，但业务默认值/兼容靠约定。
- **方案**：显式 migration + version 表。
- **回归**：旧版本库升级冒烟。

#### P2-D3 无外键 / 删除级联靠手工
- **位置**：删书 `removeLocalBook` / `removeBookFromBookShelf` + `deleteAllCharpter`
- **描述**：若只删 read 不删 chapter 产生孤儿章节。
- **触发**：异常中断清空流程。
- **影响**：DB 膨胀、错书内容。
- **方案**：单一 `BookRepository.deleteBook` 事务；定期 orphan 清理。
- **回归**：删书后 chapter 表无残留。

#### P3-D1 表名 `chapter` 与代码 `charpter` 不一致
- **位置**：`kCharpterTable = @"chapter"`
- **影响**：可读性。

---

### 2.4 完整业务链路问题

#### 链路 A：本地导入 → 书架 → 阅读
```
DocumentPicker/OpenURL
  → RDLocalBookManager.importBookAtURL
  → MD5 bookId(<0) → LocalBooks 落盘 → Parser → WCDB chapters
  → RDReadRecordManager.insertOrReplace
  → Notification → Bookshelf reload
  → RDReadHelper → RDReadPageViewController / RDPdfReadController
```
| 问题 | 级别 | 说明 |
|------|------|------|
| 大文件内存 | P1 | 见 P1-B2 |
| 重复导入 | OK | 同 MD5 复用记录 |
| 并发多文件导入 | P1 | 共用全局队列+DB，无导入队列串行化，**需要进一步验证**交错写冲突 |
| PDF | OK | 专用控制器 |
| 无章节本地书打开 | P1 | 见 P1-F3 |

#### 链路 B：备份 → 分享 → 恢复
```
RDBackupManager.createBackup
  → bookshelf.json + config.json + ai_config.json + books/*
  → UIActivity
恢复 DocumentPicker zip
  → 写文件 → rebuildChapters → insertOrReplace → restore config/AI
```
| 问题 | 级别 | 说明 |
|------|------|------|
| 密钥进 zip | P0 | P0-B1 |
| 部分失败 | P1 | P1-B4 |
| 仅本地书 | 设计 | 在线书架书不进备份（需产品确认） |
| 无本地书不能备份 | P2 | AI-only 用户无法备份配置（产品缺口） |
| 恢复后进度 | P2 | rebuild 后 chapterId 映射失败回退第一章，进度丢失 |

#### 链路 C：AI 翻译
```
TopBar 翻译 → Menu forward → PageVC
  → activeProfile → RDAIClient → NSURLSession
  → Alert 展示
```
| 问题 | 级别 | 说明 |
|------|------|------|
| 密钥明文 | P0 | |
| 连点竞态 | P1 | |
| 未配置引导 | OK | 已有设置跳转 |
| 错误信息含 HTTP body | P2 | 可能含上游敏感信息展示给用户 |
| 格式类型自定义 URL | OK | 有校验；SSRF 风险：用户自填 URL 从设备出站——移动端可接受，但恶意配置可打内网（**低，需知悉**） |

#### 链路 D：在线章节（遗留）
```
RDCharpterManager → RDCharpterApi/ContentApi → WCDB
RDReadPageViewController.p_updateChapter → RDCheckApi
```
| 问题 | 级别 | 说明 |
|------|------|------|
| HTTP 明文 | P1 | |
| complete 遗漏 | P2 | |
| 本地书隔离 | OK | bookId<0 短路 |

#### 链路 E：清空书架
```
Setting 清空 → 本地 removeLocalBook / 在线 remove + deleteAllCharpter
```
| 问题 | 级别 | 说明 |
|------|------|------|
| AI 配置是否清空 | P2 | **不清空** AI 与阅读配置——需产品确认 |
| 无二次进度/事务 | P2 | 中断可能半清空 |

---

### 2.5 可复用与可精简实现

| 重复/复杂点 | 现状 | 建议统一 |
|-------------|------|----------|
| 调试日志 3 处 | AppDelegate / RDUtilities / LEEAlert 各写一份 | 删除或 `RDDebugLog` DEBUG-only |
| 安全作用域文件读 | Import/Backup/Font 各自 start/stop | `RDScopedFileReader` |
| JSON 读写 | AI store、backup 条目、多处手写 | `RDJSONFileStore` |
| 后台任务+主线程回调 | Import/Backup/Storage 统计模板重复 | `RDAsyncTask` 小工具 |
| 阅读打开 | Helper 内 PDF/本地/在线分支 | `RDBookOpenRouter` |
| 在线 API 模块 | 产品不用仍编译 | 编译剥离或动态框架 |
| 章节插入 | N+1 | 批量 API |
| 双持久化 | Archiver + JSON | 统一 Settings |

**可精简：**

1. **RDReadPageViewController**：拆协调器（见 P2-F1）。  
2. **遗留 Discover/Search/Library**：删除或 `#if` 剔除约数百文件依赖。  
3. **MOBI/EPUB 解析器**：大文件，保持独立 module，避免再塞进 Manager。  
4. **AI 六类型**：请求/解析已较干净；UI 编辑页可与类型元数据表驱动（默认 model、是否需要 baseURL）减少 switch。

---

### 2.6 隐藏风险与高并发风险

| 风险 | 说明 | 验证方法 |
|------|------|----------|
| WCDB 多线程 | 导入/恢复后台写 + UI 读书架无串行队列 | TSan / 连续导入+滑动书架 |
| primaryId 碰撞 | 无分隔符 | 构造 id 对插入 |
| isEqual 跨书 | 目录 indexOfObject | 双书同 chapterId |
| 翻译乱序 | 连点 | 弱网连点 |
| 备份密钥外泄 | 分享 zip | 解压检查 |
| 调试日志路径 | 真机无效但污染代码 | grep |
| 大文件 OOM | 200MB+ | Memory gauge |
| 恢复 Security Scope | 若未来改为流式读 zip 可能踩坑 | iCloud Drive 恢复 |
| 在线空内容不 complete | 调用方死等 | Mock |
| 缓存旧 bookDetail | 阅读中外部 restore 同 bookId | 恢复后是否仍显示旧章节——**需要进一步验证** |

**高数据量预期瓶颈：**

1. 章节 content 全量进 SQLite + 错误索引。  
2. 导入 N+1。  
3. 书架 `getAllOnBookshelf` 全量加载无分页（书多时列表卡）。  

---

### 2.7 测试缺口

#### 已有
- `Reader/Tests/AIHarness`：六协议 request/parse/translate、配置持久化、zip AI 条目、UI wiring 结构检查。

#### 缺失（应按优先级补）

| 场景 | 类型 | 建议输入 | 期望 |
|------|------|----------|------|
| TXT 导入重复 | 正常/幂等 | 同一文件两次 | 同一 bookId，书架一本 |
| 大 TXT | 边界 | 50–200MB | 不杀进程或明确失败 |
| EPUB/MOBI/PDF 各一 | 正常 | 样例书 | 可打开 |
| 备份往返 | 正常 | 2 本地书+AI | 进度与 AI 一致 |
| 备份缺文件 | 异常 | 删 zip 内一本 | 明确部分失败 |
| 备份含 Key | 安全 | 配置 key 后备份 | **期望最终无明文**（现状失败） |
| 翻译无配置 | 异常 | 清 AI | 引导设置 |
| 翻译连点 | 并发 | 连点 | 单飞行 |
| 清空书架 | 正常 | 有书清空 | 文件+章节+记录无残留 |
| 本地书无网 | 正常 | 飞行模式 | 可阅读 |
| primaryId 碰撞 | 边界 | 构造 id | 不互相覆盖 |
| 在线空内容 | 异常 | Mock | complete 必调 |

**重要：当前 AI harness 不能替代导入/WCDB/UI 集成测试。**

---

## 3. 分阶段整改计划

### 阶段 0（0.5–1 天）— 止血 P0
1. 删除全部 `debug-603e3d` / 本机绝对路径日志。  
2. AI Key 迁 Keychain；备份默认不导出明文 Key（或加密 zip）。  
3. Release 配置断言：grep 无 `/Users/luma`、无明文 key 样例。

### 阶段 1（3–5 天）— P1 核心链路
1. 翻译 in-flight 门闩 + 取消。  
2. 导入流式哈希；大文件策略。  
3. 章节批量插入优化；去掉 content 索引。  
4. 备份原子恢复与结果模型。  
5. ATS 收紧 + 本地模式禁用 HTTP API。  
6. `primaryId`/`isEqual` 修复 + 迁移。  
7. 本地书打开完整性校验。

### 阶段 2（1–2 周）— 架构收敛
1. 拆分 `RDReadPageViewController`。  
2. 统一 Settings/JSON 存储。  
3. 编译剥离或删除 Discover/Library/Search 死模块。  
4. WCDB 串行队列 / repository 层。  
5. 可选 DB 加密。

### 阶段 3（持续）— 测试与质量
1. XCTest target：LocalBook / Backup / CharpterData / AI（已有 harness 迁入）。  
2. 关键样例书 fixture。  
3. CI：`run_tests.sh` + `xcodebuild test`。  
4. 性能基准：导入 1k 章、书架 500 本。

### 阶段依赖
```
阶段0 ──► 阶段1 ──► 阶段2
              └──► 阶段3（可与阶段1末并行）
```

---

## 4. 最终验收标准

必须全部满足方可认为「核心质量达标」：

1. **多入口一致**  
   - 书架点开 / 恢复后点开 / 导入完成点开，同一本书进度与章节一致。  
   - 设置与阅读页进入 AI 配置，读写同一 `RDAIConfigStore`。

2. **无角色账号下的「权限」**  
   - 本地书全程无网络（飞行模式可读、可听书）。  
   - 未配置 AI 必引导，不出现静默失败。

3. **密钥与备份**  
   - 设备 Documents 与分享 zip 中无明文 API Key（或强加密且文档说明）。  
   - 备份含 bookshelf/config/books；恢复后本地书可打开；AI 元数据一致。

4. **幂等与重复操作**  
   - 同文件重复导入不产生重复书架项。  
   - 翻译连点不产生错乱结果。  
   - 重复恢复不损坏已有可读性（可覆盖但可打开）。

5. **异常与部分失败**  
   - 备份缺文件、导入坏文件、翻译 HTTP 4xx，均有明确错误，不脏写半状态（或可解释的部分成功 UI）。

6. **数据量**  
   - 约定基线（如 500 章书、100 本书架）下列表滑动与打开 < 可接受阈值（团队定量）；无 content 全列索引导致的异常膨胀。

7. **缺陷关闭**  
   - 本报告 **所有 P0、P1** 关闭并附回归记录。  
   - P2 有排期或明确 Won’t fix 理由。

8. **工程卫生**  
   - 无开发者绝对路径；Release 无 agent debug 区域。  
   - AIHarness +（新增）导入/备份测试在 CI 绿。

---

## 5. 需要进一步验证（不得当定论）

| 项 | 为何存疑 | 验证方法 |
|----|----------|----------|
| `isEqual` 是否已在阅读目录导致串书 | 取决于是否用 `indexOfObject:` 跨书 | 代码路径审计 + 构造双书 |
| 多文件同时导入是否损坏 DB | WCDB 线程安全依赖版本与用法 | 并行导入压力 + TSan |
| 兼容网关是否接受 Gemini header key | 各代理实现不一 | 对目标 baseURL 实测 |
| 恢复进行中阅读中的书 | 无会话失效机制 | 边读边恢复实验 |
| 遗留搜索入口是否用户可达 | 需走一遍当前 UI 树 | 手工点选所有书架按钮 |

---

## 6. Gitflow 与审查工作方式

| 项 | 说明 |
|----|------|
| Feature 分支 | `feature/code-review-ai-translate`（已从 `master` 创建） |
| 本报告路径 | `docs/code-review-report.md` |
| 整改状态 | 见下方「整改落地记录」(2026-07-17) |

## 8. 整改落地记录 (2026-07-17)

| 编号 | 状态 | 做法摘要 |
|------|------|----------|
| P0-F1 调试绝对路径 | **已修** | 删除 AppDelegate/RDUtilities/LEEAlert 中 `RDWriteDebugLog` 与调用 |
| P0-B1 API Key 明文 | **已修** | Keychain(测试用 sidecar);磁盘 JSON/备份 zip **不含** apiKey;旧明文自动迁移 |
| P1-F2 翻译连点 | **已修** | `isTranslating` 门闩 + `cancelInFlightTranslate` + generation 丢弃过期回调 |
| P1-F3 本地打开 | **已修** | RDReadHelper 校验文件/章节;缺失明确 toast |
| P1-B2 大文件 MD5 | **已修** | 流式 `bookIdForFileURL` + copy 落盘优先 |
| P1-B3 章节 N+1 | **已修** | 一次查已有 id + batch insert |
| P1-D2 content 索引 | **已修** | 移除 `(bookId,content)` 索引 |
| P1-D3 isEqual | **已修** | 比较 bookId+charpterId;hash 对齐 |
| P1 primaryId 碰撞 | **已修** | 新 id 使用 `bookId_charpterId` 分隔 |
| P1-B4 备份部分失败 | **已修** | 临时文件提交;失败计数;允许仅 AI 备份;空书架+AI 可恢复 |
| P1-B5 Gemini key | **已修** | `x-goog-api-key` header,URL 不含 key |
| P1 ATS | **已修** | 关闭任意加载,仅 yuenov.com 例外 HTTP |
| P2-B1 complete 遗漏 | **已修** | 空内容路径 `complete(NO,nil)` |
| P2 翻译截断提示 | **已修** | Toast「仅翻译前 4000 字」 |
| P2 阅读翻译编排抽出 | **已修** | `RDReadTranslateHelper` 承接翻译 UI 编排 |
| P2 在线搜索入口 | **已修** | 书架搜索 cell 不再 push 在线搜索 |
| P2 WCDB 并发 | **已修** | `performSync/Async` 串行队列包裹读写 |
| P2 primaryId 历史数据 | **已修** | 启动一次性迁移 `bookId_charpterId` |
| P2 数据文件保护 | **已修** | DB/LocalBooks/AIConfig 使用 `NSFileProtectionCompleteUntilFirstUserAuthentication` |
| P3 Discover 模块整包删除 | **未做** | 代码仍在工程但主路径不可达;全量删模块风险大,保留编译兼容 |

验证: `Reader/Tests/AIHarness` ALL PASSED; `xcodebuild` BUILD SUCCEEDED.

---

## 7. 总结表（按级别计数）

| 级别 | 数量（约） | 主题 |
|------|------------|------|
| P0 | 3 | 密钥+备份、调试绝对路径、（与 ATS/HTTP 并列可升 P0 的明文传输） |
| P1 | 12+ | 内存导入、N+1、索引、并发翻译、部分恢复、打开失败 UX、等 |
| P2 | 10+ | 上帝类、死模块、双存储、回调遗漏、产品缺口 |
| P3 | 若干 | 命名、Pod 闲置 |

**优先行动：阶段 0 三件事（删 debug 路径、Keychain、备份脱敏）应在任何功能迭代之前完成。**
