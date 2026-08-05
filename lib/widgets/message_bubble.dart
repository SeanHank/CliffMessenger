import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:open_file/open_file.dart';
import '../core/constants/theme.dart';
import '../core/utils/utils.dart';
import '../models/message.dart';
import '../client/storage/file_storage.dart';

class MessageBubble extends StatefulWidget {
  final MessageModel message;
  final bool isMe;
  final String Function(Uint8List key) onDecrypt;
  final Uint8List? groupKey;
  final Future<void> Function()? onDownload;

  const MessageBubble({
    super.key,
    required this.message,
    required this.isMe,
    required this.onDecrypt,
    this.groupKey,
    this.onDownload,
  });

  @override
  State<MessageBubble> createState() => _MessageBubbleState();
}

class _MessageBubbleState extends State<MessageBubble> {
  String? _decryptedContent;
  String? _localFilePath;
  bool _downloading = false;

  @override
  void initState() {
    super.initState();
    _loadLocalFile();
    _decryptContent();
  }

  Future<void> _decryptContent() async {
    try {
      final decrypted = widget.onDecrypt(widget.groupKey!);
      if (mounted) {
        setState(() {
          _decryptedContent = decrypted;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _decryptedContent = '[Decryption Failed]';
        });
      }
    }
  }

  // Future<void> _loadLocalFile() async {
  //   if (widget.message.attachment != null) {
  //     final path = await ClientFileStorage.getFilePath(widget.message.attachment!.fileId);
  //     if (mounted) {
  //       setState(() => _localFilePath = path);
  //     }
  //   }
  // }
  // Future<void> _loadLocalFile() async {
  //   if (widget.message.attachment != null) {
  //     final path = await ClientFileStorage.getFilePath(widget.message.attachment!.fileId);
  //     if (path == null) {
  //       // 文件不存在，触发下载
  //       _downloadFile();
  //     } else if (mounted) {
  //       setState(() => _localFilePath = path);
  //     }
  //   }
  // }
  Future<void> _loadLocalFile() async {
    if (widget.message.attachment != null) {
      final path = await ClientFileStorage.getFilePath(widget.message.attachment!.fileId);
      if (mounted) {
        setState(() => _localFilePath = path);
      }
    }
  }

  @override
  void didUpdateWidget(covariant MessageBubble oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 当 widget 更新时，重新检查文件是否存在
    if (oldWidget.message.attachment?.fileId != widget.message.attachment?.fileId ||
        _localFilePath == null) {
      _loadLocalFile();
    }
  }

  Future<void> _downloadFile() async {
    if (_downloading) return;
    setState(() => _downloading = true);
    try {
      await widget.onDownload?.call();
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        mainAxisAlignment:
            widget.isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: [
          if (!widget.isMe) ...[
            CircleAvatar(
              radius: 16,
              backgroundColor: AppTheme.primaryPurple,
              child: Text(
                widget.message.senderNickname.isNotEmpty
                    ? widget.message.senderNickname[0].toUpperCase()
                    : '?',
                style: const TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 14,
                ),
              ),
            ),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: widget.isMe ? AppTheme.primaryPurple : AppTheme.bgInput,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (!widget.isMe)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text(
                        widget.message.senderNickname,
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppTheme.lightPurple,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  _buildContent(),
                  const SizedBox(height: 4),
                  Text(
                    _formatTime(widget.message.timestamp),
                    style: TextStyle(
                      fontSize: 10,
                      color: widget.isMe
                          ? Colors.white.withValues(alpha: 0.7)
                          : AppTheme.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (widget.isMe) const SizedBox(width: 8),
        ],
      ),
    );
  }

  Widget _buildContent() {
    switch (widget.message.type) {
      case MessageType.text:
        return Text(
          _decryptedContent ?? widget.message.encryptedContent,
          style: const TextStyle(color: AppTheme.textPrimary, fontSize: 15),
        );
      case MessageType.image:
        return _buildImageContent();
      case MessageType.file:
        return _buildFileContent();
    }
  }

  // Widget _buildImageContent() {
  //   if (_localFilePath != null) {
  //     return ClipRRect(
  //       borderRadius: BorderRadius.circular(8),
  //       child: Image.file(
  //         File(_localFilePath!),
  //         width: 200,
  //         fit: BoxFit.cover,
  //       ),
  //     );
  //   }
  //   return Container(
  //     width: 200,
  //     height: 150,
  //     decoration: BoxDecoration(
  //       color: Colors.black26,
  //       borderRadius: BorderRadius.circular(8),
  //     ),
  //     child: const Center(
  //       child: Icon(Icons.image, size: 48, color: AppTheme.textSecondary),
  //     ),
  //   );
  // }
  Widget _buildImageContent() {
    // if (_localFilePath != null) {
    //   return ClipRRect(
    //     borderRadius: BorderRadius.circular(8),
    //     child: Image.file(
    //       File(_localFilePath!),
    //       width: 200,
    //       fit: BoxFit.cover,
    //     ),
    //   );
    // }
    if (_localFilePath != null) {
      return GestureDetector(
        onTap: () => _showFullScreenImage(context),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.file(
            File(_localFilePath!),
            width: 200,
            fit: BoxFit.cover,
          ),
        ),
      );
    }

    // 未下载状态 - 显示可点击下载区域
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: _downloading ? null : _downloadFile,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          width: 200,
          height: 150,
          decoration: BoxDecoration(
            color: Colors.black26,
            borderRadius: BorderRadius.circular(8),
          ),
          child: _downloading
              ? const Center(
                  child: CircularProgressIndicator(
                    color: AppTheme.lightPurple,
                    strokeWidth: 2,
                  ),
                )
              : Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.download,
                      size: 48,
                      color: AppTheme.lightPurple,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Tap to download',
                      style: TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }

  // void _showFullScreenImage(BuildContext context) {
  //   showDialog(
  //     context: context,
  //     barrierColor: Colors.black87,
  //     builder: (context) => Dialog(
  //       backgroundColor: Colors.transparent,
  //       insetPadding: EdgeInsets.zero,
  //       child: Stack(
  //         children: [
  //           // 点击背景关闭
  //           GestureDetector(
  //             onTap: () => Navigator.pop(context),
  //             child: Container(color: Colors.black87),
  //           ),
  //           // 居中图片（可缩放）
  //           InteractiveViewer(
  //             minScale: 0.5,
  //             maxScale: 4.0,
  //             child: Center(
  //               child: Image.file(File(_localFilePath!)),
  //             ),
  //           ),
  //           // 关闭按钮
  //           Positioned(
  //             top: 50,
  //             right: 20,
  //             child: IconButton(
  //               onPressed: () => Navigator.pop(context),
  //               icon: const Icon(Icons.close, color: Colors.white, size: 32),
  //             ),
  //           ),
  //         ],
  //       ),
  //     ),
  //   );
  // }
  // void _showFullScreenImage(BuildContext context) {
  //   showDialog(
  //     context: context,
  //     barrierColor: Colors.black87,
  //     builder: (context) => Dialog(
  //       backgroundColor: Colors.transparent,
  //       insetPadding: EdgeInsets.zero,
  //       child: Stack(
  //         children: [
  //           // 点击背景关闭
  //           GestureDetector(
  //             onTap: () => Navigator.pop(context),
  //             child: Container(color: Colors.black87),
  //           ),
  //           // 居中图片（可缩放）
  //           InteractiveViewer(
  //             minScale: 0.5,
  //             maxScale: 4.0,
  //             child: Center(
  //               child: Image.file(File(_localFilePath!)),
  //             ),
  //           ),
  //           // 顶部操作栏
  //           Positioned(
  //             top: 50,
  //             left: 20,
  //             right: 20,
  //             child: Row(
  //               mainAxisAlignment: MainAxisAlignment.end,
  //               children: [
  //                 // 在文件夹显示按钮
  //                 Container(
  //                   decoration: BoxDecoration(
  //                     color: Colors.black54,
  //                     borderRadius: BorderRadius.circular(25),
  //                   ),
  //                   child: IconButton(
  //                     onPressed: () {
  //                       _openFileDirectory();
  //                     },
  //                     icon: const Icon(Icons.folder_open, color: Colors.white, size: 24),
  //                     tooltip: 'Show in Folder',
  //                   ),
  //                 ),
  //                 SizedBox(width: 16),
  //                 // 关闭按钮 - 添加深色圆角背景
  //                 Container(
  //                   decoration: BoxDecoration(
  //                     color: Colors.black54,
  //                     borderRadius: BorderRadius.circular(25),
  //                   ),
  //                   child: IconButton(
  //                     onPressed: () => Navigator.pop(context),
  //                     icon: const Icon(Icons.close, color: Colors.white, size: 28),
  //                   ),
  //                 ),
  //               ],
  //             ),
  //           ),
  //           // 底部信息栏（可选：显示文件名）
  //           Positioned(
  //             bottom: 50,
  //             left: 20,
  //             right: 20,
  //             child: Center(
  //               child: Container(
  //                 padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
  //                 decoration: BoxDecoration(
  //                   color: Colors.black54,
  //                   borderRadius: BorderRadius.circular(20),
  //                 ),
  //                 child: Text(
  //                   widget.message.attachment?.fileName ?? 'Image',
  //                   style: const TextStyle(color: Colors.white, fontSize: 14),
  //                   overflow: TextOverflow.ellipsis,
  //                 ),
  //               ),
  //             ),
  //           ),
  //         ],
  //       ),
  //     ),
  //   );
  // }
  void _showFullScreenImage(BuildContext context) {
    showDialog(
      context: context,
      barrierColor: Colors.black87,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: EdgeInsets.zero,
        child: Stack(
          children: [
            // 居中图片（可缩放）+ 点击关闭
            InteractiveViewer(
              minScale: 0.5,
              maxScale: 4.0,
              child: GestureDetector(
                onTap: () => Navigator.pop(context),
                child: Center(
                  child: Image.file(File(_localFilePath!)),
                ),
              ),
            ),
            // 顶部操作栏
            Positioned(
              top: 50,
              left: 20,
              right: 20,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  // 在文件夹显示按钮
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(25),
                    ),
                    child: IconButton(
                      onPressed: () {
                        _openFileDirectory();
                      },
                      icon: const Icon(Icons.folder_open, color: Colors.white, size: 24),
                      tooltip: 'Show in Folder',
                    ),
                  ),
                  SizedBox(width: 16),
                  // 关闭按钮
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(25),
                    ),
                    child: IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close, color: Colors.white, size: 28),
                    ),
                  ),
                ],
              ),
            ),
            // 底部信息栏
            Positioned(
              bottom: 50,
              left: 20,
              right: 20,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    widget.message.attachment?.fileName ?? 'Image',
                    style: const TextStyle(color: Colors.white, fontSize: 14),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Widget _buildFileContent() {
  //   final attachment = widget.message.attachment;
  //   if (attachment == null) {
  //     return const Text('File', style: TextStyle(color: AppTheme.textPrimary));
  //   }
  //   return Row(
  //     mainAxisSize: MainAxisSize.min,
  //     children: [
  //       const Icon(Icons.attach_file, size: 20, color: AppTheme.textSecondary),
  //       const SizedBox(width: 8),
  //       Flexible(
  //         child: Column(
  //           crossAxisAlignment: CrossAxisAlignment.start,
  //           children: [
  //             Text(
  //               attachment.fileName,
  //               style: const TextStyle(
  //                 color: AppTheme.textPrimary,
  //                 fontWeight: FontWeight.w500,
  //               ),
  //               overflow: TextOverflow.ellipsis,
  //             ),
  //             Text(
  //               FileUtils.formatFileSize(attachment.fileSize),
  //               style: const TextStyle(
  //                 color: AppTheme.textSecondary,
  //                 fontSize: 12,
  //               ),
  //             ),
  //           ],
  //         ),
  //       ),
  //     ],
  //   );
  // }
  // Widget _buildFileContent() {
  //   final attachment = widget.message.attachment;
  //   if (attachment == null) {
  //     return const Text('File', style: TextStyle(color: AppTheme.textPrimary));
  //   }
  //
  //   final isDownloaded = _localFilePath != null;
  //
  //   return Row(
  //     mainAxisSize: MainAxisSize.min,
  //     children: [
  //       const Icon(Icons.attach_file, size: 20, color: AppTheme.textSecondary),
  //       const SizedBox(width: 8),
  //       Flexible(
  //         child: Column(
  //           crossAxisAlignment: CrossAxisAlignment.start,
  //           children: [
  //             Text(
  //               attachment.fileName,
  //               style: const TextStyle(
  //                 color: AppTheme.textPrimary,
  //                 fontWeight: FontWeight.w500,
  //               ),
  //               overflow: TextOverflow.ellipsis,
  //             ),
  //             Text(
  //               FileUtils.formatFileSize(attachment.fileSize),
  //               style: const TextStyle(
  //                 color: AppTheme.textSecondary,
  //                 fontSize: 12,
  //               ),
  //             ),
  //           ],
  //         ),
  //       ),
  //       const SizedBox(width: 8),
  //       // 使用 InkWell 替代 GestureDetector，添加明确尺寸
  //       if (!isDownloaded)
  //         Material(
  //           color: Colors.transparent,
  //           child: InkWell(
  //             onTap: widget.onDownload,
  //             borderRadius: BorderRadius.circular(8),
  //             child: Padding(
  //               padding: const EdgeInsets.all(8),
  //               child: Icon(
  //                 Icons.download,
  //                 size: 24,
  //                 color: AppTheme.lightPurple,
  //               ),
  //             ),
  //           ),
  //         )
  //       else
  //         Padding(
  //           padding: const EdgeInsets.all(8),
  //           child: Icon(
  //             Icons.check_circle,
  //             size: 24,
  //             color: AppTheme.successGreen,
  //           ),
  //         ),
  //     ],
  //   );
  // }

  Widget _buildFileContent() {
    final attachment = widget.message.attachment;
    if (attachment == null) {
      return const Text('File', style: TextStyle(color: AppTheme.textPrimary));
    }

    final isDownloaded = _localFilePath != null;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.attach_file, size: 20, color: AppTheme.textSecondary),
        const SizedBox(width: 8),
        Flexible(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                attachment.fileName,
                style: const TextStyle(
                  color: AppTheme.textPrimary,
                  fontWeight: FontWeight.w500,
                ),
                overflow: TextOverflow.ellipsis,
              ),
              Text(
                FileUtils.formatFileSize(attachment.fileSize),
                style: const TextStyle(
                  color: AppTheme.textSecondary,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        if (isDownloaded)
        // 已下载 - 点击打开文件
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: _openFileDirectory,
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Icon(
                  Icons.visibility,
                  size: 24,
                  color: AppTheme.lightPurple,
                ),
              ),
            ),
          )
        else
        // 未下载 - 点击下载
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: _downloading ? null : _downloadFile,
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: _downloading
                    ? const SizedBox(
                        height: 24,
                        width: 24,
                        child: CircularProgressIndicator(
                          color: AppTheme.lightPurple,
                          strokeWidth: 2,
                        ),
                      )
                    : Icon(
                        Icons.download,
                        size: 24,
                        color: AppTheme.lightPurple,
                      ),
              ),
            ),
          ),
      ],
    );
  }

// 新增方法
//   Future<void> _openFile() async {
//     if (_localFilePath != null) {
//       await OpenFile.open(_localFilePath!);
//     }
//   }
//   Future<void> _openFile() async {
//     if (_localFilePath == null) return;
//
//     try {
//       await OpenFile.open(_localFilePath!).timeout(
//         const Duration(seconds: 5),
//         onTimeout: () => _openFileDirectory(),
//       );
//     } catch (e) {
//       _openFileDirectory();
//     }
//   }
  Future<void> _openFileDirectory() async {
    if (_localFilePath == null) return;

    try {
      final directory = File(_localFilePath!).parent.path;
      await OpenFile.open(directory);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to open file: $e'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }

  String _formatTime(int timestamp) {
    final date = DateTime.fromMillisecondsSinceEpoch(timestamp);
    return '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }
}
