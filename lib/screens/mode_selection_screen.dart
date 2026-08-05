import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/constants/theme.dart';
import '../core/constants/app_strings.dart';
import '../providers/server_provider.dart';
import 'server_setup_screen.dart';
import 'server_select_screen.dart';

class ModeSelectionScreen extends StatelessWidget {
  const ModeSelectionScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.message_rounded,
                  size: 80,
                  color: AppTheme.lightPurple,
                ),
                const SizedBox(height: 16),
                const Text(
                  AppStrings.appName,
                  style: TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.textPrimary,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'End-to-End Encrypted Messaging',
                  style: TextStyle(
                    fontSize: 16,
                    color: AppTheme.textSecondary,
                  ),
                ),
                const SizedBox(height: 64),
                const Text(
                  AppStrings.chooseMode,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textPrimary,
                  ),
                ),
                const SizedBox(height: 24),
                _ModeCard(
                  icon: Icons.dns_outlined,
                  title: AppStrings.serverMode,
                  description: AppStrings.serverModeDesc,
                  onTap: () {
                    context.read<ServerProvider>().setMode(ServerMode.server);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const ServerSetupScreen(),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 16),
                _ModeCard(
                  icon: Icons.desktop_windows_outlined,
                  title: AppStrings.clientMode,
                  description: AppStrings.clientModeDesc,
                  onTap: () {
                    context.read<ServerProvider>().setMode(ServerMode.client);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const ServerSelectScreen(),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ModeCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;
  final VoidCallback onTap;

  const _ModeCard({
    required this.icon,
    required this.title,
    required this.description,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: AppTheme.bgCard,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppTheme.primaryPurple.withValues(alpha: 0.3)),
        ),
        child: Row(
          children: [
            Icon(icon, size: 40, color: AppTheme.lightPurple),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    description,
                    style: const TextStyle(
                      fontSize: 14,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.arrow_forward_ios, color: AppTheme.lightPurple),
          ],
        ),
      ),
    );
  }
}
