import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class TranslationService {
  final Map<String, String> _cache = {};
  String? geminiApiKey;

  // Language code normalization for Google Translate
  String _normalizeGoogleLang(String code) {
    final lower = code.toLowerCase();
    if (lower.startsWith('zh')) {
      if (lower.contains('cn') || lower.contains('hans') || lower.contains('simple')) {
        return 'zh-CN';
      }
      return 'zh-TW';
    }
    if (lower.startsWith('en')) return 'en';
    if (lower.startsWith('ja')) return 'ja';
    if (lower.startsWith('ko')) return 'ko';
    if (lower.startsWith('fr')) return 'fr';
    if (lower.startsWith('de')) return 'de';
    if (lower.startsWith('es')) return 'es';
    return lower.split('_')[0].split('-')[0];
  }

  Future<String> translate(
    String text, {
    String sourceLang = "auto",
    String targetLang = "zh-TW",
  }) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return "";

    final cacheKey = "$sourceLang->$targetLang:$trimmed";
    if (_cache.containsKey(cacheKey)) {
      return _cache[cacheKey]!;
    }

    // 1. Try Gemini API if API key is provided
    if (geminiApiKey != null && geminiApiKey!.trim().isNotEmpty) {
      try {
        final geminiResult = await _translateWithGemini(trimmed, targetLang);
        if (geminiResult != null && geminiResult.isNotEmpty) {
          _cache[cacheKey] = geminiResult;
          return geminiResult;
        }
      } catch (e) {
        debugPrint("Gemini translation fallback error: $e");
      }
    }

    // 2. High-speed Direct Google Translate (No API key required)
    try {
      final googleResult = await _translateWithGoogle(trimmed, sourceLang, targetLang);
      if (googleResult != null && googleResult.isNotEmpty) {
        _cache[cacheKey] = googleResult;
        return googleResult;
      }
    } catch (e) {
      debugPrint("Google translation error: $e");
    }

    return trimmed;
  }

  Future<String?> _translateWithGoogle(String text, String src, String tgt) async {
    final sl = src == "auto" ? "auto" : _normalizeGoogleLang(src);
    final tl = _normalizeGoogleLang(tgt);

    // Try primary clients: 'gtx' and 'dict-chrome-ex'
    final clients = ['gtx', 'dict-chrome-ex'];
    for (final client in clients) {
      try {
        final url = Uri.parse(
          'https://translate.googleapis.com/translate_a/single?client=$client&sl=$sl&tl=$tl&dt=t&q=${Uri.encodeComponent(text)}',
        );

        final response = await http.get(
          url,
          headers: {
            'User-Agent':
                'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1',
          },
        ).timeout(const Duration(seconds: 4));

        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          if (data is List && data.isNotEmpty && data[0] is List) {
            final buffer = StringBuffer();
            for (final item in data[0]) {
              if (item is List && item.isNotEmpty && item[0] != null) {
                buffer.write(item[0].toString());
              }
            }
            final result = buffer.toString().trim();
            if (result.isNotEmpty) {
              return result;
            }
          }
        }
      } catch (e) {
        debugPrint("Google client $client error: $e");
      }
    }
    return null;
  }

  Future<String?> _translateWithGemini(String text, String targetLang) async {
    final targetName = targetLang.toLowerCase().contains("zh")
        ? "Traditional Chinese (台灣繁體中文)"
        : targetLang;

    final url = Uri.parse(
      'https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash:generateContent?key=${geminiApiKey!.trim()}',
    );

    final payload = jsonEncode({
      "contents": [
        {
          "parts": [
            {
              "text":
                  "You are a professional conference translator. Translate the following speech into $targetName accurately and naturally. Output ONLY the translated text without explanations:\n\n$text"
            }
          ]
        }
      ],
      "generationConfig": {
        "temperature": 0.2,
        "maxOutputTokens": 256,
      }
    });

    final response = await http.post(
      url,
      headers: {'Content-Type': 'application/json'},
      body: payload,
    ).timeout(const Duration(seconds: 5));

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      final candidates = data['candidates'] as List?;
      if (candidates != null && candidates.isNotEmpty) {
        final content = candidates[0]['content'];
        final parts = content?['parts'] as List?;
        if (parts != null && parts.isNotEmpty) {
          return parts[0]['text']?.toString().trim();
        }
      }
    }
    return null;
  }

  void clearCache() {
    _cache.clear();
  }
}
