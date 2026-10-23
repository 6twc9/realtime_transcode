# 即時會議語音翻譯系統 (Real-time Meeting Speech Translator)

專為會議場景打造的即時語音收音、聽寫與翻譯工具。支援本機離線 AI 語音識別（Faster-Whisper），並透過瀏覽器 Web Audio API 實現低延遲串流與繁體中文（台灣習慣用語）即時字幕呈現。

---

## ✨ 核心特色

1. **本機離線語音辨識 (Faster-Whisper)**
   - 採用 CTranslate2 高效能推理引擎，針對 Apple Silicon (M 系列晶片) 與 CPU 進行量化加速。
   - 內建 `tiny`、`base` 離線模型（亦支援 `small`、`medium`），資料完全留於本機，確保會議商業隱私。
2. **智慧即時字幕 (Live Subtitle Banner)**
   - **雙語對照 / 純譯文模式**：隨時一鍵切換。
   - **即時聽寫預覽**：說話當下即時顯示暫態字幕，句尾自動結算並翻譯。
   - **大字體與全螢幕投影**：支援字體無段調整 (A- / A+) 及一鍵全螢幕，可放置於會議視窗旁或副螢幕。
3. **繁體中文在地化翻譯**
   - 整合台灣繁體中文轉換庫（OpenCC 常用詞彙如「軟體」、「發布/釋出」在地轉換）。
   - 具備多層翻譯容錯機制（本機 Ollama / Google Translate / MyMemory 備援），無縫切換。
4. **會議逐字稿記錄與匯出**
   - 完整記錄每一句對話之時間戳記、原文與翻譯。
   - 支援單句快速複製、一鍵複製全部內容。
   - 支援**一鍵匯出會議記錄 Markdown (`.md`)**。
5. **即時音訊動態波形**
   - 視覺化顯示麥克風收音強度與語音活動，隨時掌握收音狀態。

---

## 🚀 快速啟動

在專案目錄下執行：

```bash
./run.sh
```

此腳本將自動啟動服務並於瀏覽器中開啟 `http://127.0.0.1:8000`。

> 亦可手動啟動：
> ```bash
> source venv/bin/activate
> uvicorn app.main:app --host 127.0.0.1 --port 8000
> ```

---

## 🎙️ 使用說明

1. 開啟網頁後，初次使用請在瀏覽器彈窗中**允許麥克風存取權限**。
2. 在頂部工具列選擇：
   - **收音麥克風**：內建麥克風、AirPods 或外接 USB 麥克風。
   - **語音來源**：發言者的語言（如：英語 English、中文、日語或自動偵測）。
   - **翻譯目標**：預設為「繁體中文 (Traditional Chinese)」。
   - **離線模型**：預設為 `Base`（速度與辨識率平衡佳）；需要最低延遲可切換為 `Tiny`。
3. 點擊 **「開始會議收音」** 即可開始。
4. 會議結束後，可點擊右上角 **「匯出會議紀錄 (.md)」** 儲存本次會議紀錄。

---

## 💡 線上會議收音技巧 (Zoom / Google Meet / Teams)

如果希望在線上會議中**同時捕捉對方的聲音**：
- 可在 macOS 上免費安裝虛擬音訊驅動 [BlackHole](https://github.com/ExistentialAudio/BlackHole)（2ch）。
- 在 macOS 的「音訊 MIDI 設定」中建立「多輸出裝置」（包含耳機 + BlackHole）。
- 在本工具的「收音麥克風」下拉選單中直接選擇 **BlackHole 2ch**，即可直接擷取線上會議中所有與會者的語音！

---

## 🛠️ 技術架構

- **後端**：Python 3.9+, FastAPI, WebSockets, faster-whisper, OpenCC
- **前端**：Vanilla JavaScript, Web Audio API, CSS3
- **音訊傳輸**：16kHz 1-Channel Mono PCM Float32 (低延遲二進位 WebSocket 串流)
