import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/constants/theme.dart';
import '../core/constants/app_strings.dart';
import '../providers/server_provider.dart';
import '../server/server_manager.dart';

class ServerRunningScreen extends StatefulWidget {
  const ServerRunningScreen({super.key});

  @override
  State<ServerRunningScreen> createState() => _ServerRunningScreenState();
}

class _ServerRunningScreenState extends State<ServerRunningScreen> {
  @override
  Widget build(BuildContext context) {
    final serverProvider = context.watch<ServerProvider>();

    return Scaffold(
      appBar: AppBar(
        title: const Text(AppStrings.serverRunning),
        automaticallyImplyLeading: false,
        actions: [
          IconButton(
            icon: const Icon(Icons.stop),
            onPressed: _stopServer,
            tooltip: AppStrings.stopServer,
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.check_circle_outline,
                  size: 80,
                  color: AppTheme.successGreen,
                ),
                const SizedBox(height: 24),
                const Text(
                  AppStrings.serverRunning,
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.textPrimary,
                  ),
                ),
                const SizedBox(height: 32),
                _InfoRow(
                  label: AppStrings.serverName,
                  value: serverProvider.serverName,
                ),
                const SizedBox(height: 12),
                _InfoRow(
                  label: AppStrings.serverPort,
                  value: serverProvider.serverPort.toString(),
                ),
                const SizedBox(height: 12),
                _InfoRow(
                  label: 'Address',
                  value: '0.0.0.0:${serverProvider.serverPort}',
                ),
                const SizedBox(height: 48),
                const Text(
                  'Waiting for clients...',
                  style: TextStyle(
                    fontSize: 16,
                    color: AppTheme.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _stopServer() async {
    final serverManager = ServerManager();
    final serverProvider = context.read<ServerProvider>();
    await serverManager.stop();
    serverProvider.stopServer();
    if (!mounted) return;
    Navigator.pop(context);
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;

  const _InfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 14,
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              color: AppTheme.textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
