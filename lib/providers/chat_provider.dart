import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../../core/crypto/aes_crypto.dart';
import '../../core/crypto/rsa_crypto.dart';
import '../../core/network/protocol.dart';
import '../../core/utils/utils.dart';
import '../../models/message.dart';
import '../../models/group.dart';
import '../../client/db/message_store.dart';
import '../../client/websocket_client.dart';
import '../client/db/client_db.dart';
import '../client/storage/file_storage.dart';

class ChatProvider extends ChangeNotifier {
  GroupModel? _activeGroup;
  final List<MessageModel> _messages = [];
  bool _loading = false;
  String? _error;
  int _offlinePage = 1;
  int _totalOfflineCount = 0;
  bool _hasMoreOffline = false;
  final Map<String, Uint8List> _groupKeys = {};
  final Map<String, String> _decryptedMessages = {};
  VoidCallback? _onMessageAdded;

  GroupModel? get activeGroup => _activeGroup;
  List<MessageModel> get messages => _messages;
  bool get loading => _loading;
  String? get error => _error;
  int get totalOfflineCount => _totalOfflineCount;
  bool get hasMoreOffline => _hasMoreOffline;

  void setActiveGroup(GroupModel? group) {
    _activeGroup = group;
    _messages.clear();
    notifyListeners();
  }

  void setOnMessageAddedCallback(VoidCallback? callback) {
    _onMessageAdded = callback;
  }

  String? getDecryptedContent(String messageId) {
    return _decryptedMessages[messageId];
  }

  Uint8List? getGroupKey(String groupId) {
    return _groupKeys[groupId];
  }

  Future<void> loadMessages(String groupId) async {
    _loading = true;
    _decryptedMessages.clear();

    try {
      final stored = await MessageStore.getMessagesByGroup(groupId, limit: 50, userId: ClientDb.currentUserId);
      _messages.clear();
      // stored 是 DESC 排序（最新在前），reversed 后变成旧→新
      for (final message in stored.reversed) {
        _messages.add(message);
        _decryptAndCacheMessage(message);
      }

      _loading = false;
      notifyListeners();
    } catch (e) {
      _error = e.toString();
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> loadMoreMessages(String groupId) async {
    if (_messages.isEmpty) return;
    _loading = true;

    try {
      // 获取比当前最旧消息更早的消息
      final oldestMessage = _messages.first;
      final stored = await MessageStore.getMessagesByGroupBefore(
        groupId,
        beforeTimestamp: oldestMessage.timestamp,
        limit: 50,
        userId: ClientDb.currentUserId,
      );

      // 插入到列表最前面（最旧的位置）
      for (final message in stored.reversed) {
        _messages.insert(0, message);
        _decryptAndCacheMessage(message);
      }

      _loading = false;
      notifyListeners();
    } catch (e) {
      _loading = false;
      notifyListeners();
    }
  }

  void _decryptAndCacheMessage(MessageModel message) {
    final groupKey = _groupKeys[message.groupId];
    if (groupKey != null) {
      try {
        final decrypted = decryptMessage(message, groupKey);
        _decryptedMessages[message.id] = decrypted;
      } catch (e) {
        _decryptedMessages[message.id] = '[Decryption Failed]';
      }
    }
  }

  Future<void> sendTextMessage(
      ServerConnection connection, String privateKeyPem, String text) async {
    if (_activeGroup == null) return;

    try {
      final groupKey = await _getGroupKey(connection, _activeGroup!, privateKeyPem);
      if (groupKey == null) {
        _error = 'No group key available';
        notifyListeners();
        return;
      }

      final encrypted = AesCrypto.encryptText(text, groupKey);

      connection.sendMessage(
        _activeGroup!.id,
        MessageType.text.name,
        encrypted['content']!,
        encrypted['iv']!,
      );
    } catch (e) {
      _error = 'Failed to send: $e';
      notifyListeners();
    }
  }

  Future<void> sendFileMessage(
      ServerConnection connection, String privateKeyPem,
      {required String filePath, required bool isImage}) async {
    if (_activeGroup == null) return;

    try {
      final fileData = await FileUtils.readFileBytes(filePath);
      final fileName = FileUtils.getFileName(filePath);
      final mimeType = FileUtils.getMimeType(filePath);

      final groupKey = await _getGroupKey(connection, _activeGroup!, privateKeyPem);
      if (groupKey == null) {
        _error = 'No group key available';
        notifyListeners();
        return;
      }

      final fileKey = AesCrypto.generateKey();
      final encryptResult = await compute(computeEncryptFile, {
        'fileData': fileData,
        'key': fileKey,
      });
      final encryptedFile = encryptResult['encrypted'] as Uint8List;
      final encryptedFileKey = AesCrypto.encryptKey(fileKey, groupKey);

      final fileId = UuidGenerator.generate();
      final attachment = FileAttachment(
        fileId: fileId,
        fileName: fileName,
        fileSize: fileData.length,
        mimeType: mimeType,
      );

      final encrypted = AesCrypto.encryptText(
        jsonEncode({
          'fileKey': base64Encode(encryptedFileKey),
          'fileSize': fileData.length,
        }),
        groupKey,
      );

      await connection.uploadFile(fileId, encryptedFile);

      connection.sendMessage(
        _activeGroup!.id,
        (isImage ? MessageType.image : MessageType.file).name,
        encrypted['content']!,
        encrypted['iv']!,
        attachment: attachment,
      );
    } catch (e) {
      _error = 'Failed to send file: $e';
      notifyListeners();
    }
  }

  Future<void> loadOfflineMessages(ServerConnection connection) async {
    if (_totalOfflineCount == 0) return;

    _loading = true;
    notifyListeners();

    connection.requestOffline(_offlinePage, 50);
  }

  void handleIncomingMessage(WSMessage msg) {
    if (msg.type == WSMessageType.msg) {
      try {
        final message = MessageModel.fromJson(msg.payload);
        _messages.add(message);
        _decryptAndCacheMessage(message);  // 解密并缓存
        notifyListeners();
        _onMessageAdded?.call();
      } catch (e) {
        // ignore errors
      }
    } else if (msg.type == WSMessageType.offlinePage) {
      _offlinePage = (msg.payload['page'] as int?) ?? 1;
      _totalOfflineCount = (msg.payload['totalCount'] as int?) ?? 0;
      _hasMoreOffline = (msg.payload['hasMore'] as bool?) ?? false;
      _loading = false;
      notifyListeners();
    } else if (msg.type == WSMessageType.msgAck) {
      // message acknowledged by server
    }
  }

  Future<Uint8List?> _getGroupKey(ServerConnection connection, GroupModel group, String privateKeyPem) async {
    if (_groupKeys.containsKey(group.id)) {
      return _groupKeys[group.id];
    }

    if (group.encryptedGroupKey != null && privateKeyPem.isNotEmpty) {
      try {
        final privateKey = RsaCrypto.privateKeyFromPem(privateKeyPem);
        final encryptedKeyBytes = base64Decode(group.encryptedGroupKey!);
        final groupKey = RsaCrypto.decryptAesKeyForUser(encryptedKeyBytes, privateKey);
        _groupKeys[group.id] = groupKey;
        return groupKey;
      } catch (e) {
        _error = 'Failed to decrypt group key: $e';
        notifyListeners();
      }
    }

    return null;
  }

  void setGroupKey(String groupId, Uint8List key) {
    _groupKeys[groupId] = key;
  }

  String decryptMessage(MessageModel message, Uint8List groupKey) {
    return AesCrypto.decryptText(
      message.encryptedContent,
      message.iv,
      groupKey,
    );
  }

  Future<void> downloadAndDecryptFile(
      ServerConnection connection,
      String fileId,
      String privateKeyPem,
      GroupModel group,
      ) async {
    try {
      final groupKey = await _getGroupKey(connection, group, privateKeyPem);
      if (groupKey == null) {
        _error = 'No group key available';
        notifyListeners();
        return;
      }

      connection.requestFileDownload(fileId);

      final completer = Completer<void>();
      StreamSubscription? subscription;

      subscription = connection.fileDownloadComplete.listen((data) async {
        final downloadFileId = data['fileId'] as String;
        final encryptedFile = data['encryptedFile'] as Uint8List;

        if (downloadFileId == fileId) {
          await subscription?.cancel();  // 使用 ?. 安全取消

          try {
            final message = _messages.firstWhere(
                  (m) => m.attachment?.fileId == fileId,
              orElse: () => throw Exception('Message not found'),
            );

            final fileMetadata = _decryptFileMetadata(message, groupKey);
            final encryptedFileKey = base64Decode(fileMetadata['fileKey'] as String);
            final fileKey = AesCrypto.decryptKey(encryptedFileKey, groupKey);
            final decryptResult = await compute(computeDecryptFile, {
              'encryptedData': encryptedFile,
              'key': fileKey,
            });
            final decryptedFile = decryptResult['decrypted'] as Uint8List;

            // await ClientFileStorage.saveFile(fileId, decryptedFile);
            await ClientFileStorage.saveFile(fileId, decryptedFile, fileName: message.attachment?.fileName);
            notifyListeners();
          } catch (e) {
            _error = 'Failed to decrypt file: $e';
            notifyListeners();
          }

          completer.complete();
        }
      });

      await completer.future;
    } catch (e) {
      _error = 'Failed to download file: $e';
      notifyListeners();
    }
  }

  Map<String, dynamic> _decryptFileMetadata(MessageModel message, Uint8List groupKey) {
    // 从消息的 encryptedContent 中解密出 fileKey 元数据
    final decryptedText = AesCrypto.decryptText(
      message.encryptedContent,
      message.iv,
      groupKey,
    );
    return jsonDecode(decryptedText) as Map<String, dynamic>;
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }

  void clear() {
    _activeGroup = null;
    _messages.clear();
    _loading = false;
    _error = null;
    _offlinePage = 1;
    _totalOfflineCount = 0;
    _hasMoreOffline = false;
    _groupKeys.clear();
    notifyListeners();
  }
}