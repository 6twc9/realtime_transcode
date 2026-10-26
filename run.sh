#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$DIR"

echo "=========================================================="
echo "  即時會議語音翻譯系統 (Real-time Meeting Translator)   "
echo "=========================================================="

# Check Python environment
if [ ! -d "venv" ]; then
    echo "建立虛擬環境中..."
    python3 -m venv venv
    ./venv/bin/pip install --upgrade pip
    ./venv/bin/pip install -r requirements.txt
fi

# Check and free port 8000 if occupied
EXISTING_PID=$(lsof -ti :8000 || true)
if [ -n "$EXISTING_PID" ]; then
    echo "關閉前次執行的服務 (PID: $EXISTING_PID)..."
    kill -9 $EXISTING_PID 2>/dev/null || true
    sleep 0.5
fi

echo "啟動服務於 http://127.0.0.1:8000 ..."

# Open browser after 1.5 seconds in background
(sleep 1.5 && open "http://127.0.0.1:8000") &

# Start Uvicorn with reload support (0.0.0.0 allows iPhone on the same Wi-Fi to connect)
exec ./venv/bin/uvicorn app.main:app --host 0.0.0.0 --port 8000 --reload
