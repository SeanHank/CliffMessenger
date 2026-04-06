import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/constants/theme.dart';
import '../core/constants/app_strings.dart';
import '../core/network/protocol.dart';
import '../providers/auth_provider.dart';

class JoinGroupScreen extends StatefulWidget {
  const JoinGroupScreen({super.key});

  @override
  State<JoinGroupScreen> createState() => _JoinGroupScreenState();
}

class _JoinGroupScreenState extends State<JoinGroupScreen> {
  final _codeController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _joining = false;
  String? _error;
  Completer<Map<String, dynamic>>? _responseCompleter;

  @override
  void initState() {
    super.initState();
    _setupResponseListener();
  }

  void _setupResponseListener() {
    final connection = context
        .read<AuthProvider>()
        .activeConnection;
    if (connection != null) {
      connection.messages.listen((msg) {
        if (_responseCompleter != null && !_responseCompleter!.isCompleted) {
          if (msg.type == WSMessageType.error) {
            _responseCompleter!.complete({
              'success': false,
              'message': msg.payload['message'] as String? ?? 'Unknown error',
            });
          } else if (msg.type == WSMessageType.groupJoinRequest) {
            final action = msg.payload['action'] as String?;
            if (action == 'pending') {
              _responseCompleter!.complete({
                'success': true,
                'message': 'Join request submitted, waiting for approval',
              });
            }
          } else if (msg.type == WSMessageType.groupJoinResult) {
            final action = msg.payload['action'] as String?;
            if (action == 'approved') {
              _responseCompleter!.complete({
                'success': true,
                'message': 'Join request approved!',
              });
            } else if (action == 'rejected') {
              _responseCompleter!.complete({
                'success': false,
                'message': msg.payload['message'] as String? ??
                    'Request rejected',
              });
            }
          }
        }
      });
    }
  }

  @override
  void dispose() {
    if (_responseCompleter != null && !_responseCompleter!.isCompleted) {
      _responseCompleter!.completeError('Screen disposed');
    }
    _codeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(AppStrings.joinGroup),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 32),
                const Icon(
                  Icons.vpn_key_outlined,
                  size: 64,
                  color: AppTheme.lightPurple,
                ),
                const SizedBox(height: 32),
                TextFormField(
                  controller: _codeController,
                  decoration: const InputDecoration(
                    labelText: AppStrings.inviteCode,
                    prefixIcon: Icon(Icons.key_outlined),
                    hintText: 'Enter UUID invite code',
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return AppStrings.required;
                    }
                    return null;
                  },
                ),
                if (_error != null) ...[
                  const SizedBox(height: 16),
                  Text(
                    _error!,
                    style: const TextStyle(color: AppTheme.errorRed),
                    textAlign: TextAlign.center,
                  ),
                ],
                const SizedBox(height: 32),
                ElevatedButton(
                  onPressed: _joining ? null : _joinGroup,
                  child: _joining
                      ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                      : const Text(AppStrings.joinGroup),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // Future<void> _joinGroup() async {
  //   if (!_formKey.currentState!.validate()) return;
  //
  //   setState(() {
  //     _joining = true;
  //     _error = null;
  //   });
  //
  //   final connection = context
  //       .read<AuthProvider>()
  //       .activeConnection;
  //   if (connection == null) {
  //     setState(() {
  //       _error = 'Not connected to server';
  //       _joining = false;
  //     });
  //     return;
  //   }
  //
  //   connection.joinGroup(_codeController.text.trim());
  //
  //   await Future.delayed(const Duration(seconds: 1));
  //
  //   setState(() => _joining = false);
  //
  //   if (mounted) {
  //     Navigator.pop(context);
  //   }
  // }
  Future<void> _joinGroup() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _joining = true;
      _error = null;
    });

    final connection = context.read<AuthProvider>().activeConnection;
    if (connection == null) {
      setState(() {
        _error = 'Not connected to server';
        _joining = false;
      });
      return;
    }

    _responseCompleter = Completer<Map<String, dynamic>>();

    connection.joinGroup(_codeController.text.trim());

    try {
      final response = await _responseCompleter!.future.timeout(
        const Duration(seconds: 10),
        onTimeout: () => {
          'success': false,
          'message': 'Request timed out',
        },
      );

      if (!mounted) return;

      if (response['success'] == true) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(response['message'] as String),
            backgroundColor: AppTheme.successGreen,
          ),
        );
        Navigator.pop(context);
      } else {
        setState(() {
          _error = response['message'] as String;
          _joining = false;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Failed to send request';
        _joining = false;
      });
    }
  }
}