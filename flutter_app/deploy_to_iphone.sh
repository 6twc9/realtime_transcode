#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
cd "$DIR"

echo "==> 1. 編譯 Flutter 資源與代碼..."
export PATH="/Users/wadetseng/development/flutter/bin:/opt/homebrew/bin:/Library/Developer/CommandLineTools/usr/bin:$PATH"
flutter build ios --debug --no-codesign

echo "==> 2. 使用 Xcode 簽署 Runner.app..."
cd ios
xcodebuild -workspace Runner.xcworkspace -scheme Runner -configuration Debug -destination 'generic/platform=iOS' CODE_SIGN_IDENTITY="iPhone Developer" DEVELOPMENT_TEAM=6P33F5P63Y build -quiet

DERIVED_APP="/Users/wadetseng/Library/Developer/Xcode/DerivedData/Runner-eyceumayrgfgejgstkxvzomfwyit/Build/Products/Debug-iphoneos/Runner.app"

if [ ! -d "$DERIVED_APP" ]; then
  DERIVED_APP=$(find /Users/wadetseng/Library/Developer/Xcode/DerivedData/ -name "Runner.app" -path "*/Debug-iphoneos/*" | head -n 1)
fi

echo "==> 3. 打包 Runner.ipa..."
mkdir -p /tmp/Payload
rm -rf /tmp/Payload/*
cp -R "$DERIVED_APP" /tmp/Payload/
IPA_PATH="$DIR/build/Runner.ipa"
mkdir -p "$DIR/build"
rm -f "$IPA_PATH"
cd /tmp && zip -q -r "$IPA_PATH" Payload
rm -rf /tmp/Payload

echo "==> 4. 安裝至 iPhone..."
/Users/wadetseng/Library/Python/3.9/bin/pymobiledevice3 apps install --native "$IPA_PATH" || \
/Users/wadetseng/Library/Python/3.9/bin/pymobiledevice3 apps install "$IPA_PATH"

echo "==> 安裝成功！請直接在 iPhone 桌面開啟「即時會議翻譯」App。"
