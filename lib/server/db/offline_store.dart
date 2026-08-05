import 'package:sembast/sembast.dart';
import '../../models/message.dart';
import 'server_db.dart';

class OfflineStore {
  static const _storeName = 'offline_messages';

  static StoreRef<String, Map<String, dynamic>> get _store =>
      stringMapStoreFactory.store(_storeName);

  static Future<void> addOfflineMessage(MessageModel message, String targetUserId) async {
    final db = await ServerDb.getDatabase();
    final id = '${targetUserId}_${message.id}';
    await _store.record(id).put(db, {
      ...message.toJson(),
      'targetUserId': targetUserId,
      'delivered': false,
    });
  }

  static Future<List<MessageModel>> getOfflineMessages(
      String userId, {int page = 1, int pageSize = 50}) async {
    final db = await ServerDb.getDatabase();
    final finder = Finder(
      filter: Filter.and([
        Filter.equals('targetUserId', userId),
        Filter.equals('delivered', false),
      ]),
      sortOrders: [SortOrder('timestamp', true)],
      limit: pageSize,
      offset: (page - 1) * pageSize,
    );
    final records = await _store.find(db, finder: finder);
    return records.map((r) => MessageModel.fromJson(r.value)).toList();
  }

  static Future<int> getOfflineCount(String userId) async {
    final db = await ServerDb.getDatabase();
    return await _store.count(db, filter: Filter.and([
      Filter.equals('targetUserId', userId),
      Filter.equals('delivered', false),
    ]));
  }

  static Future<void> markDelivered(String userId, String messageId) async {
    final db = await ServerDb.getDatabase();
    final id = '${userId}_$messageId';
    final record = await _store.record(id).get(db);
    if (record != null) {
      await _store.record(id).put(db, {...record, 'delivered': true});
    }
  }

  static Future<void> clearDelivered(String userId) async {
    final db = await ServerDb.getDatabase();
    final finder = Finder(
      filter: Filter.and([
        Filter.equals('targetUserId', userId),
        Filter.equals('delivered', true),
      ]),
    );
    final records = await _store.find(db, finder: finder);
    for (final record in records) {
      await _store.record(record.key).delete(db);
    }
  }
}
