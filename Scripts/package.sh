#!/bin/bash
# 分别归档真机和模拟器产物，合成 SDK 的 XCFramework。
set -euo pipefail
PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_ROOT="$PROJECT_ROOT/build/Release"
OUTPUT="$PROJECT_ROOT/Products"
FRAMEWORKS="$OUTPUT/Frameworks"
FRAMEWORK="XYBookAudioSDK.framework"
mkdir -p "$BUILD_ROOT" "$FRAMEWORKS/Device"
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
arguments=()
for platform in device simulator; do
  archive="$BUILD_ROOT/$platform.xcarchive"
  arguments+=(-framework "$archive/Products/Library/Frameworks/$FRAMEWORK")
  if [[ -d "$archive/dSYMs/$FRAMEWORK.dSYM" ]]; then
    arguments+=(-debug-symbols "$archive/dSYMs/$FRAMEWORK.dSYM")
  fi
done
rm -rf "$FRAMEWORKS/XYBookAudioSDK.xcframework" "$FRAMEWORKS/Device/$FRAMEWORK" "$OUTPUT/Dependencies"
xcodebuild -create-xcframework "${arguments[@]}" -output "$FRAMEWORKS/XYBookAudioSDK.xcframework"
ditto "$BUILD_ROOT/device.xcarchive/Products/Library/Frameworks/$FRAMEWORK" "$FRAMEWORKS/Device/$FRAMEWORK"
otool -L "$FRAMEWORKS/Device/$FRAMEWORK/XYBookAudioSDK" > "$OUTPUT/DEPENDENCIES.txt"
python3 "$PROJECT_ROOT/Scripts/bundle_release.py"
python3 "$PROJECT_ROOT/Scripts/checksums.py" "$OUTPUT"
echo "Release artifacts: $OUTPUT"
