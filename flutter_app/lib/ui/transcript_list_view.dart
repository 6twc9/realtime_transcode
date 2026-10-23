import 'dart:io';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../models/transcript_segment.dart';

class TranscriptListView extends StatefulWidget {
  final List<TranscriptSegment> history;
  final VoidCallback onClearHistory;

  const TranscriptListView({
    super.key,
    required this.history,
    required this.onClearHistory,
  });

  @override
  State<TranscriptListView> createState() => _TranscriptListViewState();
}

class _TranscriptListViewState extends State<TranscriptListView> {
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();
  bool _autoScroll = true;
  String _searchQuery = "";

  @override
  void didUpdateWidget(covariant TranscriptListView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_autoScroll && widget.history.length > oldWidget.history.length) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients) {
          _scrollController.animateTo(
            _scrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOut,
          );
        }
      });
    }
  }

  Future<void> _exportMarkdown() async {
    if (widget.history.isEmpty) return;

    final buffer = StringBuffer();
    buffer.writeln("# 會議逐字稿與即時翻譯記錄");
    buffer.writeln("- 匯出時間: ${DateTime.now()}");
    buffer.writeln("- 總紀錄句數: ${widget.history.length}\n");
    buffer.writeln("---\n");

    for (final item in widget.history) {
      buffer.writeln("### [${item.formattedTime}]");
      buffer.writeln("**原文**: ${item.originalText}\n");
      buffer.writeln("**翻譯**: ${item.translatedText}\n");
    }

    try {
      final tempDir = await getTemporaryDirectory();
      final file = File('${tempDir.path}/meeting_transcript_${DateTime.now().millisecondsSinceEpoch}.md');
      await file.writeAsString(buffer.toString());

      await Share.shareXFiles(
        [XFile(file.path)],
        subject: "會議逐字稿記錄",
      );
    } catch (e) {
      debugPrint("Export failed: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final filteredList = widget.history.where((s) {
      if (_searchQuery.isEmpty) return true;
      final q = _searchQuery.toLowerCase();
      return s.originalText.toLowerCase().contains(q) ||
          s.translatedText.toLowerCase().contains(q);
    }).toList();

    return Column(
      children: [
        // Action toolbar
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              Expanded(
                child: CupertinoSearchTextField(
                  controller: _searchController,
                  placeholder: "搜尋對話內容...",
                  onChanged: (val) {
                    setState(() {
                      _searchQuery = val;
                    });
                  },
                ),
              ),
              const SizedBox(width: 8),
              CupertinoButton(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                minSize: 32,
                color: isDark ? Colors.white12 : Colors.black12,
                borderRadius: BorderRadius.circular(8),
                onPressed: () {
                  setState(() {
                    _autoScroll = !_autoScroll;
                  });
                },
                child: Row(
                  children: [
                    Icon(
                      _autoScroll ? CupertinoIcons.arrow_down_circle_fill : CupertinoIcons.arrow_down_circle,
                      size: 14,
                      color: _autoScroll ? CupertinoColors.activeBlue : null,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      "自動捲動",
                      style: TextStyle(
                        fontSize: 12,
                        color: _autoScroll ? CupertinoColors.activeBlue : (isDark ? Colors.white70 : Colors.black87),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              CupertinoButton(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                minSize: 32,
                color: CupertinoColors.activeBlue,
                borderRadius: BorderRadius.circular(8),
                onPressed: widget.history.isEmpty ? null : _exportMarkdown,
                child: const Text("匯出 .md", style: TextStyle(fontSize: 12, color: Colors.white)),
              ),
              const SizedBox(width: 8),
              CupertinoButton(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                minSize: 32,
                color: CupertinoColors.systemRed.withOpacity(0.15),
                borderRadius: BorderRadius.circular(8),
                onPressed: widget.history.isEmpty ? null : widget.onClearHistory,
                child: const Text("清空", style: TextStyle(fontSize: 12, color: CupertinoColors.systemRed)),
              ),
            ],
          ),
        ),

        // List
        Expanded(
          child: filteredList.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        CupertinoIcons.chat_bubble_2,
                        size: 48,
                        color: isDark ? Colors.white24 : Colors.black26,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        "尚無任何會議對話紀錄",
                        style: TextStyle(
                          color: isDark ? Colors.white54 : Colors.black45,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.all(16),
                  itemCount: filteredList.length,
                  itemBuilder: (context, index) {
                    final item = filteredList[index];
                    return _buildTranscriptItem(item, isDark);
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildTranscriptItem(TranscriptSegment item, bool isDark) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? Colors.white10 : Colors.black.withOpacity(0.06),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                "[${item.formattedTime}]",
                style: const TextStyle(
                  fontSize: 11,
                  fontFamily: "monospace",
                  color: Colors.grey,
                ),
              ),
              CupertinoButton(
                padding: EdgeInsets.zero,
                minSize: 20,
                onPressed: () {
                  Clipboard.setData(ClipboardData(
                    text: "${item.originalText}\n${item.translatedText}",
                  ));
                },
                child: const Icon(CupertinoIcons.doc_on_doc, size: 14, color: Colors.grey),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            item.originalText,
            style: TextStyle(
              fontSize: 13,
              color: isDark ? Colors.white70 : Colors.black54,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            item.translatedText.isEmpty ? "翻譯中..." : item.translatedText,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: isDark ? Colors.white : Colors.black,
            ),
          ),
        ],
      ),
    );
  }
}
