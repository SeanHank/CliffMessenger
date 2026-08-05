import 'dart:convert';
import 'dart:io';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:crypto/crypto.dart';

class DbKeyManager {
  static const String _salt = 'd1fc44e698f906832eb99352e43cdc6984d08bf51de5d826cb0a88bee2684a07183e0e93d70bfe3c1efc4a0550cea868759ed972fc48dc4d65a92067e5634f2c';

  static Future<String> getEncryptionKey() async {
    final deviceInfo = DeviceInfoPlugin();
    String deviceId;

    if (Platform.isAndroid) {
      final androidInfo = await deviceInfo.androidInfo;
      deviceId = androidInfo.id; // ANDROID_ID
    } else if (Platform.isIOS) {
      final iosInfo = await deviceInfo.iosInfo;
      deviceId = iosInfo.identifierForVendor!;
    } else if (Platform.isMacOS) {
      final macosInfo = await deviceInfo.macOsInfo;
      // 优先使用 systemGUID，否则组合 computerName + hostName
      deviceId = macosInfo.systemGUID ?? '${macosInfo.computerName}${macosInfo.hostName}';
    } else if (Platform.isWindows) {
      final windowsInfo = await deviceInfo.windowsInfo;
      deviceId = windowsInfo.computerName;
    } else if (Platform.isLinux) {
      final linuxInfo = await deviceInfo.linuxInfo;
      deviceId = linuxInfo.machineId ?? '${linuxInfo.name}${linuxInfo.id}';
    } else {
      deviceId = 'default_fallback_device';
    }

    final keySource = '$deviceId$_salt';
    final keyBytes = sha256.convert(utf8.encode(keySource)).bytes;
    return base64Encode(keyBytes); // 44字符的base64字符串
  }
}