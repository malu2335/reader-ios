#!/bin/bash
# Compile and run AI harness against shipped sources.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
SRC="$ROOT/Reader/Reader"
HARNESS="$(cd "$(dirname "$0")" && pwd)"
SCRATCH="${1:-/tmp/ai_harness_out}"
mkdir -p "$SCRATCH"
OUT="$SCRATCH/ai_harness"

# Real reading UI path: TopBar -> MenuView forward -> PageVC -> RDAIClient
python3 - "$SRC" "$SCRATCH/ui_wiring.txt" <<'PY'
import sys
from pathlib import Path
src, out = Path(sys.argv[1]), Path(sys.argv[2])
menu = (src/"Sections/Bookshelf/Read/View/RDMenuView.m").read_text()
top = (src/"Sections/Bookshelf/Read/View/RDReadTopBar.m").read_text()
page = (src/"Sections/Bookshelf/Read/RDReadPageViewController.m").read_text()
setting = (src/"Sections/Setting/RDSettingController.m").read_text()
checks = [
    ("RDMenuView implements translateAction and forwards to delegate",
     "-(void)translateAction" in menu and "[self.delegate translateAction]" in menu),
    ("RDReadTopBar invokes translateAction on its delegate",
     "respondsToSelector:@selector(translateAction)" in top),
    ("topBar.delegate is RDMenuView",
     "_topBar.delegate = self" in menu),
    ("RDReadPageViewController.translateAction uses RDReadTranslateHelper",
     "-(void)translateAction" in page and "RDReadTranslateHelper" in page),
    ("RDReadTranslateHelper calls shipped RDAIClient",
     "[[RDAIClient sharedClient] translateText" in (src/"Common/AI/RDReadTranslateHelper.m").read_text()),
    ("empty-config path directs to AI settings",
     "未配置 AI" in (src/"Common/AI/RDReadTranslateHelper.m").read_text() and "RDAIConfigController" in (src/"Common/AI/RDReadTranslateHelper.m").read_text()),
    ("Settings exposes AI 配置 entry",
     "RDSettingRowAIConfig" in setting and "AI 配置" in setting),
    ("Online search entry disabled on bookshelf",
     "本地阅读模式" in (src/"Sections/Bookshelf/Cell/RDBookshelfSearchCell.m").read_text()),
]
lines = ["=== UI wiring real-path (translate chain) ==="]
failed = 0
for msg, ok in checks:
    lines.append(("PASS" if ok else "FAIL") + ": " + msg)
    if not ok:
        failed += 1
lines.append(f"failed={failed}")
out.write_text("\n".join(lines) + "\n")
print("\n".join(lines))
sys.exit(failed)
PY

clang -fobjc-arc -framework Foundation -framework Security -lz \
  -I"$SRC/Common/AI" \
  -I"$SRC/Common/LocalBook" \
  "$SRC/Common/AI/RDAIConfig.m" \
  "$SRC/Common/AI/RDAIClient.m" \
  "$SRC/Common/LocalBook/RDZipArchive.m" \
  "$HARNESS/main.m" \
  -o "$OUT"

"$OUT" "$SCRATCH"
echo "exit=$?"
