import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

enum ConnectionStateStatus { disconnected, connecting, connected, error }

class WebSocketService {
  WebSocketChannel? _channel;
  StreamSubscription? _subscription;
  ConnectionStateStatus _status = ConnectionStateStatus.disconnected;

  final _transcriptController = StreamController<Map<String, dynamic>>.broadcast();
  final _translationController = StreamController<Map<String, dynamic>>.broadcast();
  final _statusController = StreamController<ConnectionStateStatus>.broadcast();

  Stream<Map<String, dynamic>> get onTranscript => _transcriptController.stream;
  Stream<Map<String, dynamic>> get onTranslation => _translationController.stream;
  Stream<ConnectionStateStatus> get onStatusChanged => _statusController.stream;
  ConnectionStateStatus get status => _status;

  Future<void> connect(String wsUrl) async {
    if (_status == ConnectionStateStatus.connected || _status == ConnectionStateStatus.connecting) {
      return;
    }

    _setStatus(ConnectionStateStatus.connecting);
    try {
      final uri = Uri.parse(wsUrl);
      _channel = WebSocketChannel.connect(uri);
      await _channel!.ready;

      _subscription = _channel!.stream.listen(
        (message) {
          if (message is String) {
            _handleTextMessage(message);
          }
        },
        onError: (error) {
          debugPrint("WebSocket error: $error");
          _setStatus(ConnectionStateStatus.error);
          disconnect();
        },
        onDone: () {
          debugPrint("WebSocket closed.");
          _setStatus(ConnectionStateStatus.disconnected);
          disconnect();
        },
      );

      _setStatus(ConnectionStateStatus.connected);
    } catch (e) {
      debugPrint("WebSocket connect exception: $e");
      _setStatus(ConnectionStateStatus.error);
      disconnect();
    }
  }

  void _handleTextMessage(String text) {
    try {
      final data = jsonDecode(text) as Map<String, dynamic>;
      final type = data['type'];
      if (type == 'transcript') {
        _transcriptController.add(data);
      } else if (type == 'translation_update') {
        _translationController.add(data);
      }
    } catch (e) {
      debugPrint("Failed to parse incoming WebSocket message: $e");
    }
  }

  void sendAudioChunk(Uint8List pcmBytes) {
    if (_channel != null && _status == ConnectionStateStatus.connected) {
      _channel!.sink.add(pcmBytes);
    }
  }

  void sendConfig({required String sourceLang, required String targetLang}) {
    if (_channel != null && _status == ConnectionStateStatus.connected) {
      final msg = jsonEncode({
        'type': 'config',
        'source_lang': sourceLang,
        'target_lang': targetLang,
      });
      _channel!.sink.add(msg);
    }
  }

  void _setStatus(ConnectionStateStatus newStatus) {
    _status = newStatus;
    _statusController.add(_status);
  }

  void disconnect() {
    _subscription?.cancel();
    _subscription = null;
    _channel?.sink.close();
    _channel = null;
    if (_status != ConnectionStateStatus.error) {
      _setStatus(ConnectionStateStatus.disconnected);
    }
  }

  void dispose() {
    disconnect();
    _transcriptController.close();
    _translationController.close();
    _statusController.close();
  }
}
