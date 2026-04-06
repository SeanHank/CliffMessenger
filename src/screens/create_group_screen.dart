import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/constants/theme.dart';
import '../core/constants/app_strings.dart';
import '../providers/auth_provider.dart';

class CreateGroupScreen extends StatefulWidget {
  const CreateGroupScreen({super.key});

  @override
  State<CreateGroupScreen> createState() => _CreateGroupScreenState();
}

class _CreateGroupScreenState extends State<CreateGroupScreen> {
  final _nameController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _creating = false;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(AppStrings.createGroup),
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
                  Icons.group_add,
                  size: 64,
                  color: AppTheme.lightPurple,
                ),
                const SizedBox(height: 32),
                TextFormField(
                  controller: _nameController,
                  decoration: const InputDecoration(
                    labelText: AppStrings.groupName,
                    prefixIcon: Icon(Icons.group_outlined),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return AppStrings.required;
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 32),
                ElevatedButton(
                  onPressed: _creating ? null : _createGroup,
                  child: _creating
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text(AppStrings.createGroup),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _createGroup() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _creating = true);

    final connection = context.read<AuthProvider>().activeConnection;
    connection?.createGroup(_nameController.text.trim());

    await Future.delayed(const Duration(milliseconds: 500));

    setState(() => _creating = false);

    if (mounted) {
      Navigator.pop(context);
    }
  }
}
