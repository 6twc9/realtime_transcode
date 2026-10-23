class TranscriptSegment {
  final int segmentId;
  final DateTime timestamp;
  String originalText;
  String translatedText;
  bool isFinal;

  TranscriptSegment({
    required this.segmentId,
    required this.timestamp,
    required this.originalText,
    this.translatedText = "",
    this.isFinal = false,
  });

  String get formattedTime {
    final h = timestamp.hour.toString().padLeft(2, '0');
    final m = timestamp.minute.toString().padLeft(2, '0');
    final s = timestamp.second.toString().padLeft(2, '0');
    return "$h:$m:$s";
  }
}
