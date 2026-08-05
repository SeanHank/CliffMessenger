import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:encrypt/encrypt.dart' as enc;
import 'dart:typed_data';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:crypto/crypto.dart';
import 'rsa_crypto.dart';

class KeyManager {
  static const _keyDir = 'cliff_keys';
  static const _privateKeyFile = 'private_key.enc';
  static const _publicKeyFile = 'public_key.pem';
  static String? _currentUserId;

  static final math.Random _secureRandom = math.Random.secure();

  static void setCurrentUser(String? userId) {
    _currentUserId = userId;
  }

  // static Future<Directory> _getKeyDir() async {
  //   final appDir = await getApplicationDocumentsDirectory();
  //   final keyDir = Directory(p.join(appDir.path, _keyDir));
  //   if (!await keyDir.exists()) {
  //     await keyDir.create(recursive: true);
  //   }
  //   return keyDir;
  // }
  static Future<Directory> _getKeyDir() async {
    final appDir = await getApplicationDocumentsDirectory();
    final userId = _currentUserId ?? 'default';
    final keyDir = Directory(p.join(appDir.path, _keyDir, userId));
    if (!await keyDir.exists()) {
      await keyDir.create(recursive: true);
    }
    return keyDir;
  }

  // static Future<Map<String, dynamic>> generateAndStoreKeys(String password) async {
  //   final keyPair = RsaCrypto.generateKeyPair();
  //   final publicKeyPem = RsaCrypto.publicKeyToPem(keyPair.publicKey);
  //   final privateKeyPem = RsaCrypto.privateKeyToPem(keyPair.privateKey);
  //
  //   final dir = await _getKeyDir();
  //
  //   await File(p.join(dir.path, _publicKeyFile)).writeAsString(publicKeyPem);
  //
  //   final encryptedPrivateKey = _encryptPrivateKey(privateKeyPem, password);
  //   await File(p.join(dir.path, _privateKeyFile))
  //       .writeAsBytes(encryptedPrivateKey);
  //
  //   return {
  //     'publicKey': publicKeyPem,
  //     'privateKeyPem': privateKeyPem,
  //   };
  // }
  static Map<String, String> generateKeys() {
    final keyPair = RsaCrypto.generateKeyPair();
    final publicKeyPem = RsaCrypto.publicKeyToPem(keyPair.publicKey);
    final privateKeyPem = RsaCrypto.privateKeyToPem(keyPair.privateKey);

    return {
      'publicKey': publicKeyPem,
      'privateKeyPem': privateKeyPem,
    };
  }

// 新增：存储密钥到当前用户目录
  static Future<void> storeKeys(String password, String publicKeyPem, String privateKeyPem) async {
    final dir = await _getKeyDir();

    await File(p.join(dir.path, _publicKeyFile)).writeAsString(publicKeyPem);

    final encryptedPrivateKey = _encryptPrivateKey(privateKeyPem, password);
    await File(p.join(dir.path, _privateKeyFile)).writeAsBytes(encryptedPrivateKey);
  }

  static Future<String?> loadPublicKey() async {
    final dir = await _getKeyDir();
    final file = File(p.join(dir.path, _publicKeyFile));
    if (await file.exists()) {
      return await file.readAsString();
    }
    return null;
  }

  static Future<String?> loadPrivateKey(String password) async {
    final dir = await _getKeyDir();
    final file = File(p.join(dir.path, _privateKeyFile));
    if (await file.exists()) {
      final encryptedData = await file.readAsBytes();
      return _decryptPrivateKey(encryptedData, password);
    }
    return null;
  }

  static Future<bool> hasKeys() async {
    final dir = await _getKeyDir();
    return File(p.join(dir.path, _publicKeyFile)).exists();
  }

  static Future<void> deleteKeys() async {
    final dir = await _getKeyDir();
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
  }

  // static Uint8List _encryptPrivateKey(String pem, String password) {
  //   final keyBytes = utf8.encode(pem);
  //   final salt = Uint8List.fromList(List.generate(16, (i) => i));
  //   final derivedKey = _deriveKey(password, salt);
  //
  //   final result = Uint8List(salt.length + keyBytes.length);
  //   result.setRange(0, salt.length, salt);
  //   for (int i = 0; i < keyBytes.length; i++) {
  //     result[salt.length + i] = keyBytes[i] ^ derivedKey[i % derivedKey.length];
  //   }
  //   return result;
  // }
  //
  // static String _decryptPrivateKey(Uint8List data, String password) {
  //   final salt = data.sublist(0, 16);
  //   final encrypted = data.sublist(16);
  //   final derivedKey = _deriveKey(password, salt);
  //
  //   final decrypted = Uint8List(encrypted.length);
  //   for (int i = 0; i < encrypted.length; i++) {
  //     decrypted[i] = encrypted[i] ^ derivedKey[i % derivedKey.length];
  //   }
  //   return utf8.decode(decrypted);
  // }
  //
  // static Uint8List _deriveKey(String password, Uint8List salt) {
  //   final passwordBytes = utf8.encode(password);
  //   var combined = <int>[...passwordBytes, ...salt];
  //   for (int round = 0; round < 100; round++) {
  //     final hash = sha256.convert(combined);
  //     combined = hash.bytes;
  //   }
  //   return Uint8List.fromList(combined);
  // }
  // 修改：使用 AES-GCM 加密私钥
  static Uint8List _encryptPrivateKey(String pem, String password) {
    // 1. 生成随机 salt（16 字节）
    final salt = _generateRandomBytes(16);

    // 2. 生成随机 IV（12 字节，GCM 推荐长度）
    final iv = _generateRandomBytes(12);

    // 3. 从密码派生密钥
    final derivedKey = _deriveKey(password, salt);

    // 4. AES-GCM 加密
    final encrypter = enc.Encrypter(
      enc.AES(enc.Key(derivedKey), mode: enc.AESMode.gcm),
    );
    final encrypted = encrypter.encrypt(pem, iv: enc.IV(iv));

    // 5. 组合结果：salt(16) + iv(12) + encryptedContent（已包含 auth tag）
    final result = Uint8List(salt.length + iv.length + encrypted.bytes.length);
    result.setRange(0, salt.length, salt);
    result.setRange(salt.length, salt.length + iv.length, iv);
    result.setRange(salt.length + iv.length, result.length, encrypted.bytes);

    return result;
  }

// 修改：使用 AES-GCM 解密私钥
  static String _decryptPrivateKey(Uint8List data, String password) {
    // 1. 提取各部分
    final salt = data.sublist(0, 16);
    final iv = data.sublist(16, 28);
    final encryptedContent = data.sublist(28);  // 包含密文 + auth tag

    // 2. 从密码派生密钥
    final derivedKey = _deriveKey(password, salt);

    // 3. AES-GCM 解密
    final encrypter = enc.Encrypter(
      enc.AES(enc.Key(derivedKey), mode: enc.AESMode.gcm),
    );
    final encrypted = enc.Encrypted(Uint8List.fromList(encryptedContent));
    final decrypted = encrypter.decrypt(encrypted, iv: enc.IV(iv));

    return decrypted;
  }

// 新增：生成随机字节
  static Uint8List _generateRandomBytes(int length) {
    return Uint8List.fromList(
      List.generate(length, (_) => _secureRandom.nextInt(256)),
    );
  }

// 修改：使用更安全的密钥派生（保持 SHA-256 但增加轮数）
  static Uint8List _deriveKey(String password, Uint8List salt) {
    final passwordBytes = utf8.encode(password);
    var combined = <int>[...passwordBytes, ...salt];
    for (int round = 0; round < 10000; round++) {  // 增加到 10000 轮
      final hash = sha256.convert(combined);
      combined = hash.bytes;
    }
    return Uint8List.fromList(combined);
  }
}
