import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';

class ApiException implements Exception {
  final String message;
  final int? statusCode;
  final String? responseBody;
  ApiException(this.message, {this.statusCode, this.responseBody});
  @override
  String toString() => message;
}

class ApiService {
  String _baseUrl;
  String _apiKey;
  String _model;

  ApiService({
    required String baseUrl,
    required String apiKey,
    required String model,
  })  : _baseUrl = baseUrl,
        _apiKey = apiKey,
        _model = model;

  void updateConfig({String? baseUrl, String? apiKey, String? model}) {
    if (baseUrl != null) _baseUrl = baseUrl;
    if (apiKey != null) _apiKey = apiKey;
    if (model != null) _model = model;
  }

  static ApiService fromConfig({
    required String model,
    required String apiKey,
    required String baseUrl,
  }) {
    return ApiService(baseUrl: baseUrl, apiKey: apiKey, model: model);
  }

  String get _maskedKey {
    if (_apiKey.length <= 8) return '***';
    return '${_apiKey.substring(0, 4)}...${_apiKey.substring(_apiKey.length - 4)}';
  }

  Future<Map<String, dynamic>> chatCompletion({
    required List<Map<String, dynamic>> messages,
    required List<Map<String, dynamic>> tools,
    String toolChoice = 'auto',
  }) async {
    final url = _baseUrl.endsWith('/v1')
        ? '$_baseUrl/chat/completions'
        : '$_baseUrl/v1/chat/completions';

    debugPrint('══════════════════════════════════════');
    debugPrint('API CALL');
    debugPrint('  URL: $url');
    debugPrint('  Model: $_model');
    debugPrint('  Key: $_maskedKey');

    final bodyJson = <String, dynamic>{
      'model': _model,
      'messages': messages,
      'tools': tools,
      'tool_choice': 'required',
    };

    // DeepSeek 模型强制关闭思考模式
    if (_model.contains('deepseek')) {
      bodyJson['thinking'] = {'type': 'disabled'};
    }

    debugPrint('  Body has tools: ${bodyJson.containsKey('tools')}');
    debugPrint('  Tools count: ${(bodyJson['tools'] as List?)?.length ?? 0}');
    debugPrint('  tool_choice: ${bodyJson['tool_choice'] ?? 'none'}');
    debugPrint('  thinking: ${bodyJson['thinking'] ?? 'none'}');
    debugPrint('  Messages count: ${messages.length}');
    debugPrint('  Last msg role: ${messages.isNotEmpty ? messages.last['role'] : 'N/A'}');
    debugPrint('══════════════════════════════════════');

    var body = jsonEncode(bodyJson);

    try {
      final response = await http
          .post(
            Uri.parse(url),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $_apiKey',
            },
            body: body,
          )
          .timeout(const Duration(seconds: 60));

      debugPrint('  HTTP ${response.statusCode}');

      return _handleResponse(response);
    } on ApiException catch (e) {
      // tool_choice / thinking 不被支持时降级重试
      var retried = false;
      if (bodyJson.containsKey('tool_choice') && bodyJson['tool_choice'] == 'required' &&
          (e.message.contains('tool_choice') || e.message.contains('does not support'))) {
        bodyJson.remove('tool_choice');
        retried = true;
      }
      if (bodyJson.containsKey('thinking') &&
          (e.message.contains('thinking') || e.message.contains('unexpected parameter'))) {
        bodyJson.remove('thinking');
        retried = true;
      }
      if (retried) {
        debugPrint('  ⚠ Parameter rejected → retrying with: ${bodyJson.keys.where((k) => k != 'messages' && k != 'tools')}');
        body = jsonEncode(bodyJson);
        final retryResponse = await http
            .post(
              Uri.parse(url),
              headers: {
                'Content-Type': 'application/json',
                'Authorization': 'Bearer $_apiKey',
              },
              body: body,
            )
            .timeout(const Duration(seconds: 60));
        return _handleResponse(retryResponse);
      }
      rethrow;
    } on SocketException catch (e) {
      debugPrint('  ERROR: SocketException - $e');
      throw ApiException('网络连接失败，请检查 Base URL 是否可达', responseBody: e.toString());
    } on TimeoutException catch (e) {
      debugPrint('  ERROR: TimeoutException - $e');
      throw ApiException('请求超时，请检查网络或服务端状态', responseBody: e.toString());
    } on FormatException catch (e) {
      debugPrint('  ERROR: FormatException - $e');
      throw ApiException('响应格式异常，服务端返回了非 JSON 数据', responseBody: e.toString());
    } on ApiException {
      rethrow;
    } catch (e) {
      debugPrint('  ERROR: unknown - $e');
      throw ApiException('请求失败: $e');
    }
  }

  Map<String, dynamic> _handleResponse(http.Response response) {
    final statusCode = response.statusCode;
    String? bodyText;
    Map<String, dynamic>? bodyJson;

    try {
      bodyText = response.body;
      bodyJson = jsonDecode(bodyText) as Map<String, dynamic>;
    } catch (_) {
      bodyText = response.body;
    }

    switch (statusCode) {
      case 200:
        if (bodyJson == null) {
          throw ApiException('服务端返回了空响应', statusCode: 200, responseBody: bodyText);
        }
        final error = bodyJson['error'] as Map<String, dynamic>?;
        if (error != null) {
          final errMsg = error['message'] as String? ?? error.toString();
          throw ApiException(errMsg, statusCode: 200, responseBody: bodyText);
        }
        final choices = bodyJson['choices'] as List?;
        final firstChoice = choices?.first as Map<String, dynamic>?;
        final msg = firstChoice?['message'] as Map<String, dynamic>?;
        debugPrint('  Response choices: ${choices?.length ?? 0}');
        debugPrint('  Has tool_calls: ${msg?['tool_calls'] != null}');
        debugPrint('  Has content: ${msg?['content'] != null}');
        debugPrint('  Content length: ${(msg?['content'] as String?)?.length ?? 0}');
        debugPrint('  Finish reason: ${firstChoice?['finish_reason']}');
        return bodyJson;

      case 401:
        throw ApiException('API Key 无效或已过期', statusCode: 401, responseBody: bodyText);

      case 403:
        throw ApiException('无权访问，请检查 API Key 权限', statusCode: 403, responseBody: bodyText);

      case 404:
        final hint = bodyText != null ? ' (响应: ${bodyText.length > 100 ? bodyText.substring(0, 100) : bodyText})' : '';
        throw ApiException('Base URL 不正确或模型 $_model 不存在$hint', statusCode: 404, responseBody: bodyText);

      case 429:
        throw ApiException('请求过于频繁，请稍后重试', statusCode: 429, responseBody: bodyText);

      case 400:
        final msg = bodyJson?['error']?['message'] as String? ?? '请求参数有误';
        throw ApiException(msg, statusCode: 400, responseBody: bodyText);

      default:
        if (statusCode >= 500) {
          throw ApiException('服务端错误 ($statusCode)，请稍后重试', statusCode: statusCode, responseBody: bodyText);
        }
        throw ApiException('HTTP $statusCode: ${bodyText.substring(0, _min(200, bodyText.length))}', statusCode: statusCode, responseBody: bodyText);
    }
  }

  int _min(int a, int b) => a < b ? a : b;

  static List<Map<String, dynamic>> parseToolCalls(Map<String, dynamic> response) {
    final choices = response['choices'] as List<dynamic>?;
    if (choices == null || choices.isEmpty) return [];
    final message = choices[0]['message'] as Map<String, dynamic>?;
    if (message == null) return [];
    final toolCalls = message['tool_calls'] as List<dynamic>?;
    if (toolCalls == null || toolCalls.isEmpty) return [];
    return toolCalls.map((tc) {
      final call = tc as Map<String, dynamic>;
      return {
        'id': call['id'] as String? ?? '',
        'name': call['function']?['name'] as String? ?? '',
        'arguments': call['function']?['arguments'] is String
            ? jsonDecode(call['function']['arguments'] as String)
            : (call['function']?['arguments'] ?? {}),
      };
    }).toList();
  }

  static String? parseContent(Map<String, dynamic> response) {
    final choices = response['choices'] as List<dynamic>?;
    if (choices == null || choices.isEmpty) return null;
    final message = choices[0]['message'] as Map<String, dynamic>?;
    return message?['content'] as String?;
  }

  static String? parseFinishReason(Map<String, dynamic> response) {
    final choices = response['choices'] as List<dynamic>?;
    if (choices == null || choices.isEmpty) return null;
    return choices[0]['finish_reason'] as String?;
  }

  static List<Map<String, dynamic>> getToolDefinitions() {
    return [
      {
        'type': 'function',
        'function': {
          'name': 'remember',
          'description': '记住一条当前状态或过去的事件。可用于创建/更新长期记忆，或向基础记忆追加事件。',
          'parameters': {
            'type': 'object',
            'properties': {
              'memory_type': {'type': 'string', 'enum': ['long_term', 'base'], 'description': 'long_term 表示更新当前有效信息，base 表示追加历史事件。'},
              'action': {'type': 'string', 'enum': ['create', 'update'], 'description': '创建新条目或更新原有条目。更新时必须提供 target_id。'},
              'target_id': {'type': 'string', 'description': '当 action 为 update 时，要更新的条目序号（如 L003）。'},
              'field': {'type': 'string', 'enum': ['time', 'location', 'current_events', 'characters', 'relationships', 'goals', 'thoughts', 'status', 'to_do'], 'description': '长期记忆的字段名。base 类型无需此参数。'},
              'content': {'type': 'string', 'description': '要记住的具体内容。如果是更新，提供完整的新内容。'},
            },
            'required': ['memory_type', 'action'],
          },
        },
      },
      {
        'type': 'function',
        'function': {
          'name': 'forget',
          'description': '删除不再有用的长期记忆条目或基础记忆中的事件条目。设定条目不可删除。',
          'parameters': {
            'type': 'object',
            'properties': {
              'target_ids': {'type': 'array', 'items': {'type': 'string'}, 'description': '要删除的条目序号列表，如 ["L003", "B007"]。'},
            },
            'required': ['target_ids'],
          },
        },
      },
      {
        'type': 'function',
        'function': {
          'name': 'chat',
          'description': '向用户发送自然语言回复。在所有记忆操作完成后，用它来最终回复。',
          'parameters': {
            'type': 'object',
            'properties': {
              'message': {'type': 'string', 'description': '回复给用户的文本。'},
            },
            'required': ['message'],
          },
        },
      },
      {
        'type': 'function',
        'function': {
          'name': 'plan',
          'description': '安排一条未来发送的消息。例如提醒或主动关心。',
          'parameters': {
            'type': 'object',
            'properties': {
              'send_time': {'type': 'string', 'description': "发送时间：相对时间如 '30m' 表示30分钟后，'2h' 表示2小时后，或 ISO 8601 具体时间。"},
              'message': {'type': 'string', 'description': '到时间后要发送的消息内容。'},
            },
            'required': ['send_time', 'message'],
          },
        },
      },
    ];
  }
}
