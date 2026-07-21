#!/bin/bash
# Phase 4: 串联全部静态 harness,供 CI / 本地发布门禁使用。
# 顺序固定;任一失败立即退出非 0。
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT/Reader"

echo "=== LibraryMutationHarness ==="
bash Tests/LibraryMutationHarness/run_tests.sh
echo
echo "=== PhaseCHarness ==="
bash Tests/PhaseCHarness/run_tests.sh
echo
echo "=== ExternalImportHarness ==="
bash Tests/ExternalImportHarness/run_tests.sh
echo
echo "=== LegalDocumentsHarness ==="
bash Tests/LegalDocumentsHarness/run_tests.sh
echo
echo "=== AIHarness ==="
bash Tests/AIHarness/run_tests.sh
echo
echo "ALL HARNESSES PASSED"
