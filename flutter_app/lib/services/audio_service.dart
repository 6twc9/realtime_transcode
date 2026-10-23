import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:record/record.dart';
import 'websocket_service.dart';

class AudioService {
  final AudioRecorder _recorder = AudioRecorder();
  final WebSocketService _webSocketService;
  StreamSubscription? _audioSubscription;
  bool _isRecording = false;

  final _volumeController = StreamController<double>.broadcast();
  Stream<double> get onVolumeChanged => _volumeController.stream;

  bool get isRecording => _isRecording;

  AudioService(this._webSocketService);

  Future<bool> hasPermission() async {
    return await _recorder.hasPermission();
  }

  Future<void> startRecording() async {
    if (_isRecording) return;

    final hasPerm = await hasPermission();
    if (!hasPerm) {
      debugPrint("Microphone permission denied.");
      return;
    }

    try {
      // 16kHz, 1-channel mono, 16-bit PCM streaming
      const recordConfig = RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: 16000,
        numChannels: 1,
        echoCancel: true,
        noiseSuppress: true,
        autoGain: true,
      );

      final stream = await _recorder.startStream(recordConfig);
      _isRecording = true;

      _audioSubscription = stream.listen(
        (Uint8List chunk) {
          if (!_isRecording) return;

          // Stream audio chunk to backend via WebSocket
          _webSocketService.sendAudioChunk(chunk);

          // Compute RMS for volume meter
          _calculateVolume(chunk);
        },
        onError: (err) {
          debugPrint("Audio recording stream error: $err");
          stopRecording();
        },
      );
    } catch (e) {
      debugPrint("Error starting audio recording: $e");
      _isRecording = false;
    }
  }

  void _calculateVolume(Uint8List chunk) {
    if (chunk.isEmpty) return;
    int sum = 0;
    // 16-bit PCM samples
    final count = chunk.length ~/ 2;
    if (count == 0) return;

    final byteData = ByteData.sublistView(chunk);
    for (int i = 0; i < count; i++) {
      final sample = byteData.getInt16(i * 2, Endian.little);
      sum += sample * sample;
    }

    final rms = sqrt(sum / count);
    // Normalize to 0.0 ~ 1.0 range
    final normalized = (rms / 32768.0).clamp(0.0, 1.0);
    _volumeController.add(normalized);
  }

  Future<void> stopRecording() async {
    if (!_isRecording) return;
    _isRecording = false;
    await _audioSubscription?.cancel();
    _audioSubscription = null;
    await _recorder.stop();
    _volumeController.add(0.0);
  }

  void dispose() {
    stopRecording();
    _recorder.dispose();
    _volumeController.close();
  }
}
