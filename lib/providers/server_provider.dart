import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart';
import '../../client/websocket_client.dart';
import '../../client/db/server_store.dart';
import '../../models/server_config.dart';
import '../../core/constants/app_strings.dart';
import '../../core/network/mdns_discovery.dart';
import '../../models/discovered_server.dart';

enum ServerMode { none, server, client }

class ServerProvider extends ChangeNotifier {
  ServerMode _mode = ServerMode.none;
  bool _serverRunning = false;
  String _serverName = '';
  int _serverPort = 0;
  final String _serverId = DateTime.now().millisecondsSinceEpoch.toString();
  final List<ServerConnection> _clientConnections = [];
  ServerConnection? _activeConnection;
  final List<DiscoveredServer> _discoveredServers = [];
  bool _discovering = false;
  bool _connecting = false;
  String? _error;
  StreamSubscription? _discoverySubscription;
  final _logger = Logger('ServerProvider');

  ServerMode get mode => _mode;
  bool get serverRunning => _serverRunning;
  String get serverName => _serverName;
  int get serverPort => _serverPort;
  String get serverId => _serverId;
  List<ServerConnection> get clientConnections => List.unmodifiable(_clientConnections);
  ServerConnection? get activeConnection => _activeConnection;
  List<DiscoveredServer> get discoveredServers => List.unmodifiable(_discoveredServers);
  bool get discovering => _discovering;
  bool get connecting => _connecting;
  String? get error => _error;

  Future<void> loadSavedServers() async {
    try {
      final saved = await ServerStore.getAllServers();
      _clientConnections.clear();
      for (final config in saved) {
        final connection = ServerConnection(config);
        _clientConnections.add(connection);
      }
      notifyListeners();
    } catch (e) {
      _logger.warning('Failed to load saved servers: $e');
    }
  }

  void setMode(ServerMode mode) {
    _mode = mode;
    notifyListeners();
  }

  Future<bool> startServer(String name, int port) async {
    try {
      _serverName = name;
      _serverPort = port;
      _serverRunning = true;

      final mdns = MdnsDiscovery();
      await mdns.registerService(_serverId, name, port);

      notifyListeners();
      return true;
    } catch (e) {
      _error = 'Failed to start server: $e';
      notifyListeners();
      return false;
    }
  }

  Future<void> stopServer() async {
    _serverRunning = false;
    final mdns = MdnsDiscovery();
    await mdns.unregisterService();
    notifyListeners();
  }

  Future<ServerConnection> addServerConnection(String name, String host, int port) async {
    if (name.trim().isEmpty) {
      _serverName = AppStrings.defaultServerName;
    } else {
      _serverName = name.trim();
    }

    final config = ServerConfig(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: _serverName,
      host: host.trim(),
      port: port,
    );
    final connection = ServerConnection(config);
    _clientConnections.add(connection);
    await ServerStore.saveServer(config);
    notifyListeners();
    return connection;
  }

  Future<bool> connectToServer(ServerConnection connection) async {
    _connecting = true;
    _error = null;
    notifyListeners();

    try {
      if (_activeConnection != null && _activeConnection != connection) {
        _activeConnection!.disconnect();
        _activeConnection = null;
      }

      final success = await connection.connect();
      if (success) {
        _activeConnection = connection;
        await ServerStore.saveServer(connection.config);
      } else {
        _error = connection.connectionError ?? AppStrings.connectionFailed;
      }
      _connecting = false;
      notifyListeners();
      return success;
    } catch (e) {
      _error = e.toString();
      _connecting = false;
      notifyListeners();
      return false;
    }
  }

  void disconnectFromServer(ServerConnection connection) {
    connection.disconnect();
    if (_activeConnection == connection) {
      _activeConnection = null;
    }
    notifyListeners();
  }

  void removeServerConnection(ServerConnection connection) {
    if (_activeConnection == connection) {
      _activeConnection = null;
    }
    connection.dispose();
    _clientConnections.remove(connection);
    ServerStore.removeServer(connection.config.id);
    notifyListeners();
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }

  Future<void> startDiscovery() async {
    _discovering = true;
    _discoveredServers.clear();
    notifyListeners();

    await _discoverySubscription?.cancel();
    final mdns = MdnsDiscovery();
    await mdns.startListening();
    _discoverySubscription = mdns.discoveredStream.listen((server) {
      if (!_discoveredServers.any((s) => s.id == server.id)) {
        _discoveredServers.add(server);
        notifyListeners();
      }
    });
  }

  void stopDiscovery({bool notify = true}) {
    _discoverySubscription?.cancel();
    _discoverySubscription = null;
    final mdns = MdnsDiscovery();
    mdns.stopListening();
    _discovering = false;
    if (notify) {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _discoverySubscription?.cancel();
    final mdns = MdnsDiscovery();
    mdns.dispose();
    for (final conn in _clientConnections) {
      conn.dispose();
    }
    _clientConnections.clear();
    super.dispose();
  }
}