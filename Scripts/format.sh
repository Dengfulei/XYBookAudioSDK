#!/bin/bash
# 仅格式化项目自有原生源码，跳过第三方依赖和生成产物。
set -euo pipefail

project_root="$(cd "$(dirname "$0")/.." && pwd)"
mode="${1:---check}"

if [[ $# -gt 1 || ( "$mode" != "--check" && "$mode" != "--write" ) ]]; then
    printf 'Usage: bash Scripts/format.sh [--check|--write]\n' >&2
    exit 2
fi

clang_formatter="$(xcrun --find clang-format)"
swift_formatter="$(xcrun --find swift-format)"
objc_sources=()
swift_sources=()

while IFS= read -r -d '' source; do
    case "$source" in
        *.h|*.m) objc_sources+=("$source") ;;
        *.swift) swift_sources+=("$source") ;;
    esac
done < <(find "$project_root/XYBookAudioSDK" "$project_root/XYBookAudioSDKDemo" \
    "$project_root/Tests" -type f \( -name '*.h' -o -name '*.m' -o -name '*.swift' \) -print0)

if [[ "$mode" == "--write" ]]; then
    "$clang_formatter" --style="file:$project_root/.clang-format" -i "${objc_sources[@]}"
    "$swift_formatter" format --configuration "$project_root/.swift-format" \
        --in-place "${swift_sources[@]}"
else
    "$clang_formatter" --style="file:$project_root/.clang-format" --dry-run --Werror "${objc_sources[@]}"
    "$swift_formatter" lint --strict --configuration "$project_root/.swift-format" "${swift_sources[@]}"
fi

printf 'Native source formatting %s completed.\n' "$mode"
