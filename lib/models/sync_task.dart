import 'sync_status.dart';

/// 同步任务
class SyncTask {
  /// 任务 ID（UUID）
  final String id;

  /// 用户自定义任务名
  final String name;

  /// 本地目录绝对路径
  final String localDir;

  /// 远程目录（相对于 /data/\<fileBrowserUser\> 的路径）
  final String remoteDir;

  /// FileBrowser 用户名（yachen/xulei）
  final String fileBrowserUser;

  /// 同步间隔（分钟）
  final int intervalMinutes;

  /// 是否启用
  final bool enabled;

  /// 上次同步时间
  final DateTime? lastSyncTime;

  /// 任务状态
  final SyncStatus status;

  const SyncTask({
    required this.id,
    required this.name,
    required this.localDir,
    required this.remoteDir,
    required this.fileBrowserUser,
    required this.intervalMinutes,
    this.enabled = true,
    this.lastSyncTime,
    this.status = SyncStatus.idle,
  });

  /// 从 JSON 创建
  factory SyncTask.fromJson(Map<String, dynamic> json) {
    return SyncTask(
      id: json['id'] as String,
      name: json['name'] as String,
      localDir: json['localDir'] as String,
      remoteDir: json['remoteDir'] as String,
      fileBrowserUser: json['fileBrowserUser'] as String? ?? 'yachen', // 默认 yachen
      intervalMinutes: json['intervalMinutes'] as int,
      enabled: json['enabled'] as bool? ?? true,
      lastSyncTime: json['lastSyncTime'] != null
          ? DateTime.parse(json['lastSyncTime'] as String)
          : null,
      status: json['status'] != null
          ? SyncStatusExtension.fromJson(json['status'] as String)
          : SyncStatus.idle,
    );
  }

  /// 转换为 JSON
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'localDir': localDir,
      'remoteDir': remoteDir,
      'fileBrowserUser': fileBrowserUser,
      'intervalMinutes': intervalMinutes,
      'enabled': enabled,
      if (lastSyncTime != null) 'lastSyncTime': lastSyncTime!.toIso8601String(),
      'status': status.toJson(),
    };
  }

  /// 复制并修改部分字段
  SyncTask copyWith({
    String? id,
    String? name,
    String? localDir,
    String? remoteDir,
    String? fileBrowserUser,
    int? intervalMinutes,
    bool? enabled,
    DateTime? lastSyncTime,
    SyncStatus? status,
  }) {
    return SyncTask(
      id: id ?? this.id,
      name: name ?? this.name,
      localDir: localDir ?? this.localDir,
      remoteDir: remoteDir ?? this.remoteDir,
      fileBrowserUser: fileBrowserUser ?? this.fileBrowserUser,
      intervalMinutes: intervalMinutes ?? this.intervalMinutes,
      enabled: enabled ?? this.enabled,
      lastSyncTime: lastSyncTime ?? this.lastSyncTime,
      status: status ?? this.status,
    );
  }

  /// 获取状态描述文本
  String get statusText {
    if (status == SyncStatus.syncing) {
      return '同步中...';
    } else if (status == SyncStatus.error) {
      return '同步失败';
    } else if (lastSyncTime != null) {
      final diff = DateTime.now().difference(lastSyncTime!);
      if (diff.inMinutes < 1) {
        return '刚刚同步';
      } else if (diff.inHours < 1) {
        return '${diff.inMinutes} 分钟前';
      } else if (diff.inDays < 1) {
        return '${diff.inHours} 小时前';
      } else {
        return '${diff.inDays} 天前';
      }
    } else {
      return '从未同步';
    }
  }

  @override
  String toString() {
    return 'SyncTask(id: $id, name: $name, status: ${status.description})';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is SyncTask && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;
}
