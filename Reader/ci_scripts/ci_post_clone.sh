#!/bin/sh
# Xcode Cloud post-clone hook.
#
# MUST live next to the Xcode workspace (Reader/ci_scripts/), not at the
# repository root. Apple only looks for ci_scripts beside the .xcodeproj /
# .xcworkspace that the workflow builds.
#
# Why this exists:
#   Pods/ is gitignored, but Reader.xcodeproj base configurations reference
#   Pods/Target Support Files/Pods-Reader/Pods-Reader.{debug,release}.xcconfig.
#   Without pod install those files are missing and archive fails at config
#   load time with:
#     Unable to open base configuration reference file
#     '.../Pods-Reader.release.xcconfig'
#
set -e

echo "=== ci_post_clone: start ==="
echo "pwd=$(pwd)"
echo "CI_PRIMARY_REPOSITORY_PATH=${CI_PRIMARY_REPOSITORY_PATH:-<unset>}"
echo "script=$0"

# Prefer the directory that contains this script (…/Reader/ci_scripts) → Reader/
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
READER_DIR=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)

# Fallback: Xcode Cloud injects the clone root
if [ -n "${CI_PRIMARY_REPOSITORY_PATH:-}" ] && [ -d "$CI_PRIMARY_REPOSITORY_PATH/Reader" ]; then
    READER_DIR="$CI_PRIMARY_REPOSITORY_PATH/Reader"
fi

if [ ! -f "$READER_DIR/Podfile" ]; then
    echo "error: Podfile not found under $READER_DIR"
    exit 1
fi

cd "$READER_DIR"
echo "=== working directory: $(pwd) ==="

# CocoaPods is not always preinstalled on Xcode Cloud images
if ! command -v pod >/dev/null 2>&1; then
    echo "CocoaPods missing; installing via Homebrew…"
    export HOMEBREW_NO_AUTO_UPDATE=1
    export HOMEBREW_NO_INSTALL_CLEANUP=1
    export HOMEBREW_NO_ENV_HINTS=1
    if ! brew install cocoapods; then
        echo "brew install failed; trying gem --user-install…"
        gem install --user-install cocoapods
        # user gem bin may not be on PATH
        export PATH="$HOME/.gem/ruby/$(ruby -e 'print RUBY_VERSION[/\d+\.\d+/]')/bin:$PATH"
        export PATH="$HOME/.gem/bin:$PATH"
    fi
fi

echo "pod version: $(pod --version)"
echo "=== pod install (lockfile, no repo-update for speed) ==="
# Podfile.lock is committed; --repo-update is slow and often unnecessary on CI
if ! pod install; then
    echo "pod install failed; retrying with --repo-update…"
    pod install --repo-update
fi

missing=0
for cfg in debug release; do
    file="Pods/Target Support Files/Pods-Reader/Pods-Reader.${cfg}.xcconfig"
    if [ ! -f "$file" ]; then
        echo "error: still missing after pod install: $file"
        missing=1
    else
        echo "OK: $file"
    fi
done

if [ "$missing" -ne 0 ]; then
    echo "listing Pods/Target Support Files (if any):"
    ls -la "Pods/Target Support Files" 2>/dev/null || true
    exit 1
fi

echo "=== ci_post_clone: done ==="
exit 0
