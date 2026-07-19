#!/bin/bash
# Phase B 数据正确性骨架的静态不变量检查。
# 这些约定一旦被回退,导入/恢复会重新退化成"部分提交"的混合状态,
# 而这类回归在 UI 上几乎看不出来,所以钉在源码层面。
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

local  = (src/"Common/LocalBook/RDLocalBookManager.m").read_text()
backup = (src/"Common/LocalBook/RDBackupManager.m").read_text()
coord  = (src/"Common/LocalBook/RDLibraryMutationCoordinator.m").read_text()
chapter= (src/"Database/RDCharpterDataManager.mm").read_text()
record = (src/"Database/RDReadRecordManager.mm").read_text()
txn    = (src/"Database/RDLibraryTransaction.mm").read_text()
dbm    = (src/"Database/RDDatabaseManager.mm").read_text()
setting= (src/"Sections/Setting/RDSettingController.m").read_text()

# --- 单事务提交 ---
check("RDLibraryTransaction 在一次事务内写章节和读记录",
      "performTransactionSync" in txn
      and "db_replaceChaptersForBookId" in txn
      and "db_insertOrReplaceModel" in txn)

check("章节替换是同事务内的 delete + insert,任一失败返回 NO",
      re.search(r"db_replaceChaptersForBookId.*?deleteObjectsFromTable.*?return NO;.*?insertOrReplaceObjects",
                chapter, re.S) is not None)

check("performTransactionSync 用 WCTTransaction 取回错误并输出 NSError",
      "getTransaction" in dbm and "RDDatabaseErrorDomain" in dbm)

check("读记录写入返回 BOOL 供外层回滚",
      "+(BOOL)db_insertOrReplaceModel:" in record)

# --- 导入 ---
check("导入通过 RDLibraryTransaction 提交,不再直接 insertOrReplaceModel",
      "RDLibraryTransaction commitBook" in local
      and "[RDReadRecordManager insertOrReplaceModel:book];" not in local)

check("导入提交失败时删除已落盘的源文件并报错",
      re.search(r"commitBook.*?removeItemAtPath:filePath.*?finish\(nil,", local, re.S) is not None)

check("导入不再在解析后立刻单独插章节",
      "[RDCharpterDataManager insertObjectsWithCharpters:result.chapters];" not in local)

# --- 恢复 ---
check("恢复跑在书库变更串行队列上",
      "RDLibraryMutationCoordinator performAsync" in backup)

check("恢复先写 staging 目录,不直接覆盖正式路径",
      "p_createRestoreStagingDirectory" in backup
      and "RestoreStaging" in backup
      and "writeEntry:bookEntry toFile:staged" in backup)

check("恢复解析的是 staging 里的文件",
      "parseChaptersForBook:book atPath:staged" in backup)

check("恢复的数据库提交失败会把旧源文件放回",
      re.search(r"commitBook.*?p_rollbackTarget", backup, re.S) is not None)

check("恢复只在全部处理完后发一次刷新通知",
      "RDLibraryMutationCoordinator postLibraryChanged" in backup
      and "postNotificationName:RDLocalBookImportedNotification" not in backup)

# --- 队列统一 ---
check("导入队列即书库变更协调器队列",
      "RDLibraryMutationCoordinator queue" in local)

check("协调器队列是串行的",
      "DISPATCH_QUEUE_SERIAL" in coord)

check("清空书架走变更队列,且完成提示再排一轮",
      re.search(r"RDLibraryMutationCoordinator performAsync.*?RDLibraryMutationCoordinator performAsync",
                setting, re.S) is not None)

# --- 迁移状态机 ---
check("primaryId 迁移复查通过才落完成标志",
      "p_primaryIdMigrationIsComplete" in dbm
      and re.search(r"allBatchesCommitted.*?p_primaryIdMigrationIsComplete.*?return;", dbm, re.S) is not None)

print()
if failed:
    print("Library mutation checks FAILED: %d" % failed)
    sys.exit(1)
print("Library mutation checks passed.")
PY
