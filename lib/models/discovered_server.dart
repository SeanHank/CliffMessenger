import 'dart:async';
import 'dart:io';

import 'package:web_socket_channel/io.dart';

import '../core/constants/app_strings.dart';
import '../core/network/protocol.dart';

class DiscoveredServer {
  final String id;
  final String name;
  final String host;
  final int port;
  final DateTime discoveredAt;

  DiscoveredServer({
    required this.id,
    required this.name,
    required this.host,
    required this.port,
    required this.discoveredAt,
  });

  String get displayName => '$name ($host:$port)';

  Future<String> trySetServerName() async {
    String serverName = AppStrings.defaultServerName;
    final wsUrl = 'ws://$host:$port/ws';
    try {
      final tempSocket = await WebSocket.connect(wsUrl).timeout(
        const Duration(seconds: 3),
      );
      final tempChannel = IOWebSocketChannel(tempSocket);

      final nameCompleter = Completer<String>();
      tempChannel.stream.listen(
            (data) {
          try {
            final msg = WSMessage.fromRaw(data as String);
            if (msg.type == WSMessageType.serverInfoResponse) {
              nameCompleter.complete(
                  msg.payload['serverName'] as String? ?? serverName);
            }
          } catch (_) {}
        },
        onDone: () {
          if (!nameCompleter.isCompleted) {
            nameCompleter.complete(serverName);
          }
        },
      );

      tempChannel.sink.add(WSMessage.requestServerInfo().toJsonString());
      serverName = await nameCompleter.future.timeout(
        const Duration(seconds: 3),
        onTimeout: () => serverName,
      );
      await tempChannel.sink.close();
    } catch (e) {
      // Use default server name if connection fails
    }

    return serverName;
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'host': host,
        'port': port,
        'discoveredAt': discoveredAt.toIso8601String(),
      };

  factory DiscoveredServer.fromJson(Map<String, dynamic> json) => DiscoveredServer(
        id: json['id'] as String,
        name: json['name'] as String,
        host: json['host'] as String,
        port: json['port'] as int,
        discoveredAt: DateTime.parse(json['discoveredAt'] as String),
      );
}
