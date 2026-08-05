import 'dart:convert';
import 'dart:io';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_web_socket/shelf_web_socket.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:bcrypt/bcrypt.dart';
import 'package:logging/logging.dart';
import '../core/network/protocol.dart';
import '../core/utils/utils.dart';
import '../models/group.dart';
import '../models/message.dart';
import '../models/user.dart';
import 'db/group_join_request_store.dart';
import 'db/group_dissolve_store.dart';
import 'db/group_store.dart';
import 'db/offline_store.dart';
import 'db/user_store.dart';
import 'storage/file_storage.dart';
import '../core/crypto/aes_crypto.dart';
import '../core/crypto/rsa_crypto.dart';

class ConnectedClient {
  final WebSocketChannel channel;
  final String userId;
  final String username;

  ConnectedClient({
    required this.channel,
    required this.userId,
    required this.username,
  });
}

class ServerManager {
  static final ServerManager _instance = ServerManager._internal();
  factory ServerManager() => _instance;
  ServerManager._internal();

  HttpServer? _server;
  final Map<String, ConnectedClient> _connectedClients = {};
  final Map<String, List<int>> _fileBuffers = {};
  String? _serverId;
  String _serverName = '';
  int _port = 0;
  bool _isRunning = false;
  final _logger = Logger('ServerManager');

  bool get isRunning => _isRunning;
  String get serverId => _serverId ?? '';
  String get serverName => _serverName;
  int get port => _port;

  Future<bool> start(String name, int port) async {
    try {
      _serverName = name;
      _port = port;
      _serverId = UuidGenerator.generate();

      final handler = const Pipeline()
          .addMiddleware(logRequests())
          .addHandler(_handleRequest);

      _server = await shelf_io.serve(
        handler,
        InternetAddress.anyIPv4,
        port,
      );

      _isRunning = true;
      return true;
    } catch (e) {
      _logger.severe('Server start failed: $e');
      return false;
    }
  }

  Future<void> stop() async {
    await _server?.close(force: true);
    for (final client in _connectedClients.values) {
      await client.channel.sink.close();
    }
    _connectedClients.clear();
    _isRunning = false;
  }

  Future<void> _handleWebSocket(WebSocketChannel channel) async {
    String? currentUserId;
    String? currentUsername;

    await for (final message in channel.stream) {
      try {
        final wsMsg = WSMessage.fromRaw(message as String);
        final result = await _processMessage(channel, wsMsg);
        if (result != null) {
          currentUserId = result['userId'] as String?;
          currentUsername = result['username'] as String?;
          if (currentUserId != null) {
            _connectedClients[currentUserId] = ConnectedClient(
              channel: channel,
              userId: currentUserId,
              username: currentUsername ?? '',
            );
          }
        }
      } catch (e) {
        final error = WSMessage(
          type: WSMessageType.error,
          id: UuidGenerator.generate(),
          payload: {'message': 'Invalid message format'},
        );
        channel.sink.add(error.toJsonString());
      }
    }

    if (currentUserId != null) {
      _connectedClients.remove(currentUserId);
    }
  }

  Future<Map<String, dynamic>?> _processMessage(
      WebSocketChannel channel, WSMessage msg) async {
    Map<String, dynamic>? authResult;

    switch (msg.type) {
      case WSMessageType.serverInfo:
        channel.sink.add(WSMessage(
          type: WSMessageType.serverInfoResponse,
          id: msg.id,
          payload: {
            'serverName': _serverName,
          },
        ).toJsonString());
        break;
      case WSMessageType.register:
        await _handleRegister(channel, msg);
        break;
      case WSMessageType.login:
        authResult = await _handleLogin(channel, msg);
        break;
      case WSMessageType.msg:
        await _handleSendMessage(channel, msg);
        break;
      case WSMessageType.groupCreate:
        await _handleGroupCreate(channel, msg);
        break;
      case WSMessageType.groupJoin:
        await _handleGroupJoin(channel, msg);
        break;
      case WSMessageType.groupJoinApprove:
        await _handleGroupJoinApprove(channel, msg);
        break;
      case WSMessageType.groupJoinReject:
        await _handleGroupJoinReject(channel, msg);
        break;
      case WSMessageType.groupList:
        await _handleGroupList(channel, msg);
        break;
      case WSMessageType.offlineFetch:
        await _handleOfflineFetch(channel, msg);
        break;
      case WSMessageType.msgAck:
        await _handleAck(channel, msg);
        break;
      case WSMessageType.leaveGroup:
        await _handleLeaveGroup(channel, msg);
        break;
      case WSMessageType.ping:
        channel.sink.add(WSMessage(
          type: WSMessageType.pong,
          id: msg.id,
          payload: {},
        ).toJsonString());
        break;
      case WSMessageType.fileUpload:
        await _handleFileUploadStart(channel, msg);
        break;
      case WSMessageType.fileData:
        await _handleFileData(channel, msg);
        break;
      case WSMessageType.fileComplete:
        await _handleFileComplete(channel, msg);
        break;
      case WSMessageType.fileDownload:
        await _handleFileDownload(channel, msg);
        break;
      case WSMessageType.getUserPublicKey:
        await _handleGetUserPublicKey(channel, msg);
        break;
    }

    return authResult;
  }

  Future<void> _handleGetUserPublicKey(WebSocketChannel channel, WSMessage msg) async {
    final userId = msg.payload['userId'] as String?;
    if (userId == null) return;

    final user = await UserStore.getUserById(userId);
    if (user == null) return;

    channel.sink.add(WSMessage(
      type: WSMessageType.userPublicKey,
      id: msg.id,
      payload: {
        'userId': userId,
        'publicKey': user.rsaPublicKey,
      },
    ).toJsonString());
  }

  Future<void> _handleRegister(WebSocketChannel channel, WSMessage msg) async {
    final username = msg.payload['username'] as String?;
    final nickname = msg.payload['nickname'] as String?;
    final password = msg.payload['password'] as String?;
    final rsaPublicKey = msg.payload['rsaPublicKey'] as String?;

    if (username == null || nickname == null || password == null || rsaPublicKey == null) {
      channel.sink.add(WSMessage(
        type: WSMessageType.registerFailed,
        id: msg.id,
        payload: {'message': 'Missing required fields'},
      ).toJsonString());
      return;
    }

    if (await UserStore.userExists(username)) {
      channel.sink.add(WSMessage(
        type: WSMessageType.registerFailed,
        id: msg.id,
        payload: {'message': 'Username already exists'},
      ).toJsonString());
      return;
    }

    final passwordHash = BCrypt.hashpw(password, BCrypt.gensalt());

    final user = UserModel(
      id: UuidGenerator.generate(),
      username: username,
      nickname: nickname,
      passwordHash: passwordHash,
      rsaPublicKey: rsaPublicKey,
    );

    await UserStore.createUser(user);

    channel.sink.add(WSMessage(
      type: WSMessageType.registerSuccess,
      id: msg.id,
      payload: {'userId': user.id},
    ).toJsonString());
  }

  Future<Map<String, dynamic>?> _handleLogin(
      WebSocketChannel channel, WSMessage msg) async {
    final username = msg.payload['username'] as String?;
    final password = msg.payload['password'] as String?;

    if (username == null || password == null) {
      channel.sink.add(WSMessage(
        type: WSMessageType.loginFailed,
        id: msg.id,
        payload: {'message': 'Missing credentials'},
      ).toJsonString());
      return null;
    }

    final user = await UserStore.getUserByUsername(username);
    if (user == null || !BCrypt.checkpw(password, user.passwordHash)) {
      channel.sink.add(WSMessage(
        type: WSMessageType.loginFailed,
        id: msg.id,
        payload: {'message': 'Invalid credentials'},
      ).toJsonString());
      return null;
    }

    final groups = await GroupStore.getGroupsByMember(user.id);
    final offlineCount = await OfflineStore.getOfflineCount(user.id);

    // 构建用户专属的 group 信息
    final List<Map<String, dynamic>> groupsWithMemberKey = [];
    for (final g in groups) {
      final Map<String, dynamic> groupJson = g.toJson();

      // 只返回当前用户专属的 encryptedGroupKey
      if (g.encryptedGroupKeys != null && g.encryptedGroupKeys!.containsKey(user.id)) {
        groupJson['encryptedGroupKey'] = g.encryptedGroupKeys![user.id];
      } else if (g.creatorId == user.id && g.encryptedGroupKey != null) {
        // 群主使用原有的 encryptedGroupKey
        groupJson['encryptedGroupKey'] = g.encryptedGroupKey;
      }

      groupsWithMemberKey.add(groupJson);
    }

    channel.sink.add(WSMessage(
      type: WSMessageType.loginSuccess,
      id: msg.id,
      payload: {
        'userId': user.id,
        'nickname': user.nickname,
        'groups': groupsWithMemberKey,
        'offlineCount': offlineCount,
      },
    ).toJsonString());

    // 在登录成功后，推送暂存的加入请求
    final pendingRequests = await GroupJoinRequestStore.getRequestsByCreator(user.id);
    for (final request in pendingRequests) {
      final group = await GroupStore.getGroupById(request['groupId'] as String);
      channel.sink.add(WSMessage(
        type: WSMessageType.groupJoinRequest,
        id: UuidGenerator.generate(),
        payload: {
          'requestId': request['requestId'],
          'groupId': request['groupId'],
          'groupName': group?.name ?? '',
          'requesterId': request['requesterId'],
          'requesterNickname': request['requesterNickname'],
        },
      ).toJsonString());

      await GroupJoinRequestStore.deleteRequest(request['requestId'] as String);
    }

    // 推送暂存的群解散通知
    final dissolveNotifications = await GroupDissolveStore.getNotificationsByUser(user.id);
    for (final notification in dissolveNotifications) {
      channel.sink.add(WSMessage(
        type: WSMessageType.groupUpdate,
        id: UuidGenerator.generate(),
        payload: {
          'action': 'dissolved',
          'groupId': notification['groupId'],
          'groupName': notification['groupName'],
        },
      ).toJsonString());

      await GroupDissolveStore.deleteNotification(user.id, notification['groupId'] as String);
    }

    return {'userId': user.id, 'username': user.username};
  }

  Future<void> _handleSendMessage(WebSocketChannel channel, WSMessage msg) async {
    final client = _getClient(channel);
    if (client == null) return;

    final groupId = msg.payload['groupId'] as String;
    final msgType = msg.payload['msgType'] as String;
    final encryptedContent = msg.payload['encryptedContent'] as String;
    final iv = msg.payload['iv'] as String;
    final attachmentJson = msg.payload['attachment'];

    if (!await GroupStore.isMember(groupId, client.userId)) {
      channel.sink.add(WSMessage(
        type: WSMessageType.error,
        id: msg.id,
        payload: {'message': 'Not a member of this group'},
      ).toJsonString());
      return;
    }

    final group = await GroupStore.getGroupById(groupId);
    if (group == null) return;

    final user = await UserStore.getUserById(client.userId);

    final message = MessageModel(
      id: UuidGenerator.generate(),
      groupId: groupId,
      senderId: client.userId,
      senderNickname: user?.nickname ?? 'Unknown',
      type: MessageType.values.firstWhere(
        (e) => e.name == msgType,
        orElse: () => MessageType.text,
      ),
      encryptedContent: encryptedContent,
      iv: iv,
      attachment: attachmentJson != null
          ? FileAttachment.fromJson(attachmentJson as Map<String, dynamic>)
          : null,
      timestamp: DateTime.now().millisecondsSinceEpoch,
      serverId: serverId,
    );

    final jsonMsg = message.toJson();
    jsonMsg['type'] = WSMessageType.msg;

    // for (final memberId in group.memberIds) {
    //   // if (memberId == client.userId) continue;
    //   final targetClient = _connectedClients[memberId];
    //   if (targetClient != null) {
    //     targetClient.channel.sink.add(jsonEncode(jsonMsg));
    //   } else {
    //     await OfflineStore.addOfflineMessage(message, memberId);
    //   }
    // }
    for (final memberId in group.memberIds) {
      // if (memberId == client.userId) continue;
      final targetClient = _connectedClients[memberId];
      if (targetClient != null) {
        // 正确的 WSMessage 格式
        final wsMessage = WSMessage(
          type: WSMessageType.msg,
          id: UuidGenerator.generate(),
          payload: message.toJson(),
        );
        targetClient.channel.sink.add(wsMessage.toJsonString());
      } else {
        await OfflineStore.addOfflineMessage(message, memberId);
      }
    }

    channel.sink.add(WSMessage(
      type: WSMessageType.msgAck,
      id: msg.id,
      payload: {'messageId': message.id},
    ).toJsonString());
  }

  // Future<void> _handleGroupCreate(WebSocketChannel channel, WSMessage msg) async {
  //   final client = _getClient(channel);
  //   if (client == null) return;
  //
  //   final name = msg.payload['name'] as String?;
  //   if (name == null || name.isEmpty) {
  //     channel.sink.add(WSMessage(
  //       type: WSMessageType.error,
  //       id: msg.id,
  //       payload: {'message': 'Group name is required'},
  //     ).toJsonString());
  //     return;
  //   }
  //
  //   final group = GroupModel(
  //     id: UuidGenerator.generate(),
  //     name: name,
  //     inviteCode: UuidGenerator.generateInviteCode(),
  //     creatorId: client.userId,
  //     serverId: serverId,
  //     memberIds: [client.userId],
  //     createdAt: DateTime.now().millisecondsSinceEpoch,
  //   );
  //
  //   await GroupStore.createGroup(group);
  //
  //   channel.sink.add(WSMessage(
  //     type: WSMessageType.groupUpdate,
  //     id: msg.id,
  //     payload: {
  //       'action': 'created',
  //       'group': group.toJson(),
  //     },
  //   ).toJsonString());
  // }
  Future<void> _handleGroupCreate(WebSocketChannel channel, WSMessage msg) async {
    final client = _getClient(channel);
    if (client == null) return;

    final name = msg.payload['name'] as String?;
    if (name == null || name.isEmpty) {
      channel.sink.add(WSMessage(
        type: WSMessageType.error,
        id: msg.id,
        payload: {'message': 'Group name is required'},
      ).toJsonString());
      return;
    }

    // 生成 AES-256 群密钥
    final groupKey = AesCrypto.generateKey();

    // 用创建者的 RSA 公钥加密群密钥
    final user = await UserStore.getUserById(client.userId);
    if (user == null) return;

    final encryptedGroupKey = RsaCrypto.encryptAesKeyForUser(
      groupKey,
      user.rsaPublicKey,
    );

    final group = GroupModel(
      id: UuidGenerator.generate(),
      name: name,
      inviteCode: UuidGenerator.generateInviteCode(),
      creatorId: client.userId,
      serverId: serverId,
      memberIds: [client.userId],
      createdAt: DateTime.now().millisecondsSinceEpoch,
      encryptedGroupKey: base64Encode(encryptedGroupKey),
    );

    await GroupStore.createGroup(group);

    channel.sink.add(WSMessage(
      type: WSMessageType.groupUpdate,
      id: msg.id,
      payload: {
        'action': 'created',
        'group': group.toJson(),
      },
    ).toJsonString());
  }

  // Future<void> _handleGroupJoin(WebSocketChannel channel, WSMessage msg) async {
  //   final client = _getClient(channel);
  //   if (client == null) return;
  //
  //   final inviteCode = msg.payload['inviteCode'] as String?;
  //   if (inviteCode == null) {
  //     channel.sink.add(WSMessage(
  //       type: WSMessageType.error,
  //       id: msg.id,
  //       payload: {'message': 'Invite code is required'},
  //     ).toJsonString());
  //     return;
  //   }
  //
  //   final group = await GroupStore.getGroupByInviteCode(inviteCode);
  //   if (group == null) {
  //     channel.sink.add(WSMessage(
  //       type: WSMessageType.error,
  //       id: msg.id,
  //       payload: {'message': 'Invalid invite code'},
  //     ).toJsonString());
  //     return;
  //   }
  //
  //   if (group.memberIds.contains(client.userId)) {
  //     channel.sink.add(WSMessage(
  //       type: WSMessageType.error,
  //       id: msg.id,
  //       payload: {'message': 'Already a member'},
  //     ).toJsonString());
  //     return;
  //   }
  //
  //   final updatedGroup = group.copyWith(
  //     memberIds: [...group.memberIds, client.userId],
  //   );
  //   await GroupStore.updateGroup(updatedGroup);
  //
  //   channel.sink.add(WSMessage(
  //     type: WSMessageType.groupUpdate,
  //     id: msg.id,
  //     payload: {
  //       'action': 'joined',
  //       'group': updatedGroup.toJson(),
  //     },
  //   ).toJsonString());
  //
  //   for (final memberId in group.memberIds) {
  //     if (memberId == client.userId) continue;
  //     final targetClient = _connectedClients[memberId];
  //     if (targetClient != null) {
  //       targetClient.channel.sink.add(WSMessage(
  //         type: WSMessageType.groupUpdate,
  //         id: UuidGenerator.generate(),
  //         payload: {
  //           'action': 'member_joined',
  //           'groupId': group.id,
  //           'newMemberId': client.userId,
  //         },
  //       ).toJsonString());
  //     }
  //   }
  // }
  // Future<void> _handleGroupJoin(WebSocketChannel channel, WSMessage msg) async {
  //   final client = _getClient(channel);
  //   if (client == null) return;
  //
  //   final inviteCode = msg.payload['inviteCode'] as String?;
  //   if (inviteCode == null) {
  //     channel.sink.add(WSMessage(
  //       type: WSMessageType.error,
  //       id: msg.id,
  //       payload: {'message': 'Invite code is required'},
  //     ).toJsonString());
  //     return;
  //   }
  //
  //   final group = await GroupStore.getGroupByInviteCode(inviteCode);
  //   if (group == null) {
  //     channel.sink.add(WSMessage(
  //       type: WSMessageType.error,
  //       id: msg.id,
  //       payload: {'message': 'Invalid invite code'},
  //     ).toJsonString());
  //     return;
  //   }
  //
  //   if (group.memberIds.contains(client.userId)) {
  //     channel.sink.add(WSMessage(
  //       type: WSMessageType.error,
  //       id: msg.id,
  //       payload: {'message': 'Already a member'},
  //     ).toJsonString());
  //     return;
  //   }
  //
  //   // 用新成员的 RSA 公钥加密群密钥
  //   final newUser = await UserStore.getUserById(client.userId);
  //   if (newUser == null) return;
  //   //
  //   // String? newEncryptedGroupKey = group.encryptedGroupKey;
  //   // if (group.encryptedGroupKey != null) {
  //   //   final groupKeyBytes = base64Decode(group.encryptedGroupKey!);
  //   //   final encryptedForNewUser = RsaCrypto.encryptAesKeyForUser(
  //   //     groupKeyBytes,
  //   //     newUser.rsaPublicKey,
  //   //   );
  //   //   newEncryptedGroupKey = base64Encode(encryptedForNewUser);
  //   // }
  //
  //   final creatorClient = _connectedClients[group.creatorId];
  //   if (creatorClient != null) {
  //     // 通知创建者：有新成员加入，需要重新加密并发送群聊密钥
  //     creatorClient.channel.sink.add(WSMessage(
  //       type: WSMessageType.groupKeyRequest,
  //       id: msg.id,
  //       payload: {
  //         'action': 'new_member',
  //         'groupId': group.id,
  //         'newMemberId': client.userId,
  //         'newMemberPublicKey': newUser.rsaPublicKey,  // 直接从数据库获取
  //       },
  //     ).toJsonString());
  //   }
  //
  //   final updatedGroup = group.copyWith(
  //     memberIds: [...group.memberIds, client.userId],
  //     // encryptedGroupKey: newEncryptedGroupKey,
  //   );
  //   await GroupStore.updateGroup(updatedGroup);
  //
  //   channel.sink.add(WSMessage(
  //     type: WSMessageType.groupUpdate,
  //     id: msg.id,
  //     payload: {
  //       'action': 'joined',
  //       'group': updatedGroup.toJson(),
  //     },
  //   ).toJsonString());
  //
  //   for (final memberId in group.memberIds) {
  //     if (memberId == client.userId) continue;
  //     final targetClient = _connectedClients[memberId];
  //     if (targetClient != null) {
  //       targetClient.channel.sink.add(WSMessage(
  //         type: WSMessageType.groupUpdate,
  //         id: UuidGenerator.generate(),
  //         payload: {
  //           'action': 'member_joined',
  //           'groupId': group.id,
  //           'newMemberId': client.userId,
  //         },
  //       ).toJsonString());
  //     }
  //   }
  // }
  Future<void> _handleGroupJoin(WebSocketChannel channel, WSMessage msg) async {
    final client = _getClient(channel);
    if (client == null) return;

    final inviteCode = msg.payload['inviteCode'] as String?;
    if (inviteCode == null) {
      channel.sink.add(WSMessage(
        type: WSMessageType.error,
        id: msg.id,
        payload: {'message': 'Invite code is required'},
      ).toJsonString());
      return;
    }

    final group = await GroupStore.getGroupByInviteCode(inviteCode);
    if (group == null) {
      channel.sink.add(WSMessage(
        type: WSMessageType.error,
        id: msg.id,
        payload: {'message': 'Invalid invite code'},
      ).toJsonString());
      return;
    }

    if (group.memberIds.contains(client.userId)) {
      channel.sink.add(WSMessage(
        type: WSMessageType.error,
        id: msg.id,
        payload: {'message': 'Already a member'},
      ).toJsonString());
      return;
    }

    final newUser = await UserStore.getUserById(client.userId);
    if (newUser == null) return;

    // 创建加入请求记录
    final requestId = UuidGenerator.generate();
    await GroupJoinRequestStore.addRequest(
      requestId: requestId,
      groupId: group.id,
      requesterId: client.userId,
      requesterNickname: newUser.nickname,
      creatorId: group.creatorId,
      inviteCode: inviteCode,
      timestamp: DateTime.now().millisecondsSinceEpoch,
    );

    // 通知群主
    final creatorClient = _connectedClients[group.creatorId];
    if (creatorClient != null) {
      // 群主在线，立即推送
      creatorClient.channel.sink.add(WSMessage(
        type: WSMessageType.groupJoinRequest,
        id: msg.id,
        payload: {
          'requestId': requestId,
          'groupId': group.id,
          'groupName': group.name,
          'requesterId': client.userId,
          'requesterNickname': newUser.nickname,
        },
      ).toJsonString());
    }
    // 如果群主不在线，请求已存储在数据库中，等上线后推送

    // 通知申请人：请求已提交，等待审批
    channel.sink.add(WSMessage(
      type: WSMessageType.groupJoinRequest,
      id: msg.id,
      payload: {
        'action': 'pending',
        'message': 'Join request submitted, waiting for approval',
      },
    ).toJsonString());
  }

  // Future<void> _handleGroupJoinApprove(WebSocketChannel channel, WSMessage msg) async {
  //   final client = _getClient(channel);
  //   if (client == null) return;
  //
  //   final groupId = msg.payload['groupId'] as String?;
  //   final requesterId = msg.payload['requesterId'] as String?;
  //   if (groupId == null || requesterId == null) return;
  //
  //   final group = await GroupStore.getGroupById(groupId);
  //   if (group == null) return;
  //
  //   // 验证是群主操作
  //   if (group.creatorId != client.userId) return;
  //
  //   // 获取申请人公钥
  //   final requester = await UserStore.getUserById(requesterId);
  //   if (requester == null) return;
  //
  //   // 通知群主：需要重新加密群密钥并发送
  //   // 这里直接转发给群主处理
  //   channel.sink.add(WSMessage(
  //     type: WSMessageType.groupKeyRequest,
  //     id: msg.id,
  //     payload: {
  //       'action': 'approve_join',
  //       'groupId': groupId,
  //       'requesterId': requesterId,
  //       'requesterPublicKey': requester.rsaPublicKey,
  //     },
  //   ).toJsonString());
  // }
  Future<void> _handleGroupJoinApprove(WebSocketChannel channel, WSMessage msg) async {
    final client = _getClient(channel);
    if (client == null) return;

    final groupId = msg.payload['groupId'] as String?;
    final requesterId = msg.payload['requesterId'] as String?;
    final newEncryptedGroupKey = msg.payload['encryptedGroupKey'] as String?;

    if (groupId == null || requesterId == null || newEncryptedGroupKey == null) return;

    final group = await GroupStore.getGroupById(groupId);
    if (group == null) return;

    // 验证是群主操作
    if (group.creatorId != client.userId) return;

    // 获取申请人
    final requester = await UserStore.getUserById(requesterId);
    if (requester == null) return;

    // 检查申请人是否已是成员
    if (group.memberIds.contains(requesterId)) return;

    // 构建每个成员的专属加密密钥
    final Map<String, String> allEncryptedKeys = {};

    // 保留群主专属密钥
    if (group.encryptedGroupKey != null) {
      allEncryptedKeys[group.creatorId] = group.encryptedGroupKey!;
    }

    // 保留其他已有成员的密钥
    if (group.encryptedGroupKeys != null) {
      allEncryptedKeys.addAll(group.encryptedGroupKeys!);
    }

    // 添加新成员的专属密钥
    allEncryptedKeys[requesterId] = newEncryptedGroupKey;

    final updatedGroup = group.copyWith(
      memberIds: [...group.memberIds, requesterId],
      encryptedGroupKeys: allEncryptedKeys,
    );
    await GroupStore.updateGroup(updatedGroup);

    // 通知申请人：加入成功，发送群信息和加密密钥
    final requesterClient = _connectedClients[requesterId];
    if (requesterClient != null) {
      requesterClient.channel.sink.add(WSMessage(
        type: WSMessageType.groupJoinResult,
        id: msg.id,
        payload: {
          'action': 'approved',
          'groupId': groupId,
          'group': updatedGroup.toJson(),
          'encryptedGroupKey': newEncryptedGroupKey,
        },
      ).toJsonString());
    }

    // 通知群主和其他成员
    channel.sink.add(WSMessage(
      type: WSMessageType.groupUpdate,
      id: msg.id,
      payload: {
        'action': 'member_joined',
        'groupId': groupId,
        'group': updatedGroup.toJson(),
        'newMemberId': requesterId,
      },
    ).toJsonString());

    for (final memberId in group.memberIds) {
      if (memberId == client.userId || memberId == requesterId) continue;
      final targetClient = _connectedClients[memberId];
      if (targetClient != null) {
        targetClient.channel.sink.add(WSMessage(
          type: WSMessageType.groupUpdate,
          id: UuidGenerator.generate(),
          payload: {
            'action': 'member_joined',
            'groupId': groupId,
            'group': updatedGroup.toJson(),
            'newMemberId': requesterId,
          },
        ).toJsonString());
      }
    }

    // 删除暂存的请求
    await GroupJoinRequestStore.deleteRequestsByCreator(client.userId);
  }

  Future<void> _handleGroupJoinReject(WebSocketChannel channel, WSMessage msg) async {
    final client = _getClient(channel);
    if (client == null) return;

    final groupId = msg.payload['groupId'] as String?;
    final requesterId = msg.payload['requesterId'] as String?;
    if (groupId == null || requesterId == null) return;

    // 通知申请人被拒绝
    final requesterClient = _connectedClients[requesterId];
    if (requesterClient != null) {
      requesterClient.channel.sink.add(WSMessage(
        type: WSMessageType.groupJoinResult,
        id: msg.id,
        payload: {
          'groupId': groupId,
          'action': 'rejected',
          'message': 'Join request rejected by group owner',
        },
      ).toJsonString());
    }

    // 删除暂存的请求
    await GroupJoinRequestStore.deleteRequestsByCreator(client.userId);
  }

  Future<void> _handleGroupList(WebSocketChannel channel, WSMessage msg) async {
    final client = _getClient(channel);
    if (client == null) return;

    final groups = await GroupStore.getGroupsByMember(client.userId);
    channel.sink.add(WSMessage(
      type: WSMessageType.groupList,
      id: msg.id,
      payload: {
        'groups': groups.map((g) => g.toJson()).toList(),
      },
    ).toJsonString());
  }

  Future<void> _handleOfflineFetch(WebSocketChannel channel, WSMessage msg) async {
    final client = _getClient(channel);
    if (client == null) return;

    final page = msg.payload['page'] as int? ?? 1;
    final pageSize = msg.payload['pageSize'] as int? ?? 50;

    final messages = await OfflineStore.getOfflineMessages(
      client.userId,
      page: page,
      pageSize: pageSize,
    );
    final totalCount = await OfflineStore.getOfflineCount(client.userId);

    // for (final message in messages) {
    //   final jsonMsg = message.toJson();
    //   jsonMsg['type'] = WSMessageType.msg;
    //   channel.sink.add(jsonEncode(jsonMsg));
    //   await OfflineStore.markDelivered(client.userId, message.id);
    // }
    for (final message in messages) {
      final jsonMsg = message.toJson();
      // jsonMsg['type'] = WSMessageType.msg;

      // 使用 WSMessage 包装
      final wsMessage = WSMessage(
        type: WSMessageType.msg,
        id: UuidGenerator.generate(),
        payload: jsonMsg,
      );
      channel.sink.add(wsMessage.toJsonString());

      await OfflineStore.markDelivered(client.userId, message.id);
    }

    channel.sink.add(WSMessage(
      type: WSMessageType.offlinePage,
      id: msg.id,
      payload: {
        'page': page,
        'pageSize': pageSize,
        'totalCount': totalCount,
        'hasMore': totalCount > page * pageSize,
      },
    ).toJsonString());
  }

  Future<void> _handleAck(WebSocketChannel channel, WSMessage msg) async {
    final client = _getClient(channel);
    if (client == null) return;
    final messageId = msg.payload['messageId'] as String?;
    if (messageId != null) {
      await OfflineStore.markDelivered(client.userId, messageId);
    }
  }

  Future<void> _handleLeaveGroup(WebSocketChannel channel, WSMessage msg) async {
    final client = _getClient(channel);
    if (client == null) return;

    final groupId = msg.payload['groupId'] as String?;
    if (groupId == null) return;

    final group = await GroupStore.getGroupById(groupId);
    if (group == null) return;
    if (!group.memberIds.contains(client.userId)) return;

    // 如果是群主，解散群
    if (group.creatorId == client.userId) {
      await GroupStore.deleteGroup(groupId);

      channel.sink.add(WSMessage(
        type: WSMessageType.groupUpdate,
        id: msg.id,
        payload: {
          'action': 'dissolved',
          'groupId': groupId,
          'groupName': group.name,
        },
      ).toJsonString());

      for (final memberId in group.memberIds) {
        if (memberId == client.userId) continue;
        final targetClient = _connectedClients[memberId];
        if (targetClient != null) {
          targetClient.channel.sink.add(WSMessage(
            type: WSMessageType.groupUpdate,
            id: UuidGenerator.generate(),
            payload: {
              'action': 'dissolved',
              'groupId': groupId,
              'groupName': group.name,
            },
          ).toJsonString());
        } else {
          await GroupDissolveStore.addNotification(groupId, group.name, memberId);
        }
      }
      return;
    }

    // 非群主退群
    final updatedGroup = group.copyWith(
      memberIds: group.memberIds.where((id) => id != client.userId).toList(),
    );
    await GroupStore.updateGroup(updatedGroup);

    channel.sink.add(WSMessage(
      type: WSMessageType.groupUpdate,
      id: msg.id,
      payload: {
        'action': 'left',
        'groupId': groupId,
      },
    ).toJsonString());

    // 广播给其他成员
    for (final memberId in group.memberIds) {
      if (memberId == client.userId) continue;
      final targetClient = _connectedClients[memberId];
      if (targetClient != null) {
        targetClient.channel.sink.add(WSMessage(
          type: WSMessageType.groupUpdate,
          id: UuidGenerator.generate(),
          payload: {
            'action': 'member_left',
            'groupId': groupId,
            'group': updatedGroup.toJson(),
            'leftMemberId': client.userId,
          },
        ).toJsonString());
      }
    }
  }

  // Future<void> _handleFileUploadStart(WebSocketChannel channel, WSMessage msg) async {
  //   _getClient(channel);
  //   final fileId = UuidGenerator.generate();
  //   _fileBuffers[fileId] = [];
  //
  //   channel.sink.add(WSMessage(
  //     type: WSMessageType.fileUpload,
  //     id: msg.id,
  //     payload: {'fileId': fileId},
  //   ).toJsonString());
  // }
  Future<void> _handleFileUploadStart(WebSocketChannel channel, WSMessage msg) async {
    _getClient(channel);
    final fileId = msg.payload['fileId'] as String?;  // 使用客户端的 fileId
    if (fileId == null) return;

    _fileBuffers[fileId] = [];

    channel.sink.add(WSMessage(
      type: WSMessageType.fileUpload,
      id: msg.id,
      payload: {'fileId': fileId},
    ).toJsonString());
  }

  Future<void> _handleFileData(WebSocketChannel channel, WSMessage msg) async {
    final fileId = msg.payload['fileId'] as String?;
    final data = msg.payload['data'] as String?;
    if (fileId == null || data == null) return;

    final buffer = _fileBuffers[fileId];
    if (buffer != null) {
      buffer.addAll(base64Decode(data));
    }
  }

  Future<void> _handleFileComplete(WebSocketChannel channel, WSMessage msg) async {
    _getClient(channel);
    final fileId = msg.payload['fileId'] as String?;
    // final fileName = msg.payload['fileName'] as String?;
    // final mimeType = msg.payload['mimeType'] as String?;
    if (fileId == null) return;

    final data = _fileBuffers[fileId];
    if (data != null) {
      await ServerFileStorage.saveFile(fileId, data);
      _fileBuffers.remove(fileId);

      channel.sink.add(WSMessage(
        type: WSMessageType.fileComplete,
        id: msg.id,
        payload: {
          'fileId': fileId,
          // 'fileName': fileName,
          'fileSize': data.length,
          // 'mimeType': mimeType,
        },
      ).toJsonString());
    }
  }

  Future<void> _handleFileDownload(WebSocketChannel channel, WSMessage msg) async {
    _getClient(channel);
    final fileId = msg.payload['fileId'] as String?;
    if (fileId == null) return;

    final data = await ServerFileStorage.getFile(fileId);
    if (data != null) {
      channel.sink.add(WSMessage(
        type: WSMessageType.fileData,
        id: msg.id,
        payload: {
          'fileId': fileId,
          'data': base64Encode(data),
          'complete': true,
        },
      ).toJsonString());
    } else {
      channel.sink.add(WSMessage(
        type: WSMessageType.error,
        id: msg.id,
        payload: {'message': 'File not found'},
      ).toJsonString());
    }
  }

  ConnectedClient? _getClient(WebSocketChannel channel) {
    return _connectedClients.values.firstWhere(
      (c) => c.channel == channel,
      orElse: () => throw Exception('Not authenticated'),
    );
  }

  Future<Response> _handleRequest(Request request) async {
    if (request.url.path == 'ws') {
      return webSocketHandler((channel) {
        _handleWebSocket(channel as WebSocketChannel);
      })(request);
    }
    return Response.ok('Cliff Messenger Server');
  }
}
