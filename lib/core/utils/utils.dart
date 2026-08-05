import 'dart:io';
import 'dart:typed_data';
import 'package:uuid/uuid.dart';
import '../constants/app_strings.dart';

class UuidGenerator {
  static const _uuid = Uuid();

  static String generate() => _uuid.v4();

  static String generateInviteCode() => _uuid.v4();
}

class FileUtils {
  static String formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes ${AppStrings.bytes}';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} ${AppStrings.kb}';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} ${AppStrings.mb}';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} ${AppStrings.gb}';
  }

  static String getMimeType(String filePath) {
    final ext = filePath.split('.').last.toLowerCase();
    const mimeMap = {
      'jpg': 'image/jpeg',
      'jpeg': 'image/jpeg',
      'png': 'image/png',
      'gif': 'image/gif',
      'webp': 'image/webp',
      'pdf': 'application/pdf',
      'txt': 'text/plain',
      'doc': 'application/msword',
      'docx': 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
      'xls': 'application/vnd.ms-excel',
      'xlsx': 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      'zip': 'application/zip',
      'rar': 'application/x-rar-compressed',
      'mp4': 'video/mp4',
      'mp3': 'audio/mpeg',
    };
    return mimeMap[ext] ?? 'application/octet-stream';
  }

  static Future<Uint8List> readFileBytes(String path) async {
    final file = File(path);
    return await file.readAsBytes();
  }

  static String getFileName(String path) {
    return path.split(Platform.pathSeparator).last;
  }
}
