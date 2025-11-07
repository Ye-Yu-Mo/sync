import 'dart:async';
import 'package:workmanager/workmanager.dart';
import '../../models/models.dart';
import '../storage/storage_service.dart';
import '../sync_engine.dart';
import '../transport/transport.dart';

/// 后台调度服务
class SchedulerService {
  static const String _taskPrefix = 'sync_task_';

  /// 初始化 WorkManager
  static Future<void> initialize() async {
    await Workmanager().initialize(
      backgroundSyncCallback,
    );
  }

  /// 注册后台任务（Task 8.1）
  Future<void> scheduleTask(String taskId, int intervalMinutes) async {
    final uniqueName = _getUniqueName(taskId);

    try {
      // 取消旧任务（如果存在）
      await Workmanager().cancelByUniqueName(uniqueName);

      // 注册新的周期性任务
      await Workmanager().registerPeriodicTask(
        uniqueName,
        uniqueName,
        frequency: Duration(minutes: intervalMinutes),
        constraints: Constraints(
          networkType: NetworkType.connected, // 需要网络连接
        ),
        inputData: {
          'taskId': taskId,
        },
      );
    } catch (e) {
      throw SchedulerException('注册后台任务失败: $e');
    }
  }

  /// 取消后台任务（Task 8.1）
  Future<void> cancelTask(String taskId) async {
    final uniqueName = _getUniqueName(taskId);

    try {
      await Workmanager().cancelByUniqueName(uniqueName);
    } catch (e) {
      throw SchedulerException('取消后台任务失败: $e');
    }
  }

  /// 取消所有后台任务
  Future<void> cancelAllTasks() async {
    try {
      await Workmanager().cancelAll();
    } catch (e) {
      throw SchedulerException('取消所有后台任务失败: $e');
    }
  }

  /// 批量注册任务
  Future<void> scheduleAllEnabledTasks(List<SyncTask> tasks) async {
    for (var task in tasks) {
      if (task.enabled) {
        await scheduleTask(task.id, task.intervalMinutes);
      }
    }
  }

  /// 批量取消任务
  Future<void> cancelTasks(List<String> taskIds) async {
    for (var taskId in taskIds) {
      await cancelTask(taskId);
    }
  }

  /// 获取唯一任务名称
  String _getUniqueName(String taskId) {
    return '$_taskPrefix$taskId';
  }
}

/// 后台同步回调函数（Task 8.2）
/// 注意：这是 WorkManager 的入口点，必须是顶层函数
@pragma('vm:entry-point')
void backgroundSyncCallback() {
  Workmanager().executeTask((task, inputData) async {
    try {
      // 获取任务 ID
      final taskId = inputData?['taskId'] as String?;
      if (taskId == null) {
        return Future.value(false);
      }

      // 加载配置
      final storage = StorageService();
      final config = await storage.loadConfig();
      if (config == null) {
        return Future.value(false);
      }

      // 查找任务
      final syncTask = config.findTaskById(taskId);
      if (syncTask == null || !syncTask.enabled) {
        return Future.value(false);
      }

      // 执行同步
      final client = ResilientSftpClient();
      final engine = SyncEngine(client);

      try {
        // 连接到服务器
        await client.connect(
          host: config.server.host,
          port: config.server.port,
          username: config.server.username,
          password: config.server.password,
        );

        // 计算远程完整路径：/data/<fileBrowserUser>/<remoteDir>
        final remoteFullPath = _joinRemotePath(
          '/data/${syncTask.fileBrowserUser}',
          syncTask.remoteDir,
        );

        // 执行同步
        final result = await engine.performFullSync(
          localDir: syncTask.localDir,
          remoteDir: remoteFullPath,
          lastSyncTime: syncTask.lastSyncTime,
          autoDelete: false, // 后台不自动删除
        );

        // 断开连接
        await client.disconnect();

        // 显示通知
        await _showNotification(
          taskName: syncTask.name,
          result: result,
        );

        // 更新最后同步时间（如果成功）
        if (result.isSuccess) {
          // 注意：这里需要重新加载配置，因为可能被其他进程修改
          final updatedConfig = await storage.loadConfig();
          if (updatedConfig != null) {
            final updatedTask = syncTask.copyWith(
              lastSyncTime: DateTime.now(),
              status: SyncStatus.idle,
            );
            final newConfig = updatedConfig.updateTask(taskId, updatedTask);
            await storage.saveConfig(newConfig);
          }
        }

        return Future.value(true);
      } finally {
        await client.disconnect();
      }
    } catch (e) {
      // 后台任务失败，记录错误
      // TODO: 使用日志系统记录错误
      return Future.value(false);
    }
  });
}

/// 显示同步完成通知
Future<void> _showNotification({
  required String taskName,
  required SyncResult result,
}) async {
  // TODO: 使用 flutter_local_notifications 显示系统通知
  // 占位实现 - 未来将使用 flutter_local_notifications
  // final message = result.isSuccess
  //     ? '成功：${result.summary}'
  //     : '失败：${result.errors.first}';
}

/// 拼接远程路径
String _joinRemotePath(String base, String relative) {
  final trimmedBase = base.endsWith('/') ? base.substring(0, base.length - 1) : base;
  final trimmedRelative = relative.startsWith('/') ? relative.substring(1) : relative;

  if (trimmedRelative.isEmpty) {
    return trimmedBase;
  }

  return '$trimmedBase/$trimmedRelative';
}

/// 调度器异常
class SchedulerException implements Exception {
  final String message;

  const SchedulerException(this.message);

  @override
  String toString() => 'SchedulerException: $message';
}
