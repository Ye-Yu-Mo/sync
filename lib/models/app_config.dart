import 'server_config.dart';
import 'sync_task.dart';

/// 应用配置文件（~/.sftp_sync/app.json）
class AppConfig {
  /// 服务器配置
  final ServerConfig server;

  /// 同步任务列表
  final List<SyncTask> tasks;

  const AppConfig({
    required this.server,
    required this.tasks,
  });

  /// 创建空配置
  factory AppConfig.empty({
    required ServerConfig server,
  }) {
    return AppConfig(
      server: server,
      tasks: const [],
    );
  }

  /// 从 JSON 创建
  factory AppConfig.fromJson(Map<String, dynamic> json) {
    return AppConfig(
      server: ServerConfig.fromJson(json['server'] as Map<String, dynamic>),
      tasks: (json['tasks'] as List<dynamic>?)
              ?.map((e) => SyncTask.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }

  /// 转换为 JSON
  Map<String, dynamic> toJson() {
    return {
      'server': server.toJson(),
      'tasks': tasks.map((e) => e.toJson()).toList(),
    };
  }

  /// 复制并修改部分字段
  AppConfig copyWith({
    ServerConfig? server,
    List<SyncTask>? tasks,
  }) {
    return AppConfig(
      server: server ?? this.server,
      tasks: tasks ?? this.tasks,
    );
  }

  /// 根据 ID 查找任务
  SyncTask? findTaskById(String id) {
    try {
      return tasks.firstWhere((task) => task.id == id);
    } catch (_) {
      return null;
    }
  }

  /// 添加任务
  AppConfig addTask(SyncTask task) {
    return copyWith(tasks: [...tasks, task]);
  }

  /// 更新任务
  AppConfig updateTask(String id, SyncTask updatedTask) {
    final newTasks = tasks.map((task) {
      return task.id == id ? updatedTask : task;
    }).toList();
    return copyWith(tasks: newTasks);
  }

  /// 删除任务
  AppConfig removeTask(String id) {
    final newTasks = tasks.where((task) => task.id != id).toList();
    return copyWith(tasks: newTasks);
  }

  /// 切换任务启用状态
  AppConfig toggleTask(String id, bool enabled) {
    final task = findTaskById(id);
    if (task == null) return this;
    return updateTask(id, task.copyWith(enabled: enabled));
  }

  @override
  String toString() {
    return 'AppConfig(server: ${server.host}, tasks: ${tasks.length})';
  }
}
