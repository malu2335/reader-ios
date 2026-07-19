#!/bin/bash
# Phase C(业务一致性与性能)与 P1-07 收尾的静态不变量检查。
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
SRC="$ROOT/Reader/Reader"

python3 - "$SRC" <<'PY'
import sys, re
from pathlib import Path

src = Path(sys.argv[1])
failed = 0

def check(name, ok):
    global failed
    print(("PASS: " if ok else "FAIL: ") + name)
    if not ok:
        failed += 1

setting  = (src/"Sections/Setting/RDSettingController.m").read_text()
shelf    = (src/"Sections/Bookshelf/RDBookshelfController.m").read_text()
helper   = (src/"Common/Read/RDReadHelper.m").read_text()
catcell  = (src/"Sections/Bookshelf/Read/View/Catalog/RDReadCatalogCell.m").read_text()
catview  = (src/"Sections/Bookshelf/Read/View/Catalog/RDReadCatalogView.m").read_text()
localbk  = (src/"Common/LocalBook/RDLocalBookManager.m").read_text()
readpage = (src/"Sections/Bookshelf/Read/RDReadPageViewController.m").read_text()
record_h = (src/"Database/RDReadRecordManager.h").read_text()
record_m = (src/"Database/RDReadRecordManager.mm").read_text()
chap_h   = (src/"Database/RDCharpterDataManager.h").read_text()
dbm      = (src/"Database/RDDatabaseManager.mm").read_text()
prefetch = (src/"Common/Manager/RDBookshelfPrefetch.m").read_text()

# --- P2-01 导入路由 ---
check("设置页先切书架 tab,再下一 tick 才发导入请求",
      re.search(r"setSelectedIndex:RDMainBookShelf.*?dispatch_async\(dispatch_get_main_queue\(\).*?RDLocalBookImportRequestNotification",
                setting, re.S) is not None)

check("书架 importAction 校验已上屏且无模态",
      re.search(r"-\(void\)importAction\s*\{[^}]*?self\.view\.window[^}]*?self\.presentedViewController", shelf, re.S) is not None)

# --- P2-02 阅读 single-flight ---
check("RDReadHelper 有 openingBookId 门闩",
      "sRDOpeningBookId" in helper and "p_beginOpeningBookId" in helper)

check("打开前检查导航栈顶是否已是同一本书",
      "p_isAlreadyReadingBookId" in helper)

check("每条失败/成功路径都调用 p_endOpening",
      helper.count("[self p_endOpening]") >= 5)

# --- P2-03 目录投影 ---
check("目录 cell 不再查库",
      "RDCharpterDataManager" not in catcell and "hasContent" in catcell)

check("目录列表一次查出有正文的章节 id",
      "charpterIdsWithContentForBookId" in catview)

# --- P2-06 PDF 封面 ---
check("PDF 封面已就位时只 stat 不解码",
      "fileExistsAtPath:coverPath" in localbk
      and "imageWithContentsOfFile:coverPath" not in localbk)

# --- P2-17 / P2-18 ---
check("removeLocalBook 提供 completion",
      "removeLocalBook:(RDBookDetailModel *)book completion:" in localbk)

check("清空枚举全部记录行而非只枚举负 id",
      "getAllRecordsForDestructiveClear" in setting)

# --- P1-07 收尾 ---
check("schema 版本落在 PRAGMA user_version",
      "user_version" in dbm and "p_setSchemaVersion" in dbm)

check("旧 NSUserDefaults 标志只用于一次性接管",
      "kLegacyPrimaryIdMigratedKey" in dbm
      and "removeObjectForKey:kLegacyPrimaryIdMigratedKey" in dbm)

void_writes = re.findall(r"^\+\(void\)(?:insertOrReplaceModel|updateProgressWithModel|updateTitle|updateReadTime|updateBookshelfState|removeBookFromBookShelf|updateOnBookselfUpdate)",
                         record_m, re.M)
check("读记录写 API 不再返回 void(asyncUpdatePage 除外)", not void_writes)

check("章节写 API 返回 BOOL",
      "+(BOOL)insertObjectsWithCharpters:" in chap_h
      and "+(BOOL)deleteAllCharpterWithBookId:" in chap_h)

check("getBookshelfDisplayList 查询失败返回 nil,不再兜成空数组",
      "return result ?: @[]" not in record_m)

check("书架把查询失败显示成错误而不是空书架",
      re.search(r"if \(!books\).*?showText:@\"书架读取失败", shelf, re.S) is not None)

check("启动预取查询失败时不提交空快照",
      re.search(r"if \(!books\).*?return;", prefetch, re.S) is not None)

print()
if failed:
    print("Phase C checks FAILED: %d" % failed)
    sys.exit(1)
print("Phase C checks passed.")
PY
