import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/constants/theme.dart';
import '../core/constants/app_strings.dart';
import '../providers/server_provider.dart';
import '../models/discovered_server.dart';

class DiscoveryScreen extends StatefulWidget {
  const DiscoveryScreen({super.key});

  @override
  State<DiscoveryScreen> createState() => _DiscoveryScreenState();
}

class _DiscoveryScreenState extends State<DiscoveryScreen> {
  @override
  void initState() {
    super.initState();
    context.read<ServerProvider>().startDiscovery();
  }

  @override
  void dispose() {
    context.read<ServerProvider>().stopDiscovery();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final serverProvider = context.watch<ServerProvider>();

    return Scaffold(
      appBar: AppBar(
        title: const Text(AppStrings.discoverServers),
      ),
      body: SafeArea(
        child: serverProvider.discoveredServers.isEmpty
            ? Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (serverProvider.discovering)
                const CircularProgressIndicator()
              else
                const Icon(
                  Icons.wifi_off,
                  size: 64,
                  color: AppTheme.textSecondary,
                ),
              const SizedBox(height: 16),
              Text(
                serverProvider.discovering
                    ? AppStrings.scanning
                    : AppStrings.noServersFound,
                style: const TextStyle(
                  fontSize: 18,
                  color: AppTheme.textSecondary,
                ),
              ),
            ],
          ),
        )
            : ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: serverProvider.discoveredServers.length,
          itemBuilder: (context, index) {
            final server = serverProvider.discoveredServers[index];
            return _ServerTile(
              server: server,
              onTap: () => _connectToServer(server),
            );
          },
        ),
      ),
    );
  }

  Future<void> _connectToServer(DiscoveredServer server) async {
    final serverProvider = context.read<ServerProvider>();
    final connection = await serverProvider.addServerConnection(
      server.name,
      server.host,
      server.port,
    );

    final success = await serverProvider.connectToServer(connection);

    if (success && mounted) {
      Navigator.pop(context);
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text(AppStrings.connectionFailed)),
      );
    }
  }
}

class _ServerTile extends StatelessWidget {
  final DiscoveredServer server;
  final VoidCallback onTap;

  const _ServerTile({required this.server, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        leading: const Icon(Icons.dns, color: AppTheme.lightPurple),
        title: Text(
          server.name,
          style: const TextStyle(color: AppTheme.textPrimary),
        ),
        subtitle: Text(
          '${server.host}:${server.port}',
          style: const TextStyle(color: AppTheme.textSecondary),
        ),
        trailing: ElevatedButton(
          onPressed: onTap,
          child: const Text(AppStrings.connect),
        ),
      ),
    );
  }
}