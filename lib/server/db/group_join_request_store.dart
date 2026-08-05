import 'package:sembast/sembast.dart';
import 'server_db.dart';

class GroupJoinRequestStore {
  static const _storeName = 'group_join_requests';

  static StoreRef<String, Map<String, dynamic>> get _store =>
      stringMapStoreFactory.store(_storeName);

  static Future<void> addRequest({
    required String requestId,
    required String groupId,
    required String requesterId,
    required String requesterNickname,
    required String creatorId,
    required String inviteCode,
    required int timestamp,
  }) async {
    final db = await ServerDb.getDatabase();
    await _store.record(requestId).put(db, {
      'requestId': requestId,
      'groupId': groupId,
      'requesterId': requesterId,
      'requesterNickname': requesterNickname,
      'creatorId': creatorId,
      'inviteCode': inviteCode,
      'timestamp': timestamp,
    });
  }

  static Future<List<Map<String, dynamic>>> getRequestsByCreator(String creatorId) async {
    final db = await ServerDb.getDatabase();
    final finder = Finder(
      filter: Filter.equals('creatorId', creatorId),
      sortOrders: [SortOrder('timestamp', true)],
    );
    final records = await _store.find(db, finder: finder);
    return records.map((r) => r.value).toList();
  }

  static Future<void> deleteRequest(String requestId) async {
    final db = await ServerDb.getDatabase();
    await _store.record(requestId).delete(db);
  }

  static Future<void> deleteRequestsByCreator(String creatorId) async {
    final db = await ServerDb.getDatabase();
    final finder = Finder(filter: Filter.equals('creatorId', creatorId));
    final records = await _store.find(db, finder: finder);
    for (final record in records) {
      await _store.record(record.key).delete(db);
    }
  }
}