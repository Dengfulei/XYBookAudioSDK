#!/bin/bash
# 分别归档真机和模拟器产物，导出与宿主共享动态 YYModel 依赖的 SDK。
set -euo pipefail
PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_ROOT="$PROJECT_ROOT/build/Release"
OUTPUT="$PROJECT_ROOT/Products"
mkdir -p "$BUILD_ROOT" "$OUTPUT/Frameworks/Device" "$OUTPUT/Dependencies/Device"
for platform in device simulator; do
  destination='generic/platform=iOS'
  architectures='arm64'
  if [[ "$platform" == simulator ]]; then
    destination='generic/platform=iOS Simulator'
    architectures='arm64 x86_64'
  fi
  log="$BUILD_ROOT/$platform.log"
  if ! xcodebuild archive -workspace "$PROJECT_ROOT/XYBookAudioSDK.xcworkspace" -scheme XYBookAudioSDK \
    -configuration Release -destination "$destination" -archivePath "$BUILD_ROOT/$platform.xcarchive" \
    -derivedDataPath "$BUILD_ROOT/DerivedData-$platform" SKIP_INSTALL=NO ONLY_ACTIVE_ARCH=NO \
    ARCHS="$architectures" CODE_SIGNING_ALLOWED=NO > "$log" 2>&1; then
    tail -n 60 "$log" >&2
    exit 1
  fi
done
for framework in XYBookAudioSDK YYModel; do
  directory="$OUTPUT/Frameworks"
  if [[ "$framework" == YYModel ]]; then directory="$OUTPUT/Dependencies"; fi
  rm -rf "$directory/$framework.xcframework" "$directory/Device/$framework.framework"
  arguments=()
  for platform in device simulator; do
    archive="$BUILD_ROOT/$platform.xcarchive"
    arguments+=(-framework "$archive/Products/Library/Frameworks/$framework.framework")
    if [[ -d "$archive/dSYMs/$framework.framework.dSYM" ]]; then
      arguments+=(-debug-symbols "$archive/dSYMs/$framework.framework.dSYM")
    fi
  done
  xcodebuild -create-xcframework "${arguments[@]}" -output "$directory/$framework.xcframework"
  ditto "$BUILD_ROOT/device.xcarchive/Products/Library/Frameworks/$framework.framework" "$directory/Device/$framework.framework"
done
cp "$PROJECT_ROOT/Pods/YYModel/LICENSE" "$OUTPUT/Dependencies/YYModel-LICENSE.txt"
otool -L "$OUTPUT/Frameworks/Device/XYBookAudioSDK.framework/XYBookAudioSDK" > "$OUTPUT/DEPENDENCIES.txt"
if nm -gU "$OUTPUT/Frameworks/Device/XYBookAudioSDK.framework/XYBookAudioSDK" | grep -q 'OBJC_CLASS_\$_YYClassInfo'; then
  echo 'YYModel was unexpectedly copied into the SDK binary.' >&2
  exit 1
fi
python3 "$PROJECT_ROOT/Scripts/bundle_release.py"
python3 "$PROJECT_ROOT/Scripts/checksums.py" "$OUTPUT"
echo "Release artifacts: $OUTPUT"
