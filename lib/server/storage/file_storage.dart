import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

class ServerFileStorage {
  static const _dirName = 'cliff_server_files';

  static Future<Directory> _getDir() async {
    final appDir = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(appDir.path, _dirName));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  static Future<String> saveFile(String fileId, List<int> data) async {
    final dir = await _getDir();
    final file = File(p.join(dir.path, fileId));
    await file.writeAsBytes(data);
    return file.path;
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

  static Future<void> deleteFile(String fileId) async {
    final dir = await _getDir();
    final file = File(p.join(dir.path, fileId));
    if (await file.exists()) {
      await file.delete();
    }
  }
}
