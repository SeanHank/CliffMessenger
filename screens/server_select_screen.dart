import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:web_socket_channel/io.dart';
import '../client/db/server_store.dart';
import '../core/constants/theme.dart';
import '../core/constants/app_strings.dart';
import '../core/network/protocol.dart';
import '../providers/server_provider.dart';
import '../client/websocket_client.dart';
import '../models/discovered_server.dart';
import 'login_screen.dart';

class ServerSelectScreen extends StatefulWidget {
  const ServerSelectScreen({super.key});

  @override
  State<ServerSelectScreen> createState() => _ServerSelectScreenState();
}

class _ServerSelectScreenState extends State<ServerSelectScreen> {
  late ServerProvider _serverProvider;
  final _hostController = TextEditingController();
  final _portController = TextEditingController(text: '8080');
  final _formKey = GlobalKey<FormState>();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _serverProvider = context.read<ServerProvider>();
  }

  @override
  void initState() {
    super.initState();
    context.read<ServerProvider>().loadSavedServers();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        context.read<ServerProvider>().startDiscovery();
      }
    });
  }

  @override
  void dispose() {
    _hostController.dispose();
    _portController.dispose();
    _serverProvider.stopDiscovery(notify: false);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final serverProvider = context.watch<ServerProvider>();
    final savedServers = serverProvider.clientConnections;
    final discovered = serverProvider.discoveredServers;

    return Scaffold(
      appBar: AppBar(
        title: const Text(AppStrings.selectServer),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            context.read<ServerProvider>().setMode(ServerMode.none);
            Navigator.pop(context);
          },
        ),
      ),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (serverProvider.error != null)
              Container(
                padding: const EdgeInsets.all(12),
                margin: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppTheme.errorRed.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline, color: AppTheme.errorRed),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        serverProvider.error!,
                        style: const TextStyle(color: AppTheme.errorRed),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, color: AppTheme.errorRed, size: 20),
                      onPressed: () => serverProvider.clearError(),
                    ),
                  ],
                ),
              ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _SectionHeader(title: 'Lan server'),
                  if (serverProvider.discovering)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 16),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else if (discovered.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: Center(
                        child: Text(
                          AppStrings.noServersFound,
                          style: TextStyle(color: AppTheme.textSecondary),
                        ),
                      ),
                    )
                  else
                    ...discovered.map((s) => _DiscoveredServerTile(
                          server: s,
                          onConnect: () => _connectToDiscovered(s),
                        )),
                  const SizedBox(height: 24),
                  _SectionHeader(title: AppStrings.addServer),
                  Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              flex: 3,
                              child: TextFormField(
                                controller: _hostController,
                                decoration: const InputDecoration(
                                  labelText: AppStrings.serverAddress,
                                  hintText: '127.0.0.1',
                                ),
                                validator: (v) =>
                                (v == null || v.trim().isEmpty) ? AppStrings.required : null,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              flex: 1,
                              child: TextFormField(
                                controller: _portController,
                                decoration: const InputDecoration(
                                  labelText: 'Port',
                                ),
                                keyboardType: TextInputType.number,
                                validator: (v) {
                                  if (v == null || v.isEmpty) return AppStrings.required;
                                  final p = int.tryParse(v);
                                  if (p == null || p < 1 || p > 65535) return AppStrings.invalidPort;
                                  return null;
                                },
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        ElevatedButton.icon(
                          onPressed: serverProvider.connecting ? null : _addAndConnect,
                          icon: serverProvider.connecting
                              ? const SizedBox(
                            height: 16,
                            width: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                              : const Icon(Icons.add),
                          label: Text(serverProvider.connecting
                              ? AppStrings.connecting
                              : AppStrings.connect),
                        ),
                      ],
                    ),
                  ),
                  if (savedServers.isNotEmpty) ...[
                    const SizedBox(height: 24),
                    _SectionHeader(title: 'Saved server'),
                    ...savedServers.map((conn) => _SavedServerTile(
                          connection: conn,
                          isActive: serverProvider.activeConnection == conn,
                          onConnect: () => _connectToSaved(conn),
                          onDisconnect: () => serverProvider.disconnectFromServer(conn),
                          onDelete: () => serverProvider.removeServerConnection(conn),
                        )),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<String> _getServerName(String host, int port, String wsUrl) async {
    String serverName = AppStrings.defaultServerName;
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

  Future<void> _addAndConnect() async {
    if (!_formKey.currentState!.validate()) return;

    final host = _hostController.text.trim();
    final port = int.parse(_portController.text);
    final wsUrl = 'ws://$host:$port/ws';
    String serverName = await _getServerName(host, port, wsUrl);

    final connection = await _serverProvider.addServerConnection(
      serverName,
      _hostController.text,
      port,
    );
    _hostController.clear();
    await _connectToSaved(connection);
  }

  Future<void> _connectToDiscovered(DiscoveredServer server) async {
    String serverName = await server.trySetServerName();
    final connection = await _serverProvider.addServerConnection(
      serverName,
      server.host,
      server.port,
    );
    await _connectToSaved(connection);
  }

  Future<void> _connectToSaved(ServerConnection connection) async {
    final host = connection.config.host;
    final port = connection.config.port;
    final wsUrl = '${connection.config.wsUrl}/ws';
    final serverName = await _getServerName(host, port, wsUrl);

    // 2. 如果获取到有效名称且与当前不同，更新 config
    if (serverName.isNotEmpty && serverName != connection.config.name) {
      final newConfig = connection.config.copyWith(name: serverName);
      await ServerStore.saveServer(newConfig);
      // 更新内存中的 connection config
      connection.updateConfig(newConfig);
    }

    final success = await _serverProvider.connectToServer(connection);
    if (success && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text(AppStrings.connectionSuccess)),
      );
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const LoginScreen()),
      );
    }
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: AppTheme.textSecondary,
        ),
      ),
    );
  }
}

class _DiscoveredServerTile extends StatelessWidget {
  final DiscoveredServer server;
  final VoidCallback onConnect;
  const _DiscoveredServerTile({required this.server, required this.onConnect});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: const Icon(Icons.dns, color: AppTheme.lightPurple),
        title: Text(server.name, style: const TextStyle(color: AppTheme.textPrimary)),
        subtitle: Text('${server.host}:${server.port}',
            style: const TextStyle(color: AppTheme.textSecondary)),
        trailing: ElevatedButton(
          onPressed: onConnect,
          child: const Text(AppStrings.connect),
        ),
      ),
    );
  }
}

class _SavedServerTile extends StatelessWidget {
  final ServerConnection connection;
  final bool isActive;
  final VoidCallback onConnect;
  final VoidCallback onDisconnect;
  final VoidCallback onDelete;
  const _SavedServerTile({
    required this.connection,
    required this.isActive,
    required this.onConnect,
    required this.onDisconnect,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final statusColor = isActive
        ? AppTheme.successGreen
        : connection.status == ConnectionStatus.error
            ? AppTheme.errorRed
            : AppTheme.textSecondary;
    final statusIcon = isActive
        ? Icons.check_circle
        : connection.status == ConnectionStatus.error
            ? Icons.error
            : Icons.circle_rounded;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Icon(statusIcon, color: statusColor),
        title: Text(connection.config.name,
            style: const TextStyle(color: AppTheme.textPrimary)),
        subtitle: Text('${connection.config.host}:${connection.config.port}',
            style: const TextStyle(color: AppTheme.textSecondary)),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isActive)
              TextButton(
                onPressed: onDisconnect,
                child: const Text(AppStrings.disconnect),
              )
            else
              ElevatedButton(
                onPressed: onConnect,
                child: const Text(AppStrings.connect),
              ),
            const SizedBox(width: 4),
            IconButton(
              icon: const Icon(Icons.delete_outline, color: AppTheme.errorRed),
              onPressed: onDelete,
              tooltip: AppStrings.delete,
            ),
          ],
        ),
      ),
    );
  }
}
