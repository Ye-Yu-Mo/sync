import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../models/models.dart';
import '../services/services.dart';
import 'server_config_screen.dart';
import 'task_edit_screen.dart';
import 'sync_progress_screen.dart';

/// 任务列表界面
class TaskListScreen extends StatefulWidget {
  const TaskListScreen({super.key});

  @override
  State<TaskListScreen> createState() => _TaskListScreenState();
}

class _TaskListScreenState extends State<TaskListScreen> {
  final StorageService _storage = StorageService();
  final SchedulerService _scheduler = SchedulerService();
  late final TaskManager _taskManager;
  List<SyncTask> _tasks = [];
  bool _isLoading = true;
  bool _needsServerConfig = false;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _taskManager = TaskManager(_storage, scheduler: _scheduler);
    _loadTasks();
  }

  Future<void> _loadTasks() async {
    setState(() {
      _isLoading = true;
      _loadError = null;
    });
    try {
      final tasks = await _taskManager.loadTasks();
      if (mounted) {
        setState(() {
          _tasks = tasks;
          _isLoading = false;
          _needsServerConfig = false;
        });
      }
    } catch (e) {
      final needsConfig =
          e is TaskManagerException && e.message.contains('服务器配置');
      if (mounted) {
        setState(() {
          _tasks = [];
          _isLoading = false;
          _needsServerConfig = needsConfig;
          _loadError = needsConfig ? null : e.toString();
        });

        if (!needsConfig) {
          // 延迟显示错误，避免在初始化时显示
          Future.delayed(const Duration(milliseconds: 500), () {
            if (mounted && _loadError != null) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('加载任务失败: $e'),
                  duration: const Duration(seconds: 3),
                ),
              );
            }
          });
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('SFTP 同步管理'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            onPressed: _openServerConfig,
            tooltip: '服务器配置',
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadTasks,
            tooltip: '刷新',
          ),
        ],
      ),
      body: _buildBody(),
      floatingActionButton: FloatingActionButton(
        onPressed:
            _needsServerConfig ? _openServerConfig : _createNewTask,
        tooltip: _needsServerConfig ? '先配置服务器' : '新建任务',
        child: Icon(_needsServerConfig ? Icons.settings : Icons.add),
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_needsServerConfig) {
      return _buildServerConfigPrompt();
    }

    if (_loadError != null) {
      return _buildErrorPlaceholder();
    }

    if (_tasks.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.inbox, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              '暂无同步任务',
              style: TextStyle(fontSize: 18, color: Colors.grey[600]),
            ),
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: _createNewTask,
              icon: const Icon(Icons.add),
              label: const Text('创建第一个任务'),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadTasks,
      child: ListView.builder(
        itemCount: _tasks.length,
        padding: const EdgeInsets.all(8),
        itemBuilder: (context, index) {
          return TaskCard(
            task: _tasks[index],
            onSync: () => _syncTask(_tasks[index]),
            onToggle: (enabled) => _toggleTask(_tasks[index], enabled),
            onEdit: () => _editTask(_tasks[index]),
            onDelete: () => _deleteTask(_tasks[index]),
          );
        },
      ),
    );
  }

  Widget _buildServerConfigPrompt() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.settings_suggest, size: 72, color: Colors.orange[300]),
            const SizedBox(height: 16),
            const Text(
              '请先创建服务器配置',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              '配置 SFTP 服务器后即可创建同步任务。',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _openServerConfig,
              icon: const Icon(Icons.settings),
              label: const Text('配置服务器'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorPlaceholder() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 64, color: Colors.redAccent),
            const SizedBox(height: 16),
            const Text(
              '加载任务失败',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              _loadError ?? '未知错误',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.black54),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _loadTasks,
              icon: const Icon(Icons.refresh),
              label: const Text('重试'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _createNewTask() async {
    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (context) => const TaskEditScreen(),
      ),
    );

    // 如果保存成功，刷新任务列表
    if (result == true) {
      _taskManager.clearCache();
      await _loadTasks();
    }
  }

  Future<void> _openServerConfig() async {
    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (context) => const ServerConfigScreen(),
      ),
    );

    if (result == true) {
      _taskManager.clearCache();
      await _loadTasks();
    }
  }

  Future<void> _syncTask(SyncTask task) async {
    final startedAt = DateTime.now();
    debugPrint(
      '[ManualSync] Triggered manual sync for task ${task.id} (${task.name})',
    );

    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (context) => SyncProgressScreen(task: task),
      ),
    );

    final elapsed = DateTime.now().difference(startedAt);

    if (result == true && mounted) {
      debugPrint(
        '[ManualSync] Task ${task.id} completed in ${elapsed.inSeconds}s',
      );
      // 如果同步成功，刷新任务列表
      await _loadTasks();
    } else if (result == false) {
      debugPrint(
        '[ManualSync] Task ${task.id} cancelled after ${elapsed.inSeconds}s',
      );
    } else {
      debugPrint(
        '[ManualSync] Task ${task.id} exited without completion '
        '(${elapsed.inSeconds}s)',
      );
    }
  }

  Future<void> _toggleTask(SyncTask task, bool enabled) async {
    try {
      await _taskManager.toggleTask(task.id, enabled);
      await _loadTasks();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(enabled ? '已启用: ${task.name}' : '已禁用: ${task.name}'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('操作失败: $e')),
        );
      }
    }
  }

  Future<void> _editTask(SyncTask task) async {
    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (context) => TaskEditScreen(task: task),
      ),
    );

    // 如果保存成功，刷新任务列表
    if (result == true) {
      _taskManager.clearCache();
      await _loadTasks();
    }
  }

  Future<void> _deleteTask(SyncTask task) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认删除'),
        content: Text('确定要删除任务"${task.name}"吗？\n\n此操作不会删除已同步的文件。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('删除'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await _taskManager.deleteTask(task.id);
        await _loadTasks();

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('已删除: ${task.name}')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('删除失败: $e')),
          );
        }
      }
    }
  }
}

/// 任务卡片
class TaskCard extends StatelessWidget {
  final SyncTask task;
  final VoidCallback onSync;
  final ValueChanged<bool> onToggle;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const TaskCard({
    super.key,
    required this.task,
    required this.onSync,
    required this.onToggle,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 任务名称和状态
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        task.name,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      _buildStatusRow(),
                    ],
                  ),
                ),
                // 启用/禁用开关
                Switch(
                  value: task.enabled,
                  onChanged: onToggle,
                ),
              ],
            ),

            const Divider(height: 16),

            // 目录信息
            _buildInfoRow(Icons.folder_outlined, task.localDir),
            const SizedBox(height: 4),
            _buildInfoRow(Icons.cloud_outlined, task.remoteDir),
            const SizedBox(height: 4),
            _buildInfoRow(
              Icons.schedule,
              '每 ${task.intervalMinutes} 分钟',
            ),

            const SizedBox(height: 12),

            // 操作按钮
            Row(
              children: [
                // 手动同步按钮
                ElevatedButton.icon(
                  onPressed: task.status == SyncStatus.syncing ? null : onSync,
                  icon: Icon(
                    task.status == SyncStatus.syncing
                        ? Icons.sync
                        : Icons.sync_outlined,
                    size: 18,
                  ),
                  label: Text(
                    task.status == SyncStatus.syncing ? '同步中...' : '手动同步',
                  ),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                  ),
                ),
                const SizedBox(width: 8),

                // 编辑按钮
                OutlinedButton.icon(
                  onPressed: onEdit,
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  label: const Text('编辑'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                  ),
                ),
                const Spacer(),

                // 删除按钮
                IconButton(
                  onPressed: onDelete,
                  icon: const Icon(Icons.delete_outline),
                  color: Colors.red,
                  tooltip: '删除',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// 构建状态行
  Widget _buildStatusRow() {
    Color statusColor;
    IconData statusIcon;
    String statusText;

    switch (task.status) {
      case SyncStatus.syncing:
        statusColor = Colors.blue;
        statusIcon = Icons.sync;
        statusText = '同步中...';
      case SyncStatus.error:
        statusColor = Colors.red;
        statusIcon = Icons.error_outline;
        statusText = '同步失败';
      case SyncStatus.idle:
        statusColor = Colors.grey;
        statusIcon = Icons.check_circle_outline;
        statusText = task.statusText; // 使用 SyncTask 的 statusText 属性
    }

    return Row(
      children: [
        Icon(statusIcon, size: 16, color: statusColor),
        const SizedBox(width: 4),
        Text(
          statusText,
          style: TextStyle(fontSize: 13, color: statusColor),
        ),
      ],
    );
  }

  /// 构建信息行
  Widget _buildInfoRow(IconData icon, String text) {
    return Row(
      children: [
        Icon(icon, size: 16, color: Colors.grey[600]),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            text,
            style: TextStyle(fontSize: 13, color: Colors.grey[700]),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}
