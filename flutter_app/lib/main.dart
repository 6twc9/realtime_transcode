import 'dart:io';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';
import 'models/transcript_segment.dart';
import 'services/audio_service.dart';
import 'services/websocket_service.dart';
import 'ui/floating_subtitle_card.dart';
import 'ui/transcript_list_view.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Desktop macOS Window Customization
  if (Platform.isMacOS) {
    await windowManager.ensureInitialized();
    const windowOptions = WindowOptions(
      size: Size(850, 680),
      minimumSize: Size(480, 360),
      center: true,
      backgroundColor: Colors.transparent,
      skipTaskbar: false,
      title: "即時會議語音翻譯 (Meeting Translator)",
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
      title: '即時會議翻譯',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0F172A),
        colorScheme: const ColorScheme.dark(
          primary: CupertinoColors.activeBlue,
          surface: Color(0xFF1E293B),
        ),
        fontFamily: Platform.isIOS || Platform.isMacOS ? '.SF Pro Text' : null,
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
  late final WebSocketService _wsService;
  late final AudioService _audioService;

  String _serverUrl = "ws://127.0.0.1:8000/ws/live";
  String _sourceLang = "en";
  String _targetLang = "zh-TW";

  final List<TranscriptSegment> _activeQueue = [];
  final List<TranscriptSegment> _history = [];
  static const int _maxLiveCompleted = 2;

  double _currentVolume = 0.0;
  double _subtitleFontSize = 24.0;
  bool _isDualMode = true;
  bool _isAlwaysOnTop = false;

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
    if (Platform.isIOS || Platform.isAndroid) {
      _serverUrl = "ws://192.168.68.55:8000/ws/live";
    }
    _wsService = WebSocketService();
    _audioService = AudioService(_wsService);

    _setupListeners();
  }

  void _setupListeners() {
    // Listen for volume changes for audio meter
    _audioService.onVolumeChanged.listen((vol) {
      if (mounted) {
        setState(() {
          _currentVolume = vol;
        });
      }
    });

    // Listen for incoming transcripts
    _wsService.onTranscript.listen((data) {
      final segId = data['segment_id'] as int?;
      final status = data['status'] as String?;
      final original = (data['original_text'] as String?) ?? "";

      if (original.isEmpty || segId == null) return;

      setState(() {
        final matchIndex = _activeQueue.indexWhere((item) => item.segmentId == segId);
        if (matchIndex != -1) {
          _activeQueue[matchIndex].originalText = original;
          if (status == 'final') {
            _activeQueue[matchIndex].isFinal = true;
          }
        } else {
          final newSeg = TranscriptSegment(
            segmentId: segId,
            timestamp: DateTime.now(),
            originalText: original,
            translatedText: "翻譯中...",
            isFinal: status == 'final',
          );
          _activeQueue.add(newSeg);
        }

        if (status == 'final') {
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

    // Listen for incoming translations
    _wsService.onTranslation.listen((data) {
      final segId = data['segment_id'] as int?;
      final status = data['status'] as String?;
      final translated = (data['translated_text'] as String?) ?? "";

      if (translated.isEmpty || segId == null) return;

      setState(() {
        // 1. Update in activeQueue
        final liveMatch = _activeQueue.where((item) => item.segmentId == segId);
        if (liveMatch.isNotEmpty) {
          liveMatch.first.translatedText = translated;
        }

        // 2. Update in history
        final histMatch = _history.where((item) => item.segmentId == segId);
        if (histMatch.isNotEmpty) {
          histMatch.first.translatedText = translated;
        }
      });
    });
  }

  Future<void> _toggleRecording() async {
    if (_audioService.isRecording) {
      await _audioService.stopRecording();
      _wsService.disconnect();
      for (final item in _activeQueue) {
        item.isFinal = true;
        _commitToHistory(item);
      }
      setState(() {});
    } else {
      _activeQueue.clear();
      await _wsService.connect(_serverUrl);
      _wsService.sendConfig(sourceLang: _sourceLang, targetLang: _targetLang);
      await _audioService.startRecording();
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
    final urlController = TextEditingController(text: _serverUrl);
    showCupertinoDialog(
      context: context,
      builder: (context) {
        return CupertinoAlertDialog(
          title: const Text("連線與語言設定"),
          content: Column(
            children: [
              const SizedBox(height: 12),
              CupertinoTextField(
                controller: urlController,
                placeholder: "WebSocket 伺服器網址 (ws://...)",
                style: const TextStyle(fontSize: 13),
              ),
              const SizedBox(height: 8),
              const Text(
                "iPhone/iPad 請填寫電腦區網 IP (如 ws://192.168.1.x:8000/ws/live)",
                style: TextStyle(fontSize: 11, color: Colors.grey),
              ),
            ],
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
                  _serverUrl = urlController.text.trim();
                });
                Navigator.pop(context);
              },
            ),
          ],
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
            const Text(
              "即時會議翻譯",
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
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
            // Prominent Subtitle Card
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: FloatingSubtitleCard(
                activeQueue: _activeQueue,
                isSpeaking: _audioService.isRecording,
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

            // Transcript Section
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

            // Bottom Action Bar
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
                      color: _audioService.isRecording
                          ? CupertinoColors.destructiveRed
                          : CupertinoColors.systemGreen,
                      borderRadius: BorderRadius.circular(12),
                      onPressed: _toggleRecording,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            _audioService.isRecording
                                ? CupertinoIcons.stop_fill
                                : CupertinoIcons.mic_fill,
                            size: 18,
                            color: Colors.white,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            _audioService.isRecording ? "停止會議收音" : "開始會議收音",
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
    _audioService.dispose();
    _wsService.dispose();
    super.dispose();
  }
}
