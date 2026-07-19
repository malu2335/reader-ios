#!/bin/sh
# Xcode Cloud 在克隆仓库后、开始构建前执行本脚本。
#
# 为什么需要它:
#   Pods/ 不入版本库(见 .gitignore),而 Reader.xcodeproj 的 build configuration
#   直接引用了 Pods 生成的 xcconfig:
#       Pods/Target Support Files/Pods-Reader/Pods-Reader.release.xcconfig
#   CI 上没人跑过 pod install,这个文件就不存在,构建会以
#       Unable to open base configuration reference file ...
#   直接失败。
#
# Xcode Cloud 的工作目录是 /Volumes/workspace/repository,
# 本脚本必须放在仓库根的 ci_scripts/ 下且有可执行权限。
set -e

echo "=== ci_post_clone: 安装依赖 ==="

# Xcode Cloud 镜像自带 Homebrew,但不一定带 CocoaPods
if ! command -v pod >/dev/null 2>&1; then
    echo "CocoaPods 未安装,通过 Homebrew 安装…"
    export HOMEBREW_NO_AUTO_UPDATE=1
    export HOMEBREW_NO_INSTALL_CLEANUP=1
    brew install cocoapods
fi

pod --version

# CI_PRIMARY_REPOSITORY_PATH 由 Xcode Cloud 注入;本地手动跑时回退到脚本上级目录
REPO_ROOT="${CI_PRIMARY_REPOSITORY_PATH:-$(cd "$(dirname "$0")/.." && pwd)}"
cd "$REPO_ROOT/Reader"

echo "=== 在 $(pwd) 执行 pod install ==="
pod install --repo-update

# 明确校验产物存在,失败时给出比 Xcode 更清楚的报错
for cfg in Debug Release; do
    lower=$(echo "$cfg" | tr '[:upper:]' '[:lower:]')
    file="Pods/Target Support Files/Pods-Reader/Pods-Reader.${lower}.xcconfig"
    if [ ! -f "$file" ]; then
        echo "错误:pod install 后仍缺少 $file"
        exit 1
    fi
    echo "OK: $file"
done

echo "=== ci_post_clone 完成 ==="
