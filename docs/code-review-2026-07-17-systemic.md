# Reader iOS 系统性代码审查报告

审查日期：2026-07-17  
审查分支：`feature/system-code-review-2026-07-17`  
基线：`master@201ef75`  
审查对象：当前工作区完整状态（包含尚未提交的 PDF 首页封面、手动封面和书籍信息修改相关改动）

> **修复记录（2026-07-17 之后，同分支）**
>
> 已修复并通过 AIHarness / 独立 fixtest / 无签名模拟器 Debug 构建验证（提交 `19038e4`，版本 1.2.1）：
>
> - **P1-01** 备份恢复路径穿越：`localPath`/`coverImg` 规约为纯文件名并校验落盘目标仍在书籍目录内
> - **P1-02** ZIP 资源预算：条目数/单条目/累计解压量/压缩比上限 + CRC32 校验；MOBI 两处 32 位相加溢出改
>   64 位判断；EPUB 空数组 `removeLastObject` 崩溃修复；TXT 章节上限提高且超限内容并入末章而非静默丢弃
> - **P1-03** AI profile 备份劫持：恢复时 profileId 一律重新生成，密钥只按 `(provider, 规范化 baseURL)`
>   内容匹配重新绑定，不再信任清单里的 id；`activeProfileId` 不再盲目沿用备份声明值
> - **P1-04** 删除/重导竞态：`removeLocalBook` 的章节清理从无关全局队列改到 import 串行队列
> - **P1-06** 备份静默失败：源文件缺失的书不再进清单；可选内容写入失败作为警告随成功结果一起展示
> - **P1-08** 清空书架遗漏：在线书分支补齐与单本删除一致的书签清理
> - **P1-09** 书架刷新竞态：`RDBookshelfController.isReloading` 改 `pendingReload` 排队模式；
>   `RDBookshelfPrefetch` 静态缓存补齐 `@synchronized` 与递增代次，旧快照不能覆盖新快照
> - **P1-10** 翻译缓存 identity 错误：缓存 key 从页码改为原文内容哈希；缓存值改存结构化句对，
>   展示时按当前字号/字体/主题重新渲染
> - **P1-12** 隐私清单未申报：补充 `NSUserDefaults`（CA92.1）与文件元数据（3B52.1）Required Reason
> - **P2-01** `viewDisappear:` 拼写错误改为 `viewWillDisappear:`
>
> 部分缓解（未完整解决，原因见下）：
>
> - **P1-11** 大章节主线程分页：仅加了 30 万字符硬上限防御极端/恶意超长单章阻塞主线程或触发
>   watchdog；真正的后台可取消分页涉及 `UIPageViewControllerDataSource` 的同步契约（4/6 调用点结构上
>   必须同步返回），需要先补齐 XCUITest 才能安全重构翻页交互，本次未做。
>
> 评估后判断本次不适合动手、留待专门排期（原因见下）：
>
> - **P1-13 / P2-17** 遗留在线模块物理删除：实际排查发现死代码簇比报告估计的「~51 个文件」更大，
>   达 **118 个文件**（`Sections/Discover`、`Library`、`Search`、`Bookshelf/BookDetail`、
>   `Bookshelf/Catalog`、`Bookshelf/Read/View/Download`、整个 `Service/` 目录，以及
>   `RDBookshelfSearchCell` 等散落在 Bookshelf 目录下但已不可达的文件），且彼此交叉引用；完整安全删除
>   需要先做一次完整可达性分析、同步调整 Podfile（移除 AFNetworking/YTKNetwork）并重新 `pod install`，
>   人工编辑 pbxproj 移除百余个文件引用风险较高，建议单独开分支、每步都跑一次完整构建验证，而不是作为
>   本轮众多修复之一顺带处理。另外即使完整执行，P1-13 仍不会完全解决——`MBProgressHUD`/`SDWebImage`
>   是书架封面与全局 HUD 仍在使用的依赖，其隐私清单缺失需要单独的版本升级评估，与本项删除无关。
> - **P1-05**（备份恢复整体原子性/staging）、**P1-07**（WCDB 全量错误传播与迁移完成标志）：本轮修复
>   覆盖了两者的部分具体场景（备份创建诚实性、恢复路径安全性），但未建立报告建议的统一
>   `RDLibraryMutationCoordinator`/`Result` 错误模型/迁移状态机,这两项的完整方案仍是独立的架构性工作。
> - 其余 P2/P3 与第 12 节「需要进一步验证」事项（真机权限、服务端契约、CI/Archive/SBOM 等）现状不变。

## 1. 审查边界与方法

本次审查覆盖 UIKit 前端、客户端业务层、WCDB/SQLite 持久化、文件生命周期、备份恢复、AI 网络、遗留在线接口、权限/隐私、构建发布和测试。采用了静态调用链追踪、并发与失败路径推演、数据模型/索引检查、依赖与发布配置核对，以及现有测试和无签名模拟器构建验证。

本仓库是 iOS 客户端，不包含远端服务端、网关、服务端 Controller/Service/Mapper、服务端数据库 schema、鉴权中间件或部署清单。因此：

- 本地业务层和数据库问题可直接给出结论。
- 远端接口的认证、角色、资源所有权、事务、限流、幂等和服务端查询性能均标记为“需要进一步验证”，并给出验证方法；不能仅因客户端没有 token 就断言存在越权。
- 当前运行时主入口只有“书架 + 设置”；旧 Discover/Library/Search/Service 代码仍编译进应用，故按“低可达但仍存在”的真实攻击面和维护面审查。

严重级别定义：

- **P0**：可无条件导致全局不可用、跨安全边界失陷或不可逆的大范围数据事故，必须立即停发。
- **P1**：可造成严重数据损坏/泄露、核心链路错误、稳定复现的高影响故障或明确发布阻断。
- **P2**：在特定入口、并发、异常或规模下造成错误、性能/安全退化，需进入近期迭代。
- **P3**：可维护性、契约清晰度和工程效率问题，应在持续治理中消除。

本次未确认 P0。最高风险均需要用户导入恶意文件、特定并发或发布动作才能触发，因此定为 P1；这不降低修复优先级。

## 2. 整体代码质量结论

当前应用具备较完整的本地阅读能力，AI Key 已使用 `ThisDeviceOnly` Keychain 且备份会脱敏，系统 HTTPS 信任未被绕过，文档导入使用 copy 语义，数据库及本地书目录设置了 Data Protection；这些是有效的正向控制。现有 AI Harness 全部通过。

但整体质量尚不满足稳定发布标准，核心原因不是语法或单个崩溃点，而是**业务写操作没有统一事务/串行边界，UI 刷新没有“最后状态必达”语义，Repository 大量吞错，备份恢复把不可信清单当作可信路径，测试体系几乎未覆盖真实 App 链路**。此外，隐私清单和受管 SDK 清单构成明确的 App Store 发布风险。

综合评估：

- 数据正确性：**较高风险**。删除、重导、恢复、清空、改名和封面更换可出现部分成功或状态分叉。
- 安全与隐私：**较高风险**。恶意备份可覆盖应用容器文件并劫持 AI profile；归档无资源上限；隐私声明不完整。
- 前端一致性：**中高风险**。刷新请求可能丢失，格式间续读行为不同，失败常被渲染为空态或成功态。
- 性能：**中高风险**。大章节、漫画、目录和大量 PDF 下存在主线程阻塞、N+1 与重复全量工作。
- 可维护性：**中高风险**。超大控制器、DTO/Entity 混用、重复删除/刷新/迁移逻辑以及大量准死代码扩大变更风险。
- 测试与交付：**高风险**。无 XCTest/UI Test target、Scheme TestAction 为空、无 CI/Archive/隐私校验闭环。

## 3. 问题总览

| 级别 | 数量 | 结论 |
|---|---:|---|
| P0 | 0 | 未发现无需用户动作即可跨沙箱或导致全局失陷的确认项 |
| P1 | 13 | 数据破坏、敏感信息外发、核心状态错误、发布阻断 |
| P2 | 18 | 并发/异常/规模问题、契约和部署风险 |
| P3 | 5 | 架构、命名、重复实现和工程治理 |

## 4. P1 问题清单

### P1-01 恶意备份可路径穿越并覆盖应用容器内文件

- **问题位置**：`RDBackupManager.m:286-305`、`RDZipArchive.m:179-235`；数据库路径见 `RDDatabaseManager.h:11`、`RDDatabaseManager.mm:38`。
- **问题描述**：恢复时直接把不可信 `localPath`/`coverImg` 拼到 `Documents/LocalBooks`；ZIP 写入会先删除目标再移动 `.part` 文件，未校验标准化后的目标仍位于允许目录。
- **触发条件**：用户选择包含 `../book`、绝对路径、编码分隔符或符号链接语义的恶意备份，清单和 ZIP 条目相互配合。
- **实际影响**：可覆盖或删除沙箱内 WCDB 数据库、偏好/配置或本地书文件，造成完整书架损坏和行为篡改；iOS 沙箱仍阻止越出应用容器。
- **根本原因**：把备份 manifest 作为可信内部数据，没有安全路径解析、目标 allowlist、staging 和提交边界。
- **推荐修复方案**：忽略清单文件名，按内部 ID 与格式生成 basename；拒绝绝对路径、`..`、任意分隔符和符号链接；对标准化 URL 做后代关系校验；先恢复到随机 staging 目录，校验 manifest、CRC/摘要和容量后再原子提交。
- **涉及文件或模块**：备份恢复、ZIP、`RDLocalBookManager` 文件生命周期、数据库容器。
- **回归测试方法**：输入 `../`、多层 `..`、绝对路径、反斜杠、Unicode/百分号编码分隔符、符号链接及重复条目；恢复必须失败，数据库和容器哨兵文件 hash 必须不变。

### P1-02 归档和多格式 parser 缺少资源预算/边界检查，可被恶意文件耗尽内存或触发崩溃

- **问题位置**：`RDZipArchive.m:47-163`、`RDMobiBookParser.m:72,151`、`RDEpubBookParser.m:166,424-438`、`RDTxtBookParser.m:17-32,57-90`、`RDFontManager.m:129`、`RDComicHelper.m:70,184`；调用链还包括 `RDLocalBookManager.m:452`、`RDBackupManager.m:259`。
- **问题描述**：ZIP 信任 `uncompressedSize` 并整块申请/增长内存，无条目/累计量/压缩比/CRC 限制；MOBI 信任 `textLength` 和偏移预分配；EPUB 对开头 `..` 可能在空数组上 `removeLastObject`；TXT 整文件载入，超过 8000 章/约 6400 万字符后静默截断；字体/图片目录也缺少 magic、像素、文件数和递归深度预算。
- **触发条件**：导入 Zip Bomb、巨大/伪造长度 MOBI、越根 href EPUB、超大或异常编码 TXT、CRC 错误/截断归档。
- **实际影响**：进程 OOM、长时间 CPU、越界异常/崩溃、内容静默丢失，部分损坏数据还可能进入后续解析或恢复。
- **根本原因**：各 parser 被当作便利解码器而非不可信输入边界，缺少统一 magic 校验、checked arithmetic、路径约束和资源预算。
- **推荐修复方案**：建立 ImportPolicy；ZIP 有界流式 inflate 并限制文件/条目/单项/累计字节/压缩比、校验 CRC/header；MOBI 使用防溢出边界检查；EPUB 拒绝越根路径；TXT 流式解码且超限明确失败；字体/图片校验 magic、像素、数量和目录深度。
- **涉及文件或模块**：`RDZipArchive`、TXT/MOBI/EPUB、字体、漫画、备份、统一导入协调器。
- **回归测试方法**：构造 4 GB 声明/偏移、压缩炸弹、10 万条目、CRC 错误、截断流、leading `..` href、超大 TXT 和 fuzz corpus；断言内存/耗时受限、受控失败且无部分提交。

### P1-03 恶意备份可把现有 Keychain 密钥绑定到攻击者 AI 服务

- **问题位置**：`RDAIConfig.m:188,392-424`、`RDAIClient.m:189-225`。
- **问题描述**：恢复的 AI profile 若与本机现有 `profileId` 相同，会保留本机 Keychain 密钥，同时可替换 `baseURL` 并被设为 active。
- **触发条件**：导入特制备份，随后用户执行一次翻译。
- **实际影响**：本机 API Key 和选中书籍文本会被发送到攻击者控制的地址。
- **根本原因**：使用可导入的 profileId 作为秘密绑定身份，并允许不可信配置自动激活。
- **推荐修复方案**：导入配置重新生成 ID；秘密绑定到规范化 `(provider, HTTPS origin)`；导入后默认禁用并展示差异，要求用户重新授权/输入密钥；禁止旧备份明文密钥自动迁移。
- **涉及文件或模块**：AI 配置、Keychain、备份、网络客户端。
- **回归测试方法**：构造 profileId 碰撞且 origin 改为测试服务器的备份；恢复后旧 Key 不得附着、配置不得自动激活、确认前不得产生请求。

### P1-04 删除完成回调早于章节删除，立即重导会被迟到任务删掉新章节

- **问题位置**：`RDLocalBookManager.m:901-931`、`RDBookshelfCell.m:362-395`、`RDSettingController.m:486-511`。
- **问题描述**：read/file/bookmark/history 在 import queue 中删除后，chapter 删除又投递到无关全局队列；方法立即返回，UI 刷新并提示成功。
- **触发条件**：删除本地书后立即导入同一文件，或清空后立刻终止进程；稳定的负 bookId 使新旧导入命中同一 ID。
- **实际影响**：迟到删除可清掉新导入章节，出现“书在书架但不能阅读”；也可能残留章节。
- **根本原因**：同一本书的文件和多表生命周期没有单一串行器、事务和完成语义，接口返回 `void`。
- **推荐修复方案**：建立 `RDLibraryMutationCoordinator`，按 bookId 串行；DB 多表操作放入一个事务，文件先移至可回滚 staging；所有步骤成功后再完成/通知。
- **涉及文件或模块**：本地书删除、清空、重新导入、read/chapter/bookmark/history 表。
- **回归测试方法**：注入章节删除延迟，循环“删除→立即重导”100 次；完成后文件、read、chapter、bookmark/history 状态一致且书可打开。

### P1-05 备份恢复非原子且绕过导入串行边界

- **问题位置**：`RDBackupManager.m:257-449`、`RDLocalBookManager.m:856-895`。
- **问题描述**：恢复在全局队列执行，先覆盖源文件/封面，再解析和写库；章节重建是先删后插的两个独立 DB 调用；书签、规则、字体和 AI 配置又在书架通知之后恢复。
- **触发条件**：恢复期间并发导入、删除、生成 PDF 封面，或发生磁盘满、解析失败、杀进程。
- **实际影响**：旧 DB 可指向已覆盖源文件，章节为空、书签与配置半恢复，UI 在最终状态完成前显示成功；失败不可安全回滚。
- **根本原因**：缺少恢复状态机、预检、staging、数据库事务和文件/DB 提交日志。
- **推荐修复方案**：恢复分为 `validate → stage → DB transaction → atomic file commit → publish`；统一进入 mutation coordinator；记录 journal 以便启动时恢复或回滚。
- **涉及文件或模块**：备份、导入、文件、WCDB、通知/缓存。
- **回归测试方法**：在每个阶段故障注入（空间不足、解析失败、DB 写失败、进程中断），重启后只能是完整旧状态或完整新状态，不得出现混合状态。

### P1-06 备份允许缺失源文件/条目写失败仍报告成功

- **问题位置**：`RDBackupManager.m:61-219,448`。
- **问题描述**：manifest 先写；书籍源文件缺失时继续，配置/书签/规则/字体/普通封面和 AI JSON 的多个写入返回值被忽略，也没有完成后重新打开自检。
- **触发条件**：源文件被系统/用户移除、磁盘满、读写错误或 JSON 无效。
- **实际影响**：用户得到“备份成功”，但恢复时缺书、缺封面或缺配置；错误发现时原设备数据可能已不存在。
- **根本原因**：没有必需/可选条目契约和聚合错误模型；把 ZIP 创建成功等同于业务备份成功。
- **推荐修复方案**：定义 manifest schema、必需条目和摘要；任何必需条目失败则整体失败，可选条目汇总警告；写完重新读取并验证 CRC/摘要/条目数。
- **涉及文件或模块**：备份生成、ZIP writer、分享流程。
- **回归测试方法**：逐步骤注入读/写失败；断言失败可见、无“成功”提示，且生成物不进入可分享状态。

### P1-07 WCDB 写入、建表和迁移错误被吞，失败迁移仍可能标记完成

- **问题位置**：`RDDatabaseManager.mm:41-52,156-245`，以及各 Manager 的 insert/update/delete 调用。
- **问题描述**：多数数据库 API 不返回/不传播错误；主键迁移分批失败后仍可能写入 NSUserDefaults 完成标志。查询失败又常被转换为 `@[]`。
- **触发条件**：数据库损坏、磁盘满、文件保护未解锁、schema 冲突或迁移中断。
- **实际影响**：数据写入丢失但 UI 报成功；迁移永久跳过；书架把数据库故障显示为“空书架”，诱导用户继续覆盖数据。
- **根本原因**：Repository 契约缺少 `Result/error`，迁移没有版本表、事务和幂等验证。
- **推荐修复方案**：所有写接口返回明确结果；建立 `schema_migrations` 版本表和单事务迁移；完成标志只能在校验通过后写入；UI 使用 loading/content/empty/error 四态并保留最后好快照。
- **涉及文件或模块**：数据库管理器、所有数据 Manager、书架 UI、迁移。
- **回归测试方法**：模拟只读 DB、磁盘满、断电式中断和 schema 冲突；必须失败可见，可重试，原数据不被空快照覆盖。

### P1-08 “清空书架”未按用户承诺清除完整数据

- **问题位置**：`RDSettingController.m:464-511`、`RDBookmarkManager.mm:107-113`。
- **问题描述**：只枚举 `onBookshelf=YES`；遗漏已移出书架的历史 read/chapter/bookmark/history。对历史正 bookId 在线书分支也未删除 bookmark，多表操作非事务。
- **触发条件**：存在移出书架记录、旧版在线书或中途失败时执行“清空书架和阅读进度”。
- **实际影响**：隐私数据和孤儿记录仍留在库中，设置页提示与真实状态不符；后续恢复/统计可重新暴露旧数据。
- **根本原因**：删除规则散落在 Cell、Setting 和 LocalBookManager，未按领域聚合定义“清空”。
- **推荐修复方案**：由统一删除服务按产品语义查询所有书，事务清理 read/chapter/bookmark/history，再处理文件；明确是否连规则、AI cache 和导出文件一起清理。
- **涉及文件或模块**：设置、删除服务、四张数据表和文件目录。
- **回归测试方法**：构造正/负 bookId、书架内外、带书签/历史的组合；清空完成时表、文件、缓存、统计均符合确认文案。

### P1-09 书架刷新会丢弃最后请求，静态预取缓存存在跨线程数据竞争

- **问题位置**：`RDBookshelfController.m:494-521`、`RDBookshelfPrefetch.m:20-38,69-163`、`RDLocalBookManager.m:314-340`。
- **问题描述**：`isReloading` 时直接 return，没有 pending/dirty；多本导入的通知和最终刷新可能全被首个刷新吞掉。预取的全局静态状态在主线程和全局队列无同步读写，旧快照可覆盖新快照。
- **触发条件**：批量导入、刷新期间删除/改封面/恢复，尤其 PDF 封面回填拉长刷新窗口时。
- **实际影响**：DB 已正确但 UI 只显示部分书或旧封面，需切页/重启；在 TSan 下属于真实数据竞争。
- **根本原因**：布尔互斥代替 single-flight 合并状态机，快照没有 generation 和唯一所有者。
- **推荐修复方案**：串行 SnapshotStore；运行中请求置 `pending=YES`，完成后再拉一次；所有快照带递增 generation，旧结果不可提交；批量导入只在事务完成后通知一次。
- **涉及文件或模块**：书架、预取缓存、导入、PDF 封面、恢复/删除。
- **回归测试方法**：延迟首个刷新并同时导入 10 本、删除 1 本、改 1 个封面；最终 UI/缓存/DB 完全一致；TSan 并发 1000 次无竞争。

### P1-10 AI 翻译缓存未绑定原文和排版版本，改字号后可展示错误译文

- **问题位置**：`RDReadPageViewController.m:83-125,786-951`。
- **问题描述**：缓存 key 仅为 `bookId_chapterId_page`，缓存值还是旧主题/字体的 attributed string。字号/字体变化会让同一页码对应不同原文。
- **触发条件**：翻译页面后改变字号/字体，再回到相同页码；迟到请求与新分页并发。
- **实际影响**：译文与当前原文不匹配，属于内容正确性错误；主题切换也会显示旧样式。
- **根本原因**：以易变页码作为内容身份，缺少 text hash、配置版本和请求 generation。
- **推荐修复方案**：按规范化原文 hash、章节、目标语言和 provider/model 版本缓存结构化纯文本；展示时按当前主题渲染；分页变化递增 generation，迟到响应仅在 hash 一致时应用。
- **涉及文件或模块**：阅读分页、AI 翻译、字体、主题、缓存。
- **回归测试方法**：每页使用唯一原文，翻译后字号从 14 调至 28；逐页校验 source/translation 配对，延迟旧响应不得覆盖新分页。

### P1-11 大章节分页同步运行于主线程

- **问题位置**：`RDReadParser.m:16-93`、`RDReadPageViewController.m:119-125,198-211`。
- **问题描述**：API 虽有 completion，CoreText 全章分页实际同步；打开、切章和字体变化均从主线程调用。
- **触发条件**：数 MB 单章或快速连续改字号。
- **实际影响**：界面冻结、重复无效计算，极端情况下触发 watchdog 终止。
- **根本原因**：分页引擎没有异步执行、取消、generation、内容/布局缓存和异常章节预算。
- **推荐修复方案**：后台分页不可变配置快照；仅最新 generation 回主线程；缓存 `(contentHash, bounds, typography)` 的页偏移；对超长章节预切分。
- **涉及文件或模块**：文本阅读、分页、字体/净化规则。
- **回归测试方法**：1 MB/5 MB 单章打开并连续改字号；主线程无长任务，旧计算不得覆盖新配置，页码/进度正确。

### P1-12 应用隐私清单未申报实际使用的 Required Reason API

- **问题位置**：`PrivacyInfo.xcprivacy:7` 的 `NSPrivacyAccessedAPITypes` 为空；调用见 `RDDatabaseManager.mm:158`、`RDVoiceManager.m:34`、`NSFileManager+rd_wid.m:76`。
- **问题描述**：应用直接使用 NSUserDefaults，并编译了磁盘空间/文件元数据访问，但隐私清单没有任何类别与理由。
- **触发条件**：Archive 后由 App Store Connect 静态分析。
- **实际影响**：上传被拒或要求修正，构成明确发布阻断。
- **根本原因**：隐私清单仅创建了空壳，发布流程没有生成/审查 Privacy Report。
- **推荐修复方案**：按真实用途至少申报 UserDefaults 合法理由；移除未使用 API；以 Xcode Privacy Report 判定文件元数据类别，不得随意选择理由码。
- **涉及文件或模块**：隐私清单、Defaults、文件/语音工具、发布流程。
- **回归测试方法**：Archive 生成 Privacy Report，`plutil` 校验包内清单，并通过 App Store Connect/TestFlight 验证无 Required Reason 警告。参考 [Apple Required Reason API 文档](https://developer.apple.com/documentation/bundleresources/describing-use-of-required-reason-api)。

### P1-13 受 Apple 管控的旧第三方 SDK 缺少独立隐私清单

- **问题位置**：`Podfile.lock` 中 AFNetworking 3.2.1、MBProgressHUD 1.1.0、SDWebImage 5.6.1；当前 `Pods` 未发现对应 `PrivacyInfo.xcprivacy`。
- **问题描述**：Apple 要求清单中的常用第三方 SDK 自带独立隐私 manifest，应用自己的 manifest 不能替代 SDK manifest。SDK 签名要求针对以二进制方式引入的依赖；当前这些 CocoaPods 是源码集成，本问题不据此声称缺少 SDK 签名。
- **触发条件**：新 App 或更新中新增/重新引入这些 SDK并提交审核；具体结果仍以当前 App Store Connect 验证为准。
- **实际影响**：可能出现 ITMS-91061 并阻止提交。
- **根本原因**：依赖版本长期未升级，本地产品形态已不需要部分在线 SDK，却仍全部链接。
- **推荐修复方案**：优先移除不再使用的在线链路和依赖；其余升级到官方带 manifest 的版本；用归档而非源码目录作为最终验证对象。
- **涉及文件或模块**：CocoaPods、旧在线服务、图片/HUD、发布。
- **回归测试方法**：检查 Archive Privacy Report 和每个受管 SDK bundle；执行 App Store Connect 验证。参考 [Apple 第三方 SDK 要求](https://developer.apple.com/support/third-party-SDK-requirements/)。

## 5. P2 问题清单

### P2-01 基础控制器生命周期方法拼写错误，离场取消逻辑从未执行

- **问题位置**：`RDBaseViewController.m:42-53`。
- **问题描述**：实现的是 `viewDisappear:`，不是 UIKit 的 `viewWillDisappear:`。
- **触发条件**：请求进行中离开继承该基类的详情、搜索、目录等页面。
- **实际影响**：请求不按设计停止，迟到回调可更新离屏 UI并延长控制器/HUD 生命周期。
- **根本原因**：依赖隐式生命周期重写，没有编译期 `override` 能力或行为测试。
- **推荐修复方案**：修正生命周期；更进一步建立显式 RequestBag，区分页面级请求与允许跨页面的 TTS/后台翻译任务。
- **涉及文件或模块**：基础控制器和所有子类网络请求。
- **回归测试方法**：启动延迟请求后立即返回；断言 stop 一次、UI 不再更新、VC 释放，同时后台任务不被误取消。

### P2-02 目录列表存在主线程 N+1，并读取完整章节正文只为判断状态

- **问题位置**：`RDReadCatalogCell.m:29-34`，对照已加载的章节摘要列表。
- **问题描述**：每个 cell 配置都按章节再次查询并反序列化正文，而 UI 只需要标题/是否有内容。
- **触发条件**：滚动包含数千/上万章节的目录。
- **实际影响**：查询次数线性增长，主线程卡顿、内存抖动；旧库的大 BLOB 会放大问题。
- **根本原因**：列表 DTO 缺少轻量状态字段，Cell 直接访问 Repository。
- **推荐修复方案**：一次查询轻量 projection（id/name/contentLength/status）并由 ViewModel 提供；Cell 不发 DB 请求。
- **涉及文件或模块**：目录 UI、章节 Repository、schema projection。
- **回归测试方法**：1 万章节 fixture；打开/滚动目录的 SQL 次数应为常数级，主线程无正文反序列化，首屏耗时设定基准。

### P2-03 书签“检查后插入”非原子，契约阈值还存在 ±20/±40 不一致

- **问题位置**：`RDBookmarkManager.h`、`RDBookmarkManager.mm:17-58,115-129`。
- **问题描述**：先查询相近位置再插入，两个并发请求都可能通过；注释和实现的距离阈值不一致，表上无业务唯一约束。
- **触发条件**：重复点击或两个阅读事件并发添加同位置书签。
- **实际影响**：产生重复书签；不同调用者对“已存在”的判断不一致。
- **根本原因**：幂等性只在应用层做非原子检查，领域键未建模。
- **推荐修复方案**：明确 `(bookId, chapterId, normalizedOffset)` 业务键与阈值；事务/唯一索引 + upsert；接口返回 inserted/alreadyExists/error。
- **涉及文件或模块**：书签 Manager、表结构、阅读菜单。
- **回归测试方法**：并发 100 次同位置及阈值边界插入；最终只能一条，结果码稳定，±边界与契约一致。

### P2-04 章节 upsert 每批扫描整本目录且不更新元数据

- **问题位置**：`RDCharpterDataManager.mm:74-104`。
- **问题描述**：为判断存在性先加载全部章节 ID；已存在行只更新 content，忽略 name/bookName/author 等变化，并假设输入只属于一本书。
- **触发条件**：大目录增量更新、书籍改名、服务端章节标题修正或混入多个 bookId。
- **实际影响**：复杂度随章节数增长，元数据长期陈旧，错误批次可能更新到不一致状态。
- **根本原因**：upsert contract 不明确，批处理没有数据库原生冲突处理和输入约束。
- **推荐修复方案**：按业务键建立索引并使用事务 upsert；明确可变字段；入口验证同一 bookId；避免先全表读取。
- **涉及文件或模块**：章节 Manager、导入/远端更新、schema。
- **回归测试方法**：10 万章节分批更新，检查查询计划/SQL 次数；修改标题/作者后所有字段按契约更新；混 bookId 输入被拒绝。

### P2-05 网络 DTO、书籍实体、阅读记录和历史记录共用一个模型

- **问题位置**：`RDBookDetailModel.h`、`RDBookDetailModel.mm:17-34`及多个 API/DB 调用点。
- **问题描述**：模型包含大量远端、UI和本地字段，但 WCDB 只持久化子集；`total/end/category` 等导入/网络值重启后静默丢失。
- **触发条件**：对象跨 API → DB → 重启 → UI 链路，或新增字段时误以为已持久化。
- **实际影响**：状态依赖内存旧值，历史兼容不可预测；权限/来源字段也难以建立可信边界。
- **根本原因**：传输、领域和存储模型未分层，字段默认值掩盖缺失。
- **推荐修复方案**：拆为 API DTO、BookEntity、ReadProgress、BookshelfViewModel，显式 mapper；持久化字段有版本化 schema 和 migration。
- **涉及文件或模块**：Model、Service、数据库、书架/阅读。
- **回归测试方法**：对每个字段做 API fixture → 映射 → 持久化 → 重启 round-trip；未支持字段必须编译/测试失败而非静默丢失。

### P2-06 改名不是领域事务，可能虚假成功且关联数据/文字封面仍是旧名

- **问题位置**：`RDBookshelfCell.m:326-359`、`RDReadRecordManager.mm:97-111`、`RDLocalBookManager.m:514-536,800-816`。
- **问题描述**：UI 先改内存，再调用返回 void 的单表更新；空白/超长标题缺少反馈；chapter/bookmark/history 的反规范化标题及自动文字封面不会同步。
- **触发条件**：有书签/历史后改名、DB 写失败、输入空格/超长 Emoji。
- **实际影响**：书架、目录、备份和历史显示不同名称；重启后名称回滚，用户却已看到成功。
- **根本原因**：Cell 直接执行业务，书名有多份事实来源且没有 RenameBook transaction。
- **推荐修复方案**：统一 `renameBook` 服务，按 grapheme 校验长度，事务更新必要冗余或消除冗余；成功后再更新 UI；自动封面按 title revision 重建。
- **涉及文件或模块**：书架 Cell、read/chapter/bookmark/history、封面。
- **回归测试方法**：空白、1 万字符、组合 Emoji、DB 失败、带书签/历史/自动封面改名；所有入口显示一致，阅读进度不变。

### P2-07 手动封面替换/恢复先破坏旧状态且无可靠错误返回

- **问题位置**：`RDLocalBookManager.m:771-797`、`RDBookshelfController.m:463-472`。
- **问题描述**：替换时先删除旧封面再校验/写新图；恢复默认吞掉删除错误，Controller 固定提示成功。
- **触发条件**：无效图片、备份缺文件、磁盘/文件保护错误或写入中断。
- **实际影响**：原封面不可恢复，UI 提示与实际文件不一致。
- **根本原因**：文件 API 没有 staging/原子 replace 和 Result，UI 直接假设成功。
- **推荐修复方案**：新封面先解码、限制像素/格式、写临时文件并 fsync/原子替换；Manager 返回明确结果；失败保留旧文件与旧 revision。
- **涉及文件或模块**：封面选择、恢复默认、备份恢复、书架刷新。
- **回归测试方法**：注入无效图、写失败、删除失败和中断；旧封面保持，错误可见，重复恢复幂等。

### P2-08 PDF 首页封面回填混入每次刷新，损坏/锁定 PDF 会永久重试

- **问题位置**：`RDLocalBookManager.m:266-325,445-450`、`RDBookshelfPrefetch.m:69-82`、`RDBookshelfController.m:500-508`。
- **问题描述**：每次书架刷新遍历所有 PDF 并打开/解码；失败没有持久化状态。导入无效、零页或锁定 PDF 时仍可能创建书籍结果。
- **触发条件**：数百/上千 PDF，包含损坏、空页、密码保护文件。
- **实际影响**：刷新耗时线性增长，失败文件持续拖慢首屏；书可能导入成功却打不开且永远无封面。
- **根本原因**：一次性/增量派生资源任务放在热读路径，缺少格式预检和版本化任务状态。
- **推荐修复方案**：导入时验证 PDF 可打开且页数 > 0；封面任务保存 `pending/success/failed + source hash/mtime + generatorVersion`，后台限流，书架不等待。
- **涉及文件或模块**：PDF 导入、封面生成、预取/书架。
- **回归测试方法**：1000 本 PDF（含 100 个损坏/锁定）；首屏不等待全库，失败项不重复，源文件变化后才重试。

### P2-09 本地封面与漫画页面存在主线程同步磁盘读取/完整图片解码

- **问题位置**：`RDBookshelfCell.m:51-80,268`、`RDLocalBookManager.m:661-666,800-816`、`RDComicReadController.m:185-224`。
- **问题描述**：Cell 配置/长按会完整解码封面；漫画当前页 cache miss 时主线程 inflate ZIP 并创建 UIImage；NSCache 仅限数量、不限成本。
- **触发条件**：高速滚动、文件缓存冷、快速翻到 20–50MP 漫画图。
- **实际影响**：掉帧、翻页冻结和内存峰值，旧异步预取还可能晚到串页。
- **根本原因**：文件存在性、解码和展示耦合，没有 thumbnail/downsample、cost 和 request generation。
- **推荐修复方案**：CoverProvider 提供元数据与异步缩略图；漫画用 ImageIO 按显示尺寸下采样，后台解压，按页 generation 应用，设置 `totalCostLimit`。
- **涉及文件或模块**：书架 Cell、封面服务、漫画阅读器。
- **回归测试方法**：1000 本书滚动及大图 CBZ 快速翻页；Main Thread Checker/Instruments 无同步 I/O/大图解码，内存受限且不串图。

### P2-10 设置刷新、导入路由、重复打开和格式间续读没有统一状态机

- **问题位置**：`RDSettingController.m:112-177,332-339`、`RDBookshelfController.m:45-97`、`RDBookshelfCell.m:203-215`、`RDReadHelper.m:24-90`、各格式 Reader 启停代码。
- **问题描述**：存储刷新运行中丢掉最后请求；设置页先同步通知书架 present picker 再切 Tab；快速双击可重复 push；只有文本 Reader 维护冷启动续读缓存。
- **触发条件**：扫描中清空/恢复、从设置导入、快速多击、分别在文本/PDF/漫画阅读时杀进程。
- **实际影响**：统计长期显示旧值、picker 可能不出现、导航栈重复、不同格式恢复规则不一致。
- **根本原因**：入口通过通知/Cell 私自导航，缺少 ImportCoordinator、ReadCoordinator、ReadSessionManager 和 generation。
- **推荐修复方案**：统一路由和会话；先切可见 Tab 再 present；按 bookId single-flight；明确三种格式统一的冷启动策略；设置扫描也使用 pending + generation。
- **涉及文件或模块**：设置、书架、路由、三类阅读器。
- **回归测试方法**：需要进一步验证：iOS 15/17/18 真机从各入口导入并快速点击；断言只出现一个 picker/Reader，三种格式杀进程后的行为一致，统计最终为最新值。

### P2-11 后台翻译停止/重开不取消旧请求，可突破并发上限和重复计费

- **问题位置**：`RDReadPageViewController.m:886-960`、`RDAIClient.m:71-99,419-518`。
- **问题描述**：停止只清空 pending key，不取消 task；立即重开可对同页再次请求，旧回调又会删除新 pending。客户端共享可变状态跨主线程和 URLSession 回调队列访问。
- **触发条件**：网络延迟时连续停止/开启翻译，或多页请求同时完成。
- **实际影响**：重复请求/费用、并发限制失效、旧会话结果覆盖新会话；共享状态还需 TSan 验证。
- **根本原因**：pending 集合没有 task identity/session generation，网络状态无串行隔离。
- **推荐修复方案**：保存 taskId + generation；停止时取消或使旧 generation 失效；回调只修改匹配 task；RDAIClient 用 actor/串行队列管理状态。
- **涉及文件或模块**：AI 客户端、阅读翻译 session、缓存。
- **回归测试方法**：延迟 transport 下切换 10 次；最大并发不超配置，每 generation 每页一次，旧响应不更新 UI；TSan 无竞争。

### P2-12 Keychain 更新“先删后加”并忽略 OSStatus

- **问题位置**：`RDAIConfig.m:70-102,338,464`、`RDAIProfileEditController.m:99-125`。
- **问题描述**：删除旧项后再 add，任一步结果不传播；profile 保存仍显示成功。
- **触发条件**：Keychain locked、权限/entitlement 错误、add 失败。
- **实际影响**：旧密钥已丢、新密钥未保存，用户直到重启/请求才发现。
- **根本原因**：Keychain helper 返回 void，元数据与秘密没有可恢复提交顺序。
- **推荐修复方案**：优先 `SecItemUpdate`，不存在才 add；返回 OSStatus/可读错误；秘密成功后才提交 profile 元数据。
- **涉及文件或模块**：AI 配置、Keychain、设置 UI。
- **回归测试方法**：注入 duplicate、interaction-not-allowed、missing-entitlement；旧 Key 保留、UI 报错、元数据不提交。

### P2-13 自定义 AI 地址允许 HTTP，且局域网用途说明缺失

- **问题位置**：`RDAIProfileEditController.m:99`、`RDAIClient.m:131,199`、`Info.plist:146`。
- **问题描述**：只验证 URL 非空/可解析，不限制 scheme；ATS 仅允许 local networking，但未配置 `NSLocalNetworkUsageDescription`。
- **触发条件**：用户配置 `http://` LAN/public 网关，或首次访问局域网服务。
- **实际影响**：API Key 和书籍文本可能明文传输；真机权限提示/拒绝路径可能不符合预期。
- **根本原因**：把兼容性 URL 当成普通字符串，未把传输安全和本地网络权限纳入产品契约。
- **推荐修复方案**：默认仅 HTTPS；HTTP 最多限 loopback 且不发送真实 Key，LAN 使用 TLS/明确风险确认；补充真实用途说明。
- **涉及文件或模块**：AI Profile、URLSession、ATS/Info.plist。
- **回归测试方法**：HTTP public/LAN/`.local`/loopback、HTTPS、自签名/MITM；需要进一步验证真机干净安装的权限提示与拒绝行为。参考 [Apple 本地网络说明](https://developer.apple.com/documentation/bundleresources/information-property-list/nslocalnetworkusagedescription)。

### P2-14 备份语义不一致、明文导出且成功分享后未及时清理

- **问题位置**：`RDBackupManager.m:99-198,352-449`、`RDZipArchive.m:303`、`RDSettingController.m:378`。
- **问题描述**：配置/规则/书签/封面混用 replace/merge/skip；`lineSpace` 写出但不完整恢复，空规则不能清旧值，书签只 upsert，旧备份缺封面可删除当前封面；导出 ZIP 明文且同日固定名留在 `Caches/Exports`。
- **触发条件**：在有现存数据的设备恢复不同版本备份，或分享后第三方文件提供商保留导出。
- **实际影响**：恢复结果依赖设备恢复前状态，无法证明 round-trip；书籍原文、笔记/书签可被导出持有者直接读取。
- **根本原因**：没有版本化 manifest 和每类数据的明确 replace/merge 策略，也没有导出生命周期/敏感提示。
- **推荐修复方案**：为每类数据定义版本、默认值和策略；恢复预览差异；导出使用随机名、适当 File Protection、分享完成/启动时清理，可选认证加密封装。
- **涉及文件或模块**：备份 schema、设置、导出分享、缓存目录。
- **回归测试方法**：新/旧/空备份在空设备和非空设备 round-trip；取消/成功/失败分享后检查清理；篡改/错误密码（若加密）必须失败。

### P2-15 数据库索引、分页和历史 schema 迁移不足，大数据下风险需要验证

- **问题位置**：`RDBookDetailModel.mm:34`、读记录/章节查询、旧 `charpterModel` 与 `readChapterName` 迁移代码。
- **问题描述**：书架只有 `onBookshelf` 单列索引，但常按过滤 + `readTime` 排序；列表无稳定 tie-break/分页。旧章节 BLOB 未清瘦，新列未回填，迁移机制还分散。
- **触发条件**：数万书籍/十万章节、相同 readTime、从老版本连续升级。
- **实际影响**：可能全表扫描、内存排序、分页重复/漏项；旧用户副标题为空且 DB 持续膨胀。
- **根本原因**：schema 由当前小数据量反推，缺少查询计划和版本化数据迁移。
- **推荐修复方案**：基于实际 SQL 建 `(onBookshelf, readTime, bookId)` 等匹配索引；keyset 分页和稳定排序；迁移旧 BLOB/回填新列并校验行数。
- **涉及文件或模块**：WCDB schema、read/chapter 表、迁移、书架查询。
- **回归测试方法**：需要进一步验证：使用目标基数跑 `EXPLAIN QUERY PLAN` 和 P95 基准；覆盖相同排序值、升级中断、连续跨版本升级和数据 hash 对账。

### P2-16 本地书 identity 只使用 MD5 前 55 bit，碰撞会合并不同书籍

- **问题位置**：`RDLocalBookManager.m:545-603`。
- **问题描述**：负 bookId 来自截断 digest，去重不再核对完整摘要/文件身份。
- **触发条件**：自然或构造的截断碰撞，或者业务规模长期增长。
- **实际影响**：不同文件被视为同一本，覆盖章节/进度/封面，删除一书影响另一书。
- **根本原因**：把短整数 ID 同时用作存储主键和内容唯一身份。
- **推荐修复方案**：保存完整 SHA-256 content fingerprint；DB 使用独立 UUID/自增 ID；导入冲突时对完整摘要和格式元数据做二次确认。
- **涉及文件或模块**：导入去重、bookId 外键、备份兼容。
- **回归测试方法**：注入相同短 ID、不同 full hash 的 fixture；必须创建两个实体或明确冲突，不得共享章节/进度；验证老 ID 迁移映射。

### P2-17 遗留在线接口仍编译，HTTP/响应契约和页面竞态均未治理

- **问题位置**：`RDMainController.m:44-49`、`RDGlobalModel.m:38,61-68`、`RDBaseApi.m:18-60`、`RDHttpModel.*`、Discover/Library/Search/Service。
- **问题描述**：当前主 UI 不展示在线模块，但约 51 个实现/4860 行仍在 target；基址为公共 HTTP，ATS local 例外不放行；2xx 缺失/错误类型的 `result.code` 会因标量默认 0 被当成功。旧搜索还会被迟到的 A 请求覆盖当前 B。
- **触发条件**：旧远程书记录、隐藏/未来入口重新接入、远程封面或服务端返回协议漂移。
- **实际影响**：接口/图片不可用或空数据假成功；迟到结果串页面；无用依赖扩大攻击面和构建成本。
- **根本原因**：产品转为本地模式后未删除旧垂直切片；公共网络层无 schema validator、request token 和 HTTPS 迁移。
- **推荐修复方案**：确认无 URL Scheme/路由依赖后从 target 删除在线模块及 YTK/AF 等无用依赖；若保留，先迁 HTTPS、严格 envelope validator、统一错误模型和 latest-request-wins。
- **涉及文件或模块**：遗留前端、YTK/AF、Model/Service、远端 API。
- **回归测试方法**：本地产品移除后做全功能回归；若保留，mock 缺字段/错类型/HTML/4xx/5xx和 A/B 乱序，且做 ATS/TLS 验证。

### P2-18 构建/发布和依赖供应链缺少可复现闭环

- **问题位置**：`Podfile:28-75`、`project.pbxproj:1977-1986`、`Reader.xcscheme:25,73`。
- **问题描述**：Podfile 安装后正则修改第三方源码并全局关闭脚本沙箱，无版本/hash/替换次数断言；Release 写有 Apple Development（Automatic Signing 可能导出时重签）；`CURRENT_PROJECT_VERSION=1.0.0.1`；无 CI、ExportOptions 或发布脚本。
- **触发条件**：干净机 `pod install`、依赖内容漂移、CI Archive/App Store 上传。
- **实际影响**：补丁可能静默失效、构建脚本读取更多 CI 文件；签名/版本是否可提交不可证明，发布依赖个人 Xcode 状态。
- **根本原因**：兼容旧依赖的本地补丁取代了受控依赖升级和可复现 pipeline。
- **推荐修复方案**：升级/移除旧依赖；开启脚本沙箱并声明输入输出；补丁锁定版本/hash且不匹配即失败；建立 archive/export/validate/SBOM/SCA pipeline；build number 使用 Apple 支持的一到三段整数。
- **涉及文件或模块**：CocoaPods、Xcode project/scheme、签名、CI/CD。
- **回归测试方法**：需要进一步验证：两次干净安装产物 hash、篡改补丁目标必须失败；CI 生成 signed IPA，校验 entitlements/provisioning/隐私/安装启动并通过 App Store Connect。版本格式参考 [Apple CFBundleVersion 文档](https://developer.apple.com/documentation/bundleresources/information-property-list/cfbundleversion)。不在没有 SCA 结果时声称具体 CVE。

## 6. P3 问题清单

### P3-01 阅读页、书架页和设置页职责过载

- **问题位置**：`RDReadPageViewController.m` 约 1241 行、`RDLocalBookManager.m` 约 934 行、`RDBookshelfController.m` 约 529 行、`RDSettingController.m` 约 514 行。
- **问题描述**：控制器/Manager 同时承担渲染、分页、TTS、翻译、分享、文件、DB、路由和状态机；阅读器前后翻页构建还有大段重复。
- **触发条件**：任意新格式、缓存或恢复功能改动。
- **实际影响**：改动影响面无法局部证明，容易复制相似但不一致的逻辑，单元测试难建立。
- **根本原因**：按页面堆功能而非按领域能力组合。
- **推荐修复方案**：拆出 PageEngine、ReadSession、TranslationSession、SpeechCoordinator、LibraryMutationCoordinator、CoverProvider、BackupService；以章节页描述符合并重复翻页逻辑。
- **涉及文件或模块**：阅读、书架、设置、本地书。
- **回归测试方法**：先锁定现有契约测试，再逐组件替换；每次拆分后 golden UI/进度/翻页/备份结果一致。

### P3-02 两套 schema 迁移机制并存，临时连接 PRAGMA 不作用于 WCDB 主连接

- **问题位置**：`RDDatabaseManager.mm:112-245`及 WCDB 自动建表/加列逻辑。
- **问题描述**：自动加列与 raw SQLite `ALTER TABLE` 重复；`wal_autocheckpoint=100` 设置在临时连接，新的 WCDB 连接仍回到默认值（已用双连接实验确认）。
- **触发条件**：升级 schema 或依赖 checkpoint 参数进行性能假设。
- **实际影响**：迁移顺序和配置实际值难推断，维护者可能基于无效设置调优。
- **根本原因**：数据库生命周期没有单一 owner 和版本状态。
- **推荐修复方案**：统一版本化 migration runner；连接级 PRAGMA 必须在 WCDB 实际连接初始化时设置并读回验证。
- **涉及文件或模块**：数据库初始化、迁移、WAL。
- **回归测试方法**：每版 schema 升级 fixture；新连接读取 PRAGMA 应为预期值，迁移只能执行一次且可中断恢复。

### P3-03 命名、nullability 和对象契约不一致

- **问题位置**：`charpter`、`isExsit`、`getHisory` 等命名；`RDBaseApi.h:17-25` 与 `.m:60`；`RDBookDetailModel.mm:69-82`。
- **问题描述**：拼写错误成为公开 API；nonnull error 在成功时传 nil；模型重写 `isEqual:` 但未同步重写 `hash`。
- **触发条件**：Swift/静态分析接入、模型进入 set/dictionary、重构自动补全。
- **实际影响**：错误契约、集合行为异常和长期命名债务。
- **根本原因**：缺少编译器警告门禁、API review 和模型契约测试。
- **推荐修复方案**：兼容层逐步更名；修正 nullable；`isEqual/hash` 同步或移除自定义相等；新代码开启更严格 warning。
- **涉及文件或模块**：Model、数据库 Manager、网络公共层。
- **回归测试方法**：编译期 nullability 检查；相等对象在 NSSet/NSDictionary 中行为一致；旧 API 有迁移期测试。

### P3-04 错误响应和通用 JSON 工具可能记录/展示原始敏感内容

- **问题位置**：`RDAIClient.m:488-503`、`NSData+rd_wid.m:253-265`、`NSString+rd_wid.m:158-171`。
- **问题描述**：短错误体可原样显示；通用 JSON 失败日志打印完整 body。
- **触发条件**：兼容网关回显 prompt/内部路径/凭据片段，或未来把工具用于用户数据。
- **实际影响**：屏幕、截图或设备日志泄露书籍文本/服务内部信息。
- **根本原因**：错误诊断与用户展示/生产日志没有脱敏边界。
- **推荐修复方案**：生产只展示结构化错误码与 requestId；日志长度限制、字段 allowlist 和隐私标记，Debug 才允许受控 body。
- **涉及文件或模块**：AI 错误、Category 日志、可观测性。
- **回归测试方法**：4xx 回显 prompt/key/路径，UI 和 release 日志均不得包含敏感值。

### P3-05 固定布局、旋转声明和无效状态不一致

- **问题位置**：多处 `ScreenWidth/ScreenHeight`；`Info.plist` iPad orientation；`RDNavigationController.m:23-32`；`RDBookshelfController.m` 的 `bookSource`。
- **问题描述**：工程声明 iPad 多方向但导航/基类禁止旋转；布局依赖全屏宏；`bookSource` 只写不读。
- **触发条件**：iPad 分屏/旋转、Stage Manager、未来适配。
- **实际影响**：声明和运行行为不一致，布局可能越界；无效状态增加认知负担。
- **根本原因**：设备能力与页面实现没有统一产品决策，状态未持续清理。
- **推荐修复方案**：若仅竖屏则收紧 plist；若支持 iPad 则改用容器/safe area；删除只写状态。
- **涉及文件或模块**：导航、布局、书架状态。
- **回归测试方法**：需要进一步验证目标设备矩阵；旋转/分屏快照测试，声明方向都必须可用，否则仅声明真实支持方向。

## 7. 按技术层归类的问题清单

### 7.1 前端问题

| 主题 | 对应问题 | 核心结论 |
|---|---|---|
| 状态一致性 | P1-09、P2-10 | 刷新和导航没有 pending/generation/single-flight，不同入口及快速操作结果不一致 |
| 内容正确性 | P1-10 | 翻译缓存按页码而非原文 identity，排版变化后可串译文 |
| 主线程性能 | P1-11、P2-02、P2-08、P2-09 | 分页、目录查询、PDF 回填、封面/漫画解码可阻塞 UI |
| 生命周期/内存 | P2-01、P2-11 | 页面离场不取消；旧翻译任务跨 session 存活并更新状态 |
| 错误状态 | P1-07、P2-06、P2-07、P2-12 | DB/文件/Keychain 失败常被渲染为空态或成功态 |
| 路由/入口 | P2-10 | 设置、空态、顶栏、外部文件入口没有统一 Coordinator |
| 组件职责 | P3-01、P3-05 | Cell/Controller 执行业务写操作，God Controller 与固定布局增加变更风险 |

前端权限绕过方面：当前主业务是本地单用户应用，没有客户端用户角色系统；未发现通过 UI 隐藏即可绕过的本地角色权限。远端资源授权不能由前端按钮或 bookId 正负值保证，必须由仓库外服务端验证。

### 7.2 后端/客户端业务层问题

本仓库没有服务端实现。本节所称“后端”包括客户端 Service/Manager/Repository 以及可观察到的远端 API 契约。

| 主题 | 对应问题 | 核心结论 |
|---|---|---|
| 业务事务 | P1-04、P1-05、P1-08 | 删除、恢复、清空跨文件与多表，没有统一提交/回滚 |
| 不可信输入 | P1-01、P1-02、P1-03 | 备份路径、归档长度和 AI identity 缺少信任边界 |
| 错误传播 | P1-06、P1-07、P2-07、P2-12 | `void`/忽略返回值使部分成功和假成功扩散到 UI |
| 幂等/并发 | P1-04、P2-03、P2-11 | 同书删除重导、书签重复和翻译 session 没有幂等键 |
| API 契约 | P2-17 | 缺 schema validator、统一错误模型和请求版本；服务端契约未知 |
| 配置/安全 | P2-13、P2-18 | URL scheme、权限说明、依赖补丁和发布配置未形成闭环 |

### 7.3 数据库问题

| 主题 | 对应问题 | 核心结论 |
|---|---|---|
| 事务边界 | P1-04、P1-05、P1-08 | 文件、read/chapter/bookmark/history 无原子业务事务 |
| 错误/迁移 | P1-07、P3-02 | 写入失败被吞；迁移完成标志、两套 migration 与连接 PRAGMA 不可靠 |
| 约束/幂等 | P2-03、P2-04、P2-16 | 书签/章节/书籍 identity 缺稳定业务键与冲突策略 |
| 模型一致性 | P2-05、P2-06 | DTO/Entity 混用，冗余标题跨表不一致 |
| 索引/规模 | P2-02、P2-04、P2-15 | N+1、全量扫描、过滤排序索引和稳定分页不足 |
| 历史兼容 | P1-08、P2-14、P2-15 | 旧在线书、旧 BLOB、新列回填与备份语义未形成版本矩阵 |

外键方面，当前大量关联依赖 bookId 约定和手工删除，而非数据库级 FK/cascade。鉴于文件系统也参与生命周期，不能简单新增 cascade；应先定义领域事务，再决定哪些关联由 FK 保证，哪些由服务协调，并对现有孤儿数据做迁移审计。

### 7.4 权限、异常、部署与测试配置

- 本地权限：文档 picker、相册保存、Personal Voice、本地网络等需在真机分别验证首次允许、拒绝、设置中撤销和受限状态。当前确认缺少本地网络用途说明（P2-13）。
- 数据保护：主 DB/本地书使用 `NSFileProtectionCompleteUntilFirstUserAuthentication`；SQLCipher 虽链接但未确认设置数据库密钥，WAL/SHM 保护属性也需真机核验。若威胁模型要求“设备首次解锁后再次锁屏仍不可读”，现配置不足；这是**需要进一步验证**的产品安全需求，不直接判漏洞。
- 异常处理：目前错误多在 Manager 被吞，导致 UI 无法区分 empty/error/partial。统一 Result 和错误码是修复多数假成功的前提。
- 部署：P1-12/P1-13 是发布阻断风险，P2-18 是签名、版本与供应链可复现性风险。
- 测试：工程只有一个 App target，Scheme TestAction 为空；唯一自动测试是独立 AI Harness，不能覆盖 UIKit、WCDB、文件系统和应用生命周期。

## 8. 完整业务与接口调用链

### 8.1 本地书导入链路

`书架顶栏/空态/设置/外部文件 → UIDocumentPicker → RDLocalBookManager import queue → 格式 parser → LocalBooks 文件 → read/chapter DB → 通知 → RDBookshelfController/RDBookshelfPrefetch`

- 正常路径：本地串行导入可降低同批文件竞争。
- 失败路径：parser/DB/file 错误没有统一事务和 Result（P1-06/P1-07）。
- 多入口：设置入口先通知后切 Tab，需真机验证；外部/顶部入口与设置入口不是同一路由状态机（P2-10）。
- 重复/快速：短 bookId identity、批量通知和刷新丢请求使去重/最终显示不可靠（P1-09/P2-16）。
- 大/恶意输入：ZIP/TXT/MOBI/PDF/图片缺统一预算（P1-02/P2-08）。

闭环要求：只有“文件安全落盘 + 全部 DB 写成功 + 派生封面任务已登记”才算 import committed；UI 最终必须以提交后的最高 generation 快照为准。

### 8.2 书籍信息、封面与删除链路

`Cell 长按 → Alert/Picker → Cell/Controller 直接调用 Manager → 单表更新或文件删除 → 通知/刷新`

- 改名只更新 read 表且先改内存（P2-06）。
- 手动封面替换/恢复无原子性与错误返回（P2-07）。
- 删除完成早于章节任务，立即重导会反向删除新数据（P1-04）。
- 清空逻辑在设置页另写一套并遗漏历史记录（P1-08）。

闭环要求：这些入口均应调用统一的领域命令，成功回调之后 read/chapter/bookmark/history/file/cover/cache 必须处于同一 revision；失败不得更改旧 UI 快照。

### 8.3 阅读、进度和书签链路

`书架 Cell → RDReadHelper → 根据格式选择 Reader → chapter/PDF/ZIP 读取 → 分页/解码 → UI → 进度/书签写回 WCDB`

- 快速点击缺 route single-flight，可能重复 Reader（P2-10）。
- 文本分页、大漫画解码、目录 N+1 阻塞主线程（P1-11/P2-02/P2-09）。
- 文本/PDF/漫画冷启动 session 规则不同（P2-10）。
- 书签去重非原子，DB 失败无法反馈（P1-07/P2-03）。

闭环要求：导航一次只打开一个 book session；进度写入有明确 revision/最后写入规则；书签命令幂等；任何格式的恢复策略一致。

### 8.4 AI 翻译链路

`阅读页选择文本/后台页 → active profile → Keychain 取 Key → RDAIClient/NSURLSession → provider JSON → 解析 → translation cache/UI`

- 恶意备份可把旧 Key 绑定到新 origin（P1-03）。
- HTTP URL 可能明文发送 Key/文本（P2-13）。
- Keychain 更新和请求 session 缺可靠错误/并发边界（P2-11/P2-12）。
- cache identity 与页面原文不一致（P1-10）。

闭环要求：秘密绑定 provider+origin；每个请求有 requestId/session generation/content hash；传输失败、HTTP、协议、provider 业务错误分层返回；旧响应不能更新新页面。

### 8.5 备份与恢复链路

`设置 → 收集配置/书/进度/书签/规则/字体/AI metadata → ZIP → Share Sheet`  
`DocumentPicker → 读 ZIP/manifest → 写源文件/封面 → parser → WCDB → 书架通知 → 恢复其余配置`

当前链路的信任边界、原子性、完整性和结果语义分别对应 P1-01、P1-03、P1-05、P1-06、P2-14。恢复通知位于完整恢复之前，故当前不能把 UI “完成”当作业务完成。

### 8.6 遗留远端接口链路

调用链：`Controller → API 子类(requestUrl/requestArgument) → RDBaseApi → YTKNetworkAgent → AFHTTPSessionManager → HTTP endpoint → RDHttpModel/YYModel → Controller`。

当前客户端接口清单：

| 方法 | 路径 | 客户端参数 |
|---|---|---|
| GET | `/system/getAppConfig` | 无 |
| POST | `/book/checkUpdate` | `books[{bookId,chapterId}]` JSON |
| GET | `/book/search` | `pageNum,pageSize,keyWord` |
| GET | `/book/getCategoryId` | `pageNum,pageSize,categoryId,channelId?,orderBy?` |
| GET | `/book/getDetail` | `bookId` |
| GET | `/chapter/getByBookId` | `bookId,chapterId` |
| POST | `/chapter/get` | `chapterIdList,bookId` JSON |
| POST | `/chapter/updateForce` | `chapterIdList,bookId` JSON |
| GET | `/book/getRecommend` | `pageNum,pageSize,bookId` |
| GET | `/category/getCategoryChannel` | 无 |
| GET | `/category/discovery` | `pageNum,pageSize` |
| GET | `/category/getCategoryEnd` | `pageNum,pageSize` |
| GET | `/category/discoveryAll` | `pageNum,pageSize,categoryId,type` |
| GET | `/rank/getList` | 无 |
| GET | `/rank/getPage` | `pageNum,pageSize,rankId,channelId` |
| GET | `/book/getSpecialList` | `pageNum,pageSize` |
| GET | `/book/getSpecialPage` | `pageNum,pageSize,id` |

已确认的客户端问题：公共 HTTP 基址与 ATS 冲突；没有严格 envelope schema；页码/数组/关键词边界不足；页面请求没有统一 latest-request-wins。系统 TLS 验证未被关闭，这是正向控制。

以下服务端事项全部**需要进一步验证**：

1. 每个接口是 public 还是 authenticated，token 的过期、撤销、audience/issuer 规则。
2. `bookId/chapterId/rankId/categoryId/id/channelId` 是否做角色、租户和资源所有权校验；用账号 A 访问账号 B 的 ID 做 IDOR 黑盒测试。
3. `pageSize`、关键词字节数、ID 数组、请求/响应体的硬上限；负数、0、极大整数、重复 ID、非法 enum、Unicode 和畸形 JSON。
4. `/chapter/updateForce` 是否修改服务端状态；若有副作用，需验证事务、幂等 key、超时重试、并发/乱序语义。
5. HTTP 状态、`result.code/result.msg/data`、分页字段、空列表/未知字段契约；401/403/404 不得混用。
6. 网关 TLS/HSTS、限流、超时、缓存头、requestId、审计日志与 token/关键词/书籍文本脱敏。
7. 服务端 Controller/Service/Mapper 是否存在循环查询、错误事务边界、并发覆盖、慢 SQL；需提供服务端仓库、OpenAPI、schema、执行计划和观测数据才能结论化。

验证方法：获取 OpenAPI 与服务端代码；使用两个角色/两个租户账号做代理抓包和跨 ID 测试；重复/并发 POST；边界/模糊输入；结合服务端日志、数据库锁和 `EXPLAIN ANALYZE` 对账。

## 9. 可复用与可精简实现

| 建议能力 | 替代的重复/复杂位置 | 预期影响范围 |
|---|---|---|
| `RDLibraryMutationCoordinator` | 导入、Cell 删除、设置清空、备份恢复各自排队和多表操作 | 统一 per-book 串行、事务、staging、Result 和通知；影响所有写链路 |
| `RDBookRepository` + Result | 各 Manager 的 void/`@[]`/吞错 | UI 可区分空/错/部分；迁移和故障注入可测 |
| `RDBookshelfSnapshotStore` | Controller `isReloading` 与 Prefetch 静态缓存 | 合并 pending、generation、immutable snapshot，消除旧快照覆盖 |
| `RDImportCoordinator` | 顶栏、空态、设置、外部文件四套入口 | 统一可见控制器、single-flight、批量完成与格式预算 |
| `RDCoverProvider` | Cell/LocalBookManager/PDF 回填的路径、存在性、解码、生成 | 原子封面生命周期、异步缩略图、失败状态和版本化派生资源 |
| `RDReadCoordinator/ReadSession` | Cell push、三格式冷启动状态、进度 | 防重复打开，统一恢复/失败语义与进度 revision |
| `RDPageEngine` | 阅读 VC 的同步分页和两段重复前后页逻辑 | 后台可取消分页、缓存页偏移、减少 God Controller |
| `RDTranslationSession` | pending key、缓存、主题渲染、task 管理 | 以 content hash/generation 保证结果不串页，控制并发/费用 |
| 版本化 `MigrationRunner` | WCDB auto migration + raw ALTER + Defaults flag | 可验证、可重试、单一 schema 真相源 |
| DTO/Entity/ViewModel mapper | `RDBookDetailModel` 全层复用 | 消除字段静默丢失，明确可信输入和持久化边界 |
| `RDErrorEnvelope` | DB、文件、Keychain、HTTP 各自字符串/void | 统一错误码、用户文案、日志脱敏和可观测性 |
| 删除遗留在线垂直切片 | 约 51 个旧页面/Service + 多个 Pods | 若产品确认本地化，可直接缩小攻击面、编译时间和审查成本 |

建议不要先“大重写”。先用契约测试锁定行为，再从 P1 的 mutation/error 边界开始抽取；每次只迁移一条业务命令。

## 10. 隐藏风险与高并发风险

| 隐藏场景 | 小样本为何不暴露 | 生产/组合状态结果 | 对应问题 |
|---|---|---|---|
| 删除后立即重导 | 单次删除最终看似成功 | 迟到任务删除新章节 | P1-04 |
| 恢复中并发导入/杀进程 | 正常恢复路径能完成 | 文件与多表处于不同版本 | P1-05 |
| 批量导入时刷新 | 1 本书通知通常恰好可见 | 运行中请求被丢，UI 缺书 | P1-09 |
| 改字号且旧翻译迟到 | 固定字号测试全过 | 当前原文展示旧页译文 | P1-10 |
| 书签快速重复点击 | 顺序点击能被检查挡住 | 并发 check/insert 产生重复 | P2-03 |
| 停止后立即开启翻译 | 单次 session 并发受限 | 旧 task 存活，新 task 重发 | P2-11 |
| 目录/书架规模扩大 | 几十本/章无明显卡顿 | N+1、排序、全量 PDF 工作线性放大 | P2-02/P2-08/P2-15 |
| 设置扫描时清空/恢复 | 常规等待后文案正确 | 旧扫描晚到覆盖新统计 | P2-10 |
| 搜索 A 后立刻搜索 B | 单请求返回正常 | A 的迟到响应覆盖 B | P2-17 |
| DB 故障 | 成功场景返回数组 | 故障被当成真实空库并缓存 | P1-07 |
| 恶意 profileId 恢复 | 普通备份 Key 脱敏测试通过 | 本机旧 Key 绑定攻击者 origin | P1-03 |

还需关注“最后写入获胜”的进度并发：多个重复 Reader 或后台/前台 session 可能乱序写 readTime/page。当前没有显式 revision；应在统一 ReadSession 后用单会话或单调 revision 证明正确性。

## 11. 测试缺口与建议测试矩阵

现状：`Reader.xcscheme` 的 TestAction 为空，无 XCTest/UI Test target、xctestplan 或 CI；`Reader/Tests/AIHarness/run_tests.sh` 是 Foundation 独立 Harness，当前全部通过，覆盖六类 provider 请求/解析、Key 不入备份及 AI ZIP round-trip，但不启动 App、不连接 WCDB/UIKit/真实文件生命周期。

| ID | 场景与输入 | 步骤 | 预期结果 |
|---|---|---|---|
| T01 | 恶意备份：`../book`、绝对/编码路径、symlink | 保留 DB/配置哨兵 hash 后恢复 | 明确拒绝；任何哨兵、现有书和配置不变 |
| T02A | 4 GB 声明、超高压缩比、10 万条目、坏 CRC | 分别按 EPUB/CBZ/备份导入 | 资源预算内快速失败，无 OOM/部分文件/DB 行 |
| T02B | MOBI 溢出偏移、超大 TXT/图片/字体、越根 href | 对所有非 ZIP parser 做 corpus/fuzz 导入 | 受控失败、不崩溃/截断/越界，无部分入库 |
| T03 | profileId 与本机相同、origin 指向测试服务器 | 恢复后打开翻译但不确认配置 | 不发请求、不附着旧 Key、profile 默认禁用 |
| T04 | 同一本书删除→立即重导 100 次 | 给 chapter delete 注入随机延迟 | 每轮最终书/章节/文件完整可读，无迟到删除 |
| T05 | 恢复各阶段磁盘满/DB 失败/杀进程 | 每个 commit point 重启检查 | 仅完整旧状态或完整新状态，且错误可见 |
| T06 | 10 本混合格式 + 慢 PDF，同时删书/改封面 | 挂起首个 refresh 后执行操作 | 最终 UI/缓存/DB 数量、顺序、封面完全一致 |
| T07 | 空白、超长 Emoji、带书签/历史的改名，DB 失败 | 从书架修改并重启/备份 | 非法输入被拒；成功时所有展示一致；失败保留旧名 |
| T08 | 无效图、超大图、写/删失败、恢复默认重复点击 | 更换/恢复/备份恢复封面 | 原子、幂等；失败保留旧封面且提示真实 |
| T09 | 1000 PDF，含损坏/0 页/加密 100 本 | 冷启动、反复刷新、源文件变化 | 首屏不等待；失败不重试；变化后按版本重试 |
| T10 | 翻译后改字体/字号/主题，旧响应延迟 | 快速翻页并停/开 10 次 | 译文 source 匹配当前文本；并发有界、无重复计费 |
| T11 | 1/5 MB 单章、50MP 漫画、1 万章目录 | 打开、滚动、快速改字号/翻页 | 主线程无长任务，峰值内存/P95 达到约定预算 |
| T12 | DB 只读、损坏、未解锁、迁移中断 | 启动、写入、刷新、重启 | error 态而非空态；可重试；迁移不误标完成 |
| T13 | 正/负 bookId、书架内外、书签/历史组合 | 执行清空后立即终止并重启 | 确认文案范围内的数据、文件和缓存全部清除 |
| T14 | Keychain 各 OSStatus；HTTP/LAN/HTTPS/MITM | 保存 profile 并发起请求 | 旧 Key 不丢；错误分层；不允许不安全传输 |
| T15 | 两账号/两角色、跨资源 ID、重复并发 POST | 对全部 17 个服务端接口黑盒测试 | authn/authz、限流、幂等和错误码符合 OpenAPI；无 IDOR |
| T16 | 1 万书/10 万章节/百万书签历史数据 | 查询计划、分页、统计、升级 | 无全表扫描/重复漏页；P95/内存达到预算；数据对账为 0 差异 |
| T17 | iOS 15/17/18，顶栏/空态/设置/外部导入 | 取消、连续点击、后台返回、权限拒绝 | 每入口同结果；只有一个 picker/Reader；错误可恢复 |
| T18 | 干净 CI Archive/Export/App Store validate | 安装依赖、构建、签名、隐私报告、真机启动 | 可复现 IPA；签名/版本/清单合规；无上传阻断 |

必须引入的测试层次：

1. Foundation 单测：路径规范化、manifest/schema、digest、错误映射、AI request/response。
2. WCDB 集成测试：迁移、事务、并发、唯一约束、故障注入和大数据查询计划。
3. 文件系统集成：staging/atomic replace、数据保护、空间不足、恶意 ZIP和恢复 journal。
4. XCUITest：多入口、快速点击、导航、失败状态、三格式续读、权限拒绝。
5. 性能/稳定性：XCTest metrics、Instruments、TSan、ASan/UBSan、parser fuzz。
6. 发布门禁：静态分析、覆盖率、SBOM/许可证/SCA、Archive/Privacy Report/App Store validation。

## 12. 需要进一步验证的事项

| 事项 | 不能静态确认的原因 | 验证方法 |
|---|---|---|
| 服务端认证、角色、IDOR、事务、Mapper/慢 SQL | 服务端源码/schema/运行日志不在仓库 | 获取服务端仓库/OpenAPI/schema；双账号、并发、`EXPLAIN ANALYZE` 和日志对账 |
| 线上 API 可用性和 TLS 迁移状态 | 当前硬编码 HTTP 域名可能已废弃，主 UI 不可达 | 产品确认入口；抓包、DNS/TLS/ATS 诊断；决定删除或迁 HTTPS |
| 旧在线模块是否有 URL Scheme/历史入口可达 | 主 Tab 不展示不代表所有路由不可达 | 枚举 JLRoutes/URL Scheme/deep link/历史 DB，做运行时覆盖 |
| iOS 版本间设置导入和重复 present | UIKit window hierarchy 行为依赖系统/时序 | iOS 15/17/18 真机 UI 自动化和控制台断言 |
| 本地网络权限和 Personal Voice/相册拒绝路径 | 模拟器不能等价于真机权限状态 | 干净真机安装，允许/拒绝/设置撤销/受限四态测试 |
| Release 签名、四段 build number、受管 SDK manifest | Automatic Signing/ASC 最终处理取决于 Archive 与账号 | 干净 CI Archive/Export，检查包并执行 App Store Connect validate |
| 依赖是否存在具体已知 CVE | 需要当前 OSV/NVD/vendor 数据与实际编译版本 | 生成 SBOM 并运行受控 SCA；人工核对可达性，禁止仅按版本号猜测 |
| 索引和分页是否达到生产预算 | 仓库无生产基数/分布/P95 目标 | 复制脱敏分布或生成目标规模数据，跑 query plan 和性能基准 |
| DB/WAL/SHM 在锁屏态的数据保护需求 | 当前保护级别与产品威胁模型未定义 | 真机文件属性/锁屏访问测试；安全评审决定是否启用 SQLCipher key |
| iPad 横屏/分屏是否为产品要求 | plist 与控制器行为矛盾 | 产品确认后按支持矩阵做 snapshot/UI 测试 |

## 13. 分阶段整改计划

### 阶段 0：冻结基线与建立防回归门禁（1–2 天）

1. 保留当前 feature 审查分支和工作区差异，建立最小 XCTest/UI Test target 与 CI。
2. 把 T01–T06、T10、T12 做成失败用例；保存现有数据 fixture 和备份版本矩阵。
3. 定义统一 `Result`、错误分层、书籍业务命令和严重事故日志格式。

退出标准：P1 均有自动复现或可审计的静态/Archive 验证；现有 AI Harness 与基础构建进入 CI。

### 阶段 1：安全、发布和数据完整性止血（3–7 天）

1. 修复 P1-01/P1-02/P1-03：路径 allowlist、归档预算/CRC、AI profile secret binding。
2. 修复 P1-04/P1-05/P1-06/P1-07/P1-08：MutationCoordinator、staging、事务、错误传播、清空语义。
3. 补齐 P1-12/P1-13 隐私清单，升级/移除受管旧 SDK，并做 Archive/ASC 验证。

退出标准：恶意输入测试全过；恢复/删除故障注入无部分状态；App Store 隐私验证通过。

### 阶段 2：并发与多入口一致性（1 个迭代）

1. SnapshotStore + generation 解决 P1-09；Import/Read Coordinator 统一入口和防重复。
2. TranslationSession 以 content hash/taskId/generation 修复 P1-10、P2-11。
3. Rename/Cover command 返回 Result，消除 P2-06/P2-07；Keychain 改 update-first。

退出标准：T04、T06–T10、T12–T14 在 TSan 和 UI 测试下通过；所有失败不再假成功。

### 阶段 3：性能、schema 与架构收敛（1–2 个迭代）

1. 后台可取消分页、异步下采样封面/漫画、版本化 PDF cover job。
2. 拆 DTO/Entity/ViewModel；统一 MigrationRunner；补索引、约束、keyset pagination 和旧数据回填。
3. 移除 Cell 业务操作和 God Controller 重复职责；按测试保护逐步拆分。

退出标准：目标规模 P95/内存达到预算；数据库升级对账无差异；主线程不再执行大 I/O/解码/分页。

### 阶段 4：遗留服务与持续交付治理（并行，1 个迭代）

1. 产品决策：彻底删除旧在线模块，或获取服务端仓库后按第 8.6 节完成端到端整改。
2. 建立可复现依赖、SBOM/SCA、Release Archive/Export/Privacy/安装流水线。
3. 真机完成权限、Data Protection、升级、后台/锁屏与无障碍矩阵。

退出标准：无准死网络模块；每次合并均可生成可验证 IPA；外部 API 的 authn/authz/幂等/限流有自动契约测试。

## 14. 最终验收标准

只有同时满足以下条件才可验收：

1. 所有 P0（当前为 0）和 P1 已修复、代码审查通过，并有自动回归证据；P2 有完成记录或经风险负责人书面接受。
2. 顶栏、空书架、设置、外部文件四个入口，在首次/重复/快速/返回/刷新/后台恢复下得到同一最终结果。
3. 文本、EPUB、MOBI、PDF、ZIP/CBZ 在正常、空、损坏、超大和中断场景下均有受控结果；不 OOM、不长时间阻塞主线程。
4. 普通/历史数据、正负 bookId、书架内外、不同角色（若远端功能保留）及权限拒绝状态均有明确用例。
5. 导入、改名、封面、删除、清空、恢复操作完成后，UI、缓存、文件、read/chapter/bookmark/history 数据完全一致；失败保持旧状态或可自动回滚。
6. 重复点击、重复提交、超时重试和并发操作不产生重复书签、重复 Reader、重复书籍或迟到覆盖；幂等键/唯一约束可被测试证明。
7. AI 请求仅发往用户确认的 HTTPS origin；Keychain 失败不丢旧密钥；翻译结果始终绑定当前原文、语言和 session。
8. 前后端参数、类型、错误码、分页、认证和授权契约完全对齐；服务端资源所有权、角色、限流、事务和幂等通过双账号/并发测试。若服务端不提供证据，旧在线功能不得作为已验收功能发布。
9. 目标数据量下关键查询使用预期索引、分页无重复/遗漏，P95/峰值内存达到团队预先量化的预算；升级迁移行数/hash 对账为零差异。
10. 数据库和文件在故障注入/进程中断后可回滚或恢复；备份 round-trip 完整且恶意包无法越过目录/资源限制。
11. XCTest、WCDB/文件集成、XCUITest、性能、TSan/fuzz 和现有 AI Harness 进入 CI；核心领域行/分支覆盖阈值由团队设定并作为合并门禁。
12. Release Archive 可在干净 CI 复现；签名、build number、entitlements、隐私清单、第三方 SDK、SBOM/SCA 和 App Store Connect validation 全部通过。

## 15. 本次验证记录

- 分支：已从 `master@201ef75` 创建 `feature/system-code-review-2026-07-17`。
- 变更边界：审查未修改业务代码；仅新增本报告。工作区原有的 PDF/封面/书籍信息功能改动保持不变并纳入审查。
- `Reader/Tests/AIHarness/run_tests.sh`：全部通过。
- `git diff --check`：通过。
- 无签名模拟器 Debug 构建：以 `Reader.xcworkspace`、generic iOS Simulator 和独立 DerivedData 执行，结果为 `BUILD SUCCEEDED`；仍存在旧 Vendor 的 deprecated API 警告和重复 `-lc++` 链接警告。Debug 构建通过不能替代缺失的 XCTest/UI/Release/真机验证。
