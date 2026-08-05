class FileAttachment {
  final String fileId;
  final String fileName;
  final int fileSize;
  final String mimeType;

  FileAttachment({
    required this.fileId,
    required this.fileName,
    required this.fileSize,
    required this.mimeType,
  });

  Map<String, dynamic> toJson() => {
        'fileId': fileId,
        'fileName': fileName,
        'fileSize': fileSize,
        'mimeType': mimeType,
      };

  factory FileAttachment.fromJson(Map<String, dynamic> json) => FileAttachment(
        fileId: json['fileId'] as String,
        fileName: json['fileName'] as String,
        fileSize: json['fileSize'] as int,
        mimeType: json['mimeType'] as String,
      );
}

enum MessageType { text, image, file }

class MessageModel {
  final String id;
  final String groupId;
  final String senderId;
  final String senderNickname;
  final MessageType type;
  final String encryptedContent;
  final String iv;
  final FileAttachment? attachment;
  final int timestamp;
  final String serverId;

  MessageModel({
    required this.id,
    required this.groupId,
    required this.senderId,
    required this.senderNickname,
    required this.type,
    required this.encryptedContent,
    required this.iv,
    this.attachment,
    required this.timestamp,
    required this.serverId,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'groupId': groupId,
        'senderId': senderId,
        'senderNickname': senderNickname,
        'type': type.name,
        'encryptedContent': encryptedContent,
        'iv': iv,
        'attachment': attachment?.toJson(),
        'timestamp': timestamp,
        'serverId': serverId,
      };

  factory MessageModel.fromJson(Map<String, dynamic> json) => MessageModel(
        id: json['id'] as String,
        groupId: json['groupId'] as String,
        senderId: json['senderId'] as String,
        senderNickname: json['senderNickname'] as String,
        type: MessageType.values.firstWhere(
          (e) => e.name == json['type'],
          orElse: () => MessageType.text,
        ),
        encryptedContent: json['encryptedContent'] as String,
        iv: json['iv'] as String,
        attachment: json['attachment'] != null
            ? FileAttachment.fromJson(json['attachment'] as Map<String, dynamic>)
            : null,
        timestamp: json['timestamp'] as int,
        serverId: json['serverId'] as String,
      );
}
