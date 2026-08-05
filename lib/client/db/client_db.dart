// import 'package:sqflite/sqflite.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'dart:io';

import '../../core/crypto/db_key_manager.dart';

class ClientDb {
  static Database? _db;
  static Database? _globalDb;
  static String? _currentUserId;
  static String? _encryptionKey;

  static String? get currentUserId => _currentUserId;

  static Future<void> initialize() async {
    _encryptionKey = await DbKeyManager.getEncryptionKey();
  }


  // static Future<Database> getDatabase() async {
  //   if (_db != null) return _db!;
  //   final dir = await getApplicationDocumentsDirectory();
  //   final dbPath = p.join(dir.path, 'cliff_client', 'messages.db');
  //   final dbDir = Directory(p.dirname(dbPath));
  //   if (!await dbDir.exists()) {
  //     await dbDir.create(recursive: true);
  //   }
  //   _db = await openDatabase(
  //     dbPath,
  //     version: 1,
  //     onCreate: _onCreate,
  //   );
  //   return _db!;
  // }

  static Future<Database> getGlobalDatabase() async {
    if (_globalDb != null) return _globalDb!;

    final dir = await getApplicationDocumentsDirectory();
    final dbPath = p.join(dir.path, 'cliff_client', 'global.db');
    final dbDir = Directory(p.dirname(dbPath));
    if (!await dbDir.exists()) {
      await dbDir.create(recursive: true);
    }

    _globalDb = await openDatabase(
      dbPath,
      version: 1,
      onCreate: _onCreateGlobal,
      password: _encryptionKey,
    );
    return _globalDb!;
  }

  static Future<void> _onCreateGlobal(Database db, int version) async {
    await db.execute('''
      CREATE TABLE servers (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        host TEXT NOT NULL,
        port INTEGER NOT NULL,
        current_user_id TEXT,
        current_nickname TEXT
      )
    ''');

    // await db.execute('''
    //   CREATE TABLE group_keys (
    //     server_id TEXT NOT NULL,
    //     group_id TEXT NOT NULL,
    //     encrypted_key TEXT NOT NULL,
    //     PRIMARY KEY (server_id, group_id)
    //   )
    // ''');
  }

  static Future<Database> getDatabase({String? userId}) async {
    if (_db != null && _currentUserId == userId) return _db!;

    _currentUserId = userId;
    final dir = await getApplicationDocumentsDirectory();
    final dbPath = p.join(dir.path, 'cliff_client', userId ?? 'default', 'messages.db');
    final dbDir = Directory(p.dirname(dbPath));
    if (!await dbDir.exists()) {
      await dbDir.create(recursive: true);
    }

    _db = await openDatabase(
      dbPath,
      version: 1,
      onCreate: _onCreate,
      password: _encryptionKey,
    );
    return _db!;
  }

  static Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE messages (
        id TEXT PRIMARY KEY,
        group_id TEXT NOT NULL,
        sender_id TEXT NOT NULL,
        sender_nickname TEXT NOT NULL,
        type TEXT NOT NULL,
        encrypted_content TEXT NOT NULL,
        iv TEXT NOT NULL,
        auth_tag TEXT NOT NULL,
        attachment TEXT,
        timestamp INTEGER NOT NULL,
        server_id TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE INDEX idx_messages_group ON messages(group_id, timestamp)
    ''');

    // await db.execute('''
    //   CREATE TABLE servers (
    //     id TEXT PRIMARY KEY,
    //     name TEXT NOT NULL,
    //     host TEXT NOT NULL,
    //     port INTEGER NOT NULL,
    //     current_user_id TEXT,
    //     current_username TEXT,
    //     current_nickname TEXT,
    //     group_keys TEXT
    //   )
    // ''');

    // await db.execute('''
    //   CREATE TABLE group_keys (
    //     server_id TEXT NOT NULL,
    //     group_id TEXT NOT NULL,
    //     encrypted_key TEXT NOT NULL,
    //     PRIMARY KEY (server_id, group_id)
    //   )
    // ''');
  }

  static Future<void> switchUser(String userId) async {
    if (_db != null) {
      await _db!.close();
      _db = null;
    }
    _currentUserId = userId;
  }

  static Future<void> close() async {
    if (_db != null) {
      await _db!.close();
      _db = null;
      _currentUserId = null;
    }
  }
}
