# 前两轮审查报告遗留项复审（2026-07-19）

复审分支：`feature/fix-oracle-phase-a-2026-07-19`（含 Oracle Phase A 与 Phase B 修复）
复审对象：
- 第一轮 `docs/code-review-2026-07-17.md`
- 第二轮 `docs/code-review-2026-07-17-systemic.md`

结论先说：两轮报告共 5 项明确遗留，本轮 Phase B **关闭 1 项、大幅推进 1 项**，其余 3 项维持原判（属于独立排期的工作，不适合顺带处理）。

---

## 一、已关闭

### P1-05 备份恢复整体原子性 / staging（第二轮）— ✅ 本轮关闭

原判：「本轮修复覆盖了部分具体场景，但未建立统一 staging，属独立架构工作。」

现状（`RDBackupManager.m`）：

- 每次恢复创建 `RestoreStaging/<uuid>/`，源文件先落暂存，**正式路径上的旧文件在提交成功前一律不动**；
- 章节从暂存文件解析（`parseChaptersForBook:atPath:`），不再依赖已被覆盖的正式文件；
- 提交点顺序：旧文件移入备份 → 新文件原子移入正式路径 → 数据库事务提交；事务失败调用 `p_rollbackTarget:fromBackup:` 把旧文件放回；
- 封面/手动封面移到数据库提交之后，失败只降级为警告；
- 全部书籍处理完才发一次 `postLibraryChanged`，中途不暴露混合状态。

验收标准「恢复任一阶段失败后，每本书只能是全旧或全新」在文件与数据库两侧都成立。

---

## 二、显著推进但未完全关闭

### P1-07 WCDB 错误传播与迁移状态机（第二轮）— 🟡 核心路径已覆盖

原判：「未建立 `Result` 错误模型/迁移状态机。」

本轮已做：

- `RDDatabaseManager performTransactionSync:error:` 基于 `WCTTransaction` 取回 WCDB 错误，转成 `RDDatabaseErrorDomain` 的 `NSError`；
- `RDLibraryTransaction` 让导入/恢复的「章节 + 读记录」跨表写进单次事务，失败整体回滚；
- 导入不再「报成功但书架无此书」：提交失败会删掉已落盘源文件与封面，并把错误文案交给 UI；
- `p_migratePrimaryIdsIfNeeded` 不再无条件写完成标志：批次事务失败即中止，且复查全表无残留异常主键才落标志（查询失败与空表已区分）。

仍未做（保留在 P1-07 名下）：

- 迁移标志仍在 `NSUserDefaults`（`kPrimaryIdMigratedKey`），未迁到 `PRAGMA user_version` / `schema_migrations`，与数据库文件生命周期仍是脱钩的——删库重建后标志还在；
- `RDReadRecordManager` / `RDCharpterDataManager` 的其余写 API（`updateProgressWithModel:`、`updateTitle:`、`asyncUpdatePage:`、`deleteAllCharpterWithBookId:` 等，共 13 个）仍是 `void`；
- 书架仍无 loading/content/empty/**error** 四态，查询失败与「真的没有书」在 UI 上不可区分。

建议：前两条并入 Oracle Phase C，第三条依赖书架状态机改造，与 Phase C「设置刷新 pending / 目录 projection」同批做。

---

## 三、维持原判（不适合顺带处理）

### P1-11 大章节主线程分页（第二轮）— 🔴 仍只是硬上限兜底

`RDReadParser.m:23-24` 的 `kMaxPaginateCharacters = 300000` 仍是唯一防线。真正的后台可取消分页受限于 `UIPageViewControllerDataSource` 的同步返回契约（6 个调用点中 4 个结构上必须同步返回），Oracle 也明确「不要在没有测试前重写分页」。**前置条件是先有 XCUITest**，属 Phase D 之后。

### P1-13 / P2-17 遗留在线死代码物理删除（第二轮）— 🔴 维持独立排期

复核确认规模不变：`Sections/Discover`、`Library`、`Search`、`Bookshelf/BookDetail`、`Bookshelf/Catalog`、`Bookshelf/Read/View/Download`、整个 `Service/`，合计 **118 个 .h/.m 文件**，彼此交叉引用。Podfile 中 `JLRoutes`、`MJRefresh`、`WMPageController`、`YTKNetwork`、`NJKWebViewProgress` 随之可移除。

两点复核后仍成立：

1. 即使删完，P1-13 的隐私清单问题**不会随之关闭**——`SDWebImage`、`MBProgressHUD` 是书架封面与全局 HUD 仍在使用的依赖，其隐私清单缺失需要单独的版本升级评估；
2. Oracle 独立复核指出「清空书架的在线分支实际不可达」（`getAllOnBookshelf` 已按 `bookId < 0` 过滤），因此这批代码是纯维护面/发布审查面问题，不是运行时缺陷。

对应 Oracle Phase E，须单独开分支、每步跑完整构建。

### P3-1 翻页控制器双胞胎方法合并（第一轮）— 🔴 仍在，且是 P1-11 的同一块代码

`RDReadPageViewController.m` 中 `p_afterOrBeforeWithViewController:before:mirror:` 与 `p_setAfterOrBeforeViewControllerWithBefore:mirror:` 仍近乎复制，`p_creatReadController:` 的 10 参数签名仍重复 20+ 次。

复审补充判断：**这一项应与 P1-11 绑定，不要单独做**。两者改的是同一段翻页代码，先合并双胞胎方法会让后续的异步分页改造重新 rebase 一遍；合理顺序是 XCUITest → 分页架构改造 → 顺带完成 P3-1。

---

## 四、第一轮其余延期项

`P3-12`（恢复/字体 picker 拆分）、`P3-13`（`RDUrl.h` 随死代码批次删除）现状不变，`P3-13` 应并入 Phase E 一并处理。

---

## 五、遗留项状态总表

| 项 | 来源 | 本轮状态 | 归属阶段 |
|---|---|---|---|
| P1-05 恢复原子性/staging | 第二轮 | ✅ 关闭 | Phase B（已完成） |
| P1-07 错误传播/迁移状态机 | 第二轮 | 🟡 核心路径完成，schema 版本与全量 Result 未做 | Phase C |
| P1-11 大章节主线程分页 | 第二轮 | 🔴 仅硬上限 | Phase D 之后 |
| P1-13 / P2-17 在线死代码 | 第二轮 | 🔴 118 文件，维持独立排期 | Phase E |
| P3-1 翻页双胞胎方法 | 第一轮 | 🔴 仍在，建议与 P1-11 绑定 | 随 Phase D 之后 |
| P3-12 / P3-13 | 第一轮 | 🔴 现状不变 | P3-13 并入 Phase E |
