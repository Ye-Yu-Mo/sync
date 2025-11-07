/// 同步错误类型
enum SyncErrorType {
  /// 网络连接失败
  networkError,

  /// SSH 认证失败
  authError,

  /// 文件权限错误
  permissionError,

  /// 远程磁盘已满
  diskFullError,

  /// 文件不存在
  fileNotFound,

  /// 未知错误
  unknown,
}

/// 同步错误类型扩展方法
extension SyncErrorTypeExtension on SyncErrorType {
  /// 转换为 JSON 字符串
  String toJson() => name;

  /// 从 JSON 字符串解析
  static SyncErrorType fromJson(String json) {
    return SyncErrorType.values.firstWhere(
      (e) => e.name == json,
      orElse: () => SyncErrorType.unknown,
    );
  }

  /// 获取用户友好的错误提示
  String get userMessage {
    switch (this) {
      case SyncErrorType.networkError:
        return '网络连接失败，请检查 VPN 或网络状态';
      case SyncErrorType.authError:
        return 'SSH 认证失败，请检查用户名和密码';
      case SyncErrorType.permissionError:
        return '文件权限错误，请检查文件访问权限';
      case SyncErrorType.diskFullError:
        return '远程磁盘空间不足，请清理文件后重试';
      case SyncErrorType.fileNotFound:
        return '文件不存在或已被删除';
      case SyncErrorType.unknown:
        return '未知错误，请查看日志了解详情';
    }
  }
}
