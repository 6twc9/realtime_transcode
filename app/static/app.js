/**
 * Real-Time Meeting Speech Translator Client Application
 * Ultra-low Latency Decoupled Streaming Architecture
 */

// Application State
let audioContext = null;
let mediaStream = null;
let scriptProcessor = null;
let analyserNode = null;
let webSocket = null;
let isRecording = false;
let currentFontSize = 1.65; // rem
let isDualSub = true;
let isFullscreen = false;
let transcriptHistory = []; // Array of { segmentId, time, original, translated }
let activeSubtitleQueue = []; // Rolling buffer of { segmentId, time, original, translated, isFinal }
const MAX_LIVE_COMPLETED = 2; // Buffer threshold: retains 2-3 complete sentences before moving to transcript

// DOM Elements
const micSelect = document.getElementById("micSelect");
const sourceLangSelect = document.getElementById("sourceLangSelect");
const targetLangSelect = document.getElementById("targetLangSelect");
const modelSelect = document.getElementById("modelSelect");
const toggleRecordBtn = document.getElementById("toggleRecordBtn");
const btnText = document.getElementById("btnText");
const statusBadge = document.getElementById("statusBadge");
const statusText = document.getElementById("statusText");
const subtitleCard = document.getElementById("subtitleCard");
const livePulse = document.getElementById("livePulse");
const audioBars = document.querySelectorAll("#audioBars .bar");
const audioDbText = document.getElementById("audioDbText");
const liveSubtitleBody = document.getElementById("liveSubtitleBody");
const transcriptList = document.getElementById("transcriptList");
const transcriptCount = document.getElementById("transcriptCount");
const emptyState = document.getElementById("emptyState");
const autoScrollCheck = document.getElementById("autoScrollCheck");
const clearTranscriptBtn = document.getElementById("clearTranscriptBtn");
const copyAllBtn = document.getElementById("copyAllBtn");
const exportMdBtn = document.getElementById("exportMdBtn");
const fontSizeUpBtn = document.getElementById("fontSizeUpBtn");
const fontSizeDownBtn = document.getElementById("fontSizeDownBtn");
const toggleDualSubBtn = document.getElementById("toggleDualSubBtn");
const fullscreenSubBtn = document.getElementById("fullscreenSubBtn");
const themeToggleBtn = document.getElementById("themeToggleBtn");

// 1. Initialize Application
window.addEventListener("DOMContentLoaded", async () => {
  await populateAudioDevices();
  loadPreferences();
  setupEventListeners();
  fetchServerStatus();
});

// Load available microphones
async function populateAudioDevices() {
  try {
    const devices = await navigator.mediaDevices.enumerateDevices();
    micSelect.innerHTML = "";
    const audioInputs = devices.filter(d => d.kind === "audioinput");

    if (audioInputs.length === 0) {
      micSelect.innerHTML = `<option value="">預設系統麥克風</option>`;
      return;
    }

    audioInputs.forEach((device, index) => {
      const option = document.createElement("option");
      option.value = device.deviceId;
      option.textContent = device.label || `麥克風 ${index + 1}`;
      micSelect.appendChild(option);
    });
  } catch (err) {
    console.warn("無法取得音訊裝置列表:", err);
    micSelect.innerHTML = `<option value="">預設系統麥克風</option>`;
  }
}

// Fetch backend status
async function fetchServerStatus() {
  try {
    const res = await fetch("/api/status");
    if (res.ok) {
      const data = await res.json();
      if (data.current_model) {
        modelSelect.value = data.current_model;
      }
    }
  } catch (e) {
    console.warn("無法取得伺服器狀態:", e);
  }
}

// 2. Setup Event Listeners
function setupEventListeners() {
  toggleRecordBtn.addEventListener("click", toggleRecording);

  sourceLangSelect.addEventListener("change", syncConfigToWebSocket);
  targetLangSelect.addEventListener("change", syncConfigToWebSocket);

  modelSelect.addEventListener("change", async (e) => {
    const chosenModel = e.target.value;
    updateStatus("切換模型中...", "connecting");
    try {
      const res = await fetch("/api/model", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ model: chosenModel })
      });
      if (res.ok) {
        updateStatus(isRecording ? "即時收音中" : "待命就緒", isRecording ? "active" : "");
      }
    } catch (err) {
      console.error("切換模型失敗:", err);
    }
  });

  // Font size adjustments
  fontSizeUpBtn.addEventListener("click", () => {
    currentFontSize = Math.min(3.2, currentFontSize + 0.2);
    document.documentElement.style.setProperty("--sub-font-size", `${currentFontSize}rem`);
  });

  fontSizeDownBtn.addEventListener("click", () => {
    currentFontSize = Math.max(1.0, currentFontSize - 0.2);
    document.documentElement.style.setProperty("--sub-font-size", `${currentFontSize}rem`);
  });

  // Toggle Dual Subtitle Mode
  toggleDualSubBtn.addEventListener("click", () => {
    isDualSub = !isDualSub;
    toggleDualSubBtn.classList.toggle("active", isDualSub);
    toggleDualSubBtn.textContent = isDualSub ? "雙語模式" : "純譯文模式";
    localStorage.setItem("dual_sub", isDualSub);
    renderLiveSubtitleCard();
  });

  // Fullscreen Subtitle Mode
  fullscreenSubBtn.addEventListener("click", () => {
    isFullscreen = !isFullscreen;
    subtitleCard.classList.toggle("fullscreen-mode", isFullscreen);
    fullscreenSubBtn.textContent = isFullscreen ? "退出全螢幕" : "全螢幕";
  });

  // Clear Transcript
  clearTranscriptBtn.addEventListener("click", () => {
    if (confirm("確定要清空目前所有會議逐字稿記錄嗎？")) {
      transcriptHistory = [];
      activeSubtitleQueue = [];
      renderTranscriptList();
      renderLiveSubtitleCard();
    }
  });

  // Copy All Transcript
  copyAllBtn.addEventListener("click", () => {
    if (transcriptHistory.length === 0) return;
    const fullText = transcriptHistory.map(item =>
      `[${item.time}] 原文: ${item.original}\n[${item.time}] 翻譯: ${item.translated}`
    ).join("\n\n");
    navigator.clipboard.writeText(fullText);
    alert("已複製全部會議紀錄至剪貼簿！");
  });

  // Export Markdown
  exportMdBtn.addEventListener("click", exportMarkdown);

  // Dark/Light Theme toggle
  themeToggleBtn.addEventListener("click", () => {
    document.body.classList.toggle("light-theme");
  });
}

// 3. Audio Recording & WebSocket
async function toggleRecording() {
  if (isRecording) {
    stopRecording();
  } else {
    await startRecording();
  }
}

async function startRecording() {
  try {
    updateStatus("連線中...", "connecting");

    const constraints = {
      audio: {
        deviceId: micSelect.value ? { exact: micSelect.value } : undefined,
        echoCancellation: true,
        noiseSuppression: true,
        autoGainControl: true,
        channelCount: 1
      }
    };

    mediaStream = await navigator.mediaDevices.getUserMedia(constraints);
    await populateAudioDevices();

    audioContext = new (window.AudioContext || window.webkitAudioContext)({
      sampleRate: 16000
    });

    const source = audioContext.createMediaStreamSource(mediaStream);

    // Audio Visualizer Analyser
    analyserNode = audioContext.createAnalyser();
    analyserNode.fftSize = 64;
    source.connect(analyserNode);
    startVisualizer();

    // Connect WebSocket
    const protocol = window.location.protocol === "https:" ? "wss:" : "ws:";
    const wsUrl = `${protocol}//${window.location.host}/ws/live`;
    webSocket = new WebSocket(wsUrl);
    webSocket.binaryType = "arraybuffer";

    webSocket.onopen = () => {
      console.log("WebSocket connected.");
      isRecording = true;
      activeSubtitleQueue = [];
      renderLiveSubtitleCard();
      syncConfigToWebSocket();
      updateUIOnStart();
      setupAudioWorklet(source);
    };

    webSocket.onmessage = (event) => {
      try {
        const data = JSON.parse(event.data);
        if (data.type === "transcript") {
          handleIncomingTranscript(data);
        } else if (data.type === "translation_update") {
          handleTranslationUpdate(data);
        }
      } catch (e) {
        console.error("Message parse error:", e);
      }
    };

    webSocket.onerror = (err) => {
      console.error("WebSocket error:", err);
      stopRecording();
    };

    webSocket.onclose = () => {
      if (isRecording) stopRecording();
    };

  } catch (err) {
    console.error("無法啟動麥克風:", err);
    alert(`無法啟動收音: ${err.message}\n請確認已授予麥克風存取權限。`);
    stopRecording();
  }
}

function setupAudioWorklet(source) {
  // Use 2048 buffer size (128ms @ 16kHz) for ultra-low latency chunking
  const bufferSize = 2048;
  scriptProcessor = audioContext.createScriptProcessor(bufferSize, 1, 1);

  scriptProcessor.onaudioprocess = (e) => {
    if (!isRecording || !webSocket || webSocket.readyState !== WebSocket.OPEN) return;

    const inputData = e.inputBuffer.getChannelData(0);
    let outputData = inputData;
    if (audioContext.sampleRate !== 16000) {
      outputData = resampleAudio(inputData, audioContext.sampleRate, 16000);
    }

    // Send binary PCM Float32 buffer
    webSocket.send(outputData.buffer);
  };

  source.connect(scriptProcessor);
  scriptProcessor.connect(audioContext.destination);
}

// Linear resampler helper
function resampleAudio(audioBuffer, fromSampleRate, toSampleRate) {
  const ratio = fromSampleRate / toSampleRate;
  const newLength = Math.round(audioBuffer.length / ratio);
  const result = new Float32Array(newLength);
  for (let i = 0; i < newLength; i++) {
    const originalIndex = Math.round(i * ratio);
    result[i] = audioBuffer[originalIndex] || 0;
  }
  return result;
}

function stopRecording() {
  isRecording = false;

  if (scriptProcessor) {
    scriptProcessor.disconnect();
    scriptProcessor = null;
  }

  if (mediaStream) {
    mediaStream.getTracks().forEach(t => t.stop());
    mediaStream = null;
  }

  if (audioContext && audioContext.state !== "closed") {
    audioContext.close();
    audioContext = null;
  }

  if (webSocket) {
    webSocket.close();
    webSocket = null;
  }

  updateUIOnStop();
}

function syncConfigToWebSocket() {
  if (webSocket && webSocket.readyState === WebSocket.OPEN) {
    webSocket.send(JSON.stringify({
      type: "config",
      source_lang: sourceLangSelect.value,
      target_lang: targetLangSelect.value
    }));
  }
}

// 4. Visualizer & UI State
function startVisualizer() {
  const dataArray = new Uint8Array(analyserNode.frequencyBinCount);
  let silenceFrames = 0;
  let isSpeaking = false;

  function updateMeter() {
    if (!isRecording || !analyserNode) {
      audioBars.forEach(b => b.style.height = "4px");
      audioDbText.textContent = "靜音中";
      subtitleCard.classList.remove("speaking");
      isSpeaking = false;
      silenceFrames = 0;
      return;
    }

    analyserNode.getByteFrequencyData(dataArray);
    let sum = 0;
    for (let i = 0; i < dataArray.length; i++) {
      sum += dataArray[i];
    }
    const avg = sum / dataArray.length;

    audioBars.forEach((bar, idx) => {
      const val = dataArray[idx * 2] || 0;
      const height = Math.max(4, (val / 255) * 20);
      bar.style.height = `${height}px`;
    });

    // Hysteresis to prevent border/shadow flickering
    if (avg > 14) {
      silenceFrames = 0;
      if (!isSpeaking) {
        isSpeaking = true;
        subtitleCard.classList.add("speaking");
        audioDbText.textContent = "收音中";
      }
    } else {
      silenceFrames++;
      if (silenceFrames > 20 && isSpeaking) {
        isSpeaking = false;
        subtitleCard.classList.remove("speaking");
        audioDbText.textContent = "待命中";
      }
    }

    requestAnimationFrame(updateMeter);
  }

  updateMeter();
}

function updateUIOnStart() {
  toggleRecordBtn.className = "action-button stop-btn";
  btnText.textContent = "停止會議收音";
  updateStatus("即時收音中", "active");
  livePulse.classList.add("active");
}

function updateUIOnStop() {
  toggleRecordBtn.className = "action-button start-btn";
  btnText.textContent = "開始會議收音";
  updateStatus("待命就緒", "");
  livePulse.classList.remove("active");
  audioDbText.textContent = "靜音中";
  subtitleCard.classList.remove("speaking");

  // On stop, commit any remaining sentences to transcriptHistory so meeting notes are fully preserved
  activeSubtitleQueue.forEach(item => {
    item.isFinal = true;
    commitToTranscriptHistory(item);
  });
  renderLiveSubtitleCard();
}

function updateStatus(text, statusClass) {
  statusText.textContent = text;
  statusBadge.className = `status-badge ${statusClass}`;
}

// 5. Handling Decoupled Transcripts & Translations with Rolling FIFO Buffer
function renderLiveSubtitleCard() {
  if (!liveSubtitleBody) return;

  if (activeSubtitleQueue.length === 0) {
    const origBox = liveSubtitleBody.querySelector("#liveOriginal");
    const transBox = liveSubtitleBody.querySelector("#liveTranslated");
    if (origBox && transBox) {
      origBox.className = `original-box ${isDualSub ? '' : 'hidden'}`;
      const spanOrig = origBox.querySelector(".placeholder-text");
      if (spanOrig) spanOrig.textContent = isRecording ? "正在聆聽會議語音中，請對著麥克風說話..." : "點擊上方「開始會議收音」以啟動即時聽寫與翻譯...";
      const spanTrans = transBox.querySelector(".placeholder-text");
      if (spanTrans) spanTrans.textContent = isRecording ? "即時翻譯字幕將在此顯示..." : "翻譯字幕將即時顯示在此處";
      const items = liveSubtitleBody.querySelectorAll(".live-sentence-item");
      items.forEach(el => el.remove());
    } else {
      liveSubtitleBody.innerHTML = `
        <div class="original-box ${isDualSub ? '' : 'hidden'}" id="liveOriginal">
          <span class="placeholder-text">${isRecording ? "正在聆聽會議語音中，請對著麥克風說話..." : "點擊上方「開始會議收音」以啟動即時聽寫與翻譯..."}</span>
        </div>
        <div class="translated-box" id="liveTranslated">
          <span class="placeholder-text">${isRecording ? "即時翻譯字幕將在此顯示..." : "翻譯字幕將即時顯示在此處"}</span>
        </div>
      `;
    }
    return;
  }

  // Clear placeholders if active queue has items
  const origBox = liveSubtitleBody.querySelector("#liveOriginal");
  if (origBox) origBox.remove();
  const transBox = liveSubtitleBody.querySelector("#liveTranslated");
  if (transBox) transBox.remove();

  activeSubtitleQueue.forEach(item => {
    const isCompleted = item.isFinal;
    let el = document.getElementById(`live-seg-${item.segmentId}`);

    const originalHtml = isCompleted
      ? escapeHtml(item.original)
      : `<span class="partial-highlight">${escapeHtml(item.original)}</span>`;

    let transText = item.translated || "";
    let transHtml = "";
    if (isCompleted) {
      transHtml = escapeHtml(transText || "翻譯中...");
    } else {
      if (transText && !transText.includes("翻譯中")) {
        transHtml = `<span class="partial-highlight">${escapeHtml(transText)}</span>`;
      } else {
        transHtml = `<span class="partial-highlight" style="opacity: 0.6;">(翻譯中...)</span>`;
      }
    }

    if (!el) {
      el = document.createElement("div");
      el.className = isCompleted ? "live-sentence-item completed new-enter" : "live-sentence-item active new-enter";
      el.id = `live-seg-${item.segmentId}`;
      el.innerHTML = `
        <div class="live-original ${isDualSub ? '' : 'hidden'}">${originalHtml}</div>
        <div class="live-translated">${transHtml}</div>
      `;
      liveSubtitleBody.appendChild(el);
    } else {
      // In-place update to prevent DOM destruction and CSS animation re-triggering
      if (isCompleted) {
        if (!el.classList.contains("completed")) el.classList.add("completed");
        el.classList.remove("active");
      } else {
        if (!el.classList.contains("active")) el.classList.add("active");
        el.classList.remove("completed");
      }

      const origDiv = el.querySelector(".live-original");
      if (origDiv) {
        origDiv.classList.toggle("hidden", !isDualSub);
        if (origDiv.innerHTML !== originalHtml) {
          origDiv.innerHTML = originalHtml;
        }
      }

      const transDiv = el.querySelector(".live-translated");
      if (transDiv && transDiv.innerHTML !== transHtml) {
        transDiv.innerHTML = transHtml;
      }
    }
  });

  // Remove sentences that have rotated out of the live buffer
  const activeIds = new Set(activeSubtitleQueue.map(item => `live-seg-${item.segmentId}`));
  const domItems = liveSubtitleBody.querySelectorAll(".live-sentence-item");
  domItems.forEach(domEl => {
    if (!activeIds.has(domEl.id)) {
      domEl.remove();
    }
  });

  liveSubtitleBody.scrollTop = liveSubtitleBody.scrollHeight;
}

function handleIncomingTranscript(data) {
  const original = data.original_text.trim();
  const segId = data.segment_id;
  if (!original) return;

  const date = new Date(data.timestamp ? data.timestamp * 1000 : Date.now());
  const timeStr = date.toLocaleTimeString("zh-TW", { hour12: false });

  let item = activeSubtitleQueue.find(s => s.segmentId === segId);

  if (data.status === "partial") {
    if (!item) {
      item = {
        segmentId: segId,
        time: timeStr,
        original: original,
        translated: "翻譯中...",
        isFinal: false
      };
      activeSubtitleQueue.push(item);
    } else {
      item.original = original;
    }
    renderLiveSubtitleCard();
  } else if (data.status === "final") {
    if (!item) {
      item = {
        segmentId: segId,
        time: timeStr,
        original: original,
        translated: "翻譯中...",
        isFinal: true
      };
      activeSubtitleQueue.push(item);
    } else {
      item.original = original;
      item.isFinal = true;
    }

    // Rolling FIFO Buffer:
    // Retains 2-3 complete sentences visible on the upper subtitle card.
    // When completed sentences exceed MAX_LIVE_COMPLETED (2),
    // smoothly move the oldest completed sentence down into the permanent transcript!
    shiftOldestToTranscriptIfNeeded();
    renderLiveSubtitleCard();
  }
}

function shiftOldestToTranscriptIfNeeded() {
  const completedSentences = activeSubtitleQueue.filter(s => s.isFinal);
  while (completedSentences.length > MAX_LIVE_COMPLETED) {
    const oldestIndex = activeSubtitleQueue.findIndex(s => s.isFinal);
    if (oldestIndex !== -1) {
      const [oldest] = activeSubtitleQueue.splice(oldestIndex, 1);
      commitToTranscriptHistory(oldest);
      const cIdx = completedSentences.indexOf(oldest);
      if (cIdx !== -1) completedSentences.splice(cIdx, 1);
    } else {
      break;
    }
  }
}

function commitToTranscriptHistory(item) {
  if (!item || !item.original || !item.original.trim()) return;

  let existing = transcriptHistory.find(h => h.segmentId === item.segmentId);
  const transText = item.translated && !item.translated.includes("(翻譯中...)")
    ? item.translated
    : "翻譯中...";

  if (!existing) {
    transcriptHistory.push({
      segmentId: item.segmentId,
      time: item.time,
      original: item.original,
      translated: transText
    });
  } else {
    existing.original = item.original;
    if (transText !== "翻譯中...") {
      existing.translated = transText;
    }
  }
  renderTranscriptList();
}

function handleTranslationUpdate(data) {
  const trans = data.translated_text.trim();
  const segId = data.segment_id;
  if (!trans) return;

  // 1. Update in activeSubtitleQueue (if currently visible on live card)
  const liveItem = activeSubtitleQueue.find(s => s.segmentId === segId);
  if (liveItem) {
    liveItem.translated = trans;
    const domElem = document.getElementById(`live-seg-${segId}`);
    if (domElem) {
      const transBox = domElem.querySelector(".live-translated");
      if (transBox) {
        if (data.status === "partial" && !liveItem.isFinal) {
          const targetHtml = `<span class="partial-highlight">${escapeHtml(trans)}</span>`;
          if (transBox.innerHTML !== targetHtml) {
            transBox.innerHTML = targetHtml;
          }
        } else {
          if (transBox.textContent !== trans) {
            transBox.textContent = trans;
          }
        }
      }
    } else {
      renderLiveSubtitleCard();
    }
  }

  // 2. Update in transcriptHistory (if already moved down to transcript list)
  const historyItem = transcriptHistory.find(h => h.segmentId === segId);
  if (historyItem) {
    historyItem.translated = trans;
    updateTranscriptItemDOM(segId, trans);
  }
}

function updateTranscriptItemDOM(segId, translatedText) {
  const domElem = document.getElementById(`seg-${segId}`);
  if (domElem) {
    const transBox = domElem.querySelector(".item-translated");
    if (transBox && transBox.textContent !== translatedText) {
      transBox.textContent = translatedText;
    }
  }
}

function renderTranscriptList() {
  if (transcriptHistory.length === 0) {
    emptyState.style.display = "flex";
    const items = transcriptList.querySelectorAll(".transcript-item");
    items.forEach(el => el.remove());
    if (!transcriptList.contains(emptyState)) {
      transcriptList.appendChild(emptyState);
    }
    transcriptCount.textContent = "0 則紀錄";
    return;
  }

  emptyState.style.display = "none";

  // Incremental append/update to prevent screen strobe and layout jumping
  const historyIds = new Set();
  transcriptHistory.forEach((item, index) => {
    historyIds.add(`seg-${item.segmentId}`);
    let el = document.getElementById(`seg-${item.segmentId}`);
    if (!el) {
      el = document.createElement("div");
      el.className = "transcript-item";
      el.id = `seg-${item.segmentId}`;
      el.innerHTML = `
        <div class="item-meta">
          <span class="item-time">[${item.time}]</span>
          <button class="item-copy-btn" onclick="copyItem('${item.segmentId}')">複製</button>
        </div>
        <div class="item-original">${escapeHtml(item.original)}</div>
        <div class="item-translated">${escapeHtml(item.translated)}</div>
      `;
      transcriptList.appendChild(el);
    } else {
      const origDiv = el.querySelector(".item-original");
      if (origDiv && origDiv.textContent !== item.original) {
        origDiv.textContent = item.original;
      }
      const transDiv = el.querySelector(".item-translated");
      if (transDiv && transDiv.textContent !== item.translated) {
        transDiv.textContent = item.translated;
      }
    }
  });

  const domItems = transcriptList.querySelectorAll(".transcript-item");
  domItems.forEach(domEl => {
    if (!historyIds.has(domEl.id)) {
      domEl.remove();
    }
  });

  transcriptCount.textContent = `${transcriptHistory.length} 則紀錄`;

  if (autoScrollCheck && autoScrollCheck.checked) {
    transcriptList.scrollTop = transcriptList.scrollHeight;
  }
}

window.copyItem = function(idOrIdx) {
  let item = typeof idOrIdx === "number" ? transcriptHistory[idOrIdx] : transcriptHistory.find(h => h.segmentId === idOrIdx);
  if (!item && typeof idOrIdx === "string") {
    const num = parseInt(idOrIdx, 10);
    if (!isNaN(num) && transcriptHistory[num]) item = transcriptHistory[num];
  }
  if (item) {
    navigator.clipboard.writeText(`${item.original}\n${item.translated}`);
  }
};

function exportMarkdown() {
  if (transcriptHistory.length === 0) {
    alert("目前尚無會議紀錄可匯出！");
    return;
  }

  const now = new Date().toLocaleString("zh-TW");
  let md = `# 會議逐字稿與即時翻譯記錄\n\n- **產生日出時間**: ${now}\n- **總段落數**: ${transcriptHistory.length}\n\n---\n\n`;

  transcriptHistory.forEach(item => {
    md += `### [${item.time}]\n**原文**: ${item.original}\n\n**翻譯**: ${item.translated}\n\n`;
  });

  const blob = new Blob([md], { type: "text/markdown;charset=utf-8" });
  const url = URL.createObjectURL(blob);
  const a = document.createElement("a");
  a.href = url;
  a.download = `meeting_transcript_${new Date().toISOString().slice(0, 10)}.md`;
  a.click();
  URL.revokeObjectURL(url);
}

function escapeHtml(str) {
  if (!str) return "";
  return str.replace(/[&<>"']/g, (m) => ({
    "&": "&amp;",
    "<": "&lt;",
    ">": "&gt;",
    '"': "&quot;",
    "'": "&#39;"
  })[m]);
}

function loadPreferences() {
  const savedDual = localStorage.getItem("dual_sub");
  if (savedDual !== null) {
    isDualSub = savedDual === "true";
    toggleDualSubBtn.classList.toggle("active", isDualSub);
    toggleDualSubBtn.textContent = isDualSub ? "雙語模式" : "純譯文模式";
    renderLiveSubtitleCard();
  }
}
