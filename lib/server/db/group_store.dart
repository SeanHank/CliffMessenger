import 'package:sembast/sembast.dart';
import '../../models/group.dart';
import 'server_db.dart';

class GroupStore {
  static const _storeName = 'groups';

  static StoreRef<String, Map<String, dynamic>> get _store =>
      stringMapStoreFactory.store(_storeName);

  static Future<GroupModel?> getGroupById(String id) async {
    final db = await ServerDb.getDatabase();
    final record = await _store.record(id).get(db);
    if (record != null) {
      return GroupModel.fromJson(record);
    }
    return null;
  }

  static Future<GroupModel?> getGroupByInviteCode(String inviteCode) async {
    final db = await ServerDb.getDatabase();
    final finder = Finder(
      filter: Filter.equals('inviteCode', inviteCode),
    );
    final record = await _store.findFirst(db, finder: finder);
    if (record != null) {
      return GroupModel.fromJson(record.value);
    }
    return null;
  }

  static Future<List<GroupModel>> getGroupsByServer(String serverId) async {
    final db = await ServerDb.getDatabase();
    final finder = Finder(
      filter: Filter.equals('serverId', serverId),
    );
    final records = await _store.find(db, finder: finder);
    return records.map((r) => GroupModel.fromJson(r.value)).toList();
  }

  static Future<List<GroupModel>> getGroupsByMember(String userId) async {
    final db = await ServerDb.getDatabase();
    final records = await _store.find(db);
    return records
        .where((r) => (r.value['memberIds'] as List).contains(userId))
        .map((r) => GroupModel.fromJson(r.value))
        .toList();
  }

  static Future<void> createGroup(GroupModel group) async {
    final db = await ServerDb.getDatabase();
    await _store.record(group.id).put(db, group.toJson());
  }

  static Future<void> updateGroup(GroupModel group) async {
    final db = await ServerDb.getDatabase();
    await _store.record(group.id).put(db, group.toJson());
  }

  static Future<void> deleteGroup(String groupId) async {
    final db = await ServerDb.getDatabase();
    await _store.record(groupId).delete(db);
  }

  static Future<bool> isMember(String groupId, String userId) async {
    final group = await getGroupById(groupId);
    return group?.memberIds.contains(userId) ?? false;
  }
}
