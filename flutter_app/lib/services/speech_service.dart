import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:speech_to_text/speech_recognition_result.dart';

class SpeechService {
  final stt.SpeechToText _speech = stt.SpeechToText();

  bool _isInitialized = false;
  bool _isListening = false;
  bool _shouldKeepListening = false;
  String _currentLocaleId = "en_US";

  int _segmentCounter = 0;
  String _lastRecognizedWords = "";

  // Streams for UI
  final _textController = StreamController<SpeechResultEvent>.broadcast();
  final _volumeController = StreamController<double>.broadcast();
  final _statusController = StreamController<bool>.broadcast();

  Stream<SpeechResultEvent> get onSpeechResult => _textController.stream;
  Stream<double> get onVolumeChanged => _volumeController.stream;
  Stream<bool> get onListeningStateChanged => _statusController.stream;

  bool get isListening => _isListening;
  bool get isInitialized => _isInitialized;

  Future<bool> initialize() async {
    if (_isInitialized) return true;

    try {
      _isInitialized = await _speech.initialize(
        onError: (val) {
          debugPrint("Speech recognition error: ${val.errorMsg} (permanent: ${val.permanent})");
          _handleAutoRestart();
        },
        onStatus: (status) {
          debugPrint("Speech recognition status: $status");
          if (status == "listening") {
            _isListening = true;
            _statusController.add(true);
          } else if (status == "done" || status == "notListening") {
            _isListening = false;
            _handleAutoRestart();
          }
        },
      );
      return _isInitialized;
    } catch (e) {
      debugPrint("Speech initialize exception: $e");
      return false;
    }
  }

  void _handleAutoRestart() {
    if (_shouldKeepListening) {
      // Seamless restart for continuous meeting recording
      Future.delayed(const Duration(milliseconds: 250), () {
        if (_shouldKeepListening && !_speech.isListening) {
          _startListeningInternal();
        }
      });
    } else {
      _isListening = false;
      _statusController.add(false);
      _volumeController.add(0.0);
    }
  }

  Future<void> startListening({String sourceLang = "en"}) async {
    if (!_isInitialized) {
      final ok = await initialize();
      if (!ok) {
        debugPrint("SpeechToText failed to initialize.");
        return;
      }
    }

    _shouldKeepListening = true;
    _currentLocaleId = _resolveLocaleId(sourceLang);
    _segmentCounter++;
    _lastRecognizedWords = "";

    await _startListeningInternal();
  }

  String _resolveLocaleId(String langCode) {
    final lower = langCode.toLowerCase();
    if (lower.startsWith("zh")) {
      if (lower.contains("cn") || lower.contains("hans")) return "zh_CN";
      return "zh_TW";
    }
    if (lower.startsWith("en")) return "en_US";
    if (lower.startsWith("ja")) return "ja_JP";
    if (lower.startsWith("ko")) return "ko_KR";
    if (lower.startsWith("fr")) return "fr_FR";
    if (lower.startsWith("de")) return "de_DE";
    if (lower.startsWith("es")) return "es_ES";
    return "en_US";
  }

  Future<void> _startListeningInternal() async {
    if (!_shouldKeepListening) return;

    try {
      await _speech.listen(
        onResult: _onSpeechResult,
        localeId: _currentLocaleId,
        listenOptions: stt.SpeechListenOptions(
          listenMode: stt.ListenMode.dictation,
          partialResults: true,
          cancelOnError: false,
        ),
        onSoundLevelChange: (level) {
          // Normalize sound level (usually -10dB ~ 10dB on iOS/Android) to 0.0 ~ 1.0
          final normalized = ((level + 10.0) / 20.0).clamp(0.0, 1.0);
          _volumeController.add(normalized);
        },
      );
      _isListening = true;
      _statusController.add(true);
    } catch (e) {
      debugPrint("Error starting listen: $e");
      _handleAutoRestart();
    }
  }

  void _onSpeechResult(SpeechRecognitionResult result) {
    final words = result.recognizedWords.trim();
    if (words.isEmpty) return;

    final isFinal = result.finalResult;
    _lastRecognizedWords = words;

    _textController.add(SpeechResultEvent(
      segmentId: _segmentCounter,
      text: words,
      isFinal: isFinal,
    ));

    if (isFinal) {
      // Advance to next segment for subsequent speech
      _segmentCounter++;
      _lastRecognizedWords = "";
    }
  }

  Future<void> stopListening() async {
    _shouldKeepListening = false;
    _isListening = false;
    _statusController.add(false);
    _volumeController.add(0.0);

    // If there was an active pending segment, finalize it
    if (_lastRecognizedWords.isNotEmpty) {
      _textController.add(SpeechResultEvent(
        segmentId: _segmentCounter,
        text: _lastRecognizedWords,
        isFinal: true,
      ));
      _lastRecognizedWords = "";
    }

    try {
      await _speech.stop();
    } catch (e) {
      debugPrint("Error stopping speech: $e");
    }
  }

  void dispose() {
    stopListening();
    _textController.close();
    _volumeController.close();
    _statusController.close();
  }
}

class SpeechResultEvent {
  final int segmentId;
  final String text;
  final bool isFinal;

  SpeechResultEvent({
    required this.segmentId,
    required this.text,
    required this.isFinal,
  });
}
