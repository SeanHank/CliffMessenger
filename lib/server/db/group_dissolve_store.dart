import 'package:sembast/sembast.dart';
import 'server_db.dart';

class GroupDissolveStore {
  static const _storeName = 'group_dissolve_notifications';

  static StoreRef<String, Map<String, dynamic>> get _store =>
      stringMapStoreFactory.store(_storeName);

  static Future<void> addNotification(String groupId, String groupName, String targetUserId) async {
    final db = await ServerDb.getDatabase();
    final id = '${targetUserId}_$groupId';
    await _store.record(id).put(db, {
      'groupId': groupId,
      'groupName': groupName,
      'targetUserId': targetUserId,
    });
  }

  static Future<List<Map<String, dynamic>>> getNotificationsByUser(String userId) async {
    final db = await ServerDb.getDatabase();
    final finder = Finder(
      filter: Filter.equals('targetUserId', userId),
    );
    final records = await _store.find(db, finder: finder);
    return records.map((r) => r.value).toList();
  }

  static Future<void> deleteNotification(String userId, String groupId) async {
    final db = await ServerDb.getDatabase();
    await _store.record('${userId}_$groupId').delete(db);
  }
}
