#!/bin/bash
# Static checks for privacy policy, open-source licenses, and settings wiring.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
RES="$ROOT/Reader/Reader/Resource"
SETTING="$ROOT/Reader/Reader/Sections/Setting"
PBX="$ROOT/Reader/Reader.xcodeproj/project.pbxproj"
PRIVACY="$RES/PrivacyPolicy.zh-Hans.txt"
OSS="$RES/OpenSourceLicenses.txt"
XCPrivacy="$RES/PrivacyInfo.xcprivacy"
LOCK="$ROOT/Reader/Podfile.lock"
failed=0

fail() { echo "FAIL: $*"; failed=$((failed + 1)); }
pass() { echo "PASS: $*"; }

# --- file existence / UTF-8 / non-empty ---
python3 - "$PRIVACY" "$OSS" <<'PY' || failed=$((failed + 1))
import sys
from pathlib import Path
ok = True
for path in sys.argv[1:]:
    p = Path(path)
    if not p.is_file():
        print(f"FAIL: missing {p}")
        ok = False
        continue
    raw = p.read_bytes()
    if not raw:
        print(f"FAIL: empty {p}")
        ok = False
        continue
    try:
        raw.decode("utf-8")
    except UnicodeDecodeError as e:
        print(f"FAIL: not valid UTF-8: {p} ({e})")
        ok = False
        continue
    print(f"PASS: UTF-8 non-empty: {p.name}")
sys.exit(0 if ok else 1)
PY

# --- privacy content markers ---
python3 - "$PRIVACY" <<'PY'
import sys
from pathlib import Path
text = Path(sys.argv[1]).read_text(encoding='utf-8')
required = [
    ("文档标题 markup", "# 隐私声明"),
    ("生效日期", "生效日期"),
    ("章节 markup", "## 一、产品定位"),
    ("数据收集/无账号", ("收集", "账号")),
    ("设备本地存储", ("本地", "设备")),
    ("分享/披露", ("分享", "披露")),
    ("删除方式", ("删除", "卸载")),
    ("联系方式", ("联系", "邮箱")),
    ("变更说明", ("变更", "更新")),
    ("开发者联系邮箱", "malu233333@gmail.com"),
    ("开发者名称", "malu2335"),
]
failed = 0
# placeholders must be gone
if "【请填写" in text:
    print("FAIL: privacy still contains unfilled placeholder 【请填写…】")
    failed += 1
else:
    print("PASS: privacy has no unfilled contact placeholders")
# no ASCII dump separators in privacy body
if "====" in text or "----" in text:
    print("FAIL: privacy still uses ASCII separator dump style")
    failed += 1
else:
    print("PASS: privacy uses lightweight markup (no ASCII dump separators)")
for label, keys in required:
    if isinstance(keys, str):
        ok = keys in text
    else:
        ok = all(k in text for k in keys)
    print(("PASS" if ok else "FAIL") + f": privacy contains {label}")
    if not ok:
        failed += 1
sys.exit(failed)
PY

# --- open source covers Podfile.lock components + root MIT ---
python3 - "$OSS" "$LOCK" <<'PY'
import re, sys
from pathlib import Path
oss = Path(sys.argv[1]).read_text(encoding='utf-8')
lock = Path(sys.argv[2]).read_text(encoding='utf-8')
# Pod names may be quoted in Podfile.lock, e.g. "UITextView+Placeholder"
pods = set()
in_pods = False
for line in lock.splitlines():
    if line.startswith('PODS:'):
        in_pods = True
        continue
    if in_pods and (line.startswith('DEPENDENCIES:') or (line and not line.startswith(' ') and line.endswith(':'))):
        if line.startswith('DEPENDENCIES:'):
            break
    if not in_pods:
        continue
    m = re.match(r'  - "?([^" /:(]+)"?(?:/[^ ]*)? \(', line)
    if m:
        pods.add(m.group(1))
if not pods:
    print("FAIL: failed to parse any pods from Podfile.lock")
    sys.exit(1)
missing = sorted(p for p in pods if p not in oss)
if missing:
    print("FAIL: OpenSourceLicenses missing pods: " + ", ".join(missing))
    sys.exit(1)
print("PASS: OpenSourceLicenses covers all Podfile.lock components (" + str(len(pods)) + ")")
for marker in ("MIT License", "阅小说", "Copyright (c) 2020"):
    if marker not in oss:
        print(f"FAIL: OpenSourceLicenses missing root MIT marker: {marker}")
        sys.exit(2)
print("PASS: OpenSourceLicenses includes root MIT / 阅小说 copyright")
sys.exit(0)
PY

# --- Xcode resource membership ---
for name in "PrivacyPolicy.zh-Hans.txt" "OpenSourceLicenses.txt"; do
  if grep -q "$name in Resources" "$PBX"; then
    pass "pbxproj Resources includes $name"
  else
    fail "pbxproj Resources missing $name"
  fi
done
if grep -q "RDLegalDocumentController.m in Sources" "$PBX"; then
  pass "pbxproj Sources includes RDLegalDocumentController.m"
else
  fail "pbxproj Sources missing RDLegalDocumentController.m"
fi

# --- settings wiring ---
SETTING_M="$SETTING/RDSettingController.m"
if grep -q "RDSettingRowPrivacy" "$SETTING_M" && grep -q "隐私声明" "$SETTING_M" && grep -q "PrivacyPolicy.zh-Hans" "$SETTING_M"; then
  pass "Settings has privacy row wired to PrivacyPolicy.zh-Hans"
else
  fail "Settings privacy row wiring incomplete"
fi
if grep -q "RDSettingRowOpenSource" "$SETTING_M" && grep -q "开源软件使用声明" "$SETTING_M" && grep -q "OpenSourceLicenses" "$SETTING_M"; then
  pass "Settings has open-source row wired to OpenSourceLicenses"
else
  fail "Settings open-source row wiring incomplete"
fi
LEGAL_M="$SETTING/RDLegalDocumentController.m"
if [[ -f "$LEGAL_M" && -f "$SETTING/RDLegalDocumentController.h" ]]; then
  pass "RDLegalDocumentController sources exist"
else
  fail "RDLegalDocumentController sources missing"
fi
# Typography / design tokens wiring
if grep -q "RDTitleFont21" "$LEGAL_M" && grep -q "RDTitleFont17" "$LEGAL_M" && grep -q "RDBackgroudColor" "$LEGAL_M" && grep -q "RDBlackColor" "$LEGAL_M"; then
  pass "Legal page uses project serif titles and paper/ink color tokens"
else
  fail "Legal page missing design tokens (serif title / paper colors)"
fi
if grep -q "p_attributedDocumentFromText" "$LEGAL_M"; then
  pass "Legal page renders lightweight markup as attributed text"
else
  fail "Legal page missing attributed markup renderer"
fi
# OSS front matter style
if head -20 "$OSS" | grep -q '# 开源软件使用声明' && head -30 "$OSS" | grep -q '## 上游项目'; then
  pass "OpenSourceLicenses uses structured markup front matter"
else
  fail "OpenSourceLicenses front matter not redesigned"
fi

# --- privacy manifest ---
if plutil -lint "$XCPrivacy" >/dev/null; then
  pass "PrivacyInfo.xcprivacy lints OK"
else
  fail "PrivacyInfo.xcprivacy failed plutil -lint"
fi

if [[ "$failed" -ne 0 ]]; then
  echo "Legal documents checks failed: $failed"
  exit 1
fi
echo "Legal documents checks passed."
exit 0
