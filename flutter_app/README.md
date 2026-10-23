# Apple (macOS & iOS) 即時會議翻譯 App

使用 **Flutter** 開發的 Apple 跨平台原生應用程式，同時支援 **macOS 桌面端** 與 **iOS (iPhone / iPad) 行動端**。

---

## 🌟 Apple 平台核心功能

1. **macOS 桌面端**
   - **置頂半透明懸浮字幕**：點擊視窗右上角「圖釘 📌」即可啟用置頂，可懸浮在 Zoom / Teams / Google Meet 會議視窗之上。
   - **毛玻璃效果 (Backdrop Blur)**：原生 macOS 磨砂半透明視窗質感。
   - **低延遲音訊串流**：原生 16kHz PCM 錄音，直接對接本地 FastAPI WebSocket 伺服器。
2. **iOS 行動端 (iPhone / iPad)**
   - **會議桌面模式**：將 iPhone 或 iPad 橫擺於會議桌中央，即時收錄會議現場談話並顯示超大雙語字幕。
   - **原生分享機制**：一鍵將會議逐字稿以 Markdown 格式分享至備忘錄 (Apple Notes)、郵件或 AirDrop。
3. **完整會議紀錄管理**
   - 即時關鍵字搜尋對話內容。
   - 單句對話快速複製到剪貼簿。
   - 一鍵匯出 `.md` 格式會議紀錄。

---

## 🚀 如何執行

### 1. 確保翻譯後端服務已啟動
本 Flutter App 負責收音與原生 UI 呈現，後端使用專案根目錄的 FastAPI 高效能解耦服務。
請在專案根目錄執行：
```bash
./run.sh
```
*(伺服器預設於 `ws://127.0.0.1:8000/ws/live`)*

---

### 2. 執行 macOS 桌面 App
在 `flutter_app` 目錄下執行：
```bash
./run_macos.sh
```
或使用命令：
```bash
flutter run -d macos
```

亦可直接在 Xcode 開啟專案編譯：
```bash
open macos/Runner.xcworkspace
```

---

### 3. 執行 iOS App (iPhone / iPad)
1. 確保電腦與 iPhone/iPad 連接至**同一個 Wi-Fi 區域網路**。
2. 啟動 iOS 模擬器或連接實體 iPhone：
   ```bash
   flutter run -d ios
   ```
3. 在 App 介面右上角點擊「設定 ⚙️」，將伺服器網址改為電腦的區域網路 IP（例如 `ws://192.168.1.100:8000/ws/live`）即可收音！

---

## 📂 專案檔案架構

- [`lib/main.dart`](file:///Users/wadetseng/develop/realtime_transcode/flutter_app/lib/main.dart)：App 主入口、macOS 視窗管理與主畫面。
- [`lib/models/transcript_segment.dart`](file:///Users/wadetseng/develop/realtime_transcode/flutter_app/lib/models/transcript_segment.dart)：對話段落資料模型。
- [`lib/services/audio_service.dart`](file:///Users/wadetseng/develop/realtime_transcode/flutter_app/lib/services/audio_service.dart)：跨平台原生麥克風收音與即時音波計算。
- [`lib/services/websocket_service.dart`](file:///Users/wadetseng/develop/realtime_transcode/flutter_app/lib/services/websocket_service.dart)：非同步雙向 WebSocket 傳輸協議。
- [`lib/ui/floating_subtitle_card.dart`](file:///Users/wadetseng/develop/realtime_transcode/flutter_app/lib/ui/floating_subtitle_card.dart)：毛玻璃質感即時懸浮字幕卡片。
- [`lib/ui/transcript_list_view.dart`](file:///Users/wadetseng/develop/realtime_transcode/flutter_app/lib/ui/transcript_list_view.dart)：會議逐字稿歷史記錄、搜尋與匯出介面。
