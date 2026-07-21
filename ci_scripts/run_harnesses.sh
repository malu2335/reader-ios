#!/bin/sh
# Local/CI entry: run all static harnesses after pod install.
set -e
ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
exec bash "$ROOT/Reader/Tests/run_all_harnesses.sh"
