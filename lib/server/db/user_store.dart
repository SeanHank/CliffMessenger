import 'package:sembast/sembast.dart';
import '../../models/user.dart';
import 'server_db.dart';

class UserStore {
  static const _storeName = 'users';

  static StoreRef<String, Map<String, dynamic>> get _store =>
      stringMapStoreFactory.store(_storeName);

  static Future<UserModel?> getUserByUsername(String username) async {
    final db = await ServerDb.getDatabase();
    final finder = Finder(
      filter: Filter.equals('username', username),
    );
    final record = await _store.findFirst(db, finder: finder);
    if (record != null) {
      return UserModel.fromJson(record.value);
    }
    return null;
  }

  static Future<UserModel?> getUserById(String id) async {
    final db = await ServerDb.getDatabase();
    final record = await _store.record(id).get(db);
    if (record != null) {
      return UserModel.fromJson(record);
    }
    return null;
  }

  static Future<bool> userExists(String username) async {
    return (await getUserByUsername(username)) != null;
  }

  static Future<void> createUser(UserModel user) async {
    final db = await ServerDb.getDatabase();
    await _store.record(user.id).put(db, user.toJson());
  }

  static Future<List<UserModel>> getUsersByIds(List<String> ids) async {
    final db = await ServerDb.getDatabase();
    final finder = Finder(
      filter: Filter.custom((record) => ids.contains(record.key)),
    );
    final records = await _store.find(db, finder: finder);
    return records.map((r) => UserModel.fromJson(r.value)).toList();
  }
}
