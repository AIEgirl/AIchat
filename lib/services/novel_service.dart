import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../services/api_service.dart';
import '../services/database_service.dart';

class NovelService {
  static const defaultStyles = ['默认', '古风', '现代', '悬疑', '科幻', '言情'];
  static const defaultWordCount = 500;

  static Future<String> generate({
    required String content,
    required String style,
    required int wordCount,
    required String customPrompt,
    required String baseUrl,
    required String apiKey,
    required String model,
  }) async {
    final prompt = _buildPrompt(content, style, wordCount, customPrompt);
    final apiService = ApiService.fromConfig(baseUrl: baseUrl, apiKey: apiKey, model: model);

    final messages = [
      {'role': 'system', 'content': prompt},
    ];

    try {
      final result = await apiService.chatCompletion(
        messages: messages,
        tools: const [],
      );
      return ApiService.parseContent(result) ?? '';
    } catch (e) {
      debugPrint('[NovelService] generate error: $e');
      return '';
    }
  }

  static String _buildPrompt(String content, String style, int wordCount, String custom) {
    final base = '将以下聊天记录改写为${style}风格的叙事小说，约${wordCount}字。保留原意与情感，增加场景描写、心理活动和文学性表达。';
    final customPart = custom.isNotEmpty ? '\n额外要求：$custom' : '';
    return '$base$customPart\n\n---\n$content';
  }

  static Future<int> save({
    required String style,
    required int wordCount,
    required String prompt,
    required String result,
  }) async {
    return await DatabaseService.insertNovelGeneration(
      style: style,
      wordCount: wordCount,
      prompt: prompt,
      result: result,
    );
  }

  static Future<List<Map<String, dynamic>>> getAll() async {
    return await DatabaseService.getNovelGenerations();
  }

  static Future<void> delete(int id) async {
    await DatabaseService.deleteNovelGeneration(id);
  }
}
