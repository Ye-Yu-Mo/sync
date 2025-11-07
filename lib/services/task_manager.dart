import 'package:uuid/uuid.dart';
import '../models/models.dart';
import 'storage/storage_service.dart';

/// 任务管理器
class TaskManager {
  final StorageService _storage;
  AppConfig? _cachedConfig;

  TaskManager(this._storage);

  /// 加载所有任务
  Future<List<SyncTask>> loadTasks() async {
    final config = await _getConfig();
    return config.tasks;
  }

  /// 创建新任务（自动生成 UUID）
  Future<SyncTask> createTask({
    required String name,
    required String localDir,
    required String remoteDir,
    required String fileBrowserUser,
    required int intervalMinutes,
    bool enabled = true,
  }) async {
    final task = SyncTask(
      id: const Uuid().v4(),
      name: name,
      localDir: localDir,
      remoteDir: remoteDir,
      fileBrowserUser: fileBrowserUser,
      intervalMinutes: intervalMinutes,
      enabled: enabled,
      status: SyncStatus.idle,
    );

    final config = await _getConfig();
    final newConfig = config.addTask(task);
    await _saveConfig(newConfig);

    return task;
  }

  /// 更新任务
  Future<void> updateTask(String taskId, SyncTask updatedTask) async {
    final config = await _getConfig();

    // 检查任务是否存在
    final existingTask = config.findTaskById(taskId);
    if (existingTask == null) {
      throw TaskManagerException('任务不存在: $taskId');
    }

    final newConfig = config.updateTask(taskId, updatedTask);
    await _saveConfig(newConfig);
  }

  /// 删除任务
  Future<void> deleteTask(String taskId) async {
    final config = await _getConfig();

    // 检查任务是否存在
    final existingTask = config.findTaskById(taskId);
    if (existingTask == null) {
      throw TaskManagerException('任务不存在: $taskId');
    }

    final newConfig = config.removeTask(taskId);
    await _saveConfig(newConfig);
  }

  /// 启用/禁用任务
  Future<void> toggleTask(String taskId, bool enabled) async {
    final config = await _getConfig();

    // 检查任务是否存在
    final existingTask = config.findTaskById(taskId);
    if (existingTask == null) {
      throw TaskManagerException('任务不存在: $taskId');
    }

    final newConfig = config.toggleTask(taskId, enabled);
    await _saveConfig(newConfig);
  }

  /// 根据 ID 查找任务
  Future<SyncTask?> findTaskById(String taskId) async {
    final config = await _getConfig();
    return config.findTaskById(taskId);
  }

  /// 更新任务状态
  Future<void> updateTaskStatus(String taskId, SyncStatus status) async {
    final config = await _getConfig();
    final task = config.findTaskById(taskId);
    if (task == null) {
      throw TaskManagerException('任务不存在: $taskId');
    }

    final updatedTask = task.copyWith(status: status);
    final newConfig = config.updateTask(taskId, updatedTask);
    await _saveConfig(newConfig);
  }

  /// 更新任务的最后同步时间
  Future<void> updateLastSyncTime(String taskId, DateTime time) async {
    final config = await _getConfig();
    final task = config.findTaskById(taskId);
    if (task == null) {
      throw TaskManagerException('任务不存在: $taskId');
    }

    final updatedTask = task.copyWith(
      lastSyncTime: time,
      status: SyncStatus.idle,
    );
    final newConfig = config.updateTask(taskId, updatedTask);
    await _saveConfig(newConfig);
  }

  /// 获取所有启用的任务
  Future<List<SyncTask>> getEnabledTasks() async {
    final tasks = await loadTasks();
    return tasks.where((task) => task.enabled).toList();
  }

  /// 获取所有禁用的任务
  Future<List<SyncTask>> getDisabledTasks() async {
    final tasks = await loadTasks();
    return tasks.where((task) => !task.enabled).toList();
  }

  /// 检查任务名称是否已存在
  Future<bool> isTaskNameExists(String name, {String? excludeId}) async {
    final tasks = await loadTasks();
    return tasks.any((task) => task.name == name && task.id != excludeId);
  }

  /// 获取配置（带缓存）
  Future<AppConfig> _getConfig() async {
    if (_cachedConfig != null) {
      return _cachedConfig!;
    }

    _cachedConfig = await _storage.loadConfig();

    // 如果配置不存在，创建默认配置
    if (_cachedConfig == null) {
      throw TaskManagerException('配置文件不存在，请先创建服务器配置');
    }

    return _cachedConfig!;
  }

  /// 保存配置并更新缓存
  Future<void> _saveConfig(AppConfig config) async {
    await _storage.saveConfig(config);
    _cachedConfig = config;
  }

  /// 清除缓存（用于测试或强制重新加载）
  void clearCache() {
    _cachedConfig = null;
  }

  /// 导出任务到 JSON
  Future<Map<String, dynamic>> exportTask(String taskId) async {
    final task = await findTaskById(taskId);
    if (task == null) {
      throw TaskManagerException('任务不存在: $taskId');
    }
    return task.toJson();
  }

  /// 从 JSON 导入任务
  Future<SyncTask> importTask(Map<String, dynamic> json) async {
    final task = SyncTask.fromJson(json);

    // 重新生成 UUID（避免 ID 冲突）
    final newTask = task.copyWith(id: const Uuid().v4());

    final config = await _getConfig();
    final newConfig = config.addTask(newTask);
    await _saveConfig(newConfig);

    return newTask;
  }

  /// 批量创建任务
  Future<List<SyncTask>> createTasks(List<SyncTask> tasks) async {
    var config = await _getConfig();

    for (var task in tasks) {
      config = config.addTask(task);
    }

    await _saveConfig(config);
    return tasks;
  }

  /// 批量删除任务
  Future<void> deleteTasks(List<String> taskIds) async {
    var config = await _getConfig();

    for (var taskId in taskIds) {
      config = config.removeTask(taskId);
    }

    await _saveConfig(config);
  }

  /// 获取任务统计信息
  Future<TaskStatistics> getStatistics() async {
    final tasks = await loadTasks();

    return TaskStatistics(
      totalCount: tasks.length,
      enabledCount: tasks.where((t) => t.enabled).length,
      disabledCount: tasks.where((t) => !t.enabled).length,
      syncingCount: tasks.where((t) => t.status == SyncStatus.syncing).length,
      errorCount: tasks.where((t) => t.status == SyncStatus.error).length,
    );
  }
}

/// 任务统计信息
class TaskStatistics {
  final int totalCount;
  final int enabledCount;
  final int disabledCount;
  final int syncingCount;
  final int errorCount;

  const TaskStatistics({
    required this.totalCount,
    required this.enabledCount,
    required this.disabledCount,
    required this.syncingCount,
    required this.errorCount,
  });

  @override
  String toString() {
    return 'TaskStatistics(total: $totalCount, enabled: $enabledCount, syncing: $syncingCount, error: $errorCount)';
  }
}

/// 任务管理异常
class TaskManagerException implements Exception {
  final String message;

  const TaskManagerException(this.message);

  @override
  String toString() => 'TaskManagerException: $message';
}
