import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/constants/theme.dart';
import '../core/constants/app_strings.dart';
import '../providers/server_provider.dart';
import '../server/server_manager.dart';
import 'server_running_screen.dart';

class ServerSetupScreen extends StatefulWidget {
  const ServerSetupScreen({super.key});

  @override
  State<ServerSetupScreen> createState() => _ServerSetupScreenState();
}

class _ServerSetupScreenState extends State<ServerSetupScreen> {
  final _nameController = TextEditingController();
  final _portController = TextEditingController(text: '8080');
  final _formKey = GlobalKey<FormState>();
  bool _starting = false;

  @override
  void dispose() {
    _nameController.dispose();
    _portController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(AppStrings.serverSetup),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            context.read<ServerProvider>().setMode(ServerMode.none);
            Navigator.pop(context);
          },
        ),
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
                  Icons.dns_outlined,
                  size: 64,
                  color: AppTheme.lightPurple,
                ),
                const SizedBox(height: 32),
                // TextFormField(
                //   controller: _nameController,
                //   decoration: const InputDecoration(
                //     labelText: AppStrings.serverName,
                //     prefixIcon: Icon(Icons.label_outline),
                //   ),
                //   validator: (value) {
                //     if (value == null || value.isEmpty) {
                //       return AppStrings.required;
                //     }
                //     return null;
                //   },
                // ),
                TextFormField(
                  controller: _nameController,
                  decoration: const InputDecoration(
                    labelText: AppStrings.serverName,
                    hintText: '',
                    prefixIcon: Icon(Icons.label_outline),
                  ),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _portController,
                  decoration: const InputDecoration(
                    labelText: AppStrings.serverPort,
                    prefixIcon: Icon(Icons.numbers),
                  ),
                  keyboardType: TextInputType.number,
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return AppStrings.required;
                    }
                    final port = int.tryParse(value);
                    if (port == null || port < 1024 || port > 65535) {
                      return AppStrings.invalidPort;
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 48),
                ElevatedButton(
                  onPressed: _starting ? null : _startServer,
                  child: _starting
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text(AppStrings.startServer),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // Future<void> _startServer() async {
  //   if (!_formKey.currentState!.validate()) return;
  //
  //   setState(() => _starting = true);
  //
  //   final name = _nameController.text.trim();
  //   final port = int.parse(_portController.text);
  //
  //   final serverManager = ServerManager();
  //   final serverProvider = context.read<ServerProvider>();
  //   final success = await serverManager.start(name, port);
  //
  //   setState(() => _starting = false);
  //
  //   if (success) {
  //     serverProvider.startServer(name, port);
  //     if (!mounted) return;
  //     Navigator.pushReplacement(
  //       context,
  //       MaterialPageRoute(
  //         builder: (_) => const ServerRunningScreen(),
  //       ),
  //     );
  //   } else {
  //     if (!mounted) return;
  //     ScaffoldMessenger.of(context).showSnackBar(
  //       const SnackBar(content: Text('Failed to start server')),
  //     );
  //   }
  // }
  Future<void> _startServer() async {
    setState(() => _starting = true);

    final nameInput = _nameController.text.trim();
    final name = nameInput.isEmpty ? 'Server_${DateTime.now().millisecondsSinceEpoch}' : nameInput;
    final port = int.parse(_portController.text);

    final serverManager = ServerManager();
    final serverProvider = context.read<ServerProvider>();
    final success = await serverManager.start(name, port);

    setState(() => _starting = false);

    if (success) {
      serverProvider.startServer(name, port);
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => const ServerRunningScreen(),
        ),
      );
    } else {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to start server')),
      );
    }
  }
}
