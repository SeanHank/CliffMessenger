import 'dart:convert';
import 'package:sqflite_sqlcipher/sqflite.dart';
import '../../models/message.dart';
import 'client_db.dart';

class MessageStore {
  static Future<void> insertMessage(MessageModel message, String serverId, {String? userId}) async {
    // final db = await ClientDb.getDatabase();
    final db = await ClientDb.getDatabase(userId: userId);
    await db.insert(
      'messages',
      {
        'id': message.id,
        'group_id': message.groupId,
        'sender_id': message.senderId,
        'sender_nickname': message.senderNickname,
        'type': message.type.name,
        'encrypted_content': message.encryptedContent,
        'iv': message.iv,
        'auth_tag': '',
        'attachment': message.attachment != null
            ? jsonEncode(message.attachment!.toJson())
            : null,
        'timestamp': message.timestamp,
        'server_id': message.serverId,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  static Future<List<MessageModel>> getMessagesByGroup(
      String groupId, {int? limit, int? offset, String? userId}) async {
    // final db = await ClientDb.getDatabase();
    final db = await ClientDb.getDatabase(userId: userId);
    final List<Map<String, dynamic>> maps = await db.query(
      'messages',
      where: 'group_id = ?',
      whereArgs: [groupId],
      orderBy: 'timestamp DESC',
      limit: limit,
      offset: offset,
    );
    return maps.map((m) => _fromDbRow(m)).toList();
  }

  static Future<List<MessageModel>> getMessagesByGroupBefore(
      String groupId, {required int beforeTimestamp, int? limit, String? userId}) async {
    // final db = await ClientDb.getDatabase();
    final db = await ClientDb.getDatabase(userId: userId);
    final List<Map<String, dynamic>> maps = await db.query(
      'messages',
      where: 'group_id = ? AND timestamp < ?',
      whereArgs: [groupId, beforeTimestamp],
      orderBy: 'timestamp DESC',
      limit: limit,
    );
    return maps.map((m) => _fromDbRow(m)).toList();
  }

  static Future<List<MessageModel>> getMessagesByServer(String serverId, String? userId) async {
    // final db = await ClientDb.getDatabase();
    final db = await ClientDb.getDatabase(userId: userId);
    final List<Map<String, dynamic>> maps = await db.query(
      'messages',
      where: 'server_id = ?',
      whereArgs: [serverId],
      orderBy: 'timestamp DESC',
    );
    return maps.map((m) => _fromDbRow(m)).toList();
  }

  static Future<void> deleteMessagesByGroup(String groupId, String? userId) async {
    // final db = await ClientDb.getDatabase();
    final db = await ClientDb.getDatabase(userId: userId);
    await db.delete('messages', where: 'group_id = ?', whereArgs: [groupId]);
  }

  static Future<void> deleteMessagesByServer(String serverId, String? userId) async {
    // final db = await ClientDb.getDatabase();
    final db = await ClientDb.getDatabase(userId: userId);
    await db.delete('messages', where: 'server_id = ?', whereArgs: [serverId]);
  }

  static Future<bool> messageExists(String messageId, String? userId) async {
    // final db = await ClientDb.getDatabase();
    final db = await ClientDb.getDatabase(userId: userId);
    final result = await db.query(
      'messages',
      where: 'id = ?',
      whereArgs: [messageId],
      limit: 1,
    );
    return result.isNotEmpty;
  }

  static MessageModel _fromDbRow(Map<String, dynamic> row) {
    return MessageModel(
      id: row['id'] as String,
      groupId: row['group_id'] as String,
      senderId: row['sender_id'] as String,
      senderNickname: row['sender_nickname'] as String,
      type: MessageType.values.firstWhere(
        (e) => e.name == row['type'],
        orElse: () => MessageType.text,
      ),
      encryptedContent: row['encrypted_content'] as String,
      iv: row['iv'] as String,
      attachment: row['attachment'] != null
          ? FileAttachment.fromJson(jsonDecode(row['attachment'] as String))
          : null,
      timestamp: row['timestamp'] as int,
      serverId: row['server_id'] as String,
    );
  }
}
