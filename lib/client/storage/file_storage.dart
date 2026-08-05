import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

class ClientFileStorage {
  static const _dirName = 'cliff_client_files';
  static String? _currentUserId;

  static void setCurrentUser(String userId) {
    _currentUserId = userId;
  }

  // 获取当前用户 ID
  static String? get currentUserId => _currentUserId;

  static Future<Directory> _getDir() async {
    final userId = _currentUserId ?? 'default';
    final appDir = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(appDir.path, _dirName, userId));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  // static Future<String> saveFile(String fileId, List<int> data) async {
  //   final dir = await _getDir();
  //   final file = File(p.join(dir.path, fileId));
  //   await file.writeAsBytes(data);
  //   return file.path;
  // }
  static Future<String> saveFile(String fileId, List<int> data, {String? fileName}) async {
    final dir = await _getDir();
    final extension = fileName != null ? p.extension(fileName) : '';
    final finalFileName = extension.isNotEmpty ? '$fileId$extension' : fileId;
    final file = File(p.join(dir.path, finalFileName));
    await file.writeAsBytes(data);
    return file.path;
  }

  // static Future<String?> getFilePath(String fileId) async {
  //   final dir = await _getDir();
  //   final file = File(p.join(dir.path, fileId));
  //   if (await file.exists()) {
  //     return file.path;
  //   }
  //   return null;
  // }
  static Future<String?> getFilePath(String fileId) async {
    final dir = await _getDir();

    // 先尝试直接查找（无扩展名，兼容旧文件）
    final file = File(p.join(dir.path, fileId));
    if (await file.exists()) {
      return file.path;
    }

    // 遍历目录查找带扩展名的文件
    if (await dir.exists()) {
      final files = await dir.list().toList();
      for (final entity in files) {
        if (entity is File && p.basenameWithoutExtension(entity.path) == fileId) {
          return entity.path;
        }
      }
    }

    return null;
  }

  static Future<List<int>?> getFile(String fileId) async {
    final dir = await _getDir();
    final file = File(p.join(dir.path, fileId));
    if (await file.exists()) {
      return await file.readAsBytes();
    }
    return null;
  }

  static Future<bool> fileExists(String fileId) async {
    final dir = await _getDir();
    return File(p.join(dir.path, fileId)).exists();
  }

  // static Future<void> deleteFile(String fileId) async {
  //   final dir = await _getDir();
  //   final file = File(p.join(dir.path, fileId));
  //   if (await file.exists()) {
  //     await file.delete();
  //   }
  // }
  static Future<void> deleteFile(String fileId) async {
    final dir = await _getDir();

    // 尝试删除无扩展名版本
    final file = File(p.join(dir.path, fileId));
    if (await file.exists()) {
      await file.delete();
      return;
    }

    // 尝试删除带扩展名版本
    if (await dir.exists()) {
      final files = await dir.list().toList();
      for (final entity in files) {
        if (entity is File && p.basenameWithoutExtension(entity.path) == fileId) {
          await entity.delete();
          return;
        }
      }
    }
  }

  static Future<void> clearAll() async {
    final dir = await _getDir();
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
  }
}
