import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/io.dart';
import 'package:logging/logging.dart';
import '../../core/network/protocol.dart';
import '../../core/utils/utils.dart';
import '../../core/constants/app_strings.dart';
import '../../models/group.dart';
import '../../models/message.dart';
import '../../models/server_config.dart';
import '../core/crypto/rsa_crypto.dart';
import 'db/client_db.dart';
import 'db/message_store.dart';
import 'db/server_store.dart';

enum ConnectionStatus { disconnected, connecting, connected, error }

class ServerConnection {
  ServerConfig config;
  WebSocketChannel? _channel;
  ConnectionStatus _status = ConnectionStatus.disconnected;
  String? _connectionError;
  final _messageController = StreamController<WSMessage>.broadcast();
  final _statusController = StreamController<ConnectionStatus>.broadcast();
  Timer? _pingTimer;
  final _logger = Logger('ServerConnection');

  String? _userId;
  String? _nickname;
  List<GroupModel> _groups = [];
  Uint8List? _groupKey;

  ServerConnection(this.config);

  ConnectionStatus get status => _status;
  String? get connectionError => _connectionError;
  Stream<WSMessage> get messages => _messageController.stream;
  Stream<ConnectionStatus> get statusStream => _statusController.stream;
  String? get userId => _userId;
  String? get nickname => _nickname;
  List<GroupModel> get groups => _groups;
  Uint8List? get groupKey => _groupKey;

  final Map<String, List<int>> _fileDownloadBuffers = {};
  // final Map<String, Map<String, dynamic>> _fileDownloadMetadata = {};
  final Map<String, Completer<String?>> _userPublicKeyCompleters = {};
  final _fileDownloadCompleteController = StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get fileDownloadComplete => _fileDownloadCompleteController.stream;

  Future<bool> connect() async {
    _connectionError = null;
    try {
      _setStatus(ConnectionStatus.connecting);
      final wsUrl = '${config.wsUrl}/ws';

      final socket = await WebSocket.connect(wsUrl).timeout(
        const Duration(seconds: 5),
        onTimeout: () {
          throw TimeoutException(AppStrings.connectionTimeout);
        },
      );

      _channel = IOWebSocketChannel(socket);

      _channel!.stream.listen(
        _onMessage,
        onError: _onError,
        onDone: _onDone,
      );

      _setStatus(ConnectionStatus.connected);
      _startPing();
      return true;
    } on TimeoutException {
      _connectionError = AppStrings.connectionTimeout;
      _setStatus(ConnectionStatus.error);
      _logger.warning('Connection timeout: ${config.displayName}');
      return false;
    } catch (e) {
      _connectionError = e.toString();
      _setStatus(ConnectionStatus.error);
      _logger.warning('Connection failed: ${config.displayName} - $e');
      return false;
    }
  }

  void disconnect() {
    _pingTimer?.cancel();
    _channel?.sink.close();
    _channel = null;
    _connectionError = null;
    _setStatus(ConnectionStatus.disconnected);
  }

  void send(WSMessage message) {
    if (_channel != null && _status == ConnectionStatus.connected) {
      _channel!.sink.add(message.toJsonString());
    }
  }

  Future<void> register(String username, String nickname, String password, String rsaPublicKey) async {
    send(WSMessage.register(username, nickname, password, rsaPublicKey));
  }

  Future<void> login(String username, String password) async {
    send(WSMessage.login(username, password));
  }

  Future<void> sendMessage(String groupId, String msgType, String encryptedContent,
      String iv, {FileAttachment? attachment}) async {
    send(WSMessage.sendMessage(
      groupId,
      msgType,
      encryptedContent,
      iv,
      attachment: attachment?.toJson(),
    ));
  }

  Future<void> createGroup(String name) async {
    send(WSMessage.createGroup(name));
  }

  Future<void> joinGroup(String inviteCode) async {
    send(WSMessage.joinGroup(inviteCode));
  }

  Future<void> requestGroups() async {
    send(WSMessage.requestGroups());
  }

  Future<void> requestOffline(int page, int pageSize) async {
    send(WSMessage.requestOffline(page, pageSize));
  }

  Future<void> leaveGroup(String groupId) async {
    send(WSMessage.leaveGroup(groupId));
  }

  Future<void> uploadFile(String fileId, List<int> data) async {
    final chunkSize = 65536;
    send(WSMessage(
      type: WSMessageType.fileUpload,
      id: UuidGenerator.generate(),
      payload: {'fileId': fileId},
    ));

    for (int i = 0; i < data.length; i += chunkSize) {
      final chunk = data.sublist(i, i + chunkSize > data.length ? data.length : i + chunkSize);
      send(WSMessage(
        type: WSMessageType.fileData,
        id: UuidGenerator.generate(),
        payload: {
          'fileId': fileId,
          'data': base64Encode(chunk),
        },
      ));
      await Future.delayed(Duration.zero);
    }

    send(WSMessage(
      type: WSMessageType.fileComplete,
      id: UuidGenerator.generate(),
      payload: {'fileId': fileId},
    ));
  }

  void requestFileDownload(String fileId) {
    send(WSMessage(
      type: WSMessageType.fileDownload,
      id: UuidGenerator.generate(),
      payload: {'fileId': fileId},
    ));
  }

  void _onMessage(dynamic data) {
    try {
      final msg = WSMessage.fromRaw(data as String);
      _handleIncomingMessage(msg);
      _messageController.add(msg);
    } catch (e) {
      _logger.warning('Error parsing message: $e');
    }
  }

  // void _handleIncomingMessage(WSMessage msg) {
  //   switch (msg.type) {
  //     case WSMessageType.loginSuccess:
  //       _userId = msg.payload['userId'] as String?;
  //       _nickname = msg.payload['nickname'] as String?;
  //       if (msg.payload['groups'] != null) {
  //         _groups = (msg.payload['groups'] as List)
  //             .map((g) => GroupModel.fromJson(g as Map<String, dynamic>))
  //             .toList();
  //       }
  //       _updateServerConfig();
  //       break;
  //     case WSMessageType.groupUpdate:
  //       final action = msg.payload['action'] as String?;
  //       if (action == 'created' || action == 'joined') {
  //         final group = GroupModel.fromJson(msg.payload['group'] as Map<String, dynamic>);
  //         _groups = [..._groups.where((g) => g.id != group.id), group];
  //       } else if (action == 'left') {
  //         final groupId = msg.payload['groupId'] as String?;
  //         if (groupId != null) {
  //           _groups = _groups.where((g) => g.id != groupId).toList();
  //         }
  //       } else if (action == 'member_joined') {
  //         final groupId = msg.payload['groupId'] as String?;
  //         if (groupId != null) {
  //           final idx = _groups.indexWhere((g) => g.id == groupId);
  //           if (idx >= 0) {
  //             requestGroups();
  //           }
  //         }
  //       }
  //       break;
  //     case WSMessageType.groupList:
  //       if (msg.payload['groups'] != null) {
  //         _groups = (msg.payload['groups'] as List)
  //             .map((g) => GroupModel.fromJson(g as Map<String, dynamic>))
  //             .toList();
  //       }
  //       break;
  //     case WSMessageType.msg:
  //       _saveMessageLocally(msg);
  //       break;
  //   }
  // }
  void _handleIncomingMessage(WSMessage msg) {
    switch (msg.type) {
      case WSMessageType.loginSuccess:
        _userId = msg.payload['userId'] as String?;
        _nickname = msg.payload['nickname'] as String?;
        if (msg.payload['groups'] != null) {
          _groups = (msg.payload['groups'] as List)
              .map((g) => GroupModel.fromJson(g as Map<String, dynamic>))
              .toList();
        }
        _updateServerConfig();
        break;
      case WSMessageType.groupUpdate:
        final action = msg.payload['action'] as String?;
        if (action == 'created' || action == 'joined') {
          final group = GroupModel.fromJson(msg.payload['group'] as Map<String, dynamic>);
          _groups = [..._groups.where((g) => g.id != group.id), group];
        } else if (action == 'left') {
          final groupId = msg.payload['groupId'] as String?;
          if (groupId != null) {
            _groups = _groups.where((g) => g.id != groupId).toList();
          }
        } else if (action == 'member_joined') {
          final groupId = msg.payload['groupId'] as String?;
          if (groupId != null) {
            final idx = _groups.indexWhere((g) => g.id == groupId);
            if (idx >= 0) {
              requestGroups();
            }
          }
        }
        break;
      case WSMessageType.groupList:
        if (msg.payload['groups'] != null) {
          _groups = (msg.payload['groups'] as List)
              .map((g) => GroupModel.fromJson(g as Map<String, dynamic>))
              .toList();
        }
        break;
      case WSMessageType.msg:
        _saveMessageLocally(msg);
        break;
      case WSMessageType.fileData:
        _handleFileDataReceived(msg);
        break;
      // case WSMessageType.groupKeyTransfer:
      //   _handleGroupKeyTransfer(msg);
      //   break;
      // case WSMessageType.groupJoinRequest:
      //   _handleGroupJoinRequest(msg);
      //   break;
      // case WSMessageType.groupJoinResult:
      //   _handleGroupJoinResult(msg);
      //   break;
      // case WSMessageType.groupKeyRequest:
      //   _handleGroupKeyRequest(msg);
      //   break;
      case WSMessageType.userPublicKey:
        _handleUserPublicKeyResponse(msg);
        break;
    }
  }

  // void _handleGroupKeyTransfer(WSMessage msg) {
  //   // 转发给 AuthProvider 处理
  //   // 或者直接存储到本地等待 AuthProvider 处理
  //   // _messageController.add(msg);
  // }
  //
  // void _handleGroupJoinRequest(WSMessage msg) {
  //   // _messageController.add(msg);
  // }
  //
  // void _handleGroupJoinResult(WSMessage msg) {
  //   // _messageController.add(msg);
  // }
  //
  // void _handleGroupKeyRequest(WSMessage msg) {
  //   // _messageController.add(msg);
  // }

  void _handleUserPublicKeyResponse(WSMessage msg) {
    // 查找等待此响应的 Completer 并完成
    final userId = msg.payload['userId'] as String?;
    if (userId != null && _userPublicKeyCompleters.containsKey(userId)) {
      _userPublicKeyCompleters[userId]?.complete(
        msg.payload['publicKey'] as String?,
      );
      _userPublicKeyCompleters.remove(userId);
    }
  }

  void _handleFileDataReceived(WSMessage msg) {
    final fileId = msg.payload['fileId'] as String?;
    final data = msg.payload['data'] as String?;
    final complete = msg.payload['complete'] as bool? ?? false;

    if (fileId == null || data == null) return;

    // 累积文件数据
    _fileDownloadBuffers.putIfAbsent(fileId, () => []);
    _fileDownloadBuffers[fileId]!.addAll(base64Decode(data));

    if (complete) {
      // 触发下载完成回调
      final encryptedFile = Uint8List.fromList(_fileDownloadBuffers[fileId]!);
      _fileDownloadBuffers.remove(fileId);

      // 通知 ChatProvider 处理解密
      _fileDownloadCompleteController.add({
        'fileId': fileId,
        'encryptedFile': encryptedFile,
      });
    }
  }

  void decryptAndCacheGroupKey(String groupId, String privateKeyPem) {
    final group = _groups.firstWhere(
          (g) => g.id == groupId,
      orElse: () => throw Exception('Group not found'),
    );

    if (group.encryptedGroupKey != null && privateKeyPem.isNotEmpty) {
      try {
        final privateKey = RsaCrypto.privateKeyFromPem(privateKeyPem);
        final encryptedKeyBytes = base64Decode(group.encryptedGroupKey!);
        _groupKey = RsaCrypto.decryptAesKeyForUser(encryptedKeyBytes, privateKey);
      } catch (e) {
        _logger.warning('Failed to decrypt group key: $e');
      }
    }
  }

  void _saveMessageLocally(WSMessage msg) {
    try {
      final message = MessageModel.fromJson(msg.payload);
      MessageStore.insertMessage(message, config.id, userId: ClientDb.currentUserId);
    } catch (e) {
      _logger.warning('Error saving message locally: $e');
    }
  }

  // 请求获取用户公钥
  void requestUserPublicKey(String userId) {
    send(WSMessage(
      type: WSMessageType.getUserPublicKey,
      id: UuidGenerator.generate(),
      payload: {'userId': userId},
    ));
  }

// 发送群聊密钥给指定用户
  void sendGroupKeyToUser(String userId, String groupId, String encryptedKey) {
    send(WSMessage(
      type: WSMessageType.groupKeyTransfer,
      id: UuidGenerator.generate(),
      payload: {
        'userId': userId,
        'groupId': groupId,
        'encryptedKey': encryptedKey,
      },
    ));
  }

  void _onError(dynamic error) {
    _logger.severe('WebSocket error: $error');
    if (_status == ConnectionStatus.connected) {
      _connectionError = error.toString();
    }
    _setStatus(ConnectionStatus.error);
  }

  void _onDone() {
    _pingTimer?.cancel();
    _setStatus(ConnectionStatus.disconnected);
  }

  void _setStatus(ConnectionStatus status) {
    _status = status;
    _statusController.add(status);
  }

  void _startPing() {
    _pingTimer?.cancel();
    _pingTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (_status == ConnectionStatus.connected) {
        send(WSMessage.ping());
      }
    });
  }

  void _updateServerConfig() {
    ServerStore.saveServer(config.copyWith(
      currentUserId: _userId,
      currentNickname: _nickname,
    ));
  }

  void dispose() {
    disconnect();
    _messageController.close();
    _statusController.close();
  }

  void updateConfig(ServerConfig newConfig) {
    config = newConfig;
  }

  // 请求用户公钥并等待响应
  Future<String?> requestUserPublicKeyWithResponse(String userId) async {
    final completer = Completer<String?>();
    _userPublicKeyCompleters[userId] = completer;

    send(WSMessage(
      type: WSMessageType.getUserPublicKey,
      id: UuidGenerator.generate(),
      payload: {'userId': userId},
    ));

    try {
      return await completer.future.timeout(const Duration(seconds: 10));
    } finally {
      _userPublicKeyCompleters.remove(userId);
    }
  }
}
