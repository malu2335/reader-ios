#!/bin/bash
# 纯本地分支的断网门禁。
#
# 这个分支的定位是"不涉及任何联网功能"。该约定光靠人记不住 —— 一次
# 无心的 #import 或一个 sd_setImageWithURL: 就能把网络能力带回来,而且
# 不会有任何编译错误。这里把它钉死在源码层面。
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
SRC="$ROOT/Reader/Reader"
PLIST="$SRC/Resource/Info.plist"
PODFILE="$ROOT/Reader/Podfile"

python3 - "$SRC" "$PLIST" "$PODFILE" <<'PY'
import sys, os, re
from pathlib import Path

src, plist, podfile = Path(sys.argv[1]), Path(sys.argv[2]), Path(sys.argv[3])
failed = 0

def check(name, ok, detail=""):
    global failed
    print(("PASS: " if ok else "FAIL: ") + name + (("  → " + detail) if (detail and not ok) else ""))
    if not ok:
        failed += 1

# 收集所有源码
sources = []
for root, dirs, files in os.walk(src):
    for f in files:
        if f.endswith(('.m', '.mm', '.h')):
            sources.append(Path(root) / f)

def scan(pattern, label):
    """返回命中该模式的 文件:行 列表"""
    hits = []
    rx = re.compile(pattern)
    for f in sources:
        try:
            for i, line in enumerate(f.read_text(encoding='utf-8', errors='ignore').splitlines(), 1):
                if line.lstrip().startswith('//'):
                    continue          # 注释里提到不算
                if rx.search(line):
                    hits.append(f"{f.relative_to(src)}:{i}")
        except Exception:
            pass
    return hits

# --- 网络 API ---
for pattern, label in [
    (r'\bNSURLSession\b',            'NSURLSession'),
    (r'\bNSURLConnection\b',         'NSURLConnection'),
    (r'\bdataTaskWith',              'dataTaskWith…'),
    (r'\bdownloadTaskWith',          'downloadTaskWith…'),
    (r'\buploadTaskWith',            'uploadTaskWith…'),
    (r'\bNSMutableURLRequest\b',     'NSMutableURLRequest'),
    (r'\bCFStreamCreatePairWithSocket', 'CFStream socket'),
    (r'\bWKWebView\b',               'WKWebView'),
    (r'\bUIWebView\b',               'UIWebView'),
    (r'\bSCNetworkReachability',     'SCNetworkReachability'),
]:
    hits = scan(pattern, label)
    check(f"源码中无 {label}", not hits, ", ".join(hits[:4]))

# --- SDWebImage 的远程加载入口(本地封面只用内存/磁盘缓存与本地文件) ---
for pattern, label in [
    (r'sd_setImageWithURL',   'sd_setImageWithURL:'),
    (r'sd_setBackgroundImageWithURL', 'sd_setBackgroundImageWithURL:'),
    (r'SDWebImageDownloader', 'SDWebImageDownloader'),
]:
    hits = scan(pattern, label)
    check(f"源码中无 {label}", not hits, ", ".join(hits[:4]))

# --- 已移除的 AI 模块不得回归 ---
for pattern, label in [
    (r'\bRDAIClient\b',            'RDAIClient'),
    (r'\bRDAIConfig',              'RDAIConfig*'),
    (r'\bRDReadTranslateHelper\b', 'RDReadTranslateHelper'),
    (r'\btranslateAction\b',       'translateAction'),
]:
    hits = scan(pattern, label)
    check(f"源码中无 {label}", not hits, ", ".join(hits[:4]))

check("Common/AI 目录不存在", not (src / "Common" / "AI").exists())

# --- Info.plist:不得声明任何 ATS 例外或本地网络用途 ---
plist_text = plist.read_text(encoding='utf-8', errors='ignore')
for key in ["NSAllowsArbitraryLoads", "NSAllowsLocalNetworking",
            "NSExceptionDomains", "NSLocalNetworkUsageDescription",
            "NSBonjourServices"]:
    check(f"Info.plist 无 {key}", key not in plist_text)

# --- Podfile:不得引入网络库 ---
pod_text = podfile.read_text(encoding='utf-8', errors='ignore')
active_pods = [l for l in pod_text.splitlines()
               if l.strip().startswith("pod '")]
for lib in ["AFNetworking", "YTKNetwork", "Alamofire", "NJKWebViewProgress",
            "Moya", "SocketRocket", "Starscream"]:
    check(f"Podfile 无 {lib}", not any(lib in l for l in active_pods))

print()
if failed:
    print("离线门禁 FAILED: %d 项" % failed)
    print("本分支的定位是纯本地阅读器,不应引入任何联网能力。")
    sys.exit(1)
print("离线门禁通过:未发现任何联网能力。")
PY
