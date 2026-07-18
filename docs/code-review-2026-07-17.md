# 轻阅 iOS 全应用代码审查报告

> **2026-07-17 修复记录**:P0-1、P1-1~P1-3、P2-1~P2-13、以及 P3-4/5/6/7/8/9/10/11/14 与 P3-2/3(复用下沉)已在本分支修复并通过编译 + 模拟器冒烟 + 独立 harness 验证;
> 审查中补发现并一并修复:阅读页内目录/进度条跳章未清 charOffset,导致新章节落在错误页。
> 明确延期项(非缺陷,独立 PR):P3-1(翻页控制器双胞胎方法合并)、P3-12(恢复/字体 picker 拆分)、P3-13(RDUrl.h 随死代码批次删除)、P2-12 的 48 个死文件从 pbxproj 物理移除(本次已切断全部运行时在线链路:目录管理器纯本地化、书籍详情入口移除、p_updateChapter 删除)。

- 日期:2026-07-17
- 分支:`feature/code-review-full-audit`(基于 `feature/code-review-ai-translate` HEAD,含工作区未提交的漫画阅读改动)
- 范围:UI 层(Controller/View)、业务层(Manager/Helper)、数据层(WCDB)、完整业务链路、配置(Info.plist/pbxproj)、测试
- 说明:本项目为纯本地 iOS 单端应用,报告中「前端」对应 UI 层,「后端」对应业务/管理层,「数据库」对应 WCDB 存储层。

---

## 一、整体代码质量结论

核心链路(导入 → 解析 → 入库 → 书架 → 阅读 → 进度 → 备份/恢复)完整闭环,近期新增模块(AI 配置 Keychain 存储、ZIP 读写、备份、字体、TTS)边界清晰、防御较好。主要风险集中在四类:

1. **部分模型整行回写**:书架列表刻意使用轻量投影(不含 `charpterModel` 大字段),但多处把这个**不完整对象**直接 `insertOrReplace` 回库,静默清空未投影列 —— 已确认「改名丢阅读进度」P0。
2. **写放大**:阅读记录表把整章正文序列化进 `charpterModel` 列,每翻一页在主线程同步全量写 read + history 两张表。
3. **无上限增长**:AI 翻译缓存、并发预取请求、history 表都没有上限或清理机制。
4. **死代码规模大**:发现/书城/搜索/在线 API 约 48+ 个 .m 文件仍在编译目标内且部分入口仍可达(长按在线书 → 书籍详情)。

---

## 二、问题清单(按严重程度)

### P0

#### P0-1 长按「修改书名」后阅读进度丢失(回到第一章)
- **位置**:`Reader/Reader/Sections/Bookshelf/Cell/RDBookshelfCell.m:390-394`(`p_renameBook`)
- **描述**:书架 cell 拿到的 `book` 来自 `getBookshelfDisplayList` 的**轻量投影**(刻意不含 `charpterModel/total/end/desc`,见 `RDReadRecordManager.mm:74-98`)。改名后直接 `[RDReadRecordManager insertOrReplaceModel:book]` 整行替换,`charpterModel` 列被写成 NULL。
- **触发条件**:长按任意已读过的书 → 修改书名 → 保存 → 再打开该书。
- **实际影响**:`RDReadHelper.m:73` 判断 `record.charpterModel.charpterId != 0 || name.length > 0` 不成立,走 `p_openFromFirstChapter`,`page/charOffset` 一并归零 —— 阅读进度静默丢失;`total/end` 也被清零。
- **根本原因**:轻量投影对象与全量行对象共用同一个模型类型,类型系统无法阻止「部分对象整行回写」。
- **修复方案**:改名保存前先 `getReadRecordWithBookId:` 取完整行,只改 `title/author` 再回写;或新增 `updateTitle:author:forBookId:` 的按列 UPDATE 接口(推荐,顺带避免 `readTime` 被 `insertOrReplaceModel` 刷新)。系统性防护见 P1-1 的按列更新改造。
- **涉及文件**:`RDBookshelfCell.m`、`RDReadRecordManager.h/.mm`
- **回归测试**:导入 txt 读到第 3 章第 5 页 → 退出 → 改名 → 重开,应停在第 3 章原位置;书架副标题章节名不变;`total` 不为 0。

### P1

#### P1-1 每翻一页,主线程同步全量写两张表(含整章正文)
- **位置**:`RDReadPageViewController.m:282-320`(`p_saveRecord`);`RDReadRecordManager.mm:15-25`;`RDHistoryRecordManager.mm:16-21`
- **描述**:`charpterModel`(内嵌整章 content,长章节可达数百 KB)是 read/history 表的一列。每次翻页(`nextPage/lastPage/didFinishAnimating`)都会:①`getReadRecordWithBookId` 全量反序列化一行;②`insertOrReplaceObject` 写 read 表;③再写 history 表。全部经 `performSync` 在主线程等待。
- **触发条件**:正常阅读翻页;章节越大越明显。
- **实际影响**:大章节翻页掉帧;WAL 快速膨胀(代码里 checkpoint 的「recovered frames」注释即为此病征);history 表无限增长(见 P2-2)。
- **根本原因**:进度信息(charpterId/page/charOffset)与章节正文混在一列;保存粒度取错。
- **修复方案**:进度保存改为按列 UPDATE(`charpterId + page + charOffset + readChapterName + readTime`),新增 `durChapterId` 整数列,阅读时按需从章节表取正文;`charpterModel` 列仅在导入时写一次或彻底废弃。写库移到 `performAsync`。
- **涉及文件**:`RDReadRecordManager`、`RDHistoryRecordManager`、`RDReadPageViewController`、`RDBookDetailModel(.mm)`、`RDReadHelper`
- **回归测试**:大章节(>200KB)连续翻 50 页,Instruments 主线程无 >16ms 的 DB 停顿;杀进程重开进度正确;旧库数据(仍靠 charpterModel 列恢复进度)兼容。

#### P1-2 primaryId 迁移一次性把全部章节(含正文)载入内存
- **位置**:`RDDatabaseManager.mm:156-179`(`p_migratePrimaryIdsIfNeeded`)
- **描述**:`getAllObjectsOfClass` 拉出 chapter 表全部行(含 content)再逐条重写。
- **触发条件**:旧版本用户书库较大(如几十本网文,章节总正文数百 MB)时首次升级启动。
- **实际影响**:内存峰值过高被 watchdog 杀死;因 NSUserDefaults 标记在事务后设置,崩溃后每次启动重复尝试 → 启动死循环风险。
- **根本原因**:迁移未分页/未只取主键列。
- **修复方案**:只 SELECT `primaryId/bookId/charpterId` 三列,发现不合规的再逐条 `UPDATE ... SET primaryId=?`(纯 SQL,不搬 content),按 500 条分批事务。
- **涉及文件**:`RDDatabaseManager.mm`
- **回归测试**:构造 5 万章节旧格式库,首启内存峰值 <100MB,二次启动跳过迁移;中途杀进程后再启动能续跑且无重复数据(primaryId 主键天然幂等)。

#### P1-3 AI 后台翻译无并发上限、缓存无上限
- **位置**:`RDReadPageViewController.m:831-974`(`p_applyTranslateModeIfNeeded`/`p_prefetchAdjacentTranslationsFrom`/`translateCache`)
- **描述**:开启翻译后每次翻页发「当前页 + 前后页」共至多 3 个并发 LLM 请求,`translatePendingKeys` 只防同 key 重复,不限总并发;`translateCache` 按 `bookId_chapterId_page` 永久累积 NSAttributedString。
- **触发条件**:开启翻译后快速连续翻页(20 页 → 可能 20+ 个在途请求);或单次长会话翻译上百页。
- **实际影响**:API 费用不可控、局域网网关被打挂、响应乱序浪费;内存随会话线性增长(退出阅读页才释放)。
- **根本原因**:预取无队列化;缓存选了 NSMutableDictionary 而非 NSCache。
- **修复方案**:①在途请求上限(如 3),超出丢弃最旧预取;②`translateCache` 改 NSCache 设 `countLimit`(如 60 页);③翻页防抖:停留 >300ms 才发预取。
- **涉及文件**:`RDReadPageViewController.m`
- **回归测试**:用 `RDAIRecordingTransport` 断言快速翻 20 页时 `sendCount` 有界;Instruments 观察长会话内存平稳。

### P2

#### P2-1 备份恢复后 `readTime` 被覆盖,书架顺序失真
- **位置**:`RDReadRecordManager.mm:17`(`insertOrReplaceModel` 无条件 `readTime = now`)+ `RDBackupManager.m:259,275`
- **触发**:从备份恢复多本书。
- **影响**:备份里的 `lastReadTime` 全部变成恢复时刻,书架「最近阅读」排序丢失;改名(P0-1)也会顶到书架最前。
- **修复**:`insertOrReplaceModel` 拆出 `insertOrReplaceModel:touchReadTime:`;恢复与改名路径传 NO。
- **回归**:备份 3 本不同阅读时间的书 → 清空 → 恢复,书架顺序与备份前一致。

#### P2-2 history 表只写不读、无限增长
- **位置**:`RDReadPageViewController.m:314`、`RDReadHelper.m:82,113`;消费者仅剩在线书详情页(`RDBookDetailController`,准死代码)。
- **影响**:每翻页多一次全量写;删书/清空书架(`RDLocalBookManager.removeLocalBook`、`RDSettingController.p_clearAll`)不清 history → 数据库永久残留已删书(含整章正文列)。
- **修复**:纯本地版直接停止写 history 并在迁移中 DROP/清空该表;或删书时同步 `deleteHistoryWithBookId:`。
- **回归**:删除书籍后 `history` 表无该 bookId;翻页仅 1 次写库。

#### P2-3 ATS 全局关闭(`NSAllowsArbitraryLoads=YES`)
- **位置**:`Info.plist:177-196`
- **影响**:为局域网 AI 网关放行了**所有**明文 HTTP,攻击面扩大;上架审核也需说明。
- **修复**:去掉 `NSAllowsArbitraryLoads`,保留 `NSAllowsLocalNetworking=YES`;公网自定义 HTTP 网关用户引导改 HTTPS。遗留的 `yuenov.com` 例外与 `LSApplicationQueriesSchemes`(微信/微博/QQ 全家桶)一并删除。
- **回归**:局域网 `http://192.168.x.x` Ollama 可用;公网 http 被拦截并出现 RDAIClient 的 ATS 友好提示(`RDAIClient.m:470`)。

#### P2-4 `dealloc` 中执行业务逻辑(存进度、停 TTS、清缓存)
- **位置**:`RDReadPageViewController.m:1298-1311`
- **影响**:dealloc 里调 `p_saveRecord`(同步 DB×3 + 访问 pageViewController)与 `[RDSpeechManager stop]`;在对象析构期间创建 block/弱引用属未定义行为边缘,且与 `viewWillDisappear` 重复保存。
- **修复**:dealloc 只做 removeObserver;保存/停播全部收敛到 `viewWillDisappear`/`backAction`。
- **回归**:反复进出阅读页 + 听书中直接返回,无崩溃、进度正确。

#### P2-5 每个阅读页实例一个 1 秒 NSTimer,每秒新建 2 个 NSDateFormatter
- **位置**:`RDReadController.m:101,336-354`
- **影响**:仿真翻页时同时存活 3-5 个页面实例 → 每秒 3-5 次 timer 回调、约 10 个 NSDateFormatter 分配;纯耗电/浪费,时间显示只需分钟级。
- **修复**:formatter 静态复用;timer 改 60s 或用全局单例广播时间变化。

#### P2-6 替换规则正则每次分页重新编译
- **位置**:`RDReplaceRule.m:209-236`(`applyToText`)
- **影响**:每次翻章/改字体/改主题都对全部规则 `regularExpressionWithPattern`;规则多时分页延迟放大(分页本身在主线程)。
- **修复**:RDReplaceRule 持有惰性编译的 NSRegularExpression,规则变更时失效。

#### P2-7 PDF / 漫画每次翻页主线程同步整行写库
- **位置**:`RDPdfReadController.m:146-172`(PDFViewPageChangedNotification 连续滚动高频触发)、`RDComicReadController.m:243-248`
- **影响**:连续滚动 PDF 时高频 `performSync` 写库 → 掉帧。
- **修复**:节流(如 0.5s 合并)+ `performAsync` + 按列 UPDATE(依赖 P1-1 接口)。

#### P2-8 备份/恢复把整本书一次性读进内存
- **位置**:`RDBackupManager.m:149`(`dataWithContentsOfFile` 无 mapped 选项)、`RDZipWriter.addEntryWithName:data:`
- **影响**:书架里有大 PDF/漫画包(数百 MB)时备份内存峰值等于最大文件体积,可能 OOM。
- **修复**:读取用 `NSDataReadingMappedIfSafe`(store 模式写 zip 可直接流式 copy);RDZipWriter 增加 `addEntryWithName:fileAtPath:` 流式写入 + 流式 crc32。
- **回归**:含 300MB PDF 的书架执行备份,内存峰值 <80MB,备份可完整恢复。

#### P2-9 备份内容缺书签、替换规则、自定义字体、charOffset
- **位置**:`RDBackupManager.m:107-165`
- **影响**:恢复后书签全丢、净化规则回默认、自定义字体缺失、精确进度退化为页码(字体变化后漂移)。与 legado「全量配置入备份」思路尚有差距。
- **修复**:bookshelf.json 增加 `durChapterOffset`;新增 `bookmarks.json`、`replace_rules.json`(RDReplaceRuleStore 已有 JSON 序列化可直接复用)、`fonts/` 目录。注意向后兼容旧备份(缺条目视为跳过——现有代码模式已支持)。

#### P2-10 `RDAIConfigStore` 非线程安全 —— 需要进一步验证
- **位置**:`RDAIConfig.m`(`mutableProfiles` 无锁);后台写入点:`RDBackupManager.m:313`(恢复走 global queue);主线程读:设置页 `p_refreshDetailsAsync` 也在后台读,阅读页翻译在主线程读。
- **潜在影响**:恢复备份的同时进行翻译/进设置页,枚举 `mutableProfiles` 时被修改 → 崩溃。
- **验证方法**:恢复大备份的同时反复触发 `translateAction`,TSan 跑一轮;确认后给 store 加串行队列或 `os_unfair_lock`。

#### P2-11 同内容文件并发导入的幂等竞态 —— 需要进一步验证
- **位置**:`RDLocalBookManager.m:80-160`(每个导入独立 `dispatch_async` 到并发队列;dedupe 检查与落盘之间无互斥)
- **潜在影响**:两处同时导入同一内容(如「打开方式」连点两次)→ 同一 `filePath` 被并发 remove+copy,可能写坏文件。
- **验证方法**:脚本连续两次 `importBookAtURL` 同一 URL,校验落盘文件 MD5。修复:导入串行队列,或按 bookId 加锁。

#### P2-12 死代码 48+ 文件仍编译且部分入口可达
- **位置**:`Sections/Discover|Library|Search`(48 个 .m)、`Service/*` 在线 API、`RDReadPageViewController.p_updateChapter`(RDCheckApi)、`RDBookshelfCell` 长按在线书 →「书籍详情」、`RDReadHelper/RDCharpterManager` 的在线分支、`Model/Discover` 等。
- **影响**:纯本地 app 内仍有可发起网络请求的完整链路(bookId>0 的历史残留书即可触发);包体积、编译时间、维护成本;`kAdPages/userPages` 广告残留(`RDReadPageViewController.m:71,84`)。
- **修复**:分两步——先从 pbxproj 移除 Discover/Library/Search/Service/在线 Model 并删除 `p_updateChapter`、`getAllOnBookshelfPram`、`RDBookshelfCell` 在线详情入口、`slientDownWithBookId` 在线分支;`RDCharpterManager` 收敛为仅本地路径。回归:全功能冒烟 + 编译通过。

#### P2-13 清空书架在主线程串行做全部文件与 DB 删除
- **位置**:`RDSettingController.m:506-521`
- **影响**:几十本书时 UI 冻结数秒。
- **修复**:移到后台队列 + 完成后回主线程刷新(toast 先出「正在清理…」)。

### P3

| # | 位置 | 问题 | 建议 |
|---|------|------|------|
| P3-1 | `RDReadPageViewController.m:491-738` | `p_afterOrBeforeWithViewController:` 与 `p_setAfterOrBeforeViewControllerWithBefore:` 约 200 行近乎复制;`p_creatReadController` 10 参数签名重复 20+ 次 | 抽「章节页描述符」结构 + 单一构建函数,双胞胎方法合并 |
| P3-2 | `RDReadPageViewController.m:1038-1086` vs `RDBookshelfCell.m:322-365` | 金句截取 + 分享卡片逻辑两处重复实现(阈值还不一致:4/60 vs 6/40) | 下沉到 `RDShareCardBuilder` 提供 `quoteFromText:` |
| P3-3 | `RDReadPageViewController.m:1088-1127` vs `RDSettingController.m:358-381` | 查词典 alert 两处重复 | 抽 `RDDictionaryHelper` |
| P3-4 | `RDLocalBookManager.m:65-78` | `finish` 里 isDuplicate 两分支代码完全相同 | 合并;注释已过期 |
| P3-5 | `RDLocalBookManager.m:184,218` | 漫画导入打开同一 zip 两次(列表 + total) | 复用同一 RDZipArchive 实例 |
| P3-6 | `RDSpeechManager.m:159` | TTS 朗读原始 `chapter.content`,未过替换规则,与屏显不一致 | `applyToText` 后再朗读 |
| P3-7 | `RDSpeechManager` | AVSpeechSynthesizer delegate 回调线程未显式归一 —— **需要进一步验证**(在 `didFinishSpeechUtterance` 断点看线程);`willSpeakChapter` 里做 DB+UI | 回调统一 `dispatch_async(main)` |
| P3-8 | `RDAIConfig.m:391-396` | `importBackupData` 中空 for 循环(遗留脚手架) | 删除 |
| P3-9 | `RDComicReadController.m:67-72` | 缩放 >1 时 swipe 与滚动 pan 手势冲突,翻页需先缩回 | swipe 仅在 zoomScale≈1 时启用(`gestureRecognizerShouldBegin`) |
| P3-10 | `RDReadRecordManager.mm:61-72` | `countOnBookshelf` 取全部行数数组求 count | `getOneValueOnResult:count()`(RDBookmarkManager 已有正确写法可抄) |
| P3-11 | `Info.plist:142-174` | 30 个第三方 scheme 白名单(微信/微博/QQ)纯遗留 | 删除 |
| P3-12 | `RDSettingController.m:447-471` | 恢复/字体共用一个 picker 回调,仅按扩展名分流 | 用两个 delegate tag 或独立 picker,避免将来类型增多误分流 |
| P3-13 | `Common/Const/RDUrl.h` | 空壳头文件 | 随死代码清理删除 |
| P3-14 | `RDBookshelfPrefetch.m:88-98` | `usleep` 轮询等待(20ms busy-wait) | dispatch_group/semaphore |

---

## 三、完整业务链路核查

| 链路 | 结论 |
|------|------|
| 文件导入(picker/文件夹/openURL)→ 解析 → 落盘 → 入库 → 通知刷新 | ✔ 闭环。MD5 负数 bookId 幂等;重复导入重新上架逻辑正确;失败路径均清理落盘文件。遗留:并发同文件竞态(P2-11) |
| 打开阅读(书架 tap → RDReadHelper → 章节校验 → 阅读页) | ✔ 闭环,文件丢失/章节缺失均有 toast 拦截;**改名后进度丢失(P0-1)** |
| 翻页 → 进度保存 → 冷启动恢复(RDCacheModel 自动续读) | ✔ 功能闭环但写放大(P1-1);charOffset 恢复策略正确(字体变化后按偏移重定位) |
| 字体导入 → 注册 → 分页应用(KVO fontName) | ✔ 闭环;重启后 `registerCustomFontsAtLaunch` 重注册正确 |
| TTS 起播 → 跨章续播 → 阅读页同步 | ✔ 闭环;语速下一章生效(已知产品决定);读原文未净化(P3-6);delegate 线程待验证(P3-7) |
| AI 翻译(配置 → 请求 → 解析 → 内联展示/后台预取) | ✔ 闭环;三态开关逻辑自洽;取消/换页/generation 防乱序正确;无节流(P1-3) |
| 备份 → 分享 → 恢复(重建章节/进度/配置) | ✔ 闭环;恢复的临时文件 + 原子替换正确;`readTime` 覆盖(P2-1)、内容缺口(P2-9)、大文件内存(P2-8) |
| 删除/清空 → 文件+记录+书签清理 | ⚠ read/chapter/bookmark 已清,**history 表不清**(P2-2) |
| 漫画(zip/cbz/文件夹 → 打包 → 阅读 → 进度) | ✔ 闭环;RDZipArchive 只读 NSData + NSCache 均线程安全,预载并发无竞态(已核) |
| 在线书残留链路(bookId>0) | ⚠ 仍可达(P2-12),纯本地定位下应整体拆除 |

---

## 四、可复用与可精简实现

1. **进度按列更新接口**(P0-1/P1-1/P2-1/P2-7 的共同解):`RDReadRecordManager` 增加 `updateProgress:` 与 `updateTitleAuthor:`,全 app 禁止用部分模型 `insertOrReplaceModel`。
2. **金句截取 / 词典弹窗 / 分享面板**:三处重复,下沉 `RDShareCardBuilder` + 新建小 helper(P3-2/3)。
3. **翻页控制器双胞胎方法**:合并后 `RDReadPageViewController` 预计 -250 行(P3-1)。
4. **解析器分发**:`RDLocalBookManager.importBookAtURL` 与 `rebuildChaptersForBook` 各写一遍「fileType → parser」switch,抽 `+parserResultForPath:fileType:error:`。
5. **正则缓存**:RDReplaceRule 惰性编译(P2-6)。
6. **`objectAtIndexSafely`/`performSync` 等既有工具**使用规范良好,可作为团队基线保持。

## 五、隐藏风险与高并发/大数据量风险

- **大数据量**:P1-1(写放大)、P1-2(迁移 OOM)、P2-2(history 膨胀)、P2-8(备份 OOM)、`RDSettingController` 存储统计遍历大目录已放后台(✔)。
- **并发**:P1-3(LLM 并发无界)、P2-10(AIConfigStore 无锁)、P2-11(导入竞态)、`RDBookshelfPrefetch` busy-wait(P3-14)。DB 层 `performSync` 串行队列 + 队列哨兵防重入,设计正确。
- **顺序依赖**:阅读页依赖 `charpters`(简表)与 `charpterModel` 通过重写的 `isEqual`(bookId+charpterId)做 indexOf —— 已核实 `RDCharpterModel.mm:46` 有正确实现,无隐患;但任何人删掉该 isEqual 会引发越界,建议补注释/测试钉住。
- **状态回滚**:导入失败路径清理完备;恢复失败逐本计数不回滚已成功本(可接受,消息已提示「成功 N 失败 M」)。

## 六、测试缺口

现状:仓库内**无测试 target**;仅 `RDAIRecordingTransport` 夹具具备可测性。此前 21 个解析器用例在仓库外临时 harness,未沉淀。

需补(按优先级):
1. **进度保存/恢复**:改名后进度不变(P0-1 回归)、字体变化后 charOffset 定位、备份恢复后进度与 readTime。
2. **解析器**:把 txt(GB18030/Big5/无章节)、epub(NCX/nav/实体)、mobi(EXTH/DRM 拒绝/LZ77 回引)用例迁入 XCTest。
3. **ZIP 读写往返**:RDZipWriter 写 → RDZipArchive 读,含 UTF-8 名、>65535 条目截断、损坏 EOCD。
4. **备份恢复**:正常/缺书文件/损坏 json/仅 AI 配置/旧版本备份(无 ai_config.json)。
5. **AI 客户端**:用 RecordingTransport 断言三家协议请求体/响应解析/HTTP 4xx/翻页并发上限(P1-3 回归)。
6. **幂等**:同文件重复导入、重复点备份、并发导入(P2-11)。

## 七、分阶段整改计划

- **阶段一(数据正确性,1-2 天)**:P0-1、P2-1(touchReadTime)、P2-2(停写 history + 删书清理)。全部依赖新增「按列更新」接口,一并落地。回归:进度/书架顺序用例。
- **阶段二(性能与资源,2-3 天)**:P1-1(进度列改造 + 异步写)、P1-3(并发上限 + NSCache)、P2-5/6/7/13、P3-10。回归:Instruments 翻页帧率、长会话内存。
- **阶段三(架构与卫生,2-4 天)**:P2-12 死代码拆除、P2-3 ATS 收紧、P2-4、P2-8/9(备份增强)、P3 系列、建 XCTest target 迁入用例。回归:全功能冒烟 + 上架自查。
- **验证专项(穿插)**:P2-10、P2-11、P3-7 按各自「验证方法」确认后再决定是否修。
- 阶段一、二各自独立成 PR,基于 gitflow 从 `master` 拉 `feature/fix-progress-integrity`、`feature/perf-record-write` 等分支,禁止混入无关重构。

## 八、最终验收标准

1. 同一本书从「书架点开 / 冷启动自动续读 / 书签跳转 / 目录跳转 / TTS 续播 / 改名后 / 备份恢复后」七个入口进入,章节与页位置一致。
2. 改名、恢复备份、重复导入均不改变书架排序语义(readTime 仅真实阅读时更新);重复导入不产生重复行/重复文件。
3. 大章节(≥200KB)翻页主线程无 >16ms DB 停顿;含 300MB 大文件的书架可完成备份且内存峰值受控。
4. 删除书籍后 read/chapter/bookmark/history 四表及 LocalBooks 目录均无残留;存储统计随之归零。
5. AI 翻译快速翻 20 页在途请求数 ≤ 设定上限;关闭后台翻译后不再有新请求发出。
6. ATS 收紧后:局域网 HTTP 网关可用,公网 HTTP 明确报错提示。
7. 全部 P0/P1 修复合入并通过上述回归;P2 完成或降级为已记录的显式决策;XCTest target 建立且解析器/备份/AI 客户端用例通过。
