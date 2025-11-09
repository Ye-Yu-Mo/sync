import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:workmanager/workmanager.dart';
import '../../models/models.dart';
import '../security_scoped_bookmark.dart';
import '../storage/storage_service.dart';
import '../sync_engine.dart';
import '../transport/transport.dart';
import '../../utils/remote_path.dart';

/// 后台调度服务
class SchedulerService {
  static const String _taskPrefix = 'sync_task_';
  static final bool _workmanagerSupported =
      Platform.isAndroid || Platform.isIOS;
  static final _DesktopScheduler _desktopScheduler = _DesktopScheduler();

  /// 初始化 WorkManager
  static Future<void> initialize() async {
    if (_workmanagerSupported) {
      await Workmanager().initialize(
        backgroundSyncCallback,
      );
    } else {
      _desktopScheduler.start();
    }
  }

  /// 注册后台任务（Task 8.1）
  Future<void> scheduleTask(String taskId, int intervalMinutes) async {
    if (!_workmanagerSupported) {
      _desktopScheduler.scheduleTask(taskId, intervalMinutes);
      return;
    }

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
    if (!_workmanagerSupported) {
      _desktopScheduler.cancelTask(taskId);
      return;
    }

    final uniqueName = _getUniqueName(taskId);

    try {
      await Workmanager().cancelByUniqueName(uniqueName);
    } catch (e) {
      throw SchedulerException('取消后台任务失败: $e');
    }
  }

  /// 取消所有后台任务
  Future<void> cancelAllTasks() async {
    if (!_workmanagerSupported) {
      _desktopScheduler.cancelAll();
      return;
    }

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
    final taskId = inputData?['taskId'] as String?;
    if (taskId == null) {
      return Future.value(false);
    }

    return _performSyncTask(taskId);
  });
}

Future<bool> _performSyncTask(String taskId) async {
  SecurityScopedBookmarkSession? bookmarkSession;
  try {
    final storage = StorageService();
    final config = await storage.loadConfig();
    if (config == null) {
      return false;
    }

    final syncTask = config.findTaskById(taskId);
    if (syncTask == null || !syncTask.enabled) {
      return false;
    }

    if (Platform.isMacOS && syncTask.localBookmark == null) {
      debugPrint(
        '[Scheduler] 跳过任务 ${syncTask.id}，需要重新授权本地目录访问。',
      );
      return false;
    }

    bookmarkSession = await MacOSSecurityScopedBookmark.startAccess(
      syncTask.localBookmark,
    );

    final client = ResilientSftpClient();
    final engine = SyncEngine(client);

    try {
      await client.connect(
        host: config.server.host,
        port: config.server.port,
        username: config.server.username,
        password: config.server.password,
      );

      final remoteFullPath = buildRemoteTaskPath(config.server, syncTask);

      final result = await engine.performFullSync(
        localDir: syncTask.localDir,
        remoteDir: remoteFullPath,
        lastSyncTime: syncTask.lastSyncTime,
        autoDelete: false,
      );

      await _showNotification(
        taskName: syncTask.name,
        result: result,
      );

      if (result.isSuccess) {
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

      return true;
    } finally {
      await client.disconnect();
    }
  } catch (e, stack) {
    debugPrint('[Scheduler] 后台同步失败: $e\n$stack');
    return false;
  } finally {
    await MacOSSecurityScopedBookmark.stopAccess(bookmarkSession);
  }
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

/// 调度器异常
class SchedulerException implements Exception {
  final String message;

  const SchedulerException(this.message);

  @override
  String toString() => 'SchedulerException: $message';
}

class _DesktopScheduler {
  final Map<String, Timer> _timers = {};
  bool _started = false;

  void start() {
    _started = true;
  }

  void scheduleTask(String taskId, int intervalMinutes) {
    if (!_started) return;
    cancelTask(taskId);
    final timer = Timer.periodic(Duration(minutes: intervalMinutes), (_) {
      unawaited(_performSyncTask(taskId));
    });
    _timers[taskId] = timer;
  }

  void cancelTask(String taskId) {
    _timers.remove(taskId)?.cancel();
  }

  void cancelAll() {
    for (final timer in _timers.values) {
      timer.cancel();
    }
    _timers.clear();
  }
}
