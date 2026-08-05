import 'dart:convert';
import 'dart:typed_data';
import 'dart:math' as math;
import 'package:encrypt/encrypt.dart' as enc;

Map<String, dynamic> computeEncryptFile(Map<String, dynamic> params) {
  final fileData = params['fileData'] as Uint8List;
  final key = params['key'] as Uint8List;
  final iv = enc.IV.fromSecureRandom(16);
  final encrypter = enc.Encrypter(
    enc.AES(enc.Key(key), mode: enc.AESMode.gcm),
  );
  final encrypted = encrypter.encryptBytes(fileData.toList(), iv: iv);
  final result = Uint8List(iv.bytes.length + encrypted.bytes.length);
  result.setRange(0, iv.bytes.length, iv.bytes);
  result.setRange(iv.bytes.length, result.length, encrypted.bytes);
  return {'encrypted': result};
}

Map<String, dynamic> computeDecryptFile(Map<String, dynamic> params) {
  final encryptedData = params['encryptedData'] as Uint8List;
  final key = params['key'] as Uint8List;
  final ivBytes = encryptedData.sublist(0, 16);
  final content = encryptedData.sublist(16);
  final iv = enc.IV(ivBytes);
  final encrypter = enc.Encrypter(
    enc.AES(enc.Key(key), mode: enc.AESMode.gcm),
  );
  final encrypted = enc.Encrypted(content);
  return {'decrypted': Uint8List.fromList(encrypter.decryptBytes(encrypted, iv: iv))};
}

class AesCrypto {
  static final math.Random _random = math.Random.secure();

  static Uint8List generateKey() {
    return Uint8List.fromList(
      List.generate(32, (_) => _random.nextInt(256)),
    );
  }

  static Map<String, String> encryptText(String plaintext, Uint8List key) {
    final iv = enc.IV.fromSecureRandom(16);
    final encrypter = enc.Encrypter(
      enc.AES(enc.Key(key), mode: enc.AESMode.gcm),
    );
    final encrypted = encrypter.encrypt(plaintext, iv: iv);
    return {
      'content': base64Encode(encrypted.bytes),
      'iv': base64Encode(iv.bytes),
    };
  }

  static String decryptText(
      String encryptedBase64, String ivBase64, Uint8List key) {
    final iv = enc.IV(base64Decode(ivBase64));
    final encrypter = enc.Encrypter(
      enc.AES(enc.Key(key), mode: enc.AESMode.gcm),
    );
    final encrypted = enc.Encrypted(base64Decode(encryptedBase64));
    return encrypter.decrypt(encrypted, iv: iv);
  }

  static Uint8List encryptFile(Uint8List fileData, Uint8List key) {
    final iv = enc.IV.fromSecureRandom(16);
    final encrypter = enc.Encrypter(
      enc.AES(enc.Key(key), mode: enc.AESMode.gcm),
    );
    final encrypted = encrypter.encryptBytes(fileData.toList(), iv: iv);
    final result = Uint8List(iv.bytes.length + encrypted.bytes.length);
    result.setRange(0, iv.bytes.length, iv.bytes);
    result.setRange(iv.bytes.length, result.length, encrypted.bytes);
    return result;
  }

  static Uint8List decryptFile(Uint8List encryptedData, Uint8List key) {
    final ivBytes = encryptedData.sublist(0, 16);
    final content = encryptedData.sublist(16);

    final iv = enc.IV(ivBytes);
    final encrypter = enc.Encrypter(
      enc.AES(enc.Key(key), mode: enc.AESMode.gcm),
    );
    final encrypted = enc.Encrypted(content);
    return Uint8List.fromList(encrypter.decryptBytes(encrypted, iv: iv));
  }

  static Uint8List encryptKey(Uint8List keyToEncrypt, Uint8List groupKey) {
    final iv = enc.IV.fromSecureRandom(16);
    final encrypter = enc.Encrypter(
      enc.AES(enc.Key(groupKey), mode: enc.AESMode.gcm),
    );
    final encrypted = encrypter.encryptBytes(keyToEncrypt.toList(), iv: iv);
    final result = Uint8List(iv.bytes.length + encrypted.bytes.length);
    result.setRange(0, iv.bytes.length, iv.bytes);
    result.setRange(iv.bytes.length, result.length, encrypted.bytes);
    return result;
  }

  static Uint8List decryptKey(Uint8List encryptedKeyData, Uint8List groupKey) {
    final ivBytes = encryptedKeyData.sublist(0, 16);
    final content = encryptedKeyData.sublist(16);

    final iv = enc.IV(ivBytes);
    final encrypter = enc.Encrypter(
      enc.AES(enc.Key(groupKey), mode: enc.AESMode.gcm),
    );
    final encrypted = enc.Encrypted(content);
    return Uint8List.fromList(encrypter.decryptBytes(encrypted, iv: iv));
  }
}
