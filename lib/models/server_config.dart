class ServerConfig {
  final String id;
  final String name;
  final String host;
  final int port;
  final String? currentUserId;
  // final String? currentUsername;
  final String? currentNickname;

  ServerConfig({
    required this.id,
    required this.name,
    required this.host,
    required this.port,
    this.currentUserId,
    // this.currentUsername,
    this.currentNickname,
  });

  String get wsUrl => 'ws://$host:$port';
  String get httpUrl => 'http://$host:$port';
  String get displayName => '$name ($host:$port)';

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'host': host,
        'port': port,
        'currentUserId': currentUserId,
        // 'currentUsername': currentUsername,
        'currentNickname': currentNickname,
      };

  factory ServerConfig.fromJson(Map<String, dynamic> json) => ServerConfig(
        id: json['id'] as String,
        name: json['name'] as String,
        host: json['host'] as String,
        port: json['port'] as int,
        currentUserId: json['currentUserId'] as String?,
        // currentUsername: json['currentUsername'] as String?,
        currentNickname: json['currentNickname'] as String?,
      );

  ServerConfig copyWith({
    String? id,
    String? name,
    String? host,
    int? port,
    String? currentUserId,
    String? currentUsername,
    String? currentNickname,
  }) {
    return ServerConfig(
      id: id ?? this.id,
      name: name ?? this.name,
      host: host ?? this.host,
      port: port ?? this.port,
      currentUserId: currentUserId ?? this.currentUserId,
      // currentUsername: currentUsername ?? this.currentUsername,
      currentNickname: currentNickname ?? this.currentNickname,
    );
  }
}
