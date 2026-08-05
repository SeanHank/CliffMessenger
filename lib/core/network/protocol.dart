import 'dart:convert';
import '../../core/utils/utils.dart';

class WSMessageType {
  static const serverInfo = 'server_info';
  static const serverInfoResponse = 'server_info_response';
  static const register = 'register';
  static const login = 'login';
  static const loginSuccess = 'login_success';
  static const loginFailed = 'login_failed';
  static const registerSuccess = 'register_success';
  static const registerFailed = 'register_failed';
  static const msg = 'msg';
  static const msgAck = 'msg_ack';
  static const groupCreate = 'group_create';
  static const groupJoin = 'group_join';
  static const groupList = 'group_list';
  static const groupUpdate = 'group_update';
  static const groupKeyTransfer = 'group_key_transfer';
  static const groupKeyRequest = 'group_key_request';
  static const groupJoinRequest = 'group_join_request';       // 群主收到的加入申请
  static const groupJoinApprove = 'group_join_approve';       // 群主同意加入
  static const groupJoinReject = 'group_join_reject';         // 群主拒绝加入
  static const groupJoinResult = 'group_join_result';         // 通知申请人结果
  static const userPublicKey = 'user_public_key';
  static const getUserPublicKey = 'get_user_public_key';
  static const fileUpload = 'file_upload';
  static const fileDownload = 'file_download';
  static const fileData = 'file_data';
  static const fileComplete = 'file_complete';
  static const offlineFetch = 'offline_fetch';
  static const offlinePage = 'offline_page';
  static const ping = 'ping';
  static const pong = 'pong';
  static const error = 'error';
  static const leaveGroup = 'leave_group';
}

class WSMessage {
  final String type;
  final String id;
  final Map<String, dynamic> payload;

  WSMessage({
    required this.type,
    required this.id,
    required this.payload,
  });

  Map<String, dynamic> toJson() => {
        'type': type,
        'id': id,
        'payload': payload,
      };

  String toJsonString() => jsonEncode(toJson());

  factory WSMessage.fromJson(Map<String, dynamic> json) => WSMessage(
        type: json['type'] as String,
        id: json['id'] as String,
        payload: json['payload'] as Map<String, dynamic>,
      );

  factory WSMessage.fromRaw(String raw) {
    final json = jsonDecode(raw) as Map<String, dynamic>;
    return WSMessage.fromJson(json);
  }

  static WSMessage requestServerInfo() {
    return WSMessage(
      type: WSMessageType.serverInfo,
      id: UuidGenerator.generate(),
      payload: {},
    );
  }

  static WSMessage register(String username, String nickname, String password, String rsaPublicKey) {
    return WSMessage(
      type: WSMessageType.register,
      id: UuidGenerator.generate(),
      payload: {
        'username': username,
        'nickname': nickname,
        'password': password,
        'rsaPublicKey': rsaPublicKey,
      },
    );
  }

  static WSMessage login(String username, String password) {
    return WSMessage(
      type: WSMessageType.login,
      id: UuidGenerator.generate(),
      payload: {
        'username': username,
        'password': password,
      },
    );
  }

  static WSMessage sendMessage(String groupId, String type, String encryptedContent,
      String iv, {Map<String, dynamic>? attachment}) {
    final payload = <String, dynamic>{
      'groupId': groupId,
      'msgType': type,
      'encryptedContent': encryptedContent,
      'iv': iv,
    };
    if (attachment != null) {
      payload['attachment'] = attachment;
    }
    return WSMessage(
      type: WSMessageType.msg,
      id: UuidGenerator.generate(),
      payload: payload,
    );
  }

  static WSMessage createGroup(String name) {
    return WSMessage(
      type: WSMessageType.groupCreate,
      id: UuidGenerator.generate(),
      payload: {'name': name},
    );
  }

  // static WSMessage joinGroup(String inviteCode) {
  //   return WSMessage(
  //     type: WSMessageType.groupJoin,
  //     id: UuidGenerator.generate(),
  //     payload: {'inviteCode': inviteCode},
  //   );
  // }

  static WSMessage requestGroups() {
    return WSMessage(
      type: 'group_list',
      id: UuidGenerator.generate(),
      payload: {},
    );
  }

  static WSMessage requestOffline(int page, int pageSize) {
    return WSMessage(
      type: WSMessageType.offlineFetch,
      id: UuidGenerator.generate(),
      payload: {
        'page': page,
        'pageSize': pageSize,
      },
    );
  }

  static WSMessage leaveGroup(String groupId) {
    return WSMessage(
      type: WSMessageType.leaveGroup,
      id: UuidGenerator.generate(),
      payload: {'groupId': groupId},
    );
  }

  static WSMessage joinGroup(String inviteCode) {
    return WSMessage(
      type: WSMessageType.groupJoin,
      id: UuidGenerator.generate(),
      payload: {'inviteCode': inviteCode},
    );
  }

  static WSMessage approveGroupJoin(String groupId, String requesterId) {
    return WSMessage(
      type: WSMessageType.groupJoinApprove,
      id: UuidGenerator.generate(),
      payload: {
        'groupId': groupId,
        'requesterId': requesterId,
      },
    );
  }

  static WSMessage rejectGroupJoin(String groupId, String requesterId) {
    return WSMessage(
      type: WSMessageType.groupJoinReject,
      id: UuidGenerator.generate(),
      payload: {
        'groupId': groupId,
        'requesterId': requesterId,
      },
    );
  }

  static WSMessage ping() {
    return WSMessage(
      type: WSMessageType.ping,
      id: UuidGenerator.generate(),
      payload: {},
    );
  }

  static WSMessage ack(String messageId) {
    return WSMessage(
      type: WSMessageType.msgAck,
      id: UuidGenerator.generate(),
      payload: {'messageId': messageId},
    );
  }
}
