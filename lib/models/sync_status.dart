/// 同步任务状态
enum SyncStatus {
  /// 空闲状态
  idle,

  /// 同步中
  syncing,

  /// 错误状态
  error,
}

/// 同步状态扩展方法
extension SyncStatusExtension on SyncStatus {
  /// 转换为 JSON 字符串
  String toJson() => name;

  /// 从 JSON 字符串解析
  static SyncStatus fromJson(String json) {
    return SyncStatus.values.firstWhere(
      (e) => e.name == json,
      orElse: () => SyncStatus.idle,
    );
  }

  /// 获取中文描述
  String get description {
    switch (this) {
      case SyncStatus.idle:
        return '空闲';
      case SyncStatus.syncing:
        return '同步中';
      case SyncStatus.error:
        return '错误';
    }
  }
}
