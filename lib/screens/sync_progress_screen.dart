import 'dart:async';
import 'package:flutter/material.dart';
import '../models/models.dart';
import '../services/services.dart';

/// 同步进度界面
class SyncProgressScreen extends StatefulWidget {
  final SyncTask task;

  const SyncProgressScreen({
    super.key,
    required this.task,
  });

  @override
  State<SyncProgressScreen> createState() => _SyncProgressScreenState();
}

class _SyncProgressScreenState extends State<SyncProgressScreen> {
  final StorageService _storage = StorageService();
  late final ResilientSftpClient _client;
  late final SyncEngine _engine;

  bool _isConnecting = true;
  bool _isScanning = false;
  bool _isSyncing = false;
  bool _isCompleted = false;
  bool _isCancelled = false;

  FileChanges? _changes;
  SyncResult? _result;
  int _uploadedFiles = 0;
  int _totalFiles = 0;
  double _currentProgress = 0.0;
  double _uploadSpeed = 0.0; // KB/s
  String _errorMessage = '';

  DateTime? _startTime;
  Timer? _speedTimer;
  int _lastBytesUploaded = 0;

  @override
  void initState() {
    super.initState();
    _client = ResilientSftpClient();
    _engine = SyncEngine(_client);
    _startSync();
  }

  @override
  void dispose() {
    _speedTimer?.cancel();
    _client.disconnect();
    super.dispose();
  }

  /// 开始同步流程
  Future<void> _startSync() async {
    setState(() {
      _isConnecting = true;
      _startTime = DateTime.now();
    });

    try {
      // 1. 连接到服务器
      final config = await _storage.loadConfig();
      if (config == null) {
        throw Exception('配置文件不存在');
      }

      await _client.connect(
        host: config.server.host,
        port: config.server.port,
        username: config.server.username,
        password: config.server.password,
      );

      setState(() {
        _isConnecting = false;
        _isScanning = true;
      });

      // 2. 扫描文件变更
      final remoteFullPath = _joinRemotePath(
        '/data/${widget.task.fileBrowserUser}',
        widget.task.remoteDir,
      );

      _changes = await _engine.scanChanges(
        widget.task.localDir,
        remoteFullPath,
        lastSyncTime: widget.task.lastSyncTime,
      );

      setState(() {
        _isScanning = false;
        _totalFiles = _changes!.toUpload.length;
      });

      // 3. 检查是否有待删除的文件
      if (_changes!.toDelete.isNotEmpty && mounted) {
        final confirmed = await _showDeletionConfirmDialog();
        if (!confirmed) {
          // 用户取消删除，从变更中移除删除项
          _changes = FileChanges(
            toUpload: _changes!.toUpload,
            toDelete: [],
            conflicts: _changes!.conflicts,
          );
        }
      }

      // 4. 执行同步
      if (!_isCancelled && mounted) {
        setState(() {
          _isSyncing = true;
        });

        _startSpeedCalculation();

        _result = await _engine.performFullSync(
          localDir: widget.task.localDir,
          remoteDir: remoteFullPath,
          lastSyncTime: widget.task.lastSyncTime,
          autoDelete: false, // 手动处理删除
          onProgress: _onProgress,
        );

        _speedTimer?.cancel();

        // 更新上传文件数
        setState(() {
          _uploadedFiles = _result!.uploadedCount;
        });

        // 5. 如果用户确认删除，执行删除操作
        if (_changes!.toDelete.isNotEmpty && mounted) {
          await _engine.executeDeletions(
            _changes!.toDelete,
            remoteDir: remoteFullPath,
          );
        }

        // 6. 更新任务状态
        await _updateTaskStatus();

        setState(() {
          _isSyncing = false;
          _isCompleted = true;
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = e.toString();
        _isCompleted = true;
      });
    } finally {
      await _client.disconnect();
    }
  }

  /// 进度回调
  void _onProgress(int uploaded, int total) {
    if (_isCancelled) return;

    setState(() {
      _currentProgress = total > 0 ? uploaded / total : 0.0;
      _lastBytesUploaded = uploaded;
    });
  }

  /// 开始速度计算
  void _startSpeedCalculation() {
    int previousBytes = 0;
    _speedTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      final currentBytes = _lastBytesUploaded;
      final bytesPerSecond = currentBytes - previousBytes;
      previousBytes = currentBytes;

      if (mounted) {
        setState(() {
          _uploadSpeed = bytesPerSecond / 1024; // 转换为 KB/s
        });
      }
    });
  }

  /// 取消同步
  void _cancelSync() {
    setState(() {
      _isCancelled = true;
    });
    Navigator.of(context).pop(false);
  }

  /// 显示删除确认对话框
  Future<bool> _showDeletionConfirmDialog() async {
    return await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => DeletionConfirmDialog(
        files: _changes!.toDelete,
      ),
    ) ?? false;
  }

  /// 更新任务状态
  Future<void> _updateTaskStatus() async {
    try {
      final taskManager = TaskManager(_storage);
      await taskManager.updateLastSyncTime(
        widget.task.id,
        DateTime.now(),
      );
    } catch (e) {
      // 更新状态失败不影响主流程
    }
  }

  /// 拼接远程路径
  String _joinRemotePath(String base, String relative) {
    if (relative == '/') return base;
    final cleanBase = base.endsWith('/') ? base.substring(0, base.length - 1) : base;
    final cleanRelative = relative.startsWith('/') ? relative : '/$relative';
    return '$cleanBase$cleanRelative';
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_isSyncing,
      child: Scaffold(
        appBar: AppBar(
          title: Text('同步: ${widget.task.name}'),
          automaticallyImplyLeading: _isCompleted,
        ),
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 状态卡片
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildStatusRow(),
                      if (_isSyncing) ...[
                        const SizedBox(height: 16),
                        _buildProgressSection(),
                      ],
                      if (_isCompleted) ...[
                        const SizedBox(height: 16),
                        _buildResultSection(),
                      ],
                    ],
                  ),
                ),
              ),

              const Spacer(),

              // 操作按钮
              if (_isSyncing && !_isCancelled)
                ElevatedButton.icon(
                  onPressed: _cancelSync,
                  icon: const Icon(Icons.cancel),
                  label: const Text('取消同步'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                ),

              if (_isCompleted)
                ElevatedButton.icon(
                  onPressed: () => Navigator.of(context).pop(true),
                  icon: const Icon(Icons.check),
                  label: const Text('完成'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// 构建状态行
  Widget _buildStatusRow() {
    String statusText;
    IconData statusIcon;
    Color statusColor;

    if (_isConnecting) {
      statusText = '正在连接到服务器...';
      statusIcon = Icons.cloud_upload_outlined;
      statusColor = Colors.blue;
    } else if (_isScanning) {
      statusText = '正在扫描文件变更...';
      statusIcon = Icons.search;
      statusColor = Colors.blue;
    } else if (_isSyncing) {
      statusText = '正在同步...';
      statusIcon = Icons.sync;
      statusColor = Colors.blue;
    } else if (_isCancelled) {
      statusText = '已取消';
      statusIcon = Icons.cancel;
      statusColor = Colors.orange;
    } else if (_errorMessage.isNotEmpty) {
      statusText = '同步失败';
      statusIcon = Icons.error_outline;
      statusColor = Colors.red;
    } else if (_isCompleted) {
      statusText = '同步完成';
      statusIcon = Icons.check_circle_outline;
      statusColor = Colors.green;
    } else {
      statusText = '准备中...';
      statusIcon = Icons.info_outline;
      statusColor = Colors.grey;
    }

    return Row(
      children: [
        Icon(statusIcon, color: statusColor, size: 32),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                statusText,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: statusColor,
                ),
              ),
              if (_startTime != null)
                Text(
                  '耗时: ${_formatDuration(DateTime.now().difference(_startTime!))}',
                  style: const TextStyle(fontSize: 13, color: Colors.grey),
                ),
            ],
          ),
        ),
        if (_isConnecting || _isScanning || _isSyncing)
          const SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
      ],
    );
  }

  /// 构建进度部分
  Widget _buildProgressSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 总进度
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              '总进度: $_uploadedFiles / $_totalFiles',
              style: const TextStyle(fontSize: 14),
            ),
            Text(
              '${(_uploadedFiles / (_totalFiles > 0 ? _totalFiles : 1) * 100).toStringAsFixed(0)}%',
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        LinearProgressIndicator(
          value: _totalFiles > 0 ? _uploadedFiles / _totalFiles : 0.0,
          minHeight: 8,
        ),

        const SizedBox(height: 16),

        // 当前文件进度
        if (_currentProgress > 0) ...[
          const Text(
            '当前文件进度:',
            style: TextStyle(fontSize: 13, color: Colors.grey),
          ),
          const SizedBox(height: 8),
          LinearProgressIndicator(
            value: _currentProgress,
            minHeight: 4,
          ),
          const SizedBox(height: 16),
        ],

        // 上传速度
        Row(
          children: [
            const Icon(Icons.speed, size: 16, color: Colors.grey),
            const SizedBox(width: 4),
            Text(
              '${_uploadSpeed.toStringAsFixed(1)} KB/s',
              style: const TextStyle(fontSize: 13, color: Colors.grey),
            ),
          ],
        ),
      ],
    );
  }

  /// 构建结果部分
  Widget _buildResultSection() {
    if (_errorMessage.isNotEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '错误信息:',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: Colors.red,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _errorMessage,
            style: const TextStyle(fontSize: 13, color: Colors.red),
          ),
        ],
      );
    }

    if (_result == null) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildResultRow('已上传', _result!.uploadedCount, Icons.upload),
        const SizedBox(height: 8),
        _buildResultRow('已删除', _result!.deletedCount, Icons.delete),
        const SizedBox(height: 8),
        _buildResultRow('冲突文件', _result!.conflictCount, Icons.warning),
        if (_result!.errors.isNotEmpty) ...[
          const SizedBox(height: 8),
          _buildResultRow('错误', _result!.errors.length, Icons.error, isError: true),
        ],
      ],
    );
  }

  /// 构建结果行
  Widget _buildResultRow(String label, int count, IconData icon, {bool isError = false}) {
    return Row(
      children: [
        Icon(
          icon,
          size: 16,
          color: isError ? Colors.red : Colors.grey,
        ),
        const SizedBox(width: 8),
        Text(
          '$label: ',
          style: TextStyle(
            fontSize: 14,
            color: isError ? Colors.red : Colors.grey,
          ),
        ),
        Text(
          '$count',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: isError ? Colors.red : Colors.black,
          ),
        ),
      ],
    );
  }

  /// 格式化时长
  String _formatDuration(Duration duration) {
    final seconds = duration.inSeconds;
    if (seconds < 60) {
      return '$seconds 秒';
    } else if (seconds < 3600) {
      final minutes = seconds ~/ 60;
      final remainingSeconds = seconds % 60;
      return '$minutes 分 $remainingSeconds 秒';
    } else {
      final hours = seconds ~/ 3600;
      final minutes = (seconds % 3600) ~/ 60;
      return '$hours 小时 $minutes 分';
    }
  }
}

/// 删除确认对话框
class DeletionConfirmDialog extends StatelessWidget {
  final List<FileInfo> files;

  const DeletionConfirmDialog({
    super.key,
    required this.files,
  });

  @override
  Widget build(BuildContext context) {
    final totalSize = files.fold<int>(0, (sum, file) => sum + file.size);
    final sizeText = _formatBytes(totalSize);

    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.delete_outline, color: Colors.red.shade700),
          const SizedBox(width: 8),
          const Text('确认删除'),
        ],
      ),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 摘要信息
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(Icons.warning, color: Colors.red.shade700, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '将删除 ${files.length} 个文件（共 $sizeText）',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Colors.red.shade900,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            const Text(
              '以下文件将从服务器删除:',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
            ),

            const SizedBox(height: 8),

            // 文件列表
            Flexible(
              child: Container(
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey.shade300),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: files.length,
                  separatorBuilder: (context, index) => Divider(
                    height: 1,
                    color: Colors.grey.shade200,
                  ),
                  itemBuilder: (context, index) {
                    final file = files[index];
                    return ListTile(
                      dense: true,
                      leading: Icon(
                        _getFileIcon(file.relativePath),
                        size: 20,
                        color: Colors.grey.shade600,
                      ),
                      title: Text(
                        file.relativePath,
                        style: const TextStyle(fontSize: 13),
                      ),
                      trailing: Text(
                        _formatBytes(file.size),
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('取消'),
        ),
        ElevatedButton.icon(
          onPressed: () => Navigator.of(context).pop(true),
          icon: const Icon(Icons.delete),
          label: const Text('确认删除'),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.red,
            foregroundColor: Colors.white,
          ),
        ),
      ],
    );
  }

  /// 获取文件图标
  IconData _getFileIcon(String path) {
    final ext = path.split('.').last.toLowerCase();
    switch (ext) {
      case 'pdf':
        return Icons.picture_as_pdf;
      case 'doc':
      case 'docx':
        return Icons.description;
      case 'jpg':
      case 'jpeg':
      case 'png':
      case 'gif':
        return Icons.image;
      case 'zip':
      case 'rar':
      case '7z':
        return Icons.folder_zip;
      case 'mp4':
      case 'avi':
      case 'mkv':
        return Icons.video_file;
      case 'mp3':
      case 'wav':
      case 'flac':
        return Icons.audio_file;
      default:
        return Icons.insert_drive_file;
    }
  }

  /// 格式化字节大小
  String _formatBytes(int bytes) {
    if (bytes < 1024) {
      return '$bytes B';
    } else if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    } else if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    } else {
      return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
    }
  }
}
