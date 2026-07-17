#!/bin/bash
# Static checks for external document import configuration in Info.plist.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
PLIST="$ROOT/Reader/Reader/Resource/Info.plist"
PB=/usr/libexec/PlistBuddy
failed=0

fail() {
  echo "FAIL: $*"
  failed=$((failed + 1))
}

pass() {
  echo "PASS: $*"
}

if [[ ! -f "$PLIST" ]]; then
  echo "FAIL: Info.plist not found at $PLIST"
  exit 1
fi

if ! plutil -lint "$PLIST" >/dev/null; then
  echo "FAIL: Info.plist is not a valid plist"
  exit 1
fi
pass "Info.plist is valid"

# LSSupportsOpeningDocumentsInPlace must exist and be false (copy-on-open semantics).
if ! "$PB" -c 'Print :LSSupportsOpeningDocumentsInPlace' "$PLIST" >/dev/null 2>&1; then
  fail "LSSupportsOpeningDocumentsInPlace is missing"
else
  val=$("$PB" -c 'Print :LSSupportsOpeningDocumentsInPlace' "$PLIST")
  if [[ "$val" == "false" ]]; then
    pass "LSSupportsOpeningDocumentsInPlace = false"
  else
    fail "LSSupportsOpeningDocumentsInPlace should be false, got: $val"
  fi
fi

# Export compliance: no non-exempt encryption declaration.
if ! "$PB" -c 'Print :ITSAppUsesNonExemptEncryption' "$PLIST" >/dev/null 2>&1; then
  fail "ITSAppUsesNonExemptEncryption is missing"
else
  val=$("$PB" -c 'Print :ITSAppUsesNonExemptEncryption' "$PLIST")
  if [[ "$val" == "false" ]]; then
    pass "ITSAppUsesNonExemptEncryption = false"
  else
    fail "ITSAppUsesNonExemptEncryption should be false, got: $val"
  fi
fi

# Collect all LSItemContentTypes from CFBundleDocumentTypes.
DOC_UTIS=$("$PB" -c 'Print :CFBundleDocumentTypes' "$PLIST" 2>/dev/null | grep -E '^\s+[a-z0-9.]+$' | awk '{print $1}' || true)
# More reliable extraction via python
REQUIRED_UTIS=(
  public.plain-text
  org.idpf.epub-container
  com.adobe.pdf
  xyz.malu2335.reader.mobi
  public.zip-archive
  xyz.malu2335.reader.cbz
)

python3 - "$PLIST" "${REQUIRED_UTIS[@]}" <<'PY'
import plistlib, sys
from pathlib import Path

plist_path = Path(sys.argv[1])
required = sys.argv[2:]
with plist_path.open("rb") as f:
    data = plistlib.load(f)

doc_types = data.get("CFBundleDocumentTypes") or []
found = set()
for dt in doc_types:
    for u in dt.get("LSItemContentTypes") or []:
        found.add(u)

missing = [u for u in required if u not in found]
if missing:
    print("FAIL: CFBundleDocumentTypes missing UTIs: " + ", ".join(missing))
    sys.exit(1)
print("PASS: CFBundleDocumentTypes covers required UTIs: " + ", ".join(required))

imported = data.get("UTImportedTypeDeclarations") or []
by_id = {d.get("UTTypeIdentifier"): d for d in imported}

# MOBI
mobi = by_id.get("xyz.malu2335.reader.mobi")
if not mobi:
    print("FAIL: UTImportedTypeDeclarations missing xyz.malu2335.reader.mobi")
    sys.exit(2)
conforms = set(mobi.get("UTTypeConformsTo") or [])
for need in ("public.data", "public.content"):
    if need not in conforms:
        print(f"FAIL: MOBI UTI missing UTTypeConformsTo {need}")
        sys.exit(3)
tags = mobi.get("UTTypeTagSpecification") or {}
exts = set(tags.get("public.filename-extension") or [])
for need in ("mobi", "azw"):
    if need not in exts:
        print(f"FAIL: MOBI UTI missing extension {need}")
        sys.exit(4)
mimes = set(tags.get("public.mime-type") or [])
for need in ("application/x-mobipocket-ebook", "application/vnd.amazon.ebook"):
    if need not in mimes:
        print(f"FAIL: MOBI UTI missing MIME {need}")
        sys.exit(5)
print("PASS: MOBI UTI conforms to public.data/public.content, extensions mobi/azw, MIME types present")

# CBZ
cbz = by_id.get("xyz.malu2335.reader.cbz")
if not cbz:
    print("FAIL: UTImportedTypeDeclarations missing xyz.malu2335.reader.cbz")
    sys.exit(6)
conforms = set(cbz.get("UTTypeConformsTo") or [])
for need in ("public.zip-archive", "public.data", "public.content"):
    if need not in conforms:
        print(f"FAIL: CBZ UTI missing UTTypeConformsTo {need}")
        sys.exit(7)
tags = cbz.get("UTTypeTagSpecification") or {}
exts = set(tags.get("public.filename-extension") or [])
if "cbz" not in exts:
    print("FAIL: CBZ UTI missing extension cbz")
    sys.exit(8)
print("PASS: CBZ UTI conforms to public.zip-archive/public.data/public.content, extension cbz")

# System types must NOT be redeclared as imported types
system_ids = {
    "public.plain-text",
    "org.idpf.epub-container",
    "com.adobe.pdf",
    "public.zip-archive",
}
redeclared = sorted(system_ids & set(by_id))
if redeclared:
    print("FAIL: system UTIs redeclared in UTImportedTypeDeclarations: " + ", ".join(redeclared))
    sys.exit(9)
print("PASS: system UTIs not redeclared in UTImportedTypeDeclarations")
sys.exit(0)
PY

echo "External import plist checks passed."
exit 0
