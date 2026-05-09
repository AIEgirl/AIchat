import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class LocaleService {
  static const _keyLanguageMode = 'language_mode';

  /// Detect country from IP, return 'zh' for Chinese regions, 'en' otherwise
  static Future<String> detectLanguageFromIp() async {
    try {
      final response = await http.get(Uri.parse('http://ip-api.com/json')).timeout(const Duration(seconds: 5));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final country = data['countryCode'] as String? ?? '';
        if (['CN', 'HK', 'TW', 'MO', 'SG'].contains(country)) {
          return 'zh';
        }
      }
    } catch (e) {
      debugPrint('IP detection failed: $e');
    }
    return 'en';
  }

  /// Load saved language mode: 'auto', 'zh', 'en'
  static Future<String> getLanguageMode() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyLanguageMode) ?? 'auto';
  }

  /// Save language mode
  static Future<void> setLanguageMode(String mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyLanguageMode, mode);
  }

  /// Resolve the actual locale based on saved mode and IP detection
  static Future<Locale> resolveLocale() async {
    final mode = await getLanguageMode();
    if (mode == 'zh') return const Locale('zh');
    if (mode == 'en') return const Locale('en');
    // auto mode: detect from IP
    final lang = await detectLanguageFromIp();
    return Locale(lang);
  }
}
