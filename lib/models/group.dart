class GroupModel {
  final String id;
  final String name;
  final String inviteCode;
  final String creatorId;
  final String serverId;
  final List<String> memberIds;
  final int createdAt;
  final String? encryptedGroupKey;
  final Map<String, String>? encryptedGroupKeys;

  GroupModel({
    required this.id,
    required this.name,
    required this.inviteCode,
    required this.creatorId,
    required this.serverId,
    required this.memberIds,
    required this.createdAt,
    this.encryptedGroupKey,
    this.encryptedGroupKeys,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'inviteCode': inviteCode,
        'creatorId': creatorId,
        'serverId': serverId,
        'memberIds': memberIds,
        'createdAt': createdAt,
        'encryptedGroupKey': encryptedGroupKey,
        'encryptedGroupKeys': encryptedGroupKeys,
      };

  factory GroupModel.fromJson(Map<String, dynamic> json) => GroupModel(
        id: json['id'] as String,
        name: json['name'] as String,
        inviteCode: json['inviteCode'] as String,
        creatorId: json['creatorId'] as String,
        serverId: json['serverId'] as String,
        memberIds: List<String>.from(json['memberIds'] as List),
        createdAt: json['createdAt'] as int,
        encryptedGroupKey: json['encryptedGroupKey'] as String?,
        encryptedGroupKeys: json['encryptedGroupKeys'] != null
            ? Map<String, String>.from(json['encryptedGroupKeys'] as Map)
            : null,
      );

  GroupModel copyWith({
    String? id,
    String? name,
    String? inviteCode,
    String? creatorId,
    String? serverId,
    List<String>? memberIds,
    int? createdAt,
    String? encryptedGroupKey,
    Map<String, String>? encryptedGroupKeys,
  }) {
    return GroupModel(
      id: id ?? this.id,
      name: name ?? this.name,
      inviteCode: inviteCode ?? this.inviteCode,
      creatorId: creatorId ?? this.creatorId,
      serverId: serverId ?? this.serverId,
      memberIds: memberIds ?? this.memberIds,
      createdAt: createdAt ?? this.createdAt,
      encryptedGroupKey: encryptedGroupKey ?? this.encryptedGroupKey,
      encryptedGroupKeys: encryptedGroupKeys ?? this.encryptedGroupKeys,
    );
  }
}
