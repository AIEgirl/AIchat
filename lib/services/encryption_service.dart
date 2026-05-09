import 'dart:convert';
import 'package:crypto/crypto.dart';

class EncryptionService {
  static String _deriveKey(String password, String salt) {
    final bytes = utf8.encode('$password$salt');
    final digest = sha256.convert(bytes);
    return base64Encode(digest.bytes);
  }

  static String _xorEncrypt(String text, String key) {
    final textBytes = utf8.encode(text);
    final keyBytes = utf8.encode(key);
    final result = <int>[];
    for (int i = 0; i < textBytes.length; i++) {
      result.add(textBytes[i] ^ keyBytes[i % keyBytes.length]);
    }
    return base64Encode(result);
  }

  static String encrypt(String plainText) {
    const salt = 'aichat_salt_2026';
    final key = _deriveKey('aichat_memory_key_v1', salt);
    return _xorEncrypt(plainText, key);
  }

  static String decrypt(String encryptedText) {
    const salt = 'aichat_salt_2026';
    final key = _deriveKey('aichat_memory_key_v1', salt);
    try {
      final encryptedBytes = base64Decode(encryptedText);
      final keyBytes = utf8.encode(key);
      final result = <int>[];
      for (int i = 0; i < encryptedBytes.length; i++) {
        result.add(encryptedBytes[i] ^ keyBytes[i % keyBytes.length]);
      }
      return utf8.decode(result);
    } catch (_) {
      return '';
    }
  }
}
