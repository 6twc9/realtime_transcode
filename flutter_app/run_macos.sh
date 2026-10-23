#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$DIR"

# Ensure flutter is on PATH
export PATH="$HOME/development/flutter/bin:$PATH"

echo "=========================================================="
echo "  啟動 Apple macOS 會議翻譯 App (Meeting Translator)     "
echo "=========================================================="

flutter run -d macos
