import 'dart:async';
import 'package:uuid/uuid.dart';
import '../../models/server_config.dart';
import 'websocket_client.dart';

class ClientManager {
  static final ClientManager _instance = ClientManager._internal();
  factory ClientManager() => _instance;
  ClientManager._internal();

  final Map<String, ServerConnection> _connections = {};
  String? _activeServerId;

  ServerConnection? get activeConnection =>
      _activeServerId != null ? _connections[_activeServerId] : null;

  List<ServerConnection> get allConnections => _connections.values.toList();

  ServerConnection? getConnection(String serverId) => _connections[serverId];

  Future<ServerConnection> addServer(String name, String host, int port) async {
    final config = ServerConfig(
      id: const Uuid().v4(),
      name: name,
      host: host,
      port: port,
    );
    final connection = ServerConnection(config);
    _connections[config.id] = connection;
    return connection;
  }

  Future<bool> connectToServer(String serverId) async {
    final connection = _connections[serverId];
    if (connection == null) return false;

    final success = await connection.connect();
    if (success) {
      _activeServerId = serverId;
    }
    return success;
  }

  void disconnectFromServer(String serverId) {
    final connection = _connections[serverId];
    connection?.disconnect();
    if (_activeServerId == serverId) {
      _activeServerId = null;
    }
  }

  void removeServer(String serverId) {
    disconnectFromServer(serverId);
    _connections.remove(serverId);
  }

  void setActiveServer(String serverId) {
    if (_connections.containsKey(serverId)) {
      _activeServerId = serverId;
    }
  }

  void dispose() {
    for (final connection in _connections.values) {
      connection.dispose();
    }
    _connections.clear();
  }
}
