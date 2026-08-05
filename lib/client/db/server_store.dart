import 'package:sqflite_sqlcipher/sqflite.dart';
import '../../models/server_config.dart';
import 'client_db.dart';

class ServerStore {
  static Future<void> saveServer(ServerConfig config) async {
    final db = await ClientDb.getGlobalDatabase();
    await db.insert(
      'servers',
      {
        'id': config.id,
        'name': config.name,
        'host': config.host,
        'port': config.port,
        'current_user_id': config.currentUserId,
        'current_nickname': config.currentNickname,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  static Future<List<ServerConfig>> getAllServers() async {
    final db = await ClientDb.getGlobalDatabase();
    final List<Map<String, dynamic>> maps = await db.query('servers');
    return maps.map((m) => ServerConfig.fromJson(m)).toList();
  }

  static Future<ServerConfig?> getServer(String id) async {
    final db = await ClientDb.getGlobalDatabase();
    final List<Map<String, dynamic>> maps = await db.query(
      'servers',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (maps.isEmpty) return null;
    return ServerConfig.fromJson(maps.first);
  }

  // static Future<List<ServerConfig>> getAllServers() async {
  //   final db = await ClientDb.getGlobalDatabase();
  //   final maps = await db.query('servers');
  //   return maps.map(_decryptServer).toList();
  // }
  //
  // static Future<ServerConfig?> getServer(String id) async {
  //   final db = await ClientDb.getGlobalDatabase();
  //   final maps = await db.query('servers', where: 'id = ?', whereArgs: [id], limit: 1);
  //   if (maps.isEmpty) return null;
  //   return _decryptServer(maps.first);
  // }

  static Future<void> updateServer(ServerConfig config) async {
    final db = await ClientDb.getGlobalDatabase();
    await db.update(
      'servers',
      {
        'name': config.name,
        'host': config.host,
        'port': config.port,
        'current_user_id': config.currentUserId,
        'current_nickname': config.currentNickname,
      },
      where: 'id = ?',
      whereArgs: [config.id],
    );
  }

  static Future<void> removeServer(String id) async {
    final db = await ClientDb.getGlobalDatabase();
    await db.delete('servers', where: 'id = ?', whereArgs: [id]);
    // await db.delete('group_keys', where: 'server_id = ?', whereArgs: [id]);
  }

  // static Future<void> saveGroupKey(String serverId, String groupId, String encryptedKey) async {
  //   final db = await ClientDb.getGlobalDatabase();
  //   await db.insert(
  //     'group_keys',
  //     {
  //       'server_id': serverId,
  //       'group_id': groupId,
  //       'encrypted_key': encryptedKey,
  //     },
  //     conflictAlgorithm: ConflictAlgorithm.replace,
  //   );
  // }
  //
  // static Future<String?> getGroupKey(String serverId, String groupId) async {
  //   final db = await ClientDb.getGlobalDatabase();
  //   final List<Map<String, dynamic>> maps = await db.query(
  //     'group_keys',
  //     where: 'server_id = ? AND group_id = ?',
  //     whereArgs: [serverId, groupId],
  //     limit: 1,
  //   );
  //   if (maps.isEmpty) return null;
  //   return maps.first['encrypted_key'] as String;
  // }
}
