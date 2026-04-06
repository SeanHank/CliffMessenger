import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import '../core/constants/theme.dart';
import '../core/constants/app_strings.dart';
import '../providers/auth_provider.dart';
import '../providers/chat_provider.dart';
import '../models/group.dart';
import '../widgets/message_bubble.dart';

class ChatScreen extends StatefulWidget {
  final GroupModel group;
  const ChatScreen({super.key, required this.group});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _messageController = TextEditingController();
  final _scrollController = ScrollController();
  late ChatProvider _chatProvider;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _chatProvider = context.read<ChatProvider>();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _cacheGroupKey();
      _scrollWhenMessagesLoaded();
    });

    _chatProvider.setOnMessageAddedCallback(() {
      if (mounted) {
        _scrollToBottom();
      }
    });

    _chatProvider.addListener(_onErrorChanged);
  }

  void _onErrorChanged() {
    if (mounted && _chatProvider.error != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_chatProvider.error!),
          duration: const Duration(seconds: 3),
        ),
      );
      _chatProvider.clearError();
    }
  }

  void _scrollWhenMessagesLoaded() {

    void listener() {
      if (!_chatProvider.loading && _chatProvider.messages.isNotEmpty) {
        _chatProvider.removeListener(listener);
        if (mounted) {
          _initialScroll();
        }
      }
    }

    // 如果已经加载完成，直接滚动
    if (!_chatProvider.loading && _chatProvider.messages.isNotEmpty) {
      _initialScroll();
    } else {
      // 否则等待加载完成
      _chatProvider.addListener(listener);
    }
  }

  void _cacheGroupKey() {
    final authProvider = context.read<AuthProvider>();
    final groupKey = authProvider.getGroupKey(widget.group.id);
    if (groupKey != null) {
      _chatProvider.setGroupKey(widget.group.id, groupKey);
    }
  }

  @override
  void dispose() {
    _chatProvider.setOnMessageAddedCallback(null);
    _chatProvider.removeListener(_onErrorChanged);
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {  // 新增
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _initialScroll(){
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent / 1.5,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeInOutSine,
        ).then((_) {
          _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = context.watch<AuthProvider>();
    final chatProvider = context.watch<ChatProvider>();

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.group.name),
        actions: [
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'invite') {
                _showInviteCode();
              } else if (value == 'leave') {
                _leaveGroup();
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'invite',
                child: Text('Copy Invite Code'),
              ),
              const PopupMenuItem(
                value: 'leave',
                child: Text(AppStrings.leaveGroup),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: chatProvider.messages.isEmpty
                ? const Center(
              child: Text(
                AppStrings.noMessages,
                style: TextStyle(color: AppTheme.textSecondary),
              ),
            )
                : ListView.builder(
              controller: _scrollController,
              reverse: false,
              padding: const EdgeInsets.all(16),
              itemCount: chatProvider.messages.length,
              itemBuilder: (context, index) {
                final message = chatProvider.messages.toList()[index];
                final isMe = message.senderId == authProvider.userId;
                final groupKey = chatProvider.getGroupKey(widget.group.id);
                return MessageBubble(
                  message: message,
                  isMe: isMe,
                  onDecrypt: (key) {
                    try {
                      return chatProvider.decryptMessage(message, key);
                    } catch (e) {
                      return '[Decryption failed]';
                    }
                  },
                  groupKey: groupKey,
                  onDownload: () async {
                    if (message.attachment != null) {
                      final connection = authProvider.activeConnection;
                      final privateKeyPem = authProvider.privateKeyPem;

                      if (connection != null && privateKeyPem != null) {
                        await chatProvider.downloadAndDecryptFile(
                          connection,
                          message.attachment!.fileId,
                          privateKeyPem,
                          widget.group,
                        );
                      }
                    }
                  },
                );
              },
            ),
          ),
          _InputBar(
            controller: _messageController,
            onSend: _sendMessage,
            onImagePick: _pickImage,
            onFilePick: _pickFile,
            sending: _sending,
          ),
        ],
      ),
    );
  }

  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty || _sending) return;

    setState(() => _sending = true);

    final authProvider = context.read<AuthProvider>();
    final chatProvider = context.read<ChatProvider>();
    final connection = authProvider.activeConnection;

    if (connection != null && authProvider.privateKeyPem != null) {
      await chatProvider.sendTextMessage(
        connection,
        authProvider.privateKeyPem!,
        text,
      );
      _messageController.clear();
    }

    setState(() => _sending = false);
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final image = await picker.pickImage(source: ImageSource.gallery);
    if (image == null || !mounted) return;

    setState(() => _sending = true);

    final authProvider = context.read<AuthProvider>();
    final chatProvider = context.read<ChatProvider>();
    final connection = authProvider.activeConnection;

    if (connection != null && authProvider.privateKeyPem != null) {
      await chatProvider.sendFileMessage(
        connection,
        authProvider.privateKeyPem!,
        filePath: image.path,
        isImage: true,
      );
    }

    if (!mounted) return;
    setState(() => _sending = false);
  }

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles();
    if (result == null || result.files.isEmpty || !mounted) return;

    final file = result.files.first;
    if (file.path == null) return;

    setState(() => _sending = true);

    final authProvider = context.read<AuthProvider>();
    final chatProvider = context.read<ChatProvider>();
    final connection = authProvider.activeConnection;

    if (connection != null && authProvider.privateKeyPem != null) {
      await chatProvider.sendFileMessage(
        connection,
        authProvider.privateKeyPem!,
        filePath: file.path!,
        isImage: false,
      );
    }

    if (!mounted) return;
    setState(() => _sending = false);
  }

  void _showInviteCode() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text(AppStrings.inviteCode),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppTheme.bgInput,
                borderRadius: BorderRadius.circular(8),
              ),
              child: SelectableText(
                widget.group.inviteCode,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 2,
                  color: AppTheme.lightPurple,
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Share this code with others to let them join the group',
              style: TextStyle(
                fontSize: 12,
                color: AppTheme.textSecondary,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text(AppStrings.cancel),
          ),
          FilledButton.icon(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: widget.group.inviteCode));
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Invite code copied to clipboard'),
                  duration: Duration(seconds: 1),
                ),
              );
            },
            icon: const Icon(Icons.copy, size: 18),
            label: const Text('Copy'),
          ),
        ],
      ),
    );
  }

  Future<void> _leaveGroup() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text(AppStrings.leaveGroup),
        content: const Text(AppStrings.leaveGroupConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text(AppStrings.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text(AppStrings.confirm),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      final connection = context.read<AuthProvider>().activeConnection;
      connection?.leaveGroup(widget.group.id);
      context.read<AuthProvider>().removeGroup(widget.group.id);
      Navigator.pop(context);
    }
  }
}

class _InputBar extends StatelessWidget {
  final TextEditingController controller;
  final VoidCallback onSend;
  final VoidCallback onImagePick;
  final VoidCallback onFilePick;
  final bool sending;

  const _InputBar({
    required this.controller,
    required this.onSend,
    required this.onImagePick,
    required this.onFilePick,
    required this.sending,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        border: Border(top: BorderSide(color: AppTheme.primaryPurple.withValues(alpha: 0.2))),
      ),
      child: SafeArea(
        child: Row(
          children: [
            IconButton(
              icon: const Icon(Icons.image, color: AppTheme.lightPurple),
              onPressed: onImagePick,
              tooltip: AppStrings.selectImage,
            ),
            IconButton(
              icon: const Icon(Icons.attach_file, color: AppTheme.lightPurple),
              onPressed: onFilePick,
              tooltip: AppStrings.selectFile,
            ),
            Expanded(
              child: TextField(
                controller: controller,
                decoration: const InputDecoration(
                  hintText: AppStrings.typeMessage,
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
                maxLines: null,
                textCapitalization: TextCapitalization.sentences,
                onSubmitted: (_) => onSend(),
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              icon: sending
                  ? const SizedBox(
                height: 20,
                width: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
                  : const Icon(Icons.send, color: AppTheme.primaryPurple),
              onPressed: sending ? null : onSend,
            ),
          ],
        ),
      ),
    );
  }
}