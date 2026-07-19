#!/bin/sh
# Compatibility shim at repository root.
#
# Xcode Cloud only loads ci_scripts next to the workspace:
#   Reader/ci_scripts/ci_post_clone.sh
# This root script exists so local `bash ci_scripts/ci_post_clone.sh`
# still works; it just forwards to the real hook.
set -e
ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
exec sh "$ROOT/Reader/ci_scripts/ci_post_clone.sh"
