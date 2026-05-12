import 'dart:convert';
import 'package:http/http.dart' as http;

class ModelService {
  static Future<List<String>> fetchModels({
    required String baseUrl,
    required String apiKey,
  }) async {
    final url = baseUrl.contains('deepseek')
        ? '$baseUrl/models'
        : baseUrl.endsWith('/v1')
            ? '$baseUrl/models'
            : '$baseUrl/v1/models';

    final response = await http.get(
      Uri.parse(url),
      headers: {
        'Authorization': 'Bearer $apiKey',
      },
    );

    if (response.statusCode == 200) {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final data = body['data'] as List<dynamic>;
      return data
          .map((e) => (e as Map<String, dynamic>)['id'] as String)
          .where((id) =>
              !id.contains('instruct') &&
              !id.contains('embedding') &&
              !id.contains('reasoner') &&
              !id.contains('thinking') &&
              !id.contains('r1'))
          .toList();
    }
    throw Exception('Failed to fetch models: ${response.statusCode}');
  }
}
