import 'package:encrypt/encrypt.dart';

class CryptoHelper {
  // 32-character key for AES-256
  static final _key = Key.fromUtf8('LivriYesStripeSecretKeyEncKey32!');
  // 16-character IV
  static final _iv = IV.fromUtf8('LivriYesStripeIV');

  /// Encrypt a plain text string using AES-256-CBC
  static String encrypt(String plainText) {
    if (plainText.isEmpty) return '';
    try {
      final encrypter = Encrypter(AES(_key, mode: AESMode.cbc));
      final encrypted = encrypter.encrypt(plainText, iv: _iv);
      return encrypted.base64;
    } catch (e) {
      print('Encryption error: $e');
      return plainText; // Fallback
    }
  }

  /// Decrypt an encrypted base64 string using AES-256-CBC
  static String decrypt(String encryptedText) {
    if (encryptedText.isEmpty) return '';
    try {
      final encrypter = Encrypter(AES(_key, mode: AESMode.cbc));
      final decrypted = encrypter.decrypt(Encrypted.fromBase64(encryptedText), iv: _iv);
      return decrypted;
    } catch (e) {
      print('Decryption error: $e');
      // Return as is if already plain text or if decryption fails
      return encryptedText;
    }
  }
}
