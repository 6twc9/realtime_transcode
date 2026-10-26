import 'dart:async';
import 'dart:io';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import 'models/transcript_segment.dart';
import 'services/speech_service.dart';
import 'services/translation_service.dart';
import 'ui/floating_subtitle_card.dart';
import 'ui/transcript_list_view.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Desktop window configuration (macOS)
  if (Platform.isMacOS) {
    await windowManager.ensureInitialized();
    const windowOptions = WindowOptions(
      size: Size(580, 840),
      minimumSize: Size(420, 600),
      center: true,
      backgroundColor: Colors.transparent,
      skipTaskbar: false,
      title: "即時會議翻譯 (獨立運行版)",
      titleBarStyle: TitleBarStyle.normal,
    );

    windowManager.waitUntilReadyToShow(windowOptions, () async {
      await windowManager.show();
      await windowManager.focus();
    });
  }

  runApp(const MeetingTranslatorApp());
}

class MeetingTranslatorApp extends StatelessWidget {
  const MeetingTranslatorApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: "即時會議翻譯",
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0F172A), // Dark slate theme
        colorScheme: const ColorScheme.dark(
          primary: CupertinoColors.activeBlue,
          surface: Color(0xFF1E293B),
        ),
        useMaterial3: true,
      ),
      home: const MeetingMainScreen(),
    );
  }
}

class MeetingMainScreen extends StatefulWidget {
  const MeetingMainScreen({super.key});

  @override
  State<MeetingMainScreen> createState() => _MeetingMainScreenState();
}

class _MeetingMainScreenState extends State<MeetingMainScreen> {
  late final SpeechService _speechService;
  late final TranslationService _translationService;

  String _sourceLang = "en";
  String _targetLang = "zh-TW";
  String _geminiApiKey = "";

  final List<TranscriptSegment> _activeQueue = [];
  final List<TranscriptSegment> _history = [];
  static const int _maxLiveCompleted = 2;

  double _currentVolume = 0.0;
  double _subtitleFontSize = 24.0;
  bool _isDualMode = true;
  bool _isAlwaysOnTop = false;

  Timer? _debounceTimer;

  final Map<String, String> _sourceLanguages = {
    "en": "英語 (English)",
    "zh": "中文 (Chinese)",
    "ja": "日語 (Japanese)",
    "ko": "韓語 (Korean)",
    "fr": "法語 (French)",
    "de": "德語 (German)",
    "es": "西班牙語 (Spanish)",
  };

  final Map<String, String> _targetLanguages = {
    "zh-TW": "繁體中文 (Traditional Chinese)",
    "zh-CN": "簡體中文 (Simplified Chinese)",
    "en": "英語 (English)",
    "ja": "日語 (Japanese)",
    "ko": "韓語 (Korean)",
  };

  void _commitToHistory(TranscriptSegment item) {
    if (item.originalText.trim().isEmpty) return;
    final match = _history.where((h) => h.segmentId == item.segmentId);
    if (match.isEmpty) {
      _history.add(TranscriptSegment(
        segmentId: item.segmentId,
        timestamp: item.timestamp,
        originalText: item.originalText,
        translatedText: item.translatedText.isNotEmpty && !item.translatedText.contains("翻譯中")
            ? item.translatedText
            : "翻譯中...",
        isFinal: true,
      ));
    } else {
      match.first.originalText = item.originalText;
      if (item.translatedText.isNotEmpty && !item.translatedText.contains("翻譯中")) {
        match.first.translatedText = item.translatedText;
      }
    }
  }

  @override
  void initState() {
    super.initState();
    _speechService = SpeechService();
    _translationService = TranslationService();

    _setupListeners();
  }

  void _setupListeners() {
    // Listen for volume changes for audio meter
    _speechService.onVolumeChanged.listen((vol) {
      if (mounted) {
        setState(() {
          _currentVolume = vol;
        });
      }
    });

    // Listen for speech recognition results directly from Apple Speech
    _speechService.onSpeechResult.listen((event) {
      final segId = event.segmentId;
      final original = event.text;
      final isFinal = event.isFinal;

      if (original.isEmpty) return;

      setState(() {
        final matchIndex = _activeQueue.indexWhere((item) => item.segmentId == segId);
        TranscriptSegment segment;
        if (matchIndex != -1) {
          segment = _activeQueue[matchIndex];
          segment.originalText = original;
          if (isFinal) {
            segment.isFinal = true;
          }
        } else {
          segment = TranscriptSegment(
            segmentId: segId,
            timestamp: DateTime.now(),
            originalText: original,
            translatedText: "翻譯中...",
            isFinal: isFinal,
          );
          _activeQueue.add(segment);
        }

        // Trigger real-time translation
        _scheduleTranslation(segment, original, segId, isFinal);

        if (isFinal) {
          // FIFO rolling buffer: retains 2-3 completed sentences before moving to transcript
          final completed = _activeQueue.where((s) => s.isFinal).toList();
          while (completed.length > _maxLiveCompleted) {
            final oldestIdx = _activeQueue.indexWhere((s) => s.isFinal);
            if (oldestIdx != -1) {
              final oldest = _activeQueue.removeAt(oldestIdx);
              _commitToHistory(oldest);
              completed.remove(oldest);
            } else {
              break;
            }
          }
        }
      });
    });
  }

  void _scheduleTranslation(TranscriptSegment segment, String text, int segId, bool isFinal) {
    if (isFinal) {
      _doTranslate(segment, text, segId);
    } else {
      _debounceTimer?.cancel();
      _debounceTimer = Timer(const Duration(milliseconds: 300), () {
        _doTranslate(segment, text, segId);
      });
    }
  }

  Future<void> _doTranslate(TranscriptSegment segment, String text, int segId) async {
    final translated = await _translationService.translate(
      text,
      sourceLang: _sourceLang,
      targetLang: _targetLang,
    );

    if (mounted) {
      setState(() {
        segment.translatedText = translated;

        // Also update history if segment was already committed
        final histMatch = _history.where((item) => item.segmentId == segId);
        if (histMatch.isNotEmpty) {
          histMatch.first.translatedText = translated;
        }
      });
    }
  }

  Future<void> _toggleRecording() async {
    if (_speechService.isListening) {
      await _speechService.stopListening();
      for (final item in _activeQueue) {
        item.isFinal = true;
        _commitToHistory(item);
      }
      setState(() {});
    } else {
      _activeQueue.clear();
      await _speechService.startListening(sourceLang: _sourceLang);
      setState(() {});
    }
  }

  void _toggleAlwaysOnTop() async {
    if (Platform.isMacOS) {
      _isAlwaysOnTop = !_isAlwaysOnTop;
      await windowManager.setAlwaysOnTop(_isAlwaysOnTop);
      setState(() {});
    }
  }

  void _openSettingsDialog() {
    String tempSource = _sourceLang;
    String tempTarget = _targetLang;
    final apiKeyController = TextEditingController(text: _geminiApiKey);

    showCupertinoDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return CupertinoAlertDialog(
              title: const Text("語言與翻譯設定"),
              content: Material(
                color: Colors.transparent,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 12),
                    const Text(
                      "語音輸入語言 (發言者)：",
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      decoration: BoxDecoration(
                        color: Colors.white10,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: tempSource,
                          isExpanded: true,
                          dropdownColor: const Color(0xFF1E293B),
                          items: _sourceLanguages.entries.map((e) {
                            return DropdownMenuItem(
                              value: e.key,
                              child: Text(e.value, style: const TextStyle(fontSize: 13)),
                            );
                          }).toList(),
                          onChanged: (val) {
                            if (val != null) {
                              setDialogState(() => tempSource = val);
                            }
                          },
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      "翻譯目標語言 (字幕顯示)：",
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      decoration: BoxDecoration(
                        color: Colors.white10,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: tempTarget,
                          isExpanded: true,
                          dropdownColor: const Color(0xFF1E293B),
                          items: _targetLanguages.entries.map((e) {
                            return DropdownMenuItem(
                              value: e.key,
                              child: Text(e.value, style: const TextStyle(fontSize: 13)),
                            );
                          }).toList(),
                          onChanged: (val) {
                            if (val != null) {
                              setDialogState(() => tempTarget = val);
                            }
                          },
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    const Text(
                      "Gemini API Key (選填，啟用大模型潤色)：",
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                    const SizedBox(height: 4),
                    CupertinoTextField(
                      controller: apiKeyController,
                      placeholder: "若留空則使用 Google 高速直連翻譯",
                      style: const TextStyle(fontSize: 12),
                    ),
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.blue.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.blue.withOpacity(0.3)),
                      ),
                      child: const Row(
                        children: [
                          Icon(CupertinoIcons.checkmark_shield_fill, size: 14, color: Colors.lightBlueAccent),
                          SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              "目前為獨立離線/直連模式，無須啟動任何電腦後端服務。",
                              style: TextStyle(fontSize: 11, color: Colors.lightBlueAccent),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                CupertinoDialogAction(
                  child: const Text("取消"),
                  onPressed: () => Navigator.pop(context),
                ),
                CupertinoDialogAction(
                  isDefaultAction: true,
                  child: const Text("儲存"),
                  onPressed: () {
                    setState(() {
                      _sourceLang = tempSource;
                      _targetLang = tempTarget;
                      _geminiApiKey = apiKeyController.text.trim();
                      _translationService.geminiApiKey = _geminiApiKey;
                    });
                    Navigator.pop(context);
                  },
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E293B),
        elevation: 0,
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: CupertinoColors.activeBlue,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(CupertinoIcons.mic_fill, size: 16, color: Colors.white),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  "即時會議翻譯",
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                ),
                Text(
                  "${_sourceLanguages[_sourceLang]?.split(' ')[0] ?? _sourceLang} ➔ ${_targetLanguages[_targetLang]?.split(' ')[0] ?? _targetLang} (獨立運作)",
                  style: const TextStyle(fontSize: 10, color: Colors.white54),
                ),
              ],
            ),
          ],
        ),
        actions: [
          if (Platform.isMacOS)
            CupertinoButton(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              onPressed: _toggleAlwaysOnTop,
              child: Icon(
                _isAlwaysOnTop ? CupertinoIcons.pin_fill : CupertinoIcons.pin,
                size: 18,
                color: _isAlwaysOnTop ? CupertinoColors.activeBlue : Colors.white70,
              ),
            ),
          CupertinoButton(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            onPressed: _openSettingsDialog,
            child: const Icon(CupertinoIcons.settings, size: 18, color: Colors.white70),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Prominent Subtitle Card (Top)
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: FloatingSubtitleCard(
                activeQueue: _activeQueue,
                isSpeaking: _speechService.isListening,
                volume: _currentVolume,
                isDualMode: _isDualMode,
                fontSize: _subtitleFontSize,
                onToggleDual: () {
                  setState(() {
                    _isDualMode = !_isDualMode;
                  });
                },
                onIncreaseFontSize: () {
                  setState(() {
                    _subtitleFontSize = (_subtitleFontSize + 2).clamp(16.0, 40.0);
                  });
                },
                onDecreaseFontSize: () {
                  setState(() {
                    _subtitleFontSize = (_subtitleFontSize - 2).clamp(16.0, 40.0);
                  });
                },
              ),
            ),

            // Transcript History Section (Middle)
            Expanded(
              child: TranscriptListView(
                history: _history,
                onClearHistory: () {
                  setState(() {
                    _history.clear();
                    _activeQueue.clear();
                  });
                },
              ),
            ),

            // Bottom Action Bar (Bottom)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              decoration: const BoxDecoration(
                color: Color(0xFF1E293B),
                border: Border(top: BorderSide(color: Colors.white12)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: CupertinoButton(
                      color: _speechService.isListening
                          ? CupertinoColors.destructiveRed
                          : CupertinoColors.systemGreen,
                      borderRadius: BorderRadius.circular(12),
                      onPressed: _toggleRecording,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            _speechService.isListening
                                ? CupertinoIcons.stop_fill
                                : CupertinoIcons.mic_fill,
                            size: 18,
                            color: Colors.white,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            _speechService.isListening ? "停止會議收音" : "開始會議收音",
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _speechService.dispose();
    super.dispose();
  }
}
