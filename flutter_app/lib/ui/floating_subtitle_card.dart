import 'dart:ui';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../models/transcript_segment.dart';

class FloatingSubtitleCard extends StatelessWidget {
  final List<TranscriptSegment> activeQueue;
  final bool isSpeaking;
  final double volume;
  final bool isDualMode;
  final double fontSize;
  final VoidCallback onToggleDual;
  final VoidCallback onIncreaseFontSize;
  final VoidCallback onDecreaseFontSize;

  const FloatingSubtitleCard({
    super.key,
    required this.activeQueue,
    required this.isSpeaking,
    required this.volume,
    required this.isDualMode,
    required this.fontSize,
    required this.onToggleDual,
    required this.onIncreaseFontSize,
    required this.onDecreaseFontSize,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
          decoration: BoxDecoration(
            color: isDark
                ? Colors.black.withOpacity(0.65)
                : Colors.white.withOpacity(0.85),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isSpeaking
                  ? CupertinoColors.activeBlue.withOpacity(0.6)
                  : (isDark ? Colors.white12 : Colors.black12),
              width: isSpeaking ? 2.0 : 1.0,
            ),
            boxShadow: [
              BoxShadow(
                color: isSpeaking
                    ? CupertinoColors.activeBlue.withOpacity(0.2)
                    : Colors.black.withOpacity(0.15),
                blurRadius: 24,
                spreadRadius: 2,
              )
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Top control bar
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      // Recording indicator & audio volume wave
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: isSpeaking
                              ? CupertinoColors.systemGreen
                              : CupertinoColors.systemGrey,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        isSpeaking ? "即時收音中" : "待命中",
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: isSpeaking
                              ? CupertinoColors.systemGreen
                              : (isDark ? Colors.white54 : Colors.black45),
                        ),
                      ),
                      const SizedBox(width: 12),
                      _buildVolumeVisualizer(volume, isSpeaking),
                    ],
                  ),
                  Row(
                    children: [
                      _buildIconButton(
                        icon: CupertinoIcons.minus,
                        tooltip: "縮小字體",
                        onPressed: onDecreaseFontSize,
                      ),
                      const SizedBox(width: 4),
                      _buildIconButton(
                        icon: CupertinoIcons.plus,
                        tooltip: "放大字體",
                        onPressed: onIncreaseFontSize,
                      ),
                      const SizedBox(width: 8),
                      CupertinoButton(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        color: isDualMode
                            ? CupertinoColors.activeBlue
                            : CupertinoColors.systemGrey5,
                        borderRadius: BorderRadius.circular(12),
                        minSize: 26,
                        onPressed: onToggleDual,
                        child: Text(
                          isDualMode ? "雙語模式" : "純譯文",
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: isDualMode ? Colors.white : Colors.black87,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Sentences List
              if (activeQueue.isEmpty) ...[
                if (isDualMode) ...[
                  Text(
                    "等待發言...",
                    style: TextStyle(
                      fontSize: fontSize * 0.75,
                      color: isDark ? Colors.white70 : Colors.black54,
                      height: 1.35,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                  const SizedBox(height: 10),
                ],
                Text(
                  "即時翻譯字幕將顯示於此",
                  style: TextStyle(
                    fontSize: fontSize,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : Colors.black,
                    height: 1.35,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ] else ...[
                for (int i = 0; i < activeQueue.length; i++) ...[
                  Builder(
                    builder: (context) {
                      final item = activeQueue[i];
                      final isCompleted = item.isFinal;
                      final opacity = isCompleted ? 0.75 : 1.0;

                      return Opacity(
                        opacity: opacity,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (isDualMode) ...[
                              Text(
                                item.originalText.isEmpty ? "..." : item.originalText,
                                style: TextStyle(
                                  fontSize: fontSize * 0.75,
                                  color: isDark ? Colors.white70 : Colors.black54,
                                  height: 1.35,
                                ),
                              ),
                              const SizedBox(height: 4),
                            ],
                            Text(
                              item.translatedText.isEmpty ? "翻譯中..." : item.translatedText,
                              style: TextStyle(
                                fontSize: fontSize,
                                fontWeight: FontWeight.bold,
                                color: isDark ? Colors.white : Colors.black,
                                height: 1.35,
                              ),
                            ),
                            if (i < activeQueue.length - 1)
                              const Padding(
                                padding: EdgeInsets.symmetric(vertical: 8.0),
                                child: Divider(height: 1, color: Colors.white12),
                              ),
                          ],
                        ),
                      );
                    },
                  ),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildVolumeVisualizer(double vol, bool speaking) {
    return Row(
      children: List.generate(4, (index) {
        final barHeight = speaking ? (6 + (vol * 14 * (index + 1) / 4)) : 4.0;
        return Container(
          width: 3,
          height: barHeight,
          margin: const EdgeInsets.symmetric(horizontal: 1.5),
          decoration: BoxDecoration(
            color: speaking ? CupertinoColors.activeBlue : Colors.grey.withOpacity(0.4),
            borderRadius: BorderRadius.circular(2),
          ),
        );
      }),
    );
  }

  Widget _buildIconButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback onPressed,
  }) {
    return CupertinoButton(
      padding: EdgeInsets.zero,
      minSize: 28,
      onPressed: onPressed,
      child: Container(
        width: 26,
        height: 26,
        decoration: BoxDecoration(
          color: Colors.grey.withOpacity(0.2),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Icon(icon, size: 14, color: Colors.white70),
      ),
    );
  }
}
