#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$DIR"

# Ensure flutter and Homebrew are on PATH
export PATH="$HOME/development/flutter/bin:/opt/homebrew/bin:/Library/Developer/CommandLineTools/usr/bin:$PATH"

echo "=========================================================="
echo "  啟動 Apple iOS 會議翻譯 App (Meeting Translator)       "
echo "=========================================================="

# Check if an iOS device or simulator is connected/available
DEVICES=$(flutter devices 2>/dev/null | grep -E "ios|iPhone" || true)

if [ -z "$DEVICES" ]; then
    echo "未檢測到運行中的 iOS 模擬器或實體 iPhone。"
    echo "正在嘗試啟動預設 iPhone 模擬器..."
    open -a Simulator 2>/dev/null || true
    sleep 3
fi

# Run Flutter on iOS
flutter run -d ios
