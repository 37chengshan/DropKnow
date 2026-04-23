#!/bin/bash
set -euo pipefail

TAG="${1:-local-dev}"
OUT_DIR="dist"
APP_NAME="DropKnow"
SCHEME="DropKnow"
CONFIG="Release"

echo "=== Building DropKnow (Release) ==="
WORKSPACE=$(find . -name "*.xcworkspace" -type d | head -1)
PROJECT=$(find . -name "*.xcodeproj" -type d | head -1)

if [[ -n "$WORKSPACE" ]]; then
  echo "Using workspace: $WORKSPACE"
  xcodebuild -workspace "$WORKSPACE" -scheme "$SCHEME" -configuration "$CONFIG" build \
    CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO
  APP_PATH=$(find ~/Library/Developer/Xcode/DerivedData -name "${APP_NAME}.app" -type d | grep "Release" | grep -v ".build" | head -1)
elif [[ -n "$PROJECT" ]]; then
  echo "Using project: $PROJECT"
  xcodebuild -project "$PROJECT" -scheme "$SCHEME" -configuration "$CONFIG" build \
    CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO
  APP_PATH=$(find ~/Library/Developer/Xcode/DerivedData -name "${APP_NAME}.app" -type d | grep "Release" | grep -v ".build" | head -1)
else
  echo "ERROR: No Xcode workspace or project found" >&2
  exit 1
fi

if [[ -z "$APP_PATH" ]]; then
  echo "ERROR: .app not found after build" >&2
  exit 1
fi

echo "=== Found app at: $APP_PATH ==="

# Verify Info.plist
echo "=== Verifying Info.plist ==="
/usr/bin/plutil -lint "$APP_PATH/Contents/Info.plist" && echo "Info.plist OK"

# Create zip
mkdir -p "$OUT_DIR"
ZIP_PATH="${OUT_DIR}/${APP_NAME}-${TAG}.zip"
echo "=== Packaging to $ZIP_PATH ==="
rm -f "$ZIP_PATH"
zip -r "$ZIP_PATH" "$APP_PATH"
echo "=== Done: $ZIP_PATH ==="
ls -lh "$ZIP_PATH"
