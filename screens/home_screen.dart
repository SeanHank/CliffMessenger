import 'dart:async';

import 'package:cliff_messenger/screens/splash_screen.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/constants/theme.dart';
import '../core/constants/app_strings.dart';
import '../core/network/protocol.dart';
import '../providers/auth_provider.dart';
import '../providers/chat_provider.dart';
import '../providers/server_provider.dart';
import 'chat_screen.dart';
import 'create_group_screen.dart';
import 'join_group_screen.dart';
import '../widgets/group_card.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  StreamSubscription<WSMessage>? _messageSubscription;

  @override
  void initState() {
    super.initState();
    _setupMessageListener();
  }

  @override
  void dispose() {
    _messageSubscription?.cancel();
    super.dispose();
  }

  void _setupMessageListener() {
    _messageSubscription?.cancel();
    final authProvider = context.read<AuthProvider>();
    final chatProvider = context.read<ChatProvider>();
    final connection = authProvider.activeConnection;
    if (connection != null) {
      // connection.messages.listen((msg) {
      //   chatProvider.handleIncomingMessage(msg);
      // });
      _messageSubscription = connection.messages.listen((msg) {
        chatProvider.handleIncomingMessage(msg);
        // if (msg.type == WSMessageType.groupJoinRequest) {
        //   final action = msg.payload['action'] as String?;
        //   if (action == 'pending') {
        //     ScaffoldMessenger.of(context).showSnackBar(
        //       const SnackBar(
        //         content: Text('Join request submitted, waiting for approval'),
        //         duration: Duration(seconds: 3),
        //       ),
        //     );
        //   }
        // } else if (msg.type == WSMessageType.groupJoinResult) {
        //   final action = msg.payload['action'] as String?;
        //   if (action == 'rejected') {
        //     ScaffoldMessenger.of(context).showSnackBar(
        //       const SnackBar(
        //         content: Text('Join request rejected by group owner'),
        //         backgroundColor: Colors.red,
        //       ),
        //     );
        //   } else if (action == 'approved') {
        //     ScaffoldMessenger.of(context).showSnackBar(
        //       const SnackBar(
        //         content: Text('Join request approved!'),
        //         backgroundColor: Colors.green,
        //       ),
        //     );
        //   }
        // }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = context.watch<AuthProvider>();
    final chatProvider = context.watch<ChatProvider>();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (authProvider.pendingJoinRequest != null) {
        _showJoinRequestDialog(context, authProvider);
      }
      if (authProvider.pendingDissolveGroup != null) {
        _showDissolveDialog(context, authProvider);
      }
    });

    return Scaffold(
      appBar: AppBar(
        title: const Text(AppStrings.appName),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: _logout,
            tooltip: AppStrings.logout,
          ),
        ],
      ),
      body: SafeArea(
        child: authProvider.groups.isEmpty
            ? _EmptyState()
            : ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: authProvider.groups.length,
                itemBuilder: (context, index) {
                  final group = authProvider.groups[index];
                  return GroupCard(
                    group: group,
                    onTap: () {
                      final groupKey = authProvider.getGroupKey(group.id);
                      if (groupKey != null) {
                        chatProvider.setGroupKey(group.id, groupKey);
                      }
                      chatProvider.setActiveGroup(group);
                      chatProvider.loadMessages(group.id);
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ChatScreen(group: group),
                        ),
                      );
                    },
                  );
                },
              ),
      ),
      floatingActionButton: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          FloatingActionButton(
            heroTag: 'join',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const JoinGroupScreen()),
              );
            },
            child: const Icon(Icons.group_add),
          ),
          const SizedBox(height: 16),
          FloatingActionButton(
            heroTag: 'create',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const CreateGroupScreen()),
              );
            },
            child: const Icon(Icons.add),
          ),
        ],
      ),
    );
  }

  Future<void> _logout() async {
    final serverProvider = context.read<ServerProvider>();
    context.read<AuthProvider>().logout();
    context.read<ChatProvider>().clear();
    if (serverProvider.activeConnection != null) {
      serverProvider.disconnectFromServer(serverProvider.activeConnection!);
    }
    if (!mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const SplashScreen()),
      (route) => false,
    );
  }

  void _showJoinRequestDialog(BuildContext context, AuthProvider authProvider) {
    final request = authProvider.pendingJoinRequest!;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Join Request'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('${request['requesterNickname']} wants to join'),
            Text(
              request['groupName'] ?? '',
              style: const TextStyle(
                color: AppTheme.lightPurple,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              authProvider.rejectGroupJoin(
                request['groupId'],
                request['requesterId'],
              );
              Navigator.pop(dialogContext);
            },
            child: const Text('Reject'),
          ),
          FilledButton(
            onPressed: () {
              authProvider.approveGroupJoin(
                request['groupId'],
                request['requesterId'],
              );
              Navigator.pop(dialogContext);
            },
            child: const Text('Approve'),
          ),
        ],
      ),
    );
  }

  void _showDissolveDialog(BuildContext context, AuthProvider authProvider) {
    final info = authProvider.pendingDissolveGroup!;
    authProvider.clearPendingDissolveGroup();

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Group Dissolved'),
        content: Text('The group "${info['groupName']}" has been dissolved by the owner.'),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.chat_bubble_outline,
              size: 80,
              color: AppTheme.lightPurple,
            ),
            const SizedBox(height: 24),
            const Text(
              AppStrings.noGroups,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w600,
                color: AppTheme.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              AppStrings.createOrJoin,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 16,
                color: AppTheme.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
