import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../models/models.dart';
import '../services/services.dart';
import '../utils/remote_path.dart';

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
  int _uploadedBytes = 0;
  int _totalBytes = 0;
  double _overallProgress = 0.0;
  double _currentProgress = 0.0;
  double _uploadSpeed = 0.0; // KB/s
  String _errorMessage = '';

  DateTime? _startTime;
  Timer? _speedTimer;
  int _lastBytesUploaded = 0;
  List<int> _uploadThresholds = [];
  int _nextThresholdIndex = 0;

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
    debugPrint(
      '[ManualSync] [${widget.task.id}] Starting manual sync for '
      '"${widget.task.name}"',
    );

    SecurityScopedBookmarkSession? bookmarkSession;

    try {
      if (Platform.isMacOS && widget.task.localBookmark == null) {
        throw Exception('macOS 需要重新授权该目录，请编辑任务重新选择本地路径。');
      }

      bookmarkSession = await MacOSSecurityScopedBookmark.startAccess(
        widget.task.localBookmark,
      );

      // 1. 连接到服务器
      final config = await _storage.loadConfig();
      if (config == null) {
        throw Exception('配置文件不存在');
      }
      debugPrint(
        '[ManualSync] [${widget.task.id}] Connecting to '
        '${config.server.host}:${config.server.port}',
      );

      await _client.connect(
        host: config.server.host,
        port: config.server.port,
        username: config.server.username,
        password: config.server.password,
      );
      debugPrint('[ManualSync] [${widget.task.id}] Connection established');

      setState(() {
        _isConnecting = false;
        _isScanning = true;
      });

      // 2. 扫描文件变更
      final remoteFullPath = buildRemoteTaskPath(config.server, widget.task);

      _changes = await _engine.scanChanges(
        widget.task.localDir,
        remoteFullPath,
        lastSyncTime: widget.task.lastSyncTime,
      );
      debugPrint(
        '[ManualSync] [${widget.task.id}] Scan finished: '
        'upload=${_changes!.toUpload.length}, '
        'delete=${_changes!.toDelete.length}, '
        'conflict=${_changes!.conflicts.length}',
      );

      setState(() {
        _isScanning = false;
        _totalFiles = _changes!.toUpload.length;
        _totalBytes = _changes!.toUpload.fold<int>(
          0,
          (sum, file) => sum + file.size,
        );
        _uploadThresholds = [];
        var cumulative = 0;
        for (final file in _changes!.toUpload) {
          cumulative += file.size;
          _uploadThresholds.add(cumulative);
        }
        _uploadedFiles = 0;
        _uploadedBytes = 0;
        _overallProgress = 0.0;
        _currentProgress = 0.0;
        _nextThresholdIndex = 0;
      });

      // 3. 检查是否有待删除的文件
      if (_changes!.toDelete.isNotEmpty && mounted) {
        final confirmed = await _showDeletionConfirmDialog();
        if (!confirmed) {
          // 用户取消删除，从变更中移除删除项
          debugPrint(
            '[ManualSync] [${widget.task.id}] User skipped deleting '
            '${_changes!.toDelete.length} file(s)',
          );
          _changes = FileChanges(
            toUpload: _changes!.toUpload,
            toDelete: [],
            conflicts: _changes!.conflicts,
          );
        } else {
          debugPrint(
            '[ManualSync] [${widget.task.id}] User confirmed deleting '
            '${_changes!.toDelete.length} file(s)',
          );
        }
      }

      // 4. 执行同步
      if (!_isCancelled && mounted) {
        setState(() {
          _isSyncing = true;
        });

        _startSpeedCalculation();

        debugPrint(
          '[ManualSync] [${widget.task.id}] Uploading '
          '${_changes!.toUpload.length} file(s) to $remoteFullPath',
        );
        _result = await _engine.performFullSync(
          localDir: widget.task.localDir,
          remoteDir: remoteFullPath,
          lastSyncTime: widget.task.lastSyncTime,
          autoDelete: false, // 手动处理删除
          onProgress: _onProgress,
        );
        debugPrint(
          '[ManualSync] [${widget.task.id}] Sync stats -> uploaded: '
          '${_result!.uploadedCount}, deleted: ${_result!.deletedCount}, '
          'conflicts: ${_result!.conflictCount}, errors: '
          '${_result!.errors.length}',
        );

        _speedTimer?.cancel();

        // 5. 如果用户确认删除，执行删除操作
        if (_changes!.toDelete.isNotEmpty && mounted) {
          debugPrint(
            '[ManualSync] [${widget.task.id}] Deleting '
            '${_changes!.toDelete.length} remote file(s)',
          );
          await _engine.executeDeletions(
            _changes!.toDelete,
            remoteDir: remoteFullPath,
          );
          debugPrint(
            '[ManualSync] [${widget.task.id}] Remote deletions completed',
          );
        }

        // 6. 更新任务状态
        await _updateTaskStatus();
        debugPrint(
          '[ManualSync] [${widget.task.id}] Last sync timestamp updated',
        );

        setState(() {
          _isSyncing = false;
          _isCompleted = true;
        });
      }
    } catch (e, stack) {
      setState(() {
        _errorMessage = e.toString();
        _isCompleted = true;
      });
      debugPrint(
        '[ManualSync] [${widget.task.id}] Sync failed: $e\n$stack',
      );
    } finally {
      await MacOSSecurityScopedBookmark.stopAccess(bookmarkSession);
      await _client.disconnect();
      debugPrint(
        '[ManualSync] [${widget.task.id}] Connection closed '
        '(cancelled=$_isCancelled)',
      );
    }
  }

  /// 进度回调
  void _onProgress(int uploaded, int total) {
    if (_isCancelled) return;

    setState(() {
      final totalBytes = total > 0
          ? total
          : (_totalBytes > 0 ? _totalBytes : 1);
      _overallProgress =
          totalBytes > 0 ? (uploaded / totalBytes).clamp(0.0, 1.0) : 0.0;
      _uploadedBytes = uploaded;
      _lastBytesUploaded = uploaded;

      while (_nextThresholdIndex < _uploadThresholds.length &&
          uploaded >= _uploadThresholds[_nextThresholdIndex]) {
        _nextThresholdIndex++;
      }
      _uploadedFiles = _nextThresholdIndex;

      if (_nextThresholdIndex < _uploadThresholds.length) {
        final prevThreshold =
            _nextThresholdIndex == 0 ? 0 : _uploadThresholds[_nextThresholdIndex - 1];
        final currentThreshold = _uploadThresholds[_nextThresholdIndex];
        final currentSize = currentThreshold - prevThreshold;
        final currentUploaded = uploaded - prevThreshold;
        _currentProgress =
            currentSize > 0 ? currentUploaded / currentSize : 0.0;
      } else {
        _currentProgress = 1.0;
      }
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
    debugPrint('[ManualSync] [${widget.task.id}] Sync cancelled by user');
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

  String _formatBytes(int bytes) {
    if (bytes <= 0) return '0 B';
    const units = ['B', 'KB', 'MB', 'GB', 'TB'];
    var value = bytes.toDouble();
    var unitIndex = 0;
    while (value >= 1024 && unitIndex < units.length - 1) {
      value /= 1024;
      unitIndex++;
    }
    return '${value.toStringAsFixed(unitIndex == 0 ? 0 : 1)} ${units[unitIndex]}';
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
              '${(_overallProgress * 100).clamp(0, 100).toStringAsFixed(0)}%',
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          '${_formatBytes(_uploadedBytes)} / ${_formatBytes(_totalBytes)}',
          style: const TextStyle(fontSize: 12, color: Colors.grey),
        ),
        const SizedBox(height: 8),
        LinearProgressIndicator(
          value: _overallProgress.clamp(0.0, 1.0),
          minHeight: 8,
        ),

        const SizedBox(height: 16),

        // 当前文件进度
        if (_totalFiles > 0 && _uploadedFiles < _totalFiles) ...[
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
