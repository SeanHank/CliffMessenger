import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../../core/crypto/key_manager.dart';
import '../../core/crypto/rsa_crypto.dart';
import '../../client/websocket_client.dart';
import '../../core/network/protocol.dart';
import '../../models/group.dart';
import '../client/db/client_db.dart';
import '../client/storage/file_storage.dart';
import '../core/utils/utils.dart';

enum AuthState { unauthenticated, authenticating, authenticated }

class AuthProvider extends ChangeNotifier {
  AuthState _state = AuthState.unauthenticated;
  String? _userId;
  String? _username;
  String? _nickname;
  String? _error;
  String? _privateKeyPem;
  List<GroupModel> _groups = [];
  ServerConnection? _activeConnection;
  final Map<String, Uint8List> _decryptedGroupKeys = {};
  Map<String, dynamic>? _pendingJoinRequest;
  Map<String, dynamic>? _pendingDissolveGroup;
  int? _pendingOfflineCount;

  AuthState get state => _state;
  String? get userId => _userId;
  String? get username => _username;
  String? get nickname => _nickname;
  String? get error => _error;
  String? get privateKeyPem => _privateKeyPem;
  List<GroupModel> get groups => _groups;
  ServerConnection? get activeConnection => _activeConnection;
  bool get isAuthenticated => _state == AuthState.authenticated;
  Map<String, Uint8List> get decryptedGroupKeys => Map.unmodifiable(_decryptedGroupKeys);
  Map<String, dynamic>? get pendingJoinRequest => _pendingJoinRequest;
  Map<String, dynamic>? get pendingDissolveGroup => _pendingDissolveGroup;

  Future<bool> register(
      ServerConnection connection, String username, String nickname, String password) async {
    _state = AuthState.authenticating;
    _error = null;
    notifyListeners();

    try {
      final keyResult = KeyManager.generateKeys();
      _privateKeyPem = keyResult['privateKeyPem'] as String;

      final completer = Completer<bool>();

      void listener(WSMessage msg) {
        if (msg.type == WSMessageType.registerSuccess) {
          _userId = msg.payload['userId'] as String?;
          completer.complete(true);
        } else if (msg.type == WSMessageType.registerFailed) {
          _error = msg.payload['message'] as String? ?? 'Registration failed';
          completer.complete(false);
        }
      }

      final sub = connection.messages.listen(listener);

      connection.register(username, nickname, password, keyResult['publicKey'] as String);

      final success = await completer.future.timeout(const Duration(seconds: 10));
      sub.cancel();

      if (success) {
        KeyManager.setCurrentUser(_userId);
        KeyManager.storeKeys(password, keyResult['publicKey'] as String, _privateKeyPem!);
        _state = AuthState.unauthenticated;
      } else {
        _state = AuthState.unauthenticated;
      }
      notifyListeners();
      return success;
    } catch (e) {
      _error = e.toString();
      _state = AuthState.unauthenticated;
      notifyListeners();
      return false;
    }
  }

  Future<bool> login(ServerConnection connection, String username, String password) async {
    _state = AuthState.authenticating;
    _error = null;
    notifyListeners();

    try {
      final completer = Completer<bool>();

      void listener(WSMessage msg) {
        if (msg.type == WSMessageType.loginSuccess) {
          _userId = msg.payload['userId'] as String?;
          _nickname = msg.payload['nickname'] as String?;

          final offlineCount = msg.payload['offlineCount'] as int? ?? 0;

          // 立即设置用户上下文（在收到 userId 后）
          if (_userId != null) {
            ClientDb.switchUser(_userId!);
            ClientFileStorage.setCurrentUser(_userId!);
            KeyManager.setCurrentUser(_userId);
            _setupGroupMessageListener(connection);
          }

          if (msg.payload['groups'] != null) {
            _groups = (msg.payload['groups'] as List)
                .map((g) => GroupModel.fromJson(g as Map<String, dynamic>))
                .toList();

          }
          _username = username;
          _activeConnection = connection;

          if (offlineCount > 0) {
            _pendingOfflineCount = offlineCount;
          }

          completer.complete(true);
        } else if (msg.type == WSMessageType.loginFailed) {
          _error = msg.payload['message'] as String? ?? 'Login failed';
          completer.complete(false);
        }
      }

      final sub = connection.messages.listen(listener);
      connection.login(username, password);

      final success = await completer.future.timeout(const Duration(seconds: 10));
      sub.cancel();

      _privateKeyPem = await KeyManager.loadPrivateKey(password);
      if (_privateKeyPem == null) {
        _error = 'Failed to load private key';
        _state = AuthState.unauthenticated;
        notifyListeners();
        return false;
      }

      _decryptAllGroupKeys();

      _state = success ? AuthState.authenticated : AuthState.unauthenticated;
      // notifyListeners();

      if (success) {
        _activeConnection = connection;

        if (_pendingOfflineCount != null && _pendingOfflineCount! > 0) {
          await handleOfflineMessages(_pendingOfflineCount!, connection);
          _pendingOfflineCount = null;
        }
      }

      return success;
    } catch (e) {
      _error = e.toString();
      _state = AuthState.unauthenticated;
      notifyListeners();
      return false;
    }
  }

  Future<void> handleOfflineMessages(int offlineCount, ServerConnection connection) async {
    if (offlineCount > 0) {
      // 先同步群密钥
      syncGroupKeysForOfflineMessages();

      // 然后加载离线消息
      connection.requestOffline(1, 50);
    }
  }

  // 同步群密钥用于离线消息解密
  Future<void> syncGroupKeysForOfflineMessages() async {
    for (final group in _groups) {
      // 跳过已有密钥的群
      if (_decryptedGroupKeys.containsKey(group.id)) continue;

      // 尝试解密存储的 encryptedGroupKey
      if (group.encryptedGroupKey != null && _privateKeyPem != null) {
        try {
          final privateKey = RsaCrypto.privateKeyFromPem(_privateKeyPem!);
          final encryptedKeyBytes = base64Decode(group.encryptedGroupKey!);
          final groupKey = RsaCrypto.decryptAesKeyForUser(encryptedKeyBytes, privateKey);
          _decryptedGroupKeys[group.id] = groupKey;
        } catch (e) {
          // 跳过无法解密的群（可能是其他成员专用加密的密钥）
        }
      }
    }
    notifyListeners();
  }

  void _decryptAllGroupKeys() {
    if (_privateKeyPem == null) return;
    _decryptedGroupKeys.clear();
    try {
      final privateKey = RsaCrypto.privateKeyFromPem(_privateKeyPem!);
      for (final group in _groups) {
        if (group.encryptedGroupKey != null) {
          try {
            final encryptedKeyBytes = base64Decode(group.encryptedGroupKey!);
            final groupKey = RsaCrypto.decryptAesKeyForUser(encryptedKeyBytes, privateKey);
            _decryptedGroupKeys[group.id] = groupKey;
          } catch (e) {
            // skip groups that fail to decrypt
          }
        }
      }
    } catch (e) {
      // invalid private key
    }
  }

  Uint8List? getGroupKey(String groupId) {
    return _decryptedGroupKeys[groupId];
  }

  void handleGroupUpdate(GroupModel updatedGroup) {
    _groups = [..._groups.where((g) => g.id != updatedGroup.id), updatedGroup];
    if (_privateKeyPem != null && updatedGroup.encryptedGroupKey != null) {
      try {
        final privateKey = RsaCrypto.privateKeyFromPem(_privateKeyPem!);
        final encryptedKeyBytes = base64Decode(updatedGroup.encryptedGroupKey!);
        final groupKey = RsaCrypto.decryptAesKeyForUser(encryptedKeyBytes, privateKey);
        _decryptedGroupKeys[updatedGroup.id] = groupKey;
      } catch (e) {
        // skip on error
      }
    }
    notifyListeners();
  }

  Future<void> logout() async {
    await ClientDb.close();
    KeyManager.setCurrentUser(null);
    _state = AuthState.unauthenticated;
    _userId = null;
    _username = null;
    _nickname = null;
    _privateKeyPem = null;
    _groups.clear();
    _activeConnection = null;
    _error = null;
    _decryptedGroupKeys.clear();
    notifyListeners();
  }

  void addGroup(GroupModel group) {
    _groups = [..._groups.where((g) => g.id != group.id), group];
    notifyListeners();
  }

  void removeGroup(String groupId) {
    _groups = _groups.where((g) => g.id != groupId).toList();
    _decryptedGroupKeys.remove(groupId);
    notifyListeners();
  }

  void _setupGroupMessageListener(ServerConnection connection) {
    connection.messages.listen((msg) {
      if (msg.type == WSMessageType.groupUpdate) {
        final action = msg.payload['action'] as String?;
        if (action == 'created' || action == 'joined') {
          final group = GroupModel.fromJson(
              msg.payload['group'] as Map<String, dynamic>);
          addGroup(group); // 调用已有的 addGroup 方法，会 notifyListeners()
        } else if (action == 'left') {
          final groupId = msg.payload['groupId'] as String?;
          if (groupId != null) {
            removeGroup(groupId);
          }
        } else if (action == 'member_joined') {
          final groupData = msg.payload['group'] as Map<String, dynamic>?;
          if (groupData != null) {
            final group = GroupModel.fromJson(groupData);
            handleGroupUpdate(group);
          }
        } else if (action == 'member_left') {
          final groupData = msg.payload['group'] as Map<String, dynamic>?;
          if (groupData != null) {
            final group = GroupModel.fromJson(groupData);
            handleGroupUpdate(group);
          }
        } else if (action == 'dissolved') {
          final groupId = msg.payload['groupId'] as String?;
          final groupName = msg.payload['groupName'] as String?;
          if (groupId != null) {
            removeGroup(groupId);
            _pendingDissolveGroup = {'groupId': groupId, 'groupName': groupName};
            notifyListeners();
          }
        }
      } else if (msg.type == WSMessageType.groupKeyRequest) {
        // 新成员加入，创建者需要重新加密并发送密钥
        final action = msg.payload['action'] as String?;
        if (action == 'approve_join') {
          final groupId = msg.payload['groupId'] as String?;
          final newMemberId = msg.payload['requesterId'] as String?;
          if (groupId != null && newMemberId != null) {
            _reEncryptAndSendGroupKey(connection, groupId, newMemberId);
          }
        }
      } else if (msg.type == WSMessageType.groupJoinRequest) {
        _handleGroupJoinRequest(msg);
      } else if (msg.type == WSMessageType.groupKeyTransfer) {
        _handleGroupKeyTransfer(msg);
      } else if (msg.type == WSMessageType.groupJoinResult) {
        _handleGroupJoinResult(msg);
      }
    });
  }

  void _handleGroupJoinRequest(WSMessage msg) {
    final action = msg.payload['action'] as String?;

    if (action == 'pending') {
      // _error = 'Join request submitted, waiting for approval';
      notifyListeners();
      return;
    }

    // 群主收到：显示 pop up
    final groupId = msg.payload['groupId'] as String?;
    final groupName = msg.payload['groupName'] as String?;
    final requesterId = msg.payload['requesterId'] as String?;
    final requesterNickname = msg.payload['requesterNickname'] as String?;

    if (groupId == null || requesterId == null) return;

    // 触发 UI pop up（通过回调或状态）
    _pendingJoinRequest = {
      'groupId': groupId,
      'groupName': groupName,
      'requesterId': requesterId,
      'requesterNickname': requesterNickname,
    };
    notifyListeners();
  }

  void _handleGroupJoinResult(WSMessage msg) {
    final action = msg.payload['action'] as String?;
    if (action == 'rejected') {
      _error = 'Join request rejected by group owner';
      notifyListeners();
    } else if (action == 'approved') {
      // 解析群信息
      final groupJson = msg.payload['group'] as Map<String, dynamic>;
      final group = GroupModel.fromJson(groupJson);

      // 新增：处理新成员收到的群密钥
      final encryptedGroupKey = msg.payload['encryptedGroupKey'] as String?;
      if (encryptedGroupKey != null && _privateKeyPem != null) {
        try {
          final privateKey = RsaCrypto.privateKeyFromPem(_privateKeyPem!);
          final encryptedKeyBytes = base64Decode(encryptedGroupKey);
          final groupKey = RsaCrypto.decryptAesKeyForUser(encryptedKeyBytes, privateKey);
          _decryptedGroupKeys[group.id] = groupKey;
        } catch (e) {
          _error = 'Failed to decrypt group key: $e';
        }
      }

      addGroup(group);
    }
  }

  Future<void> approveGroupJoin(String groupId, String requesterId) async {
    _pendingJoinRequest = null;

    try {
      // 1. 获取原始群密钥
      Uint8List? groupKey = _decryptedGroupKeys[groupId];

      if (groupKey == null) {
        final group = _groups.firstWhere(
              (g) => g.id == groupId,
          orElse: () => throw Exception('Group not found'),
        );

        if (group.encryptedGroupKey != null && _privateKeyPem != null) {
          final privateKey = RsaCrypto.privateKeyFromPem(_privateKeyPem!);
          final encryptedKeyBytes = base64Decode(group.encryptedGroupKey!);
          groupKey = RsaCrypto.decryptAesKeyForUser(encryptedKeyBytes, privateKey);
          _decryptedGroupKeys[groupId] = groupKey;
        }
      }

      if (groupKey == null) {
        _showErrorSnackbar('No group key available');
        return;
      }

      // 2. 获取新成员公钥（使用公共方法）
      final publicKey = await _activeConnection!.requestUserPublicKeyWithResponse(requesterId);

      if (publicKey == null) {
        _showErrorSnackbar('Failed to get requester public key');
        return;
      }

      // 3. 用新成员的公钥重新加密群密钥
      final encryptedKey = RsaCrypto.encryptAesKeyForUser(groupKey, publicKey);

      // 4. 发送 Approve 消息，包含重新加密的密钥
      _activeConnection?.send(WSMessage(
        type: WSMessageType.groupJoinApprove,
        id: UuidGenerator.generate(),
        payload: {
          'groupId': groupId,
          'requesterId': requesterId,
          'encryptedGroupKey': base64Encode(encryptedKey),
        },
      ));
    } catch (e) {
      _showErrorSnackbar('Failed to approve: $e');
    }
  }

// 新增：显示错误 Snackbar
  void _showErrorSnackbar(String message) {
    _error = message;
    notifyListeners();
  }

// 新增：拒绝加入
  Future<void> rejectGroupJoin(String groupId, String requesterId) async {
    _pendingJoinRequest = null;
    _activeConnection?.send(WSMessage(
      type: WSMessageType.groupJoinReject,
      id: UuidGenerator.generate(),
      payload: {
        'groupId': groupId,
        'requesterId': requesterId,
      },
    ));
  }

  void _handleGroupKeyTransfer(WSMessage msg) {
    final groupId = msg.payload['groupId'] as String?;
    final encryptedKey = msg.payload['encryptedKey'] as String?;

    if (groupId == null || encryptedKey == null || _privateKeyPem == null) return;

    try {
      // 用私钥解密群聊密钥
      final privateKey = RsaCrypto.privateKeyFromPem(_privateKeyPem!);
      final encryptedKeyBytes = base64Decode(encryptedKey);
      final groupKey = RsaCrypto.decryptAesKeyForUser(encryptedKeyBytes, privateKey);

      // 存储解密后的群聊密钥
      _decryptedGroupKeys[groupId] = groupKey;

      // 更新本地群聊数据（包含加密的密钥，供其他 Provider 使用）
      _updateGroupEncryptedKey(groupId, encryptedKey);

      notifyListeners();
    } catch (e) {
      // 解密失败
    }
  }

// 新增：更新群聊的加密密钥
  void _updateGroupEncryptedKey(String groupId, String encryptedKey) {
    final index = _groups.indexWhere((g) => g.id == groupId);
    if (index >= 0) {
      _groups = [
        ..._groups.sublist(0, index),
        _groups[index].copyWith(encryptedGroupKey: encryptedKey),
        ..._groups.sublist(index + 1),
      ];
    }
  }

  // Future<void> _reEncryptAndSendGroupKey(
  //     ServerConnection connection, String groupId, String newMemberId) async {
  //   try {
  //     // 1. 获取原始群聊密钥
  //     final groupKey = _decryptedGroupKeys[groupId];
  //     if (groupKey == null) return;
  //
  //     // 2. 获取新成员的公钥（通过服务器获取）
  //     final completer = Completer<String?>();
  //
  //     void listener(WSMessage msg) {
  //       if (msg.type == WSMessageType.userPublicKey) {
  //         completer.complete(msg.payload['publicKey'] as String?);
  //       }
  //     }
  //
  //     final sub = connection.messages.listen(listener);
  //     connection.requestUserPublicKey(newMemberId);
  //
  //     final publicKey = await completer.future.timeout(const Duration(seconds: 10));
  //     sub.cancel();
  //
  //     if (publicKey == null) return;
  //
  //     // 3. 用新成员的公钥重新加密群聊密钥
  //     final encryptedKey = RsaCrypto.encryptAesKeyForUser(groupKey, publicKey);
  //
  //     // 4. 发送加密后的密钥给新成员
  //     connection.sendGroupKeyToUser(
  //       newMemberId,
  //       groupId,
  //       base64Encode(encryptedKey),
  //     );
  //   } catch (e) {
  //     // 忽略错误
  //   }
  // }
  Future<void> _reEncryptAndSendGroupKey(
      ServerConnection connection, String groupId, String newMemberId) async {
    try {
      // 1. 获取原始群聊密钥
      Uint8List? groupKey = _decryptedGroupKeys[groupId];

      // 如果缓存中没有，尝试解密
      if (groupKey == null) {
        final group = _groups.firstWhere(
              (g) => g.id == groupId,
          orElse: () => throw Exception('Group not found'),
        );

        if (group.encryptedGroupKey != null && _privateKeyPem != null) {
          final privateKey = RsaCrypto.privateKeyFromPem(_privateKeyPem!);
          final encryptedKeyBytes = base64Decode(group.encryptedGroupKey!);
          groupKey = RsaCrypto.decryptAesKeyForUser(encryptedKeyBytes, privateKey);
          _decryptedGroupKeys[groupId] = groupKey;
        }
      }

      if (groupKey == null) {
        _error = 'No group key available';
        notifyListeners();
        return;
      }

      // 2. 获取新成员的公钥
      final completer = Completer<String?>();

      void listener(WSMessage msg) {
        if (msg.type == WSMessageType.userPublicKey) {
          completer.complete(msg.payload['publicKey'] as String?);
        }
      }

      final sub = connection.messages.listen(listener);
      connection.requestUserPublicKey(newMemberId);

      final publicKey = await completer.future.timeout(const Duration(seconds: 10));
      sub.cancel();

      if (publicKey == null) return;

      // 3. 用新成员的公钥重新加密群聊密钥
      final encryptedKey = RsaCrypto.encryptAesKeyForUser(groupKey, publicKey);

      // 4. 发送加密后的密钥给新成员
      connection.sendGroupKeyToUser(
        newMemberId,
        groupId,
        base64Encode(encryptedKey),
      );
    } catch (e) {
      _error = 'Failed to send group key: $e';
      notifyListeners();
    }
  }

  void updateGroups(List<GroupModel> groups) {
    _groups = groups;
    _decryptAllGroupKeys();
    notifyListeners();
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }

  void clearPendingDissolveGroup() {
    _pendingDissolveGroup = null;
    notifyListeners();
  }
}