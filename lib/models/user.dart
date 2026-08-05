class UserModel {
  final String id;
  final String username;
  final String nickname;
  final String passwordHash;
  final String rsaPublicKey;

  UserModel({
    required this.id,
    required this.username,
    required this.nickname,
    required this.passwordHash,
    required this.rsaPublicKey,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'username': username,
        'nickname': nickname,
        'passwordHash': passwordHash,
        'rsaPublicKey': rsaPublicKey,
      };

  factory UserModel.fromJson(Map<String, dynamic> json) => UserModel(
        id: json['id'] as String,
        username: json['username'] as String,
        nickname: json['nickname'] as String,
        passwordHash: json['passwordHash'] as String,
        rsaPublicKey: json['rsaPublicKey'] as String,
      );

  UserModel copyWith({
    String? id,
    String? username,
    String? nickname,
    String? passwordHash,
    String? rsaPublicKey,
  }) {
    return UserModel(
      id: id ?? this.id,
      username: username ?? this.username,
      nickname: nickname ?? this.nickname,
      passwordHash: passwordHash ?? this.passwordHash,
      rsaPublicKey: rsaPublicKey ?? this.rsaPublicKey,
    );
  }
}
